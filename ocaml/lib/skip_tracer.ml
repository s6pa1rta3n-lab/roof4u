let is_synthesized_name (name : string) : bool =
  String.starts_with ~prefix:"Owner Occupant" name ||
  String.starts_with ~prefix:"Parcel " name ||
  String.ends_with ~suffix:"Owner" name

let build_payload (lead : Types.raw_lead) : string =
  let fields = ref [
    ("property_address", Json.String lead.address);
    ("property_city", Json.String "San Francisco");
    ("property_state", Json.String "CA");
    ("property_zip", Json.String lead.zip_code);
  ] in
  (match lead.owner_name with
   | Some n when not (is_synthesized_name n) && String.trim n <> "" ->
       fields := ("owner_name", Json.String n) :: !fields
   | _ -> ());
  Json.to_string (Json.Object !fields)

let rec find_valid_phone_in_json_list = function
  | [] -> None
  | Json.Object num_obj :: rest ->
      let candidate_opt =
        match List.assoc_opt "number" num_obj with
        | Some (Json.String n) -> Some n
        | _ ->
            (match List.assoc_opt "phone" num_obj with
             | Some (Json.String n) -> Some n
             | _ -> None)
      in
      (match candidate_opt with
       | Some candidate ->
           (match Phone_validator.sanitize_and_normalize candidate with
            | Ok vp -> Some vp.canonical
            | Error _ -> find_valid_phone_in_json_list rest)
       | None -> find_valid_phone_in_json_list rest)
  | Json.String candidate :: rest ->
      (match Phone_validator.sanitize_and_normalize candidate with
       | Ok vp -> Some vp.canonical
       | Error _ -> find_valid_phone_in_json_list rest)
  | _ :: rest -> find_valid_phone_in_json_list rest

let extract_phone_number (body : string) : string option =
  match Json.parse body with
  | Ok (Json.Object fields) ->
      (match List.assoc_opt "results" fields with
       | Some (Json.Object res_fields) ->
           (match List.assoc_opt "phone_numbers" res_fields with
            | Some (Json.Array nums) -> find_valid_phone_in_json_list nums
            | _ -> None)
       | Some (Json.Array res_items) ->
           let rec scan_items = function
             | [] -> None
             | Json.Object item_fields :: rest ->
                 (match List.assoc_opt "phone_numbers" item_fields with
                  | Some (Json.Array nums) ->
                      (match find_valid_phone_in_json_list nums with
                       | Some p -> Some p
                       | None -> scan_items rest)
                  | _ ->
                      (match List.assoc_opt "number" item_fields with
                       | Some (Json.String n) ->
                           (match Phone_validator.sanitize_and_normalize n with
                            | Ok vp -> Some vp.canonical
                            | Error _ -> scan_items rest)
                       | _ -> scan_items rest))
             | _ :: rest -> scan_items rest
           in
           scan_items res_items
       | _ ->
           (match List.assoc_opt "phone_numbers" fields with
            | Some (Json.Array nums) -> find_valid_phone_in_json_list nums
            | _ -> None))
  | _ -> None

let default_api_url = "https://api.batchskiptracing.com/v1/property/skip"

let append_phone_number ?(api_url = default_api_url) (lead : Types.raw_lead) : (Types.raw_lead, string) result =
  let api_key = try Sys.getenv "SKIP_TRACING_API_KEY" with Not_found -> "" in
  if api_key = "" then
    Ok { lead with phone_number = None }
  else
    let payload = build_payload lead in
    let headers = [
      ("Authorization", "Bearer " ^ api_key);
      ("Content-Type", "application/json");
      ("Accept", "application/json")
    ] in
    match Http_client.post ~headers ~timeout:5.0 ~body:payload api_url with
    | Ok resp ->
        if resp.status_code = 200 then
          match extract_phone_number resp.body with
          | Some phone -> Ok { lead with phone_number = Some phone }
          | None -> Ok { lead with phone_number = None }
        else
          Error (Printf.sprintf "Skip tracing API failed with status %d: %s" resp.status_code resp.body)
    | Error e -> Error ("Skip tracing network error: " ^ e)
