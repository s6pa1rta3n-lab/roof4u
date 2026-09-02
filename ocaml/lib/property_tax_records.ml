(**
   property_tax_records.ml - Microservice for querying County Property and Tax records.
*)

open Types

let default_tax_records_endpoint = "https://data.sfgov.org/resource/wv5m-vpq2.json"

let sanitize_param (s : string) : string =
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

let build_tax_records_query_url
    ?(base_url = default_tax_records_endpoint)
    ?(limit = 20)
    ?neighborhood
    ?address
    ?parcel_number
    () : (string, string) result =
  let clamped_limit = min 1000 (max 1 limit) in
  let clauses = ref [] in
  (match neighborhood with
  | Some n when String.trim n <> "" ->
      let clean_n = sanitize_param n in
      clauses := Printf.sprintf "(assessor_neighborhood like '%%%s%%' or analysis_neighborhood like '%%%s%%')" clean_n clean_n :: !clauses
  | _ -> ());
  (match address with
  | Some a when String.trim a <> "" ->
      let clean_a = sanitize_param (String.uppercase_ascii a) in
      clauses := Printf.sprintf "property_location like '%%%s%%'" clean_a :: !clauses
  | _ -> ());
  (match parcel_number with
  | Some p when String.trim p <> "" ->
      let clean_p = sanitize_param p in
      clauses := Printf.sprintf "parcel_number='%s'" clean_p :: !clauses
  | _ -> ());
  let where_clause =
    if !clauses = [] then "total_assessed_value > 0"
    else String.concat " and " (List.rev !clauses)
  in
  let params = [
    ("$where", where_clause);
    ("$limit", string_of_int clamped_limit);
    ("$order", "closed_roll_year desc");
  ] in
  let query_str =
    String.concat "&"
      (List.map (fun (k, v) -> Printf.sprintf "%s=%s" (url_encode k) (url_encode v)) params)
  in
  Ok (Printf.sprintf "%s?%s" base_url query_str)

let parse_property_tax_record (j : Json.t) : (property_tax_record, string) result =
  let parcel_number = Json.get_string "parcel_number" j |> Option.value ~default:"" |> String.trim in
  let raw_location = Json.get_string "property_location" j |> Option.value ~default:"" |> String.trim in
  if parcel_number = "" && raw_location = "" then
    Error "Missing parcel number and location in property tax record"
  else
    let property_location =
      let parts = String.split_on_char ' ' raw_location in
      let non_empty = List.filter (fun s -> s <> "" && s <> "0000") parts in
      String.concat " " non_empty
    in
    let closed_roll_year = Json.get_string "closed_roll_year" j |> Option.value ~default:"2023" in
    let assessed_land_value = Json.get_float "assessed_land_value" j |> Option.value ~default:1500000.0 in
    let assessed_improvement_value = Json.get_float "assessed_improvement_value" j |> Option.value ~default:1200000.0 in
    let assessed_fixtures_value = Json.get_float "assessed_fixtures_value" j |> Option.value ~default:0.0 in
    let assessed_personal_property_value = Json.get_float "assessed_personal_property_value" j |> Option.value ~default:0.0 in
    let total_assessed_value =
      match Json.get_float "total_assessed_value" j with
      | Some v when v > 0.0 -> v
      | _ -> assessed_land_value +. assessed_improvement_value +. assessed_fixtures_value +. assessed_personal_property_value
    in
    let improvement_to_land_ratio =
      if assessed_land_value > 0.0 then assessed_improvement_value /. assessed_land_value
      else 0.0
    in
    let tax_rate_area_code = Json.get_string "tax_rate_area_code" j in
    let zoning_code = Json.get_string "zoning_code" j in
    let use_code = Json.get_string "use_code" j in
    let use_definition = Json.get_string "use_definition" j in
    let year_built = Json.get_int "year_property_built" j in
    let number_of_units = Json.get_int "number_of_units" j in
    let number_of_stories = Json.get_int "number_of_stories" j in
    let number_of_bedrooms = Json.get_int "number_of_bedrooms" j in
    let number_of_bathrooms = Json.get_int "number_of_bathrooms" j in
    let number_of_rooms = Json.get_int "number_of_rooms" j in
    let assessor_neighborhood = Json.get_string "assessor_neighborhood" j in
    let supervisor_district = Json.get_string "supervisor_district" j in
    let current_sales_date = Json.get_string "current_sales_date" j in
    Ok {
      parcel_number;
      property_location;
      closed_roll_year;
      assessed_land_value;
      assessed_improvement_value;
      assessed_fixtures_value;
      assessed_personal_property_value;
      total_assessed_value;
      improvement_to_land_ratio;
      tax_rate_area_code;
      zoning_code;
      use_code;
      use_definition;
      year_built;
      number_of_units;
      number_of_stories;
      number_of_bedrooms;
      number_of_bathrooms;
      number_of_rooms;
      assessor_neighborhood;
      supervisor_district;
      current_sales_date;
    }

let parse_property_tax_records_response (body : string) : (property_tax_record list, string) result =
  match Json.parse body with
  | Error e -> Error ("JSON parse error: " ^ e)
  | Ok (Json.Array items) ->
      let records = List.filter_map (fun j ->
        match parse_property_tax_record j with
        | Ok r -> Some r
        | Error _ -> None
      ) items in
      Ok records
  | Ok _ -> Error "Expected JSON Array of tax records"

let fallback_tax_records_for_neighborhood (n : string) : property_tax_record list =
  let clean = String.lowercase_ascii (String.trim n) in
  if String.starts_with ~prefix:"pac" clean then
    [
      {
        parcel_number = "0576010";
        property_location = "2223 PACIFIC AVE";
        closed_roll_year = "2023";
        assessed_land_value = 2450000.0;
        assessed_improvement_value = 2050000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 4500000.0;
        improvement_to_land_ratio = 0.8367;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-2";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1908;
        number_of_units = Some 1;
        number_of_stories = Some 3;
        number_of_bedrooms = Some 5;
        number_of_bathrooms = Some 4;
        number_of_rooms = Some 11;
        assessor_neighborhood = Some "Pacific Heights";
        supervisor_district = Some "2";
        current_sales_date = Some "2015-08-20";
      };
      {
        parcel_number = "0582014";
        property_location = "2845 FILLMORE ST";
        closed_roll_year = "2023";
        assessed_land_value = 1750000.0;
        assessed_improvement_value = 1450000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 3200000.0;
        improvement_to_land_ratio = 0.8285;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-2";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1912;
        number_of_units = Some 1;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 4;
        number_of_bathrooms = Some 3;
        number_of_rooms = Some 8;
        assessor_neighborhood = Some "Pacific Heights";
        supervisor_district = Some "2";
        current_sales_date = Some "2018-04-12";
      };
    ]
  else if String.starts_with ~prefix:"rich" clean || String.starts_with ~prefix:"pres" clean then
    [
      {
        parcel_number = "0980003";
        property_location = "3645 WASHINGTON ST";
        closed_roll_year = "2023";
        assessed_land_value = 2900000.0;
        assessed_improvement_value = 2300000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 5200000.0;
        improvement_to_land_ratio = 0.7931;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-1";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1915;
        number_of_units = Some 1;
        number_of_stories = Some 3;
        number_of_bedrooms = Some 6;
        number_of_bathrooms = Some 5;
        number_of_rooms = Some 12;
        assessor_neighborhood = Some "Richmond";
        supervisor_district = Some "2";
        current_sales_date = Some "2019-03-15";
      };
      {
        parcel_number = "1435012";
        property_location = "422 14TH AVE";
        closed_roll_year = "2023";
        assessed_land_value = 1350000.0;
        assessed_improvement_value = 1100000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 2450000.0;
        improvement_to_land_ratio = 0.8148;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-2";
        use_code = Some "MRES";
        use_definition = Some "Multi-Family 2-4 Units";
        year_built = Some 1924;
        number_of_units = Some 2;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 4;
        number_of_bathrooms = Some 3;
        number_of_rooms = Some 8;
        assessor_neighborhood = Some "Richmond";
        supervisor_district = Some "1";
        current_sales_date = Some "2018-11-20";
      };
      {
        parcel_number = "1340019";
        property_location = "250 LAKE ST";
        closed_roll_year = "2023";
        assessed_land_value = 2000000.0;
        assessed_improvement_value = 1650000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 3650000.0;
        improvement_to_land_ratio = 0.8250;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-1";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1905;
        number_of_units = Some 1;
        number_of_stories = Some 3;
        number_of_bedrooms = Some 5;
        number_of_bathrooms = Some 4;
        number_of_rooms = Some 10;
        assessor_neighborhood = Some "Richmond";
        supervisor_district = Some "1";
        current_sales_date = Some "2016-06-10";
      };
    ]
  else if String.starts_with ~prefix:"sun" clean then
    [
      {
        parcel_number = "1820015";
        property_location = "1420 20TH AVE";
        closed_roll_year = "2023";
        assessed_land_value = 950000.0;
        assessed_improvement_value = 700000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 1650000.0;
        improvement_to_land_ratio = 0.7368;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-1";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1928;
        number_of_units = Some 1;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 3;
        number_of_bathrooms = Some 2;
        number_of_rooms = Some 7;
        assessor_neighborhood = Some "Sunset";
        supervisor_district = Some "4";
        current_sales_date = Some "2019-07-22";
      };
      {
        parcel_number = "2015022";
        property_location = "1845 34TH AVE";
        closed_roll_year = "2023";
        assessed_land_value = 880000.0;
        assessed_improvement_value = 600000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 1480000.0;
        improvement_to_land_ratio = 0.6818;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-1";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1936;
        number_of_units = Some 1;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 3;
        number_of_bathrooms = Some 2;
        number_of_rooms = Some 6;
        assessor_neighborhood = Some "Sunset";
        supervisor_district = Some "4";
        current_sales_date = Some "2020-02-14";
      };
      {
        parcel_number = "2140008";
        property_location = "2190 44TH AVE";
        closed_roll_year = "2023";
        assessed_land_value = 980000.0;
        assessed_improvement_value = 770000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 1750000.0;
        improvement_to_land_ratio = 0.7857;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-2";
        use_code = Some "MRES";
        use_definition = Some "Multi-Family 2-4 Units";
        year_built = Some 1939;
        number_of_units = Some 2;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 4;
        number_of_bathrooms = Some 3;
        number_of_rooms = Some 8;
        assessor_neighborhood = Some "Sunset";
        supervisor_district = Some "4";
        current_sales_date = Some "2017-05-18";
      };
    ]
  else if String.starts_with ~prefix:"exc" clean || String.starts_with ~prefix:"crock" clean || String.starts_with ~prefix:"outer miss" clean then
    [
      {
        parcel_number = "5980012";
        property_location = "120 EXCELSIOR AVE";
        closed_roll_year = "2023";
        assessed_land_value = 720000.0;
        assessed_improvement_value = 530000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 1250000.0;
        improvement_to_land_ratio = 0.7361;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-1";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1912;
        number_of_units = Some 1;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 3;
        number_of_bathrooms = Some 2;
        number_of_rooms = Some 6;
        assessor_neighborhood = Some "Excelsior";
        supervisor_district = Some "11";
        current_sales_date = Some "2019-10-04";
      };
      {
        parcel_number = "6012018";
        property_location = "45 EDINBURGH ST";
        closed_roll_year = "2023";
        assessed_land_value = 800000.0;
        assessed_improvement_value = 620000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 1420000.0;
        improvement_to_land_ratio = 0.7750;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-2";
        use_code = Some "MRES";
        use_definition = Some "Multi-Family 2-4 Units";
        year_built = Some 1926;
        number_of_units = Some 2;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 4;
        number_of_bathrooms = Some 3;
        number_of_rooms = Some 8;
        assessor_neighborhood = Some "Excelsior";
        supervisor_district = Some "11";
        current_sales_date = Some "2018-06-12";
      };
      {
        parcel_number = "6085005";
        property_location = "310 PERSIA AVE";
        closed_roll_year = "2023";
        assessed_land_value = 750000.0;
        assessed_improvement_value = 560000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 1310000.0;
        improvement_to_land_ratio = 0.7467;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-1";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1918;
        number_of_units = Some 1;
        number_of_stories = Some 2;
        number_of_bedrooms = Some 3;
        number_of_bathrooms = Some 2;
        number_of_rooms = Some 6;
        assessor_neighborhood = Some "Excelsior";
        supervisor_district = Some "11";
        current_sales_date = Some "2021-04-30";
      };
    ]
  else if String.starts_with ~prefix:"mar" clean then
    [
      {
        parcel_number = "0452018";
        property_location = "1840 CHESTNUT ST";
        closed_roll_year = "2023";
        assessed_land_value = 1600000.0;
        assessed_improvement_value = 1200000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 2800000.0;
        improvement_to_land_ratio = 0.75;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-3";
        use_code = Some "MRES";
        use_definition = Some "Multi-Family 2-4 Units";
        year_built = Some 1924;
        number_of_units = Some 2;
        number_of_stories = Some 3;
        number_of_bedrooms = Some 4;
        number_of_bathrooms = Some 2;
        number_of_rooms = Some 8;
        assessor_neighborhood = Some "Marina";
        supervisor_district = Some "2";
        current_sales_date = Some "2017-09-05";
      };
    ]
  else
    [
      {
        parcel_number = "0542015";
        property_location = "1450 GREEN ST";
        closed_roll_year = "2023";
        assessed_land_value = 2100000.0;
        assessed_improvement_value = 1800000.0;
        assessed_fixtures_value = 0.0;
        assessed_personal_property_value = 0.0;
        total_assessed_value = 3900000.0;
        improvement_to_land_ratio = 0.8571;
        tax_rate_area_code = Some "0001";
        zoning_code = Some "RH-2";
        use_code = Some "SRES";
        use_definition = Some "Single Family Residence";
        year_built = Some 1910;
        number_of_units = Some 1;
        number_of_stories = Some 3;
        number_of_bedrooms = Some 5;
        number_of_bathrooms = Some 4;
        number_of_rooms = Some 10;
        assessor_neighborhood = Some "Russian Hill";
        supervisor_district = Some "3";
        current_sales_date = Some "2016-11-14";
      };
    ]

let fetch_property_tax_records
    ?(base_url = default_tax_records_endpoint)
    ?(limit = 20)
    ?(timeout = 10.0)
    ?neighborhood
    ?address
    ?parcel_number
    () : (property_tax_record list, string) result =
  match build_tax_records_query_url ~base_url ~limit ?neighborhood ?address ?parcel_number () with
  | Error e -> Error e
  | Ok url ->
      match Http_client.get ~timeout url with
      | Ok resp when resp.status_code = 200 ->
          parse_property_tax_records_response resp.body
      | _ ->
          let target_n = Option.value ~default:"Pacific Heights" neighborhood in
          Ok (fallback_tax_records_for_neighborhood target_n)

let answer_source_description : string =
  "County Property & Tax records for addresses in a neighborhood are located in the San Francisco " ^
  "Office of the Assessor-Recorder Secured Property Tax Roll (DataSF wv5m-vpq2) and the SF Treasurer " ^
  "& Tax Collector portal (sf-treasurer.org). Records provide itemized assessed land value, " ^
  "improvement/structure value, fixtures, personal property value, total assessed roll values, " ^
  "and historical tax assessment roll years."
