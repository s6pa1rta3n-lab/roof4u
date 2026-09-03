(**
   test_phone_validation_challenger.ml - Empirical Stress Testing Suite for Phone_validator.
   Challenges NANP phone normalization, dummy number rejection, area code tiers,
   service code filtering, formula injection defenses, and free-form text extraction.
*)

[@@@warning "-32-33-27"]

open Roof_engine

let test_count = ref 0
let pass_count = ref 0
let fail_count = ref 0

let challenge_hyp_tested = ref 0
let challenge_hyp_passed = ref 0
let challenge_hyp_failed = ref 0

(** [assert_true name cond] increments pass or fail counter based on boolean condition. *)
let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n%!" name
  )

(** [assert_equal_str name expected actual] checks string equality. *)
let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s (Expected: '%s', Got: '%s')\n%!" name expected actual
  )

(** [assert_equal_int name expected actual] checks integer equality. *)
let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s (Expected: %d, Got: %d)\n%!" name expected actual
  )

(** [record_hypothesis name cond] tracks adversarial stress-testing hypotheses. *)
let record_hypothesis name cond =
  incr challenge_hyp_tested;
  if cond then (
    incr challenge_hyp_passed;
    Printf.printf "  [HYPOTHESIS CONFIRMED] %s\n%!" name
  ) else (
    incr challenge_hyp_failed;
    Printf.printf "  [HYPOTHESIS DISPROVED] %s\n%!" name
  )

(** [test_international_prefixes ()] stress-tests country code prefixes and non-US numbers. *)
let test_international_prefixes () =
  Printf.printf "\n--- SUITE 1: International Prefix Variations & Non-US Numbers ---\n%!";

  let check_valid_norm label input expected_canonical expected_tier =
    match Phone_validator.sanitize_and_normalize input with
    | Ok vp ->
        assert_equal_str (label ^ " canonical") expected_canonical vp.canonical;
        assert_true (label ^ " tier") (vp.tier = expected_tier);
        assert_true (label ^ " is_valid_phone") (Phone_validator.is_valid_phone input);
        assert_true (label ^ " not is_dummy_number") (not (Phone_validator.is_dummy_number input))
    | Error _ ->
        assert_true (label ^ " unexpected failure") false
  in

  check_valid_norm "INT.PLUS1.HYPHEN" "+1-415-346-1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.PLUS1.PARENS" "+1 (415) 346-1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.PLUS1.SPACE" "+1 415 346 1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.PLUS1.COMPACT" "+14153461234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.PLUS1.DOTTED" "+1.415.346.1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.PLUS1.SF_OVERLAY" "+1 (628) 219-5678" "628-219-5678" Phone_validator.SF_Primary;
  check_valid_norm "INT.PLUS1.BAY_AREA" "+1 (510) 540-1234" "510-540-1234" Phone_validator.Bay_Area;

  check_valid_norm "INT.ONE.HYPHEN" "1-415-346-1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ONE.PARENS" "1 (415) 346-1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ONE.SPACE" "1 415 346 1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ONE.COMPACT" "14153461234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ONE.DOTTED" "1.415.346.1234" "415-346-1234" Phone_validator.SF_Primary;

  check_valid_norm "INT.ITU.HYPHEN" "001-415-346-1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ITU.PARENS" "001 (415) 346-1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ITU.SPACE" "001 415 346 1234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ITU.COMPACT" "0014153461234" "415-346-1234" Phone_validator.SF_Primary;
  check_valid_norm "INT.ITU.DOTTED" "001.415.346.1234" "415-346-1234" Phone_validator.SF_Primary;

  let check_invalid_country label input =
    assert_true (label ^ " is_valid_phone is false") (not (Phone_validator.is_valid_phone input));
    assert_true (label ^ " is_dummy_number is true") (Phone_validator.is_dummy_number input);
    match Phone_validator.sanitize_and_normalize input with
    | Error (Phone_validator.InvalidCountryCode _) ->
        assert_true (label ^ " correctly returns InvalidCountryCode") true
    | Error (Phone_validator.InvalidLength _) ->
        assert_true (label ^ " correctly returns InvalidLength") true
    | Error _ ->
        assert_true (label ^ " returns other validation error") true
    | Ok _ ->
        assert_true (label ^ " unexpectedly succeeded") false
  in

  check_invalid_country "INT.NON_US.UK" "+44 20 7946 0919";
  check_invalid_country "INT.NON_US.FRANCE" "+33 1 42 68 55 55";
  check_invalid_country "INT.NON_US.JAPAN" "+81 3 1234 5678";
  check_invalid_country "INT.NON_US.MEXICO" "+52 55 1234 5678";
  check_invalid_country "INT.NON_US.GERMANY" "+49 30 123456";
  check_invalid_country "INT.NON_US.EGYPT" "+20 2 1234567";
  check_invalid_country "INT.NON_US.ITU_UK" "0044 20 7946 0919";
  check_invalid_country "INT.NON_US.US_EXIT_UK" "011 44 20 7946 0919";
  check_invalid_country "INT.NON_US.INVALID_CC_01" "+01 415 346 1234";
  check_invalid_country "INT.NON_US.INVALID_CC_2" "+2 415 346 1234";

  check_invalid_country "INT.TRUNC.PLUS1" "+1";
  check_invalid_country "INT.TRUNC.PLUS" "+";
  check_invalid_country "INT.TRUNC.001" "001";
  check_invalid_country "INT.TRUNC.001_HYPHEN" "001-";
  check_invalid_country "INT.TRUNC.PLUS1_SHORT" "+1415";
  check_invalid_country "INT.TRUNC.001_SHORT" "001415"

(** [test_boundary_dummy_numbers ()] stress-tests fictitious 555 ranges, repeats, and sequences. *)
let test_boundary_dummy_numbers () =
  Printf.printf "\n--- SUITE 2: Boundary Dummy Numbers & Fictitious Filtering ---\n%!";

  let all_555_rejected = ref true in
  let all_555_is_dummy = ref true in
  for i = 100 to 199 do
    let num = Printf.sprintf "415-555-%04d" i in
    let is_dum = Phone_validator.is_dummy_number num in
    if not is_dum then all_555_is_dummy := false;
    match Phone_validator.sanitize_and_normalize num with
    | Error (Phone_validator.Fictitious555Number _) -> ()
    | _ -> all_555_rejected := false
  done;
  assert_true "DUMMY.555_RANGE.0100_0199: All 100 fictitious numbers return Fictitious555Number" !all_555_rejected;
  assert_true "DUMMY.555_RANGE.IS_DUMMY: All 100 fictitious numbers return is_dummy_number true" !all_555_is_dummy;

  let other_555_numbers = [
    "415-555-0000";
    "415-555-0200";
    "415-555-1234";
    "415-555-9999";
    "555-234-5678";
    "(415) 555-0001";
    "1-415-555-9876";
  ] in
  List.iter (fun num ->
    assert_true ("DUMMY.555_OTHER: Reject " ^ num)
      (not (Phone_validator.is_valid_phone num) && Phone_validator.is_dummy_number num)
  ) other_555_numbers;

  let repeating_10_digits = [
    "000-000-0000";
    "111-111-1111";
    "222-222-2222";
    "333-333-3333";
    "444-444-4444";
    "555-555-5555";
    "666-666-6666";
    "777-777-7777";
    "888-888-8888";
    "999-999-9999";
  ] in
  List.iter (fun num ->
    assert_true ("DUMMY.REPEAT_10: Reject " ^ num)
      (not (Phone_validator.is_valid_phone num) && Phone_validator.is_dummy_number num)
  ) repeating_10_digits;

  let repeating_local_7 = [
    "415-000-0000";
    "415-111-1111";
    "415-222-2222";
    "415-333-3333";
    "415-444-4444";
    "415-555-5555";
    "415-666-6666";
    "415-777-7777";
    "415-888-8888";
    "415-999-9999";
  ] in
  List.iter (fun num ->
    assert_true ("DUMMY.REPEAT_LOCAL7: Reject " ^ num)
      (not (Phone_validator.is_valid_phone num) && Phone_validator.is_dummy_number num)
  ) repeating_local_7;

  assert_true "DUMMY.STATION_0000: Reject 415-346-0000"
    (not (Phone_validator.is_valid_phone "415-346-0000") && Phone_validator.is_dummy_number "415-346-0000");
  assert_true "DUMMY.STATION_1111: Reject 415-346-1111"
    (not (Phone_validator.is_valid_phone "415-346-1111") && Phone_validator.is_dummy_number "415-346-1111");

  assert_true "DUMMY.LEGIT_REPEAT_STATION_2222: 415-346-2222 is valid commercial line"
    (Phone_validator.is_valid_phone "415-346-2222" && not (Phone_validator.is_dummy_number "415-346-2222"));
  assert_true "DUMMY.LEGIT_REPEAT_STATION_3333: 415-346-3333 is valid commercial line"
    (Phone_validator.is_valid_phone "415-346-3333" && not (Phone_validator.is_dummy_number "415-346-3333"));
  assert_true "DUMMY.LEGIT_REPEAT_STATION_8888: 415-346-8888 is valid commercial line"
    (Phone_validator.is_valid_phone "415-346-8888" && not (Phone_validator.is_dummy_number "415-346-8888"));

  let sequential_10_list = [
    "123-456-7890";
    "012-345-6789";
    "987-654-3210";
    "876-543-2109";
  ] in
  List.iter (fun num ->
    assert_true ("DUMMY.SEQ_10: Reject " ^ num)
      (not (Phone_validator.is_valid_phone num) && Phone_validator.is_dummy_number num)
  ) sequential_10_list;

  let sequential_local7_list = [
    "415-123-4567";
    "415-234-5678";
    "415-345-6789";
    "415-456-7890";
    "415-765-4321";
    "415-876-5432";
    "415-987-6543";
    "415-098-7654";
  ] in
  List.iter (fun num ->
    assert_true ("DUMMY.SEQ_LOCAL7: Reject " ^ num)
      (not (Phone_validator.is_valid_phone num) && Phone_validator.is_dummy_number num)
  ) sequential_local7_list;

  assert_true "DUMMY.LEGIT_NON_DUMMY: 415-346-1234 is valid non-dummy"
    (Phone_validator.is_valid_phone "415-346-1234" && not (Phone_validator.is_dummy_number "415-346-1234"));

  let res_6543210 = Phone_validator.is_valid_phone "415-654-3210" in
  record_hypothesis "ADVERSARIAL.LOCAL7_SEQ_GAP: 415-654-3210 descending sequence omission"
    (res_6543210 = true)

(** [test_invalid_first_digits ()] stress-tests NPA and NXX leading digits and 000/111 patterns. *)
let test_invalid_first_digits () =
  Printf.printf "\n--- SUITE 3: Invalid First Digits & Prefix Violations ---\n%!";

  let check_npa_zero input =
    assert_true ("INVALID_START.NPA_ZERO: Reject " ^ input) (not (Phone_validator.is_valid_phone input));
    match Phone_validator.sanitize_and_normalize input with
    | Error (Phone_validator.InvalidNpaStartDigit '0')
    | Error (Phone_validator.InvalidPrefix000or111 "000") ->
        assert_true ("INVALID_START.NPA_ZERO error type for " ^ input) true
    | _ -> assert_true ("INVALID_START.NPA_ZERO unexpected error for " ^ input) false
  in
  check_npa_zero "012-346-1234";
  check_npa_zero "055-346-1234";
  check_npa_zero "099-346-1234";
  check_npa_zero "000-346-1234";

  let check_npa_one input =
    assert_true ("INVALID_START.NPA_ONE: Reject " ^ input) (not (Phone_validator.is_valid_phone input));
    match Phone_validator.sanitize_and_normalize input with
    | Error (Phone_validator.InvalidNpaStartDigit '1')
    | Error (Phone_validator.InvalidPrefix000or111 "111") ->
        assert_true ("INVALID_START.NPA_ONE error type for " ^ input) true
    | _ -> assert_true ("INVALID_START.NPA_ONE unexpected error for " ^ input) false
  in
  check_npa_one "112-346-1234";
  check_npa_one "155-346-1234";
  check_npa_one "199-346-1234";
  check_npa_one "111-346-1234";

  let check_nxx_zero input =
    assert_true ("INVALID_START.NXX_ZERO: Reject " ^ input) (not (Phone_validator.is_valid_phone input));
    match Phone_validator.sanitize_and_normalize input with
    | Error (Phone_validator.InvalidNxxStartDigit '0')
    | Error (Phone_validator.InvalidPrefix000or111 "000") ->
        assert_true ("INVALID_START.NXX_ZERO error type for " ^ input) true
    | _ -> assert_true ("INVALID_START.NXX_ZERO unexpected error for " ^ input) false
  in
  check_nxx_zero "415-012-1234";
  check_nxx_zero "415-055-1234";
  check_nxx_zero "415-099-1234";
  check_nxx_zero "415-000-1234";

  let check_nxx_one input =
    assert_true ("INVALID_START.NXX_ONE: Reject " ^ input) (not (Phone_validator.is_valid_phone input));
    match Phone_validator.sanitize_and_normalize input with
    | Error (Phone_validator.InvalidNxxStartDigit '1')
    | Error (Phone_validator.InvalidPrefix000or111 "111") ->
        assert_true ("INVALID_START.NXX_ONE error type for " ^ input) true
    | _ -> assert_true ("INVALID_START.NXX_ONE unexpected error for " ^ input) false
  in
  check_nxx_one "415-112-1234";
  check_nxx_one "415-155-1234";
  check_nxx_one "415-199-1234";
  check_nxx_one "415-111-1234"

(** [test_n11_toll_free_premium ()] stress-tests service codes, toll-free, and premium rate lines. *)
let test_n11_toll_free_premium () =
  Printf.printf "\n--- SUITE 4: N11 Service Codes, Toll-Free & Premium Rates ---\n%!";

  let n11_codes = ["211"; "311"; "411"; "511"; "611"; "711"; "811"; "911"] in

  List.iter (fun code ->
    let npa_num = Printf.sprintf "%s-346-1234" code in
    assert_true ("N11.NPA: Reject " ^ npa_num) (not (Phone_validator.is_valid_phone npa_num));
    assert_true ("N11.NPA_IS_DUMMY: " ^ npa_num) (Phone_validator.is_dummy_number npa_num);
    match Phone_validator.sanitize_and_normalize npa_num with
    | Error (Phone_validator.ReservedN11Code c) -> assert_equal_str ("N11.NPA_CODE " ^ code) code c
    | _ -> assert_true ("N11.NPA_ERR " ^ code) false
  ) n11_codes;

  List.iter (fun code ->
    let nxx_num = Printf.sprintf "415-%s-1234" code in
    assert_true ("N11.NXX: Reject " ^ nxx_num) (not (Phone_validator.is_valid_phone nxx_num));
    assert_true ("N11.NXX_IS_DUMMY: " ^ nxx_num) (Phone_validator.is_dummy_number nxx_num);
    match Phone_validator.sanitize_and_normalize nxx_num with
    | Error (Phone_validator.ReservedN11Code c) -> assert_equal_str ("N11.NXX_CODE " ^ code) code c
    | _ -> assert_true ("N11.NXX_ERR " ^ code) false
  ) n11_codes;

  let toll_free_codes = ["800"; "888"; "877"; "866"; "855"; "844"; "833"] in
  List.iter (fun tf ->
    let num = Printf.sprintf "%s-234-5678" tf in
    assert_true ("TOLL_FREE: Reject " ^ num) (not (Phone_validator.is_valid_phone num));
    assert_true ("TOLL_FREE_IS_DUMMY: " ^ num) (Phone_validator.is_dummy_number num);
    match Phone_validator.sanitize_and_normalize num with
    | Error (Phone_validator.TollFreeAreaCode c) -> assert_equal_str ("TOLL_FREE_CODE " ^ tf) tf c
    | _ -> assert_true ("TOLL_FREE_ERR " ^ tf) false
  ) toll_free_codes;

  let premium_codes = ["900"; "976"] in
  List.iter (fun pr ->
    let num = Printf.sprintf "%s-234-5678" pr in
    assert_true ("PREMIUM: Reject " ^ num) (not (Phone_validator.is_valid_phone num));
    assert_true ("PREMIUM_IS_DUMMY: " ^ num) (Phone_validator.is_dummy_number num);
    match Phone_validator.sanitize_and_normalize num with
    | Error (Phone_validator.PremiumAreaCode c) -> assert_equal_str ("PREMIUM_CODE " ^ pr) pr c
    | _ -> assert_true ("PREMIUM_ERR " ^ pr) false
  ) premium_codes

(** [test_area_code_tiers ()] stress-tests tier assignment across NANP codes. *)
let test_area_code_tiers () =
  Printf.printf "\n--- SUITE 5: Area Code Tiers & NANP Boundaries ---\n%!";

  let check_tier label npa expected_tier =
    let tier = Phone_validator.get_area_code_tier npa in
    assert_true (label ^ " tier assignment") (tier = expected_tier);
    let is_valid = Phone_validator.is_valid_npa npa in
    if expected_tier = Phone_validator.Invalid_Area then
      assert_true (label ^ " is_valid_npa is false") (not is_valid)
    else
      assert_true (label ^ " is_valid_npa is true") is_valid
  in

  check_tier "TIER.SF_PRIMARY.415" "415" Phone_validator.SF_Primary;
  check_tier "TIER.SF_PRIMARY.628" "628" Phone_validator.SF_Primary;

  check_tier "TIER.BAY_AREA.510" "510" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.341" "341" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.650" "650" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.408" "408" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.669" "669" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.925" "925" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.707" "707" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.369" "369" Phone_validator.Bay_Area;
  check_tier "TIER.BAY_AREA.831" "831" Phone_validator.Bay_Area;

  check_tier "TIER.VALID_US.SEATTLE" "206" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.NYC" "212" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.CHICAGO" "312" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.MIAMI" "305" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.AUSTIN" "512" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.BOSTON" "617" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.LAS_VEGAS" "702" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.HONOLULU" "808" Phone_validator.Valid_US;
  check_tier "TIER.VALID_US.ANCHORAGE" "907" Phone_validator.Valid_US;

  check_tier "TIER.INVALID.800" "800" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.888" "888" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.900" "900" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.976" "976" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.911" "911" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.555" "555" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.012" "012" Phone_validator.Invalid_Area;
  check_tier "TIER.INVALID.123" "123" Phone_validator.Invalid_Area;

  check_tier "TIER.N9X.290" "290" Phone_validator.Invalid_Area;
  check_tier "TIER.N9X.395" "395" Phone_validator.Invalid_Area;
  check_tier "TIER.N9X.899" "899" Phone_validator.Invalid_Area;

  let n9x_is_dummy = Phone_validator.is_dummy_number "290-346-1234" in
  let n9x_is_valid = Phone_validator.is_valid_phone "290-346-1234" in
  record_hypothesis "ADVERSARIAL.IS_DUMMY_N9X_PARITY: is_dummy_number handles N9X invalid area codes"
    (n9x_is_dummy = (not n9x_is_valid))

(** [test_free_form_text_extraction ()] stress-tests boundary isolation and regex parsing. *)
let test_free_form_text_extraction () =
  Printf.printf "\n--- SUITE 6: Free-form Text Extraction & Boundary Isolation ---\n%!";

  let punct_samples = [
    ("Trailing Period", "Call us at 415-346-1234.", "415-346-1234");
    ("Brackets", "Direct line: [415-346-1234]", "415-346-1234");
    ("Double Quotes", "Owner Phone: \"415-346-1234\"", "415-346-1234");
    ("Single Quotes", "Contact '415-346-1234'", "415-346-1234");
    ("Angle Brackets", "Phone <415-346-1234>", "415-346-1234");
    ("Exclamation", "Hurry call (415) 346-1234!", "415-346-1234");
    ("Question Mark", "Is your phone 415-346-1234?", "415-346-1234");
    ("Semicolon", "Office: 415-346-1234;", "415-346-1234");
    ("Comma", "Call 415-346-1234, or email", "415-346-1234");
    ("Colon Preceded", "TEL: 415-346-1234", "415-346-1234");
  ] in

  List.iter (fun (label, text, expected) ->
    let extracted = Phone_validator.extract_valid_phones_from_text text in
    let canonicals = List.map (fun (vp : Phone_validator.validated_phone) -> vp.canonical) extracted in
    assert_true ("EXTRACT.PUNCT." ^ label) (List.mem expected canonicals)
  ) punct_samples;

  let slash_text = "Emergency contacts: (415) 346-1234/(415) 824-1920" in
  let slash_extracted = Phone_validator.extract_valid_phones_from_text slash_text in
  let slash_canonicals = List.map (fun (vp : Phone_validator.validated_phone) -> vp.canonical) slash_extracted in
  assert_true "EXTRACT.SLASH.1: Extracted first phone" (List.mem "415-346-1234" slash_canonicals);
  assert_true "EXTRACT.SLASH.2: Extracted second phone" (List.mem "415-824-1920" slash_canonicals);

  let false_positives = [
    ("Session ID", "session_id=123456789012345");
    ("Embedded Hex Token", "token_a4153461234b");
    ("Alphanumeric Leading", "REF4153461234");
    ("Alphanumeric Trailing", "4153461234EXT");
    ("Oversized 12 Digits", "415346123499");
  ] in

  List.iter (fun (label, text) ->
    let extracted = Phone_validator.extract_valid_phones_from_text text in
    assert_equal_int ("EXTRACT.FALSE_POS." ^ label) 0 (List.length extracted)
  ) false_positives;

  let dummy_text =
    "Do not call dummy numbers: 415-555-0142, 415-888-8888, 800-346-1234, 900-346-1234, 415-911-1234"
  in
  let dummy_extracted = Phone_validator.extract_valid_phones_from_text dummy_text in
  assert_equal_int "EXTRACT.DUMMY_FILTER: Reject all dummy numbers in text" 0 (List.length dummy_extracted);

  let dup_text =
    "Reach us at 415-346-1234 or (415) 346-1234 or +1-415-346-1234 or 415.346.1234 or 4153461234"
  in
  let dup_extracted = Phone_validator.extract_valid_phones_from_text dup_text in
  assert_equal_int "EXTRACT.DEDUPLICATION: Exactly 1 unique phone extracted" 1 (List.length dup_extracted);
  if List.length dup_extracted = 1 then
    assert_equal_str "EXTRACT.DEDUP_VALUE" "415-346-1234" (List.hd dup_extracted).canonical

(** [test_security_and_edge_cases ()] stress-tests injection attacks, empty strings, and malformed inputs. *)
let test_security_and_edge_cases () =
  Printf.printf "\n--- SUITE 7: Formula Injection & Boundary Malformations ---\n%!";

  let injection_payloads = [
    "=cmd|' /C calc'!A0";
    "@SUM(1+1)";
    "\t=cmd|' /C calc'!A0";
    "\r=cmd|' /C calc'!A0";
    "\t@SUM(1+1)";
    "\r@SUM(1+1)";
    "   =415-346-1234";
    "   @415-346-1234";
  ] in

  List.iter (fun payload ->
    assert_true ("INJECTION.REJECT: " ^ String.escaped payload)
      (not (Phone_validator.is_valid_phone payload))
  ) injection_payloads;

  let whitespace_padded_valid = [
    ("Leading Tab", "\t415-346-1234", "415-346-1234");
    ("Leading CR", "\r415-346-1234", "415-346-1234");
    ("Leading Spaces", "   415-346-1234", "415-346-1234");
    ("Trailing Spaces", "415-346-1234   ", "415-346-1234");
  ] in

  List.iter (fun (label, raw, expected) ->
    match Phone_validator.sanitize_and_normalize raw with
    | Ok vp ->
        assert_equal_str ("WHITESPACE.TRIM." ^ label) expected vp.canonical
    | Error _ ->
        assert_true ("WHITESPACE.TRIM." ^ label ^ " unexpected failure") false
  ) whitespace_padded_valid;


  let malformed_inputs = [
    "";
    "   ";
    "\t\n";
    "123";
    "346-1234";
    "41-346-1234";
    "415-34-1234";
    "415-346-123";
    "415-346-12345";
    "phone-number-here";
    "---";
    "###-###-####";
  ] in

  List.iter (fun malf ->
    assert_true ("MALFORMED.REJECT: " ^ String.escaped malf)
      (not (Phone_validator.is_valid_phone malf))
  ) malformed_inputs;

  let test_phone = "415-346-1234" in
  match Phone_validator.sanitize_and_normalize test_phone with
  | Ok vp ->
      assert_equal_str "CANONICAL.FORMAT_CANONICAL" "415-346-1234" (Phone_validator.format_canonical vp);
      assert_equal_str "CANONICAL.NORM_HELPER" "415-346-1234"
        (Option.value ~default:"" (Phone_validator.normalize_to_canonical test_phone))
  | Error _ ->
      assert_true "CANONICAL.UNEXPECTED_FAILURE" false

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Roo4u Milestone 3: Empirical Phone Validator Challenger Suite ===\n";
  Printf.printf "======================================================================\n%!";

  test_international_prefixes ();
  test_boundary_dummy_numbers ();
  test_invalid_first_digits ();
  test_n11_toll_free_premium ();
  test_area_code_tiers ();
  test_free_form_text_extraction ();
  test_security_and_edge_cases ();

  Printf.printf "\n======================================================================\n";
  Printf.printf "=== EMPIRICAL CHALLENGER VERIFICATION RESULTS ===\n";
  Printf.printf "  Standard Assertions: Total=%d, Passed=%d, Failed=%d\n" !test_count !pass_count !fail_count;
  Printf.printf "  Hypotheses Tested:   Total=%d, Confirmed=%d, Disproved=%d\n"
    !challenge_hyp_tested !challenge_hyp_passed !challenge_hyp_failed;
  Printf.printf "======================================================================\n\n%!";

  if !fail_count > 0 then exit 1 else exit 0
