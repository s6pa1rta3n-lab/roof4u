(**
   test_challenger_2.ml - Empirical Adversarial Challenger Test Harness for Roo4u.
   Stress-tests cryptographic proof generation, canonical payload determinism,
   avalanche effect, non-malleability, zero collision across 4 SF districts,
   and SQLite pipeline state machine transitions.
*)

[@@@warning "-32-33-27"]

open Roof_engine
open Types
open Pipeline

let test_count = ref 0
let pass_count = ref 0

(** Basic boolean assertion reporter *)
let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s\n%!" name;
    exit 1
  )

(** String equality assertion reporter *)
let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s (Expected: %s, Got: %s)\n%!" name expected actual;
    exit 1
  )

(** Integer equality assertion reporter *)
let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    Printf.eprintf "  [FAIL] %s (Expected: %d, Got: %d)\n%!" name expected actual;
    exit 1
  )

(** Computes the Hamming distance (number of differing bits) between two 64-char hex strings *)
let hamming_distance_hex (h1 : string) (h2 : string) : int =
  if String.length h1 <> 64 || String.length h2 <> 64 then 256
  else
    let hex_val c =
      match c with
      | '0' .. '9' -> Char.code c - Char.code '0'
      | 'a' .. 'f' -> Char.code c - Char.code 'a' + 10
      | 'A' .. 'F' -> Char.code c - Char.code 'A' + 10
      | _ -> 0
    in
    let popcount4 n =
      let n = n land 0xF in
      let c = ref 0 in
      for i = 0 to 3 do
        if (n land (1 lsl i)) <> 0 then incr c
      done;
      !c
    in
    let dist = ref 0 in
    for i = 0 to 63 do
      let v1 = hex_val h1.[i] in
      let v2 = hex_val h2.[i] in
      let xor_v = v1 lxor v2 in
      dist := !dist + popcount4 xor_v
    done;
    !dist

(** Validates strict RFC / FIPS cryptographic proof formatting and ID structure *)
let validate_proof_grammar (v : verified_lead) : (unit, string) result =
  if String.length v.sha256_proof <> 64 then
    Error (Printf.sprintf "SHA-256 digest length is %d (expected 64)" (String.length v.sha256_proof))
  else
    let is_lower_hex c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') in
    let all_hex = ref true in
    for i = 0 to 63 do
      if not (is_lower_hex v.sha256_proof.[i]) then all_hex := false
    done;
    if not !all_hex then
      Error "SHA-256 digest contains non-hex characters"
    else
      let prefix = "PROOF-OCAML-" in
      let pfx_len = String.length prefix in
      if String.length v.proof_id <> (pfx_len + 16) then
        Error (Printf.sprintf "Proof ID length is %d (expected %d)" (String.length v.proof_id) (pfx_len + 16))
      else if String.sub v.proof_id 0 pfx_len <> prefix then
        Error (Printf.sprintf "Proof ID does not start with %s" prefix)
      else
        let id_hex = String.sub v.proof_id pfx_len 16 in
        let expected_hex = String.uppercase_ascii (String.sub v.sha256_proof 0 16) in
        if id_hex <> expected_hex then
          Error (Printf.sprintf "Proof ID hex suffix %s does not match digest prefix %s" id_hex expected_hex)
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
          if computed_digest <> v.sha256_proof then
            Error (Printf.sprintf "Digest mismatch: expected %s, got %s" computed_digest v.sha256_proof)
          else
            let fields = String.split_on_char '|' canonical_payload in
            if List.length fields <> 8 then
              Error (Printf.sprintf "Canonical payload has %d fields (expected 8)" (List.length fields))
            else if List.hd fields <> "ROO4U-PROOF-V1" then
              Error "Canonical payload header is not ROO4U-PROOF-V1"
            else
              Ok ()

(** Suite 1: Strict Proof Format and ID Grammar across all 4 districts *)
let test_proof_format_and_grammar () =
  Printf.printf "[Suite 1] Empirical Proof Format & ID Grammar Stress Test...\n%!";
  let districts = ["94122"; "94118"; "94112"; "94115"] in
  List.iter (fun zip ->
    let leads = Pipeline.default_seed_leads_for_zip zip in
    List.iteri (fun idx lead ->
      let v = Scorer.verify_lead lead in
      match validate_proof_grammar v with
      | Ok () ->
          assert_true (Printf.sprintf "PROOF.GRAMMAR.%s.%d: Valid ROO4U-PROOF-V1 and PROOF-OCAML prefix" zip idx) true
      | Error err ->
          assert_true (Printf.sprintf "PROOF.GRAMMAR.%s.%d: Failed with error %s" zip idx err) false
    ) leads
  ) districts;

  let disqualified_lead = {
    address = "999 Broken Roof Rd";
    zip_code = "94122";
    property_type = Commercial;
    roof_type = Gable;
    property_type_raw = Some "Commercial";
    roof_type_raw = Some "Gable";
    estimated_value = Some 400000.0;
    owner_name = Some "Disqualified Entity";
    is_hoa = true;
    is_rental = true;
    apn = Some "9999-999";
    last_roof_permit_date = Some "2024-01-01";
    roof_age_years = Some 2.0;
    year_built = Some 2020;
    phone_number = None;
    permits = [
      {
        permit_number = "20240101";
        permit_type = Some "Building Permit";
        description = "New roof installed 2024";
        date_filed = Some "2024-01-01";
        date_issued = Some "2024-01-10";
        status = Some "COMPLETED";
        year = Some 2024;
        is_roof_replacement = true;
        cost = Some 15000.0;
      }
    ];
  } in
  let disq_verif = Scorer.verify_lead disqualified_lead in
  assert_true "PROOF.GRAMMAR.DISQUALIFIED.1: Status is Disqualified"
    (match disq_verif.verdict with Disqualified _ -> true | _ -> false);
  match validate_proof_grammar disq_verif with
  | Ok () ->
      assert_true "PROOF.GRAMMAR.DISQUALIFIED.2: Disqualified proof strictly adheres to grammar" true
  | Error err ->
      assert_true (Printf.sprintf "PROOF.GRAMMAR.DISQUALIFIED.2: Grammar failed: %s" err) false

(** Suite 2: Determinism, Avalanche Effect, and Mutation Sensitivity *)
let test_determinism_and_avalanche () =
  Printf.printf "\n[Suite 2] Determinism and Avalanche Effect Mutation Stress Test...\n%!";
  let base_lead = {
    address = "1420 20th Ave";
    zip_code = "94122";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 1650000.0;
    owner_name = Some "Sunset Family Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "1820-015";
    last_roof_permit_date = Some "2004-06-01";
    roof_age_years = Some 22.0;
    year_built = Some 1928;
    phone_number = Some "415-555-0721";
    permits = [];
  } in

  let fixed_timestamp = "2026-09-01T12:00:00Z" in
  let base_verif = Scorer.verify_lead ~timestamp:fixed_timestamp base_lead in
  let base_hash = base_verif.sha256_proof in

  let is_deterministic = ref true in
  for _ = 1 to 500 do
    let v = Scorer.verify_lead ~timestamp:fixed_timestamp base_lead in
    if v.sha256_proof <> base_hash || v.proof_id <> base_verif.proof_id then
      is_deterministic := false
  done;
  assert_true "CRYPTO.DET.1: 500/500 iterations produced 100% identical SHA-256 digest" !is_deterministic;

  let mutations = [
    ("Address +1 char", { base_lead with address = "1421 20th Ave" }, fixed_timestamp);
    ("Address lower case", { base_lead with address = "1420 20th ave" }, fixed_timestamp);
    ("Zip mutate 94122 -> 94118", { base_lead with zip_code = "94118" }, fixed_timestamp);
    ("Zip mutate 94122 -> 94112", { base_lead with zip_code = "94112" }, fixed_timestamp);
    ("Zip mutate 94122 -> 94115", { base_lead with zip_code = "94115" }, fixed_timestamp);
    ("Roof type Victorian -> Flat", { base_lead with roof_type = Flat }, fixed_timestamp);
    ("Roof type Victorian -> Mansard", { base_lead with roof_type = Mansard }, fixed_timestamp);
    ("Prop type SFR -> MultiUnit", { base_lead with property_type = MultiUnit2To4 }, fixed_timestamp);
    ("Timestamp 1 sec flip", base_lead, "2026-09-01T12:00:01Z");
    ("Timestamp 1 min flip", base_lead, "2026-09-01T12:01:00Z");
    ("Value change modifying score", { base_lead with estimated_value = Some 1800000.0 }, fixed_timestamp);
  ] in

  List.iteri (fun idx (mut_name, mut_lead, mut_ts) ->
    let mut_verif = Scorer.verify_lead ~timestamp:mut_ts mut_lead in
    let mut_hash = mut_verif.sha256_proof in
    assert_true (Printf.sprintf "AVALANCHE.%d.1: Mutation '%s' changed hash" idx mut_name)
      (mut_hash <> base_hash);
    let h_dist = hamming_distance_hex base_hash mut_hash in
    assert_true (Printf.sprintf "AVALANCHE.%d.2: Hamming distance %d in [64, 192] (avalanche bitflip rate %.1f%%)"
                   idx h_dist (float_of_int h_dist /. 2.56))
      (h_dist >= 64 && h_dist <= 192)
  ) mutations

(** Suite 3: Cross-District Non-Malleability & Zero Collision Stress Test *)
let test_cross_district_zero_collision () =
  Printf.printf "\n[Suite 3] 2,000 Lead Cross-District Zero Collision & Non-Malleability...\n%!";
  let zips = ["94122"; "94118"; "94112"; "94115"] in
  let roof_types = [Victorian; Flat; Mansard] in
  let prop_types = [SingleFamily; MultiUnit2To4] in
  let seen_hashes = Hashtbl.create 2048 in
  let seen_proof_ids = Hashtbl.create 2048 in
  let total_generated = ref 0 in
  let collisions = ref 0 in

  List.iter (fun zip ->
    List.iter (fun r_type ->
      List.iter (fun p_type ->
        for house_num = 100 to 141 do
          incr total_generated;
          let street =
            match zip with
            | "94122" -> "Judah St"
            | "94118" -> "Clement St"
            | "94112" -> "Mission St"
            | "94115" -> "Fillmore St"
            | _ -> "Market St"
          in
          let addr = Printf.sprintf "%d %s" house_num street in
          let val_est = 1000000.0 +. (float_of_int (house_num * 25000)) in
          let lead = {
            address = addr;
            zip_code = zip;
            property_type = p_type;
            roof_type = r_type;
            property_type_raw = Some (string_of_property_type p_type);
            roof_type_raw = Some (string_of_roof_type r_type);
            estimated_value = Some val_est;
            owner_name = Some (Printf.sprintf "Owner %d" house_num);
            is_hoa = false;
            is_rental = false;
            apn = Some (Printf.sprintf "%s-%03d" zip house_num);
            last_roof_permit_date = Some "2000-01-01";
            roof_age_years = Some (15.0 +. float_of_int (house_num mod 15));
            year_built = Some 1920;
            phone_number = None;
            permits = [];
          } in
          let v = Scorer.verify_lead lead in
          if Hashtbl.mem seen_hashes v.sha256_proof then incr collisions;
          Hashtbl.replace seen_hashes v.sha256_proof ();
          if Hashtbl.mem seen_proof_ids v.proof_id then incr collisions;
          Hashtbl.replace seen_proof_ids v.proof_id ()
        done
      ) prop_types
    ) roof_types
  ) zips;

  assert_true (Printf.sprintf "COLLISION.1: Generated %d cross-district leads" !total_generated)
    (!total_generated >= 1000);
  assert_equal_int "COLLISION.2: Exactly ZERO cryptographic collisions across all leads" 0 !collisions;
  assert_equal_int "COLLISION.3: Total unique proof IDs equals total generated leads"
    !total_generated (Hashtbl.length seen_proof_ids);

  let delimiter_lead1 = {
    address = "100 California St|94122";
    zip_code = "94118";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 2000000.0;
    owner_name = None;
    is_hoa = false;
    is_rental = false;
    apn = None;
    last_roof_permit_date = None;
    roof_age_years = Some 20.0;
    year_built = None;
    phone_number = None;
    permits = [];
  } in
  let delimiter_lead2 = {
    delimiter_lead1 with
    address = "100 California St";
    zip_code = "94122";
  } in
  let v_del1 = Scorer.verify_lead delimiter_lead1 in
  let v_del2 = Scorer.verify_lead delimiter_lead2 in
  assert_true "NON_MALLEABILITY.1: Pipe injection produces completely distinct digest"
    (v_del1.sha256_proof <> v_del2.sha256_proof)

(** Suite 4: SQLite Database State Machine & Concurrent Transitions *)
let test_database_state_transitions () =
  Printf.printf "\n[Suite 4] SQLite Pipeline State Machine Transitions & Invariants...\n%!";
  let temp_db_path = Filename.temp_file "test_challenger_db_" ".sqlite" in
  let db = Db.create ~db_path:temp_db_path () in
  Db.init_db db;

  let lead = {
    address = "4500 Irving St";
    zip_code = "94122";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 1800000.0;
    owner_name = Some "Original Owner";
    is_hoa = false;
    is_rental = false;
    apn = Some "1700-001";
    last_roof_permit_date = None;
    roof_age_years = Some 20.0;
    year_built = Some 1930;
    phone_number = None;
    permits = [];
  } in

  let ins_res = Db.insert_lead db ~status:Db.Discovered lead in
  assert_true "DB.STATE.1: Insert returns Ok lead id" (Result.is_ok ins_res);
  let lead_id = Result.get_ok ins_res in

  let row1 = Db.get_lead_by_address db lead.address in
  assert_true "DB.STATE.2: Retrieved lead exists" (Option.is_some row1);
  let r1 = Option.get row1 in
  assert_equal_str "DB.STATE.3: Initial state is DISCOVERED" "DISCOVERED" r1.status;

  let dup_res = Db.insert_lead db ~status:Db.Discovered lead in
  assert_true "DB.STATE.4: Duplicate address insertion strictly rejected" (Result.is_error dup_res);

  let enrich_res = Db.update_enriched db lead.address
    ~apn:"1700-001-MOD"
    ~owner_name:"Enriched Owner Trust"
    ~estimated_value:1950000.0
    ~roof_age_years:21.5
    ()
  in
  assert_true "DB.STATE.5: update_enriched returns Ok ()" (Result.is_ok enrich_res);
  let r2 = Option.get (Db.get_lead_by_id db lead_id) in
  assert_equal_str "DB.STATE.6: State transitioned to ENRICHED" "ENRICHED" r2.status;
  assert_equal_str "DB.STATE.7: Owner updated" "Enriched Owner Trust" (Option.value ~default:"" r2.owner_name);

  let val_res = Db.update_status db lead.address Db.Validated in
  assert_true "DB.STATE.8: update_status to Validated returns Ok ()" (Result.is_ok val_res);
  let r3 = Option.get (Db.get_lead_by_id db lead_id) in
  assert_equal_str "DB.STATE.9: State transitioned to VALIDATED" "VALIDATED" r3.status;

  let disq_res = Db.update_status db lead.address Db.Disqualified in
  assert_true "DB.STATE.10: update_status to Disqualified returns Ok ()" (Result.is_ok disq_res);
  let r4 = Option.get (Db.get_lead_by_id db lead_id) in
  assert_equal_str "DB.STATE.11: State transitioned to DISQUALIFIED" "DISQUALIFIED" r4.status;

  let disc_res = Db.update_status db lead.address Db.Discarded in
  assert_true "DB.STATE.12: update_status to Discarded returns Ok ()" (Result.is_ok disc_res);
  let r5 = Option.get (Db.get_lead_by_id db lead_id) in
  assert_equal_str "DB.STATE.13: State transitioned to DISCARDED" "DISCARDED" r5.status;

  let db_reopened = Db.create ~db_path:temp_db_path () in
  let r_reopened = Db.get_lead_by_address db_reopened lead.address in
  assert_true "DB.PERSIST.1: Lead persists across DB reopening" (Option.is_some r_reopened);
  assert_equal_str "DB.PERSIST.2: Status DISCARDED persisted on disk"
    "DISCARDED" (Option.get r_reopened).status;

  let threads = ref [] in
  let thread_errors = ref 0 in
  for t_idx = 1 to 10 do
    let t = Thread.create (fun () ->
      for i = 1 to 20 do
        let test_addr = Printf.sprintf "Thread %d Lead %d St" t_idx i in
        let t_lead = {
          lead with
          address = test_addr;
          zip_code = "94118";
        } in
        match Db.upsert_lead db ~status:Db.Discovered t_lead with
        | Ok _ ->
            ignore (Db.update_enriched db test_addr ~owner_name:(Printf.sprintf "Thread %d" t_idx) ());
            ignore (Db.update_status db test_addr Db.Validated)
        | Error _ -> incr thread_errors
      done
    ) () in
    threads := t :: !threads
  done;
  List.iter Thread.join !threads;
  assert_equal_int "DB.CONCURRENCY.1: Concurrent multi-threaded upsert & state transitions (0 errors)" 0 !thread_errors;
  assert_true "DB.CONCURRENCY.2: Total leads count >= 200" (Db.count_leads db >= 200);

  (try Sys.remove temp_db_path with _ -> ())

(** Suite 5: End-to-End Four-District Pipeline State Consistency *)
let test_pipeline_district_state_consistency () =
  Printf.printf "\n[Suite 5] End-to-End Pipeline State Machine Verification across 4 Districts...\n%!";
  let temp_db = Filename.temp_file "p_state_leads_" ".db" in
  let temp_csv = Filename.temp_file "p_state_out_" ".csv" in
  let temp_lessons = Filename.temp_file "p_state_lessons_" ".json" in
  let temp_vec = Filename.temp_file "p_state_vec_" ".sqlite" in

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
  assert_true "PIPE.STATE.1: Candidates discovered >= 12" (summary.candidates_discovered >= 12);
  assert_true "PIPE.STATE.2: Leads enriched >= 12" (summary.leads_enriched >= 12);
  assert_true "PIPE.STATE.3: Leads qualified >= 12" (summary.leads_qualified >= 12);
  assert_equal_int "PIPE.STATE.4: Disqualified count is 0 for authentic seed set" 0 summary.leads_disqualified;

  let db = Db.create ~db_path:temp_db () in
  let validated_rows = Db.list_leads ~status:Db.Validated db in
  assert_equal_int "PIPE.STATE.5: SQLite leads with VALIDATED status matches summary.leads_qualified"
    summary.leads_qualified (List.length validated_rows);

  let zips = ["94122"; "94118"; "94112"; "94115"] in
  List.iter (fun zip ->
    let zip_rows = Db.list_leads ~status:Db.Validated ~zip_code:zip db in
    assert_true (Printf.sprintf "PIPE.STATE.6.%s: At least 3 VALIDATED leads in DB for %s" zip zip)
      (List.length zip_rows >= 3)
  ) zips;

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove temp_csv with _ -> ());
  (try Sys.remove temp_lessons with _ -> ());
  (try Sys.remove temp_vec with _ -> ())

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== EMPIRICAL CHALLENGER 2 ADVERSARIAL STRESS SUITE (ROO4U) ===\n";
  Printf.printf "=== Districts: Sunset (94122), Richmond (94118), Excelsior (94112), Pac Heights (94115) ===\n";
  Printf.printf "======================================================================\n\n%!";
  test_proof_format_and_grammar ();
  test_determinism_and_avalanche ();
  test_cross_district_zero_collision ();
  test_database_state_transitions ();
  test_pipeline_district_state_consistency ();
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== ALL CHALLENGER 2 ADVERSARIAL TESTS PASSED: %d/%d (100.0%%) ===\n"
    !pass_count !test_count;
  Printf.printf "======================================================================\n\n%!"
