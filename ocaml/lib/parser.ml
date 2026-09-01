(**
   parser.ml - Pure functional JSON parser and serializer for Roo4u leads and proofs.
   Provides robust zero-dependency parsing and deterministic JSON generation.
*)

open Types

let escape_json (s : string) : string =
  let b = Buffer.create (String.length s + 10) in
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let extract_string_field (key : string) (json_str : string) : string option =
  let pattern = "\"" ^ key ^ "\"" in
  try
    let k_pos = Str.search_forward (Str.regexp_string pattern) json_str 0 in
    let colon_pos = String.index_from json_str k_pos ':' in
    let sub = String.sub json_str colon_pos (String.length json_str - colon_pos) in
    if Str.string_match (Str.regexp "^:[ \t\r\n]*\"\\([^\"]*\\)\"") sub 0 then
      Some (Str.matched_group 1 sub)
    else if Str.string_match (Str.regexp "^:[ \t\r\n]*null") sub 0 then
      None
    else None
  with _ -> None

let extract_float_field (key : string) (json_str : string) : float option =
  let pattern = "\"" ^ key ^ "\"" in
  try
    let k_pos = Str.search_forward (Str.regexp_string pattern) json_str 0 in
    let colon_pos = String.index_from json_str k_pos ':' in
    let sub = String.sub json_str colon_pos (String.length json_str - colon_pos) in
    if Str.string_match (Str.regexp "^:[ \t\r\n]*\\([0-9]+\\(\\.[0-9]+\\)?\\)") sub 0 then
      Some (float_of_string (Str.matched_group 1 sub))
    else None
  with _ -> None

let extract_int_field (key : string) (json_str : string) : int option =
  let pattern = "\"" ^ key ^ "\"" in
  try
    let k_pos = Str.search_forward (Str.regexp_string pattern) json_str 0 in
    let colon_pos = String.index_from json_str k_pos ':' in
    let sub = String.sub json_str colon_pos (String.length json_str - colon_pos) in
    if Str.string_match (Str.regexp "^:[ \t\r\n]*\\([0-9]+\\)") sub 0 then
      Some (int_of_string (Str.matched_group 1 sub))
    else None
  with _ -> None

let extract_bool_field (key : string) (json_str : string) : bool =
  let pattern = "\"" ^ key ^ "\"" in
  try
    let k_pos = Str.search_forward (Str.regexp_string pattern) json_str 0 in
    let colon_pos = String.index_from json_str k_pos ':' in
    let sub = String.sub json_str colon_pos (String.length json_str - colon_pos) in
    if Str.string_match (Str.regexp "^:[ \t\r\n]*true") sub 0 then true
    else false
  with _ -> false

let extract_permits_array (json_str : string) : permit_record list =
  try
    let pattern = "\"permits\"" in
    let k_pos = Str.search_forward (Str.regexp_string pattern) json_str 0 in
    let open_bracket = String.index_from json_str k_pos '[' in
    let close_bracket = String.index_from json_str open_bracket ']' in
    let permits_content = String.sub json_str (open_bracket + 1) (close_bracket - open_bracket - 1) in
    
    let regex_obj = Str.regexp "{[^}]+}" in
    let rec collect_objs pos acc =
      try
        let match_pos = Str.search_forward regex_obj permits_content pos in
        let match_str = Str.matched_string permits_content in
        let permit_no = match extract_string_field "permit_number" match_str with Some p -> p | None -> "PERMIT" in
        let date_filed = extract_string_field "date_filed" match_str in
        let date_issued = extract_string_field "date_issued" match_str in
        let description = match extract_string_field "description" match_str with Some d -> d | None -> "" in
        let is_roof = extract_bool_field "is_roof_replacement" match_str in
        let cost = extract_float_field "cost" match_str in
        let p_rec = {
          permit_number = permit_no;
          date_filed;
          date_issued;
          description;
          is_roof_replacement = is_roof;
          cost;
        } in
        collect_objs (match_pos + String.length match_str) (p_rec :: acc)
      with Not_found -> List.rev acc
    in
    collect_objs 0 []
  with _ -> []

let parse_json_lead (json_str : string) : raw_lead =
  let address =
    match extract_string_field "address" json_str with
    | Some a -> a
    | None -> "Unknown Address"
  in
  let zip_code =
    match extract_string_field "zip_code" json_str with
    | Some z -> z
    | None -> "94115"
  in
  let property_type_str =
    match extract_string_field "property_type" json_str with
    | Some p -> p
    | None -> "Single-Family"
  in
  let roof_type_str =
    match extract_string_field "roof_type" json_str with
    | Some r -> r
    | None -> "Victorian"
  in
  let estimated_value = extract_float_field "estimated_value" json_str in
  let apn = extract_string_field "apn" json_str in
  let owner_name = extract_string_field "owner_name" json_str in
  let is_hoa = extract_bool_field "is_hoa" json_str in
  let is_rental = extract_bool_field "is_rental" json_str in
  let year_built = extract_int_field "year_built" json_str in
  let roof_age_years = extract_float_field "roof_age_years" json_str in
  let last_roof_permit_date = extract_string_field "last_roof_permit_date" json_str in
  let permits = extract_permits_array json_str in

  {
    address;
    zip_code;
    property_type_str;
    roof_type_str;
    estimated_value;
    apn;
    owner_name;
    is_hoa;
    is_rental;
    year_built;
    roof_age_years;
    last_roof_permit_date;
    permits;
  }

let verified_lead_to_json (v : verified_lead) : string =
  let lead = v.lead in
  let opt_str key = function
    | Some s -> Printf.sprintf "\"%s\": \"%s\"" key (escape_json s)
    | None -> Printf.sprintf "\"%s\": null" key
  in
  let opt_float key = function
    | Some f -> Printf.sprintf "\"%s\": %.2f" key f
    | None -> Printf.sprintf "\"%s\": null" key
  in
  let opt_int key = function
    | Some i -> Printf.sprintf "\"%s\": %d" key i
    | None -> Printf.sprintf "\"%s\": null" key
  in

  let verdict_json =
    match v.verdict with
    | Qualified { score; invariants_passed; proof_id } ->
        let passed_items = List.map (fun s -> "\"" ^ escape_json s ^ "\"") invariants_passed in
        Printf.sprintf
          "{\n\
          \      \"status\": \"QUALIFIED\",\n\
          \      \"actionability_score\": %.2f,\n\
          \      \"score_components\": {\n\
          \        \"roof_age_points\": %.2f,\n\
          \        \"property_value_points\": %.2f,\n\
          \        \"roof_type_points\": %.2f\n\
          \      },\n\
          \      \"invariants_passed\": [%s],\n\
          \      \"proof_id\": \"%s\"\n\
          \    }"
          score.total_actionability_score
          score.roof_age_component
          score.property_value_component
          score.roof_type_component
          (String.concat ", " passed_items)
          proof_id
    | Disqualified { failed_invariants; partial_score } ->
        let failed_items =
          List.map (fun (name, msg) ->
            Printf.sprintf "{\"invariant\": \"%s\", \"message\": \"%s\"}" (escape_json name) (escape_json msg)
          ) failed_invariants
        in
        Printf.sprintf
          "{\n\
          \      \"status\": \"DISQUALIFIED\",\n\
          \      \"partial_score\": %.2f,\n\
          \      \"failed_invariants\": [%s]\n\
          \    }"
          partial_score
          (String.concat ", " failed_items)
  in

  Printf.sprintf
    "{\n\
    \  \"address\": \"%s\",\n\
    \  \"zip_code\": \"%s\",\n\
    \  \"property_type\": \"%s\",\n\
    \  \"roof_type\": \"%s\",\n\
    \  %s,\n\
    \  %s,\n\
    \  %s,\n\
    \  \"is_hoa\": %b,\n\
    \  \"is_rental\": %b,\n\
    \  %s,\n\
    \  %s,\n\
    \  %s,\n\
    \  \"verdict\": %s,\n\
    \  \"verification_timestamp\": \"%s\",\n\
    \  \"proof_digest\": \"%s\"\n\
    }"
    (escape_json lead.address)
    (escape_json lead.zip_code)
    (escape_json lead.property_type_str)
    (escape_json lead.roof_type_str)
    (opt_float "estimated_value" lead.estimated_value)
    (opt_str "apn" lead.apn)
    (opt_str "owner_name" lead.owner_name)
    lead.is_hoa
    lead.is_rental
    (opt_int "year_built" lead.year_built)
    (opt_float "roof_age_years" lead.roof_age_years)
    (opt_str "last_roof_permit_date" lead.last_roof_permit_date)
    verdict_json
    v.verification_timestamp
    v.sha256_proof
