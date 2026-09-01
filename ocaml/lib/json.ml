(**
   json.ml - Pure OCaml Recursive-Descent JSON AST Parser & Serializer.
   Strictly RFC 8259 compliant, zero external dependencies.
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

let rec to_buffer buf = function
  | Null -> Buffer.add_string buf "null"
  | Bool true -> Buffer.add_string buf "true"
  | Bool false -> Buffer.add_string buf "false"
  | Number f -> Buffer.add_string buf (json_of_float f)
  | String s -> Buffer.add_string buf (escape_json_string s)
  | Array items ->
      Buffer.add_char buf '[';
      let rec loop = function
        | [] -> ()
        | [x] -> to_buffer buf x
        | x :: rest ->
            to_buffer buf x;
            Buffer.add_char buf ',';
            loop rest
      in
      loop items;
      Buffer.add_char buf ']'
  | Object kvs ->
      Buffer.add_char buf '{';
      let rec loop = function
        | [] -> ()
        | [(k, v)] ->
            Buffer.add_string buf (escape_json_string k);
            Buffer.add_char buf ':';
            to_buffer buf v
        | (k, v) :: rest ->
            Buffer.add_string buf (escape_json_string k);
            Buffer.add_char buf ':';
            to_buffer buf v;
            Buffer.add_char buf ',';
            loop rest
      in
      loop kvs;
      Buffer.add_char buf '}'

let to_string t =
  let buf = Buffer.create 64 in
  to_buffer buf t;
  Buffer.contents buf

let to_channel oc t =
  output_string oc (to_string t)

let to_string_pretty ?(indent = 2) t =
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

(* Combinators & Navigation *)
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
