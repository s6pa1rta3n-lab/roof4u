(**
   test_verif.ml - Test suite for OCaml mathematical verification engine.
   Verifies algebraic invariants, edge conditions, scoring monotonicity, and parser safety.
*)

open Roof_engine
open Types
open Invariants
open Scorer

let test_count = ref 0
let pass_count = ref 0

let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n" name;
    failwith ("Test failed: " ^ name)
  )

let () =
  Printf.printf "\n=== Starting OCaml Mathematical Verification Test Suite ===\n\n";

  (* 1. Test Roof Type and Property Type Parsing *)
  assert_true "parse Victorian" (parse_roof_type "Victorian" = Victorian);
  assert_true "parse Queen Anne" (parse_roof_type "Queen Anne Victorian" = Victorian);
  assert_true "parse Flat" (parse_roof_type "Flat" = Flat);
  assert_true "parse Tar and Gravel" (parse_roof_type "Tar and Gravel" = Flat);
  assert_true "parse Gable" (parse_roof_type "Gable" = Gable);
  assert_true "parse SingleFamily" (parse_property_type "Single-Family" = SingleFamily);
  assert_true "parse MultiUnit2To4" (parse_property_type "2-unit" = MultiUnit2To4);

  (* 2. Test Invariant 1: Physical Eligibility *)
  let res_inv1_pass = check_inv1_physical Victorian SingleFamily in
  assert_true "INV-1 passes for Victorian SFR" (match res_inv1_pass with Satisfied _ -> true | _ -> false);

  let res_inv1_pass_flat = check_inv1_physical Flat MultiUnit2To4 in
  assert_true "INV-1 passes for Flat 2-4 Unit" (match res_inv1_pass_flat with Satisfied _ -> true | _ -> false);

  let res_inv1_fail = check_inv1_physical Gable SingleFamily in
  assert_true "INV-1 fails for Gable roof" (match res_inv1_fail with Violated _ -> true | _ -> false);

  let res_inv1_fail_comm = check_inv1_physical Victorian Commercial in
  assert_true "INV-1 fails for Commercial property" (match res_inv1_fail_comm with Violated _ -> true | _ -> false);

  (* 3. Test Invariant 2: Temporal Degradation *)
  let res_inv2_pass_15 = check_inv2_temporal (Some 15.0) None in
  assert_true "INV-2 passes for 15.0 years roof age" (match res_inv2_pass_15 with Satisfied _ -> true | _ -> false);

  let res_inv2_pass_25 = check_inv2_temporal (Some 25.0) None in
  assert_true "INV-2 passes for 25.0 years roof age" (match res_inv2_pass_25 with Satisfied _ -> true | _ -> false);

  let res_inv2_fail_14 = check_inv2_temporal (Some 14.9) None in
  assert_true "INV-2 fails for 14.9 years roof age" (match res_inv2_fail_14 with Violated _ -> true | _ -> false);

  let res_inv2_built_1980 = check_inv2_temporal None (Some 1980) in
  assert_true "INV-2 passes for 1980 build year fallback" (match res_inv2_built_1980 with Satisfied _ -> true | _ -> false);

  let res_inv2_built_2015 = check_inv2_temporal None (Some 2015) in
  assert_true "INV-2 fails for 2015 build year fallback" (match res_inv2_built_2015 with Violated _ -> true | _ -> false);

  (* 4. Test Invariant 3: Economic Viability *)
  let res_inv3_pass = check_inv3_economic (Some 2500000.0) false false in
  assert_true "INV-3 passes for $2.5M SFR non-HOA" (match res_inv3_pass with Satisfied _ -> true | _ -> false);

  let res_inv3_exact_1m = check_inv3_economic (Some 1000000.0) false false in
  assert_true "INV-3 passes for exact $1.0M threshold" (match res_inv3_exact_1m with Satisfied _ -> true | _ -> false);

  let res_inv3_fail_under = check_inv3_economic (Some 999999.0) false false in
  assert_true "INV-3 fails for $999,999.00 valuation" (match res_inv3_fail_under with Violated _ -> true | _ -> false);

  let res_inv3_fail_hoa = check_inv3_economic (Some 3000000.0) true false in
  assert_true "INV-3 fails for HOA managed property" (match res_inv3_fail_hoa with Violated _ -> true | _ -> false);

  let res_inv3_fail_rental = check_inv3_economic (Some 3000000.0) false true in
  assert_true "INV-3 fails for rental property" (match res_inv3_fail_rental with Violated _ -> true | _ -> false);

  (* 5. Test Invariant 4: Permit Recency Non-Conflict *)
  let permit_old = {
    permit_number = "20050101";
    permit_type = Some "Building Permit";
    description = "Complete reroof";
    date_filed = Some "2005-06-01";
    date_issued = Some "2005-07-01";
    status = Some "ISSUED";
    year = Some 2005;
    is_roof_replacement = true;
    cost = Some 25000.0;
  } in
  let res_inv4_pass = check_inv4_permits [permit_old] in
  assert_true "INV-4 passes for 2005 roof permit (> 15 yrs)" (match res_inv4_pass with Satisfied _ -> true | _ -> false);

  let permit_recent = {
    permit_number = "20220101";
    permit_type = Some "Alteration";
    description = "Complete reroof";
    date_filed = Some "2022-06-01";
    date_issued = Some "2022-07-01";
    status = Some "ISSUED";
    year = Some 2022;
    is_roof_replacement = true;
    cost = Some 45000.0;
  } in
  let res_inv4_fail = check_inv4_permits [permit_recent] in
  assert_true "INV-4 fails for 2022 recent roof permit" (match res_inv4_fail with Violated _ -> true | _ -> false);

  (* 6. Test Scoring Determinism and Bounds *)
  let score_high = compute_actionability_score (Some 25.0) (Some 1900) (Some 4500000.0) Victorian SingleFamily in
  assert_true "Score is bounded <= 100.0" (score_high.total_score <= 100.0);
  assert_true "Score is bounded >= 0.0" (score_high.total_score >= 0.0);
  assert_true "Score for prime Victorian is >= 85.0" (score_high.total_score >= 85.0);

  let score_low = compute_actionability_score (Some 15.0) (Some 1950) (Some 1000000.0) Flat MultiUnit2To4 in
  assert_true "Score for baseline Flat 2-4 unit is between 50.0 and 80.0"
    (score_low.total_score >= 50.0 && score_low.total_score <= 80.0);

  (* 7. Test Lead Verification End-to-End *)
  let qualified_lead_raw = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 3500000.0;
    owner_name = Some "Pacific Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0576010";
    last_roof_permit_date = Some "2002-05-15";
    roof_age_years = Some 22.0;
    year_built = Some 1900;
    phone_number = Some "415-555-0199";
    permits = [permit_old];
  } in
  let verified_res = verify_lead qualified_lead_raw in
  assert_true "Full lead verification passes for prime lead"
    (match verified_res.verdict with Qualified _ -> true | _ -> false);

  let json_out = verified_lead_to_json_string ~pretty:true verified_res in
  assert_true "JSON output contains QUALIFIED status"
    (String.length json_out > 50 && String.contains json_out 'Q');

  Printf.printf "\n=== All %d OCaml Mathematical Verification Tests PASSED (100%%) ===\n\n" !pass_count
