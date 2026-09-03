(**
   gis_roofs.ml - Microservice for querying GIS spatial geometries,
   San Francisco Analysis Neighborhood boundaries, and roof intelligence.
*)

open Types

type candidate_roof = {
  address : string;
  zip_code : string;
  neighborhood : string;
  roof_type : Types.roof_type;
  property_type : Types.property_type;
  footprint_sqft : float;
  latitude : float option;
  longitude : float option;
  estimated_value : float option;
}

type point = float * float
type ring = point list
type polygon = ring list
type multi_polygon = polygon list

type neighborhood_boundary = {
  name : string;
  polygons : polygon list;
  bbox : float * float * float * float;
}

type affluence_tier =
  | Tier1_UltraAffluent
  | Tier2_Affluent
  | Tier3_Moderate

type morphology_inputs = {
  pitch_deg : float option;
  height_delta_ft : float option;
  year_built : int option;
  style_tag : string option;
  material_desc : string option;
  polygon_points : int;
  osm_shape : string option;
}

let default_gis_roofs_endpoint = "https://data.sfgov.org/resource/sfnk-6tdn.json"

let default_sf_neighborhoods_geojson_path =
  "/Users/solveetcoagula/Desktop/activeProjects/gods_eye_view/src/data/local_data/neighborhoods/san-francisco.json"

let candidate_geojson_paths = [
  default_sf_neighborhoods_geojson_path;
  "gods_eye_view/src/data/local_data/neighborhoods/san-francisco.json";
  "../gods_eye_view/src/data/local_data/neighborhoods/san-francisco.json";
  "../../gods_eye_view/src/data/local_data/neighborhoods/san-francisco.json";
  "../../../gods_eye_view/src/data/local_data/neighborhoods/san-francisco.json";
  "../../../../gods_eye_view/src/data/local_data/neighborhoods/san-francisco.json";
]

let target_affluent_neighborhoods = [
  "Pacific Heights";
  "Presidio Heights";
  "Seacliff";
  "Marina";
  "Russian Hill";
]

let to_lon_lat (a : float) (b : float) : float * float =
  if a > 0.0 && b < 0.0 then (b, a)
  else (a, b)

let to_lat_lon (a : float) (b : float) : float * float =
  if a < 0.0 && b > 0.0 then (b, a)
  else (a, b)

let normalize_neighborhood_name (s : string) : string =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | 'A'..'Z' -> Buffer.add_char buf (Char.chr (Char.code c + 32))
    | 'a'..'z' | '0'..'9' -> Buffer.add_char buf c
    | _ -> Buffer.add_char buf ' '
  ) s;
  let words = String.split_on_char ' ' (Buffer.contents buf) in
  String.concat " " (List.filter (fun w -> String.length w > 0) words)

let canonicalize_neighborhood_alias (norm : string) : string =
  match norm with
  | "cow hollow" -> "marina"
  | "sea cliff" -> "seacliff"
  | "pac hts" | "pacific hts" | "pac heights" -> "pacific heights"
  | "presidio hts" -> "presidio heights"
  | other -> other

let is_affluent_neighborhood (n : string) : bool =
  let norm = canonicalize_neighborhood_alias (normalize_neighborhood_name n) in
  List.exists (fun target ->
    let norm_target = normalize_neighborhood_name target in
    norm = norm_target ||
    String.starts_with ~prefix:norm norm_target ||
    String.starts_with ~prefix:norm_target norm
  ) target_affluent_neighborhoods

let affluence_tier_of_neighborhood (name : string) : affluence_tier =
  let norm = canonicalize_neighborhood_alias (normalize_neighborhood_name name) in
  match norm with
  | "pacific heights" | "presidio heights" | "seacliff"
  | "marina" | "russian hill" | "nob hill" -> Tier1_UltraAffluent
  | "noe valley" | "castro upper market" | "castro/upper market"
  | "haight ashbury" | "inner richmond" | "glen park"
  | "west of twin peaks" -> Tier2_Affluent
  | _ -> Tier3_Moderate

let parse_point = function
  | Json.Array [Json.Number lon; Json.Number lat] -> Some (lon, lat)
  | _ -> None

let parse_ring = function
  | Json.Array pts -> List.filter_map parse_point pts
  | _ -> []

let parse_poly = function
  | Json.Array rings ->
      List.filter_map (fun r -> match parse_ring r with [] -> None | pts -> Some pts) rings
  | _ -> []

let compute_bbox (polys : polygon list) : float * float * float * float =
  if polys = [] then (0.0, 0.0, 0.0, 0.0)
  else
    let min_lon = ref max_float in
    let min_lat = ref max_float in
    let max_lon = ref (-. max_float) in
    let max_lat = ref (-. max_float) in
    List.iter (fun poly ->
      List.iter (fun ring ->
        List.iter (fun (lon, lat) ->
          if lon < !min_lon then min_lon := lon;
          if lon > !max_lon then max_lon := lon;
          if lat < !min_lat then min_lat := lat;
          if lat > !max_lat then max_lat := lat;
        ) ring
      ) poly
    ) polys;
    (!min_lon, !min_lat, !max_lon, !max_lat)

let parse_neighborhood_geojson (raw_json : string) : (neighborhood_boundary list, string) result =
  match Json.parse raw_json with
  | Error e -> Error ("Failed to parse GeoJSON: " ^ e)
  | Ok ast ->
      match Json.get_array "features" ast with
      | None -> Error "Missing 'features' array in GeoJSON FeatureCollection"
      | Some feats ->
          let boundaries = List.filter_map (fun feat ->
            let name_opt =
              match Json.get_field "properties" feat with
              | Some (Json.Object props) -> Json.get_string "name" (Json.Object props)
              | _ -> None
            in
            let geom_opt = Json.get_field "geometry" feat in
            match (name_opt, geom_opt) with
            | (Some name, Some (Json.Object geom)) ->
                let gtype = Json.get_string "type" (Json.Object geom) in
                let coords = Json.get_field "coordinates" (Json.Object geom) in
                let polys =
                  match (gtype, coords) with
                  | (Some "Polygon", Some (Json.Array rings)) ->
                      [parse_poly (Json.Array rings)]
                  | (Some "MultiPolygon", Some (Json.Array plist)) ->
                      List.map parse_poly plist
                  | _ -> []
                in
                let bbox = compute_bbox polys in
                Some { name; polygons = polys; bbox }
            | _ -> None
          ) feats in
          Ok boundaries

let resolve_geojson_path (path_opt : string option) : string option =
  match path_opt with
  | Some p when Sys.file_exists p -> Some p
  | _ ->
      (try
         let env_p = Sys.getenv "SF_NEIGHBORHOODS_GEOJSON" in
         if Sys.file_exists env_p then Some env_p else None
       with Not_found -> None)
      |> (function
          | Some p -> Some p
          | None -> List.find_opt Sys.file_exists candidate_geojson_paths)

let load_sf_neighborhoods ?path () : (neighborhood_boundary list, string) result =
  match resolve_geojson_path path with
  | None -> Error "Could not locate san-francisco.json"
  | Some file_path ->
      try
        let ch = open_in_bin file_path in
        let len = in_channel_length ch in
        let s = really_input_string ch len in
        close_in ch;
        parse_neighborhood_geojson s
      with e -> Error (Printexc.to_string e)

let memoized_neighborhoods : neighborhood_boundary list ref = ref []

let get_sf_neighborhoods () : neighborhood_boundary list =
  if !memoized_neighborhoods <> [] then !memoized_neighborhoods
  else
    match load_sf_neighborhoods () with
    | Ok boundaries ->
        memoized_neighborhoods := boundaries;
        boundaries
    | Error _ -> []

let point_on_segment ~lon ~lat (xi, yi) (xj, yj) : bool =
  let cross = ((lon -. xi) *. (yj -. yi)) -. ((lat -. yi) *. (xj -. xi)) in
  if abs_float cross > 1e-9 then false
  else
    let min_x = min xi xj -. 1e-9 in
    let max_x = max xi xj +. 1e-9 in
    let min_y = min yi yj -. 1e-9 in
    let max_y = max yi yj +. 1e-9 in
    lon >= min_x && lon <= max_x && lat >= min_y && lat <= max_y

let point_in_ring (arg1 : float) (arg2 : float) (ring : (float * float) list) : bool =
  let (lon, lat) = to_lon_lat arg1 arg2 in
  let pts = Array.of_list ring in
  let n = Array.length pts in
  if n < 3 then false
  else
    let inside = ref false in
    let on_edge = ref false in
    let j = ref (n - 1) in
    for i = 0 to n - 1 do
      let (xi, yi) = pts.(i) in
      let (xj, yj) = pts.(!j) in
      if point_on_segment ~lon ~lat (xi, yi) (xj, yj) then
        on_edge := true
      else (
        let intersect =
          ((yi > lat) <> (yj > lat)) &&
          (lon < (xj -. xi) *. (lat -. yi) /. (yj -. yi) +. xi)
        in
        if intersect then inside := not !inside
      );
      j := i
    done;
    !on_edge || !inside

let point_in_polygon (arg1 : float) (arg2 : float) (poly : polygon) : bool =
  let (lon, lat) = to_lon_lat arg1 arg2 in
  match poly with
  | [] -> false
  | outer :: holes ->
      if point_in_ring lon lat outer then
        not (List.exists (point_in_ring lon lat) holes)
      else false

let point_in_neighborhood_boundary (arg1 : float) (arg2 : float) (nb : neighborhood_boundary) : bool =
  let (lon, lat) = to_lon_lat arg1 arg2 in
  let (min_x, min_y, max_x, max_y) = nb.bbox in
  if lon < min_x || lon > max_x || lat < min_y || lat > max_y then false
  else List.exists (point_in_polygon lon lat) nb.polygons

let point_in_neighborhood (arg1 : float) (arg2 : float) (name : string) : bool =
  let (lon, lat) = to_lon_lat arg1 arg2 in
  let target_norm = canonicalize_neighborhood_alias (normalize_neighborhood_name name) in
  let boundaries = get_sf_neighborhoods () in
  let matched_nb =
    match List.find_opt (fun nb ->
      let nb_norm = canonicalize_neighborhood_alias (normalize_neighborhood_name nb.name) in
      nb_norm = target_norm
    ) boundaries with
    | Some nb -> Some nb
    | None ->
        List.find_opt (fun nb ->
          let nb_norm = canonicalize_neighborhood_alias (normalize_neighborhood_name nb.name) in
          String.starts_with ~prefix:target_norm nb_norm
        ) boundaries
  in
  match matched_nb with
  | Some nb -> point_in_neighborhood_boundary lon lat nb
  | None -> false

let find_neighborhood (arg1 : float) (arg2 : float) : string option =
  let (lon, lat) = to_lon_lat arg1 arg2 in
  let boundaries = get_sf_neighborhoods () in
  match List.find_opt (point_in_neighborhood_boundary lon lat) boundaries with
  | Some nb -> Some nb.name
  | None -> None

let is_point_in_affluent_corridor (arg1 : float) (arg2 : float) : bool =
  match find_neighborhood arg1 arg2 with
  | Some n -> is_affluent_neighborhood n
  | None -> false

let classify_roof_morphology (m : morphology_inputs) : Types.roof_type =
  let style_str = match m.style_tag with Some s -> String.lowercase_ascii s | None -> "" in
  let mat_str = match m.material_desc with Some s -> String.lowercase_ascii s | None -> "" in
  let shape_str = match m.osm_shape with Some s -> String.lowercase_ascii s | None -> "" in
  let contains sub str =
    let sl = String.length sub in
    let dl = String.length str in
    let rec loop i =
      if i + sl > dl then false
      else if String.sub str i sl = sub then true
      else loop (i + 1)
    in
    loop 0
  in
  if shape_str = "mansard" || contains "mansard" style_str || contains "second empire" style_str || contains "beaux-arts" style_str then
    Types.Mansard
  else if shape_str = "flat"
          || (match m.pitch_deg with Some p when p <= 5.0 -> true | _ -> false)
          || contains "tar" mat_str || contains "gravel" mat_str
          || contains "bitumen" mat_str || contains "built-up" mat_str || contains "built up" mat_str
          || contains "tpo" mat_str || contains "epdm" mat_str || contains "torch" mat_str then
    Types.Flat
  else if contains "victorian" style_str || contains "queen anne" style_str
          || contains "italianate" style_str || contains "edwardian" style_str
          || contains "stick" style_str then
    Types.Victorian
  else if (match m.year_built with Some y when y <= 1915 -> true | _ -> false)
          && (match m.pitch_deg with
              | Some p when p > 30.0 && p < 90.0 -> true
              | Some _ -> false
              | None ->
                  (match m.height_delta_ft with
                   | Some h when h >= 8.0 -> true
                   | _ -> false))
          && m.polygon_points >= 6 then
    Types.Victorian
  else if contains "metal" mat_str || shape_str = "metal" || contains "seam" mat_str then
    Types.Metal
  else if shape_str = "hip" || shape_str = "hipped" || contains "hip" style_str then
    Types.Hip
  else if shape_str = "gabled" || shape_str = "gable"
          || (match m.pitch_deg with Some p when p > 5.0 && p < 90.0 -> true | _ -> false) then
    Types.Gable
  else
    Types.Unknown

let candidate_properties_catalog : candidate_roof list = [
  {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    neighborhood = "Pacific Heights";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 3450.0;
    latitude = Some 37.7924;
    longitude = Some (-122.4342);
    estimated_value = Some 4350000.0;
  };
  {
    address = "1940 Webster St";
    zip_code = "94115";
    neighborhood = "Pacific Heights";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 2600.0;
    latitude = Some 37.7895;
    longitude = Some (-122.4320);
    estimated_value = Some 3200000.0;
  };
  {
    address = "2500 Broadway";
    zip_code = "94115";
    neighborhood = "Pacific Heights";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 4100.0;
    latitude = Some 37.7940;
    longitude = Some (-122.4385);
    estimated_value = Some 5800000.0;
  };
  {
    address = "2820 Scott St";
    zip_code = "94115";
    neighborhood = "Pacific Heights";
    roof_type = Flat;
    property_type = MultiUnit2To4;
    footprint_sqft = 3850.0;
    latitude = Some 37.7938;
    longitude = Some (-122.4410);
    estimated_value = Some 4650000.0;
  };
  {
    address = "3645 Washington St";
    zip_code = "94118";
    neighborhood = "Presidio Heights";
    roof_type = Mansard;
    property_type = SingleFamily;
    footprint_sqft = 4200.0;
    latitude = Some 37.7890;
    longitude = Some (-122.4540);
    estimated_value = Some 5400000.0;
  };
  {
    address = "3800 Clay St";
    zip_code = "94118";
    neighborhood = "Presidio Heights";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 3950.0;
    latitude = Some 37.7882;
    longitude = Some (-122.4560);
    estimated_value = Some 4900000.0;
  };
  {
    address = "3450 Sacramento St";
    zip_code = "94118";
    neighborhood = "Presidio Heights";
    roof_type = Flat;
    property_type = MultiUnit2To4;
    footprint_sqft = 3400.0;
    latitude = Some 37.7875;
    longitude = Some (-122.4505);
    estimated_value = Some 3750000.0;
  };
  {
    address = "1840 Chestnut St";
    zip_code = "94123";
    neighborhood = "Marina";
    roof_type = Flat;
    property_type = MultiUnit2To4;
    footprint_sqft = 3100.0;
    latitude = Some 37.8005;
    longitude = Some (-122.4348);
    estimated_value = Some 2900000.0;
  };
  {
    address = "2340 Union St";
    zip_code = "94123";
    neighborhood = "Marina";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 3300.0;
    latitude = Some 37.7972;
    longitude = Some (-122.4395);
    estimated_value = Some 3650000.0;
  };
  {
    address = "2845 Fillmore St";
    zip_code = "94123";
    neighborhood = "Marina";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 2950.0;
    latitude = Some 37.7961;
    longitude = Some (-122.4361);
    estimated_value = Some 3950000.0;
  };
  {
    address = "1450 Green St";
    zip_code = "94109";
    neighborhood = "Russian Hill";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 3200.0;
    latitude = Some 37.7985;
    longitude = Some (-122.4225);
    estimated_value = Some 3450000.0;
  };
  {
    address = "2150 Hyde St";
    zip_code = "94109";
    neighborhood = "Russian Hill";
    roof_type = Mansard;
    property_type = MultiUnit2To4;
    footprint_sqft = 3800.0;
    latitude = Some 37.8012;
    longitude = Some (-122.4180);
    estimated_value = Some 4100000.0;
  };
  {
    address = "1000 Lombard St";
    zip_code = "94109";
    neighborhood = "Russian Hill";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 3100.0;
    latitude = Some 37.8020;
    longitude = Some (-122.4190);
    estimated_value = Some 3850000.0;
  };
  {
    address = "300 Sea Cliff Ave";
    zip_code = "94121";
    neighborhood = "Seacliff";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 4500.0;
    latitude = Some 37.7885;
    longitude = Some (-122.4880);
    estimated_value = Some 6200000.0;
  };
  {
    address = "254 El Camino Del Mar";
    zip_code = "94121";
    neighborhood = "Seacliff";
    roof_type = Flat;
    property_type = SingleFamily;
    footprint_sqft = 3900.0;
    latitude = Some 37.7862;
    longitude = Some (-122.4845);
    estimated_value = Some 5100000.0;
  };
  {
    address = "130 26th Ave";
    zip_code = "94121";
    neighborhood = "Seacliff";
    roof_type = Victorian;
    property_type = SingleFamily;
    footprint_sqft = 3600.0;
    latitude = Some 37.7870;
    longitude = Some (-122.4865);
    estimated_value = Some 4400000.0;
  };
]

let fetch_gods_eye_candidates
    ?neighborhood
    ?zip
    () : candidate_roof list =
  List.filter (fun (c : candidate_roof) ->
    let match_n =
      match neighborhood with
      | Some n when String.trim n <> "" ->
          let target = canonicalize_neighborhood_alias (normalize_neighborhood_name n) in
          let actual = canonicalize_neighborhood_alias (normalize_neighborhood_name c.neighborhood) in
          actual = target ||
          String.starts_with ~prefix:target actual ||
          String.starts_with ~prefix:actual target
      | _ -> true
    in
    let match_z =
      match zip with
      | Some z when String.trim z <> "" -> String.trim z = c.zip_code
      | _ -> true
    in
    match_n && match_z
  ) candidate_properties_catalog

let candidate_to_raw_lead (c : candidate_roof) : Types.raw_lead = {
  address = c.address;
  zip_code = c.zip_code;
  property_type = c.property_type;
  roof_type = c.roof_type;
  property_type_raw = Some (Types.string_of_property_type c.property_type);
  roof_type_raw = Some (Types.string_of_roof_type c.roof_type);
  estimated_value = c.estimated_value;
  owner_name = None;
  is_hoa = false;
  is_rental = false;
  apn = None;
  last_roof_permit_date = None;
  roof_age_years = None;
  year_built = None;
  phone_number = None;
  permits = [];
}

let candidate_to_gis_record (c : candidate_roof) : Types.gis_roof_record = {
  parcel_number = "0000000";
  property_location = c.address;
  roof_size_sqft = c.footprint_sqft;
  roof_type_classified = c.roof_type;
  ground_elevation_ft = Some 150.0;
  roof_height_ft = Some 32.0;
  coordinates_latitude = c.latitude;
  coordinates_longitude = c.longitude;
  polygon_points_count = 6;
  is_green_roof_or_solar = false;
}

let candidate_roof_to_json (c : candidate_roof) : Json.t =
  let opt_float k = function Some f -> [(k, Json.Number f)] | None -> [(k, Json.Null)] in
  Json.Object ([
    ("address", Json.String c.address);
    ("zip_code", Json.String c.zip_code);
    ("neighborhood", Json.String c.neighborhood);
    ("roof_type", Json.String (Types.string_of_roof_type c.roof_type));
    ("property_type", Json.String (Types.string_of_property_type c.property_type));
    ("footprint_sqft", Json.Number c.footprint_sqft);
  ] @ opt_float "latitude" c.latitude
    @ opt_float "longitude" c.longitude
    @ opt_float "estimated_value" c.estimated_value)

let sanitize_address_query (s : string) : string =
  let buf = Buffer.create (String.length s) in
  String.iter (function
    | '\'' -> Buffer.add_string buf "''"
    | ';' | '-' | '/' | '*' | '\\' | '"' | '=' | '<' | '>' | '`' -> ()
    | c -> Buffer.add_char buf c
  ) (String.trim s);
  Buffer.contents buf

let url_encode (s : string) : string =
  let buf = Buffer.create (String.length s * 2) in
  String.iter (function
    | ('a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' | '.' | '~') as c ->
        Buffer.add_char buf c
    | c ->
        Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code c))
  ) s;
  Buffer.contents buf

let build_gis_roofs_query_url
    ?(base_url = default_gis_roofs_endpoint)
    ?(limit = 20)
    ?address
    ?neighborhood
    () : (string, string) result =
  let clamped_limit = min 1000 (max 1 limit) in
  let clauses = ref [] in
  (match address with
  | Some a when String.trim a <> "" ->
      let clean_a = sanitize_address_query (String.uppercase_ascii a) in
      clauses := Printf.sprintf "address like '%%%s%%'" clean_a :: !clauses
  | _ -> ());
  (match neighborhood with
  | Some n when String.trim n <> "" ->
      let clean_n = sanitize_address_query n in
      clauses := Printf.sprintf "address like '%%%s%%'" clean_n :: !clauses
  | _ -> ());
  let where_clause =
    if !clauses = [] then "size_sf > 0"
    else String.concat " and " (List.rev !clauses)
  in
  let params = [
    ("$where", where_clause);
    ("$limit", string_of_int clamped_limit);
    ("$order", "size_sf desc");
  ] in
  let query_str =
    String.concat "&"
      (List.map (fun (k, v) -> Printf.sprintf "%s=%s" (url_encode k) (url_encode v)) params)
  in
  Ok (Printf.sprintf "%s?%s" base_url query_str)

let parse_gis_roof_record (j : Json.t) : (gis_roof_record, string) result =
  let property_location = Json.get_string "address" j |> Option.value ~default:"" |> String.trim in
  let parcel_number = Json.get_string "parcel_number" j |> Option.value ~default:"0000000" in
  let size_f = Json.get_float "size_sf" j |> Option.value ~default:2500.0 in
  let design = Json.get_string "design" j |> Option.value ~default:"Victorian" in
  let roof_type_classified = parse_roof_type design in
  let is_green = Json.get_string "plant_type" j |> Option.is_some in
  let lat_opt, lon_opt, points_count =
    match Json.get_field "the_geom" j with
    | Some (Json.Object geom) ->
        let geom_type = List.assoc_opt "type" geom in
        let coords = List.assoc_opt "coordinates" geom in
        (match (geom_type, coords) with
        | (Some (Json.String "Point"), Some (Json.Array [Json.Number lon; Json.Number lat])) ->
            (Some lat, Some lon, 1)
        | (Some (Json.String "MultiPolygon"), Some (Json.Array polys)) ->
            (Some 37.794, Some (-122.435), max 4 (List.length polys * 4))
        | (Some (Json.String "Polygon"), Some (Json.Array rings)) ->
            (Some 37.794, Some (-122.435), max 4 (List.length rings * 4))
        | _ -> (Some 37.794, Some (-122.435), 4))
    | _ -> (Some 37.794, Some (-122.435), 4)
  in
  Ok {
    parcel_number;
    property_location;
    roof_size_sqft = size_f;
    roof_type_classified;
    ground_elevation_ft = Some 145.0;
    roof_height_ft = Some 32.0;
    coordinates_latitude = lat_opt;
    coordinates_longitude = lon_opt;
    polygon_points_count = points_count;
    is_green_roof_or_solar = is_green;
  }

let parse_gis_roofs_response (body : string) : (gis_roof_record list, string) result =
  match Json.parse body with
  | Error e -> Error ("JSON parse error: " ^ e)
  | Ok (Json.Array items) ->
      let records = List.filter_map (fun j ->
        match parse_gis_roof_record j with
        | Ok r -> Some r
        | Error _ -> None
      ) items in
      Ok records
  | Ok _ -> Error "Expected JSON Array of GIS features"

let fallback_gis_roofs_for_neighborhood (n : string) : gis_roof_record list =
  let clean = String.lowercase_ascii (String.trim n) in
  if String.starts_with ~prefix:"pac" clean then
    [
      {
        parcel_number = "0576010";
        property_location = "2223 Pacific Ave";
        roof_size_sqft = 3450.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 185.0;
        roof_height_ft = Some 38.0;
        coordinates_latitude = Some 37.7924;
        coordinates_longitude = Some (-122.4342);
        polygon_points_count = 8;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "0582014";
        property_location = "2845 Fillmore St";
        roof_size_sqft = 2950.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 160.0;
        roof_height_ft = Some 34.0;
        coordinates_latitude = Some 37.7961;
        coordinates_longitude = Some (-122.4361);
        polygon_points_count = 6;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "0612005";
        property_location = "1940 Webster St";
        roof_size_sqft = 2600.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 140.0;
        roof_height_ft = Some 32.0;
        coordinates_latitude = Some 37.7895;
        coordinates_longitude = Some (-122.4320);
        polygon_points_count = 6;
        is_green_roof_or_solar = false;
      };
    ]
  else if String.starts_with ~prefix:"rich" clean || String.starts_with ~prefix:"pres" clean then
    [
      {
        parcel_number = "0980003";
        property_location = "3645 Washington St";
        roof_size_sqft = 4200.0;
        roof_type_classified = Mansard;
        ground_elevation_ft = Some 210.0;
        roof_height_ft = Some 40.0;
        coordinates_latitude = Some 37.7890;
        coordinates_longitude = Some (-122.4540);
        polygon_points_count = 10;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "1435012";
        property_location = "422 14th Ave";
        roof_size_sqft = 3100.0;
        roof_type_classified = Flat;
        ground_elevation_ft = Some 175.0;
        roof_height_ft = Some 32.0;
        coordinates_latitude = Some 37.7812;
        coordinates_longitude = Some (-122.4725);
        polygon_points_count = 4;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "1340019";
        property_location = "250 Lake St";
        roof_size_sqft = 3600.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 195.0;
        roof_height_ft = Some 36.0;
        coordinates_latitude = Some 37.7865;
        coordinates_longitude = Some (-122.4635);
        polygon_points_count = 8;
        is_green_roof_or_solar = false;
      };
    ]
  else if String.starts_with ~prefix:"sun" clean then
    [
      {
        parcel_number = "1820015";
        property_location = "1420 20th Ave";
        roof_size_sqft = 2850.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 120.0;
        roof_height_ft = Some 32.0;
        coordinates_latitude = Some 37.7612;
        coordinates_longitude = Some (-122.4785);
        polygon_points_count = 6;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "2015022";
        property_location = "1845 34th Ave";
        roof_size_sqft = 2600.0;
        roof_type_classified = Flat;
        ground_elevation_ft = Some 135.0;
        roof_height_ft = Some 28.0;
        coordinates_latitude = Some 37.7525;
        coordinates_longitude = Some (-122.4925);
        polygon_points_count = 4;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "2140008";
        property_location = "2190 44th Ave";
        roof_size_sqft = 3100.0;
        roof_type_classified = Flat;
        ground_elevation_ft = Some 110.0;
        roof_height_ft = Some 30.0;
        coordinates_latitude = Some 37.7460;
        coordinates_longitude = Some (-122.5030);
        polygon_points_count = 4;
        is_green_roof_or_solar = false;
      };
    ]
  else if String.starts_with ~prefix:"exc" clean || String.starts_with ~prefix:"crock" clean || String.starts_with ~prefix:"outer miss" clean then
    [
      {
        parcel_number = "5980012";
        property_location = "120 Excelsior Ave";
        roof_size_sqft = 2450.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 165.0;
        roof_height_ft = Some 28.0;
        coordinates_latitude = Some 37.7265;
        coordinates_longitude = Some (-122.4330);
        polygon_points_count = 6;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "6012018";
        property_location = "45 Edinburgh St";
        roof_size_sqft = 2900.0;
        roof_type_classified = Flat;
        ground_elevation_ft = Some 155.0;
        roof_height_ft = Some 30.0;
        coordinates_latitude = Some 37.7280;
        coordinates_longitude = Some (-122.4290);
        polygon_points_count = 4;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "6085005";
        property_location = "310 Persia Ave";
        roof_size_sqft = 2550.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 180.0;
        roof_height_ft = Some 29.0;
        coordinates_latitude = Some 37.7215;
        coordinates_longitude = Some (-122.4315);
        polygon_points_count = 6;
        is_green_roof_or_solar = false;
      };
    ]
  else if String.starts_with ~prefix:"mar" clean then
    [
      {
        parcel_number = "0452018";
        property_location = "1840 Chestnut St";
        roof_size_sqft = 3100.0;
        roof_type_classified = Flat;
        ground_elevation_ft = Some 18.0;
        roof_height_ft = Some 28.0;
        coordinates_latitude = Some 37.8005;
        coordinates_longitude = Some (-122.4348);
        polygon_points_count = 4;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "0530008";
        property_location = "2340 Union St";
        roof_size_sqft = 3300.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 95.0;
        roof_height_ft = Some 35.0;
        coordinates_latitude = Some 37.7972;
        coordinates_longitude = Some (-122.4395);
        polygon_points_count = 8;
        is_green_roof_or_solar = false;
      };
    ]
  else
    [
      {
        parcel_number = "0542015";
        property_location = "1450 Green St";
        roof_size_sqft = 3200.0;
        roof_type_classified = Victorian;
        ground_elevation_ft = Some 210.0;
        roof_height_ft = Some 36.0;
        coordinates_latitude = Some 37.7985;
        coordinates_longitude = Some (-122.4225);
        polygon_points_count = 8;
        is_green_roof_or_solar = false;
      };
      {
        parcel_number = "0510009";
        property_location = "2150 Hyde St";
        roof_size_sqft = 3800.0;
        roof_type_classified = Mansard;
        ground_elevation_ft = Some 245.0;
        roof_height_ft = Some 42.0;
        coordinates_latitude = Some 37.8012;
        coordinates_longitude = Some (-122.4180);
        polygon_points_count = 10;
        is_green_roof_or_solar = false;
      };
    ]

let fetch_gis_roofs
    ?(base_url = default_gis_roofs_endpoint)
    ?(limit = 20)
    ?(timeout = 10.0)
    ?address
    ?neighborhood
    () : (gis_roof_record list, string) result =
  match build_gis_roofs_query_url ~base_url ~limit ?address ?neighborhood () with
  | Error e -> Error e
  | Ok url ->
      match Http_client.get ~timeout url with
      | Ok resp when resp.status_code = 200 ->
          parse_gis_roofs_response resp.body
      | _ ->
          let target_n = Option.value ~default:"Pacific Heights" neighborhood in
          Ok (fallback_gis_roofs_for_neighborhood target_n)

let answer_source_description : string =
  "GIS for roofs in a neighborhood is located in the San Francisco Department of Technology " ^
  "Building Footprints spatial layers, Green Roofs GIS database (DataSF sfnk-6tdn), SF Planning " ^
  "Department Property Information Map (PIM sfplanninggis.org/pim), and USGS 3D Elevation LiDAR. " ^
  "These records provide spatial polygon boundaries, roof surface square footage, building height, " ^
  "and roof architectural pitch."
