(**
   types.ml - Formal algebraic data types for Roo4u lead verification and scoring.
   Statically typed representations for municipal properties, permits, invariants, and proofs.
*)

type roof_type =
  | Victorian
  | Flat
  | Mansard
  | Gable
  | Hip
  | Metal
  | Unknown
  | Other of string

type property_type =
  | SingleFamily
  | MultiUnit2To4
  | MultiUnit5Plus
  | Commercial
  | MixedUse
  | Condo
  | Unknown
  | Other of string

type permit_record = {
  permit_number : string;
  permit_type : string option;
  description : string;
  date_filed : string option;
  date_issued : string option;
  status : string option;
  year : int option;
  is_roof_replacement : bool;
  cost : float option;
}

type raw_lead = {
  address : string;
  zip_code : string;
  property_type : property_type;
  roof_type : roof_type;
  property_type_raw : string option;
  roof_type_raw : string option;
  estimated_value : float option;
  owner_name : string option;
  is_hoa : bool;
  is_rental : bool;
  apn : string option;
  last_roof_permit_date : string option;
  roof_age_years : float option;
  year_built : int option;
  phone_number : string option;
  permits : permit_record list;
}

type invariant_id =
  | INV1_Physical
  | INV2_Temporal
  | INV3_Economic
  | INV4_Permits

type invariant_violation = {
  code : invariant_id;
  name : string;
  message : string;
}

type invariant_status =
  | Satisfied of string
  | Violated of invariant_violation

type scoring_components = {
  age_score : float;     (** 0.0 to 40.0 *)
  value_score : float;   (** 0.0 to 35.0 *)
  type_score : float;    (** 10.0 to 25.0 *)
  total_score : float;   (** 0.0 to 100.0 *)
}

type qualification_verdict =
  | Qualified of {
      score : scoring_components;
      invariants_passed : string list;
      proof_id : string;
    }
  | Disqualified of {
      failed_invariants : invariant_violation list;
      partial_score : float;
      score_components : scoring_components;
    }

type verified_lead = {
  lead : raw_lead;
  verdict : qualification_verdict;
  proof_id : string;
  sha256_proof : string;
  timestamp : string;
}

(** Helper string converters *)
let string_of_roof_type = function
  | Victorian -> "Victorian"
  | Flat -> "Flat"
  | Mansard -> "Mansard"
  | Gable -> "Gable"
  | Hip -> "Hip"
  | Metal -> "Metal"
  | Unknown -> "Unknown"
  | Other s -> s

let parse_roof_type (raw : string) : roof_type =
  let s = String.lowercase_ascii (String.trim raw) in
  let contains_sub sub =
    let sub_len = String.length sub in
    let s_len = String.length s in
    let rec check i =
      if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else check (i + 1)
    in
    check 0
  in
  if contains_sub "vic" || contains_sub "queen anne" then Victorian
  else if s = "flat" || contains_sub "flat" || contains_sub "tar" || contains_sub "gravel" || contains_sub "built-up" || contains_sub "built up" || contains_sub "bitumen" || contains_sub "torch" || s = "tpo" || s = "epdm" then Flat
  else if contains_sub "mansard" then Mansard
  else if contains_sub "gable" || contains_sub "pitch" then Gable
  else if contains_sub "hip" then Hip
  else if contains_sub "metal" || contains_sub "seam" then Metal
  else if s = "unknown" || s = "" then Unknown
  else Other raw

let string_of_property_type = function
  | SingleFamily -> "Single-Family"
  | MultiUnit2To4 -> "Multi-Unit (2-4 Units)"
  | MultiUnit5Plus -> "Multi-Family (5+ Units)"
  | Commercial -> "Commercial"
  | MixedUse -> "Mixed-Use"
  | Condo -> "Condominium"
  | Unknown -> "Unknown"
  | Other s -> s

let parse_property_type (raw : string) : property_type =
  let s = String.lowercase_ascii (String.trim raw) in
  let contains_sub sub =
    let sub_len = String.length sub in
    let s_len = String.length s in
    let rec check i =
      if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else check (i + 1)
    in
    check 0
  in
  if s = "singlefamily" || s = "single_family" || s = "single-family" || s = "single family" || s = "sfr" || s = "single family residential" || s = "1 family dwelling" || s = "1 family" || s = "townhouse" then SingleFamily
  else if s = "multiunit2to4" || s = "multi_unit_2_to_4" || s = "multi-unit" || s = "multiunit" || s = "multi unit" || s = "2-unit" || s = "3-unit" || s = "4-unit" || s = "2 unit" || s = "3 unit" || s = "4 unit" || s = "duplex" || s = "triplex" || s = "fourplex" || s = "2 family dwelling" || s = "3 family dwelling" || s = "4 family dwelling" || contains_sub "2-4 unit" || contains_sub "2 to 4" then MultiUnit2To4
  else if s = "multiunit5plus" || s = "multi_unit_5_plus" || s = "multi-family" || s = "multifamily" || contains_sub "apartment" || contains_sub "5+ unit" || contains_sub "5+ units" || contains_sub "5-plus" then MultiUnit5Plus
  else if contains_sub "commercial" || contains_sub "retail" || contains_sub "office" || contains_sub "industrial" then Commercial
  else if contains_sub "mixed" then MixedUse
  else if contains_sub "condo" || contains_sub "co-op" then Condo
  else if s = "unknown" || s = "" then Unknown
  else Other raw

let string_of_invariant_id = function
  | INV1_Physical -> "INV1_Physical"
  | INV2_Temporal -> "INV2_Temporal"
  | INV3_Economic -> "INV3_Economic"
  | INV4_Permits -> "INV4_Permits"

let invariant_id_of_string = function
  | "INV1_Physical" | "INV-1" | "INV1" -> INV1_Physical
  | "INV2_Temporal" | "INV-2" | "INV2" -> INV2_Temporal
  | "INV3_Economic" | "INV-3" | "INV3" -> INV3_Economic
  | "INV4_Permits" | "INV-4" | "INV4" -> INV4_Permits
  | _ -> INV1_Physical

(** JSON AST conversions *)

let permit_record_to_json (p : permit_record) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let opt_int k v = match v with Some i -> [(k, Json.Number (float_of_int i))] | None -> [(k, Json.Null)] in
  let opt_float k v = match v with Some f -> [(k, Json.Number f)] | None -> [(k, Json.Null)] in
  let fields =
    [ ("permit_number", Json.String p.permit_number) ] @
    (opt_str "permit_type" p.permit_type) @
    [ ("description", Json.String p.description) ] @
    (opt_str "date_filed" p.date_filed) @
    (opt_str "date_issued" p.date_issued) @
    (opt_str "status" p.status) @
    (opt_int "year" p.year) @
    [ ("is_roof_replacement", Json.Bool p.is_roof_replacement) ] @
    (opt_float "cost" p.cost)
  in
  Json.Object fields

let permit_record_of_json (j : Json.t) : permit_record =
  let permit_number = Json.get_string "permit_number" j |> Option.value ~default:"" in
  let permit_type = Json.get_string "permit_type" j in
  let description = Json.get_string "description" j |> Option.value ~default:"" in
  let date_filed = Json.get_string "date_filed" j in
  let date_issued = Json.get_string "date_issued" j in
  let status = Json.get_string "status" j in
  let year = Json.get_int "year" j in
  let is_roof_replacement = Json.get_bool "is_roof_replacement" j |> Option.value ~default:false in
  let cost = Json.get_float "cost" j in
  {
    permit_number;
    permit_type;
    description;
    date_filed;
    date_issued;
    status;
    year;
    is_roof_replacement;
    cost;
  }

let raw_lead_to_json (l : raw_lead) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let opt_float k v = match v with Some f -> [(k, Json.Number f)] | None -> [(k, Json.Null)] in
  let opt_int k v = match v with Some i -> [(k, Json.Number (float_of_int i))] | None -> [(k, Json.Null)] in
  let permits_json = Json.Array (List.map permit_record_to_json l.permits) in
  let fields =
    [
      ("address", Json.String l.address);
      ("zip_code", Json.String l.zip_code);
      ("property_type", Json.String (string_of_property_type l.property_type));
      ("roof_type", Json.String (string_of_roof_type l.roof_type));
    ] @
    (opt_str "property_type_raw" l.property_type_raw) @
    (opt_str "roof_type_raw" l.roof_type_raw) @
    (opt_float "estimated_value" l.estimated_value) @
    (opt_str "owner_name" l.owner_name) @
    [
      ("is_hoa", Json.Bool l.is_hoa);
      ("is_rental", Json.Bool l.is_rental);
    ] @
    (opt_str "apn" l.apn) @
    (opt_str "last_roof_permit_date" l.last_roof_permit_date) @
    (opt_float "roof_age_years" l.roof_age_years) @
    (opt_int "year_built" l.year_built) @
    (opt_str "phone_number" l.phone_number) @
    [ ("permits", permits_json) ]
  in
  Json.Object fields

let raw_lead_of_json (j : Json.t) : raw_lead =
  let target =
    match Json.get_field "lead" j with
    | Some (Json.Object _ as obj) -> obj
    | _ -> j
  in
  let address = Json.get_string "address" target |> Option.value ~default:"" in
  let zip_code = Json.get_string "zip_code" target |> Option.value ~default:"94115" in
  let prop_raw =
    match Json.get_string "property_type" target with
    | Some p -> Some p
    | None -> Json.get_string "property_type_str" target
  in
  let roof_raw =
    match Json.get_string "roof_type" target with
    | Some r -> Some r
    | None -> Json.get_string "roof_type_str" target
  in
  let property_type =
    match prop_raw with
    | Some s -> parse_property_type s
    | None -> SingleFamily
  in
  let roof_type =
    match roof_raw with
    | Some s -> parse_roof_type s
    | None -> Victorian
  in
  let estimated_value = Json.get_float "estimated_value" target in
  let owner_name = Json.get_string "owner_name" target in
  let is_hoa = Json.get_bool "is_hoa" target |> Option.value ~default:false in
  let is_rental = Json.get_bool "is_rental" target |> Option.value ~default:false in
  let apn = Json.get_string "apn" target in
  let last_roof_permit_date = Json.get_string "last_roof_permit_date" target in
  let roof_age_years = Json.get_float "roof_age_years" target in
  let year_built = Json.get_int "year_built" target in
  let phone_number = Json.get_string "phone_number" target in
  let permits =
    match Json.get_array "permits" target with
    | Some arr -> List.map permit_record_of_json arr
    | None -> []
  in
  {
    address;
    zip_code;
    property_type;
    roof_type;
    property_type_raw = prop_raw;
    roof_type_raw = roof_raw;
    estimated_value;
    owner_name;
    is_hoa;
    is_rental;
    apn;
    last_roof_permit_date;
    roof_age_years;
    year_built;
    phone_number;
    permits;
  }

let scoring_components_to_json (s : scoring_components) : Json.t =
  Json.Object [
    ("age_score", Json.Number s.age_score);
    ("value_score", Json.Number s.value_score);
    ("type_score", Json.Number s.type_score);
    ("total_score", Json.Number s.total_score);
  ]

let invariant_violation_to_json (v : invariant_violation) : Json.t =
  Json.Object [
    ("code", Json.String (string_of_invariant_id v.code));
    ("name", Json.String v.name);
    ("invariant", Json.String v.name);
    ("message", Json.String v.message);
  ]

let qualification_verdict_to_json = function
  | Qualified { score; invariants_passed; proof_id } ->
      Json.Object [
        ("status", Json.String "QUALIFIED");
        ("actionability_score", Json.Number score.total_score);
        ("score", scoring_components_to_json score);
        ("score_components", scoring_components_to_json score);
        ("invariants_passed", Json.Array (List.map (fun s -> Json.String s) invariants_passed));
        ("proof_id", Json.String proof_id);
      ]
  | Disqualified { failed_invariants; partial_score; score_components } ->
      Json.Object [
        ("status", Json.String "DISQUALIFIED");
        ("actionability_score", Json.Number partial_score);
        ("failed_invariants", Json.Array (List.map invariant_violation_to_json failed_invariants));
        ("partial_score", Json.Number partial_score);
        ("score", scoring_components_to_json score_components);
        ("score_components", scoring_components_to_json score_components);
      ]

let verified_lead_to_json (v : verified_lead) : Json.t =
  Json.Object [
    ("lead", raw_lead_to_json v.lead);
    ("verdict", qualification_verdict_to_json v.verdict);
    ("proof_id", Json.String v.proof_id);
    ("sha256_proof", Json.String v.sha256_proof);
    ("proof_digest", Json.String v.sha256_proof);
    ("timestamp", Json.String v.timestamp);
    ("verification_timestamp", Json.String v.timestamp);
  ]

let verified_lead_to_json_string ?(pretty = false) (v : verified_lead) : string =
  let ast = verified_lead_to_json v in
  if pretty then Json.to_string_pretty ast
  else Json.to_string ast

let parse_json_lead (json_str : string) : (raw_lead, string) result =
  match Json.parse json_str with
  | Ok ast -> Ok (raw_lead_of_json ast)
  | Error msg -> Error msg

(** Domain-Specific Public Record Types *)

type ownership_type =
  | Individual
  | Trust
  | CorporateLLC
  | Estate
  | PublicEntity
  | UnknownOwnership

let string_of_ownership_type = function
  | Individual -> "Individual"
  | Trust -> "Trust"
  | CorporateLLC -> "Corporate / LLC"
  | Estate -> "Estate"
  | PublicEntity -> "Public Entity"
  | UnknownOwnership -> "Unknown"

let parse_ownership_type (name : string) : ownership_type =
  let s = String.lowercase_ascii (String.trim name) in
  let contains_sub sub =
    let sl = String.length sub in
    let dl = String.length s in
    let rec check i =
      if i + sl > dl then false
      else if String.sub s i sl = sub then true
      else check (i + 1)
    in
    check 0
  in
  if contains_sub "trust" || contains_sub "trs" || contains_sub "family trust" || contains_sub "living trust" then Trust
  else if contains_sub "llc" || contains_sub "corp" || contains_sub "inc" || contains_sub "holdings" || contains_sub "properties" || contains_sub "lp" || contains_sub "ltd" || contains_sub "investment" then CorporateLLC
  else if contains_sub "estate" || contains_sub "est of" || contains_sub "conservatorship" then Estate
  else if contains_sub "city" || contains_sub "county" || contains_sub "state of" || contains_sub "housing authority" then PublicEntity
  else if s = "" || s = "unknown" then UnknownOwnership
  else Individual

type homeowner_name_record = {
  parcel_number : string;
  property_location : string;
  owner_name : string;
  ownership_type : ownership_type;
  has_homeowner_exemption : bool;
  exemption_value : float;
  assessor_neighborhood : string option;
  closed_roll_year : string option;
}

type homeowner_address_record = {
  parcel_number : string;
  property_location : string;
  street_number : string;
  street_name : string;
  unit_number : string option;
  zip_code : string;
  neighborhood : string;
  property_class_code : string option;
  property_class_definition : string option;
  is_residential : bool;
  units_count : int;
}

type gis_roof_record = {
  parcel_number : string;
  property_location : string;
  roof_size_sqft : float;
  roof_type_classified : roof_type;
  ground_elevation_ft : float option;
  roof_height_ft : float option;
  coordinates_latitude : float option;
  coordinates_longitude : float option;
  polygon_points_count : int;
  is_green_roof_or_solar : bool;
}

type roof_permit_record = {
  permit_number : string;
  block : string;
  lot : string;
  parcel_number : string;
  street_number : string;
  street_name : string;
  zip_code : string;
  description : string;
  filed_date : string option;
  issued_date : string option;
  completed_date : string option;
  status : string option;
  estimated_cost : float option;
  revised_cost : float option;
  roof_age_years : float option;
  is_roof_replacement : bool;
}

type property_tax_record = {
  parcel_number : string;
  property_location : string;
  closed_roll_year : string;
  assessed_land_value : float;
  assessed_improvement_value : float;
  assessed_fixtures_value : float;
  assessed_personal_property_value : float;
  total_assessed_value : float;
  improvement_to_land_ratio : float;
  tax_rate_area_code : string option;
  zoning_code : string option;
  use_code : string option;
  use_definition : string option;
  year_built : int option;
  number_of_units : int option;
  number_of_stories : int option;
  number_of_bedrooms : int option;
  number_of_bathrooms : int option;
  number_of_rooms : int option;
  assessor_neighborhood : string option;
  supervisor_district : string option;
  current_sales_date : string option;
}

let homeowner_name_record_to_json (r : homeowner_name_record) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  Json.Object ([
    ("parcel_number", Json.String r.parcel_number);
    ("property_location", Json.String r.property_location);
    ("owner_name", Json.String r.owner_name);
    ("ownership_type", Json.String (string_of_ownership_type r.ownership_type));
    ("has_homeowner_exemption", Json.Bool r.has_homeowner_exemption);
    ("exemption_value", Json.Number r.exemption_value);
  ] @ (opt_str "assessor_neighborhood" r.assessor_neighborhood)
    @ (opt_str "closed_roll_year" r.closed_roll_year))

let homeowner_address_record_to_json (r : homeowner_address_record) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  Json.Object ([
    ("parcel_number", Json.String r.parcel_number);
    ("property_location", Json.String r.property_location);
    ("street_number", Json.String r.street_number);
    ("street_name", Json.String r.street_name);
  ] @ (opt_str "unit_number" r.unit_number) @ [
    ("zip_code", Json.String r.zip_code);
    ("neighborhood", Json.String r.neighborhood);
  ] @ (opt_str "property_class_code" r.property_class_code)
    @ (opt_str "property_class_definition" r.property_class_definition)
    @ [
    ("is_residential", Json.Bool r.is_residential);
    ("units_count", Json.Number (float_of_int r.units_count));
  ])

let gis_roof_record_to_json (r : gis_roof_record) : Json.t =
  let opt_float k v = match v with Some f -> [(k, Json.Number f)] | None -> [(k, Json.Null)] in
  Json.Object ([
    ("parcel_number", Json.String r.parcel_number);
    ("property_location", Json.String r.property_location);
    ("roof_size_sqft", Json.Number r.roof_size_sqft);
    ("roof_type_classified", Json.String (string_of_roof_type r.roof_type_classified));
  ] @ (opt_float "ground_elevation_ft" r.ground_elevation_ft)
    @ (opt_float "roof_height_ft" r.roof_height_ft)
    @ (opt_float "coordinates_latitude" r.coordinates_latitude)
    @ (opt_float "coordinates_longitude" r.coordinates_longitude)
    @ [
    ("polygon_points_count", Json.Number (float_of_int r.polygon_points_count));
    ("is_green_roof_or_solar", Json.Bool r.is_green_roof_or_solar);
  ])

let roof_permit_record_to_json (r : roof_permit_record) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let opt_float k v = match v with Some f -> [(k, Json.Number f)] | None -> [(k, Json.Null)] in
  Json.Object ([
    ("permit_number", Json.String r.permit_number);
    ("block", Json.String r.block);
    ("lot", Json.String r.lot);
    ("parcel_number", Json.String r.parcel_number);
    ("street_number", Json.String r.street_number);
    ("street_name", Json.String r.street_name);
    ("zip_code", Json.String r.zip_code);
    ("description", Json.String r.description);
  ] @ (opt_str "filed_date" r.filed_date)
    @ (opt_str "issued_date" r.issued_date)
    @ (opt_str "completed_date" r.completed_date)
    @ (opt_str "status" r.status)
    @ (opt_float "estimated_cost" r.estimated_cost)
    @ (opt_float "revised_cost" r.revised_cost)
    @ (opt_float "roof_age_years" r.roof_age_years)
    @ [ ("is_roof_replacement", Json.Bool r.is_roof_replacement) ])

let property_tax_record_to_json (r : property_tax_record) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let opt_int k v = match v with Some i -> [(k, Json.Number (float_of_int i))] | None -> [(k, Json.Null)] in
  Json.Object ([
    ("parcel_number", Json.String r.parcel_number);
    ("property_location", Json.String r.property_location);
    ("closed_roll_year", Json.String r.closed_roll_year);
    ("assessed_land_value", Json.Number r.assessed_land_value);
    ("assessed_improvement_value", Json.Number r.assessed_improvement_value);
    ("assessed_fixtures_value", Json.Number r.assessed_fixtures_value);
    ("assessed_personal_property_value", Json.Number r.assessed_personal_property_value);
    ("total_assessed_value", Json.Number r.total_assessed_value);
    ("improvement_to_land_ratio", Json.Number r.improvement_to_land_ratio);
  ] @ (opt_str "tax_rate_area_code" r.tax_rate_area_code)
    @ (opt_str "zoning_code" r.zoning_code)
    @ (opt_str "use_code" r.use_code)
    @ (opt_str "use_definition" r.use_definition)
    @ (opt_int "year_built" r.year_built)
    @ (opt_int "number_of_units" r.number_of_units)
    @ (opt_int "number_of_stories" r.number_of_stories)
    @ (opt_int "number_of_bedrooms" r.number_of_bedrooms)
    @ (opt_int "number_of_bathrooms" r.number_of_bathrooms)
    @ (opt_int "number_of_rooms" r.number_of_rooms)
    @ (opt_str "assessor_neighborhood" r.assessor_neighborhood)
    @ (opt_str "supervisor_district" r.supervisor_district)
    @ (opt_str "current_sales_date" r.current_sales_date))
