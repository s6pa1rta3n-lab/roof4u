(**
   test_district_pipeline.ml - Dedicated automated test suite for the four target
   San Francisco neighborhoods: Sunset (94122), Richmond (94118), Excelsior (94112),
   and Pacific Heights (94115).
*)

[@@@warning "-32-33"]

open Roof_engine
open Types
open Pipeline

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

let verify_lead_cryptographic_integrity (v : verified_lead) : bool =
  if String.length v.sha256_proof <> 64 then false
  else
    let expected_proof_id = "PROOF-OCAML-" ^ (String.sub v.sha256_proof 0 16 |> String.uppercase_ascii) in
    if v.proof_id <> expected_proof_id then false
    else
      let status_str =
        match v.verdict with
        | Qualified _ -> "QUALIFIED"
        | Disqualified _ -> "DISQUALIFIED"
      in
      let score_val =
        match v.verdict with
        | Qualified { score; _ } -> score.total_score
        | Disqualified { partial_score; _ } -> partial_score
      in
      let canonical_payload =
        Printf.sprintf "ROO4U-PROOF-V1|%s|%s|%s|%s|%s|%.2f|%s"
          v.lead.address
          v.lead.zip_code
          (string_of_property_type v.lead.property_type)
          (string_of_roof_type v.lead.roof_type)
          status_str
          score_val
          v.timestamp
      in
      let computed_digest = Crypto.sha256_string canonical_payload in
      computed_digest = v.sha256_proof

let test_district_seed_properties () =
  Printf.printf "[Suite 1] District Seed Properties Verification (INV1-4 & Scoring)...\n%!";
  let districts = [
    ("Sunset", "94122", 3, 60.0);
    ("Richmond", "94118", 3, 60.0);
    ("Excelsior", "94112", 3, 60.0);
    ("Pacific Heights", "94115", 3, 60.0);
  ] in
  List.iter (fun (dist_name, zip, expected_len, min_expected_score) ->
    let leads = Pipeline.default_seed_leads_for_zip zip in
    assert_equal_int (Printf.sprintf "DIST.SEED.%s.1: Exactly %d seed leads provided" dist_name expected_len)
      expected_len (List.length leads);
    List.iteri (fun idx lead ->
      let verif = Scorer.verify_lead lead in
      assert_true (Printf.sprintf "DIST.SEED.%s.%d.2: Qualified under INV1-4" dist_name idx)
        (match verif.verdict with Qualified _ -> true | Disqualified _ -> false);
      let score =
        match verif.verdict with
        | Qualified { score; _ } -> score.total_score
        | Disqualified { partial_score; _ } -> partial_score
      in
      assert_true (Printf.sprintf "DIST.SEED.%s.%d.3: Score >= %.1f (got %.2f)" dist_name idx min_expected_score score)
        (score >= min_expected_score);
      assert_true (Printf.sprintf "DIST.SEED.%s.%d.4: Cryptographic proof integrity verified" dist_name idx)
        (verify_lead_cryptographic_integrity verif)
    ) leads
  ) districts

let test_district_microservices_acquisition () =
  Printf.printf "\n[Suite 2] Microservices Public Records Lead Acquisition...\n%!";
  let districts = ["Sunset"; "Richmond"; "Excelsior"; "Pacific Heights"] in
  List.iter (fun dist_name ->
    let acq_res = Public_records_orchestrator.acquire_neighborhood_public_records ~neighborhood:dist_name ~limit:3 () in
    match acq_res with
    | Ok verified_list ->
        assert_equal_int (Printf.sprintf "DIST.MICRO.%s.1: Acquired 3 leads via orchestrator" dist_name)
          3 (List.length verified_list);
        List.iteri (fun idx v ->
          assert_true (Printf.sprintf "DIST.MICRO.%s.%d.2: Lead passes cryptographic verification" dist_name idx)
            (verify_lead_cryptographic_integrity v);
          match v.verdict with
          | Qualified { score; invariants_passed; _ } ->
              assert_true (Printf.sprintf "DIST.MICRO.%s.%d.3: Score >= 60.0 (got %.2f)" dist_name idx score.total_score)
                (score.total_score >= 60.0);
              assert_equal_int (Printf.sprintf "DIST.MICRO.%s.%d.4: Passed 4 invariants" dist_name idx)
                4 (List.length invariants_passed)
          | Disqualified _ ->
              assert_true (Printf.sprintf "DIST.MICRO.%s.%d.3: Unexpected disqualification" dist_name idx) false
        ) verified_list
    | Error err ->
        assert_true (Printf.sprintf "DIST.MICRO.%s.1: Acquisition failed: %s" dist_name err) false
  ) districts

let test_district_e2e_pipeline_execution () =
  Printf.printf "\n[Suite 3] Four-District End-to-End Pipeline & CSV Export...\n%!";
  let temp_db = Filename.temp_file "dist_leads_" ".db" in
  let temp_csv = Filename.temp_file "dist_out_" ".csv" in
  let temp_lessons = Filename.temp_file "dist_lessons_" ".json" in
  let temp_vec = Filename.temp_file "dist_vec_" ".sqlite" in

  let pipe_cfg = {
    target_zips = ["94122"; "94118"; "94112"; "94115"];
    limit_per_zip = 10;
    csv_path = temp_csv;
    db_path = temp_db;
    lessons_path = temp_lessons;
    vector_db_path = temp_vec;
    enable_learning = true;
    enable_telemetry = true;
    min_score = 60.0;
    current_year = 2026;
  } in

  let summary = Pipeline.run_pipeline ~config:pipe_cfg () in

  assert_true "DIST.PIPE.1: Discovered candidate leads across all 4 districts"
    (summary.candidates_discovered >= 12);
  assert_true "DIST.PIPE.2: Enriched all candidate properties"
    (summary.leads_enriched >= 12);
  assert_true "DIST.PIPE.3: Formally qualified leads with SHA-256 proofs"
    (summary.leads_qualified >= 12);
  assert_equal_int "DIST.PIPE.4: Zero invariant violations on authentic seed properties"
    0 summary.leads_disqualified;
  assert_true "DIST.PIPE.5: Exported qualified leads to CSV"
    (summary.leads_exported >= 12);

  assert_true "DIST.PIPE.6: Output CSV exists on disk" (Sys.file_exists temp_csv);

  let ic = open_in temp_csv in
  let header = input_line ic in
  let expected_header = "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status" in
  assert_equal_str "DIST.PIPE.7: RFC 4180 CSV header schema verified" expected_header header;

  let rec read_rows acc =
    try
      let line = input_line ic in
      read_rows (line :: acc)
    with End_of_file ->
      close_in ic;
      List.rev acc
  in
  let rows = read_rows [] in
  assert_equal_int "DIST.PIPE.8: CSV row count matches exported lead count"
    summary.leads_exported (List.length rows);

  let zip_counts = ref [] in
  List.iter (fun row ->
    let parts = String.split_on_char ',' row in
    let zip = List.nth parts 1 in
    let prev = Option.value ~default:0 (List.assoc_opt zip !zip_counts) in
    zip_counts := (zip, prev + 1) :: (List.remove_assoc zip !zip_counts)
  ) rows;

  assert_true "DIST.PIPE.9: CSV contains Sunset leads (94122)"
    (Option.value ~default:0 (List.assoc_opt "94122" !zip_counts) >= 3);
  assert_true "DIST.PIPE.10: CSV contains Richmond leads (94118)"
    (Option.value ~default:0 (List.assoc_opt "94118" !zip_counts) >= 3);
  assert_true "DIST.PIPE.11: CSV contains Excelsior leads (94112)"
    (Option.value ~default:0 (List.assoc_opt "94112" !zip_counts) >= 3);
  assert_true "DIST.PIPE.12: CSV contains Pacific Heights leads (94115)"
    (Option.value ~default:0 (List.assoc_opt "94115" !zip_counts) >= 3);

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove temp_csv with _ -> ());
  (try Sys.remove temp_lessons with _ -> ());
  (try Sys.remove temp_vec with _ -> ())

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Roo4u Four-District Automated Pipeline Verification Suite ===\n";
  Printf.printf "=== Target Districts: Sunset, Richmond, Excelsior, Pacific Heights ===\n";
  Printf.printf "======================================================================\n\n%!";
  test_district_seed_properties ();
  test_district_microservices_acquisition ();
  test_district_e2e_pipeline_execution ();
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== ALL 4-DISTRICT PIPELINE TESTS PASSED: %d/%d (100.0%%) ===\n"
    !pass_count !test_count;
  Printf.printf "======================================================================\n\n%!"
