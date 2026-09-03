let url_encode (s : string) : string =
  let buf = Buffer.create (String.length s * 3) in
  String.iter (fun c ->
    match c with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' | '.' | '~' ->
        Buffer.add_char buf c
    | ' ' ->
        Buffer.add_char buf '+'
    | _ ->
        Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code c))
  ) s;
  Buffer.contents buf

let is_synthesized_name (name : string) : bool =
  String.starts_with ~prefix:"Owner Occupant" name ||
  String.starts_with ~prefix:"Parcel " name ||
  String.ends_with ~suffix:"Owner" name

let build_search_url (lead : Types.raw_lead) : string =
  let query =
    match lead.owner_name with
    | Some n when not (is_synthesized_name n) && String.trim n <> "" ->
        Printf.sprintf "\"%s\" \"%s\" %s phone" n lead.address lead.zip_code
    | _ ->
        Printf.sprintf "\"%s\" San Francisco %s phone" lead.address lead.zip_code
  in
  "https://html.duckduckgo.com/html/?q=" ^ url_encode query

let extract_phones_from_html (html : string) : string list =
  let valid_phones = Phone_validator.extract_valid_phones_from_text html in
  let tier_rank = function
    | Phone_validator.SF_Primary -> 1
    | Phone_validator.Bay_Area -> 2
    | Phone_validator.Valid_US -> 3
    | Phone_validator.Invalid_Area -> 4
  in
  let sorted =
    List.stable_sort (fun (a : Phone_validator.validated_phone) (b : Phone_validator.validated_phone) ->
      compare (tier_rank a.tier) (tier_rank b.tier)
    ) valid_phones
  in
  List.map (fun (vp : Phone_validator.validated_phone) -> vp.canonical) sorted

let extract_phone_number ?search_url (lead : Types.raw_lead) : (Types.raw_lead, string) result =
  let url =
    match search_url with
    | Some u -> u
    | None -> build_search_url lead
  in
  let headers = [
    ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
  ] in
  match Http_client.get ~headers ~timeout:5.0 url with
  | Ok resp ->
      if resp.status_code = 200 then
        let phones = extract_phones_from_html resp.body in
        match phones with
        | hd :: _ -> Ok { lead with phone_number = Some hd }
        | [] -> Ok { lead with phone_number = None }
      else
        Error (Printf.sprintf "OSINT search failed with status %d" resp.status_code)
  | Error e -> Error ("OSINT network error: " ^ e)
