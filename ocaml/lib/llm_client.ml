(**
   llm_client.ml - Local LLM Inference Client and Response Cleansing Engine.
   Features:
     - Pure OCaml HTTP client targeting local OpenAI-compatible inference endpoints (localhost:8000/v1).
     - OpenAI chat completion JSON payload formatting with system prompts.
     - Response cleansing: strips thinking tags (<think>...</think>), markdown code fences,
       and isolates balanced-brace JSON payloads.
     - Structured decoding into property and permit extraction records.
*)

type config = {
  base_url : string;
  model : string;
  api_key : string;
  timeout : float;
}

let default_config : config = {
  base_url = "http://localhost:8000/v1";
  model = "nvidia/llama-3.1-nemotron-70b-instruct";
  api_key = "not-needed";
  timeout = 30.0;
}

type property_extraction = {
  address : string;
  zip_code : string;
  property_type : string;
  roof_type : string;
  is_hoa : bool;
  is_rental : bool;
  estimated_value : float option;
  bedrooms : int option;
  bathrooms : float option;
  sqft : int option;
  year_built : int option;
  description : string option;
  confidence_score : float;
}

type county_permit_extraction = {
  address : string;
  apn : string option;
  owner_name : string option;
  assessed_value : float option;
  last_roof_permit_date : string option;
  permit_history : Types.permit_record list;
  roof_age_years : float option;
  is_hoa : bool;
  is_rental : bool;
  confidence_score : float;
}

let remove_thinking_tags (text : string) : string =
  let lower = String.lowercase_ascii text in
  let len = String.length text in
  let buf = Buffer.create len in
  let in_tag = ref None in
  let i = ref 0 in
  while !i < len do
    match !in_tag with
    | Some tag_name ->
        let close_tag = "</" ^ tag_name ^ ">" in
        let close_len = String.length close_tag in
        if !i + close_len <= len && String.lowercase_ascii (String.sub text !i close_len) = close_tag then begin
          in_tag := None;
          i := !i + close_len
        end else incr i
    | None ->
        if !i + 7 <= len && String.sub lower !i 7 = "<think>" then begin
          in_tag := Some "think";
          i := !i + 7
        end else if !i + 10 <= len && String.sub lower !i 10 = "<thinking>" then begin
          in_tag := Some "thinking";
          i := !i + 10
        end else if !i + 9 <= len && String.sub lower !i 9 = "<thought>" then begin
          in_tag := Some "thought";
          i := !i + 9
        end else begin
          Buffer.add_char buf text.[!i];
          incr i
        end
  done;
  Buffer.contents buf

let clean_json_response (raw_text : string) : string =
  if raw_text = "" then ""
  else
    let text = String.trim (remove_thinking_tags raw_text) in
    (* 1. Check markdown code blocks ```json ... ``` *)
    let code_blocks =
      let len = String.length text in
      let blocks = ref [] in
      let i = ref 0 in
      while !i < len do
        if !i + 2 < len && text.[!i] = '`' && text.[!i+1] = '`' && text.[!i+2] = '`' then begin
          let start_content =
            let rec find_nl j =
              if j >= len then j
              else if text.[j] = '\n' then j + 1
              else find_nl (j + 1)
            in
            find_nl (!i + 3)
          in
          let rec find_end j =
            if j + 2 >= len then len
            else if text.[j] = '`' && text.[j+1] = '`' && text.[j+2] = '`' then j
            else find_end (j + 1)
          in
          let end_content = find_end start_content in
          if end_content > start_content then begin
            let block = String.sub text start_content (end_content - start_content) in
            blocks := String.trim block :: !blocks;
            i := end_content + 3
          end else i := len
        end else incr i
      done;
      List.rev !blocks
    in
    let valid_block =
      List.find_map (fun block ->
        if String.starts_with ~prefix:"{" block && String.ends_with ~suffix:"}" block then
          match Json.parse block with
          | Ok _ -> Some block
          | Error _ -> None
        else None
      ) code_blocks
    in
    match valid_block with
    | Some b -> b
    | None ->
        (* 2. Balanced brace scanner *)
        let len = String.length text in
        let rec scan_from start_idx =
          if start_idx >= len then None
          else if text.[start_idx] <> '{' then scan_from (start_idx + 1)
          else
            let depth = ref 0 in
            let in_string = ref false in
            let escape = ref false in
            let found = ref None in
            let i = ref start_idx in
            while !i < len && !found = None do
              let c = text.[!i] in
              if !in_string then begin
                if !escape then escape := false
                else if c = '\\' then escape := true
                else if c = '"' then in_string := false
              end else begin
                if c = '"' then in_string := true
                else if c = '{' then incr depth
                else if c = '}' then begin
                  decr depth;
                  if !depth = 0 then
                    let candidate = String.trim (String.sub text start_idx (!i - start_idx + 1)) in
                    match Json.parse candidate with
                    | Ok _ -> found := Some candidate
                    | Error _ -> ()
                end
              end;
              incr i
            done;
            match !found with
            | Some cand -> Some cand
            | None -> scan_from (start_idx + 1)
        in
        match scan_from 0 with
        | Some valid_json -> valid_json
        | None ->
            (* 3. Fallback: first '{' and last '}' *)
            (match String.index_opt text '{', String.rindex_opt text '}' with
             | Some s_idx, Some e_idx when e_idx > s_idx ->
                 String.trim (String.sub text s_idx (e_idx - s_idx + 1))
             | _ -> text)

let format_chat_payload
    ?(config = default_config)
    ~(system_prompt : string)
    ~(user_content : string)
    () : string =
  let payload = Json.Object [
    ("model", Json.String config.model);
    ("messages", Json.Array [
      Json.Object [
        ("role", Json.String "system");
        ("content", Json.String system_prompt);
      ];
      Json.Object [
        ("role", Json.String "user");
        ("content", Json.String user_content);
      ];
    ]);
    ("temperature", Json.Number 0.0);
    ("response_format", Json.Object [
      ("type", Json.String "json_object");
    ]);
  ] in
  Json.to_string payload

let extract_zip_5 (s : string) : string =
  let len = String.length s in
  let rec find_digit idx =
    if idx + 4 >= len then s
    else
      let is_d i = s.[i] >= '0' && s.[i] <= '9' in
      if is_d idx && is_d (idx+1) && is_d (idx+2) && is_d (idx+3) && is_d (idx+4) then
        let before_ok = idx = 0 || not (is_d (idx - 1)) in
        let after_ok = idx + 5 >= len || not (is_d (idx + 5)) in
        if before_ok && after_ok then String.sub s idx 5
        else find_digit (idx + 1)
      else find_digit (idx + 1)
  in
  find_digit 0

let parse_property_extraction (json_str : string) : (property_extraction, string) result =
  let cleaned = clean_json_response json_str in
  match Json.parse cleaned with
  | Error e -> Error ("Failed to parse PropertyExtraction JSON: " ^ e ^ "\nCleaned payload: " ^ cleaned)
  | Ok ast ->
      let address = Json.get_string "address" ast |> Option.value ~default:"" in
      let raw_zip = Json.get_string "zip_code" ast |> Option.value ~default:"" in
      let zip_code = extract_zip_5 raw_zip in
      let property_type = Json.get_string "property_type" ast |> Option.value ~default:"Single-Family" in
      let roof_type = Json.get_string "roof_type" ast |> Option.value ~default:"Unknown" in
      let is_hoa = Json.get_bool "is_hoa" ast |> Option.value ~default:false in
      let is_rental = Json.get_bool "is_rental" ast |> Option.value ~default:false in
      let estimated_value = Json.get_float "estimated_value" ast in
      let bedrooms = Json.get_int "bedrooms" ast in
      let bathrooms = Json.get_float "bathrooms" ast in
      let sqft = Json.get_int "sqft" ast in
      let year_built = Json.get_int "year_built" ast in
      let description = Json.get_string "description" ast in
      let confidence_score = Json.get_float "confidence_score" ast |> Option.value ~default:1.0 in
      Ok {
        address;
        zip_code;
        property_type;
        roof_type;
        is_hoa;
        is_rental;
        estimated_value;
        bedrooms;
        bathrooms;
        sqft;
        year_built;
        description;
        confidence_score;
      }

let parse_county_permit_extraction (json_str : string) : (county_permit_extraction, string) result =
  let cleaned = clean_json_response json_str in
  match Json.parse cleaned with
  | Error e -> Error ("Failed to parse CountyPermitExtraction JSON: " ^ e ^ "\nCleaned payload: " ^ cleaned)
  | Ok ast ->
      let address = Json.get_string "address" ast |> Option.value ~default:"" in
      let apn = Json.get_string "apn" ast in
      let owner_name = Json.get_string "owner_name" ast in
      let assessed_value = Json.get_float "assessed_value" ast in
      let last_roof_permit_date = Json.get_string "last_roof_permit_date" ast in
      let roof_age_years = Json.get_float "roof_age_years" ast in
      let is_hoa = Json.get_bool "is_hoa" ast |> Option.value ~default:false in
      let is_rental = Json.get_bool "is_rental" ast |> Option.value ~default:false in
      let confidence_score = Json.get_float "confidence_score" ast |> Option.value ~default:1.0 in
      let permit_history =
        match Json.get_array "permit_history" ast with
        | Some arr -> List.map Types.permit_record_of_json arr
        | None -> []
      in
      Ok {
        address;
        apn;
        owner_name;
        assessed_value;
        last_roof_permit_date;
        permit_history;
        roof_age_years;
        is_hoa;
        is_rental;
        confidence_score;
      }

let call_model_chat (config : config) (system_prompt : string) (user_content : string) : (string, string) result =
  let url = Printf.sprintf "%s/chat/completions" (String.trim config.base_url) in
  let body = format_chat_payload ~config ~system_prompt ~user_content () in
  let headers = [
    ("Content-Type", "application/json");
    ("Authorization", Printf.sprintf "Bearer %s" config.api_key);
  ] in
  match Http_client.post ~headers ~body ~timeout:config.timeout url with
  | Error e -> Error ("LLM HTTP request failed: " ^ e)
  | Ok resp ->
      if resp.status_code < 200 || resp.status_code >= 300 then
        Error (Printf.sprintf "LLM inference returned HTTP %d: %s" resp.status_code resp.body)
      else
        match Json.parse resp.body with
        | Error e -> Error ("Failed to parse LLM response JSON: " ^ e ^ "\nRaw body: " ^ resp.body)
        | Ok ast ->
            let content_opt =
              match Json.get_array "choices" ast with
              | Some (first_choice :: _) ->
                  (match Json.get_field "message" first_choice with
                   | Some msg_obj -> Json.get_string "content" msg_obj
                   | None -> None)
              | _ -> None
            in
            match content_opt with
            | Some c -> Ok c
            | None -> Error "LLM response choices missing or empty"

let extract_property_details
    ?(config = default_config)
    (html_or_text : string) : (property_extraction, string) result =
  let system_prompt =
    "You are an expert real estate data extraction engine. " ^
    "Analyze the provided property text/HTML and return ONLY a valid JSON object matching this schema:\n" ^
    "{\n" ^
    "  \"address\": \"string (full street address)\",\n" ^
    "  \"zip_code\": \"string (5-digit zip)\",\n" ^
    "  \"property_type\": \"string (Single-Family, Condo, Multi-Family, Townhouse)\",\n" ^
    "  \"roof_type\": \"string (Victorian, Flat, Pitched, Mansard, Unknown)\",\n" ^
    "  \"is_hoa\": boolean,\n" ^
    "  \"is_rental\": boolean,\n" ^
    "  \"estimated_value\": number or null,\n" ^
    "  \"bedrooms\": integer or null,\n" ^
    "  \"bathrooms\": number or null,\n" ^
    "  \"sqft\": integer or null,\n" ^
    "  \"year_built\": integer or null,\n" ^
    "  \"description\": \"string summary or null\",\n" ^
    "  \"confidence_score\": number (0.0 to 1.0)\n" ^
    "}\n" ^
    "If a field cannot be determined, provide appropriate defaults (e.g. roof_type='Unknown', is_hoa=false)."
  in
  let truncated =
    if String.length html_or_text > 16000 then String.sub html_or_text 0 16000
    else html_or_text
  in
  let user_content = Printf.sprintf "Property Listing Content:\n\n%s" truncated in
  match call_model_chat config system_prompt user_content with
  | Error e -> Error e
  | Ok raw_resp -> parse_property_extraction raw_resp

let extract_county_permit_details
    ?(config = default_config)
    (html_or_text : string) : (county_permit_extraction, string) result =
  let system_prompt =
    "You are an expert municipal and county assessor data extraction engine. " ^
    "Analyze the provided assessor/permit records HTML or text and return ONLY a valid JSON object matching this schema:\n" ^
    "{\n" ^
    "  \"address\": \"string (full street address)\",\n" ^
    "  \"apn\": \"string or null (Assessor Parcel Number / Block and Lot)\",\n" ^
    "  \"owner_name\": \"string or null\",\n" ^
    "  \"assessed_value\": number or null,\n" ^
    "  \"last_roof_permit_date\": \"string (YYYY-MM-DD or year) or null\",\n" ^
    "  \"permit_history\": [\n" ^
    "    {\"permit_number\": \"string\", \"permit_type\": \"string\", \"description\": \"string\", \"issued_date\": \"string\", \"status\": \"string\"}\n" ^
    "  ],\n" ^
    "  \"roof_age_years\": number or null,\n" ^
    "  \"is_hoa\": boolean,\n" ^
    "  \"is_rental\": boolean,\n" ^
    "  \"confidence_score\": number (0.0 to 1.0)\n" ^
    "}\n" ^
    "Calculate roof_age_years if last_roof_permit_date or installation date is present."
  in
  let truncated =
    if String.length html_or_text > 16000 then String.sub html_or_text 0 16000
    else html_or_text
  in
  let user_content = Printf.sprintf "Assessor & Permit Portal Content:\n\n%s" truncated in
  match call_model_chat config system_prompt user_content with
  | Error e -> Error e
  | Ok raw_resp -> parse_county_permit_extraction raw_resp
