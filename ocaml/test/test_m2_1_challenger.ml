(**
   test_m2_1_challenger.ml - Benchmark Invariants Empirical Challenger Suite.
   Stress-tests:
     1. All 5 qualified benchmark properties (BENCH-01 through BENCH-05).
     2. All 3 negative control properties (BENCH-FAIL-HOA, BENCH-FAIL-RECENT, BENCH-FAIL-RENTAL).
     3. Valuation boundary values ($999,999.00 vs $1,000,000.00).
     4. Zero-permit structural fallbacks (1996 vs 1997).
     5. Actionability scoring calibration and hypothesis verification (>= 70.0).
     6. Cryptographic SHA-256 proof integrity and tamper resistance.
     7. Heuristic collision vulnerabilities in temporal invariant check.
*)

[@@@warning "-32-33-27"]

open Roof_engine
open Types
open Invariants
open Scorer

let test_count = ref 0
let pass_count = ref 0
let fail_count = ref 0

let challenge_hyp_tested = ref 0
let challenge_hyp_passed = ref 0
let challenge_hyp_failed = ref 0

(** [assert_true name cond] records test pass or failure. *)
let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n%!" name
  )

(** [assert_equal_str name expected actual] records string equality check. *)
let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s (Expected: '%s', Got: '%s')\n%!" name expected actual
  )

(** [assert_equal_int name expected actual] records integer equality check. *)
let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s (Expected: %d, Got: %d)\n%!" name expected actual
  )

(** [assert_equal_float name tolerance expected actual] records float comparison within tolerance. *)
let assert_equal_float name tolerance expected actual =
  incr test_count;
  if abs_float (expected -. actual) <= tolerance then (
    incr pass_count;
    Printf.printf "  [PASS] %s (%.2f == %.2f)\n%!" name actual expected
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s (Expected: %.4f, Got: %.4f)\n%!" name expected actual
  )

(** [record_hypothesis name cond] tracks hypothesis testing pass or failure without aborting execution. *)
let record_hypothesis name cond =
  incr challenge_hyp_tested;
  if cond then (
    incr challenge_hyp_passed;
    Printf.printf "  [HYPOTHESIS-PASS] %s\n%!" name
  ) else (
    incr challenge_hyp_failed;
    Printf.printf "  [HYPOTHESIS-FAIL] %s\n%!" name
  )

(** [make_permit ~num ~desc ~issued ~status ~cost ~is_rep] constructs a permit record. *)
let make_permit ~num ~desc ~issued ~status ~cost ~is_rep =
  let yr = Invariants.extract_year_from_string issued in
  {
    permit_number = num;
    permit_type = Some "Roofing Replacement";
    description = desc;
    date_filed = Some issued;
    date_issued = Some issued;
    status = Some status;
    year = yr;
    is_roof_replacement = is_rep;
    cost = Some cost;
  }

(** [test_qualified_benchmarks ()] executes stress tests for BENCH-01 through BENCH-05. *)
let test_qualified_benchmarks () =
  Printf.printf "\n[Challenge Suite 1] Stress-Testing 5 Qualified Benchmark Properties...\n%!";

  let bench_01 : raw_lead = {
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
    permits = [
      make_permit ~num:"19980512" ~desc:"Complete roof replacement Victorian shingle"
        ~issued:"1998-06-01" ~status:"COMPLETED" ~cost:35000.0 ~is_rep:true;
    ];
  } in
  let v1 = Scorer.verify_lead bench_01 in
  let s1 = Scorer.calculate_score bench_01 in
  assert_true "BENCH-01: Verdict is Qualified"
    (match v1.verdict with Qualified _ -> true | Disqualified _ -> false);
  assert_equal_float "BENCH-01: Expected actionability score 94.08" 0.01 94.08 s1.total_score;
  assert_true "BENCH-01: Score exceeds qualification threshold (>= 60.0)" (s1.total_score >= 60.0);
  record_hypothesis "BENCH-01: Meets score >= 70.0 hypothesis" (s1.total_score >= 70.0);
  assert_equal_int "BENCH-01: Genuine 64-char SHA-256 proof generated" 64 (String.length v1.sha256_proof);
  assert_true "BENCH-01: Proof ID starts with PROOF-OCAML-"
    (String.length v1.proof_id >= 12 && String.sub v1.proof_id 0 12 = "PROOF-OCAML-");

  let bench_02 : raw_lead = {
    address = "2340 Union St";
    zip_code = "94123";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 4100000.0;
    owner_name = Some "Cow Hollow Family Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0530-008";
    last_roof_permit_date = Some "2001-06-05";
    roof_age_years = Some 25.0;
    year_built = Some 1912;
    phone_number = Some "415-555-0211";
    permits = [
      make_permit ~num:"20010518" ~desc:"Full tear-off and replacement of pitched Victorian roof"
        ~issued:"2001-06-05" ~status:"COMPLETED" ~cost:32000.0 ~is_rep:true;
    ];
  } in
  let v2 = Scorer.verify_lead bench_02 in
  let s2 = Scorer.calculate_score bench_02 in
  assert_true "BENCH-02: Verdict is Qualified"
    (match v2.verdict with Qualified _ -> true | Disqualified _ -> false);
  assert_equal_float "BENCH-02: Expected actionability score 88.83" 0.01 88.83 s2.total_score;
  assert_true "BENCH-02: Score exceeds qualification threshold (>= 60.0)" (s2.total_score >= 60.0);
  record_hypothesis "BENCH-02: Meets score >= 70.0 hypothesis" (s2.total_score >= 70.0);
  assert_equal_int "BENCH-02: Genuine 64-char SHA-256 proof generated" 64 (String.length v2.sha256_proof);
  assert_true "BENCH-02: Proof ID starts with PROOF-OCAML-"
    (String.length v2.proof_id >= 12 && String.sub v2.proof_id 0 12 = "PROOF-OCAML-");

  let bench_03 : raw_lead = {
    address = "1840 Chestnut St";
    zip_code = "94123";
    property_type = MultiUnit2To4;
    roof_type = Flat;
    property_type_raw = Some "Multi-Unit (2-4 Units)";
    roof_type_raw = Some "Flat";
    estimated_value = Some 2750000.0;
    owner_name = Some "Marina Residential Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0452-018";
    last_roof_permit_date = Some "2006-11-20";
    roof_age_years = Some 20.0;
    year_built = Some 1924;
    phone_number = Some "415-555-0231";
    permits = [
      make_permit ~num:"20061104" ~desc:"Built-up tar and gravel roof restoration"
        ~issued:"2006-11-20" ~status:"COMPLETED" ~cost:28000.0 ~is_rep:true;
    ];
  } in
  let v3 = Scorer.verify_lead bench_03 in
  let s3 = Scorer.calculate_score bench_03 in
  assert_true "BENCH-03: Verdict is Qualified"
    (match v3.verdict with Qualified _ -> true | Disqualified _ -> false);
  assert_equal_float "BENCH-03: Expected actionability score 68.42" 0.01 68.42 s3.total_score;
  assert_true "BENCH-03: Score exceeds system qualification threshold (>= 60.0)" (s3.total_score >= 60.0);
  record_hypothesis "BENCH-03: Challenge score >= 70.0 hypothesis (Empirical score is 68.42)" (s3.total_score >= 70.0);
  assert_equal_int "BENCH-03: Genuine 64-char SHA-256 proof generated" 64 (String.length v3.sha256_proof);
  assert_true "BENCH-03: Proof ID starts with PROOF-OCAML-"
    (String.length v3.proof_id >= 12 && String.sub v3.proof_id 0 12 = "PROOF-OCAML-");

  let bench_04 : raw_lead = {
    address = "3645 Washington St";
    zip_code = "94118";
    property_type = SingleFamily;
    roof_type = Mansard;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Mansard";
    estimated_value = Some 5200000.0;
    owner_name = Some "Presidio Heights Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0980-003";
    last_roof_permit_date = Some "2002-10-24";
    roof_age_years = Some 24.0;
    year_built = Some 1915;
    phone_number = Some "415-555-0344";
    permits = [
      make_permit ~num:"20021005" ~desc:"Mansard slate roof inspection and rebuild"
        ~issued:"2002-10-24" ~status:"COMPLETED" ~cost:48000.0 ~is_rep:true;
    ];
  } in
  let v4 = Scorer.verify_lead bench_04 in
  let s4 = Scorer.calculate_score bench_04 in
  assert_true "BENCH-04: Verdict is Qualified"
    (match v4.verdict with Qualified _ -> true | Disqualified _ -> false);
  assert_equal_float "BENCH-04: Expected actionability score 91.00" 0.01 91.00 s4.total_score;
  assert_true "BENCH-04: Score exceeds qualification threshold (>= 60.0)" (s4.total_score >= 60.0);
  record_hypothesis "BENCH-04: Meets score >= 70.0 hypothesis" (s4.total_score >= 70.0);
  assert_equal_int "BENCH-04: Genuine 64-char SHA-256 proof generated" 64 (String.length v4.sha256_proof);
  assert_true "BENCH-04: Proof ID starts with PROOF-OCAML-"
    (String.length v4.proof_id >= 12 && String.sub v4.proof_id 0 12 = "PROOF-OCAML-");

  let bench_05 : raw_lead = {
    address = "1845 34th Ave";
    zip_code = "94122";
    property_type = SingleFamily;
    roof_type = Flat;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Flat";
    estimated_value = Some 1550000.0;
    owner_name = Some "Sunset Residential Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "2015-022";
    last_roof_permit_date = Some "2005-03-12";
    roof_age_years = Some 21.0;
    year_built = Some 1936;
    phone_number = Some "415-555-0455";
    permits = [
      make_permit ~num:"20050301" ~desc:"Built-up tar and gravel flat roof replacement"
        ~issued:"2005-03-12" ~status:"COMPLETED" ~cost:24000.0 ~is_rep:true;
    ];
  } in
  let v5 = Scorer.verify_lead bench_05 in
  let s5 = Scorer.calculate_score bench_05 in
  assert_true "BENCH-05: Verdict is Qualified"
    (match v5.verdict with Qualified _ -> true | Disqualified _ -> false);
  assert_equal_float "BENCH-05: Expected actionability score 67.75" 0.01 67.75 s5.total_score;
  assert_true "BENCH-05: Score exceeds system qualification threshold (>= 60.0)" (s5.total_score >= 60.0);
  record_hypothesis "BENCH-05: Challenge score >= 70.0 hypothesis (Empirical score is 67.75)" (s5.total_score >= 70.0);
  assert_equal_int "BENCH-05: Genuine 64-char SHA-256 proof generated" 64 (String.length v5.sha256_proof);
  assert_true "BENCH-05: Proof ID starts with PROOF-OCAML-"
    (String.length v5.proof_id >= 12 && String.sub v5.proof_id 0 12 = "PROOF-OCAML-");

  assert_true "CRYPTO.COLLISION.1: Proofs for distinct properties are unique"
    (v1.sha256_proof <> v2.sha256_proof &&
     v2.sha256_proof <> v3.sha256_proof &&
     v3.sha256_proof <> v4.sha256_proof &&
     v4.sha256_proof <> v5.sha256_proof)

(** [test_negative_controls ()] executes stress tests for negative control properties. *)
let test_negative_controls () =
  Printf.printf "\n[Challenge Suite 2] Stress-Testing 3 Negative Control Properties...\n%!";

  let bench_fail_hoa : raw_lead = {
    address = "200 Brannan St #401";
    zip_code = "94107";
    property_type = Condo;
    roof_type = Flat;
    property_type_raw = Some "Condo";
    roof_type_raw = Some "Flat";
    estimated_value = Some 1850000.0;
    owner_name = Some "Private Owner (Master HOA Deed)";
    is_hoa = true;
    is_rental = false;
    apn = Some "3774-052";
    last_roof_permit_date = Some "2007-04-10";
    roof_age_years = Some 19.0;
    year_built = Some 2005;
    phone_number = None;
    permits = [
      make_permit ~num:"20070401" ~desc:"Commercial flat roof maintenance"
        ~issued:"2007-04-10" ~status:"COMPLETED" ~cost:65000.0 ~is_rep:true;
    ];
  } in
  let v_hoa = Scorer.verify_lead bench_fail_hoa in
  (match v_hoa.verdict with
   | Disqualified { failed_invariants; partial_score; _ } ->
       assert_true "NEG.HOA.1: Verdict is strictly Disqualified" true;
       assert_true "NEG.HOA.2: Fails INV1_Physical"
         (List.exists (fun v -> v.code = INV1_Physical) failed_invariants);
       assert_true "NEG.HOA.3: Fails INV3_Economic"
         (List.exists (fun v -> v.code = INV3_Economic) failed_invariants);
       assert_true "NEG.HOA.4: Does not fail INV2_Temporal"
         (not (List.exists (fun v -> v.code = INV2_Temporal) failed_invariants));
       assert_true "NEG.HOA.5: Does not fail INV4_Permits"
         (not (List.exists (fun v -> v.code = INV4_Permits) failed_invariants));
       assert_equal_int "NEG.HOA.6: Exactly 2 invariant violations" 2 (List.length failed_invariants);
       assert_true "NEG.HOA.7: Computes partial score" (partial_score > 0.0)
   | Qualified _ ->
       assert_true "NEG.HOA.1: Erroneously qualified" false);

  let bench_fail_recent : raw_lead = {
    address = "1500 Sutter St";
    zip_code = "94109";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 3200000.0;
    owner_name = Some "Private Owner";
    is_hoa = false;
    is_rental = false;
    apn = Some "0675-012";
    last_roof_permit_date = Some "2023-08-15";
    roof_age_years = Some 3.0;
    year_built = Some 1900;
    phone_number = None;
    permits = [
      make_permit ~num:"20230815" ~desc:"Complete roof replacement Victorian shingle"
        ~issued:"2023-08-15" ~status:"COMPLETED" ~cost:42000.0 ~is_rep:true;
    ];
  } in
  let v_recent = Scorer.verify_lead bench_fail_recent in
  (match v_recent.verdict with
   | Disqualified { failed_invariants; partial_score; _ } ->
       assert_true "NEG.RECENT.1: Verdict is strictly Disqualified" true;
       assert_true "NEG.RECENT.2: Fails INV2_Temporal"
         (List.exists (fun v -> v.code = INV2_Temporal) failed_invariants);
       assert_true "NEG.RECENT.3: Fails INV4_Permits"
         (List.exists (fun v -> v.code = INV4_Permits) failed_invariants);
       assert_true "NEG.RECENT.4: Does not fail INV1_Physical"
         (not (List.exists (fun v -> v.code = INV1_Physical) failed_invariants));
       assert_true "NEG.RECENT.5: Does not fail INV3_Economic"
         (not (List.exists (fun v -> v.code = INV3_Economic) failed_invariants));
       assert_equal_int "NEG.RECENT.6: Exactly 2 invariant violations" 2 (List.length failed_invariants);
       assert_true "NEG.RECENT.7: Computes partial score" (partial_score > 0.0)
   | Qualified _ ->
       assert_true "NEG.RECENT.1: Erroneously qualified" false);

  let bench_fail_rental : raw_lead = {
    address = "550 Montgomery St";
    zip_code = "94111";
    property_type = Commercial;
    roof_type = Flat;
    property_type_raw = Some "Commercial";
    roof_type_raw = Some "Flat";
    estimated_value = Some 12500000.0;
    owner_name = Some "Financial District Holdings LLC";
    is_hoa = false;
    is_rental = true;
    apn = Some "0230-004";
    last_roof_permit_date = Some "1995-10-02";
    roof_age_years = Some 31.0;
    year_built = Some 1920;
    phone_number = None;
    permits = [
      make_permit ~num:"19951002" ~desc:"Built-up commercial flat roof replacement"
        ~issued:"1995-10-02" ~status:"COMPLETED" ~cost:110000.0 ~is_rep:true;
    ];
  } in
  let v_rental = Scorer.verify_lead bench_fail_rental in
  (match v_rental.verdict with
   | Disqualified { failed_invariants; partial_score; _ } ->
       assert_true "NEG.RENTAL.1: Verdict is strictly Disqualified" true;
       assert_true "NEG.RENTAL.2: Fails INV1_Physical"
         (List.exists (fun v -> v.code = INV1_Physical) failed_invariants);
       assert_true "NEG.RENTAL.3: Fails INV3_Economic"
         (List.exists (fun v -> v.code = INV3_Economic) failed_invariants);
       assert_true "NEG.RENTAL.4: Does not fail INV2_Temporal"
         (not (List.exists (fun v -> v.code = INV2_Temporal) failed_invariants));
       assert_true "NEG.RENTAL.5: Does not fail INV4_Permits"
         (not (List.exists (fun v -> v.code = INV4_Permits) failed_invariants));
       assert_equal_int "NEG.RENTAL.6: Exactly 2 invariant violations" 2 (List.length failed_invariants);
       assert_true "NEG.RENTAL.7: Computes partial score" (partial_score > 0.0)
   | Qualified _ ->
       assert_true "NEG.RENTAL.1: Erroneously qualified" false)

(** [test_valuation_boundaries ()] executes stress tests on economic valuation thresholds. *)
let test_valuation_boundaries () =
  Printf.printf "\n[Challenge Suite 3] Stress-Testing Valuation Boundary Values...\n%!";

  let res_999k = Invariants.check_inv3_economic (Some 999999.00) false false in
  assert_true "VAL.BVA.1: Valuation $999,999.00 fails INV-3"
    (match res_999k with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let res_subcent = Invariants.check_inv3_economic (Some 999999.99) false false in
  assert_true "VAL.BVA.2: Valuation $999,999.99 fails INV-3"
    (match res_subcent with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let res_1m = Invariants.check_inv3_economic (Some 1000000.00) false false in
  assert_true "VAL.BVA.3: Exact valuation $1,000,000.00 passes INV-3"
    (match res_1m with Satisfied _ -> true | _ -> false);

  let res_1m_cent = Invariants.check_inv3_economic (Some 1000000.01) false false in
  assert_true "VAL.BVA.4: Valuation $1,000,000.01 passes INV-3"
    (match res_1m_cent with Satisfied _ -> true | _ -> false);

  let res_none = Invariants.check_inv3_economic None false false in
  assert_true "VAL.BVA.5: Missing valuation (None) fails INV-3"
    (match res_none with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let res_zero = Invariants.check_inv3_economic (Some 0.0) false false in
  assert_true "VAL.BVA.6: Zero valuation ($0.00) fails INV-3"
    (match res_zero with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let res_neg = Invariants.check_inv3_economic (Some (-500000.0)) false false in
  assert_true "VAL.BVA.7: Negative valuation (-$500k) fails INV-3"
    (match res_neg with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let val_score_1m = Scorer.compute_value_score (Some 1000000.0) in
  assert_equal_float "VAL.SCORER.1: Exact $1.0M gets baseline score 15.0" 0.001 15.0 val_score_1m;

  let val_score_5m = Scorer.compute_value_score (Some 5000000.0) in
  assert_equal_float "VAL.SCORER.2: Exact $5.0M gets max score 35.0" 0.001 35.0 val_score_5m;

  let val_score_10m = Scorer.compute_value_score (Some 10000000.0) in
  assert_equal_float "VAL.SCORER.3: High valuation $10.0M clamps at max score 35.0" 0.001 35.0 val_score_10m

(** [test_zero_permit_structural_fallbacks ()] executes stress tests on construction year degradation fallbacks. *)
let test_zero_permit_structural_fallbacks () =
  Printf.printf "\n[Challenge Suite 4] Stress-Testing Zero-Permit Structural Fallback (1996 vs 1997)...\n%!";

  let res_1996_none = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1996) in
  assert_true "STRUCT.1: Construction 1996 (30 yrs in 2026) with None age passes INV-2"
    (match res_1996_none with Satisfied _ -> true | _ -> false);

  let res_1997_none = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1997) in
  assert_true "STRUCT.2: Construction 1997 (29 yrs in 2026) with None age fails INV-2"
    (match res_1997_none with Violated { code = INV2_Temporal; _ } -> true | _ -> false);

  let res_1996_some = Invariants.check_inv2_temporal ~current_year:2026 (Some 30.0) (Some 1996) in
  assert_true "STRUCT.3: Construction 1996 with Some 30.0 age passes INV-2"
    (match res_1996_some with Satisfied _ -> true | _ -> false);

  let res_1997_some = Invariants.check_inv2_temporal ~current_year:2026 (Some 29.0) (Some 1997) in
  assert_true "STRUCT.4: Construction 1997 with Some 29.0 age fails INV-2"
    (match res_1997_some with Violated { code = INV2_Temporal; _ } -> true | _ -> false);

  let res_1995_none = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1995) in
  assert_true "STRUCT.5: Construction 1995 (31 yrs in 2026) passes INV-2"
    (match res_1995_none with Satisfied _ -> true | _ -> false);

  let res_1998_none = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1998) in
  assert_true "STRUCT.6: Construction 1998 (28 yrs in 2026) fails INV-2"
    (match res_1998_none with Violated { code = INV2_Temporal; _ } -> true | _ -> false);

  let res_1900_none = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1900) in
  assert_true "STRUCT.7: Historic 1900 (126 yrs in 2026) passes INV-2"
    (match res_1900_none with Satisfied _ -> true | _ -> false);

  let res_2025_none = Invariants.check_inv2_temporal ~current_year:2026 None (Some 2025) in
  assert_true "STRUCT.8: Recent 2025 (1 yr in 2026) fails INV-2"
    (match res_2025_none with Violated { code = INV2_Temporal; _ } -> true | _ -> false);

  let res_both_none = Invariants.check_inv2_temporal ~current_year:2026 None None in
  assert_true "STRUCT.9: Missing both roof_age and year_built fails INV-2"
    (match res_both_none with Violated { code = INV2_Temporal; _ } -> true | _ -> false)

(** [test_adversarial_vulnerabilities ()] stress-tests failure modes and edge cases. *)
let test_adversarial_vulnerabilities () =
  Printf.printf "\n[Challenge Suite 5] Stress-Testing Adversarial Edge Cases & Heuristic Collisions...\n%!";

  let res_collision = Invariants.check_inv2_temporal ~current_year:2026 (Some 18.0) (Some 2008) in
  let is_falsely_disqualified =
    match res_collision with
    | Violated { code = INV2_Temporal; _ } -> true
    | _ -> false
  in
  record_hypothesis "ADVERSARIAL.HEURISTIC_COLLISION: Documented permit (18 yrs) on 2008 build triggers structural heuristic"
    is_falsely_disqualified;
  Printf.printf "  [CHALLENGE NOTE] Heuristic collision: Property with permit age 18.0 yrs (built 2008) is treated as zero-permit structural fallback and rejected: %b\n%!" is_falsely_disqualified;

  assert_true "HOA.LOT.1: Lot 0499 is not condo" (not (Property_tax_records.is_condo_lot_series "3774-0499"));
  assert_true "HOA.LOT.2: Lot 0500 is start of condo series" (Property_tax_records.is_condo_lot_series "3774-0500");
  assert_true "HOA.LOT.3: Lot 0999 is end of condo series" (Property_tax_records.is_condo_lot_series "3774-0999");
  assert_true "HOA.LOT.4: Lot 1000 is not condo" (not (Property_tax_records.is_condo_lot_series "3774-1000"));

  assert_true "RENTAL.KEYWORD.1: LLC triggers rental"
    (Property_tax_records.is_rental_property ~owner_name:"Sunset Investments LLC" ());
  assert_true "RENTAL.KEYWORD.2: INC triggers rental"
    (Property_tax_records.is_rental_property ~owner_name:"Pacific Coast Builders Inc" ());
  assert_true "RENTAL.KEYWORD.3: CORP triggers rental"
    (Property_tax_records.is_rental_property ~owner_name:"Bay Properties Corp" ());
  assert_true "RENTAL.KEYWORD.4: LP triggers rental"
    (Property_tax_records.is_rental_property ~owner_name:"Presidio Partners LP" ());
  assert_true "RENTAL.KEYWORD.5: HOLDINGS triggers rental"
    (Property_tax_records.is_rental_property ~owner_name:"Richmond Holdings Group" ());

  assert_equal_str "USPS.STRIP.1: Normalize 0422" "422" (Homeowner_addresses.normalize_street_number "0422");
  assert_equal_str "USPS.STRIP.2: Normalize 0000" "0" (Homeowner_addresses.normalize_street_number "0000");
  assert_equal_str "USPS.STRIP.3: Normalize compact 00002223" "2223" (Homeowner_addresses.normalize_street_number "00002223");
  record_hypothesis "ADVERSARIAL.USPS_SPACE_HANDLING: normalize_street_number leaves leading space on '0000 2223'"
    (Homeowner_addresses.normalize_street_number "0000 2223" = " 2223");
  assert_equal_str "USPS.NORM.1: Full USPS Pub 28 normalization"
    "2223 PACIFIC ST" (Homeowner_addresses.normalize_usps_pub28 "0000 2223 PACIFIC STREET");

  let payload1 = "ROO4U-PROOF-V1|2223 Pacific Ave|94115|Single-Family|Victorian|QUALIFIED|94.08|2026-09-01T06:00:00Z" in
  let payload2 = "ROO4U-PROOF-V1|2223 Pacific Ave|94115|Single-Family|Victorian|QUALIFIED|94.09|2026-09-01T06:00:00Z" in
  let hash1 = Crypto.sha256_string payload1 in
  let hash2 = Crypto.sha256_string payload2 in
  assert_true "CRYPTO.AVALANCHE: Minor 0.01 score difference changes proof hash" (hash1 <> hash2);
  assert_equal_int "CRYPTO.DIGEST.LEN: Digest length is exactly 64" 64 (String.length hash1)

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Milestone 2 Benchmark Invariants Challenger Test Suite ===\n";
  Printf.printf "======================================================================\n%!";

  test_qualified_benchmarks ();
  test_negative_controls ();
  test_valuation_boundaries ();
  test_zero_permit_structural_fallbacks ();
  test_adversarial_vulnerabilities ();

  Printf.printf "\n======================================================================\n";
  Printf.printf "=== CHALLENGER TEST RESULTS SUMMARY ===\n";
  Printf.printf "  Standard Assertions: Total=%d, Passed=%d, Failed=%d\n" !test_count !pass_count !fail_count;
  Printf.printf "  Hypothesis Challenges: Total=%d, Passed=%d, Failed=%d\n"
    !challenge_hyp_tested !challenge_hyp_passed !challenge_hyp_failed;
  Printf.printf "======================================================================\n\n%!"
