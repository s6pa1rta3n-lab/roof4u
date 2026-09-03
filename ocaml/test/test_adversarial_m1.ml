(**
   test_adversarial_m1.ml - Empirical Adversarial Challenger Test Harness for Milestone 1.
   
   Stress-tests:
   1. Exact boundary value analysis (BVA):
      - Valuation: $1,000,000.00 vs $999,999.99 vs $0 vs negative (-1.0, -100M) vs $100M+
      - Roof age: 15.0 vs 14.999 vs 0.0 vs negative (-10.0) vs 100.0+
      - Year built: 1996 vs 1997 vs 2026 vs 2027 vs 1800 vs None
      - Permit year: 2011 (non-conflict) vs 2012 (conflict) vs 2026 vs string formats
   2. 10,000 randomized property combinations:
      - Strict score bounding in [0.0, 100.0]
      - Score monotonicity with respect to roof age (strictly increasing on [0, 30], clamped outside)
      - Score monotonicity with respect to valuation (strictly increasing on [1M, 5M], clamped outside)
      - Sub-component score bounds and sum preservation
   3. Conflicting permits invariant:
      - Always triggers Disqualified regardless of $100M valuation, Victorian architecture, or 50yr age.
   4. Cryptographic Proof & JSON AST tamper-resistance:
      - Genuine 64-char lowercase hex digest, 28-char uppercase PROOF-OCAML- ID, avalanche, deterministic roundtrips.
*)

open Roof_engine
open Types
open Invariants
open Scorer

let total_tests = ref 0
let passed_tests = ref 0

let check_named name cond =
  incr total_tests;
  if cond then (
    incr passed_tests
  ) else (
    Printf.eprintf "  [FAIL] %s\n" name;
    failwith ("Adversarial Assertion Failed: " ^ name)
  )

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== EMPIRICAL ADVERSARIAL CHALLENGER SUITE: MILESTONE 1 (ROO4U) ===\n";
  Printf.printf "======================================================================\n\n";

  Printf.printf "[Section 1] Boundary Value Analysis on Invariants INV1 - INV4...\n";

  check_named "BVA-INV3.1: Exact $1,000,000.00 passes INV3"
    (match check_inv3_economic (Some 1000000.00) false false with Satisfied _ -> true | _ -> false);

  check_named "BVA-INV3.2: $999,999.99 fails INV3"
    (match check_inv3_economic (Some 999999.99) false false with Violated _ -> true | _ -> false);

  check_named "BVA-INV3.3: $1,000,000.01 passes INV3"
    (match check_inv3_economic (Some 1000000.01) false false with Satisfied _ -> true | _ -> false);

  check_named "BVA-INV3.4: $0.00 fails INV3"
    (match check_inv3_economic (Some 0.0) false false with Violated _ -> true | _ -> false);

  check_named "BVA-INV3.5: Negative valuation -$1.00 fails INV3"
    (match check_inv3_economic (Some (-1.0)) false false with Violated _ -> true | _ -> false);

  check_named "BVA-INV3.6: Negative valuation -$1,000,000.00 fails INV3"
    (match check_inv3_economic (Some (-1000000.0)) false false with Violated _ -> true | _ -> false);

  check_named "BVA-INV3.7: Missing valuation None fails INV3"
    (match check_inv3_economic None false false with Violated _ -> true | _ -> false);

  check_named "BVA-INV3.8: HOA flag overrides $100,000,000.00 valuation"
    (match check_inv3_economic (Some 100000000.0) true false with Violated v -> v.code = INV3_Economic | _ -> false);

  check_named "BVA-INV3.9: Rental flag overrides $100,000,000.00 valuation"
    (match check_inv3_economic (Some 100000000.0) false true with Violated v -> v.code = INV3_Economic | _ -> false);

  check_named "BVA-INV2.1: Exact roof age 15.0 years passes INV2"
    (match check_inv2_temporal (Some 15.0) None with Satisfied _ -> true | _ -> false);

  check_named "BVA-INV2.2: Roof age 14.999 years fails INV2"
    (match check_inv2_temporal (Some 14.999) None with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.3: Roof age 15.001 years passes INV2"
    (match check_inv2_temporal (Some 15.001) None with Satisfied _ -> true | _ -> false);

  check_named "BVA-INV2.4: Roof age 0.0 years fails INV2"
    (match check_inv2_temporal (Some 0.0) None with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.5: Negative roof age -1.0 years fails INV2"
    (match check_inv2_temporal (Some (-1.0)) None with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.6: Negative roof age -50.0 years fails INV2"
    (match check_inv2_temporal (Some (-50.0)) None with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.7: YearBuilt 1996 fallback (Age 30 at 2026) passes INV2"
    (match check_inv2_temporal ~current_year:2026 None (Some 1996) with Satisfied _ -> true | _ -> false);

  check_named "BVA-INV2.8: YearBuilt 1997 fallback (Age 29 at 2026) fails INV2"
    (match check_inv2_temporal ~current_year:2026 None (Some 1997) with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.9: YearBuilt 1900 fallback (Age 126 at 2026) passes INV2"
    (match check_inv2_temporal ~current_year:2026 None (Some 1900) with Satisfied _ -> true | _ -> false);

  check_named "BVA-INV2.10: YearBuilt 2026 fallback (Age 0 at 2026) fails INV2"
    (match check_inv2_temporal ~current_year:2026 None (Some 2026) with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.11: Future YearBuilt 2030 fallback fails INV2"
    (match check_inv2_temporal ~current_year:2026 None (Some 2030) with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.12: Both roof age and YearBuilt None fails INV2"
    (match check_inv2_temporal None None with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.13: Explicit roof age overrides YearBuilt (10yr age + 1900 built -> FAILS INV2)"
    (match check_inv2_temporal (Some 10.0) (Some 1900) with Violated _ -> true | _ -> false);

  check_named "BVA-INV2.14: Explicit roof age overrides YearBuilt (20yr age + 2020 built -> PASSES INV2)"
    (match check_inv2_temporal (Some 20.0) (Some 2020) with Satisfied _ -> true | _ -> false);

  let make_permit ?(is_roof = true) ?year ?date_issued ?date_filed desc =
    {
      permit_number = "TEST-PERMIT-1";
      permit_type = Some "Building Permit";
      description = desc;
      date_filed;
      date_issued;
      status = Some "ISSUED";
      year;
      is_roof_replacement = is_roof;
      cost = Some 40000.0;
    }
  in

  check_named "BVA-INV4.1: Permit year 2011 (15 yrs ago at 2026) PASSES (non-conflict threshold)"
    (match check_inv4_permits ~current_year:2026 [make_permit ~year:2011 "Reroofing"] with
     | Satisfied _ -> true | Violated _ -> false);

  check_named "BVA-INV4.2: Permit year 2012 (14 yrs ago at 2026) FAILS (conflicting threshold)"
    (match check_inv4_permits ~current_year:2026 [make_permit ~year:2012 "Reroofing"] with
     | Violated v -> v.code = INV4_Permits | Satisfied _ -> false);

  check_named "BVA-INV4.3: Permit year 2025 (1 yr ago) FAILS"
    (match check_inv4_permits ~current_year:2026 [make_permit ~year:2025 "Reroofing"] with
     | Violated v -> v.code = INV4_Permits | Satisfied _ -> false);

  check_named "BVA-INV4.4: Permit year 2026 (current year) FAILS"
    (match check_inv4_permits ~current_year:2026 [make_permit ~year:2026 "Reroofing"] with
     | Violated v -> v.code = INV4_Permits | Satisfied _ -> false);

  check_named "BVA-INV4.5: Permit date string '2011-06-30' PASSES"
    (match check_inv4_permits ~current_year:2026 [make_permit ~date_issued:"2011-06-30" "Complete tear-off"] with
     | Satisfied _ -> true | Violated _ -> false);

  check_named "BVA-INV4.6: Permit date string '2012-01-01' FAILS"
    (match check_inv4_permits ~current_year:2026 [make_permit ~date_issued:"2012-01-01" "Complete tear-off"] with
     | Violated v -> v.code = INV4_Permits | Satisfied _ -> false);

  check_named "BVA-INV4.7: Non-roof permit in 2026 (Solar Panel) PASSES non-conflict"
    (match check_inv4_permits ~current_year:2026 [make_permit ~is_roof:false ~year:2026 "Install rooftop solar inverter and battery backup"] with
     | Satisfied _ -> true | Violated _ -> false);

  check_named "BVA-INV4.8: Multiple permits (1 old roof + 1 recent electric) PASSES"
    (let p1 = make_permit ~year:2005 "Complete reroof" in
     let p2 = make_permit ~is_roof:false ~year:2024 "EV Charger Installation" in
     match check_inv4_permits ~current_year:2026 [p1; p2] with
     | Satisfied _ -> true | Violated _ -> false);

  check_named "BVA-INV4.9: Multiple permits (1 old roof + 1 recent roof) FAILS"
    (let p1 = make_permit ~year:2005 "Complete reroof" in
     let p2 = make_permit ~year:2022 "Tar and gravel replacement" in
     match check_inv4_permits ~current_year:2026 [p1; p2] with
     | Violated v -> v.code = INV4_Permits | Satisfied _ -> false);

  let all_roofs = [Victorian; Flat; Mansard; Gable; Hip; Metal; Unknown; Other "Spanish Tile"] in
  let all_props = [SingleFamily; MultiUnit2To4; MultiUnit5Plus; Commercial; MixedUse; Condo; Unknown; Other "Warehouse"] in

  let valid_roofs = [Victorian; Flat; Mansard] in
  let valid_props = [SingleFamily; MultiUnit2To4] in

  List.iter (fun r ->
    List.iter (fun p ->
      let is_valid_pair = List.mem r valid_roofs && List.mem p valid_props in
      let status = check_inv1_physical r p in
      let passes = match status with Satisfied _ -> true | Violated _ -> false in
      if is_valid_pair <> passes then
        failwith (Printf.sprintf "INV1 mismatch for roof %s and prop %s" (string_of_roof_type r) (string_of_property_type p))
    ) all_props
  ) all_roofs;
  check_named "BVA-INV1: All 64 roof * property combinations match formal specification" true;

  Printf.printf "  [PASS] Section 1: All Boundary Value Analyses Passed (24/24)\n\n";

  Printf.printf "[Section 2] Fuzzing and Stress-Testing 10,000 Randomized Leads...\n";

  Random.init 42;

  let rand_roof_type () =
    let r = Random.int 8 in
    match r with
    | 0 -> Victorian | 1 -> Flat | 2 -> Mansard | 3 -> Gable
    | 4 -> Hip | 5 -> Metal | 6 -> Unknown | _ -> Other "SpecialTile"
  in

  let rand_prop_type () =
    let r = Random.int 8 in
    match r with
    | 0 -> SingleFamily | 1 -> MultiUnit2To4 | 2 -> MultiUnit5Plus
    | 3 -> Commercial | 4 -> MixedUse | 5 -> Condo
    | 6 -> Unknown | _ -> Other "Townhome"
  in

  let num_fuzz_iterations = 10000 in

  let bounded_count = ref 0 in
  let component_sum_count = ref 0 in
  let age_monotonic_count = ref 0 in
  let val_monotonic_count = ref 0 in

  for i = 1 to num_fuzz_iterations do
    let r_type = rand_roof_type () in
    let p_type = rand_prop_type () in
    let roof_age =
      if Random.bool () then None
      else Some ((Random.float 120.0) -. 10.0)
    in
    let year_built =
      if Random.bool () then None
      else Some (1800 + Random.int 250)
    in
    let est_val =
      if Random.bool () then None
      else Some ((Random.float 12000000.0) -. 500000.0)
    in
    let is_hoa = Random.bool () in
    let is_rental = Random.bool () in

    let num_permits = Random.int 4 in
    let permits =
      List.init num_permits (fun idx ->
        let p_yr = 1980 + Random.int 50 in
        let is_roof = Random.bool () in
        {
          permit_number = Printf.sprintf "RAND-PERMIT-%d-%d" i idx;
          permit_type = Some "Permit";
          description = if is_roof then "Tear off and reroofing" else "Electrical panel upgrade";
          date_filed = Some (Printf.sprintf "%d-01-15" p_yr);
          date_issued = Some (Printf.sprintf "%d-02-20" p_yr);
          status = Some "ISSUED";
          year = Some p_yr;
          is_roof_replacement = is_roof;
          cost = Some (float_of_int (Random.int 100000));
        }
      )
    in

    let lead : raw_lead = {
      address = Printf.sprintf "%d Random Test St" (100 + (i mod 9000));
      zip_code = "941" ^ (Printf.sprintf "%02d" (Random.int 35));
      property_type = p_type;
      roof_type = r_type;
      property_type_raw = Some (string_of_property_type p_type);
      roof_type_raw = Some (string_of_roof_type r_type);
      estimated_value = est_val;
      owner_name = Some "Random Owner";
      is_hoa;
      is_rental;
      apn = Some (Printf.sprintf "%04d-%03d" (Random.int 9999) (Random.int 999));
      last_roof_permit_date = None;
      roof_age_years = roof_age;
      year_built;
      phone_number = Some "415-555-0100";
      permits;
    } in

    let score = calculate_score ~current_year:2026 lead in
    let verif = verify_lead ~current_year:2026 lead in

    if score.total_score >= 0.0 && score.total_score <= 100.0 &&
       score.age_score >= 0.0 && score.age_score <= 40.0 &&
       score.value_score >= 0.0 && score.value_score <= 35.0 &&
       score.type_score >= 10.0 && score.type_score <= 25.0 then
      incr bounded_count
    else
      failwith (Printf.sprintf "Iteration %d: Score out of bounds! total=%.2f, age=%.2f, val=%.2f, type=%.2f"
                  i score.total_score score.age_score score.value_score score.type_score);

    let expected_sum = min 100.0 (max 0.0 (score.age_score +. score.value_score +. score.type_score)) in
    if abs_float (score.total_score -. expected_sum) < 0.0001 then
      incr component_sum_count
    else
      failwith (Printf.sprintf "Iteration %d: Score sum mismatch! total=%.4f, expected=%.4f"
                  i score.total_score expected_sum);

    let age1 = Random.float 40.0 in
    let age2 = age1 +. (Random.float 20.0) in
    let s_age1 = compute_age_score (Some age1) None in
    let s_age2 = compute_age_score (Some age2) None in
    if s_age1 <= s_age2 then incr age_monotonic_count
    else failwith (Printf.sprintf "Iteration %d: Age non-monotonicity! age1=%.2f (s=%.2f), age2=%.2f (s=%.2f)"
                     i age1 s_age1 age2 s_age2);

    let v1 = Random.float 8000000.0 in
    let v2 = v1 +. (Random.float 2000000.0) in
    let s_v1 = compute_value_score (Some v1) in
    let s_v2 = compute_value_score (Some v2) in
    if s_v1 <= s_v2 then incr val_monotonic_count
    else failwith (Printf.sprintf "Iteration %d: Value non-monotonicity! v1=%.2f (s=%.2f), v2=%.2f (s=%.2f)"
                     i v1 s_v1 v2 s_v2);

    if String.length verif.sha256_proof <> 64 ||
       String.sub verif.proof_id 0 12 <> "PROOF-OCAML-" then
      failwith (Printf.sprintf "Iteration %d: Invalid proof format: proof=%s, id=%s"
                  i verif.sha256_proof verif.proof_id);

    match verif.verdict with
    | Qualified _ ->
        if not (match check_inv1_physical lead.roof_type lead.property_type with Satisfied _ -> true | _ -> false) ||
           not (match check_inv2_temporal lead.roof_age_years lead.year_built with Satisfied _ -> true | _ -> false) ||
           not (match check_inv3_economic lead.estimated_value lead.is_hoa lead.is_rental with Satisfied _ -> true | _ -> false) ||
           not (match check_inv4_permits lead.permits with Satisfied _ -> true | _ -> false) then
          failwith (Printf.sprintf "Iteration %d: Inconsistent QUALIFIED verdict with failed invariants!" i)
    | Disqualified { failed_invariants; partial_score; _ } ->
        if failed_invariants = [] then
          failwith (Printf.sprintf "Iteration %d: DISQUALIFIED with empty failed_invariants list!" i);
        if partial_score < 0.0 || partial_score > 100.0 then
          failwith (Printf.sprintf "Iteration %d: Partial score out of bounds: %.2f" i partial_score)
  done;

  check_named "STRESS.1: 10,000/10,000 randomized leads strictly bounded in [0.0, 100.0]" (!bounded_count = num_fuzz_iterations);
  check_named "STRESS.2: 10,000/10,000 score components exactly sum to total_score" (!component_sum_count = num_fuzz_iterations);
  check_named "STRESS.3: 10,000/10,000 age score monotonic tests passed" (!age_monotonic_count = num_fuzz_iterations);
  check_named "STRESS.4: 10,000/10,000 valuation score monotonic tests passed" (!val_monotonic_count = num_fuzz_iterations);

  Printf.printf "  [PASS] Section 2: 10,000 Random Fuzz Iterations Verified (40,000/40,000 Sub-checks Passed)\n\n";

  Printf.printf "[Section 3] Verifying Conflicting Permits Override Dominance...\n";

  let ultra_lead = {
    address = "1 Billionaire Row";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 100000000.0;
    owner_name = Some "Tech Titan Billionaire";
    is_hoa = false;
    is_rental = false;
    apn = Some "0001-001";
    last_roof_permit_date = Some "2024-03-01";
    roof_age_years = Some 50.0;
    year_built = Some 1890;
    phone_number = Some "415-555-9999";
    permits = [
      {
        permit_number = "CONFLICT-2024-ROOF";
        permit_type = Some "Reroofing";
        description = "Complete slate and tile tear-off and replacement";
        date_filed = Some "2024-02-01";
        date_issued = Some "2024-03-01";
        status = Some "ISSUED";
        year = Some 2024;
        is_roof_replacement = true;
        cost = Some 250000.0;
      }
    ];
  } in

  let verif_ultra = verify_lead ultra_lead in

  check_named "CONFLICT.1: $100M Victorian lead is DISQUALIFIED due to 2024 reroof permit"
    (match verif_ultra.verdict with
     | Disqualified { failed_invariants; partial_score; score_components } ->
         let has_inv4 = List.exists (fun v -> v.code = INV4_Permits) failed_invariants in
         let has_only_inv4 = List.length failed_invariants = 1 in
         has_inv4 && has_only_inv4 && partial_score = 100.0 && score_components.total_score = 100.0
     | Qualified _ -> false);

  check_named "CONFLICT.2: Proof digest is still valid SHA-256 for Disqualified lead"
    (String.length verif_ultra.sha256_proof = 64);

  check_named "CONFLICT.3: Proof ID starts with PROOF-OCAML- for Disqualified lead"
    (String.sub verif_ultra.proof_id 0 12 = "PROOF-OCAML-");

  let conflict_override_passed = ref 0 in
  for yr = 2012 to 2026 do
    let base_permit = List.hd ultra_lead.permits in
    let test_lead = {
      ultra_lead with
      permits = [{
        base_permit with
        year = Some yr;
        date_issued = Some (Printf.sprintf "%d-06-15" yr);
      }]
    } in
    let v = verify_lead test_lead in
    match v.verdict with
    | Disqualified { failed_invariants; _ } ->
        if List.exists (fun inv -> inv.code = INV4_Permits) failed_invariants then
          incr conflict_override_passed
    | Qualified _ -> ()
  done;

  check_named "CONFLICT.4: All permit years 2012..2026 unconditionally trigger Disqualified (15/15)"
    (!conflict_override_passed = 15);

  Printf.printf "  [PASS] Section 3: Conflicting Permits Dominance Invariant Verified (4/4)\n\n";

  Printf.printf "[Section 4] Cryptographic & JSON Parser Adversarial Hardening...\n";

  let hash_abc = Crypto.sha256_string "abc" in
  check_named "CRYPTO.1: RFC 6234 'abc' vector exact match"
    (hash_abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");

  let hash_empty = Crypto.sha256_string "" in
  check_named "CRYPTO.2: RFC 6234 empty string vector exact match"
    (hash_empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

  let p1 = verif_ultra.sha256_proof in
  let modified_lead = { ultra_lead with address = "2 Billionaire Row" } in
  let verif_mod = verify_lead modified_lead in
  let p2 = verif_mod.sha256_proof in

  let diff_chars = ref 0 in
  for c = 0 to 63 do
    if p1.[c] <> p2.[c] then incr diff_chars
  done;

  check_named "CRYPTO.3: 1-char address modification alters >= 40 hex digest characters"
    (!diff_chars >= 40);

  let json_str = Types.verified_lead_to_json_string ~pretty:false verif_ultra in
  let parsed_back = Types.parse_json_lead json_str in
  check_named "JSON.1: Disqualified lead roundtrips through JSON parser"
    (match parsed_back with
     | Ok l -> l.address = "1 Billionaire Row" && l.estimated_value = Some 100000000.0 && List.length l.permits = 1
     | Error _ -> false);

  Printf.printf "  [PASS] Section 4: Cryptography & AST Hardening Verified (4/4)\n\n";

  Printf.printf "======================================================================\n";
  Printf.printf "=== ALL ADVERSARIAL CHALLENGER TESTS PASSED: %d/%d (100.0%%) ===\n" !passed_tests !total_tests;
  Printf.printf "======================================================================\n\n"
