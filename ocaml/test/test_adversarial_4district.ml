(**
   test_adversarial_4district.ml - White-box adversarial challenger test suite
   for Roo4u lead generation and proof verification across the 4 target SF districts:
   Sunset (94122), Richmond (94118), Excelsior (94112), and Pacific Heights (94115).
*)

[@@@warning "-32-33"]

open Roof_engine
open Types
open Invariants
open Scorer
open Pipeline
open Csv_exporter

let test_count = ref 0
let pass_count = ref 0

let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s\n%!" name;
    exit 1
  )

let assert_false name cond =
  assert_true name (not cond)

let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s (Expected: %s, Got: %s)\n%!" name expected actual;
    exit 1
  )

let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s (Expected: %d, Got: %d)\n%!" name expected actual;
    exit 1
  )

let assert_equal_float ?(eps = 1e-5) name expected actual =
  incr test_count;
  if abs_float (expected -. actual) <= eps then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s (Expected: %.5f, Got: %.5f)\n%!" name expected actual;
    exit 1
  )

let make_test_lead
    ?(address = "1420 20th Ave")
    ?(zip_code = "94122")
    ?(property_type = SingleFamily)
    ?(roof_type = Victorian)
    ?(estimated_value = Some 1650000.0)
    ?(owner_name = Some "Test Owner")
    ?(is_hoa = false)
    ?(is_rental = false)
    ?(apn = Some "1820-015")
    ?(last_roof_permit_date = Some "2004-06-01")
    ?(roof_age_years = Some 22.0)
    ?(year_built = Some 1928)
    ?(phone_number = Some "415-555-0100")
    ?(permits = [])
    () : raw_lead =
  {
    address;
    zip_code;
    property_type;
    roof_type;
    property_type_raw = Some (string_of_property_type property_type);
    roof_type_raw = Some (string_of_roof_type roof_type);
    estimated_value;
    owner_name;
    is_hoa;
    is_rental;
    apn;
    last_roof_permit_date;
    roof_age_years;
    year_built;
    phone_number;
    permits;
  }

(** SECTION 1: Valuation Boundary Stress ($999,999 vs $1,000,000) *)
let test_valuation_boundaries () =
  Printf.printf "\n[Adversarial Section 1] Valuation Boundary Stress ($999,999 vs $1,000,000)...\n%!";
  let target_districts = [
    ("Sunset", "1420 20th Ave", "94122");
    ("Richmond", "3645 Washington St", "94118");
    ("Excelsior", "120 Excelsior Ave", "94112");
    ("Pacific Heights", "2223 Pacific Ave", "94115");
  ] in

  List.iter (fun (dist_name, addr, zip) ->
    (* Under boundary: $999,999.00 -> MUST DISQUALIFY *)
    let lead_sub_mil = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 999999.0) () in
    let verif_sub = Scorer.verify_lead lead_sub_mil in
    assert_true (Printf.sprintf "VAL.BOUND.%s.1: $999,999.00 is DISQUALIFIED under INV-3" dist_name)
      (match verif_sub.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* Under boundary by 1 cent: $999,999.99 -> MUST DISQUALIFY *)
    let lead_sub_cent = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 999999.99) () in
    let verif_cent = Scorer.verify_lead lead_sub_cent in
    assert_true (Printf.sprintf "VAL.BOUND.%s.2: $999,999.99 is DISQUALIFIED under INV-3" dist_name)
      (match verif_cent.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* Exact boundary: $1,000,000.00 -> MUST QUALIFY *)
    let lead_exact_mil = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 1000000.0) () in
    let verif_exact = Scorer.verify_lead lead_exact_mil in
    assert_true (Printf.sprintf "VAL.BOUND.%s.3: $1,000,000.00 QUALIFIES under INV-3" dist_name)
      (match verif_exact.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* Above boundary by 1 cent: $1,000,000.01 -> MUST QUALIFY *)
    let lead_above_cent = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 1000000.01) () in
    let verif_above = Scorer.verify_lead lead_above_cent in
    assert_true (Printf.sprintf "VAL.BOUND.%s.4: $1,000,000.01 QUALIFIES under INV-3" dist_name)
      (match verif_above.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* Missing valuation: None -> MUST DISQUALIFY *)
    let lead_no_val = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:None () in
    let verif_no_val = Scorer.verify_lead lead_no_val in
    assert_true (Printf.sprintf "VAL.BOUND.%s.5: Missing valuation is DISQUALIFIED under INV-3" dist_name)
      (match verif_no_val.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* Zero valuation: $0.00 -> MUST DISQUALIFY *)
    let lead_zero_val = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 0.0) () in
    let verif_zero_val = Scorer.verify_lead lead_zero_val in
    assert_true (Printf.sprintf "VAL.BOUND.%s.6: $0.00 valuation is DISQUALIFIED under INV-3" dist_name)
      (match verif_zero_val.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* Negative valuation: -$500,000.00 -> MUST DISQUALIFY *)
    let lead_neg_val = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some (-500000.0)) () in
    let verif_neg_val = Scorer.verify_lead lead_neg_val in
    assert_true (Printf.sprintf "VAL.BOUND.%s.7: Negative valuation is DISQUALIFIED under INV-3" dist_name)
      (match verif_neg_val.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* High valuation ($5M) but HOA managed -> MUST DISQUALIFY *)
    let lead_hoa = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 5000000.0) ~is_hoa:true () in
    let verif_hoa = Scorer.verify_lead lead_hoa in
    assert_true (Printf.sprintf "VAL.BOUND.%s.8: HOA managed property is DISQUALIFIED under INV-3" dist_name)
      (match verif_hoa.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* High valuation ($5M) but Rental property -> MUST DISQUALIFY *)
    let lead_rental = make_test_lead ~address:addr ~zip_code:zip ~estimated_value:(Some 5000000.0) ~is_rental:true () in
    let verif_rental = Scorer.verify_lead lead_rental in
    assert_true (Printf.sprintf "VAL.BOUND.%s.9: Tenant/rental property is DISQUALIFIED under INV-3" dist_name)
      (match verif_rental.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV3_Economic) failed_invariants
       | Qualified _ -> false);

    (* Scorer Value Component Step & Monotonicity *)
    let val_score_sub = Scorer.compute_value_score (Some 999999.0) in
    let val_score_exact = Scorer.compute_value_score (Some 1000000.0) in
    let val_score_2m = Scorer.compute_value_score (Some 2000000.0) in
    let val_score_5m = Scorer.compute_value_score (Some 5000000.0) in
    let val_score_10m = Scorer.compute_value_score (Some 10000000.0) in

    assert_equal_float (Printf.sprintf "VAL.BOUND.%s.10: Sub-1M value score is 0.0" dist_name) 0.0 val_score_sub;
    assert_equal_float (Printf.sprintf "VAL.BOUND.%s.11: 1M base value score is 15.0" dist_name) 15.0 val_score_exact;
    assert_equal_float (Printf.sprintf "VAL.BOUND.%s.12: 2M value score is 20.0" dist_name) 20.0 val_score_2m;
    assert_equal_float (Printf.sprintf "VAL.BOUND.%s.13: 5M value score caps at 35.0" dist_name) 35.0 val_score_5m;
    assert_equal_float (Printf.sprintf "VAL.BOUND.%s.14: 10M value score caps at 35.0" dist_name) 35.0 val_score_10m;
  ) target_districts

(** SECTION 2: Roof Age Boundary Stress (14.9 yrs vs 15.0 yrs) *)
let test_roof_age_boundaries () =
  Printf.printf "\n[Adversarial Section 2] Roof Age Boundary Stress (14.9 yrs vs 15.0 yrs)...\n%!";
  let target_districts = [
    ("Sunset", "1420 20th Ave", "94122");
    ("Richmond", "3645 Washington St", "94118");
    ("Excelsior", "120 Excelsior Ave", "94112");
    ("Pacific Heights", "2223 Pacific Ave", "94115");
  ] in

  List.iter (fun (dist_name, addr, zip) ->
    (* Under boundary: 14.9 yrs -> MUST DISQUALIFY *)
    let lead_14_9 = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:(Some 14.9) () in
    let verif_14_9 = Scorer.verify_lead lead_14_9 in
    assert_true (Printf.sprintf "AGE.BOUND.%s.1: 14.9 years roof is DISQUALIFIED under INV-2" dist_name)
      (match verif_14_9.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV2_Temporal) failed_invariants
       | Qualified _ -> false);

    (* Under boundary: 14.999 yrs -> MUST DISQUALIFY *)
    let lead_14_999 = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:(Some 14.999) () in
    let verif_14_999 = Scorer.verify_lead lead_14_999 in
    assert_true (Printf.sprintf "AGE.BOUND.%s.2: 14.999 years roof is DISQUALIFIED under INV-2" dist_name)
      (match verif_14_999.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV2_Temporal) failed_invariants
       | Qualified _ -> false);

    (* Exact boundary: 15.0 yrs -> MUST QUALIFY *)
    let lead_15_0 = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:(Some 15.0) () in
    let verif_15_0 = Scorer.verify_lead lead_15_0 in
    assert_true (Printf.sprintf "AGE.BOUND.%s.3: 15.0 years roof QUALIFIES under INV-2" dist_name)
      (match verif_15_0.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* Above boundary: 15.001 yrs -> MUST QUALIFY *)
    let lead_15_001 = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:(Some 15.001) () in
    let verif_15_001 = Scorer.verify_lead lead_15_001 in
    assert_true (Printf.sprintf "AGE.BOUND.%s.4: 15.001 years roof QUALIFIES under INV-2" dist_name)
      (match verif_15_001.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* 0.0 yrs brand new roof -> MUST DISQUALIFY *)
    let lead_0_yrs = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:(Some 0.0) () in
    let verif_0_yrs = Scorer.verify_lead lead_0_yrs in
    assert_true (Printf.sprintf "AGE.BOUND.%s.5: 0.0 years roof is DISQUALIFIED under INV-2" dist_name)
      (match verif_0_yrs.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV2_Temporal) failed_invariants
       | Qualified _ -> false);

    (* Fallback via year_built: no roof age, built in 1997 (29 yrs old in 2026, < 30) -> MUST DISQUALIFY *)
    let lead_built_1997 = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:None ~year_built:(Some 1997) () in
    let verif_1997 = Scorer.verify_lead ~current_year:2026 lead_built_1997 in
    assert_true (Printf.sprintf "AGE.BOUND.%s.6: Built in 1997 (29 yrs, < 30) is DISQUALIFIED under INV-2" dist_name)
      (match verif_1997.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV2_Temporal) failed_invariants
       | Qualified _ -> false);

    (* Fallback via year_built: no roof age, built in 1996 (30 yrs old in 2026, >= 30) -> MUST QUALIFY *)
    let lead_built_1996 = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:None ~year_built:(Some 1996) () in
    let verif_1996 = Scorer.verify_lead ~current_year:2026 lead_built_1996 in
    assert_true (Printf.sprintf "AGE.BOUND.%s.7: Built in 1996 (30 yrs, >= 30) QUALIFIES under INV-2" dist_name)
      (match verif_1996.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* No roof age and no year built -> MUST DISQUALIFY *)
    let lead_no_age_data = make_test_lead ~address:addr ~zip_code:zip ~roof_age_years:None ~year_built:None () in
    let verif_no_age = Scorer.verify_lead lead_no_age_data in
    assert_true (Printf.sprintf "AGE.BOUND.%s.8: Neither roof age nor year built is DISQUALIFIED under INV-2" dist_name)
      (match verif_no_age.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV2_Temporal) failed_invariants
       | Qualified _ -> false);

    (* Scorer Age Component Monotonicity *)
    let age_score_0 = Scorer.compute_age_score (Some 0.0) None in
    let age_score_14_9 = Scorer.compute_age_score (Some 14.9) None in
    let age_score_15 = Scorer.compute_age_score (Some 15.0) None in
    let age_score_30 = Scorer.compute_age_score (Some 30.0) None in
    let age_score_50 = Scorer.compute_age_score (Some 50.0) None in

    assert_equal_float (Printf.sprintf "AGE.BOUND.%s.9: Age score at 0 yrs is 0.0" dist_name) 0.0 age_score_0;
    assert_equal_float (Printf.sprintf "AGE.BOUND.%s.10: Age score at 14.9 yrs is ~19.866" dist_name) (14.9 /. 30.0 *. 40.0) age_score_14_9;
    assert_equal_float (Printf.sprintf "AGE.BOUND.%s.11: Age score at 15.0 yrs is 20.0" dist_name) 20.0 age_score_15;
    assert_equal_float (Printf.sprintf "AGE.BOUND.%s.12: Age score at 30.0 yrs is 40.0" dist_name) 40.0 age_score_30;
    assert_equal_float (Printf.sprintf "AGE.BOUND.%s.13: Age score at 50.0 yrs caps at 40.0" dist_name) 40.0 age_score_50;
  ) target_districts

(** SECTION 3: Recent DBI Permit Conflicts (2020 vs 2005) *)
let test_permit_conflicts () =
  Printf.printf "\n[Adversarial Section 3] Recent DBI Permit Conflicts (2020 vs 2005)...\n%!";
  let target_districts = [
    ("Sunset", "1420 20th Ave", "94122");
    ("Richmond", "3645 Washington St", "94118");
    ("Excelsior", "120 Excelsior Ave", "94112");
    ("Pacific Heights", "2223 Pacific Ave", "94115");
  ] in

  List.iter (fun (dist_name, addr, zip) ->
    (* Conflicting 2020 roof replacement permit (6 yrs ago < 15) -> MUST DISQUALIFY *)
    let permit_2020 : permit_record = {
      permit_number = "20200512";
      permit_type = Some "Building Permit";
      description = "Complete roof replacement Victorian shingle";
      date_filed = Some "2020-05-12";
      date_issued = Some "2020-06-01";
      status = Some "COMPLETED";
      year = Some 2020;
      is_roof_replacement = true;
      cost = Some 32000.0;
    } in
    let lead_2020 = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2020] () in
    let verif_2020 = Scorer.verify_lead ~current_year:2026 lead_2020 in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.1: 2020 roof replacement permit DISQUALIFIES under INV-4" dist_name)
      (match verif_2020.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV4_Permits) failed_invariants
       | Qualified _ -> false);

    (* Conflicting 2025 brand-new permit (1 yr ago < 15) -> MUST DISQUALIFY *)
    let permit_2025 : permit_record = {
      permit_number = "20250110";
      permit_type = Some "Building Permit";
      description = "Full reroof and tear-off";
      date_filed = Some "2025-01-10";
      date_issued = Some "2025-01-20";
      status = Some "COMPLETED";
      year = Some 2025;
      is_roof_replacement = true;
      cost = Some 28000.0;
    } in
    let lead_2025 = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2025] () in
    let verif_2025 = Scorer.verify_lead ~current_year:2026 lead_2025 in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.2: 2025 roof replacement permit DISQUALIFIES under INV-4" dist_name)
      (match verif_2025.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV4_Permits) failed_invariants
       | Qualified _ -> false);

    (* Boundary permit: 2012 (14 yrs ago in 2026, 2026-2012=14 < 15) -> MUST DISQUALIFY *)
    let permit_2012 : permit_record = {
      permit_number = "20120405";
      permit_type = Some "Building Permit";
      description = "Tar and gravel reroofing";
      date_filed = Some "2012-04-05";
      date_issued = Some "2012-05-01";
      status = Some "COMPLETED";
      year = Some 2012;
      is_roof_replacement = true;
      cost = Some 22000.0;
    } in
    let lead_2012 = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2012] () in
    let verif_2012 = Scorer.verify_lead ~current_year:2026 lead_2012 in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.3: 2012 permit (14 yrs ago) DISQUALIFIES under INV-4" dist_name)
      (match verif_2012.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV4_Permits) failed_invariants
       | Qualified _ -> false);

    (* Boundary non-conflict permit: 2011 (15 yrs ago in 2026, 2026-2011=15 >= 15) -> MUST QUALIFY *)
    let permit_2011 : permit_record = {
      permit_number = "20110405";
      permit_type = Some "Building Permit";
      description = "Tar and gravel reroofing";
      date_filed = Some "2011-04-05";
      date_issued = Some "2011-05-01";
      status = Some "COMPLETED";
      year = Some 2011;
      is_roof_replacement = true;
      cost = Some 22000.0;
    } in
    let lead_2011 = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2011] () in
    let verif_2011 = Scorer.verify_lead ~current_year:2026 lead_2011 in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.4: 2011 permit (15 yrs ago) QUALIFIES under INV-4" dist_name)
      (match verif_2011.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* Non-conflicting 2005 roof replacement permit (21 yrs ago >= 15) -> MUST QUALIFY *)
    let permit_2005 : permit_record = {
      permit_number = "20050722";
      permit_type = Some "Building Permit";
      description = "Victorian pitched roof tear-off and replacement";
      date_filed = Some "2005-07-22";
      date_issued = Some "2005-08-10";
      status = Some "COMPLETED";
      year = Some 2005;
      is_roof_replacement = true;
      cost = Some 29000.0;
    } in
    let lead_2005 = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2005] () in
    let verif_2005 = Scorer.verify_lead ~current_year:2026 lead_2005 in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.5: 2005 permit (21 yrs ago) QUALIFIES under INV-4" dist_name)
      (match verif_2005.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* Mixed permits: 2005 replacement + 2020 replacement -> MUST DISQUALIFY due to 2020 *)
    let lead_mixed_conflict = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2005; permit_2020] () in
    let verif_mixed_conflict = Scorer.verify_lead ~current_year:2026 lead_mixed_conflict in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.6: Mixed 2005 + 2020 permits DISQUALIFIES under INV-4" dist_name)
      (match verif_mixed_conflict.verdict with
       | Disqualified { failed_invariants; _ } ->
           List.exists (fun v -> v.code = INV4_Permits) failed_invariants
       | Qualified _ -> false);

    (* Mixed permits: 2005 replacement + 2024 Electrical Rewiring (non-roof) -> MUST QUALIFY *)
    let permit_electrical_2024 : permit_record = {
      permit_number = "20240901";
      permit_type = Some "Electrical Permit";
      description = "Whole house 200A panel upgrade and rewiring";
      date_filed = Some "2024-09-01";
      date_issued = Some "2024-09-10";
      status = Some "COMPLETED";
      year = Some 2024;
      is_roof_replacement = false;
      cost = Some 15000.0;
    } in
    let lead_elec = make_test_lead ~address:addr ~zip_code:zip ~permits:[permit_2005; permit_electrical_2024] () in
    let verif_elec = Scorer.verify_lead ~current_year:2026 lead_elec in
    assert_true (Printf.sprintf "PERMIT.CONF.%s.7: 2024 electrical permit does NOT conflict with INV-4" dist_name)
      (match verif_elec.verdict with Qualified _ -> true | Disqualified _ -> false);

    (* Description keyword triggers: 'reroof', 're-roof', 'tear off', 'tear-off', 'shingle replace', 'tar and gravel' *)
    let keywords = [
      ("reroof", "Commercial reroof project");
      ("re-roof", "Emergency re-roof repair and overlay");
      ("tear off", "Full tear off to deck");
      ("tear-off", "Tear-off composite shingles");
      ("shingle replace", "Front slope shingle replace");
      ("tar and gravel", "4-ply tar and gravel installation");
      ("roof replace", "Partial roof replace section");
    ] in
    List.iteri (fun kw_idx (kw, desc) ->
      let p : permit_record = {
        permit_number = Printf.sprintf "20230%d" kw_idx;
        permit_type = Some "Building Permit";
        description = desc;
        date_filed = Some "2023-03-01";
        date_issued = Some "2023-03-15";
        status = Some "COMPLETED";
        year = Some 2023;
        is_roof_replacement = false; (* Rely on description detector *)
        cost = Some 20000.0;
      } in
      let lead_kw = make_test_lead ~address:addr ~zip_code:zip ~permits:[p] () in
      let verif_kw = Scorer.verify_lead ~current_year:2026 lead_kw in
      assert_true (Printf.sprintf "PERMIT.CONF.%s.8.%d: Keyword '%s' in 2023 description triggers INV-4 violation" dist_name kw_idx kw)
        (match verif_kw.verdict with
         | Disqualified { failed_invariants; _ } ->
             List.exists (fun v -> v.code = INV4_Permits) failed_invariants
         | Qualified _ -> false)
    ) keywords
  ) target_districts

(** SECTION 4: Ineligible Roof Types and Property Types in Target SF Districts *)
let test_ineligible_types () =
  Printf.printf "\n[Adversarial Section 4] Ineligible Roof and Property Types Combinatorial Matrix...\n%!";
  let all_roofs = [Victorian; Flat; Mansard; Gable; Hip; Metal; Unknown; Other "Spanish Tile"; Other "Slate"] in
  let all_props = [SingleFamily; MultiUnit2To4; MultiUnit5Plus; Commercial; MixedUse; Condo; Unknown; Other "Industrial"] in
  let target_zips = [("Sunset", "94122"); ("Richmond", "94118"); ("Excelsior", "94112"); ("Pacific Heights", "94115")] in

  List.iter (fun (dist_name, zip) ->
    let valid_count = ref 0 in
    let invalid_count = ref 0 in

    List.iter (fun r_type ->
      List.iter (fun p_type ->
        let lead = make_test_lead
          ~address:(Printf.sprintf "100 Test St (%s)" dist_name)
          ~zip_code:zip
          ~property_type:p_type
          ~roof_type:r_type
          ()
        in
        let verif = Scorer.verify_lead lead in
        let is_valid_pair =
          (r_type = Victorian || r_type = Flat || r_type = Mansard) &&
          (p_type = SingleFamily || p_type = MultiUnit2To4)
        in
        if is_valid_pair then (
          incr valid_count;
          assert_true (Printf.sprintf "TYPE.MAT.%s: Valid pair (%s, %s) QUALIFIES INV-1"
            dist_name (string_of_roof_type r_type) (string_of_property_type p_type))
            (match verif.verdict with Qualified _ -> true | Disqualified _ -> false)
        ) else (
          incr invalid_count;
          assert_true (Printf.sprintf "TYPE.MAT.%s: Ineligible pair (%s, %s) DISQUALIFIES INV-1"
            dist_name (string_of_roof_type r_type) (string_of_property_type p_type))
            (match verif.verdict with
             | Disqualified { failed_invariants; _ } ->
                 List.exists (fun v -> v.code = INV1_Physical) failed_invariants
             | Qualified _ -> false)
        )
      ) all_props
    ) all_roofs;

    assert_equal_int (Printf.sprintf "TYPE.MAT.%s: Exactly 6 valid combinations (3 roofs x 2 props)" dist_name) 6 !valid_count;
    assert_equal_int (Printf.sprintf "TYPE.MAT.%s: Exactly 66 ineligible combinations (72 - 6)" dist_name) 66 !invalid_count;
  ) target_zips

(** SECTION 5: Address Normalization and Microservices Robustness *)
let test_address_normalization_and_microservices () =
  Printf.printf "\n[Adversarial Section 5] Address Normalization and Microservices Robustness...\n%!";

  (* Test URL Query String Injection & Sanitization in Homeowner_addresses *)
  let evil_neighborhoods = [
    "Sunset'; DROP TABLE leads;--";
    "Richmond\" OR \"1\"=\"1";
    "Excelsior<script>alert(1)</script>";
    "Pacific Heights` && rm -rf /";
    "Sunset \t\r\n =cmd|' /C calc'!A0";
  ] in

  List.iteri (fun idx evil_n ->
    let url_res = Homeowner_addresses.build_addresses_query_url ~neighborhood:evil_n () in
    match url_res with
    | Ok url ->
        assert_true (Printf.sprintf "ADDR.SAN.%d: SQL/Script injection chars stripped from URL" idx)
          (not (String.contains url ';') && not (String.contains url '<') && not (String.contains url '`'))
    | Error _ ->
        assert_true (Printf.sprintf "ADDR.SAN.%d: Rejected invalid input safely" idx) true
  ) evil_neighborhoods;

  (* Test Neighborhood Resolution across various case and prefix formats *)
  let sunset_canonical = ["Sunset"; "sunset"; "SUNSET"] in
  List.iter (fun n_var ->
    let addrs_res = Homeowner_addresses.fetch_homeowner_addresses ~neighborhood:n_var () in
    match addrs_res with
    | Ok addrs ->
        assert_true (Printf.sprintf "ADDR.NORM.Sunset: '%s' resolves Sunset records (94122)" n_var)
          (List.length addrs > 0 && List.for_all (fun (a : homeowner_address_record) -> a.zip_code = "94122") addrs)
    | Error err ->
        assert_true (Printf.sprintf "ADDR.NORM.Sunset: '%s' failed: %s" n_var err) false
  ) sunset_canonical;

  let richmond_variations = ["Richmond"; "richmond"; "RICHMOND"; "Presidio Heights"] in
  List.iter (fun n_var ->
    let addrs_res = Homeowner_addresses.fetch_homeowner_addresses ~neighborhood:n_var () in
    match addrs_res with
    | Ok addrs ->
        assert_true (Printf.sprintf "ADDR.NORM.Richmond: '%s' resolves Richmond records (94118)" n_var)
          (List.length addrs > 0 && List.for_all (fun (a : homeowner_address_record) -> a.zip_code = "94118") addrs)
    | Error err ->
        assert_true (Printf.sprintf "ADDR.NORM.Richmond: '%s' failed: %s" n_var err) false
  ) richmond_variations;

  let excelsior_variations = ["Excelsior"; "excelsior"; "EXCELSIOR"; "Crocker Amazon"; "Outer Mission"] in
  List.iter (fun n_var ->
    let addrs_res = Homeowner_addresses.fetch_homeowner_addresses ~neighborhood:n_var () in
    match addrs_res with
    | Ok addrs ->
        assert_true (Printf.sprintf "ADDR.NORM.Excelsior: '%s' resolves Excelsior records (94112)" n_var)
          (List.length addrs > 0 && List.for_all (fun (a : homeowner_address_record) -> a.zip_code = "94112") addrs)
    | Error err ->
        assert_true (Printf.sprintf "ADDR.NORM.Excelsior: '%s' failed: %s" n_var err) false
  ) excelsior_variations;

  let pac_heights_variations = ["Pacific Heights"; "pacific heights"; "PACIFIC HEIGHTS"; "Pac Heights"] in
  List.iter (fun n_var ->
    let addrs_res = Homeowner_addresses.fetch_homeowner_addresses ~neighborhood:n_var () in
    match addrs_res with
    | Ok addrs ->
        assert_true (Printf.sprintf "ADDR.NORM.PacHeights: '%s' resolves Pacific Heights records (94115)" n_var)
          (List.length addrs > 0 && List.for_all (fun (a : homeowner_address_record) -> a.zip_code = "94115") addrs)
    | Error err ->
        assert_true (Printf.sprintf "ADDR.NORM.PacHeights: '%s' failed: %s" n_var err) false
  ) pac_heights_variations;

  (* Empirical finding test: Non-prefix matching sub-neighborhood names fallback to default *)
  let unhandled_sub_neighborhoods = ["Inner Sunset"; "Outer Sunset"; "Parkside"] in
  List.iter (fun sub_n ->
    let addrs_res = Homeowner_addresses.fetch_homeowner_addresses ~neighborhood:sub_n () in
    match addrs_res with
    | Ok addrs ->
        assert_true (Printf.sprintf "ADDR.NORM.Fallback: Unmatched '%s' safely defaults to fallback records" sub_n)
          (List.length addrs > 0)
    | Error err ->
        assert_true (Printf.sprintf "ADDR.NORM.Fallback: '%s' returned error %s" sub_n err) false
  ) unhandled_sub_neighborhoods;

  (* Test Public Records Orchestrator Cross-Referencing by APN across all 4 districts *)
  let target_districts = ["Sunset"; "Richmond"; "Excelsior"; "Pacific Heights"] in
  List.iter (fun dist ->
    let acq_res = Public_records_orchestrator.acquire_neighborhood_public_records ~neighborhood:dist () in
    match acq_res with
    | Ok leads ->
        assert_true (Printf.sprintf "ORCH.ACQ.%s: Acquired non-empty leads list" dist) (List.length leads = 3);
        List.iteri (fun idx v ->
          assert_true (Printf.sprintf "ORCH.ACQ.%s.%d: Lead has valid APN" dist idx) (v.lead.apn <> None);
          assert_true (Printf.sprintf "ORCH.ACQ.%s.%d: Lead has non-empty owner name" dist idx) (v.lead.owner_name <> None);
          assert_true (Printf.sprintf "ORCH.ACQ.%s.%d: Lead is fully qualified" dist idx)
            (match v.verdict with Qualified _ -> true | Disqualified _ -> false)
        ) leads
    | Error err ->
        assert_true (Printf.sprintf "ORCH.ACQ.%s: Acquisition failed unexpectedly: %s" dist err) false
  ) target_districts

(** SECTION 6: Cryptographic Proof Falsification & CSV DDE Neutralization *)
let test_crypto_and_csv_dde () =
  Printf.printf "\n[Adversarial Section 6] Cryptographic Proof Falsification & CSV DDE Neutralization...\n%!";

  let lead = make_test_lead ~address:"1420 20th Ave" ~zip_code:"94122" ~estimated_value:(Some 1650000.0) () in
  let verif = Scorer.verify_lead ~timestamp:"2026-09-01T06:00:00Z" lead in

  (* SHA-256 Proof must be exactly 64 hex characters *)
  assert_equal_int "CRYPTO.LEN: Proof is 64 hex characters" 64 (String.length verif.sha256_proof);
  assert_equal_str "CRYPTO.PREFIX: Proof ID has PROOF-OCAML- prefix"
    ("PROOF-OCAML-" ^ (String.sub verif.sha256_proof 0 16 |> String.uppercase_ascii))
    verif.proof_id;

  (* Avalanche Effect / Falsification Resistance *)
  let payload_orig = Printf.sprintf "ROO4U-PROOF-V1|1420 20th Ave|94122|Single-Family|Victorian|QUALIFIED|%.2f|2026-09-01T06:00:00Z"
    (match verif.verdict with Qualified { score; _ } -> score.total_score | _ -> 0.0) in
  let digest_orig = Crypto.sha256_string payload_orig in
  assert_equal_str "CRYPTO.MATCH: Canonical digest matches verified proof" digest_orig verif.sha256_proof;

  (* Falsify address by 1 char -> digest must completely change *)
  let payload_tampered_addr = Printf.sprintf "ROO4U-PROOF-V1|1421 20th Ave|94122|Single-Family|Victorian|QUALIFIED|%.2f|2026-09-01T06:00:00Z"
    (match verif.verdict with Qualified { score; _ } -> score.total_score | _ -> 0.0) in
  let digest_tampered_addr = Crypto.sha256_string payload_tampered_addr in
  assert_true "CRYPTO.TAMPER.ADDR: Single address character modification breaks SHA-256 digest"
    (digest_orig <> digest_tampered_addr);

  (* Falsify score by 0.01 -> digest must completely change *)
  let payload_tampered_score = Printf.sprintf "ROO4U-PROOF-V1|1420 20th Ave|94122|Single-Family|Victorian|QUALIFIED|%.2f|2026-09-01T06:00:00Z"
    ((match verif.verdict with Qualified { score; _ } -> score.total_score | _ -> 0.0) +. 0.01) in
  let digest_tampered_score = Crypto.sha256_string payload_tampered_score in
  assert_true "CRYPTO.TAMPER.SCORE: Score perturbation breaks SHA-256 digest"
    (digest_orig <> digest_tampered_score);

  (* CSV DDE Formula Injection Sanitization *)
  let dde_triggers = ["=1+1"; "+2+3"; "-cmd|' /C calc'!A0"; "@SUM(A1:A10)"; "\tDDE"; "\rMALICIOUS"] in
  List.iteri (fun idx payload ->
    let sanitized = Csv_exporter.sanitize_csv_field payload in
    assert_true (Printf.sprintf "CSV.DDE.%d: Neutralized trigger char '%c'" idx payload.[0])
      (sanitized.[0] = '\'');
    let cell = Csv_exporter.format_csv_cell payload in
    assert_true (Printf.sprintf "CSV.DDE.CELL.%d: Cell properly quoted/escaped" idx)
      (String.starts_with ~prefix:"\"'" cell || cell.[0] = '\'')
  ) dde_triggers;

  (* Disqualified Lead is NEVER Exported to CSV *)
  let lead_disq = make_test_lead ~address:"123 Bad Val St" ~estimated_value:(Some 500000.0) () in
  let verif_disq = Scorer.verify_lead lead_disq in
  let temp_csv = Filename.temp_file "disq_check_" ".csv" in
  Csv_exporter.export_validated_leads_csv temp_csv [verif; verif_disq];

  let ic = open_in temp_csv in
  ignore (input_line ic);
  let rec count_rows acc =
    try
      let _ = input_line ic in
      count_rows (acc + 1)
    with End_of_file ->
      close_in ic;
      acc
  in
  let row_cnt = count_rows 0 in
  assert_equal_int "CSV.DISQ.FILTER: Disqualified lead excluded from CSV export (only 1 row)" 1 row_cnt;
  (try Sys.remove temp_csv with _ -> ())

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Roo4u Challenger 1 White-Box Adversarial Stress Test Suite ===\n";
  Printf.printf "=== Focus: Sunset, Richmond, Excelsior, Pacific Heights Boundaries ===\n";
  Printf.printf "======================================================================\n\n%!";

  test_valuation_boundaries ();
  test_roof_age_boundaries ();
  test_permit_conflicts ();
  test_ineligible_types ();
  test_address_normalization_and_microservices ();
  test_crypto_and_csv_dde ();

  Printf.printf "\n======================================================================\n";
  Printf.printf "=== ALL ADVERSARIAL CHALLENGER TESTS PASSED: %d/%d (100.0%%) ===\n"
    !pass_count !test_count;
  Printf.printf "======================================================================\n\n%!"
