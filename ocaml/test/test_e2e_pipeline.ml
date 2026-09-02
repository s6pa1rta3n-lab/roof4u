(**
   test_e2e_pipeline.ml - Comprehensive Tier 4 Real-World Application Scenarios.
   Executes 5 complete end-to-end multi-agent pipelines with full qualification,
   cryptographic proofs, dual-memory learning, SQLite persistence, and RFC 4180 CSV export.
*)

[@@@warning "-32"]

open Roof_engine
open Types
open Scorer
open Csv_exporter
open Pipeline

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

let () =
  Printf.printf "\n=================================================================\n";
  Printf.printf "=== [TIER 4] Real-World End-to-End Application Pipeline Tests ===\n";
  Printf.printf "=================================================================\n\n";

  (* -------------------------------------------------------------------------- *)
  (* SCENARIO 1: Full Pacific Heights (94115) Victorian Acquisition             *)
  (* -------------------------------------------------------------------------- *)
  Printf.printf "--- Scenario 1: Pacific Heights Victorian Acquisition (94115) ---\n";
  let pac_heights_permit = {
    permit_number = "19980512";
    permit_type = Some "Building Permit";
    date_filed = Some "1998-05-12";
    date_issued = Some "1998-06-01";
    status = Some "ISSUED";
    year = Some 1998;
    description = "Complete roof replacement Victorian shingle";
    is_roof_replacement = true;
    cost = Some 35000.0;
  } in
  let pac_heights_lead = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 4350000.0;
    apn = Some "0576-010";
    owner_name = Some "Pacific Heights Heritage Trust";
    is_hoa = false;
    is_rental = false;
    year_built = Some 1895;
    roof_age_years = Some 28.0;
    last_roof_permit_date = Some "1998-06-01";
    phone_number = Some "415-555-0142";
    permits = [pac_heights_permit];
  } in
  let verif_s1 = verify_lead pac_heights_lead in
  assert_true "T4.S1.1: Lead is QUALIFIED under INV1-4"
    (match verif_s1.verdict with Qualified _ -> true | _ -> false);

  let score_s1 = match verif_s1.verdict with Qualified { score; _ } -> score.total_score | _ -> 0.0 in
  assert_true "T4.S1.2: Actionability score exceeds 90.0 points" (score_s1 > 90.0);

  let json_s1 = verified_lead_to_json_string ~pretty:true verif_s1 in
  assert_true "T4.S1.3: Exportable JSON proof generated" (String.length json_s1 > 100);

  let proof_sha = verif_s1.sha256_proof in
  assert_true "T4.S1.4: Cryptographic proof is 64 hex characters" (String.length proof_sha = 64);

  let csv_row_s1 = row_of_verified_lead verif_s1 in
  assert_true "T4.S1.5: CSV row has exactly 10 columns" (List.length csv_row_s1 = 10);
  assert_true "T4.S1.6: CSV address matches" (List.hd csv_row_s1 = "2223 Pacific Ave");
  assert_true "T4.S1.7: CSV status is VALIDATED" (List.nth csv_row_s1 9 = "VALIDATED");

  (* -------------------------------------------------------------------------- *)
  (* SCENARIO 2: Marina & Cow Hollow (94123) Flat Roof Multi-Unit               *)
  (* -------------------------------------------------------------------------- *)
  Printf.printf "\n--- Scenario 2: Marina & Cow Hollow Flat Multi-Unit (94123) ---\n";
  let marina_permit = {
    permit_number = "20061104";
    permit_type = Some "Building Permit";
    date_filed = Some "2006-11-04";
    date_issued = Some "2006-11-20";
    status = Some "ISSUED";
    year = Some 2006;
    description = "Built-up tar and gravel roof restoration";
    is_roof_replacement = true;
    cost = Some 28000.0;
  } in
  let marina_lead = {
    address = "1840 Chestnut St";
    zip_code = "94123";
    property_type = MultiUnit2To4;
    roof_type = Flat;
    property_type_raw = Some "2-unit";
    roof_type_raw = Some "Tar and Gravel";
    estimated_value = Some 2750000.0;
    apn = Some "0452-018";
    owner_name = Some "Marina Properties LLC";
    is_hoa = false;
    is_rental = false;
    year_built = Some 1932;
    roof_age_years = Some 20.0;
    last_roof_permit_date = Some "2006-11-20";
    phone_number = None;
    permits = [marina_permit];
  } in
  let verif_s2 = verify_lead marina_lead in
  assert_true "T4.S2.1: Marina Multi-Unit qualifies with Flat roof"
    (match verif_s2.verdict with Qualified _ -> true | _ -> false);

  let score_s2 = match verif_s2.verdict with Qualified { score; _ } -> score.total_score | _ -> 0.0 in
  assert_true "T4.S2.2: Actionability score is within expected range (60.0 - 80.0)"
    (score_s2 >= 60.0 && score_s2 <= 80.0);

  let db_temp = Db.create ~db_path:":memory:" () in
  Db.init_db db_temp;
  assert_true "T4.S2.3: Insert into SQLite returns Ok"
    (match Db.insert_lead db_temp ~status:Db.Discovered marina_lead with Ok _ -> true | _ -> false);
  assert_true "T4.S2.4: Update status to Validated"
    (match Db.update_status db_temp marina_lead.address Db.Validated with Ok () -> true | _ -> false);

  (* -------------------------------------------------------------------------- *)
  (* SCENARIO 3: Self-Healing Closed Loop with Induced Scraping Drift           *)
  (* -------------------------------------------------------------------------- *)
  Printf.printf "\n--- Scenario 3: Self-Healing Closed Loop & Telemetry Drift ---\n";
  let temp_lessons = Filename.temp_file "lessons_" ".json" in
  let temp_vec_db = Filename.temp_file "vector_" ".sqlite" in
  let lesson_store = Lesson_store.create ~file_path:temp_lessons () in
  let vector_store = Vector_store.create ~db_path:temp_vec_db () in

  let event = {
    Telemetry.domain = "sfplanninggis.org";
    url = "https://sfplanninggis.org/pim/?search=2223+Pacific+Ave";
    failure_type = "DOM_DRIFT";
    error_message = "Table selector #property_summary not found";
    selector = Some "#property_summary";
    stack_trace = None;
    dom_snippet = Some "<div class='modern-pim-grid'>...</div>";
    suggested_fix = Some "Update selector to .modern-pim-grid";
    lead_address = Some "2223 Pacific Ave";
    phase = Some "ENRICHMENT";
    attempted_action = Some "Scrape PIM property details";
    exception_class = Some "SelectorNotFoundError";
    retry_count = 1;
    timestamp = "2026-09-01T06:30:00Z";
  } in

  let fp = Telemetry.generate_error_fingerprint event in
  assert_true "T4.S3.1: Deterministic error fingerprint generated" (String.length fp = 16);

  let lesson = Lesson_store.make_lesson
    ~domain:event.domain
    ~failure_type:event.failure_type
    ~error_message:event.error_message
    ~lesson_learned:"SF PIM migrated table layout to CSS grid (.modern-pim-grid)"
    ~recommended_action:"Query .modern-pim-grid table cells"
    ~suggested_selectors:[".modern-pim-grid"; ".property-card"]
    ()
  in
  let saved_lesson = Lesson_store.upsert_lesson lesson_store lesson in
  assert_true "T4.S3.2: Lesson saved to store with ACTIVE status" (saved_lesson.status = "ACTIVE");

  let vec_rec = Vector_store.upsert
    ~domain:event.domain
    ~failure_type:event.failure_type
    vector_store
    saved_lesson.id
    "SF PIM selector error table modern-pim-grid DOM drift"
  in
  assert_true "T4.S3.3: Lesson indexed in vector store (256-D)" (Array.length vec_rec.embedding = 256);

  let results = Vector_store.search ~top_k:1 vector_store (Some "PIM DOM selector drift") in
  assert_true "T4.S3.4: Vector cosine search retrieves relevant lesson" (List.length results = 1);

  (* Self-healing resolution after 5 successes *)
  for _ = 1 to 5 do
    ignore (Lesson_store.increment_success lesson_store saved_lesson.id)
  done;
  let resolved_lesson = Option.get (Lesson_store.get_lesson lesson_store saved_lesson.id) in
  assert_true "T4.S3.5: Self-healing transitions lesson to RESOLVED after 5 successes"
    (resolved_lesson.status = "RESOLVED" && resolved_lesson.resolved);

  (try Sys.remove temp_lessons with _ -> ());
  (try Sys.remove temp_vec_db with _ -> ());

  (* -------------------------------------------------------------------------- *)
  (* SCENARIO 4: Adversarial Fuzzing & Malicious Injection Ingestion            *)
  (* -------------------------------------------------------------------------- *)
  Printf.printf "\n--- Scenario 4: Adversarial Fuzzing & Malicious Ingestion ---\n";
  let malicious_lead = {
    address = "=cmd|' /C calc'!A0, 100 Main St";
    zip_code = "94115' OR 1=1--";
    property_type = Other "<script>alert(1)</script>";
    roof_type = Victorian;
    property_type_raw = Some "<script>alert(1)</script>";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 10000000.0;
    apn = Some "../../etc/passwd";
    owner_name = Some "+@EVIL_DDE_EXPLOIT";
    is_hoa = false;
    is_rental = false;
    year_built = Some 1900;
    roof_age_years = Some 30.0;
    last_roof_permit_date = None;
    phone_number = Some "@1-800-MALWARE";
    permits = [];
  } in
  let verif_s4 = verify_lead malicious_lead in
  assert_true "T4.S4.1: Malicious injection payloads handled safely without crashing"
    (match verif_s4.verdict with Qualified _ | Disqualified _ -> true);

  (* Test formula injection protection on all dangerous prefixes *)
  assert_true "T4.S4.2: Neutralize '=' formula prefix"
    (sanitize_csv_field "=cmd|' /C calc'!A0" = "'=cmd|' /C calc'!A0");
  assert_true "T4.S4.3: Neutralize '+' formula prefix"
    (sanitize_csv_field "+@EVIL_DDE" = "'+@EVIL_DDE");
  assert_true "T4.S4.4: Neutralize '-' formula prefix"
    (sanitize_csv_field "-2+3*cmd" = "'-2+3*cmd");
  assert_true "T4.S4.5: Neutralize '@' formula prefix"
    (sanitize_csv_field "@SUM(A1:A10)" = "'@SUM(A1:A10)");
  assert_true "T4.S4.6: Neutralize '\\t' tab prefix"
    (sanitize_csv_field "\t=1+1" = "'\t=1+1");
  assert_true "T4.S4.7: Neutralize '\\r' carriage return prefix"
    (sanitize_csv_field "\r=cmd" = "'\r=cmd");

  let sanitized_row = row_of_raw_lead malicious_lead in
  assert_true "T4.S4.8: Sanitized CSV row contains single quote prepend for address"
    (String.starts_with ~prefix:"\"'=cmd|" (List.hd sanitized_row) ||
     String.starts_with ~prefix:"'=cmd|" (List.hd sanitized_row));
  assert_true "T4.S4.9: Sanitized CSV row contains single quote prepend for owner name"
    (String.starts_with ~prefix:"\"'+@EVIL" (List.nth sanitized_row 5) ||
     String.starts_with ~prefix:"'+@EVIL" (List.nth sanitized_row 5));

  (* -------------------------------------------------------------------------- *)
  (* SCENARIO 5: Complete Ingestion to CSV Parity Verification across 4 SF Zips *)
  (* -------------------------------------------------------------------------- *)
  Printf.printf "\n--- Scenario 5: Complete Ingestion to CSV Parity Verification ---\n";
  let temp_e2e_db = Filename.temp_file "e2e_leads_" ".db" in
  let temp_e2e_csv = Filename.temp_file "e2e_validated_" ".csv" in
  let temp_e2e_lessons = Filename.temp_file "e2e_lessons_" ".json" in
  let temp_e2e_vec = Filename.temp_file "e2e_vector_" ".sqlite" in

  let cfg = {
    target_zips = ["94122"; "94118"; "94112"; "94115"];
    limit_per_zip = 5;
    db_path = temp_e2e_db;
    csv_path = temp_e2e_csv;
    lessons_path = temp_e2e_lessons;
    vector_db_path = temp_e2e_vec;
    enable_learning = true;
    enable_telemetry = true;
    min_score = 60.0;
    current_year = 2026;
  } in

  let summary = Pipeline.run_pipeline ~config:cfg () in

  assert_true "T4.S5.1: Pipeline discovered candidates across 4 SF corridors"
    (summary.candidates_discovered >= 12);
  assert_true "T4.S5.2: Pipeline enriched candidate leads"
    (summary.leads_enriched >= 12);
  assert_true "T4.S5.3: Pipeline qualified high-value leads (INV1-4)"
    (summary.leads_qualified >= 8);
  assert_true "T4.S5.4: Pipeline exported qualified leads to CSV"
    (summary.leads_exported >= 8);

  assert_true "T4.S5.5: Output CSV file exists on disk" (Sys.file_exists temp_e2e_csv);

  let ic = open_in temp_e2e_csv in
  let header_line = input_line ic in
  let expected_header = "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status" in
  assert_true "T4.S5.6: Exact 10-column header matches RFC 4180 schema" (header_line = expected_header);

  let rec count_lines acc =
    try
      let _ = input_line ic in
      count_lines (acc + 1)
    with End_of_file ->
      close_in ic;
      acc
  in
  let data_row_count = count_lines 0 in
  assert_true "T4.S5.7: CSV row count equals exported lead count"
    (data_row_count = summary.leads_exported);

  (try Sys.remove temp_e2e_db with _ -> ());
  (try Sys.remove temp_e2e_csv with _ -> ());
  (try Sys.remove temp_e2e_lessons with _ -> ());
  (try Sys.remove temp_e2e_vec with _ -> ());

  (* -------------------------------------------------------------------------- *)
  (* SCENARIO 6: Four Target Neighborhoods Cryptographic Proof Verification    *)
  (* -------------------------------------------------------------------------- *)
  Printf.printf "\n--- Scenario 6: Four Target Neighborhoods Cryptographic Proofs ---\n";
  let sunset_lead = List.hd (Pipeline.default_seed_leads_for_zip "94122") in
  let richmond_lead = List.hd (Pipeline.default_seed_leads_for_zip "94118") in
  let excelsior_lead = List.hd (Pipeline.default_seed_leads_for_zip "94112") in
  let pac_heights_lead_s6 = List.hd (Pipeline.default_seed_leads_for_zip "94115") in

  let verify_and_check_district dist_name (lead : Types.raw_lead) expected_min_score =
    let verif = Scorer.verify_lead lead in
    assert_true (Printf.sprintf "T4.S6.%s.1: %s property qualifies under INV1-4" dist_name dist_name)
      (match verif.verdict with Qualified _ -> true | Disqualified _ -> false);
    let score =
      match verif.verdict with
      | Qualified { score; _ } -> score.total_score
      | Disqualified { partial_score; _ } -> partial_score
    in
    assert_true (Printf.sprintf "T4.S6.%s.2: %s score exceeds %.1f (got %.2f)" dist_name dist_name expected_min_score score)
      (score >= expected_min_score);
    assert_true (Printf.sprintf "T4.S6.%s.3: %s SHA-256 proof is 64 hex characters" dist_name dist_name)
      (String.length verif.sha256_proof = 64);
    let expected_pid = "PROOF-OCAML-" ^ (String.sub verif.sha256_proof 0 16 |> String.uppercase_ascii) in
    assert_true (Printf.sprintf "T4.S6.%s.4: %s proof ID matches prefix format" dist_name dist_name)
      (verif.proof_id = expected_pid);
    let canonical =
      Printf.sprintf "ROO4U-PROOF-V1|%s|%s|%s|%s|%s|%.2f|%s"
        lead.address
        lead.zip_code
        (string_of_property_type lead.property_type)
        (string_of_roof_type lead.roof_type)
        "QUALIFIED"
        score
        verif.timestamp
    in
    let recomputed = Crypto.sha256_string canonical in
    assert_true (Printf.sprintf "T4.S6.%s.5: %s proof matches canonical SHA-256 hash" dist_name dist_name)
      (verif.sha256_proof = recomputed)
  in

  verify_and_check_district "Sunset" sunset_lead 70.0;
  verify_and_check_district "Richmond" richmond_lead 85.0;
  verify_and_check_district "Excelsior" excelsior_lead 70.0;
  verify_and_check_district "Pacific Heights" pac_heights_lead_s6 90.0;

  Printf.printf "\n=================================================================\n";
  Printf.printf "=== All Tier 4 Real-World Application Scenarios Completed: %d/%d ===\n"
    !pass_count !test_count;
  Printf.printf "=================================================================\n\n"
