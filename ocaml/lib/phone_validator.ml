type area_code_tier =
  | SF_Primary
  | Bay_Area
  | Valid_US
  | Invalid_Area

type validation_error =
  | EmptyNumber
  | InvalidLength of int
  | InvalidCountryCode of string
  | InvalidNpaStartDigit of char
  | InvalidNxxStartDigit of char
  | ReservedN11Code of string
  | TollFreeAreaCode of string
  | PremiumAreaCode of string
  | Fictitious555Number of string
  | InvalidPrefix000or111 of string
  | RepeatingDigits of string
  | SequentialDigits of string
  | InvalidAreaCode of string
  | MaliciousFormulaPrefix of string

type validated_phone = {
  raw : string;
  digits : string;
  npa : string;
  nxx : string;
  station : string;
  canonical : string;
  tier : area_code_tier;
}

let sf_primary_codes = ["415"; "628"]

let bay_area_codes = ["510"; "341"; "650"; "408"; "669"; "925"; "707"; "369"; "831"]

let toll_free_codes = ["800"; "888"; "877"; "866"; "855"; "844"; "833"]

let premium_codes = ["900"; "976"]

let get_area_code_tier (npa : string) : area_code_tier =
  if String.length npa <> 3 then Invalid_Area
  else if npa.[0] < '2' || npa.[0] > '9' then Invalid_Area
  else if npa.[1] = '1' && npa.[2] = '1' then Invalid_Area
  else if npa.[1] = '9' then Invalid_Area
  else if npa = "555" then Invalid_Area
  else if List.mem npa toll_free_codes then Invalid_Area
  else if List.mem npa premium_codes then Invalid_Area
  else if List.mem npa sf_primary_codes then SF_Primary
  else if List.mem npa bay_area_codes then Bay_Area
  else Valid_US

let is_valid_npa (npa : string) : bool =
  match get_area_code_tier npa with
  | Invalid_Area -> false
  | _ -> true

let is_repeating_10 (digits : string) : bool =
  let len = String.length digits in
  if len <> 10 then false
  else String.make 10 digits.[0] = digits

let is_repeating_local7 (digits : string) : bool =
  let len = String.length digits in
  if len <> 10 then false
  else
    let local = String.sub digits 3 7 in
    String.make 7 local.[0] = local

let is_repeating_station (station : string) : bool =
  station = "0000" || station = "1111"

let sequential_10_patterns = [
  "1234567890";
  "0123456789";
  "9876543210";
  "8765432109";
]

let sequential_local7_patterns = [
  "1234567";
  "2345678";
  "3456789";
  "4567890";
  "7654321";
  "8765432";
  "9876543";
  "0987654";
]

let is_sequential_number (digits : string) : bool =
  let len = String.length digits in
  if len <> 10 then false
  else if List.mem digits sequential_10_patterns then true
  else
    let local7 = String.sub digits 3 7 in
    List.mem local7 sequential_local7_patterns

let is_dummy_number (digits_or_raw : string) : bool =
  let buf = Buffer.create (String.length digits_or_raw) in
  String.iter (fun c ->
    if c >= '0' && c <= '9' then Buffer.add_char buf c
  ) digits_or_raw;
  let raw_digits = Buffer.contents buf in
  let digits =
    if String.length raw_digits = 11 && raw_digits.[0] = '1' then
      String.sub raw_digits 1 10
    else if String.length raw_digits = 13 && String.starts_with ~prefix:"001" raw_digits then
      String.sub raw_digits 3 10
    else
      raw_digits
  in
  if String.length digits <> 10 then true
  else
    let npa = String.sub digits 0 3 in
    let nxx = String.sub digits 3 3 in
    let station = String.sub digits 6 4 in
    if npa.[0] < '2' || npa.[0] > '9' then true
    else if nxx.[0] < '2' || nxx.[0] > '9' then true
    else if npa = "000" || npa = "111" || nxx = "000" || nxx = "111" then true
    else if (npa.[1] = '1' && npa.[2] = '1') || (nxx.[1] = '1' && nxx.[2] = '1') then true
    else if npa = "555" || nxx = "555" then true
    else if List.mem npa toll_free_codes || List.mem npa premium_codes then true
    else if is_repeating_10 digits || is_repeating_local7 digits || is_repeating_station station then true
    else if is_sequential_number digits then true
    else false

let sanitize_and_normalize (raw : string) : (validated_phone, validation_error) result =
  let trimmed = String.trim raw in
  if trimmed = "" then Error EmptyNumber
  else if trimmed.[0] = '=' || trimmed.[0] = '@' || trimmed.[0] = '\t' || trimmed.[0] = '\r' then
    Error (MaliciousFormulaPrefix raw)
  else if trimmed.[0] = '+' && (String.length trimmed > 1 && trimmed.[1] <> '1' && trimmed.[1] <> ' ' && trimmed.[1] <> '(') then
    Error (InvalidCountryCode raw)
  else
    let buf = Buffer.create (String.length trimmed) in
    String.iter (fun c ->
      if c >= '0' && c <= '9' then Buffer.add_char buf c
    ) trimmed;
    let raw_digits = Buffer.contents buf in
    let digits_res =
      if String.length raw_digits = 13 && String.starts_with ~prefix:"001" raw_digits then
        Ok (String.sub raw_digits 3 10)
      else if String.length raw_digits = 11 then
        if raw_digits.[0] = '1' then Ok (String.sub raw_digits 1 10)
        else Error (InvalidCountryCode (String.sub raw_digits 0 2))
      else if String.length raw_digits = 10 then
        Ok raw_digits
      else
        Error (InvalidLength (String.length raw_digits))
    in
    match digits_res with
    | Error err -> Error err
    | Ok digits ->
        let npa = String.sub digits 0 3 in
        let nxx = String.sub digits 3 3 in
        let station = String.sub digits 6 4 in
        if npa = "000" || npa = "111" then Error (InvalidPrefix000or111 npa)
        else if nxx = "000" || nxx = "111" then Error (InvalidPrefix000or111 nxx)
        else if npa.[0] < '2' || npa.[0] > '9' then Error (InvalidNpaStartDigit npa.[0])
        else if nxx.[0] < '2' || nxx.[0] > '9' then Error (InvalidNxxStartDigit nxx.[0])
        else if npa.[1] = '1' && npa.[2] = '1' then Error (ReservedN11Code npa)
        else if nxx.[1] = '1' && nxx.[2] = '1' then Error (ReservedN11Code nxx)
        else if List.mem npa toll_free_codes then Error (TollFreeAreaCode npa)
        else if List.mem npa premium_codes then Error (PremiumAreaCode npa)
        else if npa = "555" || nxx = "555" then Error (Fictitious555Number digits)
        else if is_repeating_10 digits || is_repeating_local7 digits || is_repeating_station station then
          Error (RepeatingDigits digits)
        else if is_sequential_number digits then Error (SequentialDigits digits)
        else
          let tier = get_area_code_tier npa in
          if tier = Invalid_Area then Error (InvalidAreaCode npa)
          else
            let canonical = Printf.sprintf "%s-%s-%s" npa nxx station in
            Ok { raw; digits; npa; nxx; station; canonical; tier }

let format_canonical (vp : validated_phone) : string =
  vp.canonical

let is_valid_phone (s : string) : bool =
  match sanitize_and_normalize s with
  | Ok _ -> true
  | Error _ -> false

let normalize_to_canonical (s : string) : string option =
  match sanitize_and_normalize s with
  | Ok vp -> Some vp.canonical
  | Error _ -> None

let is_boundary_isolated (s : string) (start_pos : int) (end_pos : int) : bool =
  let prev_ok =
    if start_pos = 0 then true
    else
      let c = s.[start_pos - 1] in
      not ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
  in
  let next_ok =
    if end_pos >= String.length s then true
    else
      let c = s.[end_pos] in
      not ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
  in
  prev_ok && next_ok

let extract_valid_phones_from_text (text : string) : validated_phone list =
  let tel_regex = Str.regexp_case_fold "href=[\"']tel:\\([^\"'> ]+\\)[\"']" in
  let rec extract_tel pos acc =
    try
      let _ = Str.search_forward tel_regex text pos in
      let tel_target = Str.matched_group 1 text in
      extract_tel (Str.match_end ()) (tel_target :: acc)
    with Not_found -> List.rev acc
  in
  let tel_candidates = extract_tel 0 [] in
  let phone_regex = Str.regexp "\\([+]?1[-. ]\\)?[(]?[2-9][0-9][0-9][)]?[-. ]?[2-9][0-9][0-9][-. ]?[0-9][0-9][0-9][0-9]" in
  let rec extract_text pos acc =
    try
      let idx = Str.search_forward phone_regex text pos in
      let matched = Str.matched_string text in
      let mend = Str.match_end () in
      let new_acc =
        if is_boundary_isolated text idx mend then matched :: acc
        else acc
      in
      extract_text mend new_acc
    with Not_found -> List.rev acc
  in
  let text_candidates = extract_text 0 [] in
  let all_candidates = tel_candidates @ text_candidates in
  let rec process_candidates seen = function
    | [] -> []
    | cand :: rest ->
        (match sanitize_and_normalize cand with
        | Ok vp ->
            if List.mem vp.canonical seen then process_candidates seen rest
            else vp :: process_candidates (vp.canonical :: seen) rest
        | Error _ -> process_candidates seen rest)
  in
  process_candidates [] all_candidates
