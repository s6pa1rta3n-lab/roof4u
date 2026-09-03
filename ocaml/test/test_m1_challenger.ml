(**
   test_m1_challenger.ml - Adversarial Challenger & Empirical Stress Test Suite for Milestone 1.
   Author: Empirical Challenger Agent (teamwork_preview_challenger_m1_1)
   
   Scope:
   1. SHA-256 Stress: Boundary coverage (0..8192 bytes), Streaming Chunk Invariance (primes, boundaries),
      Zero-length updates, High-entropy / byte value variations (0x00, 0x80, 0xFF, alternating).
   2. JSON Parser Adversarial Fuzzing:
      - Deep nesting (1..1024, 1025 boundary rejection, configurable depth).
      - Malformed floats and numbers (leading +, bare dots, exponent without digits, double signs, leading zeros).
      - Unicode escapes & surrogate pairs (RFC 8259 valid/invalid, lone surrogates, max code point U+10FFFF).
      - Unescaped control characters 0x00..0x1F.
      - Truncated syntax across all JSON primitives and composite types.
      - Duplicate key collision handling and retrieval stability.
      - Memory & scale stress (10,000 array elements, large objects).
*)

open Roof_engine
open Crypto
open Json

let total_tests = ref 0
let passed_tests = ref 0
let failed_tests = ref 0

let check_true desc cond =
  incr total_tests;
  if cond then (
    incr passed_tests;
    Printf.printf "  [PASS] %s\n" desc
  ) else (
    incr failed_tests;
    Printf.printf "  [FAIL] %s\n" desc;
    failwith ("Challenger assertion failed: " ^ desc)
  )

let check_equal_str desc expected actual =
  incr total_tests;
  if expected = actual then (
    incr passed_tests;
    Printf.printf "  [PASS] %s\n" desc
  ) else (
    incr failed_tests;
    Printf.printf "  [FAIL] %s\n    Expected: %s\n    Actual:   %s\n" desc expected actual;
    failwith ("Challenger assertion failed: " ^ desc)
  )

let check_is_error desc (res : ('a, string) result) =
  incr total_tests;
  match res with
  | Error _ ->
      incr passed_tests;
      Printf.printf "  [PASS] %s (correctly rejected)\n" desc
  | Ok _ ->
      incr failed_tests;
      Printf.printf "  [FAIL] %s (expected Error, but parsed successfully)\n" desc;
      failwith ("Challenger expected error but got Ok: " ^ desc)

let check_is_ok desc (res : ('a, string) result) =
  incr total_tests;
  match res with
  | Ok _ ->
      incr passed_tests;
      Printf.printf "  [PASS] %s\n" desc
  | Error msg ->
      incr failed_tests;
      Printf.printf "  [FAIL] %s (expected Ok, got Error: %s)\n" desc msg;
      failwith ("Challenger expected Ok but got Error: " ^ desc ^ " -> " ^ msg)

let test_sha256_boundaries () =
  Printf.printf "\n--- SHA-256 Stress & Boundary Invariance ---\n";

  let critical_lengths = [
    0; 1; 2; 54; 55; 56; 57; 63; 64; 65;
    118; 119; 120; 121; 127; 128; 129;
    182; 183; 184; 185; 191; 192; 193;
    255; 256; 511; 512; 513; 1023; 1024; 1025;
    2047; 2048; 4095; 4096; 8191; 8192
  ] in

  List.iter (fun len ->
    let s_zeros = String.make len '\x00' in
    let s_ones = String.make len '\xFF' in
    let s_pattern = String.init len (fun i -> Char.chr (i mod 256)) in

    let h_zeros = sha256_string s_zeros in
    let h_ones = sha256_string s_ones in
    let h_pattern = sha256_string s_pattern in

    check_true (Printf.sprintf "SHA-256 len=%d 0x00 digest length is 64 hex" len) (String.length h_zeros = 64);
    check_true (Printf.sprintf "SHA-256 len=%d 0xFF digest length is 64 hex" len) (String.length h_ones = 64);
    check_true (Printf.sprintf "SHA-256 len=%d pattern digest length is 64 hex" len) (String.length h_pattern = 64);
    if len > 0 then
      check_true (Printf.sprintf "SHA-256 len=%d 0x00 != 0xFF" len) (h_zeros <> h_ones)
  ) critical_lengths;

  let ctx = init () in
  update_string ctx "hello";
  update_bytes ctx (Bytes.create 0) 0 0;
  update_string ctx " world";
  let h_with_empty_chunk = finalize_hex ctx in
  let h_direct = sha256_string "hello world" in
  check_equal_str "SHA-256 zero-length update invariance" h_direct h_with_empty_chunk;

  let payload_4k = String.init 4096 (fun i -> Char.chr ((i * 37 + 13) mod 256)) in
  let expected_4k = sha256_string payload_4k in

  let chunk_sizes = [1; 2; 3; 5; 7; 11; 13; 17; 31; 55; 56; 63; 64; 65; 127; 128; 129; 255; 256; 500; 512; 1000; 1024; 2048; 4096] in
  List.iter (fun chunk_sz ->
    let c = init () in
    let pos = ref 0 in
    let len = String.length payload_4k in
    while !pos < len do
      let take = min chunk_sz (len - !pos) in
      update_string c (String.sub payload_4k !pos take);
      pos := !pos + take
    done;
    let stream_hash = finalize_hex c in
    check_equal_str (Printf.sprintf "SHA-256 4KB payload chunk size %d invariance" chunk_sz) expected_4k stream_hash
  ) chunk_sizes;

  let c_jitter = init () in
  let pos = ref 0 in
  let len = String.length payload_4k in
  let step = ref 1 in
  while !pos < len do
    let take = min !step (len - !pos) in
    update_string c_jitter (String.sub payload_4k !pos take);
    pos := !pos + take;
    step := (!step * 7 + 3) mod 67 + 1
  done;
  check_equal_str "SHA-256 4KB jittered irregular chunks invariance" expected_4k (finalize_hex c_jitter)

let test_json_nesting_depth () =
  Printf.printf "\n--- JSON Adversarial Fuzzing: Nesting Depth & Limits ---\n";

  let depths = [1; 10; 50; 100; 500; 1000; 1023] in
  List.iter (fun d ->
    let open_b = String.make d '[' in
    let close_b = String.make d ']' in
    let json_str = open_b ^ "42" ^ close_b in
    check_is_ok (Printf.sprintf "JSON nested array depth=%d accepted" d) (parse json_str)
  ) depths;

  let open_1024 = String.make 1024 '[' in
  let close_1024 = String.make 1024 ']' in
  check_is_ok "JSON nested array depth=1024 accepted (boundary)" (parse (open_1024 ^ "1" ^ close_1024));

  let open_1025 = String.make 1025 '[' in
  let close_1025 = String.make 1025 ']' in
  check_is_error "JSON nested array depth=1025 rejected (exceeds default max_depth 1024)" (parse (open_1025 ^ "1" ^ close_1025));

  let open_50 = String.make 50 '[' in
  let close_50 = String.make 50 ']' in
  check_is_error "JSON depth=50 rejected when max_depth=30" (parse ~max_depth:30 (open_50 ^ "1" ^ close_50));
  check_is_ok "JSON depth=50 accepted when max_depth=60" (parse ~max_depth:60 (open_50 ^ "1" ^ close_50));

  let rec build_obj_depth d inner =
    if d = 0 then inner
    else "{\"k\":" ^ build_obj_depth (d - 1) inner ^ "}"
  in
  check_is_ok "JSON nested object depth=500 accepted" (parse (build_obj_depth 500 "true"));
  check_is_error "JSON nested object depth=1025 rejected" (parse (build_obj_depth 1025 "true"))

let test_json_number_fuzzing () =
  Printf.printf "\n--- JSON Adversarial Fuzzing: Malformed Numbers & Floats ---\n";

  let invalid_numbers = [
    "+1"; "+0"; "+1.5"; "+1e5";
    "01"; "00"; "007"; "0123.45"; "-01"; "-00";
    ".5"; "-.5"; ".123"; "+.5";
    "1."; "0."; "-5."; "100.";
    "1.e2"; "1.e+2"; "0.E5";
    "1e"; "1e+"; "1e-"; "1E"; "1E+"; "1E-"; "-1e";
    "1e1.5"; "1e0.5";
    "--1"; "-+1"; "+-1";
    "1.2.3"; "1..2";
    "0x123"; "0b101"; "0o77";
    "Infinity"; "-Infinity"; "+Infinity"; "inf"; "-inf";
    "NaN"; "-NaN"; "nan";
    "1_000"; "1 000";
    "1a"; "2f"; "3d"; "4L"
  ] in

  List.iter (fun num_str ->
    check_is_error (Printf.sprintf "Reject malformed number '%s'" num_str) (parse num_str);
    check_is_error (Printf.sprintf "Reject malformed number in object '{\"n\": %s}'" num_str) (parse ("{\"n\": " ^ num_str ^ "}"));
    check_is_error (Printf.sprintf "Reject malformed number in array '[%s]'" num_str) (parse ("[" ^ num_str ^ "]"))
  ) invalid_numbers;

  let valid_numbers = [
    ("0", 0.0);
    ("-0", 0.0);
    ("0.0", 0.0);
    ("-0.0", 0.0);
    ("0.12345", 0.12345);
    ("100", 100.0);
    ("-100", -100.0);
    ("1.25e3", 1250.0);
    ("1.25E3", 1250.0);
    ("1.25e+3", 1250.0);
    ("1.25e-3", 0.00125);
    ("0e0", 0.0);
    ("0e5", 0.0);
    ("-0e-5", 0.0);
    ("1000000000000.0", 1e12);
  ] in

  List.iter (fun (s, expected) ->
    match parse s with
    | Ok (Number f) ->
        check_true (Printf.sprintf "Parse valid number '%s' -> %g" s f) (abs_float (f -. expected) < 1e-5 || (expected = 0.0 && abs_float f < 1e-5))
    | Ok _ ->
        check_true (Printf.sprintf "Parse valid number '%s' returned non-number AST" s) false
    | Error msg ->
        check_true (Printf.sprintf "Parse valid number '%s' failed: %s" s msg) false
  ) valid_numbers

let test_json_unicode_and_surrogates () =
  Printf.printf "\n--- JSON Adversarial Fuzzing: Unicode Escapes & UTF-16 Surrogates ---\n";

  let invalid_escapes = [
    "\"\\u\""; "\"\\u1\""; "\"\\u12\""; "\"\\u123\"";
    "\"\\u123g\""; "\"\\uZZZZ\""; "\"\\u----\""; "\"\\u####\""; "\"\\u 123\"";
    "\"\\u12\\n\""; "\"\\u12\\\"\"";
  ] in
  List.iter (fun esc_str ->
    check_is_error (Printf.sprintf "Reject invalid unicode escape %s" esc_str) (parse esc_str)
  ) invalid_escapes;

  let valid_escapes = [
    ("\"\\u0000\"", "\x00");
    ("\"\\u0020\"", " ");
    ("\"\\u0041\\u0042\\u0043\"", "ABC");
    ("\"\\u00E9\"", "\xC3\xA9");
    ("\"\\u4E2D\\u6587\"", "\xE4\xB8\xAD\xE6\x96\x87");
    ("\"\\uFFFF\"", "\xEF\xBF\xBF");
    ("\"\\uD83D\\uDE00\"", "\xF0\x9F\x98\x80");
    ("\"\\uDBFF\\uDFFF\"", "\xF4\x8F\xBF\xBF");
    ("\"\\uD83C\\uDFE0\"", "\xF0\x9F\x8F\xA0");
  ] in
  List.iter (fun (json_str, expected_utf8) ->
    match parse json_str with
    | Ok (String s) ->
        check_equal_str (Printf.sprintf "Unicode escape %s decoded to expected UTF-8 bytes" json_str) expected_utf8 s
    | Ok _ -> check_true (Printf.sprintf "Unicode escape %s gave non-string AST" json_str) false
    | Error msg -> check_true (Printf.sprintf "Unicode escape %s failed to parse: %s" json_str msg) false
  ) valid_escapes;

  let lone_surrogates = [
    "\"\\uD800\"";
    "\"\\uDC00\"";
    "\"\\uD800\\uD800\"";
    "\"\\uD800\\u0041\"";
    "\"\\uD800abc\"";
    "\"\\uD800\\\\\"";
  ] in
  List.iter (fun s ->
    let res = parse s in
    check_is_ok (Printf.sprintf "Lone surrogate %s handled gracefully without crash" s) res
  ) lone_surrogates

let test_json_control_chars_and_truncations () =
  Printf.printf "\n--- JSON Adversarial Fuzzing: Control Characters & Truncated Payloads ---\n";

  for code = 0 to 31 do
    let raw_char = String.make 1 (Char.chr code) in
    let invalid_json = "\"" ^ raw_char ^ "\"" in
    check_is_error (Printf.sprintf "Reject unescaped control char 0x%02X in string literal" code) (parse invalid_json)
  done;

  let truncated_payloads = [
    ""; "   "; "\t\n";
    "{"; "}"; "["; "]";
    "{\""; "{\"key"; "{\"key\""; "{\"key\":"; "{\"key\": ";
    "{\"key\": 1"; "{\"key\": 1,"; "{\"key\": 1, ";
    "{\"k1\": 1, \"k2\""; "{\"k1\": 1, \"k2\":";
    "[1"; "[1,"; "[1, "; "[1, 2, ";
    "\""; "\"hello"; "\"hello\\"; "\"hello\\\"";
    "t"; "tr"; "tru"; "f"; "fa"; "fal"; "fals"; "n"; "nu"; "nul";
    "-"; "-."; "+"; "1e"; "1.";
  ] in
  List.iter (fun trunc ->
    check_is_error (Printf.sprintf "Reject truncated JSON input '%s'" (String.escaped trunc)) (parse trunc)
  ) truncated_payloads

let test_json_key_collisions_and_stress () =
  Printf.printf "\n--- JSON Adversarial Fuzzing: Key Collisions & Scale Stress ---\n";

  let dup_json = "{\"a\": 1, \"b\": 2, \"a\": 3, \"a\": 4}" in
  let res_dup = parse dup_json in
  check_is_ok "JSON duplicate keys parsed safely into AST" res_dup;
  let ast_dup = Result.get_ok res_dup in
  (match ast_dup with
   | Object kvs ->
       check_true "AST preserves all 4 duplicate key entries" (List.length kvs = 4);
       check_equal_str "get_int retrieves first occurrence" "1" (string_of_int (Option.get (get_int "a" ast_dup)));
   | _ -> check_true "Expected Object AST" false);

  let empty_key_json = "{\"\": \"empty_key_value\"}" in
  let res_empty = parse empty_key_json in
  check_is_ok "JSON empty string key parsed safely" res_empty;
  let ast_empty = Result.get_ok res_empty in
  check_equal_str "Extract value from empty string key" "empty_key_value" (Option.get (get_string "" ast_empty));

  let complex_keys_json = "{\"key\\\"with\\\"quotes\": 10, \"key/with/slash\": 20, \"key\\\\with\\\\backslash\": 30}" in
  let res_complex_keys = parse complex_keys_json in
  check_is_ok "JSON complex escaped keys parsed safely" res_complex_keys;
  let ast_complex = Result.get_ok res_complex_keys in
  check_true "Extract key with quotes" (get_int "key\"with\"quotes" ast_complex = Some 10);
  check_true "Extract key with slashes" (get_int "key/with/slash" ast_complex = Some 20);
  check_true "Extract key with backslashes" (get_int "key\\with\\backslash" ast_complex = Some 30);

  let count = 10000 in
  let buf = Buffer.create (count * 6) in
  Buffer.add_char buf '[';
  for i = 0 to count - 1 do
    if i > 0 then Buffer.add_char buf ',';
    Buffer.add_string buf (string_of_int i)
  done;
  Buffer.add_char buf ']';
  let large_arr_json = Buffer.contents buf in
  let t0 = Unix.gettimeofday () in
  let res_large = parse large_arr_json in
  let t1 = Unix.gettimeofday () in
  check_is_ok (Printf.sprintf "Parse 10,000 element array in %.3fs" (t1 -. t0)) res_large;
  let ast_large = Result.get_ok res_large in
  (match ast_large with
   | Array items ->
       check_true "10,000 element array has exact count" (List.length items = count);
       check_true "10,000th element unwrapped is 9999" (as_int (List.nth items 9999) = Some 9999);
   | _ -> check_true "Expected Array AST" false);

  let serialized_nan = to_string (Number Float.nan) in
  check_equal_str "Serializer converts NaN to 'null'" "null" serialized_nan;
  let serialized_inf = to_string (Number Float.infinity) in
  check_equal_str "Serializer converts Infinity to 'null'" "null" serialized_inf;
  let serialized_neg_inf = to_string (Number Float.neg_infinity) in
  check_equal_str "Serializer converts -Infinity to 'null'" "null" serialized_neg_inf

let () =
  Printf.printf "\n=================================================================\n";
  Printf.printf "=== Pure OCaml Milestone 1 Empirical Challenger Test Suite ===\n";
  Printf.printf "=================================================================\n";

  test_sha256_boundaries ();
  test_json_nesting_depth ();
  test_json_number_fuzzing ();
  test_json_unicode_and_surrogates ();
  test_json_control_chars_and_truncations ();
  test_json_key_collisions_and_stress ();

  Printf.printf "\n=================================================================\n";
  Printf.printf "=== Challenger Test Results: %d/%d Tests Passed (0 Failures) ===\n"
    !passed_tests !total_tests;
  Printf.printf "=================================================================\n\n";
  if !failed_tests > 0 then exit 1 else exit 0
