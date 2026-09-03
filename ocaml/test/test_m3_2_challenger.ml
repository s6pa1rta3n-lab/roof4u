(**
   test_m3_2_challenger.ml - Adversarial edge-case validation suite for Milestone 3.
   Stress-tests:
     1. CSV formula injection with leading whitespace, tabs, carriage returns, and control chars.
     2. Malformed, truncated, and polymorphic JSON in skip tracer API payloads.
     3. Regex catastrophic backtracking resistance and false extraction rejection in OSINT scraping.
     4. Adversarial permutations of dummy, fictitious, repeating, and sequential phone numbers.
     5. Multi-tier contact enricher waterfall and error isolation under network faults.
*)

[@@@warning "-32-33-27-35"]

open Roof_engine
open Types
open Phone_validator
open Contact_enricher
open Skip_tracer
open Osint_scraper
open Csv_exporter

let total_passed = ref 0
let total_failed = ref 0

(** [assert_true name cond] records test pass if cond is true, else records fail. *)
let assert_true name cond =
  if cond then (
    incr total_passed;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr total_failed;
    Printf.eprintf "  [FAIL] %s\n%!" name
  )

(** [assert_equal_string name expected actual] checks string equality. *)
let assert_equal_string name expected actual =
  if expected = actual then (
    incr total_passed;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr total_failed;
    Printf.eprintf "  [FAIL] %s (expected %S, got %S)\n%!" name expected actual
  )

(** [assert_equal_int name expected actual] checks int equality. *)
let assert_equal_int name expected actual =
  if expected = actual then (
    incr total_passed;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr total_failed;
    Printf.eprintf "  [FAIL] %s (expected %d, got %d)\n%!" name expected actual
  )

(** [test_csv_injection_probes ()] tests CSV formula injection edge cases. *)
let test_csv_injection_probes () =
  Printf.printf "\n=== CHALLENGER 1: CSV FORMULA INJECTION & LEADING WHITESPACE PROBES ===\n";
  let check_sanitized label raw expected =
    let actual = Csv_exporter.sanitize_csv_field raw in
    assert_equal_string (label ^ ": sanitize") expected actual
  in
  check_sanitized "C1.1 Direct equal" "=1+1" "'=1+1";
  check_sanitized "C1.2 Direct plus" "+12345" "'+12345";
  check_sanitized "C1.3 Direct minus" "-2+3" "'-2+3";
  check_sanitized "C1.4 Direct at" "@SUM(A1:A10)" "'@SUM(A1:A10)";
  check_sanitized "C1.5 Direct tab" "\t=cmd" "'\t=cmd";
  check_sanitized "C1.6 Direct CR" "\r=cmd" "'\r=cmd";
  check_sanitized "C1.7 Single space equal" " =cmd" "' =cmd";
  check_sanitized "C1.8 Triple space equal" "   =cmd" "'   =cmd";
  check_sanitized "C1.9 Spaces plus" "  +cmd" "'  +cmd";
  check_sanitized "C1.10 Spaces minus" "    -cmd" "'    -cmd";
  check_sanitized "C1.11 Spaces at" "   @cmd" "'   @cmd";
  check_sanitized "C1.12 Spaces tab" "   \t=cmd" "'   \t=cmd";
  check_sanitized "C1.13 Spaces CR" "   \r=cmd" "'   \r=cmd";
  check_sanitized "C1.14 Mixed whitespace" " \t \r \n =cmd" "' \t \r \n =cmd";
  check_sanitized "C1.15 Tab-prefixed tab" "\t\t=cmd" "'\t\t=cmd";
  check_sanitized "C1.16 Newline prefixed" "\n=cmd" "'\n=cmd";
  check_sanitized "C1.17 CRLF prefixed" "\r\n=cmd" "'\r\n=cmd";
  check_sanitized "C1.18 Prompt whitespace trigger 1" "   =cmd|'/C calc'!A0" "'   =cmd|'/C calc'!A0";
  check_sanitized "C1.19 Prompt whitespace trigger 2" "\t+123" "'\t+123";
  check_sanitized "C1.20 Prompt whitespace trigger 3" "  @SUM(1,1)" "'  @SUM(1,1)";
  check_sanitized "C1.21 Benign address" "2223 Pacific Ave" "2223 Pacific Ave";
  check_sanitized "C1.22 Benign canonical phone" "415-346-1234" "415-346-1234";
  check_sanitized "C1.23 Benign parens phone" "(415) 346-1234" "(415) 346-1234";
  check_sanitized "C1.24 Benign empty string" "" "";
  check_sanitized "C1.25 Benign whitespace only" "   " "   ";

  let cell_escaped = Csv_exporter.format_csv_cell "   =cmd|' /C calc'!A0" in
  assert_equal_string "C1.26 Leading whitespace formula neutralized with single-quote"
    "'   =cmd|' /C calc'!A0" cell_escaped;

  let cell_escaped_prompt = Csv_exporter.format_csv_cell "   =cmd|'/C calc'!A0" in
  assert_equal_string "C1.27 Prompt payload neutralized without unwanted quotes"
    "'   =cmd|'/C calc'!A0" cell_escaped_prompt;

  let cell_tab_plus = Csv_exporter.format_csv_cell "\t+123" in
  assert_equal_string "C1.28 Tab plus neutralized" "'\t+123" cell_tab_plus;

  let cell_sum = Csv_exporter.format_csv_cell "  @SUM(1,1)" in
  assert_equal_string "C1.29 Formula with comma is single-quoted and RFC wrapped"
    "\"'  @SUM(1,1)\"" cell_sum;

  let cell_comma = Csv_exporter.format_csv_cell "   =cmd,calc" in
  assert_equal_string "C1.30 Leading whitespace formula with comma is both single-quoted and escaped"
    "\"'   =cmd,calc\"" cell_comma;

  let benign_cell = Csv_exporter.format_csv_cell "415-346-1234" in
  assert_equal_string "C1.31 Benign canonical phone not quoted" "415-346-1234" benign_cell;
  assert_true "C1.32 Canonical phone has no leading single quote"
    (benign_cell.[0] <> '\'');

  let dummy_lead : raw_lead = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 4350000.0;
    owner_name = Some "Pacific Heights Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0576-010";
    last_roof_permit_date = Some "1998-06-01";
    roof_age_years = Some 28.0;
    year_built = Some 1895;
    phone_number = Some "415-346-1234";
    permits = [];
  } in
  let row = Csv_exporter.row_of_raw_lead dummy_lead in
  let exported_phone = List.nth row 8 in
  assert_equal_string "C1.33 Row phone export is clean canonical" "415-346-1234" exported_phone;
  assert_true "C1.34 Row phone export contains no single quote"
    (not (String.contains exported_phone '\''));

  let comma_cell = Csv_exporter.format_csv_cell "Doe, John" in
  assert_equal_string "C1.35 Field with comma is wrapped in double quotes" "\"Doe, John\"" comma_cell;

  let quote_cell = Csv_exporter.format_csv_cell "John \"The Boss\" Doe" in
  assert_equal_string "C1.36 Embedded quotes are doubled per RFC 4180" "\"John \"\"The Boss\"\" Doe\"" quote_cell

(** [test_skip_tracer_malformed_json ()] tests JSON resilience in skip tracer. *)
let test_skip_tracer_malformed_json () =
  Printf.printf "\n=== CHALLENGER 2: SKIP TRACER MALFORMED & POLYMORPHIC JSON PROBES ===\n";
  let check_extract label body expected =
    let actual = Skip_tracer.extract_phone_number body in
    assert_true (label ^ ": extract") (actual = expected)
  in
  check_extract "C2.1 Completely invalid non-JSON" "not a json string" None;
  check_extract "C2.2 Truncated JSON object" "{\"results\": {\"phone_numbers\":" None;
  check_extract "C2.3 Truncated array" "{\"results\": [{\"number\": \"4153461234\"" None;
  check_extract "C2.4 JSON null" "null" None;
  check_extract "C2.5 JSON scalar integer" "12345" None;
  check_extract "C2.6 JSON scalar boolean" "true" None;
  check_extract "C2.7 JSON empty array root" "[]" None;
  check_extract "C2.8 Empty object" "{}" None;
  check_extract "C2.9 Results null" "{\"results\": null}" None;
  check_extract "C2.10 Results scalar" "{\"results\": 999}" None;
  check_extract "C2.11 Results boolean" "{\"results\": false}" None;
  check_extract "C2.12 Phone numbers null" "{\"results\": {\"phone_numbers\": null}}" None;
  check_extract "C2.13 Phone numbers scalar" "{\"results\": {\"phone_numbers\": 12345}}" None;
  check_extract "C2.14 Phone numbers string" "{\"results\": {\"phone_numbers\": \"415-346-1234\"}}" None;
  check_extract "C2.15 Heterogeneous array elements"
    "{\"results\": {\"phone_numbers\": [null, 123, true, [], {}, \"invalid\", \"415-346-1234\"]}}"
    (Some "415-346-1234");
  check_extract "C2.16 Heterogeneous results array with nulls"
    "{\"results\": [null, 123, false, {\"number\": \"415-346-1234\"}]}"
    (Some "415-346-1234");
  check_extract "C2.17 Results array with nested phone_numbers array"
    "{\"results\": [{\"other\": 1}, {\"phone_numbers\": [{\"number\": \"415-922-3190\"}]}]}"
    (Some "415-922-3190");
  check_extract "C2.18 Alternative 'phone' key in object"
    "{\"results\": {\"phone_numbers\": [{\"phone\": \"(415) 346-1234\"}]}}"
    (Some "415-346-1234");
  check_extract "C2.19 Flat string array in phone_numbers"
    "{\"phone_numbers\": [\"415-346-1234\"]}"
    (Some "415-346-1234");
  check_extract "C2.20 Array with only 555 dummy numbers returns None"
    "{\"results\": {\"phone_numbers\": [{\"number\": \"415-555-0142\"}, {\"number\": \"415-555-0199\"}]}}"
    None;
  check_extract "C2.21 Array with only sequential dummy numbers returns None"
    "{\"results\": {\"phone_numbers\": [{\"number\": \"1234567890\"}, {\"number\": \"415-123-4567\"}]}}"
    None;
  check_extract "C2.22 Array with dummy followed by valid number extracts valid"
    "{\"results\": {\"phone_numbers\": [{\"number\": \"415-555-0142\"}, {\"number\": \"415-346-1234\"}]}}"
    (Some "415-346-1234");

  let complex_lead : raw_lead = {
    address = "1234 O'Connor St \"Suite 5\"";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 3500000.0;
    owner_name = Some "Dr. John \"Jack\" O'Connor & Family Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0123-456";
    last_roof_permit_date = Some "2005-01-01";
    roof_age_years = Some 21.0;
    year_built = Some 1910;
    phone_number = None;
    permits = [];
  } in
  let built_payload = Skip_tracer.build_payload complex_lead in
  match Json.parse built_payload with
  | Ok (Json.Object _) ->
      assert_true "C2.23 build_payload produces strictly valid JSON under quotes/escapes" true
  | _ ->
      assert_true "C2.23 build_payload produces strictly valid JSON under quotes/escapes" false

(** [test_osint_redos_and_false_extractions ()] tests ReDoS resistance and false extractions. *)
let test_osint_redos_and_false_extractions () =
  Printf.printf "\n=== CHALLENGER 3: OSINT REDOS RESISTANCE & FALSE EXTRACTION PROBES ===\n";

  let start_time = Unix.gettimeofday () in
  let repeated_digits = String.make 10000 '9' in
  let _ = Phone_validator.extract_valid_phones_from_text repeated_digits in
  let duration1 = Unix.gettimeofday () -. start_time in
  assert_true "C3.1 Long digit stream (10,000 digits) processed in < 0.2s without ReDoS"
    (duration1 < 0.2);

  let start_time2 = Unix.gettimeofday () in
  let rec build_pattern n acc =
    if n <= 0 then acc
    else build_pattern (n - 1) ("(415) 346- (415) 346- " ^ acc)
  in
  let partial_phone_bomb = build_pattern 500 "" in
  let _ = Phone_validator.extract_valid_phones_from_text partial_phone_bomb in
  let duration2 = Unix.gettimeofday () -. start_time2 in
  assert_true "C3.2 Partial repeating delimiters processed in < 0.2s without ReDoS"
    (duration2 < 0.2);

  let check_not_extracted label snippet =
    let extracted = Phone_validator.extract_valid_phones_from_text snippet in
    assert_true (label ^ ": rejected false extraction") (extracted = [])
  in
  check_not_extracted "C3.3 ISO-8601 UTC timestamp" "2026-09-03T10:15:30Z";
  check_not_extracted "C3.4 Compact timestamp" "20260903101530";
  check_not_extracted "C3.5 UUID v4" "9dc3737c-92d0-4d74-8ff9-d19ed501e534";
  check_not_extracted "C3.6 SHA256 git commit hash" "7f33b48f98a21345678901234567890123456789";
  check_not_extracted "C3.7 CSS hex color" "color: #415346; background: #fff;";
  check_not_extracted "C3.8 Session ID parameter" "https://example.com/login?session_id=123456789012345";
  check_not_extracted "C3.9 Order ID sequence" "Order #415346123499 placed successfully";
  check_not_extracted "C3.10 GPS Coordinates" "Coordinates: 37.774929, -122.419416";
  check_not_extracted "C3.11 Large currency value" "Estimated home value: $4,153,461,234.00";
  check_not_extracted "C3.12 Social security format" "SSN: 123-45-6789 (invalid format)";
  check_not_extracted "C3.13 Credit card format" "Card: 4153-4612-3456-7890";
  check_not_extracted "C3.14 IPv4 Address" "Connected from 192.168.1.1 or 10.0.0.1";
  check_not_extracted "C3.15 Subnet mask" "Netmask: 255.255.255.0";
  check_not_extracted "C3.16 Localhost with port" "Listening on 127.0.0.1:8080 and :3000";

  let legitimate_text =
    "Office contact: (415) 346-1234. Alternate branch: 510.982.5678. Tel: <a href=\"tel:+14159223190\">Call</a>"
  in
  let extracted_legit = Phone_validator.extract_valid_phones_from_text legitimate_text in
  let canon_list = List.map (fun (vp : Phone_validator.validated_phone) -> vp.canonical) extracted_legit in
  assert_true "C3.17 Extracts legitimate (415) 346-1234" (List.mem "415-346-1234" canon_list);
  assert_true "C3.18 Extracts legitimate 510.982.5678" (List.mem "510-982-5678" canon_list);
  assert_true "C3.19 Extracts legitimate tel:+14159223190" (List.mem "415-922-3190" canon_list);
  assert_equal_int "C3.20 Exactly 3 legitimate numbers extracted" 3 (List.length canon_list)

(** [test_dummy_number_exhaustive ()] tests dummy and invalid phone numbers. *)
let test_dummy_number_exhaustive () =
  Printf.printf "\n=== CHALLENGER 4: EXHAUSTIVE DUMMY & INVALID NUMBER PROBES ===\n";
  let check_dummy label num =
    assert_true (label ^ ": is_dummy_number") (Phone_validator.is_dummy_number num);
    assert_true (label ^ ": not is_valid_phone") (not (Phone_validator.is_valid_phone num))
  in
  let check_valid label num expected_canon =
    assert_true (label ^ ": not is_dummy_number") (not (Phone_validator.is_dummy_number num));
    assert_true (label ^ ": is_valid_phone") (Phone_validator.is_valid_phone num);
    match Phone_validator.sanitize_and_normalize num with
    | Ok vp -> assert_equal_string (label ^ ": canonical") expected_canon vp.canonical
    | Error _ -> assert_true (label ^ ": unexpected error") false
  in

  check_dummy "C4.1 Fictitious 555-0100" "415-555-0100";
  check_dummy "C4.2 Fictitious 555-0150" "415-555-0150";
  check_dummy "C4.3 Fictitious 555-0199" "415-555-0199";
  check_dummy "C4.4 Fictitious 555-1212" "415-555-1212";
  check_dummy "C4.5 General 555-4321" "415-555-4321";
  check_dummy "C4.6 Area code 555" "555-346-1234";
  check_dummy "C4.7 All 5s" "555-555-5555";

  check_dummy "C4.8 Repeating 0s" "000-000-0000";
  check_dummy "C4.9 Repeating 1s" "111-111-1111";
  check_dummy "C4.10 Repeating 2s" "222-222-2222";
  check_dummy "C4.11 Repeating 3s" "333-333-3333";
  check_dummy "C4.12 Repeating 4s" "444-444-4444";
  check_dummy "C4.13 Repeating 6s" "666-666-6666";
  check_dummy "C4.14 Repeating 7s" "777-777-7777";
  check_dummy "C4.15 Repeating 8s" "888-888-8888";
  check_dummy "C4.16 Repeating 9s" "999-999-9999";

  check_dummy "C4.17 Local 7 repeating 0s" "415-000-0000";
  check_dummy "C4.18 Local 7 repeating 1s" "415-111-1111";
  check_dummy "C4.19 Local 7 repeating 2s" "415-222-2222";
  check_dummy "C4.20 Local 7 repeating 3s" "415-333-3333";
  check_dummy "C4.21 Local 7 repeating 8s" "415-888-8888";
  check_dummy "C4.22 Local 7 repeating 9s" "415-999-9999";

  check_dummy "C4.23 Station 0000" "415-346-0000";
  check_dummy "C4.24 Station 1111" "415-346-1111";

  check_dummy "C4.25 Sequential 1234567890" "123-456-7890";
  check_dummy "C4.26 Sequential 0123456789" "012-345-6789";
  check_dummy "C4.27 Sequential 9876543210" "987-654-3210";
  check_dummy "C4.28 Sequential 8765432109" "876-543-2109";
  check_dummy "C4.29 Local sequential 1234567" "415-123-4567";
  check_dummy "C4.30 Local sequential 2345678" "415-234-5678";
  check_dummy "C4.31 Local sequential 3456789" "415-345-6789";
  check_dummy "C4.32 Local sequential 4567890" "415-456-7890";
  check_dummy "C4.33 Local reverse 7654321" "415-765-4321";
  check_dummy "C4.34 Local reverse 8765432" "415-876-5432";
  check_dummy "C4.35 Local reverse 9876543" "415-987-6543";

  check_dummy "C4.36 N11 NPA 211" "211-346-1234";
  check_dummy "C4.37 N11 NPA 311" "311-346-1234";
  check_dummy "C4.38 N11 NPA 411" "411-346-1234";
  check_dummy "C4.39 N11 NPA 611" "611-346-1234";
  check_dummy "C4.40 N11 NPA 711" "711-346-1234";
  check_dummy "C4.41 N11 NPA 811" "811-346-1234";
  check_dummy "C4.42 N11 NPA 911" "911-346-1234";
  check_dummy "C4.43 N11 NXX 415-211-1234" "415-211-1234";
  check_dummy "C4.44 N11 NXX 415-411-1234" "415-411-1234";
  check_dummy "C4.45 N11 NXX 415-911-1234" "415-911-1234";

  check_dummy "C4.46 Toll-free 800" "800-346-1234";
  check_dummy "C4.47 Toll-free 888" "888-346-1234";
  check_dummy "C4.48 Toll-free 877" "877-346-1234";
  check_dummy "C4.49 Toll-free 866" "866-346-1234";
  check_dummy "C4.50 Toll-free 855" "855-346-1234";
  check_dummy "C4.51 Toll-free 844" "844-346-1234";
  check_dummy "C4.52 Toll-free 833" "833-346-1234";

  check_dummy "C4.53 Premium 900" "900-346-1234";
  check_dummy "C4.54 Premium 976" "976-346-1234";

  check_dummy "C4.55 NPA starts with 0" "045-346-1234";
  check_dummy "C4.56 NPA starts with 1" "145-346-1234";
  check_dummy "C4.57 NXX starts with 0" "415-046-1234";
  check_dummy "C4.58 NXX starts with 1" "415-146-1234";
  check_dummy "C4.59 Non-US country +44" "+44 20 7946 0919";
  check_dummy "C4.60 Non-US country +33" "+33 1 42 68 55 55";

  check_valid "C4.61 Authentic SF 415" "415-346-1920" "415-346-1920";
  check_valid "C4.62 Authentic SF 628" "628-200-1234" "628-200-1234";
  check_valid "C4.63 Authentic East Bay 510" "510-922-3190" "510-922-3190";
  check_valid "C4.64 Authentic Peninsula 650" "650-321-4567" "650-321-4567";
  check_valid "C4.65 Authentic South Bay 408" "408-280-9988" "408-280-9988";
  check_valid "C4.66 Authentic North Bay 707" "707-523-1122" "707-523-1122";
  check_valid "C4.67 Authentic US NYC 212" "212-736-5000" "212-736-5000";
  check_valid "C4.68 Authentic US Chicago 312" "312-819-2000" "312-819-2000";
  check_valid "C4.69 Legitimate sequential station" "415-346-1234" "415-346-1234";
  check_valid "C4.70 Legitimate reverse station" "415-346-4321" "415-346-4321"

(** [test_waterfall_fault_tolerance ()] tests contact enricher cascade under faults. *)
let test_waterfall_fault_tolerance () =
  Printf.printf "\n=== CHALLENGER 5: CONTACT ENRICHER WATERFALL FAULT TOLERANCE ===\n";
  let base_lead : raw_lead = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 4350000.0;
    owner_name = Some "Pacific Heights Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0576-010";
    last_roof_permit_date = Some "1998-06-01";
    roof_age_years = Some 28.0;
    year_built = Some 1895;
    phone_number = None;
    permits = [];
  } in

  let (lead_t1, stat_t1) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun l -> Ok { l with phone_number = Some "415-346-1920" })
      ~osint_fn:(fun l -> Ok { l with phone_number = Some "415-922-3190" })
      base_lead
  in
  assert_equal_string "C5.1 Tier 1 selected when available" "TIER1_SKIP_TRACER" stat_t1;
  assert_equal_string "C5.2 Tier 1 number attached" "415-346-1920" (Option.value ~default:"" lead_t1.phone_number);

  let (lead_t1_dummy, stat_t1_dummy) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun l -> Ok { l with phone_number = Some "415-555-0142" })
      ~osint_fn:(fun l -> Ok { l with phone_number = Some "415-922-3190" })
      base_lead
  in
  assert_equal_string "C5.3 Tier 1 dummy number triggers fallback to Tier 2" "TIER2_OSINT_SCRAPER" stat_t1_dummy;
  assert_equal_string "C5.4 Tier 2 number attached after Tier 1 dummy rejection"
    "415-922-3190" (Option.value ~default:"" lead_t1_dummy.phone_number);

  let (lead_t1_exn, stat_t1_exn) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun _ -> failwith "Unexpected socket error")
      ~osint_fn:(fun l -> Ok { l with phone_number = Some "415-922-3190" })
      base_lead
  in
  assert_equal_string "C5.5 Tier 1 exception safely caught and falls back to Tier 2"
    "TIER2_OSINT_SCRAPER" stat_t1_exn;
  assert_equal_string "C5.6 Tier 2 number attached after Tier 1 exception"
    "415-922-3190" (Option.value ~default:"" lead_t1_exn.phone_number);

  let (lead_t2_exn, stat_t2_exn) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun _ -> Error "HTTP 502")
      ~osint_fn:(fun _ -> failwith "DuckDuckGo captcha challenge")
      ~seed_directory_fn:(fun _ -> Some "415-752-0422")
      base_lead
  in
  assert_equal_string "C5.7 Tier 1+2 errors fall back to Tier 3 municipal seed"
    "TIER3_MUNICIPAL_DIRECTORY" stat_t2_exn;
  assert_equal_string "C5.8 Tier 3 seed number attached"
    "415-752-0422" (Option.value ~default:"" lead_t2_exn.phone_number);

  let check_t1_fault label t1_fn =
    let (l, s) =
      Contact_enricher.enrich_lead_custom
        ~skip_tracing_fn:t1_fn
        ~osint_fn:(fun l -> Ok { l with phone_number = Some "415-922-3190" })
        base_lead
    in
    assert_equal_string (label ^ " status is TIER2") "TIER2_OSINT_SCRAPER" s;
    assert_equal_string (label ^ " phone is attached") "415-922-3190" (Option.value ~default:"" l.phone_number)
  in
  check_t1_fault "C5.11 Tier 1 missing key (None phone)" (fun l -> Ok { l with phone_number = None });
  check_t1_fault "C5.12 Tier 1 HTTP 401 Unauthorized"
    (fun _ -> Error "Skip tracing API failed with status 401: Unauthorized");
  check_t1_fault "C5.13 Tier 1 HTTP 429 Rate Limit"
    (fun _ -> Error "Skip tracing API failed with status 429: Rate limit exceeded");
  check_t1_fault "C5.14 Tier 1 HTTP 500 Server Error"
    (fun _ -> Error "Skip tracing API failed with status 500: Internal Server Error");
  check_t1_fault "C5.15 Tier 1 network error"
    (fun _ -> Error "Skip tracing network error: Connection refused");

  let check_t1_t2_fail label t1_err t2_err =
    let (l, s) =
      Contact_enricher.enrich_lead_custom
        ~skip_tracing_fn:(fun _ -> Error t1_err)
        ~osint_fn:(fun _ -> Error t2_err)
        ~seed_directory_fn:(fun _ -> Some "415-752-0422")
        base_lead
    in
    assert_equal_string (label ^ " status is TIER3") "TIER3_MUNICIPAL_DIRECTORY" s;
    assert_equal_string (label ^ " seed phone attached") "415-752-0422" (Option.value ~default:"" l.phone_number)
  in
  check_t1_t2_fail "C5.16 T1 401 & T2 404 fallback to T3" "HTTP 401" "HTTP 404";
  check_t1_t2_fail "C5.17 T1 429 & T2 429 fallback to T3" "HTTP 429" "HTTP 429";
  check_t1_t2_fail "C5.18 T1 500 & T2 500 fallback to T3" "HTTP 500" "HTTP 500";
  check_t1_t2_fail "C5.19 T1 Network Error & T2 Network Error fallback to T3" "Network error" "Network error";

  let (l_all_fail, s_all_fail) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun _ -> Error "T1 fail")
      ~osint_fn:(fun _ -> Error "T2 fail")
      ~seed_directory_fn:(fun _ -> None)
      base_lead
  in
  assert_equal_string "C5.20 All tiers fail status is NONE" "NONE" s_all_fail;
  assert_true "C5.21 All tiers fail phone is None" (l_all_fail.phone_number = None);

  let stall_start = Unix.gettimeofday () in
  let stall_completed = ref 0 in
  for i = 1 to 500 do
    let (l_iter, s_iter) =
      Contact_enricher.enrich_lead_custom
        ~skip_tracing_fn:(fun _ -> Error "Simulated error")
        ~osint_fn:(fun _ -> Error "Simulated error")
        ~seed_directory_fn:(fun _ -> None)
        base_lead
    in
    if s_iter = "NONE" && l_iter.phone_number = None then incr stall_completed
  done;
  let stall_duration = Unix.gettimeofday () -. stall_start in
  assert_equal_int "C5.22 500-iteration all-tier failure pipeline completed" 500 !stall_completed;
  assert_true "C5.23 Pipeline runs under 0.2s without stall" (stall_duration < 0.2)

let () =
  Printf.printf "===================================================================\n";
  Printf.printf "=== ROO4U MILESTONE 3: EMPIRICAL ADVERSARIAL CHALLENGER SUITE   ===\n";
  Printf.printf "===================================================================\n";
  test_csv_injection_probes ();
  test_skip_tracer_malformed_json ();
  test_osint_redos_and_false_extractions ();
  test_dummy_number_exhaustive ();
  test_waterfall_fault_tolerance ();
  Printf.printf "\n===================================================================\n";
  Printf.printf "=== CHALLENGER SUMMARY: %d Passed, %d Failed ===\n" !total_passed !total_failed;
  Printf.printf "===================================================================\n";
  if !total_failed > 0 then exit 1 else exit 0
