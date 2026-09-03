(**
   test_m2_2_challenger.ml - Empirical Stress Testing Suite for Milestone 2.
   Stress-tests:
     1. Multi-permit parcels with mixed permit types (INV-4 non-conflict).
     2. Date precedence (issued_date > completed_date > filed_date).
     3. Roofing replacement keyword coverage (bitumen, tpo, epdm, torch down, built-up, tar and gravel, shingle).
     4. Non-roof alteration exclusions (kitchen remodel, plumbing, seismic retrofit, electrical, HVAC, etc.).
     5. Structural fallback age calculations across varied year_built inputs and boundary conditions.
     6. Fuzzing and adversarial permutations.
*)

[@@@warning "-32-33-27"]

open Roof_engine
open Types
open Invariants
open Roof_permits
open Scorer

let test_count = ref 0
let pass_count = ref 0
let fail_count = ref 0

(** [assert_true name cond] registers a test and verifies that [cond] is true. *)
let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.eprintf "  [FAIL] %s\n%!" name
  )

(** [assert_equal_str name expected actual] registers a test and verifies string equality. *)
let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.eprintf "  [FAIL] %s (Expected: '%s', Got: '%s')\n%!" name expected actual
  )

(** [assert_equal_int name expected actual] registers a test and verifies integer equality. *)
let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.eprintf "  [FAIL] %s (Expected: %d, Got: %d)\n%!" name expected actual
  )

(** [assert_equal_float name expected actual] registers a test and verifies float equality within 0.001. *)
let assert_equal_float name expected actual =
  incr test_count;
  if abs_float (expected -. actual) < 0.001 then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.eprintf "  [FAIL] %s (Expected: %.2f, Got: %.2f)\n%!" name expected actual
  )

(** [assert_inv4_satisfied name status] checks if invariant status is Satisfied. *)
let assert_inv4_satisfied name status =
  match status with
  | Satisfied _ -> assert_true name true
  | Violated v ->
      Printf.eprintf "    Violation details: %s - %s\n%!" v.name v.message;
      assert_true name false

(** [assert_inv4_violated name status] checks if invariant status is Violated with code INV4_Permits. *)
let assert_inv4_violated name status =
  match status with
  | Violated v ->
      assert_true (name ^ " (violated)") true;
      assert_true (name ^ " (code is INV4_Permits)") (v.code = INV4_Permits)
  | Satisfied msg ->
      Printf.eprintf "    Unexpectedly satisfied: %s\n%!" msg;
      assert_true name false

(** [assert_inv2_satisfied name status] checks if invariant status is Satisfied. *)
let assert_inv2_satisfied name status =
  match status with
  | Satisfied _ -> assert_true name true
  | Violated v ->
      Printf.eprintf "    Violation details: %s - %s\n%!" v.name v.message;
      assert_true name false

(** [assert_inv2_violated name status] checks if invariant status is Violated with code INV2_Temporal. *)
let assert_inv2_violated name status =
  match status with
  | Violated v ->
      assert_true (name ^ " (violated)") true;
      assert_true (name ^ " (code is INV2_Temporal)") (v.code = INV2_Temporal)
  | Satisfied msg ->
      Printf.eprintf "    Unexpectedly satisfied: %s\n%!" msg;
      assert_true name false

(** [test_suite_1_multi_permit_parcels ()] executes stress tests on parcels with mixed permit types. *)
let test_suite_1_multi_permit_parcels () =
  Printf.printf "\n[Suite 1] Multi-Permit Parcels & Mixed Permit Types vs INV-4...\n%!";

  let p_roof_1990 : permit_record = {
    permit_number = "PERMIT-1990-ROOF";
    permit_type = Some "Roofing Replacement";
    description = "Complete tear-off and reroof Victorian shingle";
    date_filed = Some "1990-05-01";
    date_issued = Some "1990-06-01";
    status = Some "COMPLETED";
    year = Some 1990;
    is_roof_replacement = true;
    cost = Some 25000.0;
  } in

  let p_elec_2024 : permit_record = {
    permit_number = "PERMIT-2024-EV";
    permit_type = Some "Electrical";
    description = "Install 200A electrical service panel and Level 2 EV charger";
    date_filed = Some "2024-03-10";
    date_issued = Some "2024-04-15";
    status = Some "ISSUED";
    year = Some 2024;
    is_roof_replacement = false;
    cost = Some 9500.0;
  } in

  assert_inv4_satisfied "1.1: 1990 reroof + 2024 EV charger satisfies INV-4"
    (check_inv4_permits [p_roof_1990; p_elec_2024]);

  assert_inv4_satisfied "1.2: Order independence (EV charger first, then 1990 reroof)"
    (check_inv4_permits [p_elec_2024; p_roof_1990]);

  let p_plumb_2023 : permit_record = {
    permit_number = "PERMIT-2023-PLUMB";
    permit_type = Some "Plumbing";
    description = "Whole house copper repipe and tankless water heater";
    date_filed = Some "2023-01-15";
    date_issued = Some "2023-02-01";
    status = Some "COMPLETED";
    year = Some 2023;
    is_roof_replacement = false;
    cost = Some 18000.0;
  } in

  let p_seismic_2024 : permit_record = {
    permit_number = "PERMIT-2024-SEISMIC";
    permit_type = Some "Structural";
    description = "Earthquake retrofit foundation bolting and cripple wall shear ply";
    date_filed = Some "2024-06-01";
    date_issued = Some "2024-07-10";
    status = Some "ISSUED";
    year = Some 2024;
    is_roof_replacement = false;
    cost = Some 22000.0;
  } in

  let p_kitchen_2025 : permit_record = {
    permit_number = "PERMIT-2025-KITCHEN";
    permit_type = Some "Alteration";
    description = "Kitchen remodel cabinet replacement and interior non-structural alteration";
    date_filed = Some "2025-02-10";
    date_issued = Some "2025-03-05";
    status = Some "ISSUED";
    year = Some 2025;
    is_roof_replacement = false;
    cost = Some 45000.0;
  } in

  assert_inv4_satisfied "1.3: 1990 reroof + 4 modern non-roof permits satisfies INV-4"
    (check_inv4_permits [p_roof_1990; p_elec_2024; p_plumb_2023; p_seismic_2024; p_kitchen_2025]);

  let p_elec_as_roofing_type : permit_record = {
    permit_number = "PERMIT-2024-ELEC-TAGGED";
    permit_type = Some "Roofing Replacement";
    description = "Install 200A electrical service panel and EV charger";
    date_filed = Some "2024-03-10";
    date_issued = Some "2024-04-15";
    status = Some "ISSUED";
    year = Some 2024;
    is_roof_replacement = false;
    cost = Some 9500.0;
  } in

  assert_true "1.4: Non-roof description with Roofing Replacement permit_type is not classified as replacement"
    (not (is_roof_replacement_permit p_elec_as_roofing_type));

  assert_inv4_satisfied "1.5: Non-roof description with Roofing Replacement permit_type does not trigger INV-4"
    (check_inv4_permits [p_roof_1990; p_elec_as_roofing_type]);

  let lead_multi_permit : raw_lead = {
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
    last_roof_permit_date = Some "1990-06-01";
    roof_age_years = Some 36.0;
    year_built = Some 1895;
    phone_number = Some "415-555-0199";
    permits = [p_roof_1990; p_elec_2024; p_plumb_2023; p_seismic_2024; p_kitchen_2025];
  } in

  let verified = Scorer.verify_lead lead_multi_permit in
  (match verified.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "1.6: Lead with 1990 reroof and 4 modern non-roof permits is Qualified" true;
       assert_equal_int "1.7: Lead passes exactly 4 formal invariants" 4 (List.length invariants_passed);
       assert_true "1.8: Lead score >= 90.0" (score.total_score >= 90.0)
   | Disqualified _ ->
       assert_true "1.6: Lead unexpectedly disqualified" false);

  let p_roof_recent_2023 : permit_record = {
    permit_number = "PERMIT-2023-ROOF";
    permit_type = Some "Roofing Replacement";
    description = "Complete roof replacement Victorian shingle";
    date_filed = Some "2023-04-01";
    date_issued = Some "2023-05-15";
    status = Some "COMPLETED";
    year = Some 2023;
    is_roof_replacement = true;
    cost = Some 42000.0;
  } in

  assert_inv4_violated "1.9: Negative control: mixed parcel with old 1990 reroof AND 2023 reroof fails INV-4"
    (check_inv4_permits [p_roof_1990; p_roof_recent_2023; p_elec_2024]);

  let lead_conflicting : raw_lead = {
    lead_multi_permit with
    permits = [p_roof_1990; p_roof_recent_2023; p_elec_2024];
  } in
  let verified_conflict = Scorer.verify_lead lead_conflicting in
  (match verified_conflict.verdict with
   | Disqualified { failed_invariants; _ } ->
       assert_true "1.10: Lead with recent 2023 roof permit is Disqualified" true;
       assert_true "1.11: Failure list contains INV4_Permits"
         (List.exists (fun (v : invariant_violation) -> v.code = INV4_Permits) failed_invariants)
   | Qualified _ ->
       assert_true "1.10: Lead unexpectedly qualified despite recent reroof" false)

(** [test_suite_2_date_precedence ()] executes stress tests on permit date precedence rules. *)
let test_suite_2_date_precedence () =
  Printf.printf "\n[Suite 2] Date Precedence: issued_date > completed_date > filed_date...\n%!";

  let json_all_three =
    Json.Object [
      ("permit_number", Json.String "P-DATE-1");
      ("description", Json.String "Complete tear-off and reroof");
      ("filed_date", Json.String "1995-03-01T00:00:00");
      ("issued_date", Json.String "2000-08-15T00:00:00");
      ("completed_date", Json.String "2001-11-20T00:00:00");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_all_three with
   | Ok r ->
       assert_equal_float "2.1: issued_date (2000) strictly governs when filed (1995) & completed (2001) exist (age 26.0)"
         26.0 (Option.value ~default:(-1.0) r.roof_age_years)
   | Error e ->
       assert_true ("2.1: Parse error: " ^ e) false);

  let json_issued_filed =
    Json.Object [
      ("permit_number", Json.String "P-DATE-2");
      ("description", Json.String "Roof replacement");
      ("filed_date", Json.String "2010-01-01T00:00:00");
      ("issued_date", Json.String "2015-06-01T00:00:00");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_issued_filed with
   | Ok r ->
       assert_equal_float "2.2: issued_date (2015) governs over older filed_date (2010) (age 11.0, not 16.0)"
         11.0 (Option.value ~default:(-1.0) r.roof_age_years)
   | Error e ->
       assert_true ("2.2: Parse error: " ^ e) false);

  let json_completed_filed =
    Json.Object [
      ("permit_number", Json.String "P-DATE-3");
      ("description", Json.String "Reroofing with shingle");
      ("filed_date", Json.String "2002-04-10T00:00:00");
      ("completed_date", Json.String "2005-09-15T00:00:00");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_completed_filed with
   | Ok r ->
       assert_equal_float "2.3: completed_date (2005) governs when issued_date is missing (age 21.0, not 24.0)"
         21.0 (Option.value ~default:(-1.0) r.roof_age_years)
   | Error e ->
       assert_true ("2.3: Parse error: " ^ e) false);

  let json_filed_only =
    Json.Object [
      ("permit_number", Json.String "P-DATE-4");
      ("description", Json.String "Replace roof built-up");
      ("filed_date", Json.String "2004-12-05T00:00:00");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_filed_only with
   | Ok r ->
       assert_equal_float "2.4: filed_date (2004) is used when issued and completed are missing (age 22.0)"
         22.0 (Option.value ~default:(-1.0) r.roof_age_years)
   | Error e ->
       assert_true ("2.4: Parse error: " ^ e) false);

  let json_no_dates =
    Json.Object [
      ("permit_number", Json.String "P-DATE-5");
      ("description", Json.String "Replace roof shingle");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_no_dates with
   | Ok r ->
       assert_true "2.5: Missing all dates yields roof_age_years = None"
         (r.roof_age_years = None)
   | Error e ->
       assert_true ("2.5: Parse error: " ^ e) false);

  let p_prec_check : permit_record = {
    permit_number = "P-GET-YEAR";
    permit_type = Some "Roofing";
    description = "Reroof";
    date_filed = Some "1998-02-01";
    date_issued = Some "2001-07-15";
    status = Some "COMPLETED";
    year = None;
    is_roof_replacement = true;
    cost = None;
  } in
  assert_equal_int "2.6: Invariants.get_permit_year prioritizes date_issued (2001) over date_filed (1998)"
    2001 (Option.value ~default:0 (get_permit_year p_prec_check));

  let p_prec_explicit_yr : permit_record = {
    p_prec_check with
    year = Some 2003;
  } in
  assert_equal_int "2.7: Invariants.get_permit_year honors explicit year (2003) over date_issued"
    2003 (Option.value ~default:0 (get_permit_year p_prec_explicit_yr));

  let json_current_yr =
    Json.Object [
      ("permit_number", Json.String "P-DATE-CURRENT");
      ("description", Json.String "Complete reroof");
      ("issued_date", Json.String "2026-05-20T00:00:00");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_current_yr with
   | Ok r ->
       assert_equal_float "2.8: Permit issued in current year (2026) clamps roof age to 0.0"
         0.0 (Option.value ~default:(-1.0) r.roof_age_years)
   | Error e ->
       assert_true ("2.8: Parse error: " ^ e) false);

  let json_future_yr =
    Json.Object [
      ("permit_number", Json.String "P-DATE-FUTURE");
      ("description", Json.String "Complete reroof");
      ("issued_date", Json.String "2028-01-10T00:00:00");
    ]
  in
  (match parse_roof_permit_record ~current_year:2026 json_future_yr with
   | Ok r ->
       assert_equal_float "2.9: Future permit date clamps to 0.0 without negative age"
         0.0 (Option.value ~default:(-1.0) r.roof_age_years)
   | Error e ->
       assert_true ("2.9: Parse error: " ^ e) false)

(** [test_suite_3_roofing_keywords ()] executes stress tests on all required roofing keywords. *)
let test_suite_3_roofing_keywords () =
  Printf.printf "\n[Suite 3] Roofing Replacement Keyword Coverage...\n%!";

  let check_kw kw desc =
    let json = Json.Object [
      ("permit_number", Json.String ("P-" ^ kw));
      ("description", Json.String desc);
      ("issued_date", Json.String "2005-06-01T00:00:00");
    ] in
    (match parse_roof_permit_record ~current_year:2026 json with
     | Ok r ->
         assert_true (Printf.sprintf "3.%s (record.is_roof_replacement): '%s'" kw desc) r.is_roof_replacement;
         assert_equal_float (Printf.sprintf "3.%s (record.roof_age_years): '%.1f'" kw 21.0)
           21.0 (Option.value ~default:(-1.0) r.roof_age_years)
     | Error e ->
         assert_true ("Parse error: " ^ e) false);
    let p : permit_record = {
      permit_number = "P-" ^ kw;
      permit_type = Some "Alteration";
      description = desc;
      date_filed = None;
      date_issued = Some "2005-06-01";
      status = Some "ISSUED";
      year = Some 2005;
      is_roof_replacement = false;
      cost = None;
    } in
    assert_true (Printf.sprintf "3.%s (invariants.is_roof_replacement_permit): '%s'" kw desc)
      (is_roof_replacement_permit p)
  in

  check_kw "bitumen.1" "Modified bitumen flat roofing installation";
  check_kw "bitumen.2" "BITUMEN CAP SHEET HOT MOP APPLICATION";
  check_kw "bitumen.3" "Self-adhered SBS bitumen membrane replacement";

  check_kw "tpo.1" "Single-ply TPO membrane roof installation";
  check_kw "tpo.2" "INSTALL 60-MIL WHITE TPO ROOFING SYSTEM";
  check_kw "tpo.3" "Commercial flat roof TPO membrane restoration";

  check_kw "epdm.1" "EPDM rubber membrane reroofing";
  check_kw "epdm.2" "SINGLE-PLY EPDM 60 MIL MEMBRANE";
  check_kw "epdm.3" "Fully adhered EPDM flat roof assembly";

  check_kw "torch_down.1" "Torch down multi-ply flat roof application";
  check_kw "torch_down.2" "2-PLY TORCH DOWN ROOFING INSTALLATION";
  check_kw "torch_down.3" "Modified bitumen torch down system";

  check_kw "built_up.1" "Built-up roofing system with gravel surfacing";
  check_kw "built_up.2" "4-ply built up asphalt and felt roof";
  check_kw "built_up.3" "BUILT-UP TAR AND ASPHALT INSTALLATION";

  check_kw "tar_and_gravel.1" "Tar and gravel flat roof restoration";
  check_kw "tar_and_gravel.2" "HOT TAR AND GRAVEL REPLACEMENT";
  check_kw "tar_and_gravel.3" "Flat roof tar and gravel surfacing";

  check_kw "shingle.1" "Victorian asphalt shingle replacement";
  check_kw "shingle.2" "ARCHITECTURAL FIBERGLASS SHINGLE INSTALLATION";
  check_kw "shingle.3" "Wood shingle tear off and composite shingle application";

  check_kw "reroof.1" "Complete residential reroof";
  check_kw "reroof.2" "Residential re-roofing per standard plans";
  check_kw "replace_roof.1" "Replace roof with composite materials";
  check_kw "roof_replace.1" "Complete roof replacement with architectural shingles";
  check_kw "tear_off.1" "Tear off existing layers to deck and install new membrane";
  check_kw "tear_off.2" "Full tear-off and new waterproofing membrane"

(** [test_suite_4_non_roof_alterations ()] executes stress tests rejecting non-roof alterations. *)
let test_suite_4_non_roof_alterations () =
  Printf.printf "\n[Suite 4] Non-Roof Alteration Exclusions...\n%!";

  let check_non_roof tag desc =
    let json = Json.Object [
      ("permit_number", Json.String ("P-NON-" ^ tag));
      ("description", Json.String desc);
      ("issued_date", Json.String "2024-06-01T00:00:00");
    ] in
    (match parse_roof_permit_record ~current_year:2026 json with
     | Ok r ->
         assert_true (Printf.sprintf "4.%s (is_roof_replacement = false)" tag) (not r.is_roof_replacement);
         assert_true (Printf.sprintf "4.%s (roof_age_years = None)" tag) (r.roof_age_years = None)
     | Error e ->
         assert_true ("Parse error: " ^ e) false);
    let p : permit_record = {
      permit_number = "P-NON-" ^ tag;
      permit_type = Some "Alteration";
      description = desc;
      date_filed = None;
      date_issued = Some "2024-06-01";
      status = Some "ISSUED";
      year = Some 2024;
      is_roof_replacement = false;
      cost = None;
    } in
    assert_true (Printf.sprintf "4.%s (is_roof_replacement_permit is false)" tag)
      (not (is_roof_replacement_permit p));
    assert_inv4_satisfied (Printf.sprintf "4.%s (recent non-roof permit does not trigger INV-4)" tag)
      (check_inv4_permits [p])
  in

  check_non_roof "kitchen.1" "Kitchen remodel and cabinet replacement";
  check_non_roof "kitchen.2" "Complete kitchen renovation with island and electrical";
  check_non_roof "plumbing.1" "Plumbing repipe whole house copper piping";
  check_non_roof "plumbing.2" "Replace sewer lateral and main plumbing stack";
  check_non_roof "seismic.1" "Seismic retrofit foundation bolting and hold downs";
  check_non_roof "seismic.2" "Soft story seismic upgrade per mandatory retrofit ordinance";
  check_non_roof "bath.1" "Bathroom remodel new tile floor vanity and shower enclosure";
  check_non_roof "electrical.1" "200A service panel upgrade and circuit breaker replacement";
  check_non_roof "ev.1" "Install Tesla Level 2 EV charging station in private garage";
  check_non_roof "hvac.1" "Install heat pump and split system air conditioning";
  check_non_roof "windows.1" "Retrofit 12 vinyl double-pane replacement windows";
  check_non_roof "deck.1" "Repair rear wood deck joists and guardrail";
  check_non_roof "foundation.1" "Concrete foundation underpinning and crack repair";
  check_non_roof "painting.1" "Exterior stucco patch and elastomeric paint coating";
  check_non_roof "sprinkler.1" "Install fire sprinkler system NFPA 13R throughout building";
  check_non_roof "drywall.1" "Interior drywall repair and sound insulation batting"

(** [test_suite_5_structural_fallback ()] executes stress tests on structural degradation fallbacks. *)
let test_suite_5_structural_fallback () =
  Printf.printf "\n[Suite 5] Structural Fallback Calculations Across Varied year_built Inputs...\n%!";

  let check_fallback_year yr expected_satisfied =
    let age = float_of_int (2026 - yr) in
    let status = check_inv2_temporal ~current_year:2026 (Some age) (Some yr) in
    let tag = Printf.sprintf "5.yr.%d: Built %d (age %.0f in 2026)" yr yr age in
    if expected_satisfied then
      assert_inv2_satisfied (tag ^ " -> Satisfies INV-2 (>= 30 yrs)") status
    else
      assert_inv2_violated (tag ^ " -> Fails INV-2 (< 30 yrs)") status
  in

  check_fallback_year 1885 true;
  check_fallback_year 1895 true;
  check_fallback_year 1900 true;
  check_fallback_year 1906 true;
  check_fallback_year 1920 true;
  check_fallback_year 1940 true;
  check_fallback_year 1960 true;
  check_fallback_year 1975 true;
  check_fallback_year 1980 true;
  check_fallback_year 1990 true;
  check_fallback_year 1995 true;
  check_fallback_year 1996 true;
  check_fallback_year 1997 false;
  check_fallback_year 1998 false;
  check_fallback_year 2000 false;
  check_fallback_year 2005 false;
  check_fallback_year 2010 false;
  check_fallback_year 2015 false;
  check_fallback_year 2020 false;
  check_fallback_year 2025 false;
  check_fallback_year 2026 false;

  let check_fallback_none_age yr expected_satisfied =
    let status = check_inv2_temporal ~current_year:2026 None (Some yr) in
    let tag = Printf.sprintf "5.none_age.%d: Built %d (roof_age is None)" yr yr in
    if expected_satisfied then
      assert_inv2_satisfied (tag ^ " -> Satisfies INV-2 (>= 30 yrs)") status
    else
      assert_inv2_violated (tag ^ " -> Fails INV-2 (< 30 yrs)") status
  in

  check_fallback_none_age 1996 true;
  check_fallback_none_age 1997 false;
  check_fallback_none_age 1980 true;
  check_fallback_none_age 2015 false;

  let status_empirical_pass = check_inv2_temporal ~current_year:2026 (Some 18.0) (Some 2005) in
  assert_inv2_satisfied "5.empirical.1: Built 2005 with 2008 replacement (age 18.0) passes INV-2 (>= 15 yrs)"
    status_empirical_pass;

  let status_empirical_fail = check_inv2_temporal ~current_year:2026 (Some 10.0) (Some 2005) in
  assert_inv2_violated "5.empirical.2: Built 2005 with 2016 replacement (age 10.0) fails INV-2 (< 15 yrs)"
    status_empirical_fail;

  let status_custom_2030_pass = check_inv2_temporal ~current_year:2030 (Some 30.0) (Some 2000) in
  assert_inv2_satisfied "5.dynamic_yr.1: current_year=2030, built 2000 (age 30) passes INV-2"
    status_custom_2030_pass;

  let status_custom_2030_fail = check_inv2_temporal ~current_year:2030 (Some 29.0) (Some 2001) in
  assert_inv2_violated "5.dynamic_yr.2: current_year=2030, built 2001 (age 29) fails INV-2"
    status_custom_2030_fail;

  let status_no_data = check_inv2_temporal ~current_year:2026 None None in
  assert_inv2_violated "5.missing.1: Both roof_age and year_built missing fails INV-2"
    status_no_data;

  let status_age_only_pass = check_inv2_temporal ~current_year:2026 (Some 15.0) None in
  assert_inv2_satisfied "5.age_only.1: Empirical age 15.0 without year_built passes INV-2"
    status_age_only_pass;

  let status_age_only_fail = check_inv2_temporal ~current_year:2026 (Some 14.9) None in
  assert_inv2_violated "5.age_only.2: Empirical age 14.9 without year_built fails INV-2"
    status_age_only_fail

(** [test_suite_6_fuzz_and_stress ()] executes randomized generative stress testing. *)
let test_suite_6_fuzz_and_stress () =
  Printf.printf "\n[Suite 6] Generative Stress & Fuzz Harness (1,000 Iterations)...\n%!";

  let noise_words = [
    "kitchen"; "plumbing"; "seismic"; "deck"; "window"; "foundation";
    "drywall"; "electrical"; "charger"; "furnace"; "heater"; "panel"
  ] in

  let roof_words = [
    "bitumen"; "tpo"; "epdm"; "torch down"; "built-up"; "built up";
    "tar and gravel"; "shingle"; "reroof"; "re-roof"; "replace roof"; "tear off"
  ] in

  let random_date yr =
    let m = 1 + Random.int 12 in
    let d = 1 + Random.int 28 in
    Printf.sprintf "%04d-%02d-%02dT00:00:00" yr m d
  in

  Random.init 42;
  let exception_count = ref 0 in

  for i = 1 to 1000 do
    try
      let is_roof = Random.bool () in
      let desc =
        if is_roof then
          let kw = List.nth roof_words (Random.int (List.length roof_words)) in
          let noise = List.nth noise_words (Random.int (List.length noise_words)) in
          Printf.sprintf "%s with %s repair" kw noise
        else
          let noise1 = List.nth noise_words (Random.int (List.length noise_words)) in
          let noise2 = List.nth noise_words (Random.int (List.length noise_words)) in
          Printf.sprintf "%s and %s upgrade" noise1 noise2
      in
      let yr_issued = 1980 + Random.int 48 in
      let yr_filed = yr_issued - Random.int 3 in
      let json = Json.Object [
        ("permit_number", Json.String (Printf.sprintf "FUZZ-%d" i));
        ("description", Json.String desc);
        ("filed_date", Json.String (random_date yr_filed));
        ("issued_date", Json.String (random_date yr_issued));
      ] in
      (match parse_roof_permit_record ~current_year:2026 json with
       | Ok r ->
           let p : permit_record = {
             permit_number = r.permit_number;
             permit_type = Some "Permit";
             description = r.description;
             date_filed = r.filed_date;
             date_issued = r.issued_date;
             status = r.status;
             year = Some yr_issued;
             is_roof_replacement = r.is_roof_replacement;
             cost = None;
           } in
           let _ = check_inv4_permits ~current_year:2026 [p] in
           ()
       | Error e ->
           failwith ("Fuzz parse failure: " ^ e))
    with _ ->
      incr exception_count
  done;

  assert_equal_int "6.1: 1,000 randomized fuzz iterations executed with 0 unhandled exceptions"
    0 !exception_count

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Milestone 2 Challenger Stress & Invariant Verification Suite ===\n";
  Printf.printf "======================================================================\n%!";

  test_suite_1_multi_permit_parcels ();
  test_suite_2_date_precedence ();
  test_suite_3_roofing_keywords ();
  test_suite_4_non_roof_alterations ();
  test_suite_5_structural_fallback ();
  test_suite_6_fuzz_and_stress ();

  Printf.printf "\n======================================================================\n";
  Printf.printf "=== CHALLENGER SUMMARY: %d Total, %d Passed, %d Failed ===\n"
    !test_count !pass_count !fail_count;
  Printf.printf "======================================================================\n\n%!";

  if !fail_count > 0 then exit 1 else exit 0
