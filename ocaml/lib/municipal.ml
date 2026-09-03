(**
   municipal.ml - Scrapers and Table Extractors for SF Planning PIM and SF DBI Permit Tracking.
   Features:
     - Comprehensive multi-format date parser and normalizer (ISO 8601, US MM/DD/YYYY, YYYY-MM-DD, 4-digit years).
     - Roofing permit classification heuristics (reroof, tear-off, roof replace vs non-roof alterations).
     - DOM/HTML text cleaner and table extractor for municipal portal responses.
*)

open Types

let contains_substring (needle : string) (haystack : string) : bool =
  let n_len = String.length needle in
  let h_len = String.length haystack in
  if n_len = 0 then true
  else if n_len > h_len then false
  else
    let rec check i =
      if i + n_len > h_len then false
      else if String.sub haystack i n_len = needle then true
      else check (i + 1)
    in
    check 0

let month_of_string (s : string) : int option =
  match String.lowercase_ascii (String.trim s) with
  | "jan" | "january" -> Some 1
  | "feb" | "february" -> Some 2
  | "mar" | "march" -> Some 3
  | "apr" | "april" -> Some 4
  | "may" -> Some 5
  | "jun" | "june" -> Some 6
  | "jul" | "july" -> Some 7
  | "aug" | "august" -> Some 8
  | "sep" | "september" | "sept" -> Some 9
  | "oct" | "october" -> Some 10
  | "nov" | "november" -> Some 11
  | "dec" | "december" -> Some 12
  | _ -> None

let normalize_year (y : int) : int =
  if y < 100 then
    if y <= 40 then 2000 + y else 1900 + y
  else y

let is_valid_ymd (y : int) (m : int) (d : int) : bool =
  y >= 1800 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31

let normalize_date (raw_str : string) : string option =
  let s = String.trim raw_str in
  let s_lower = String.lowercase_ascii s in
  if s = "" ||
     s_lower = "n/a" || s_lower = "not available" || s_lower = "unknown" ||
     s_lower = "none" || s_lower = "null" || s_lower = "---" ||
     s_lower = "no_permit_on_file" || s_lower = "pending approval" ||
     s_lower = "no permits found" || s_lower = "pending" ||
     s_lower = "n/a - historic" then
    None
  else
    if String.length s >= 10 && s.[4] = '-' && s.[7] = '-' then
      (try
         let y = int_of_string (String.sub s 0 4) in
         let m = int_of_string (String.sub s 5 2) in
         let d = int_of_string (String.sub s 8 2) in
         if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
         else None
       with _ -> None)

    else if String.length s >= 10 && s.[4] = '/' && s.[7] = '/' then
      (try
         let y = int_of_string (String.sub s 0 4) in
         let m = int_of_string (String.sub s 5 2) in
         let d = int_of_string (String.sub s 8 2) in
         if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
         else None
       with _ -> None)

    else if String.length s >= 10 && s.[4] = '.' && s.[7] = '.' then
      (try
         let y = int_of_string (String.sub s 0 4) in
         let m = int_of_string (String.sub s 5 2) in
         let d = int_of_string (String.sub s 8 2) in
         if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
         else None
       with _ -> None)

    else if String.contains s '/' then
      (match String.split_on_char '/' s with
       | [m_str; d_str; y_str] ->
           (try
              let m = int_of_string (String.trim m_str) in
              let d = int_of_string (String.trim d_str) in
              let y = normalize_year (int_of_string (String.trim y_str)) in
              if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
              else None
            with _ -> None)
       | _ -> None)

    else if String.contains s '-' then
      (match String.split_on_char '-' s with
       | [p1; p2; p3] ->
           let p1 = String.trim p1 in
           let p2 = String.trim p2 in
           let p3 = String.trim p3 in
           (match month_of_string p2 with
            | Some m ->
                (try
                   let d = int_of_string p1 in
                   let y = normalize_year (int_of_string p3) in
                   if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
                   else None
                 with _ -> None)
            | None ->
                (try
                   let m = int_of_string p1 in
                   let d = int_of_string p2 in
                   let y = normalize_year (int_of_string p3) in
                   if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
                   else None
                 with _ -> None))
       | _ -> None)

    else
      let clean_commas = String.map (function ',' -> ' ' | c -> c) s in
      let tokens = List.filter (fun t -> t <> "") (String.split_on_char ' ' clean_commas) in
      match tokens with
      | [t1; t2; t3] ->
          (match month_of_string t1 with
           | Some m ->
               (try
                  let d = int_of_string t2 in
                  let y = normalize_year (int_of_string t3) in
                  if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
                  else None
                with _ -> None)
           | None ->
               (match month_of_string t2 with
                | Some m ->
                    (try
                       let d = int_of_string t1 in
                       let y = normalize_year (int_of_string t3) in
                       if is_valid_ymd y m d then Some (Printf.sprintf "%04d-%02d-%02d" y m d)
                       else None
                     with _ -> None)
                | None -> None))
      | _ ->
          let len = String.length s in
          let rec find_year idx =
            if idx + 3 >= len then None
            else
              let c0 = s.[idx] in
              let c1 = s.[idx + 1] in
              let c2 = s.[idx + 2] in
              let c3 = s.[idx + 3] in
              if c0 >= '0' && c0 <= '9' &&
                 c1 >= '0' && c1 <= '9' &&
                 c2 >= '0' && c2 <= '9' &&
                 c3 >= '0' && c3 <= '9' then
                let yr = ((Char.code c0 - 48) * 1000) +
                         ((Char.code c1 - 48) * 100) +
                         ((Char.code c2 - 48) * 10) +
                         (Char.code c3 - 48) in
                if yr >= 1800 && yr <= 2099 then Some (Printf.sprintf "%04d-01-01" yr)
                else find_year (idx + 1)
              else find_year (idx + 1)
          in
          find_year 0

let parse_date_year (raw_str : string) : int option =
  match normalize_date raw_str with
  | Some d when String.length d >= 4 ->
      (try Some (int_of_string (String.sub d 0 4)) with _ -> None)
  | _ -> None

let is_roof_replacement (description : string) : bool =
  let d = String.lowercase_ascii description in
  let keywords = [
    "reroof"; "re-roof"; "reroofing"; "re-roofing";
    "roof replacement"; "roof replace"; "replace roof"; "roofing replacement";
    "tear off"; "tear-off"; "new roof";
    "shingle replacement"; "shingle replace"; "replace shingles";
    "tar and gravel"; "flat roof replace"; "roof overlay";
    "torch down"; "built up roof"; "built-up roof";
  ] in
  List.exists (fun kw -> contains_substring kw d) keywords

let is_non_roof_alteration (description : string) : bool =
  let d = String.lowercase_ascii description in
  let keywords = [
    "solar inverter"; "solar panels"; "photovoltaic";
    "kitchen remodel"; "bathroom remodel"; "electrical service";
    "plumbing"; "seismic retrofit"; "window replacement";
    "drywall repair"; "furnace replacement"; "water heater";
    "ev charger"; "panel upgrade";
  ] in
  List.exists (fun kw -> contains_substring kw d) keywords

let decode_html_entities (s : string) : string =
  let len = String.length s in
  let buf = Buffer.create len in
  let rec loop i =
    if i >= len then Buffer.contents buf
    else if s.[i] = '&' then
      if i + 4 <= len && String.sub s i 4 = "&amp;" then (Buffer.add_char buf '&'; loop (i + 4))
      else if i + 3 <= len && String.sub s i 3 = "&lt;" then (Buffer.add_char buf '<'; loop (i + 3))
      else if i + 3 <= len && String.sub s i 3 = "&gt;" then (Buffer.add_char buf '>'; loop (i + 3))
      else if i + 5 <= len && String.sub s i 5 = "&quot;" then (Buffer.add_char buf '"'; loop (i + 5))
      else if i + 5 <= len && String.sub s i 5 = "&#39;" then (Buffer.add_char buf '\''; loop (i + 5))
      else if i + 5 <= len && String.sub s i 5 = "&nbsp;" then (Buffer.add_char buf ' '; loop (i + 5))
      else (Buffer.add_char buf '&'; loop (i + 1))
    else (Buffer.add_char buf s.[i]; loop (i + 1))
  in
  loop 0

let clean_dom_text
    ?(extra_selectors = [])
    ?(max_chars = 12000)
    (html : string) : string =
  let _ = extra_selectors in
  let len = String.length html in
  let buf = Buffer.create (min len max_chars) in
  let in_tag = ref false in
  let in_script = ref false in
  let in_style = ref false in
  let in_comment = ref false in
  let i = ref 0 in

  while !i < len do
    if !in_comment then
      if !i + 2 < len && html.[!i] = '-' && html.[!i+1] = '-' && html.[!i+2] = '>' then
        (in_comment := false; i := !i + 3)
      else incr i
    else if !in_script then
      if !i + 8 < len && String.lowercase_ascii (String.sub html !i 9) = "</script>" then
        (in_script := false; i := !i + 9)
      else incr i
    else if !in_style then
      if !i + 7 < len && String.lowercase_ascii (String.sub html !i 8) = "</style>" then
        (in_style := false; i := !i + 8)
      else incr i
    else if !in_tag then
      if html.[!i] = '>' then
        (in_tag := false; Buffer.add_char buf ' '; incr i)
      else incr i
    else
      if !i + 3 < len && html.[!i] = '<' && html.[!i+1] = '!' && html.[!i+2] = '-' && html.[!i+3] = '-' then
        (in_comment := true; i := !i + 4)
      else if !i + 6 < len && String.lowercase_ascii (String.sub html !i 7) = "<script" then
        (in_script := true; i := !i + 7)
      else if !i + 5 < len && String.lowercase_ascii (String.sub html !i 6) = "<style" then
        (in_style := true; i := !i + 6)
      else if html.[!i] = '<' then
        (in_tag := true; incr i)
      else
        (Buffer.add_char buf html.[!i]; incr i)
  done;

  let raw_text = decode_html_entities (Buffer.contents buf) in
  let lines = String.split_on_char '\n' raw_text in
  let cleaned_lines = List.filter_map (fun l ->
    let words = List.filter (fun w -> w <> "") (String.split_on_char ' ' (String.trim l)) in
    if words = [] then None
    else Some (String.concat " " words)
  ) lines in
  let result = String.concat "\n" cleaned_lines in
  if String.length result > max_chars then String.sub result 0 max_chars
  else result

let extract_pim_details (text_or_html : string) :
    (string * string option * float option * bool option * bool option) =
  let text = clean_dom_text text_or_html in
  let address =
    match String.split_on_char '\n' text with
    | h :: _ -> String.trim h
    | [] -> ""
  in
  let apn =
    let rec find_apn lines =
      match lines with
      | [] -> None
      | line :: rest ->
          let l_lower = String.lowercase_ascii line in
          if contains_substring "apn:" l_lower || contains_substring "parcel:" l_lower || contains_substring "block/lot:" l_lower then
            let parts = String.split_on_char ':' line in
            match parts with
            | _ :: apn_val :: _ -> Some (String.trim apn_val)
            | _ -> find_apn rest
          else find_apn rest
    in
    find_apn (String.split_on_char '\n' text)
  in
  let assessed_val =
    let rec find_val lines =
      match lines with
      | [] -> None
      | line :: rest ->
          let l_lower = String.lowercase_ascii line in
          if contains_substring "assessed value" l_lower || contains_substring "total value" l_lower then
            let cleaned_digits =
              let b = Buffer.create 16 in
              String.iter (function '0'..'9' | '.' as c -> Buffer.add_char b c | _ -> ()) line;
              Buffer.contents b
            in
            (try Some (float_of_string cleaned_digits) with _ -> find_val rest)
          else find_val rest
    in
    find_val (String.split_on_char '\n' text)
  in
  let is_hoa =
    let t_lower = String.lowercase_ascii text in
    if contains_substring "condo" t_lower || contains_substring "hoa" t_lower || contains_substring "homeowners association" t_lower then
      Some true
    else Some false
  in
  let is_rental =
    let t_lower = String.lowercase_ascii text in
    if contains_substring "rental" t_lower || contains_substring "tenant occupied" t_lower || contains_substring "commercial residential" t_lower then
      Some true
    else Some false
  in
  (address, apn, assessed_val, is_hoa, is_rental)

let extract_dbi_permits (text_or_html : string) : Types.permit_record list =
  let text = clean_dom_text text_or_html in
  let lines = String.split_on_char '\n' text in
  let permits = ref [] in
  List.iter (fun line ->
    let l_trim = String.trim line in
    if contains_substring "permit" (String.lowercase_ascii l_trim) ||
       (String.length l_trim >= 6 && l_trim.[0] >= '0' && l_trim.[0] <= '9') then
      let is_rep = is_roof_replacement l_trim in
      let date_opt = normalize_date l_trim in
      let yr = match date_opt with Some d -> parse_date_year d | None -> None in
      let p : Types.permit_record = {
        permit_number = Printf.sprintf "DBI-%04d" (List.length !permits + 1);
        permit_type = Some "Building Permit";
        description = l_trim;
        date_filed = date_opt;
        date_issued = date_opt;
        status = Some "Completed";
        year = yr;
        is_roof_replacement = is_rep;
        cost = None;
      } in
      permits := p :: !permits
  ) lines;
  List.rev !permits
