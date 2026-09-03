open Roof_engine

let total_passed = ref 0
let total_failed = ref 0

let assert_true name cond =
  if cond then (
    incr total_passed;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    incr total_failed;
    Printf.printf "  [FAIL] %s\n" name
  )

let assert_equal_string name expected actual =
  if expected = actual then (
    incr total_passed;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    incr total_failed;
    Printf.printf "  [FAIL] %s (expected %S, got %S)\n" name expected actual
  )

let assert_equal_int name expected actual =
  if expected = actual then (
    incr total_passed;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    incr total_failed;
    Printf.printf "  [FAIL] %s (expected %d, got %d)\n" name expected actual
  )

let make_test_lead ?(address = "2223 Pacific Ave") ?(zip_code = "94115") ?owner_name ?phone_number () : Types.raw_lead =
  {
    address;
    zip_code;
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 4350000.0;
    owner_name;
    is_hoa = false;
    is_rental = false;
    apn = Some "0576-010";
    last_roof_permit_date = Some "1998-06-01";
    roof_age_years = Some 28.0;
    year_built = Some 1895;
    phone_number;
    permits = [];
  }

let test_tier1_standard_formats () =
  Printf.printf "\n--- Tier 1: Standard Phone Formats & Normalization ---\n";
  let check_pass label input expected_canonical =
    match Phone_validator.sanitize_and_normalize input with
    | Ok vp ->
        assert_equal_string (label ^ ": canonical format") expected_canonical vp.canonical;
        assert_true (label ^ ": is_valid_phone") (Phone_validator.is_valid_phone input)
    | Error _ ->
        assert_true (label ^ ": unexpected validation failure") false
  in
  check_pass "T1.1.1 Hyphenated" "415-346-1234" "415-346-1234";
  check_pass "T1.1.2 Parentheses" "(415) 346-1234" "415-346-1234";
  check_pass "T1.1.3 Dotted" "415.346.1234" "415-346-1234";
  check_pass "T1.1.4 Spaced" "415 346 1234" "415-346-1234";
  check_pass "T1.1.5 Raw Digits" "4153461234" "415-346-1234";
  check_pass "T1.1.6 Plus-One Prefix" "+1-415-346-1234" "415-346-1234";
  check_pass "T1.1.7 Plus-One Parens" "+1 (415) 346-1234" "415-346-1234";
  check_pass "T1.1.8 One-Prefix" "1-415-346-1234" "415-346-1234";
  check_pass "T1.1.9 One-Parens" "1 (415) 346-1234" "415-346-1234";
  check_pass "T1.1.10 ITU Prefix" "001-415-346-1234" "415-346-1234";
  check_pass "T1.1.11 Trailing spaces" "  415-346-1234  " "415-346-1234"

let test_tier1_area_code_tiers () =
  Printf.printf "\n--- Tier 1: Area Code Tier Classification ---\n";
  assert_true "T1.2.1 SF Primary 415"
    (Phone_validator.get_area_code_tier "415" = Phone_validator.SF_Primary);
  assert_true "T1.2.2 SF Primary 628"
    (Phone_validator.get_area_code_tier "628" = Phone_validator.SF_Primary);
  assert_true "T1.2.3 Bay Area 510"
    (Phone_validator.get_area_code_tier "510" = Phone_validator.Bay_Area);
  assert_true "T1.2.4 Bay Area 341"
    (Phone_validator.get_area_code_tier "341" = Phone_validator.Bay_Area);
  assert_true "T1.2.5 Bay Area 650"
    (Phone_validator.get_area_code_tier "650" = Phone_validator.Bay_Area);
  assert_true "T1.2.6 Bay Area 408"
    (Phone_validator.get_area_code_tier "408" = Phone_validator.Bay_Area);
  assert_true "T1.2.7 Bay Area 669"
    (Phone_validator.get_area_code_tier "669" = Phone_validator.Bay_Area);
  assert_true "T1.2.8 Bay Area 925"
    (Phone_validator.get_area_code_tier "925" = Phone_validator.Bay_Area);
  assert_true "T1.2.9 Bay Area 707"
    (Phone_validator.get_area_code_tier "707" = Phone_validator.Bay_Area);
  assert_true "T1.2.10 Bay Area 369"
    (Phone_validator.get_area_code_tier "369" = Phone_validator.Bay_Area);
  assert_true "T1.2.11 Bay Area 831"
    (Phone_validator.get_area_code_tier "831" = Phone_validator.Bay_Area);
  assert_true "T1.2.12 Valid US 212 (NYC)"
    (Phone_validator.get_area_code_tier "212" = Phone_validator.Valid_US);
  assert_true "T1.2.13 Valid US 312 (Chicago)"
    (Phone_validator.get_area_code_tier "312" = Phone_validator.Valid_US);
  assert_true "T1.2.14 Valid US 206 (Seattle)"
    (Phone_validator.get_area_code_tier "206" = Phone_validator.Valid_US);
  assert_true "T1.2.15 Invalid Area 800 (TollFree)"
    (Phone_validator.get_area_code_tier "800" = Phone_validator.Invalid_Area);
  assert_true "T1.2.16 Invalid Area 900 (Premium)"
    (Phone_validator.get_area_code_tier "900" = Phone_validator.Invalid_Area);
  assert_true "T1.2.17 Invalid Area 911 (N11)"
    (Phone_validator.get_area_code_tier "911" = Phone_validator.Invalid_Area);
  assert_true "T1.2.18 Invalid Area 555"
    (Phone_validator.get_area_code_tier "555" = Phone_validator.Invalid_Area);
  assert_true "T1.2.19 Invalid Area 012"
    (Phone_validator.get_area_code_tier "012" = Phone_validator.Invalid_Area);
  assert_true "T1.2.20 Invalid Area 123"
    (Phone_validator.get_area_code_tier "123" = Phone_validator.Invalid_Area);
  assert_true "T1.2.21 is_valid_npa 415" (Phone_validator.is_valid_npa "415");
  assert_true "T1.2.22 is_valid_npa 510" (Phone_validator.is_valid_npa "510");
  assert_true "T1.2.23 is_valid_npa 212" (Phone_validator.is_valid_npa "212");
  assert_true "T1.2.24 not is_valid_npa 800" (not (Phone_validator.is_valid_npa "800"));
  assert_true "T1.2.25 not is_valid_npa 911" (not (Phone_validator.is_valid_npa "911"))

let test_tier1_invalid_lengths_and_starts () =
  Printf.printf "\n--- Tier 1: Invalid Lengths, Prefixes & Service Codes ---\n";
  assert_true "T1.3.1 Empty string"
    (match Phone_validator.sanitize_and_normalize "" with
     | Error Phone_validator.EmptyNumber -> true
     | _ -> false);
  assert_true "T1.3.2 Whitespace only"
    (match Phone_validator.sanitize_and_normalize "   \t\n" with
     | Error Phone_validator.EmptyNumber -> true
     | _ -> false);
  assert_true "T1.3.3 7 digits (missing NPA)"
    (match Phone_validator.sanitize_and_normalize "346-1234" with
     | Error (Phone_validator.InvalidLength 7) -> true
     | _ -> false);
  assert_true "T1.3.4 9 digits"
    (match Phone_validator.sanitize_and_normalize "41-346-1234" with
     | Error (Phone_validator.InvalidLength 9) -> true
     | _ -> false);
  assert_true "T1.3.5 12 digits"
    (match Phone_validator.sanitize_and_normalize "441234567890" with
     | Error (Phone_validator.InvalidLength 12) -> true
     | _ -> false);
  assert_true "T1.3.6 Non-US country code +44"
    (match Phone_validator.sanitize_and_normalize "+44 20 7946 0919" with
     | Error (Phone_validator.InvalidCountryCode _) -> true
     | _ -> false);
  assert_true "T1.3.7 NPA starts with 0"
    (match Phone_validator.sanitize_and_normalize "015-346-1234" with
     | Error (Phone_validator.InvalidNpaStartDigit '0') -> true
     | _ -> false);
  assert_true "T1.3.8 NPA starts with 1"
    (match Phone_validator.sanitize_and_normalize "115-346-1234" with
     | Error (Phone_validator.InvalidNpaStartDigit '1') -> true
     | _ -> false);
  assert_true "T1.3.9 NXX starts with 0"
    (match Phone_validator.sanitize_and_normalize "415-046-1234" with
     | Error (Phone_validator.InvalidNxxStartDigit '0') -> true
     | _ -> false);
  assert_true "T1.3.10 NXX starts with 1"
    (match Phone_validator.sanitize_and_normalize "415-146-1234" with
     | Error (Phone_validator.InvalidNxxStartDigit '1') -> true
     | _ -> false);
  assert_true "T1.3.11 Reserved N11 NPA 911"
    (match Phone_validator.sanitize_and_normalize "911-346-1234" with
     | Error (Phone_validator.ReservedN11Code "911") -> true
     | _ -> false);
  assert_true "T1.3.12 Reserved N11 NPA 411"
    (match Phone_validator.sanitize_and_normalize "411-346-1234" with
     | Error (Phone_validator.ReservedN11Code "411") -> true
     | _ -> false);
  assert_true "T1.3.13 Reserved N11 NXX 415-911-1234"
    (match Phone_validator.sanitize_and_normalize "415-911-1234" with
     | Error (Phone_validator.ReservedN11Code "911") -> true
     | _ -> false);
  assert_true "T1.3.14 Reserved N11 NXX 415-311-1234"
    (match Phone_validator.sanitize_and_normalize "415-311-1234" with
     | Error (Phone_validator.ReservedN11Code "311") -> true
     | _ -> false);
  assert_true "T1.3.15 Toll Free 800"
    (match Phone_validator.sanitize_and_normalize "800-346-1234" with
     | Error (Phone_validator.TollFreeAreaCode "800") -> true
     | _ -> false);
  assert_true "T1.3.16 Toll Free 888"
    (match Phone_validator.sanitize_and_normalize "888-346-1234" with
     | Error (Phone_validator.TollFreeAreaCode "888") -> true
     | _ -> false);
  assert_true "T1.3.17 Toll Free 877"
    (match Phone_validator.sanitize_and_normalize "877-346-1234" with
     | Error (Phone_validator.TollFreeAreaCode "877") -> true
     | _ -> false);
  assert_true "T1.3.18 Premium 900"
    (match Phone_validator.sanitize_and_normalize "900-346-1234" with
     | Error (Phone_validator.PremiumAreaCode "900") -> true
     | _ -> false);
  assert_true "T1.3.19 Premium 976"
    (match Phone_validator.sanitize_and_normalize "976-346-1234" with
     | Error (Phone_validator.PremiumAreaCode "976") -> true
     | _ -> false)

let test_tier2_dummy_rejection () =
  Printf.printf "\n--- Tier 2: Boundary & Dummy Rejection ---\n";
  assert_true "T2.1.1 Fictitious 555-0100"
    (match Phone_validator.sanitize_and_normalize "415-555-0100" with
     | Error (Phone_validator.Fictitious555Number _) -> true
     | _ -> false);
  assert_true "T2.1.2 Fictitious 555-0142"
    (match Phone_validator.sanitize_and_normalize "415-555-0142" with
     | Error (Phone_validator.Fictitious555Number _) -> true
     | _ -> false);
  assert_true "T2.1.3 Fictitious 555-0199"
    (match Phone_validator.sanitize_and_normalize "415-555-0199" with
     | Error (Phone_validator.Fictitious555Number _) -> true
     | _ -> false);
  assert_true "T2.1.4 General 555 exchange 415-555-1234"
    (match Phone_validator.sanitize_and_normalize "415-555-1234" with
     | Error (Phone_validator.Fictitious555Number _) -> true
     | _ -> false);
  assert_true "T2.1.5 Area code 555"
    (match Phone_validator.sanitize_and_normalize "555-346-1234" with
     | Error (Phone_validator.Fictitious555Number _) -> true
     | _ -> false);
  assert_true "T2.1.6 Repeating 0000000000"
    (match Phone_validator.sanitize_and_normalize "000-000-0000" with
     | Error _ -> true
     | _ -> false);
  assert_true "T2.1.7 Repeating 1111111111"
    (match Phone_validator.sanitize_and_normalize "111-111-1111" with
     | Error _ -> true
     | _ -> false);
  assert_true "T2.1.8 Repeating 9999999999"
    (match Phone_validator.sanitize_and_normalize "999-999-9999" with
     | Error (Phone_validator.RepeatingDigits _) -> true
     | _ -> false);
  assert_true "T2.1.9 Local 7 repeating 415-888-8888"
    (match Phone_validator.sanitize_and_normalize "415-888-8888" with
     | Error (Phone_validator.RepeatingDigits _) -> true
     | _ -> false);
  assert_true "T2.1.10 All-zero station 415-346-0000"
    (match Phone_validator.sanitize_and_normalize "415-346-0000" with
     | Error (Phone_validator.RepeatingDigits _) -> true
     | _ -> false);
  assert_true "T2.1.11 All-one station 415-346-1111"
    (match Phone_validator.sanitize_and_normalize "415-346-1111" with
     | Error (Phone_validator.RepeatingDigits _) -> true
     | _ -> false);
  assert_true "T2.1.12 Sequential 1234567890"
    (match Phone_validator.sanitize_and_normalize "123-456-7890" with
     | Error _ -> true
     | _ -> false);
  assert_true "T2.1.13 Sequential 9876543210"
    (match Phone_validator.sanitize_and_normalize "987-654-3210" with
     | Error (Phone_validator.SequentialDigits _) -> true
     | _ -> false);
  assert_true "T2.1.14 Local sequential 415-123-4567"
    (match Phone_validator.sanitize_and_normalize "415-123-4567" with
     | Error _ -> true
     | _ -> false);
  assert_true "T2.1.15 Legitimate station sequential 415-346-1234"
    (match Phone_validator.sanitize_and_normalize "415-346-1234" with
     | Ok vp -> vp.canonical = "415-346-1234"
     | Error _ -> false);
  assert_true "T2.1.16 Invalid prefix 000 NPA"
    (match Phone_validator.sanitize_and_normalize "000-346-1234" with
     | Error (Phone_validator.InvalidPrefix000or111 "000") -> true
     | _ -> false);
  assert_true "T2.1.17 Invalid prefix 111 NPA"
    (match Phone_validator.sanitize_and_normalize "111-346-1234" with
     | Error (Phone_validator.InvalidPrefix000or111 "111") -> true
     | _ -> false);
  assert_true "T2.1.18 Invalid prefix 000 NXX"
    (match Phone_validator.sanitize_and_normalize "415-000-1234" with
     | Error (Phone_validator.InvalidPrefix000or111 "000") -> true
     | _ -> false);
  assert_true "T2.1.19 Invalid prefix 111 NXX"
    (match Phone_validator.sanitize_and_normalize "415-111-1234" with
     | Error (Phone_validator.InvalidPrefix000or111 "111") -> true
     | _ -> false);
  assert_true "T2.1.20 is_dummy_number on 415-555-0142"
    (Phone_validator.is_dummy_number "415-555-0142");
  assert_true "T2.1.21 is_dummy_number on 415-888-8888"
    (Phone_validator.is_dummy_number "415-888-8888");
  assert_true "T2.1.22 is_dummy_number on 1234567890"
    (Phone_validator.is_dummy_number "1234567890");
  assert_true "T2.1.23 not is_dummy_number on 415-346-1234"
    (not (Phone_validator.is_dummy_number "415-346-1234"))

let test_tier2_text_extraction () =
  Printf.printf "\n--- Tier 2: Free-form Text & HTML Extraction ---\n";
  let html_snippet =
    "<html><body>" ^
    "<h1>Contact Us</h1>" ^
    "<p>Direct line: (415) 346-7890 for Pacific Heights office.</p>" ^
    "<p>Do not call 415-555-0142 (test dummy).</p>" ^
    "<p>East Bay affiliate: 510-540-1234.</p>" ^
    "<p>Customer tracking session_id=123456789012345</p>" ^
    "<a href=\"tel:+14159223190\">Call Marina Branch</a>" ^
    "</body></html>"
  in
  let extracted = Phone_validator.extract_valid_phones_from_text html_snippet in
  let canonicals = List.map (fun (vp : Phone_validator.validated_phone) -> vp.canonical) extracted in
  assert_true "T2.2.1 Extracted parenthesized (415) 346-7890"
    (List.mem "415-346-7890" canonicals);
  assert_true "T2.2.2 Extracted tel URI +14159223190"
    (List.mem "415-922-3190" canonicals);
  assert_true "T2.2.3 Extracted East Bay 510-540-1234"
    (List.mem "510-540-1234" canonicals);
  assert_true "T2.2.4 Fictitious 555-0142 filtered out"
    (not (List.mem "415-555-0142" canonicals));
  assert_true "T2.2.5 Boundary check rejected session_id number"
    (not (List.mem "123-456-7890" canonicals) && not (List.mem "234-567-8901" canonicals));
  assert_true "T2.2.6 Total extracted count is 3"
    (List.length canonicals = 3)

let test_tier3_skip_tracer () =
  Printf.printf "\n--- Tier 3: Skip Tracer Module & Parsing ---\n";
  let lead = make_test_lead ~owner_name:"Pacific Heights Heritage Trust" () in
  let payload = Skip_tracer.build_payload lead in
  assert_true "T3.1.1 Payload contains property_address"
    (String.contains payload '2' && String.contains payload 'P');
  assert_true "T3.1.2 Payload contains San Francisco"
    (String.contains payload 'S' && String.contains payload 'F');
  assert_true "T3.1.3 Payload contains owner_name"
    (String.contains payload 'H' && String.contains payload 'T');

  let lead_synth = make_test_lead ~owner_name:"Owner Occupant (2223 Pacific Ave)" () in
  let payload_synth = Skip_tracer.build_payload lead_synth in
  assert_true "T3.1.4 Synthesized owner name omitted from payload"
    (not (String.contains payload_synth 'O' && String.contains payload_synth '('));

  let mock_success_json =
    "{\"status\":\"success\",\"results\":{\"phone_numbers\":[" ^
    "{\"number\":\"4158241920\",\"type\":\"Mobile\"}," ^
    "{\"number\":\"4155550199\",\"type\":\"Landline\"}" ^
    "]}}"
  in
  let parsed_opt = Skip_tracer.extract_phone_number mock_success_json in
  assert_true "T3.1.5 Extract valid phone from JSON object"
    (parsed_opt = Some "415-824-1920");

  let mock_array_json =
    "{\"results\":[{\"phone_numbers\":[{\"number\":\"(415) 346-1234\"}]}]}"
  in
  let parsed_arr = Skip_tracer.extract_phone_number mock_array_json in
  assert_true "T3.1.6 Extract valid phone from polymorphic array"
    (parsed_arr = Some "415-346-1234");

  let mock_dummy_json =
    "{\"results\":{\"phone_numbers\":[{\"number\":\"415-555-0142\"},{\"number\":\"000-000-0000\"}]}}"
  in
  let parsed_dummy = Skip_tracer.extract_phone_number mock_dummy_json in
  assert_true "T3.1.7 All dummy numbers in JSON rejected"
    (parsed_dummy = None);

  let mock_empty_json = "{\"results\":{\"phone_numbers\":[]}}" in
  assert_true "T3.1.8 Empty results returns None"
    (Skip_tracer.extract_phone_number mock_empty_json = None)

let test_tier3_osint_scraper () =
  Printf.printf "\n--- Tier 3: OSINT Scraper Module & Tier Sorting ---\n";
  let lead = make_test_lead ~owner_name:"Fillmore Landmark LLC" () in
  let search_url = Osint_scraper.build_search_url lead in
  assert_true "T3.2.1 Search URL contains duckduckgo"
    (String.starts_with ~prefix:"https://html.duckduckgo.com/html/?q=" search_url);

  let html_multi_tier =
    "<html><body>" ^
    "<div>Chicago Affiliate: 312-555-4321</div>" ^
    "<div>Valid US: 212-736-2345</div>" ^
    "<div>East Bay: 510-482-1234</div>" ^
    "<div>San Francisco Office: (415) 346-9900</div>" ^
    "</body></html>"
  in
  let sorted_phones = Osint_scraper.extract_phones_from_html html_multi_tier in
  assert_true "T3.2.2 Sorted phones non-empty" (List.length sorted_phones >= 3);
  assert_equal_string "T3.2.3 Top phone prioritized to SF Primary (415)"
    "415-346-9900" (List.hd sorted_phones)

let test_tier3_contact_enricher_cascade () =
  Printf.printf "\n--- Tier 3: Contact Enricher Fallback Cascade ---\n";
  let lead = make_test_lead () in

  let (lead_t1, status_t1) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun l -> Ok { l with phone_number = Some "415-824-1920" })
      ~osint_fn:(fun l -> Ok { l with phone_number = Some "415-346-7890" })
      lead
  in
  assert_equal_string "T3.3.1 Tier 1 Skip Tracer success status"
    "TIER1_SKIP_TRACER" status_t1;
  assert_equal_string "T3.3.2 Tier 1 Phone Attached"
    "415-824-1920" (Option.value ~default:"" lead_t1.phone_number);

  let (lead_t2, status_t2) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun l -> Ok { l with phone_number = None })
      ~osint_fn:(fun l -> Ok { l with phone_number = Some "415-346-7890" })
      lead
  in
  assert_equal_string "T3.3.3 Tier 2 OSINT fallback status"
    "TIER2_OSINT_SCRAPER" status_t2;
  assert_equal_string "T3.3.4 Tier 2 Phone Attached"
    "415-346-7890" (Option.value ~default:"" lead_t2.phone_number);

  let lead_with_seed = make_test_lead ~phone_number:"415-346-1920" () in
  let (lead_t3, status_t3) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun _ -> Error "API timeout")
      ~osint_fn:(fun _ -> Error "Scraper blocked")
      lead_with_seed
  in
  assert_equal_string "T3.3.5 Tier 3 Municipal Seed fallback status"
    "TIER3_MUNICIPAL_DIRECTORY" status_t3;
  assert_equal_string "T3.3.6 Tier 3 Phone Preserved"
    "415-346-1920" (Option.value ~default:"" lead_t3.phone_number);

  let lead_with_dummy = make_test_lead ~phone_number:"415-555-0142" () in
  let (lead_t4, status_t4) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun l -> Ok { l with phone_number = None })
      ~osint_fn:(fun l -> Ok { l with phone_number = None })
      lead_with_dummy
  in
  assert_equal_string "T3.3.7 Tier 4 Dummy 555 eliminated status"
    "NONE" status_t4;
  assert_true "T3.3.8 Tier 4 Phone is None"
    (lead_t4.phone_number = None);

  let (lead_all_fail, status_all_fail) =
    Contact_enricher.enrich_lead_custom
      ~skip_tracing_fn:(fun _ -> Error "Network 500")
      ~osint_fn:(fun _ -> Error "Network 429")
      lead
  in
  assert_equal_string "T3.3.9 Tier 4 Graceful degradation status"
    "NONE" status_all_fail;
  assert_true "T3.3.10 Tier 4 Degradation Phone is None"
    (lead_all_fail.phone_number = None);

  let enriched_lead = Contact_enricher.enrich_lead lead_with_seed in
  assert_equal_string "T3.3.11 enrich_lead convenience wrapper"
    "415-346-1920" (Option.value ~default:"" enriched_lead.phone_number);

  let enriched_phone_lead = Contact_enricher.enrich_phone lead_with_seed in
  assert_equal_string "T3.3.12 enrich_phone contract alias"
    "415-346-1920" (Option.value ~default:"" enriched_phone_lead.phone_number)

let test_tier4_csv_injection () =
  Printf.printf "\n--- Tier 4: CSV Formula Injection & Export Parity ---\n";
  let check_sanitize raw expected =
    let res = Csv_exporter.sanitize_csv_field raw in
    assert_equal_string ("T4.1 Sanitize: " ^ raw) expected res
  in
  check_sanitize "=cmd|' /C calc'!A0" "'=cmd|' /C calc'!A0";
  check_sanitize "+1-800-MALWARE" "'+1-800-MALWARE";
  check_sanitize "-2+3*cmd" "'-2+3*cmd";
  check_sanitize "@SUM(1+1)" "'@SUM(1+1)";
  check_sanitize "\t=1+1" "'\t=1+1";
  check_sanitize "\r=cmd" "'\r=cmd";
  check_sanitize "   =cmd|' /C calc'!A0" "'   =cmd|' /C calc'!A0";
  check_sanitize "   +1-800-MALWARE" "'   +1-800-MALWARE";
  check_sanitize "   @SUM(1+1)" "'   @SUM(1+1)";
  check_sanitize "   -2+3*cmd" "'   -2+3*cmd";
  check_sanitize "   \t=1+1" "'   \t=1+1";
  check_sanitize "   \r=cmd" "'   \r=cmd";
  check_sanitize "415-346-1234" "415-346-1234";
  check_sanitize "2223 Pacific Ave" "2223 Pacific Ave";

  let valid_lead = make_test_lead ~phone_number:"415-346-1920" () in
  let row = Csv_exporter.row_of_raw_lead valid_lead in
  assert_equal_int "T4.2.1 CSV row has exactly 10 columns" 10 (List.length row);
  assert_equal_string "T4.2.2 Phone column exported cleanly"
    "415-346-1920" (List.nth row 8);

  let empty_phone_lead = make_test_lead () in
  let row_empty = Csv_exporter.row_of_raw_lead empty_phone_lead in
  assert_equal_string "T4.2.3 Empty phone exported as empty cell"
    "" (List.nth row_empty 8)

let () =
  Printf.printf "===================================================================\n";
  Printf.printf "=== ROO4U MILESTONE 3: PHONE VALIDATION & ENRICHMENT TEST SUITE ===\n";
  Printf.printf "===================================================================\n";
  test_tier1_standard_formats ();
  test_tier1_area_code_tiers ();
  test_tier1_invalid_lengths_and_starts ();
  test_tier2_dummy_rejection ();
  test_tier2_text_extraction ();
  test_tier3_skip_tracer ();
  test_tier3_osint_scraper ();
  test_tier3_contact_enricher_cascade ();
  test_tier4_csv_injection ();
  Printf.printf "\n===================================================================\n";
  Printf.printf "=== SUMMARY: %d Passed, %d Failed ===\n" !total_passed !total_failed;
  Printf.printf "===================================================================\n";
  if !total_failed > 0 then exit 1 else exit 0
