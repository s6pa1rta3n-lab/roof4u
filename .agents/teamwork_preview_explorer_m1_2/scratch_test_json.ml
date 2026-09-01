(**
   scratch_test_json.ml - Interactive test harness for json.ml prototype
*)

type t =
  | Null
  | Bool of bool
  | Number of float
  | String of string
  | Array of t list
  | Object of (string * t) list

type parser_state = {
  src : string;
  len : int;
  mutable pos : int;
  mutable line : int;
  mutable col : int;
  max_depth : int;
  mutable depth : int;
}

exception Parse_error of string

let fail state msg =
  let err = Printf.sprintf "JSON parse error at line %d, col %d (byte %d): %s"
    state.line state.col state.pos msg in
  raise (Parse_error err)

let peek state =
  if state.pos < state.len then Some state.src.[state.pos]
  else None

let advance state =
  if state.pos < state.len then begin
    if state.src.[state.pos] = '\n' then begin
      state.line <- state.line + 1;
      state.col <- 1
    end else begin
      state.col <- state.col + 1
    end;
    state.pos <- state.pos + 1
  end

let rec skip_ws state =
  match peek state with
  | Some (' ' | '\t' | '\r' | '\n') ->
      advance state;
      skip_ws state
  | _ -> ()

let expect_char state c msg =
  match peek state with
  | Some ch when ch = c -> advance state
  | Some ch -> fail state (Printf.sprintf "%s (expected '%c', found '%c')" msg c ch)
  | None -> fail state (Printf.sprintf "%s (expected '%c', reached EOF)" msg c)

let hex_digit_val = function
  | '0' .. '9' as c -> Char.code c - Char.code '0'
  | 'a' .. 'f' as c -> 10 + Char.code c - Char.code 'a'
  | 'A' .. 'F' as c -> 10 + Char.code c - Char.code 'A'
  | _ -> -1

let parse_hex4 state =
  let cp = ref 0 in
  for _ = 1 to 4 do
    match peek state with
    | Some c ->
        let v = hex_digit_val c in
        if v < 0 then fail state "Invalid hexadecimal digit in \\u escape"
        else begin
          cp := (!cp lsl 4) lor v;
          advance state
        end
    | None -> fail state "Unexpected EOF in \\u escape"
  done;
  !cp

let encode_utf8 buf cp =
  if cp < 0 then ()
  else if cp <= 0x7F then
    Buffer.add_char buf (Char.chr cp)
  else if cp <= 0x7FF then begin
    Buffer.add_char buf (Char.chr (0xC0 lor (cp lsr 6)));
    Buffer.add_char buf (Char.chr (0x80 lor (cp land 0x3F)))
  end else if cp <= 0xFFFF then begin
    Buffer.add_char buf (Char.chr (0xE0 lor (cp lsr 12)));
    Buffer.add_char buf (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
    Buffer.add_char buf (Char.chr (0x80 lor (cp land 0x3F)))
  end else if cp <= 0x10FFFF then begin
    Buffer.add_char buf (Char.chr (0xF0 lor (cp lsr 18)));
    Buffer.add_char buf (Char.chr (0x80 lor ((cp lsr 12) land 0x3F)));
    Buffer.add_char buf (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
    Buffer.add_char buf (Char.chr (0x80 lor (cp land 0x3F)))
  end else begin
    (* Replacement character U+FFFD *)
    Buffer.add_string buf "\xEF\xBF\xBD"
  end

let parse_string state =
  expect_char state '"' "Expected opening quote for string";
  let buf = Buffer.create 32 in
  let rec loop () =
    match peek state with
    | None -> fail state "Unterminated string literal (reached EOF)"
    | Some '"' ->
        advance state;
        Buffer.contents buf
    | Some '\\' ->
        advance state;
        (match peek state with
         | None -> fail state "Unexpected EOF after escape backslash"
         | Some '"' -> Buffer.add_char buf '"'; advance state; loop ()
         | Some '\\' -> Buffer.add_char buf '\\'; advance state; loop ()
         | Some '/' -> Buffer.add_char buf '/'; advance state; loop ()
         | Some 'b' -> Buffer.add_char buf '\b'; advance state; loop ()
         | Some 'f' -> Buffer.add_char buf '\012'; advance state; loop ()
         | Some 'n' -> Buffer.add_char buf '\n'; advance state; loop ()
         | Some 'r' -> Buffer.add_char buf '\r'; advance state; loop ()
         | Some 't' -> Buffer.add_char buf '\t'; advance state; loop ()
         | Some 'u' ->
             advance state;
             let cp = parse_hex4 state in
             if cp >= 0xD800 && cp <= 0xDBFF then begin
               (* High surrogate, check for low surrogate \uDC00..\uDFFF *)
               if state.pos + 1 < state.len && state.src.[state.pos] = '\\' && state.src.[state.pos + 1] = 'u' then begin
                 advance state; advance state;
                 let low = parse_hex4 state in
                 if low >= 0xDC00 && low <= 0xDFFF then
                   let full_cp = 0x10000 + ((cp - 0xD800) lsl 10) + (low - 0xDC00) in
                   encode_utf8 buf full_cp
                 else begin
                   encode_utf8 buf 0xFFFD;
                   encode_utf8 buf low
                 end
               end else begin
                 encode_utf8 buf 0xFFFD
               end
             end else begin
               encode_utf8 buf cp
             end;
             loop ()
         | Some c -> fail state (Printf.sprintf "Invalid escape sequence '\\%c'" c))
    | Some c when Char.code c < 0x20 ->
        fail state (Printf.sprintf "Unescaped control character (ASCII %d) in string literal" (Char.code c))
    | Some c ->
        Buffer.add_char buf c;
        advance state;
        loop ()
  in
  loop ()

let parse_number state =
  let start_pos = state.pos in
  (* Optional minus *)
  if peek state = Some '-' then advance state;
  (* Integer part *)
  (match peek state with
   | Some '0' ->
       advance state;
       (* Next char cannot be a digit (leading zero forbidden in RFC 8259) *)
       (match peek state with
        | Some ('0' .. '9') -> fail state "Leading zeros in numbers are not allowed"
        | _ -> ())
   | Some ('1' .. '9') ->
       advance state;
       while match peek state with Some ('0' .. '9') -> true | _ -> false do
         advance state
       done
   | Some _ -> fail state "Invalid number format (expected digits)"
   | None -> fail state "Unexpected EOF while reading number");
  (* Optional fraction *)
  if peek state = Some '.' then begin
    advance state;
    match peek state with
    | Some ('0' .. '9') ->
        advance state;
        while match peek state with Some ('0' .. '9') -> true | _ -> false do
          advance state
        done
    | _ -> fail state "Decimal point must be followed by at least one digit"
  end;
  (* Optional exponent *)
  (match peek state with
   | Some ('e' | 'E') ->
       advance state;
       (match peek state with
        | Some ('+' | '-') -> advance state
        | _ -> ());
       (match peek state with
        | Some ('0' .. '9') ->
            advance state;
            while match peek state with Some ('0' .. '9') -> true | _ -> false do
              advance state
            done
        | _ -> fail state "Exponent must be followed by at least one digit")
   | _ -> ());
  let num_str = String.sub state.src start_pos (state.pos - start_pos) in
  try Number (float_of_string num_str)
  with _ -> fail state (Printf.sprintf "Failed to parse float: %s" num_str)

let parse_literal state expected result =
  let elen = String.length expected in
  if state.pos + elen <= state.len && String.sub state.src state.pos elen = expected then begin
    for _ = 1 to elen do advance state done;
    result
  end else
    fail state (Printf.sprintf "Expected literal '%s'" expected)

let rec parse_value state =
  skip_ws state;
  match peek state with
  | None -> fail state "Unexpected end of input, expected JSON value"
  | Some 'n' -> parse_literal state "null" Null
  | Some 't' -> parse_literal state "true" (Bool true)
  | Some 'f' -> parse_literal state "false" (Bool false)
  | Some '"' -> String (parse_string state)
  | Some ('-' | '0' .. '9') -> parse_number state
  | Some '[' -> parse_array state
  | Some '{' -> parse_object state
  | Some c -> fail state (Printf.sprintf "Unexpected character '%c', expected JSON value" c)

and parse_array state =
  if state.depth >= state.max_depth then
    fail state (Printf.sprintf "Maximum JSON nesting depth (%d) exceeded" state.max_depth);
  state.depth <- state.depth + 1;
  expect_char state '[' "Expected '[' to start array";
  skip_ws state;
  let items =
    if peek state = Some ']' then begin
      advance state;
      []
    end else begin
      let rec loop acc =
        let v = parse_value state in
        skip_ws state;
        match peek state with
        | Some ',' ->
            advance state;
            skip_ws state;
            if peek state = Some ']' then
              fail state "Trailing comma is not allowed in array"
            else
              loop (v :: acc)
        | Some ']' ->
            advance state;
            List.rev (v :: acc)
        | Some c -> fail state (Printf.sprintf "Expected ',' or ']' in array, found '%c'" c)
        | None -> fail state "Unterminated array (reached EOF)"
      in
      loop []
    end
  in
  state.depth <- state.depth - 1;
  Array items

and parse_object state =
  if state.depth >= state.max_depth then
    fail state (Printf.sprintf "Maximum JSON nesting depth (%d) exceeded" state.max_depth);
  state.depth <- state.depth + 1;
  expect_char state '{' "Expected '{' to start object";
  skip_ws state;
  let kvs =
    if peek state = Some '}' then begin
      advance state;
      []
    end else begin
      let rec loop acc =
        skip_ws state;
        if peek state <> Some '"' then
          fail state "Expected string key in object";
        let key = parse_string state in
        skip_ws state;
        expect_char state ':' "Expected ':' after object key";
        skip_ws state;
        let v = parse_value state in
        skip_ws state;
        match peek state with
        | Some ',' ->
            advance state;
            skip_ws state;
            if peek state = Some '}' then
              fail state "Trailing comma is not allowed in object"
            else
              loop ((key, v) :: acc)
        | Some '}' ->
            advance state;
            List.rev ((key, v) :: acc)
        | Some c -> fail state (Printf.sprintf "Expected ',' or '}' in object, found '%c'" c)
        | None -> fail state "Unterminated object (reached EOF)"
      in
      loop []
    end
  in
  state.depth <- state.depth - 1;
  Object kvs

let parse ?(max_depth = 1024) src =
  let state = {
    src;
    len = String.length src;
    pos = 0;
    line = 1;
    col = 1;
    max_depth;
    depth = 0;
  } in
  try
    skip_ws state;
    if state.pos >= state.len then
      Error "Empty JSON input"
    else begin
      let v = parse_value state in
      skip_ws state;
      if state.pos < state.len then
        Error (Printf.sprintf "Unexpected trailing characters at line %d, col %d (byte %d)" state.line state.col state.pos)
      else
        Ok v
    end
  with
  | Parse_error msg -> Error msg
  | e -> Error (Printexc.to_string e)

let escape_json_string s =
  let b = Buffer.create (String.length s + 16) in
  Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\b' -> Buffer.add_string b "\\b"
    | '\012' -> Buffer.add_string b "\\f"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c ->
        let code = Char.code c in
        if code < 0x20 then
          Buffer.add_string b (Printf.sprintf "\\u%04x" code)
        else
          Buffer.add_char b c
  ) s;
  Buffer.add_char b '"';
  Buffer.contents b

let json_of_float f =
  if Float.is_nan f || Float.is_infinite f then "null"
  else
    let s = string_of_float f in
    let len = String.length s in
    if len > 0 && s.[len - 1] = '.' then s ^ "0"
    else s

let rec to_string = function
  | Null -> "null"
  | Bool true -> "true"
  | Bool false -> "false"
  | Number f -> json_of_float f
  | String s -> escape_json_string s
  | Array items ->
      "[" ^ (String.concat "," (List.map to_string items)) ^ "]"
  | Object kvs ->
      let pair (k, v) = escape_json_string k ^ ":" ^ to_string v in
      "{" ^ (String.concat "," (List.map pair kvs)) ^ "}"

let rec to_string_pretty ?(indent = 2) t =
  let ind lvl = String.make (lvl * indent) ' ' in
  let rec pp lvl = function
    | Null -> "null"
    | Bool true -> "true"
    | Bool false -> "false"
    | Number f -> json_of_float f
    | String s -> escape_json_string s
    | Array [] -> "[]"
    | Array items ->
        let inner =
          items
          |> List.map (fun x -> ind (lvl + 1) ^ pp (lvl + 1) x)
          |> String.concat ",\n"
        in
        "[\n" ^ inner ^ "\n" ^ ind lvl ^ "]"
    | Object [] -> "{}"
    | Object kvs ->
        let inner =
          kvs
          |> List.map (fun (k, v) ->
               ind (lvl + 1) ^ escape_json_string k ^ ": " ^ pp (lvl + 1) v)
          |> String.concat ",\n"
        in
        "{\n" ^ inner ^ "\n" ^ ind lvl ^ "}"
  in
  pp 0 t

(* Safe Accessors *)
let get_field key = function
  | Object kvs -> List.assoc_opt key kvs
  | _ -> None

let get_string key json =
  match get_field key json with
  | Some (String s) -> Some s
  | _ -> None

let get_float key json =
  match get_field key json with
  | Some (Number f) -> Some f
  | _ -> None

let get_int key json =
  match get_field key json with
  | Some (Number f) -> Some (int_of_float f)
  | _ -> None

let get_bool key json =
  match get_field key json with
  | Some (Bool b) -> Some b
  | _ -> None

let get_array key json =
  match get_field key json with
  | Some (Array arr) -> Some arr
  | _ -> None

let get_object key json =
  match get_field key json with
  | Some (Object obj) -> Some obj
  | _ -> None

(* Verification tests *)
let () =
  let test name input expected_valid =
    match parse input with
    | Ok v ->
        if not expected_valid then
          Printf.printf "[FAIL] %s: Expected parse failure but got Ok: %s\n" name (to_string v)
        else
          Printf.printf "[PASS] %s: parsed successfully -> %s\n" name (to_string v)
    | Error err ->
        if expected_valid then
          Printf.printf "[FAIL] %s: Expected parse success but got Error: %s\n" name err
        else
          Printf.printf "[PASS] %s: correctly rejected with error: %s\n" name err
  in

  print_endline "=== Testing JSON Parser ===";
  test "empty object" "{}" true;
  test "empty array" "[]" true;
  test "simple object" "{\"name\": \"Roo4u\", \"active\": true, \"count\": 42, \"ratio\": 3.14159}" true;
  test "nested structures" "{\"lead\": {\"address\": \"2223 Pacific Ave\", \"permits\": [{\"id\": 1, \"type\": \"reroof\"}]}}" true;
  test "escaped string" "{\"quote\": \"He said \\\"Hello, World!\\\" \\n \\t \\\\\"}" true;
  test "unicode escape BMP" "{\"unicode\": \"\\u0041\\u0042\\u0043\"}" true;
  test "unicode surrogate pair (emoji)" "{\"emoji\": \"\\uD83D\\uDE00\"}" true;
  test "negative float and exp" "{\"vals\": [-0.5, -42, 1e5, 2.5E-3, -1.2e+4]}" true;
  test "trailing comma in array" "[1, 2, 3,]" false;
  test "trailing comma in object" "{\"a\": 1,}" false;
  test "leading zero number" "{\"bad\": 0123}" false;
  test "unclosed string" "{\"bad\": \"hello}" false;
  test "unclosed array" "[1, 2, 3" false;
  test "unclosed object" "{\"a\": 1" false;
  test "missing colon" "{\"a\" 1}" false;
  test "trailing garbage" "{\"a\": 1} trailing" false;
  test "empty string" "" false;

  (* Test round-trip serialization and typed accessors *)
  let json_str = "{\"address\": \"2223 Pacific Ave\", \"estimated_value\": 3500000.0, \"year_built\": 1900, \"is_hoa\": false, \"tags\": [\"victorian\", \"residential\"], \"meta\": {\"zone\": \"RH-2\"}}" in
  match parse json_str with
  | Error e -> Printf.printf "[FAIL] Failed to parse valid lead JSON: %s\n" e
  | Ok ast ->
      assert (get_string "address" ast = Some "2223 Pacific Ave");
      assert (get_float "estimated_value" ast = Some 3500000.0);
      assert (get_int "year_built" ast = Some 1900);
      assert (get_bool "is_hoa" ast = Some false);
      assert (match get_array "tags" ast with Some [String "victorian"; String "residential"] -> true | _ -> false);
      assert (match get_object "meta" ast with Some [("zone", String "RH-2")] -> true | _ -> false);
      let reserialized = to_string ast in
      let pretty = to_string_pretty ast in
      Printf.printf "[PASS] Typed accessors passed! Roundtrip: %s\nPretty:\n%s\n" reserialized pretty
