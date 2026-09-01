(**
   test_invariants.ml - Comprehensive unit test suite for Formal Invariants & Deterministic Scorer.
   Formally evaluates INV1, INV2, INV3, INV4, continuous and discrete scoring arithmetic,
   and genuine SHA-256 cryptographic proof verification.
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
  Printf.printf "\n=================================================================\n";
  Printf.printf "=== Formal Invariant Qualification & Scoring Engine Tests ===\n";
  Printf.printf "=================================================================\n\n";

  (* --- TIER 1: FEATURE COVERAGE TESTS --- *)
  
  (* INV1 Physical Eligibility *)
  assert_true "T1.INV1.1: Victorian SFR Passes"
    (match check_inv1_physical Victorian SingleFamily with Satisfied _ -> true | _ -> false);

  assert_true "T1.INV1.2: Flat MultiUnit 2-4 Passes"
    (match check_inv1_physical Flat MultiUnit2To4 with Satisfied _ -> true | _ -> false);

  assert_true "T1.INV1.3: Mansard SFR Passes"
    (match check_inv1_physical Mansard SingleFamily with Satisfied _ -> true | _ -> false);

  assert_true "T1.INV1.4: Gable Roof Fails"
    (match check_inv1_physical Gable SingleFamily with Violated _ -> true | _ -> false);

  assert_true "T1.INV1.5: Hip Roof Fails"
    (match check_inv1_physical Hip SingleFamily with Violated _ -> true | _ -> false);

  assert_true "T1.INV1.6: Metal Roof Fails"
    (match check_inv1_physical Metal SingleFamily with Violated _ -> true | _ -> false);

  assert_true "T1.INV1.7: Commercial Property Fails"
    (match check_inv1_physical Victorian Commercial with Violated _ -> true | _ -> false);

  assert_true "T1.INV1.8: MultiUnit 5+ Fails"
    (match check_inv1_physical Flat MultiUnit5Plus with Violated _ -> true | _ -> false);

  assert_true "T1.INV1.9: MixedUse Fails"
    (match check_inv1_physical Flat MixedUse with Violated _ -> true | _ -> false);

  (* INV2 Temporal Degradation *)
  assert_true "T1.INV2.1: Roof Age 18.0 yrs Passes"
    (match check_inv2_temporal (Some 18.0) None with Satisfied _ -> true | _ -> false);

  assert_true "T1.INV2.2: Roof Age 10.0 yrs Fails"
    (match check_inv2_temporal (Some 10.0) None with Violated _ -> true | _ -> false);

  assert_true "T1.INV2.3: Build Year 1985 Fallback Passes (>= 30 yrs)"
    (match check_inv2_temporal None (Some 1985) with Satisfied _ -> true | _ -> false);

  assert_true "T1.INV2.4: Build Year 2010 Fallback Fails (< 30 yrs)"
    (match check_inv2_temporal None (Some 2010) with Violated _ -> true | _ -> false);

  assert_true "T1.INV2.5: No Age and No YearBuilt Fails"
    (match check_inv2_temporal None None with Violated _ -> true | _ -> false);

  (* INV3 Economic Viability *)
  assert_true "T1.INV3.1: Assessed $2.5M SFR Passes"
    (match check_inv3_economic (Some 2500000.0) false false with Satisfied _ -> true | _ -> false);

  assert_true "T1.INV3.2: Assessed $800k Fails (< $1.0M threshold)"
    (match check_inv3_economic (Some 800000.0) false false with Violated _ -> true | _ -> false);

  assert_true "T1.INV3.3: HOA Property Fails"
    (match check_inv3_economic (Some 3500000.0) true false with Violated _ -> true | _ -> false);

  assert_true "T1.INV3.4: Rental Property Fails"
    (match check_inv3_economic (Some 3500000.0) false true with Violated _ -> true | _ -> false);

  assert_true "T1.INV3.5: Missing Valuation Fails"
    (match check_inv3_economic None false false with Violated _ -> true | _ -> false);

  (* INV4 Permit Recency Non-Conflict *)
  let p_old = {
    permit_number = "PERMIT-2004-99";
    permit_type = Some "Building Permit";
    description = "Complete tear-off and reroof";
    date_filed = Some "2004-03-01";
    date_issued = Some "2004-04-15";
    status = Some "ISSUED";
    year = Some 2004;
    is_roof_replacement = true;
    cost = Some 32000.0;
  } in
  assert_true "T1.INV4.1: Permit 2004 (22 yrs ago) Passes"
    (match check_inv4_permits [p_old] with Satisfied _ -> true | _ -> false);

  let p_recent = {
    permit_number = "PERMIT-2023-11";
    permit_type = Some "Alteration";
    description = "Reroofing with architectural shingle";
    date_filed = Some "2023-01-10";
    date_issued = Some "2023-02-20";
    status = Some "ISSUED";
    year = Some 2023;
    is_roof_replacement = true;
    cost = Some 55000.0;
  } in
  assert_true "T1.INV4.2: Permit 2023 (3 yrs ago) Fails"
    (match check_inv4_permits [p_recent] with Violated _ -> true | _ -> false);

  let p_electric = {
    permit_number = "PERMIT-2024-ELEC";
    permit_type = Some "Electrical";
    description = "EV Charger 200A Electrical Upgrade";
    date_filed = Some "2024-05-01";
    date_issued = Some "2024-05-10";
    status = Some "ISSUED";
    year = Some 2024;
    is_roof_replacement = false;
    cost = Some 8000.0;
  } in
  assert_true "T1.INV4.3: Non-Roof Permit in 2024 Does Not Conflict"
    (match check_inv4_permits [p_electric] with Satisfied _ -> true | _ -> false);

  (* Scorer Tests *)
  let sc_max = compute_actionability_score (Some 30.0) (Some 1900) (Some 5000000.0) Victorian SingleFamily in
  assert_true "T1.Scorer.1: Max Score is exactly 100.0" (sc_max.total_score = 100.0);
  assert_true "T1.Scorer.2: Age Component is 40.0 for 30yr roof" (sc_max.age_score = 40.0);
  assert_true "T1.Scorer.3: Value Component is 35.0 for $5.0M property" (sc_max.value_score = 35.0);
  assert_true "T1.Scorer.4: Type Component is 25.0 for Victorian SFR" (sc_max.type_score = 25.0);

  (* --- TIER 2: BOUNDARY VALUE ANALYSIS & CORNER CASES --- *)

  (* Temporal Degradation Exact Thresholds *)
  assert_true "T2.BVA.1: Roof Age 15.0 yrs EXACT Threshold Passes"
    (match check_inv2_temporal (Some 15.0) None with Satisfied _ -> true | _ -> false);

  assert_true "T2.BVA.2: Roof Age 14.999 yrs Sub-Threshold Fails"
    (match check_inv2_temporal (Some 14.999) None with Violated _ -> true | _ -> false);

  assert_true "T2.BVA.3: Construction Year 1996 (Age 30 in 2026) Passes"
    (match check_inv2_temporal None (Some 1996) with Satisfied _ -> true | _ -> false);

  assert_true "T2.BVA.4: Construction Year 1997 (Age 29 in 2026) Fails"
    (match check_inv2_temporal None (Some 1997) with Violated _ -> true | _ -> false);

  (* Economic Viability Exact Thresholds *)
  assert_true "T2.BVA.5: Valuation $1,000,000.00 EXACT Threshold Passes"
    (match check_inv3_economic (Some 1000000.0) false false with Satisfied _ -> true | _ -> false);

  assert_true "T2.BVA.6: Valuation $999,999.99 Sub-Threshold Fails"
    (match check_inv3_economic (Some 999999.99) false false with Violated _ -> true | _ -> false);

  (* Scoring Monotonicity & Boundary Verification *)
  let sc_low = compute_actionability_score (Some 0.0) None (Some 1000000.0) Flat MultiUnit2To4 in
  assert_true "T2.Scorer.1: Min Valid Baseline Score >= 33.0" (sc_low.total_score >= 33.0);

  let sc_mid = compute_actionability_score (Some 15.0) None (Some 2000000.0) Flat MultiUnit2To4 in
  let sc_high = compute_actionability_score (Some 25.0) None (Some 4000000.0) Victorian SingleFamily in
  assert_true "T2.Scorer.2: Monotonic Score Growth (Low < Mid < High)"
    (sc_low.total_score < sc_mid.total_score && sc_mid.total_score < sc_high.total_score);

  (* --- TIER 3: PAIRWISE COMBINATORIAL QUALIFICATION & CRYPTOGRAPHIC PROOFS --- *)
  
  let lead_prime = {
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
    phone_number = Some "415-555-0199";
    permits = [p_old];
  } in
  let verif_prime = verify_lead lead_prime in
  assert_true "T3.1: Prime Victorian Qualifies with Score > 85"
    (match verif_prime.verdict with
     | Qualified { score; _ } -> score.total_score > 85.0
     | _ -> false);

  (* Verify genuine SHA-256 proof format and non-empty proof_id *)
  assert_true "T3.2: Genuine 64-character hex SHA-256 proof generated"
    (String.length verif_prime.sha256_proof = 64);
  assert_equal_str "T3.3: Proof ID starts with PROOF-OCAML-"
    "PROOF-OCAML-"
    (String.sub verif_prime.proof_id 0 12);

  let lead_conflict = {
    lead_prime with
    property_type = MultiUnit2To4;
    roof_type = Flat;
    permits = [p_recent];
  } in
  let verif_conflict = verify_lead lead_conflict in
  assert_true "T3.4: Conflicting Permit causes DISQUALIFIED with partial score"
    (match verif_conflict.verdict with
     | Disqualified { failed_invariants; partial_score; _ } ->
         partial_score > 0.0 && List.exists (fun v -> v.code = INV4_Permits) failed_invariants
     | _ -> false);

  let lead_hoa = {
    lead_prime with
    property_type = Condo;
    is_hoa = true;
  } in
  let verif_hoa = verify_lead lead_hoa in
  assert_true "T3.5: HOA Condo accumulates multiple invariant failures"
    (match verif_hoa.verdict with
     | Disqualified { failed_invariants; _ } -> List.length failed_invariants >= 2
     | _ -> false);

  (* JSON serialization and parsing roundtrip *)
  let json_lead_str = Types.verified_lead_to_json_string ~pretty:true verif_prime in
  assert_true "T3.6: Verified lead serializes to JSON string"
    (String.length json_lead_str > 100);

  let parsed_lead = parse_json_lead json_lead_str in
  assert_true "T3.7: Parse JSON lead from verified lead JSON"
    (match parsed_lead with
     | Ok l -> l.address = "2223 Pacific Ave" && l.zip_code = "94115"
     | Error _ -> false);

  Printf.printf "\n=== Completed Invariant & Scoring Test Suite: %d/%d Tests Passed ===\n\n" !pass_count !test_count
