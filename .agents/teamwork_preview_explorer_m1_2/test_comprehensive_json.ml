(**
   test_comprehensive_json.ml - Rigorous test suite for json.ml
*)

module Json = struct
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
    if peek state = Some '-' then advance state;
    (match peek state with
     | Some '0' ->
         advance state;
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

  let parse_exn ?(max_depth = 1024) src =
    match parse ~max_depth src with
    | Ok v -> v
    | Error msg -> failwith msg

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
    else if floor f = f && abs_float f < 1e15 then
      if f = 0.0 then "0"
      else Printf.sprintf "%.0f" f
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

  (* Value Unwrappers *)
  let as_string = function String s -> Some s | _ -> None
  let as_float = function Number f -> Some f | _ -> None
  let as_int = function Number f -> Some (int_of_float f) | _ -> None
  let as_bool = function Bool b -> Some b | _ -> None
  let as_array = function Array arr -> Some arr | _ -> None
  let as_object = function Object obj -> Some obj | _ -> None

  (* AST Constructors *)
  let null = Null
  let bool b = Bool b
  let string s = String s
  let float f = Number f
  let int n = Number (float_of_int n)
  let array arr = Array arr
  let obj kvs = Object kvs

  (* Navigation Helpers *)
  let member key json =
    match get_field key json with
    | Some v -> v
    | None -> Null

  let index i = function
    | Array arr ->
        if i >= 0 && i < List.length arr then Some (List.nth arr i)
        else None
    | _ -> None

  let rec path keys json =
    match keys with
    | [] -> Some json
    | k :: rest ->
        match get_field k json with
        | Some next -> path rest next
        | None -> None
end

(* Rigorous Unit Test Suite *)
let test_count = ref 0
let pass_count = ref 0

let check name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n" name;
    failwith ("Assertion failed: " ^ name)
  )

let () =
  Printf.printf "\n=== Starting Pure OCaml JSON Module Test Suite ===\n\n";

  (* 1. Primitive Values *)
  check "Parse null" (Json.parse "null" = Ok Json.Null);
  check "Parse true" (Json.parse "true" = Ok (Json.Bool true));
  check "Parse false" (Json.parse "false" = Ok (Json.Bool false));
  check "Parse integer 0" (Json.parse "0" = Ok (Json.Number 0.0));
  check "Parse integer 42" (Json.parse "42" = Ok (Json.Number 42.0));
  check "Parse negative integer -17" (Json.parse "-17" = Ok (Json.Number (-17.0)));
  check "Parse float 3.14159" (Json.parse "3.14159" = Ok (Json.Number 3.14159));
  check "Parse exponent 1e5" (Json.parse "1e5" = Ok (Json.Number 100000.0));
  check "Parse exponent -2.5E-3" (Json.parse "-2.5E-3" = Ok (Json.Number (-0.0025)));
  check "Parse empty string" (Json.parse "\"\"" = Ok (Json.String ""));
  check "Parse simple string" (Json.parse "\"hello world\"" = Ok (Json.String "hello world"));

  (* 2. String Escapes & Unicode *)
  check "Escape quotes and backslashes"
    (Json.parse "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"" = Ok (Json.String "\"\\/\b\012\n\r\t"));
  check "Unicode BMP escape"
    (Json.parse "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"" = Ok (Json.String "Hello"));
  check "Unicode surrogate pair (Rocket 🚀)"
    (Json.parse "\"\\uD83D\\uDE80\"" = Ok (Json.String "\xF0\x9F\x9A\x80"));

  (* 3. Nested Arrays & Objects *)
  let complex_json = {|
    {
      "address": "2223 Pacific Ave",
      "zip_code": "94115",
      "estimated_value": 4370000.0,
      "year_built": 1908,
      "is_hoa": false,
      "is_rental": false,
      "roof_type": "Victorian",
      "permits": [
        {
          "permit_number": "20050101",
          "description": "Complete reroof",
          "is_roof_replacement": true,
          "cost": 25000.0
        }
      ],
      "metadata": {
        "verified": true,
        "score": 92.5
      }
    }
  |} in
  let ast = match Json.parse complex_json with Ok v -> v | Error e -> failwith e in
  check "Object field 'address'" (Json.get_string "address" ast = Some "2223 Pacific Ave");
  check "Object field 'zip_code'" (Json.get_string "zip_code" ast = Some "94115");
  check "Object field 'estimated_value'" (Json.get_float "estimated_value" ast = Some 4370000.0);
  check "Object field 'year_built'" (Json.get_int "year_built" ast = Some 1908);
  check "Object field 'is_hoa'" (Json.get_bool "is_hoa" ast = Some false);
  check "Nested permits array length"
    (match Json.get_array "permits" ast with Some [p] -> true | _ -> false);
  check "Nested permit field via member"
    (let p0 = Json.index 0 (Json.member "permits" ast) in
     match p0 with
     | Some p -> Json.get_string "permit_number" p = Some "20050101"
     | None -> false);
  check "Path traversal to metadata score"
    (Json.path ["metadata"; "score"] ast = Some (Json.Number 92.5));

  (* 4. Error Handling & RFC 8259 Strictness *)
  let should_fail input msg_tag =
    match Json.parse input with
    | Error _ -> true
    | Ok _ -> false
  in
  check "Reject unquoted keys" (should_fail "{a: 1}" "unquoted key");
  check "Reject single quotes" (should_fail "{'a': 1}" "single quotes");
  check "Reject trailing comma in array" (should_fail "[1, 2,]" "array trailing comma");
  check "Reject trailing comma in object" (should_fail "{\"a\": 1,}" "object trailing comma");
  check "Reject leading zero number" (should_fail "0123" "leading zero");
  check "Reject trailing decimal point" (should_fail "123." "trailing decimal");
  check "Reject leading decimal point" (should_fail ".123" "leading decimal");
  check "Reject lone minus" (should_fail "-" "lone minus");
  check "Reject exponent without digits" (should_fail "1e" "exponent without digits");
  check "Reject invalid escape \\x" (should_fail "\"\\x41\"" "invalid escape");
  check "Reject unclosed string" (should_fail "\"unclosed" "unclosed string");
  check "Reject unclosed array" (should_fail "[1, 2" "unclosed array");
  check "Reject unclosed object" (should_fail "{\"a\": 1" "unclosed object");
  check "Reject trailing junk" (should_fail "{\"a\": 1} trailing" "trailing junk");
  check "Reject empty string" (should_fail "" "empty string");
  check "Reject whitespace only" (should_fail "   \t\n  " "whitespace only");

  (* 5. Depth Limit Stack Overflow Protection *)
  let deep_nest = String.make 50 '[' ^ "1" ^ String.make 50 ']' in
  check "Allow nesting within limit"
    (match Json.parse ~max_depth:60 deep_nest with Ok _ -> true | Error _ -> false);
  check "Reject nesting exceeding max_depth"
    (match Json.parse ~max_depth:30 deep_nest with Error _ -> true | Ok _ -> false);

  (* 6. Serialization Round-Trip *)
  let ser1 = Json.to_string ast in
  let ast2 = match Json.parse ser1 with Ok v -> v | Error e -> failwith e in
  check "AST round-trip equality" (ast = ast2);
  let pretty = Json.to_string_pretty ~indent:2 ast in
  let ast3 = match Json.parse pretty with Ok v -> v | Error e -> failwith e in
  check "Pretty print round-trip equality" (ast = ast3);

  Printf.printf "\n=== All %d JSON Tests Passed (100%%) ===\n\n" !pass_count
