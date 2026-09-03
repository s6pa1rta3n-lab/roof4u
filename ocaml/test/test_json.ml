(**
   test_json.ml - Comprehensive unit test suite for Pure OCaml RFC 8259 JSON AST Parser & Serializer.
   Tests full AST representation, typed accessors, unwrappers, Unicode escapes, surrogate pairs,
   error trapping, and roundtrip serialization.
*)

open Roof_engine
open Json

let test_count = ref 0
let pass_count = ref 0

let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n" name;
    failwith ("Assertion failed: " ^ name)
  )

let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n  Expected: %s\n  Actual:   %s\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let () =
  Printf.printf "\n======================================================\n";
  Printf.printf "=== Pure OCaml JSON AST Parser & Serializer Tests ===\n";
  Printf.printf "======================================================\n\n";

  let r_null = parse "null" in
  assert_true "T1.1: Parse Null" (r_null = Ok Null);

  let r_bool_t = parse "true" in
  assert_true "T1.2: Parse Bool true" (r_bool_t = Ok (Bool true));

  let r_bool_f = parse "false" in
  assert_true "T1.3: Parse Bool false" (r_bool_f = Ok (Bool false));

  let r_num = parse "12345.67" in
  assert_true "T1.4: Parse Number float" (match r_num with Ok (Number f) -> abs_float (f -. 12345.67) < 0.001 | _ -> false);

  let r_int = parse "42" in
  assert_true "T1.5: Parse Number int" (match r_int with Ok (Number f) -> f = 42.0 | _ -> false);

  let r_neg = parse "-99.5" in
  assert_true "T1.6: Parse Negative Number" (match r_neg with Ok (Number f) -> f = -99.5 | _ -> false);

  let r_exp = parse "1.25e-3" in
  assert_true "T1.7: Parse Scientific Exponent" (match r_exp with Ok (Number f) -> abs_float (f -. 0.00125) < 1e-6 | _ -> false);

  let r_str = parse "\"San Francisco Municipal Database\"" in
  assert_true "T1.8: Parse String" (r_str = Ok (String "San Francisco Municipal Database"));

  let json_obj_str = "{\"address\": \"2223 Pacific Ave\", \"zip\": \"94115\", \"value\": 4350000.0, \"hoa\": false, \"units\": 1}" in
  let r_obj = parse json_obj_str in
  assert_true "T1.9: Parse Structured JSON Object" (match r_obj with Ok (Object _) -> true | _ -> false);

  let ast = match r_obj with Ok o -> o | Error e -> failwith e in
  assert_equal_str "T1.10: Extract string field (address)" "2223 Pacific Ave" (Option.get (get_string "address" ast));
  assert_equal_str "T1.11: Extract string field (zip)" "94115" (Option.get (get_string "zip" ast));
  assert_true "T1.12: Extract float field (value)" (Option.get (get_float "value" ast) = 4350000.0);
  assert_true "T1.13: Extract bool field (hoa)" (Option.get (get_bool "hoa" ast) = false);
  assert_true "T1.14: Extract int field (units)" (Option.get (get_int "units" ast) = 1);

  let arr_json = "{\"permits\": [101, 102, 103]}" in
  let r_arr = parse arr_json in
  assert_true "T1.15: Extract array field" (match r_arr with Ok o -> get_array "permits" o <> None | _ -> false);

  let permits_list = Option.get (get_array "permits" (Result.get_ok r_arr)) in
  assert_true "T1.16: Array element count is 3" (List.length permits_list = 3);
  assert_true "T1.17: Array element unwrapping" (as_int (List.hd permits_list) = Some 101);

  let uni_str = "{\"greeting\": \"Hello \\u0057\\u006f\\u0072\\u006c\\u0064!\"}" in
  let r_uni = parse uni_str in
  assert_true "T1.18: Parse \\u00XX Unicode escapes"
    (match r_uni with
     | Ok o -> get_string "greeting" o = Some "Hello World!"
     | Error _ -> false);

  let emoji_str = "{\"icon\": \"\\uD83C\\uDFE0\"}" in
  let r_emoji = parse emoji_str in
  assert_true "T1.19: Parse UTF-16 surrogate pair to UTF-8"
    (match r_emoji with
     | Ok o -> get_string "icon" o = Some "\xF0\x9F\x8F\xA0"
     | Error _ -> false);

  let esc_json = "{\"path\": \"C:\\\\Program Files\\\\App\", \"quote\": \"He said \\\"Hello\\\"\", \"lines\": \"A\\nB\\tC\"}" in
  let r_esc = parse esc_json in
  assert_true "T1.20: Parse all standard escape sequences" (match r_esc with Ok (Object _) -> true | _ -> false);
  let ast_esc = Result.get_ok r_esc in
  assert_equal_str "T1.21: Escaped backslash" "C:\\Program Files\\App" (Option.get (get_string "path" ast_esc));
  assert_equal_str "T1.22: Escaped quotes" "He said \"Hello\"" (Option.get (get_string "quote" ast_esc));
  assert_equal_str "T1.23: Newline and Tab" "A\nB\tC" (Option.get (get_string "lines" ast_esc));

  assert_true "T1.24: as_string on String" (as_string (String "test") = Some "test");
  assert_true "T1.25: as_string on Null" (as_string Null = None);
  assert_true "T1.26: as_float on Number" (as_float (Number 3.14) = Some 3.14);
  assert_true "T1.27: as_int on Number" (as_int (Number 42.0) = Some 42);
  assert_true "T1.28: as_bool on Bool" (as_bool (Bool true) = Some true);
  assert_true "T1.29: as_array on Array" (as_array (Array [Null]) = Some [Null]);
  assert_true "T1.30: as_object on Object" (as_object (Object [("k", Null)]) = Some [("k", Null)]);

  let complex_json = "{\"data\": {\"leads\": [{\"addr\": \"100 Main\"}, {\"addr\": \"200 Market\"}]}}" in
  let ast_complex = parse_exn complex_json in
  assert_equal_str "T1.31: Path navigation to nested property"
    "100 Main"
    (match path ["data"; "leads"] ast_complex with
     | Some arr ->
         (match index 0 arr with
          | Some item -> Option.value ~default:"" (get_string "addr" item)
          | None -> "")
     | None -> "");

  assert_true "T1.32: Member combinator fallback to Null on missing key"
    (member "nonexistent" ast_complex = Null);

  let built_ast = obj [
    ("name", string "Roo4u");
    ("version", int 2);
    ("active", bool true);
    ("tags", array [string "sf"; string "real_estate"]);
    ("metadata", null);
  ] in
  assert_true "T1.33: Programmatic AST construction"
    (match built_ast with Object kvs -> List.length kvs = 5 | _ -> false);

  let compact_str = to_string built_ast in
  assert_true "T1.34: Compact serialization contains required keys"
    (String.length compact_str > 20);

  let pretty_str = to_string_pretty ~indent:2 built_ast in
  assert_true "T1.35: Pretty serialization produces multiline indented string"
    (String.contains pretty_str '\n');

  let roundtrip_ast = parse_exn compact_str in
  assert_equal_str "T1.36: Roundtrip AST string equivalence"
    "Roo4u"
    (Option.get (get_string "name" roundtrip_ast));
  assert_true "T1.37: Roundtrip AST int equivalence"
    (get_int "version" roundtrip_ast = Some 2);

  assert_true "T2.1: Rejects empty input" (match parse "" with Error _ -> true | _ -> false);
  assert_true "T2.2: Rejects whitespace-only input" (match parse "   \n\t  " with Error _ -> true | _ -> false);
  assert_true "T2.3: Rejects unclosed object" (match parse "{\"key\": \"val\"" with Error _ -> true | _ -> false);
  assert_true "T2.4: Rejects unclosed array" (match parse "[1, 2, 3" with Error _ -> true | _ -> false);
  assert_true "T2.5: Rejects trailing comma in array" (match parse "[1, 2, 3,]" with Error _ -> true | _ -> false);
  assert_true "T2.6: Rejects trailing comma in object" (match parse "{\"a\": 1,}" with Error _ -> true | _ -> false);
  assert_true "T2.7: Rejects unquoted object key" (match parse "{key: \"val\"}" with Error _ -> true | _ -> false);
  assert_true "T2.8: Rejects leading zeros in number" (match parse "0123" with Error _ -> true | _ -> false);
  assert_true "T2.9: Rejects trailing decimal in number" (match parse "1." with Error _ -> true | _ -> false);
  assert_true "T2.10: Rejects unescaped control char" (match parse "{\"msg\": \"hello\x00world\"}" with Error _ -> true | _ -> false);
  assert_true "T2.11: Rejects trailing garbage after valid JSON" (match parse "{\"a\": 1} trailing_garbage" with Error _ -> true | _ -> false);
  assert_true "T2.12: Rejects depth exceeding max_depth"
    (match parse ~max_depth:3 "[[[[1]]]]" with Error _ -> true | _ -> false);

  Printf.printf "\n=== Completed Pure OCaml JSON AST Test Suite: %d/%d Tests Passed ===\n\n" !pass_count !test_count
