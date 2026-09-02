let api_url = "https://api.batchskiptracing.com/v1/property/skip"

let build_payload (lead : Types.raw_lead) : string =
  let owner_name = match lead.owner_name with Some n -> n | None -> "" in
  let address = lead.address in
  let zip_code = lead.zip_code in
  Printf.sprintf "{\"property_address\": \"%s\", \"property_zip\": \"%s\", \"owner_name\": \"%s\"}" 
    (String.escaped address) (String.escaped zip_code) (String.escaped owner_name)

let extract_phone_number (body : string) : string option =
  match Json.parse body with
  | Ok (Json.Object fields) ->
      (match List.assoc_opt "results" fields with
       | Some (Json.Object res_fields) ->
           (match List.assoc_opt "phone_numbers" res_fields with
            | Some (Json.Array nums) ->
                let rec find_first_valid = function
                  | [] -> None
                  | Json.Object num_obj :: rest ->
                      (match List.assoc_opt "number" num_obj with
                       | Some (Json.String n) -> Some n
                       | _ -> find_first_valid rest)
                  | _ :: rest -> find_first_valid rest
                in
                find_first_valid nums
            | _ -> None)
       | _ -> None)
  | _ -> None

let append_phone_number (lead : Types.raw_lead) : (Types.raw_lead, string) result =
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
    match Http_client.post ~headers ~body:payload api_url with
    | Ok resp ->
        if resp.status_code = 200 then
          match extract_phone_number resp.body with
          | Some phone -> Ok { lead with phone_number = Some phone }
          | None -> Ok { lead with phone_number = None }
        else
          Error (Printf.sprintf "Skip tracing API failed with status %d: %s" resp.status_code resp.body)
    | Error e -> Error ("Skip tracing network error: " ^ e)
