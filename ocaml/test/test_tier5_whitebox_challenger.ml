[@@@warning "-33-32"]

open Roof_engine
open Db
open Types
open Invariants
open Scorer
open Gis_roofs
open Phone_validator
open Contact_enricher
open Csv_exporter

let test_count = ref 0
let pass_count = ref 0
let fail_count = ref 0

let check_assert (name : string) (cond : bool) : unit =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n" name
  )

let check_equal_str (name : string) (expected : string) (actual : string) : unit =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n    Expected: %s\n    Actual:   %s\n" name expected actual
  )

let check_equal_int (name : string) (expected : int) (actual : int) : unit =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n    Expected: %d\n    Actual:   %d\n" name expected actual
  )

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== [TIER 5] Dedicated White-Box Adversarial Stress Harness ===\n";
  Printf.printf "======================================================================\n\n";

  Printf.printf "[T5.1] GIS Roofs: Spatial Geometry, Ray-Casting & Morphology...\n";

  let triangle : ring = [
    (-122.435, 37.790);
    (-122.430, 37.790);
    (-122.4325, 37.795);
    (-122.435, 37.790);
  ] in

  check_assert "T5.GIS.1: Point strictly inside triangle"
    (point_in_ring (-122.4325) 37.792 triangle);

  check_assert "T5.GIS.2: Point strictly outside triangle"
    (not (point_in_ring (-122.440) 37.792 triangle));

  check_assert "T5.GIS.3: Point on triangle bottom horizontal edge"
    (point_in_ring (-122.432) 37.790 triangle);

  check_assert "T5.GIS.4: Point on triangle apex vertex"
    (point_in_ring (-122.4325) 37.795 triangle);

  check_assert "T5.GIS.5: Point with latitude-longitude swapped coordinates"
    (point_in_ring 37.792 (-122.4325) triangle);

  let degen_empty : ring = [] in
  let degen_two : ring = [(-122.435, 37.790); (-122.430, 37.790)] in
  check_assert "T5.GIS.6: Degenerate empty ring returns false"
    (not (point_in_ring (-122.432) 37.790 degen_empty));
  check_assert "T5.GIS.7: Degenerate two-point ring returns false"
    (not (point_in_ring (-122.432) 37.790 degen_two));

  let outer_square : ring = [
    (-10.0, -10.0);
    (10.0, -10.0);
    (10.0, 10.0);
    (-10.0, 10.0);
    (-10.0, -10.0);
  ] in
  let hole_square : ring = [
    (-4.0, -4.0);
    (4.0, -4.0);
    (4.0, 4.0);
    (-4.0, 4.0);
    (-4.0, -4.0);
  ] in
  let poly_with_hole : polygon = [outer_square; hole_square] in

  check_assert "T5.GIS.8: Point inside outer ring but outside hole is inside polygon"
    (point_in_polygon 7.0 7.0 poly_with_hole);

  check_assert "T5.GIS.9: Point inside interior hole is excluded from polygon"
    (not (point_in_polygon 0.0 0.0 poly_with_hole));

  check_assert "T5.GIS.10: Point outside outer ring is excluded from polygon"
    (not (point_in_polygon 15.0 15.0 poly_with_hole));

  let horseshoe_poly : polygon = [[
    (0.0, 0.0);
    (6.0, 0.0);
    (6.0, 6.0);
    (4.0, 6.0);
    (4.0, 2.0);
    (2.0, 2.0);
    (2.0, 6.0);
    (0.0, 6.0);
    (0.0, 0.0);
  ]] in
  check_assert "T5.GIS.11: Point inside concavity cove is outside polygon"
    (not (point_in_polygon 3.0 4.0 horseshoe_poly));
  check_assert "T5.GIS.12: Point inside horseshoe arm is inside polygon"
    (point_in_polygon 1.0 4.0 horseshoe_poly);

  let bbox_empty = compute_bbox [] in
  check_assert "T5.GIS.13: compute_bbox on empty list returns zeros"
    (bbox_empty = (0.0, 0.0, 0.0, 0.0));

  let m_mansard_1 : morphology_inputs = {
    pitch_deg = Some 45.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1920;
    style_tag = Some "Second Empire";
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  check_assert "T5.GIS.14: Morphology classifier identifies Mansard via style"
    (classify_roof_morphology m_mansard_1 = Mansard);

  let m_mansard_shape : morphology_inputs = {
    pitch_deg = Some 50.0;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = Some "mansard";
  } in
  check_assert "T5.GIS.15: Morphology classifier identifies Mansard via osm_shape"
    (classify_roof_morphology m_mansard_shape = Mansard);

  let m_flat_pitch : morphology_inputs = {
    pitch_deg = Some 4.5;
    height_delta_ft = None;
    year_built = Some 1950;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "T5.GIS.16: Morphology classifier identifies Flat via low pitch <= 5.0 deg"
    (classify_roof_morphology m_flat_pitch = Flat);

  let m_flat_mat : morphology_inputs = {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = Some "Modified Bitumen Membrane";
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "T5.GIS.17: Morphology classifier identifies Flat via membrane material"
    (classify_roof_morphology m_flat_mat = Flat);

  let m_vic_style : morphology_inputs = {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 12.0;
    year_built = Some 1898;
    style_tag = Some "Queen Anne Victorian";
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  check_assert "T5.GIS.18: Morphology classifier identifies Victorian via style"
    (classify_roof_morphology m_vic_style = Victorian);

  let m_vic_structural : morphology_inputs = {
    pitch_deg = Some 40.0;
    height_delta_ft = None;
    year_built = Some 1905;
    style_tag = None;
    material_desc = None;
    polygon_points = 7;
    osm_shape = None;
  } in
  check_assert "T5.GIS.19: Morphology classifier identifies Victorian via pre-1915 age and high pitch"
    (classify_roof_morphology m_vic_structural = Victorian);

  let m_metal : morphology_inputs = {
    pitch_deg = Some 20.0;
    height_delta_ft = None;
    year_built = Some 1980;
    style_tag = None;
    material_desc = Some "Standing Seam Metal";
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "T5.GIS.20: Morphology classifier identifies Metal"
    (classify_roof_morphology m_metal = Metal);

  let m_hip : morphology_inputs = {
    pitch_deg = Some 25.0;
    height_delta_ft = None;
    year_built = Some 1960;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = Some "hipped";
  } in
  check_assert "T5.GIS.21: Morphology classifier identifies Hip"
    (classify_roof_morphology m_hip = Hip);

  let m_gable : morphology_inputs = {
    pitch_deg = Some 22.0;
    height_delta_ft = None;
    year_built = Some 1975;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "T5.GIS.22: Morphology classifier identifies Gable"
    (classify_roof_morphology m_gable = Gable);

  let m_unknown : morphology_inputs = {
    pitch_deg = Some 90.0;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 2;
    osm_shape = None;
  } in
  check_assert "T5.GIS.23: Morphology classifier identifies 90-degree pitch as Unknown"
    (classify_roof_morphology m_unknown = Unknown);

  check_assert "T5.GIS.24: Affluence tier for Pacific Heights is Tier 1"
    (affluence_tier_of_neighborhood "Pacific Heights" = Tier1_UltraAffluent);

  check_assert "T5.GIS.25: Affluence alias Cow Hollow maps to Tier 1"
    (affluence_tier_of_neighborhood "Cow Hollow" = Tier1_UltraAffluent);

  check_assert "T5.GIS.26: Affluence tier for Noe Valley is Tier 2"
    (affluence_tier_of_neighborhood "Noe Valley" = Tier2_Affluent);

  check_assert "T5.GIS.27: Affluence tier for Mission is Tier 3"
    (affluence_tier_of_neighborhood "Mission" = Tier3_Moderate);

  Printf.printf "  Section 1 complete.\n\n";

  Printf.printf "[T5.2] Phone Validator: NANP RFC Compliance & Dummy Filtration...\n";

  let v_sf = sanitize_and_normalize "(415) 824-1928" in
  check_assert "T5.PHONE.1: Valid SF 415 phone parses to SF_Primary tier"
    (match v_sf with
     | Ok p -> p.canonical = "415-824-1928" && p.tier = SF_Primary
     | Error _ -> false);

  let v_bay = sanitize_and_normalize "510.652.8190" in
  check_assert "T5.PHONE.2: Valid Oakland 510 phone parses to Bay_Area tier"
    (match v_bay with
     | Ok p -> p.canonical = "510-652-8190" && p.tier = Bay_Area
     | Error _ -> false);

  let v_us = sanitize_and_normalize "+1-212-736-5000" in
  check_assert "T5.PHONE.3: Valid NYC 212 phone parses to Valid_US tier"
    (match v_us with
     | Ok p -> p.canonical = "212-736-5000" && p.tier = Valid_US
     | Error _ -> false);

  let v_int_001 = sanitize_and_normalize "0014158241928" in
  check_assert "T5.PHONE.4: 13-digit 001 international prefix stripped cleanly"
    (match v_int_001 with
     | Ok p -> p.canonical = "415-824-1928"
     | Error _ -> false);

  let v_foreign = sanitize_and_normalize "+44 20 7123 4567" in
  check_assert "T5.PHONE.5: Foreign +44 country code rejected"
    (match v_foreign with
     | Error (InvalidCountryCode _) -> true
     | _ -> false);

  let v_npa_zero = sanitize_and_normalize "015-824-1928" in
  check_assert "T5.PHONE.6: NPA starting with 0 rejected"
    (match v_npa_zero with
     | Error (InvalidNpaStartDigit '0') -> true
     | _ -> false);

  let v_npa_one = sanitize_and_normalize "115-824-1928" in
  check_assert "T5.PHONE.7: NPA starting with 1 rejected"
    (match v_npa_one with
     | Error (InvalidNpaStartDigit '1') -> true
     | _ -> false);

  let v_npa_n11 = sanitize_and_normalize "911-824-1928" in
  check_assert "T5.PHONE.8: Reserved 911 NPA rejected"
    (match v_npa_n11 with
     | Error (ReservedN11Code "911") -> true
     | _ -> false);

  let v_npa_n9x = sanitize_and_normalize "290-824-1928" in
  check_assert "T5.PHONE.9: Reserved ERC N9X NPA rejected"
    (match v_npa_n9x with
     | Error (InvalidAreaCode "290") -> true
     | _ -> false);

  let v_npa_555 = sanitize_and_normalize "555-824-1928" in
  check_assert "T5.PHONE.10: 555 area code rejected"
    (match v_npa_555 with
     | Error (Fictitious555Number _) -> true
     | _ -> false);

  let v_tollfree = sanitize_and_normalize "800-555-1212" in
  check_assert "T5.PHONE.11: Toll-free 800 code rejected"
    (match v_tollfree with
     | Error (TollFreeAreaCode "800") -> true
     | _ -> false);

  let v_premium = sanitize_and_normalize "900-824-1928" in
  check_assert "T5.PHONE.12: Premium 900 code rejected"
    (match v_premium with
     | Error (PremiumAreaCode "900") -> true
     | _ -> false);

  let v_nxx_zero = sanitize_and_normalize "415-034-5678" in
  check_assert "T5.PHONE.13: NXX starting with 0 rejected"
    (match v_nxx_zero with
     | Error (InvalidNxxStartDigit '0') -> true
     | _ -> false);

  let v_nxx_n11 = sanitize_and_normalize "415-911-5678" in
  check_assert "T5.PHONE.14: NXX N11 rejected"
    (match v_nxx_n11 with
     | Error (ReservedN11Code "911") -> true
     | _ -> false);

  let v_nxx_555 = sanitize_and_normalize "415-555-0199" in
  check_assert "T5.PHONE.15: Fictitious 555 exchange rejected"
    (match v_nxx_555 with
     | Error (Fictitious555Number _) -> true
     | _ -> false);

  let v_rep_10 = sanitize_and_normalize "415-444-4444" in
  check_assert "T5.PHONE.16: Repeating 7-digit local rejected"
    (match v_rep_10 with
     | Error (RepeatingDigits _) -> true
     | _ -> false);

  let v_rep_station = sanitize_and_normalize "415-824-0000" in
  check_assert "T5.PHONE.17: Repeating 0000 station rejected"
    (match v_rep_station with
     | Error (RepeatingDigits _) -> true
     | _ -> false);

  let v_seq_10 = sanitize_and_normalize "987-654-3210" in
  check_assert "T5.PHONE.18: Sequential 9876543210 rejected"
    (match v_seq_10 with
     | Error (SequentialDigits _) -> true
     | _ -> false);

  let v_seq_loc = sanitize_and_normalize "415-876-5432" in
  check_assert "T5.PHONE.19: Sequential local 8765432 rejected"
    (match v_seq_loc with
     | Error (SequentialDigits _) -> true
     | _ -> false);

  let v_formula_eq = sanitize_and_normalize "=4158241928" in
  check_assert "T5.PHONE.20: Malicious formula prefix '=' rejected"
    (match v_formula_eq with
     | Error (MaliciousFormulaPrefix _) -> true
     | _ -> false);

  let v_formula_at = sanitize_and_normalize "@4158241928" in
  check_assert "T5.PHONE.21: Malicious formula prefix '@' rejected"
    (match v_formula_at with
     | Error (MaliciousFormulaPrefix _) -> true
     | _ -> false);

  let v_empty = sanitize_and_normalize "   " in
  check_assert "T5.PHONE.22: Empty string rejected"
    (match v_empty with
     | Error EmptyNumber -> true
     | _ -> false);

  let v_short = sanitize_and_normalize "415-824" in
  check_assert "T5.PHONE.23: Short phone length rejected"
    (match v_short with
     | Error (InvalidLength 6) -> true
     | _ -> false);

  let extracted = extract_valid_phones_from_text "Call our office at <a href=\"tel:4158241928\">here</a> or 510-652-8190 directly." in
  check_assert "T5.PHONE.24: extract_valid_phones_from_text extracts tel link and body phone"
    (List.length extracted = 2 &&
     List.exists (fun p -> p.canonical = "415-824-1928") extracted &&
     List.exists (fun p -> p.canonical = "510-652-8190") extracted);

  Printf.printf "  Section 2 complete.\n\n";

  Printf.printf "[T5.3] Contact Enricher: 4-Tier Cascade Error Isolation...\n";

  let dummy_lead : Types.raw_lead = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 4350000.0;
    owner_name = Some "Pacific Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0576-010";
    last_roof_permit_date = None;
    roof_age_years = Some 28.0;
    year_built = Some 1895;
    phone_number = None;
    permits = [];
  } in

  let mock_skip_success (lead : Types.raw_lead) : (Types.raw_lead, string) result =
    Ok { lead with Types.phone_number = Some "415-824-1928" }
  in
  let mock_osint_fail _ : (Types.raw_lead, string) result =
    Error "OSINT timeout"
  in
  let mock_seed_none _ : string option = None in

  let (lead_t1, tag_t1) = enrich_lead_custom
    ~skip_tracing_fn:mock_skip_success
    ~osint_fn:mock_osint_fail
    ~seed_directory_fn:mock_seed_none
    dummy_lead
  in
  check_assert "T5.ENRICH.1: Tier 1 Skip Tracer success populates phone"
    (lead_t1.phone_number = Some "415-824-1928" && tag_t1 = "TIER1_SKIP_TRACER");

  let mock_skip_crash _ : (Types.raw_lead, string) result =
    failwith "Skip tracing socket connection crashed"
  in
  let mock_osint_success (lead : Types.raw_lead) : (Types.raw_lead, string) result =
    Ok { lead with Types.phone_number = Some "510-652-8190" }
  in

  let (lead_t2, tag_t2) = enrich_lead_custom
    ~skip_tracing_fn:mock_skip_crash
    ~osint_fn:mock_osint_success
    ~seed_directory_fn:mock_seed_none
    dummy_lead
  in
  check_assert "T5.ENRICH.2: Tier 1 exception is isolated, falls to Tier 2 OSINT"
    (lead_t2.phone_number = Some "510-652-8190" && tag_t2 = "TIER2_OSINT_SCRAPER");

  let mock_skip_dummy (lead : Types.raw_lead) : (Types.raw_lead, string) result =
    Ok { lead with Types.phone_number = Some "415-555-0199" }
  in
  let mock_osint_crash _ : (Types.raw_lead, string) result =
    raise (Sys_error "Connection refused")
  in
  let mock_seed_success _ : string option =
    Some "650-843-1920"
  in

  let (lead_t3, tag_t3) = enrich_lead_custom
    ~skip_tracing_fn:mock_skip_dummy
    ~osint_fn:mock_osint_crash
    ~seed_directory_fn:mock_seed_success
    dummy_lead
  in
  check_assert "T5.ENRICH.3: Tier 1 dummy phone rejected, Tier 2 exception isolated, falls to Tier 3"
    (lead_t3.phone_number = Some "650-843-1920" && tag_t3 = "TIER3_MUNICIPAL_DIRECTORY");

  let mock_seed_crash _ : string option =
    failwith "Directory disk corrupt"
  in

  let (lead_t4, tag_t4) = enrich_lead_custom
    ~skip_tracing_fn:mock_skip_crash
    ~osint_fn:mock_osint_crash
    ~seed_directory_fn:mock_seed_crash
    dummy_lead
  in
  check_assert "T5.ENRICH.4: All tiers crashing isolated gracefully, returns NONE"
    (lead_t4.phone_number = None && tag_t4 = "NONE");

  Printf.printf "  Section 3 complete.\n\n";

  Printf.printf "[T5.4] SQLite DB: WAL Mode, SQL Injection Escaping & Concurrency...\n";

  let temp_db_file = Filename.temp_file "t5_adv_db" ".sqlite" in
  let db = Db.create ~db_path:temp_db_file () in

  let pragma_wal = Db.run_sqlite_cmd temp_db_file "PRAGMA journal_mode;" in
  check_assert "T5.DB.1: SQLite WAL journal mode is active"
    (match pragma_wal with
     | Ok s -> String.trim (String.lowercase_ascii s) = "wal"
     | Error _ -> false);

  let sqli_lead_1 : Types.raw_lead = {
    dummy_lead with
    address = "100 O'Farrell St, Suite #200";
    owner_name = Some "Patrick O'Connor & Co";
    estimated_value = Some 3500000.0;
  } in
  let res_sqli_1 = Db.insert_lead db sqli_lead_1 in
  check_assert "T5.DB.2: Insert lead with single quotes succeeds"
    (match res_sqli_1 with Ok _ -> true | Error _ -> false);

  let retrieved_1 = Db.get_lead_by_address db "100 O'Farrell St, Suite #200" in
  check_assert "T5.DB.3: Single quote escaping round-trips with byte fidelity"
    (match retrieved_1 with
     | Some r -> r.address = "100 O'Farrell St, Suite #200" && r.owner_name = Some "Patrick O'Connor & Co"
     | None -> false);

  let sqli_lead_2 : Types.raw_lead = {
    dummy_lead with
    address = "'; DROP TABLE leads; --";
    owner_name = Some "Robert'); DROP TABLE leads;--";
  } in
  let res_sqli_2 = Db.insert_lead db sqli_lead_2 in
  check_assert "T5.DB.4: SQL injection payload safely stored as string literal"
    (match res_sqli_2 with Ok _ -> true | Error _ -> false);

  let table_exists = Db.run_sqlite_cmd temp_db_file "SELECT count(*) FROM leads;" in
  check_assert "T5.DB.5: Table remains intact and not dropped"
    (match table_exists with Ok _ -> true | Error _ -> false);

  let empty_lead : Types.raw_lead = { dummy_lead with address = "   " } in
  check_assert "T5.DB.6: Empty address is rejected on insert"
    (match Db.insert_lead db empty_lead with Error _ -> true | Ok _ -> false);

  let dup_res = Db.insert_lead db sqli_lead_1 in
  check_assert "T5.DB.7: Duplicate address insertion is rejected"
    (match dup_res with Error _ -> true | Ok _ -> false);

  let upsert_res = Db.upsert_lead db ~status:Validated { sqli_lead_1 with estimated_value = Some 4000000.0 } in
  check_assert "T5.DB.8: Upsert updates existing lead without duplicating"
    (match upsert_res with
     | Ok id ->
         let r = Db.get_lead_by_id db id in
         (match r with Some row -> row.estimated_value = Some 4000000.0 | None -> false)
     | Error _ -> false);

  let threads = ref [] in
  let thread_errors = ref 0 in
  for i = 1 to 10 do
    let th = Thread.create (fun idx ->
      let addr = Printf.sprintf "%d Concurrent Pacific Way" (idx + 1000) in
      let l = { dummy_lead with address = addr; estimated_value = Some (float_of_int (idx * 1000000)) } in
      match Db.insert_lead db l with
      | Ok _ -> ()
      | Error _ -> incr thread_errors
    ) i in
    threads := th :: !threads
  done;
  List.iter Thread.join !threads;

  check_assert "T5.DB.9: Concurrent multi-threaded inserts complete without race errors"
    (!thread_errors = 0);

  let count_all = Db.count_leads db in
  check_assert "T5.DB.10: All concurrent leads counted in SQLite and memory cache"
    (count_all >= 12);

  (try Sys.remove temp_db_file with _ -> ());
  (try Sys.remove (temp_db_file ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db_file ^ "-shm") with _ -> ());

  Printf.printf "  Section 4 complete.\n\n";

  Printf.printf "[T5.5] CSV Exporter: Formula Injection Neutralization & RFC 4180 Escaping...\n";

  let triggers = ["="; "+"; "-"; "@"; "\t"; "\r"] in
  let triggers_sanitized = ref true in
  List.iter (fun tr ->
    let payload = tr ^ "cmd|'/c calc'!A0" in
    let s = sanitize_csv_field payload in
    if s <> "'" ^ payload then triggers_sanitized := false
  ) triggers;
  check_assert "T5.CSV.1: All 6 DDE trigger characters prefixed with single quote"
    !triggers_sanitized;

  let whitespace_triggers = [
    "  =cmd";
    "   @SUM(A1:A10)";
    " \t-cmd";
    "  +12345";
  ] in
  let ws_passed = ref true in
  List.iter (fun p ->
    let s = sanitize_csv_field p in
    if not (String.starts_with ~prefix:"'" s) then ws_passed := false
  ) whitespace_triggers;
  check_assert "T5.CSV.2: DDE triggers preceded by whitespace are sanitized"
    !ws_passed;

  let comma_field = escape_csv_field "2223 Pacific Ave, Suite #4" in
  check_equal_str "T5.CSV.3: Field with comma is wrapped in double quotes"
    "\"2223 Pacific Ave, Suite #4\"" comma_field;

  let quote_field = escape_csv_field "John \"Architect\" Doe" in
  check_equal_str "T5.CSV.4: Field with internal quotes doubles them"
    "\"John \"\"Architect\"\" Doe\"" quote_field;

  let newline_field = escape_csv_field "Line1\nLine2" in
  check_equal_str "T5.CSV.5: Field with newline is wrapped in double quotes"
    "\"Line1\nLine2\"" newline_field;

  let space_field = escape_csv_field " 94115 " in
  check_equal_str "T5.CSV.6: Field with leading space is wrapped in double quotes"
    "\" 94115 \"" space_field;

  let clean_field = escape_csv_field "94115" in
  check_equal_str "T5.CSV.7: Clean field remains unquoted"
    "94115" clean_field;

  let row_cells = row_of_raw_lead dummy_lead in
  check_equal_int "T5.CSV.8: row_of_raw_lead produces exactly 10 schema columns"
    10 (List.length row_cells);

  check_equal_str "T5.CSV.9: CSV header string has exact 10 column names"
    "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status\n"
    header_string;

  Printf.printf "  Section 5 complete.\n\n";

  Printf.printf "[T5.6] Invariants & Scorer: Mathematical Domain & Proof Integrity...\n";

  let roofs = [Victorian; Flat; Mansard; Gable; Hip; Metal; Unknown; Other "Special"] in
  let props = [SingleFamily; MultiUnit2To4; MultiUnit5Plus; Commercial; MixedUse; Condo; Unknown; Other "Special"] in
  let valid_inv1 = ref 0 in
  List.iter (fun r ->
    List.iter (fun p ->
      match check_inv1_physical r p with
      | Satisfied _ -> incr valid_inv1
      | Violated _ -> ()
    ) props
  ) roofs;
  check_equal_int "T5.INV.1: Exactly 6 valid pairs out of 64 satisfy INV-1" 6 !valid_inv1;

  check_assert "T5.INV.2: INV-2 satisfied when roof age is 15.0 years"
    (match check_inv2_temporal (Some 15.0) None with Satisfied _ -> true | Violated _ -> false);

  check_assert "T5.INV.3: INV-2 violated when roof age is 14.99 years"
    (match check_inv2_temporal (Some 14.99) None with Violated _ -> true | Satisfied _ -> false);

  check_assert "T5.INV.4: INV-2 satisfied when structure age >= 30 without documented roof age"
    (match check_inv2_temporal ~current_year:2026 None (Some 1996) with Satisfied _ -> true | Violated _ -> false);

  check_assert "T5.INV.5: INV-2 violated when structure age < 30 without documented roof age"
    (match check_inv2_temporal ~current_year:2026 None (Some 1997) with Violated _ -> true | Satisfied _ -> false);

  check_assert "T5.INV.6: INV-2 violated when structural fallback age is 25 years"
    (match check_inv2_temporal ~current_year:2026 (Some 25.0) (Some 2001) with Violated _ -> true | Satisfied _ -> false);

  check_assert "T5.INV.7: INV-2 violated when both roof age and year built are None"
    (match check_inv2_temporal None None with Violated _ -> true | Satisfied _ -> false);

  check_assert "T5.INV.8: INV-3 violated when is_hoa is true"
    (match check_inv3_economic (Some 5000000.0) true false with Violated _ -> true | Satisfied _ -> false);

  check_assert "T5.INV.9: INV-3 violated when is_rental is true"
    (match check_inv3_economic (Some 5000000.0) false true with Violated _ -> true | Satisfied _ -> false);

  check_assert "T5.INV.10: INV-3 satisfied when value is $1,000,000.00"
    (match check_inv3_economic (Some 1000000.0) false false with Satisfied _ -> true | Violated _ -> false);

  check_assert "T5.INV.11: INV-3 violated when value is $999,999.99"
    (match check_inv3_economic (Some 999999.99) false false with Violated _ -> true | Satisfied _ -> false);

  let recent_reroof_permit : permit_record = {
    permit_number = "BP2021001";
    date_issued = Some "2021-05-10";
    date_filed = None;
    status = Some "ISSUED";
    description = "Full reroof and shingle replacement";
    permit_type = Some "Reroof";
    cost = Some 45000.0;
    is_roof_replacement = true;
    year = Some 2021;
  } in
  check_assert "T5.INV.12: INV-4 violated when roof replacement permit occurred 5 years ago"
    (match check_inv4_permits ~current_year:2026 [recent_reroof_permit] with Violated _ -> true | Satisfied _ -> false);

  let old_reroof_permit : permit_record = {
    permit_number = "BP2005001";
    date_issued = Some "2005-06-15";
    date_filed = None;
    status = Some "COMPLETED";
    description = "Complete tear-off and built-up roof";
    permit_type = Some "Reroof";
    cost = Some 35000.0;
    is_roof_replacement = true;
    year = Some 2005;
  } in
  check_assert "T5.INV.13: INV-4 satisfied when roof replacement permit is 21 years old"
    (match check_inv4_permits ~current_year:2026 [old_reroof_permit] with Satisfied _ -> true | Violated _ -> false);

  let non_roof_permit : permit_record = {
    permit_number = "BP2024099";
    date_issued = Some "2024-02-20";
    date_filed = None;
    status = Some "ISSUED";
    description = "Kitchen remodel and electrical upgrade";
    permit_type = Some "Alterations";
    cost = Some 85000.0;
    is_roof_replacement = false;
    year = Some 2024;
  } in
  check_assert "T5.INV.14: INV-4 satisfied for recent non-roof remodel permits"
    (match check_inv4_permits ~current_year:2026 [non_roof_permit] with Satisfied _ -> true | Violated _ -> false);

  let score_min = calculate_score { dummy_lead with estimated_value = Some 100000.0; roof_age_years = Some 0.0; roof_type = Other "X"; property_type = Commercial } in
  check_assert "T5.SCORE.1: Minimum possible score is strictly bounded in [0.0, 100.0]"
    (score_min.total_score >= 0.0 && score_min.total_score <= 100.0);

  let score_max = calculate_score { dummy_lead with estimated_value = Some 10000000.0; roof_age_years = Some 40.0; roof_type = Victorian; property_type = SingleFamily } in
  check_assert "T5.SCORE.2: Maximum possible score is 100.0"
    (score_max.total_score = 100.0);

  let verified_ok = verify_lead dummy_lead in
  check_assert "T5.PROOF.1: High-ticket eligible lead receives Qualified verdict"
    (match verified_ok.verdict with Qualified _ -> true | _ -> false);

  check_assert "T5.PROOF.2: Proof ID begins with 'PROOF-OCAML-'"
    (String.starts_with ~prefix:"PROOF-OCAML-" verified_ok.proof_id);

  check_assert "T5.PROOF.3: SHA-256 proof matches 64 hex characters"
    (String.length verified_ok.sha256_proof = 64);

  let tampered_lead = { dummy_lead with address = "2224 Pacific Ave" } in
  let verified_tampered = verify_lead tampered_lead in
  check_assert "T5.PROOF.4: Tampering with single character in address invalidates SHA-256 proof"
    (verified_ok.sha256_proof <> verified_tampered.sha256_proof);

  Printf.printf "  Section 6 complete.\n\n";

  Printf.printf "======================================================================\n";
  Printf.printf "=== TIER 5 HARNESS RESULTS: Passed: %d, Failed: %d, Total: %d ===\n" !pass_count !fail_count !test_count;
  Printf.printf "======================================================================\n\n";

  if !fail_count > 0 then exit 1 else exit 0
