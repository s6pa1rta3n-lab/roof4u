(**
   test_milestone2_benchmarks.ml - Formal Milestone 2 Benchmark Verification Suite.
   Evaluates 5 Qualified Benchmark Properties (BENCH-01 to BENCH-05),
   3 Negative Controls (BENCH-FAIL-HOA, BENCH-FAIL-RECENT, BENCH-FAIL-RENTAL),
   Valuation Boundaries ($999,999 vs $1,000,000), Zero-Permit Structural Fallback
   (1996 vs 1997), USPS Pub 28 Address Normalization, and Canonical APN Matching.
*)

open Roof_engine
open Types

let test_count = ref 0
let pass_count = ref 0

let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.printf "  [FAIL] %s\n%!" name;
    failwith ("Assertion failed: " ^ name)
  )

let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.printf "  [FAIL] %s\n  Expected: %s\n  Actual:   %s\n%!" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.printf "  [FAIL] %s\n  Expected: %d\n  Actual:   %d\n%!" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

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

let run_qualified_benchmarks () =
  Printf.printf "\n[Benchmark Suite 1] 5 Qualified Benchmark Properties (INV1-4)...\n%!";

  let bench_01_lead : raw_lead = {
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
  let v1 = Scorer.verify_lead bench_01_lead in
  (match v1.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-01: Pacific Heights Victorian Qualifies" true;
       assert_true "BENCH-01: Score >= 70.0 (got >= 90.0)" (score.total_score >= 90.0);
       assert_equal_int "BENCH-01: Passes all 4 formal invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-01: Valid 64-character SHA-256 proof" (String.length v1.sha256_proof = 64)
   | Disqualified _ ->
       assert_true "BENCH-01: Unexpected disqualification" false);

  let bench_02_lead : raw_lead = {
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
  let v2 = Scorer.verify_lead bench_02_lead in
  (match v2.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-02: Cow Hollow Victorian Qualifies" true;
       assert_true "BENCH-02: Score >= 70.0 (got >= 85.0)" (score.total_score >= 85.0);
       assert_equal_int "BENCH-02: Passes all 4 formal invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-02: Valid 64-character SHA-256 proof" (String.length v2.sha256_proof = 64)
   | Disqualified _ ->
       assert_true "BENCH-02: Unexpected disqualification" false);

  let bench_03_lead : raw_lead = {
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
  let v3 = Scorer.verify_lead bench_03_lead in
  (match v3.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-03: Marina Flat 2-4 Unit Qualifies" true;
       assert_true "BENCH-03: Score >= 60.0 qualification threshold (got >= 65.0)" (score.total_score >= 65.0);
       assert_equal_int "BENCH-03: Passes all 4 formal invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-03: Valid 64-character SHA-256 proof" (String.length v3.sha256_proof = 64)
   | Disqualified _ ->
       assert_true "BENCH-03: Unexpected disqualification" false);

  let bench_04_lead : raw_lead = {
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
  let v4 = Scorer.verify_lead bench_04_lead in
  (match v4.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-04: Presidio Heights Mansard Qualifies" true;
       assert_true "BENCH-04: Score >= 70.0 (got >= 90.0)" (score.total_score >= 90.0);
       assert_equal_int "BENCH-04: Passes all 4 formal invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-04: Valid 64-character SHA-256 proof" (String.length v4.sha256_proof = 64)
   | Disqualified _ ->
       assert_true "BENCH-04: Unexpected disqualification" false);

  let bench_05_lead : raw_lead = {
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
  let v5 = Scorer.verify_lead bench_05_lead in
  (match v5.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-05: Sunset Flat Roof Qualifies" true;
       assert_true "BENCH-05: Score >= 60.0 qualification threshold (got >= 65.0)" (score.total_score >= 65.0);
       assert_equal_int "BENCH-05: Passes all 4 formal invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-05: Valid 64-character SHA-256 proof" (String.length v5.sha256_proof = 64)
   | Disqualified _ ->
       assert_true "BENCH-05: Unexpected disqualification" false)

let run_negative_controls () =
  Printf.printf "\n[Benchmark Suite 2] 3 Negative Control Properties (Exact Invariant Failures)...\n%!";

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
   | Disqualified { failed_invariants; _ } ->
       assert_true "BENCH-FAIL-HOA: Disqualified as expected" true;
       assert_true "BENCH-FAIL-HOA: Fails INV-1 Physical (Condo)"
         (List.exists (fun v -> v.code = INV1_Physical) failed_invariants);
       assert_true "BENCH-FAIL-HOA: Fails INV-3 Economic (HOA)"
         (List.exists (fun v -> v.code = INV3_Economic) failed_invariants)
   | Qualified _ ->
       assert_true "BENCH-FAIL-HOA: Erroneously qualified" false);

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
   | Disqualified { failed_invariants; _ } ->
       assert_true "BENCH-FAIL-RECENT: Disqualified as expected" true;
       assert_true "BENCH-FAIL-RECENT: Fails INV-2 Temporal (Roof age 3.0 < 15.0 yrs)"
         (List.exists (fun v -> v.code = INV2_Temporal) failed_invariants);
       assert_true "BENCH-FAIL-RECENT: Fails INV-4 Permits (Replacement permit in 2023)"
         (List.exists (fun v -> v.code = INV4_Permits) failed_invariants)
   | Qualified _ ->
       assert_true "BENCH-FAIL-RECENT: Erroneously qualified" false);

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
   | Disqualified { failed_invariants; _ } ->
       assert_true "BENCH-FAIL-RENTAL: Disqualified as expected" true;
       assert_true "BENCH-FAIL-RENTAL: Fails INV-1 Physical (Commercial)"
         (List.exists (fun v -> v.code = INV1_Physical) failed_invariants);
       assert_true "BENCH-FAIL-RENTAL: Fails INV-3 Economic (Corporate Rental)"
         (List.exists (fun v -> v.code = INV3_Economic) failed_invariants)
   | Qualified _ ->
       assert_true "BENCH-FAIL-RENTAL: Erroneously qualified" false)

let run_valuation_boundary_tests () =
  Printf.printf "\n[Benchmark Suite 3] Valuation Boundary Value Analysis ($999,999 vs $1,000,000)...\n%!";

  let inv3_sub = Invariants.check_inv3_economic (Some 999999.0) false false in
  assert_true "VAL.BVA.1: $999,999.00 fails INV-3 Economic"
    (match inv3_sub with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let inv3_sub_cent = Invariants.check_inv3_economic (Some 999999.99) false false in
  assert_true "VAL.BVA.2: $999,999.99 fails INV-3 Economic"
    (match inv3_sub_cent with Violated { code = INV3_Economic; _ } -> true | _ -> false);

  let inv3_exact = Invariants.check_inv3_economic (Some 1000000.0) false false in
  assert_true "VAL.BVA.3: $1,000,000.00 exact threshold passes INV-3 Economic"
    (match inv3_exact with Satisfied _ -> true | _ -> false);

  let inv3_above_cent = Invariants.check_inv3_economic (Some 1000000.01) false false in
  assert_true "VAL.BVA.4: $1,000,000.01 passes INV-3 Economic"
    (match inv3_above_cent with Satisfied _ -> true | _ -> false);

  let inv3_none = Invariants.check_inv3_economic None false false in
  assert_true "VAL.BVA.5: Missing valuation fails INV-3 Economic"
    (match inv3_none with Violated { code = INV3_Economic; _ } -> true | _ -> false)

let run_zero_permit_structural_fallback_tests () =
  Printf.printf "\n[Benchmark Suite 4] Zero-Permit Structural Age Fallback (1996 vs 1997)...\n%!";

  let inv2_1996 = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1996) in
  assert_true "STRUCT.FALLBACK.1: Built in 1996 (age 30 in 2026) passes INV-2"
    (match inv2_1996 with Satisfied _ -> true | _ -> false);

  let inv2_1997 = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1997) in
  assert_true "STRUCT.FALLBACK.2: Built in 1997 (age 29 in 2026) fails INV-2"
    (match inv2_1997 with Violated { code = INV2_Temporal; _ } -> true | _ -> false);

  let lead_1996 : raw_lead = {
    address = "123 Historic Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 2500000.0;
    owner_name = Some "Historic Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0100-001";
    last_roof_permit_date = None;
    roof_age_years = Some 30.0;
    year_built = Some 1996;
    phone_number = None;
    permits = [];
  } in
  let v_1996 = Scorer.verify_lead ~current_year:2026 lead_1996 in
  assert_true "STRUCT.FALLBACK.3: Lead built in 1996 with zero permits qualifies"
    (match v_1996.verdict with Qualified _ -> true | Disqualified _ -> false);

  let lead_1997 : raw_lead = {
    address = "124 Modern Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 2500000.0;
    owner_name = Some "Modern Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0100-002";
    last_roof_permit_date = None;
    roof_age_years = Some 29.0;
    year_built = Some 1997;
    phone_number = None;
    permits = [];
  } in
  let v_1997 = Scorer.verify_lead ~current_year:2026 lead_1997 in
  assert_true "STRUCT.FALLBACK.4: Lead built in 1997 with zero permits fails INV-2"
    (match v_1997.verdict with
     | Disqualified { failed_invariants; _ } ->
         List.exists (fun v -> v.code = INV2_Temporal) failed_invariants
     | Qualified _ -> false)

let run_address_normalization_tests () =
  Printf.printf "\n[Benchmark Suite 5] USPS Publication 28 Address Normalization...\n%!";

  assert_equal_str "USPS.1: Strip leading zeros from street number 0422"
    "422" (Homeowner_addresses.normalize_street_number "0422");
  assert_equal_str "USPS.2: Strip quadruple zeros 0000"
    "0" (Homeowner_addresses.normalize_street_number "0000");
  assert_equal_str "USPS.3: Retain non-zero street number 2223"
    "2223" (Homeowner_addresses.normalize_street_number "2223");

  assert_equal_str "USPS.4: Standardize STREET to ST"
    "ST" (Homeowner_addresses.normalize_street_suffix "STREET");
  assert_equal_str "USPS.5: Standardize AVENUE to AVE"
    "AVE" (Homeowner_addresses.normalize_street_suffix "AVENUE");
  assert_equal_str "USPS.6: Standardize BOULEVARD to BLVD"
    "BLVD" (Homeowner_addresses.normalize_street_suffix "BOULEVARD");
  assert_equal_str "USPS.7: Standardize DRIVE to DR"
    "DR" (Homeowner_addresses.normalize_street_suffix "DRIVE");

  assert_equal_str "USPS.8: Full address normalization 0422 14TH AVENUE"
    "422 14TH AVE" (Homeowner_addresses.normalize_usps_pub28 "0422 14TH AVENUE");
  assert_equal_str "USPS.9: Full address normalization with 0000 prefix"
    "2223 PACIFIC ST" (Homeowner_addresses.normalize_usps_pub28 "0000 2223 PACIFIC STREET")

let run_hoa_and_rental_detection_tests () =
  Printf.printf "\n[Benchmark Suite 6] HOA and Rental Property Detection...\n%!";

  assert_true "HOA.1: Lot in 0500-0999 series is condo"
    (Property_tax_records.is_condo_lot_series "3774-0502");
  assert_true "HOA.2: Lot 520 compact is condo"
    (Property_tax_records.is_condo_lot_series "37740520");
  assert_true "HOA.3: Lot 010 is not condo series"
    (not (Property_tax_records.is_condo_lot_series "0576-010"));

  assert_true "HOA.4: Property type Condo triggers HOA"
    (Property_tax_records.is_hoa_property ~property_type:Condo ());
  assert_true "HOA.5: Master HOA deed token triggers HOA"
    (Property_tax_records.is_hoa_property ~owner_name:"200 Brannan Master HOA Deed" ());
  assert_true "HOA.6: Unit number in address triggers HOA"
    (Property_tax_records.is_hoa_property ~address:"200 Brannan St #401" ());
  assert_true "HOA.7: Class D with single-family definition is disambiguated"
    (not (Property_tax_records.is_hoa_property
            ~property_class_code:"D"
            ~property_class_def:"Single Family Residence"
            ~property_type:SingleFamily
            ~parcel_number:"0576-010"
            ~address:"2223 Pacific Ave" ()));

  assert_true "RENTAL.1: Units count > 4 triggers rental"
    (Property_tax_records.is_rental_property ~units_count:6 ());
  assert_true "RENTAL.2: Corporate LLC triggers rental"
    (Property_tax_records.is_rental_property ~ownership_type:CorporateLLC ());
  assert_true "RENTAL.3: Corporate LLC owner name triggers rental"
    (Property_tax_records.is_rental_property ~owner_name:"Financial District Holdings LLC" ());
  assert_true "RENTAL.4: Absence of Prop 13 exemption triggers rental"
    (Property_tax_records.is_rental_property ~has_homeowner_exemption:false ());
  assert_true "RENTAL.5: Mailing address mismatch triggers rental"
    (Property_tax_records.is_rental_property
       ~situs_address:"2223 Pacific Ave, San Francisco, CA"
       ~tax_mailing_address:"PO Box 1234, Dallas, TX"
       ~has_homeowner_exemption:true ());
  assert_true "RENTAL.6: Matching mailing address with exemption is not rental"
    (not (Property_tax_records.is_rental_property
            ~situs_address:"2223 Pacific Ave, San Francisco, CA"
            ~tax_mailing_address:"2223 Pacific Ave, San Francisco, CA"
            ~has_homeowner_exemption:true
            ~ownership_type:Trust
            ~units_count:1 ()))

let run_permit_and_keyword_tests () =
  Printf.printf "\n[Benchmark Suite 7] Roofing Permit Keywords, Recency, and Date Priority...\n%!";

  let p_bitumen = {
    permit_number = "P-BITUMEN";
    permit_type = Some "Alteration";
    description = "Modified bitumen flat roofing installation";
    date_filed = Some "2008-03-22";
    date_issued = Some "2008-04-10";
    status = Some "COMPLETED";
    year = Some 2008;
    is_roof_replacement = false;
    cost = Some 26500.0;
  } in
  assert_true "KEYWORD.1: Bitumen recognized as roof replacement"
    (Invariants.is_roof_replacement_permit p_bitumen);

  let p_tpo = {
    permit_number = "P-TPO";
    permit_type = Some "Alteration";
    description = "Single-ply TPO membrane roof installation";
    date_filed = Some "2010-06-15";
    date_issued = Some "2010-07-01";
    status = Some "COMPLETED";
    year = Some 2010;
    is_roof_replacement = false;
    cost = Some 31000.0;
  } in
  assert_true "KEYWORD.2: TPO recognized as roof replacement"
    (Invariants.is_roof_replacement_permit p_tpo);

  let p_epdm = {
    permit_number = "P-EPDM";
    permit_type = Some "Alteration";
    description = "EPDM rubber membrane reroofing";
    date_filed = Some "2005-02-10";
    date_issued = Some "2005-02-28";
    status = Some "COMPLETED";
    year = Some 2005;
    is_roof_replacement = false;
    cost = Some 28000.0;
  } in
  assert_true "KEYWORD.3: EPDM recognized as roof replacement"
    (Invariants.is_roof_replacement_permit p_epdm);

  let p_torch = {
    permit_number = "P-TORCH";
    permit_type = Some "Alteration";
    description = "Torch down multi-ply flat roof application";
    date_filed = Some "2007-09-12";
    date_issued = Some "2007-09-30";
    status = Some "COMPLETED";
    year = Some 2007;
    is_roof_replacement = false;
    cost = Some 24000.0;
  } in
  assert_true "KEYWORD.4: Torch down recognized as roof replacement"
    (Invariants.is_roof_replacement_permit p_torch);

  let p_builtup = {
    permit_number = "P-BUILTUP";
    permit_type = Some "Alteration";
    description = "Built-up tar and gravel flat roof replacement";
    date_filed = Some "2006-11-04";
    date_issued = Some "2006-11-20";
    status = Some "COMPLETED";
    year = Some 2006;
    is_roof_replacement = false;
    cost = Some 28000.0;
  } in
  assert_true "KEYWORD.5: Built-up tar and gravel recognized as roof replacement"
    (Invariants.is_roof_replacement_permit p_builtup);

  let p_shingle = {
    permit_number = "P-SHINGLE";
    permit_type = Some "Alteration";
    description = "Victorian asphalt shingle tear off and install";
    date_filed = Some "1998-05-12";
    date_issued = Some "1998-06-01";
    status = Some "COMPLETED";
    year = Some 1998;
    is_roof_replacement = false;
    cost = Some 35000.0;
  } in
  assert_true "KEYWORD.6: Shingle recognized directly as roof replacement"
    (Invariants.is_roof_replacement_permit p_shingle);

  let json_issued_priority =
    Json.Object [
      ("permit_number", Json.String "P-DATE-TEST");
      ("description", Json.String "Reroofing with shingle");
      ("filed_date", Json.String "2000-01-01T00:00:00");
      ("issued_date", Json.String "2001-06-05T00:00:00");
      ("completed_date", Json.String "2001-08-01T00:00:00");
    ]
  in
  (match Roof_permits.parse_roof_permit_record ~current_year:2026 json_issued_priority with
   | Ok r ->
       assert_true "DATE.1: Issued date takes priority over filed date (age 25.0)"
         (r.roof_age_years = Some 25.0)
   | Error e ->
       assert_true ("DATE.1: Parse error: " ^ e) false);

  let json_non_roof =
    Json.Object [
      ("permit_number", Json.String "P-ELEC-TEST");
      ("description", Json.String "EV Charger 200A Electrical Service Panel");
      ("filed_date", Json.String "2020-01-01T00:00:00");
      ("issued_date", Json.String "2020-02-01T00:00:00");
    ]
  in
  (match Roof_permits.parse_roof_permit_record ~current_year:2026 json_non_roof with
   | Ok r ->
       assert_true "DATE.2: Non-roof permit has roof_age_years = None"
         (r.roof_age_years = None);
       assert_true "DATE.3: Non-roof permit has is_roof_replacement = false"
         (not r.is_roof_replacement)
   | Error e ->
       assert_true ("DATE.2: Parse error: " ^ e) false);

  let json_clamp_zero =
    Json.Object [
      ("permit_number", Json.String "P-CLAMP-TEST");
      ("description", Json.String "Complete reroof");
      ("issued_date", Json.String "2026-03-01T00:00:00");
    ]
  in
  (match Roof_permits.parse_roof_permit_record ~current_year:2026 json_clamp_zero with
   | Ok r ->
       assert_true "DATE.4: Roof replaced in current year clamps to 0.0 yrs"
         (r.roof_age_years = Some 0.0)
   | Error e ->
       assert_true ("DATE.4: Parse error: " ^ e) false)

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Milestone 2 Benchmark Properties & Invariant Verification Suite ===\n";
  Printf.printf "======================================================================\n%!";
  run_qualified_benchmarks ();
  run_negative_controls ();
  run_valuation_boundary_tests ();
  run_zero_permit_structural_fallback_tests ();
  run_address_normalization_tests ();
  run_hoa_and_rental_detection_tests ();
  run_permit_and_keyword_tests ();
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== ALL MILESTONE 2 BENCHMARK TESTS PASSED: %d/%d (100.0%%) ===\n" !pass_count !test_count;
  Printf.printf "======================================================================\n\n%!"
