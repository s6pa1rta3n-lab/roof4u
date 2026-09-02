let build_search_url (lead : Types.raw_lead) : string =
  let owner_name = match lead.owner_name with Some n -> n | None -> "" in
  let query = Printf.sprintf "\"%s\" \"%s\" %s phone" owner_name lead.address lead.zip_code in
  let encoded_query = Str.global_replace (Str.regexp " ") "+" query in
  "https://html.duckduckgo.com/html/?q=" ^ encoded_query

let extract_phones_from_html (html : string) : string list =
  (* Basic regex to match US phone numbers (e.g., (415) 555-1234 or 415-555-1234) *)
  let phone_regex = Str.regexp "\\([0-9][0-9][0-9]\\)[- .]?\\([0-9][0-9][0-9]\\)[- .]?\\([0-9][0-9][0-9][0-9]\\)" in
  let rec extract_loop pos acc =
    try
      let _ = Str.search_forward phone_regex html pos in
      let matched_string = Str.matched_string html in
      extract_loop (Str.match_end ()) (matched_string :: acc)
    with Not_found -> List.rev acc
  in
  let raw_phones = extract_loop 0 [] in
  (* Filter out dummy 555 numbers and common dates masquerading as phones *)
  List.filter (fun p -> 
    let digits_only = Str.global_replace (Str.regexp "[^0-9]") "" p in
    String.length digits_only = 10 && not (String.starts_with ~prefix:"555" (String.sub digits_only 3 3))
  ) raw_phones

let extract_phone_number (lead : Types.raw_lead) : (Types.raw_lead, string) result =
  let url = build_search_url lead in
  let headers = [("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")] in
  match Http_client.get ~headers ~timeout:10.0 url with
  | Ok resp ->
      if resp.status_code = 200 then
        let phones = extract_phones_from_html resp.body in
        match phones with
        | hd :: _ -> Ok { lead with phone_number = Some hd }
        | [] -> Ok { lead with phone_number = None }
      else
        Error (Printf.sprintf "OSINT search failed with status %d" resp.status_code)
  | Error e -> Error ("OSINT network error: " ^ e)
