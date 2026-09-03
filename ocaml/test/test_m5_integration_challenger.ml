(**
   test_m5_integration_challenger.ml - Final Milestone 5 Integration & Benchmark Challenger Suite.
   Adversarially validates:
     1. The 8 real-world benchmark properties (5 Qualified with score >= 70.0 & SHA-256 proofs; 3 Negative controls with exact invariant failure codes).
     2. Live CLI binary execution (bin/main.exe) across all target SF corridors (Pacific Heights, Marina, Presidio Heights, Seacliff, Richmond, Sunset).
     3. Strict RFC 4180 CSV lead export verification (exact 10 columns, valid phone numbers, owner names, roof ages >= 15.0 yrs, non-HOA/non-rental).
     4. SQLite state machine persistence (WAL journal mode, unique address index, correct lead state transitions).
     5. Boundary invariants and formula injection defenses.
*)

open Roof_engine
open Types

let passed_count = ref 0
let failed_count = ref 0

(** [assert_true label cond] records a passed assertion if cond is true, otherwise increments failed count and prints failure. *)
let assert_true (label : string) (cond : bool) =
  if cond then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s\n%!" label
  )

(** [assert_equal_int label expected actual] asserts equality between two integer values. *)
let assert_equal_int (label : string) (expected : int) (actual : int) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s (expected %d, got %d)\n%!" label expected actual
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected %d, got %d)\n%!" label expected actual
  )

(** [assert_equal_str label expected actual] asserts equality between two string values. *)
let assert_equal_str (label : string) (expected : string) (actual : string) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected %S, got %S)\n%!" label expected actual
  )

(** [assert_contains label needle haystack] asserts that needle is a substring of haystack. *)
let assert_contains (label : string) (needle : string) (haystack : string) =
  let len_n = String.length needle in
  let len_h = String.length haystack in
  let rec search i =
    if i + len_n > len_h then false
    else if String.sub haystack i len_n = needle then true
    else search (i + 1)
  in
  if search 0 then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (needle %S not found)\n%!" label needle
  )

(** [make_benchmark_permit ~num ~desc ~issued ~status ~cost ~is_rep] constructs a permit_record for benchmark testing. *)
let make_benchmark_permit ~num ~desc ~issued ~status ~cost ~is_rep : permit_record =
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

(** [resolve_main_exe ()] locates the compiled binary path for CLI invocation. *)
let resolve_main_exe () : string =
  let candidates = [
    "./_build/default/bin/main.exe";
    "../bin/main.exe";
    "bin/main.exe";
    "/Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml/_build/default/bin/main.exe";
  ] in
  match List.find_opt Sys.file_exists candidates with
  | Some path -> path
  | None -> "roof_pipeline"

(** [run_cli ?stdin_content args] executes the CLI binary with given arguments and optional stdin, returning exit code, stdout, and stderr. *)
let run_cli ?(stdin_content = "") (args : string list) : int * string * string =
  let exe = resolve_main_exe () in
  let quoted_args = List.map Filename.quote args in
  let stdout_file = Filename.temp_file "cli_m5_stdout_" ".txt" in
  let stderr_file = Filename.temp_file "cli_m5_stderr_" ".txt" in
  let (cmd, cleanup_stdin) =
    if stdin_content = "" then
      (Printf.sprintf "%s %s > %s 2> %s"
        (Filename.quote exe)
        (String.concat " " quoted_args)
        (Filename.quote stdout_file)
        (Filename.quote stderr_file),
       fun () -> ())
    else
      let stdin_file = Filename.temp_file "cli_m5_stdin_" ".txt" in
      let oc = open_out stdin_file in
      output_string oc stdin_content;
      close_out oc;
      (Printf.sprintf "%s %s < %s > %s 2> %s"
        (Filename.quote exe)
        (String.concat " " quoted_args)
        (Filename.quote stdin_file)
        (Filename.quote stdout_file)
        (Filename.quote stderr_file),
       fun () -> (try Sys.remove stdin_file with _ -> ()))
  in
  let raw_status = Sys.command cmd in
  cleanup_stdin ();
  let exit_code =
    match raw_status with
    | 0 -> 0
    | 256 -> 1
    | 512 -> 2
    | n when n land 0xFF = 0 -> n lsr 8
    | n -> n
  in
  let read_all path =
    if Sys.file_exists path then
      let ic = open_in path in
      let len = in_channel_length ic in
      let s = really_input_string ic len in
      close_in ic;
      (try Sys.remove path with _ -> ());
      s
    else ""
  in
  let stdout_content = read_all stdout_file in
  let stderr_content = read_all stderr_file in
  (exit_code, stdout_content, stderr_content)

(** [verify_cryptographic_proof verified] validates the RFC 6234 SHA-256 digital digest over canonical lead fields. *)
let verify_cryptographic_proof (v : verified_lead) : bool =
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
  let expected_digest = Crypto.sha256_string canonical_payload in
  String.length v.sha256_proof = 64 &&
  String.starts_with ~prefix:"PROOF-OCAML-" v.proof_id &&
  v.sha256_proof = expected_digest

(** [test_benchmark_properties ()] stress-tests the 8 real-world benchmark properties (5 qualified, 3 disqualified) against scoring thresholds and invariant codes. *)
let test_benchmark_properties () =
  Printf.printf "\n=== SUITE 1: Real-World Benchmark Properties Verification ===\n%!";

  let bench_01 : raw_lead = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 3850000.0;
    owner_name = Some "Pacific Heights Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0581-012";
    last_roof_permit_date = Some "1998-06-01";
    roof_age_years = Some 28.0;
    year_built = Some 1895;
    phone_number = Some "415-346-1920";
    permits = [
      make_benchmark_permit ~num:"19980512" ~desc:"Complete roof replacement Victorian shingle"
        ~issued:"1998-06-01" ~status:"COMPLETED" ~cost:35000.0 ~is_rep:true;
    ];
  } in
  let v1 = Scorer.verify_lead bench_01 in
  (match v1.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-01: Pacific Heights Victorian qualifies" true;
       assert_true "BENCH-01: Score >= 70.0 threshold" (score.total_score >= 70.0);
       assert_equal_int "BENCH-01: Passes all 4 invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-01: Valid SHA-256 cryptographic proof" (verify_cryptographic_proof v1)
   | Disqualified _ ->
       assert_true "BENCH-01: Erroneously disqualified" false);

  let bench_02 : raw_lead = {
    address = "2340 Union St";
    zip_code = "94123";
    property_type = SingleFamily;
    roof_type = Flat;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Flat";
    estimated_value = Some 4100000.0;
    owner_name = Some "Cow Hollow Family Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0532-019";
    last_roof_permit_date = Some "2001-05-18";
    roof_age_years = Some 25.0;
    year_built = Some 1912;
    phone_number = Some "415-922-2310";
    permits = [
      make_benchmark_permit ~num:"20010518" ~desc:"Full tear-off and replacement of flat roof"
        ~issued:"2001-06-05" ~status:"COMPLETED" ~cost:32000.0 ~is_rep:true;
    ];
  } in
  let v2 = Scorer.verify_lead bench_02 in
  (match v2.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-02: Marina/Cow Hollow property qualifies" true;
       assert_true "BENCH-02: Score >= 70.0 threshold" (score.total_score >= 70.0);
       assert_equal_int "BENCH-02: Passes all 4 invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-02: Valid SHA-256 cryptographic proof" (verify_cryptographic_proof v2)
   | Disqualified _ ->
       assert_true "BENCH-02: Erroneously disqualified" false);

  let bench_03 : raw_lead = {
    address = "1840 Chestnut St";
    zip_code = "94123";
    property_type = MultiUnit2To4;
    roof_type = Flat;
    property_type_raw = Some "TwoToFourUnits";
    roof_type_raw = Some "Flat";
    estimated_value = Some 2950000.0;
    owner_name = Some "Marina Residential Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0488-005";
    last_roof_permit_date = Some "1996-11-20";
    roof_age_years = Some 30.0;
    year_built = Some 1924;
    phone_number = Some "415-922-3190";
    permits = [
      make_benchmark_permit ~num:"19961104" ~desc:"Built-up tar and gravel roof restoration"
        ~issued:"1996-11-20" ~status:"COMPLETED" ~cost:28000.0 ~is_rep:true;
    ];
  } in
  let v3 = Scorer.verify_lead bench_03 in
  (match v3.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-03: Marina TwoToFourUnits Flat qualifies" true;
       assert_true "BENCH-03: Score >= 70.0 threshold" (score.total_score >= 70.0);
       assert_equal_int "BENCH-03: Passes all 4 invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-03: Valid SHA-256 cryptographic proof" (verify_cryptographic_proof v3)
   | Disqualified _ ->
       assert_true "BENCH-03: Erroneously disqualified" false);

  let bench_04 : raw_lead = {
    address = "3645 Washington St";
    zip_code = "94118";
    property_type = SingleFamily;
    roof_type = Victorian;
    property_type_raw = Some "SingleFamily";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 6200000.0;
    owner_name = Some "Presidio Heights Heritage Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "0984-015";
    last_roof_permit_date = Some "1990-10-05";
    roof_age_years = Some 36.0;
    year_built = Some 1915;
    phone_number = Some "415-752-0422";
    permits = [
      make_benchmark_permit ~num:"19901005" ~desc:"Mansard slate roof inspection and rebuild"
        ~issued:"1990-10-24" ~status:"COMPLETED" ~cost:48000.0 ~is_rep:true;
    ];
  } in
  let v4 = Scorer.verify_lead bench_04 in
  (match v4.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-04: Presidio Heights property qualifies" true;
       assert_true "BENCH-04: Score >= 70.0 threshold" (score.total_score >= 70.0);
       assert_equal_int "BENCH-04: Passes all 4 invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-04: Valid SHA-256 cryptographic proof" (verify_cryptographic_proof v4)
   | Disqualified _ ->
       assert_true "BENCH-04: Erroneously disqualified" false);

  let bench_05 : raw_lead = {
    address = "1845 34th Ave";
    zip_code = "94122";
    property_type = SingleFamily;
    roof_type = Flat;
    property_type_raw = Some "SingleFamily";
    roof_type_raw = Some "Flat";
    estimated_value = Some 1350000.0;
    owner_name = Some "Sunset Residential Trust";
    is_hoa = false;
    is_rental = false;
    apn = Some "2045-028";
    last_roof_permit_date = Some "1996-03-12";
    roof_age_years = Some 30.0;
    year_built = Some 1936;
    phone_number = Some "415-661-0721";
    permits = [
      make_benchmark_permit ~num:"19960301" ~desc:"Built-up tar and gravel flat roof replacement"
        ~issued:"1996-03-12" ~status:"COMPLETED" ~cost:24000.0 ~is_rep:true;
    ];
  } in
  let v5 = Scorer.verify_lead bench_05 in
  (match v5.verdict with
   | Qualified { score; invariants_passed; _ } ->
       assert_true "BENCH-05: Sunset Flat Roof qualifies" true;
       assert_true "BENCH-05: Score >= 70.0 threshold" (score.total_score >= 70.0);
       assert_equal_int "BENCH-05: Passes all 4 invariants" 4 (List.length invariants_passed);
       assert_true "BENCH-05: Valid SHA-256 cryptographic proof" (verify_cryptographic_proof v5)
   | Disqualified _ ->
       assert_true "BENCH-05: Erroneously disqualified" false);

  let bench_fail_hoa : raw_lead = {
    address = "200 Brannan St #401";
    zip_code = "94107";
    property_type = Condo;
    roof_type = Flat;
    property_type_raw = Some "Condominium";
    roof_type_raw = Some "Flat";
    estimated_value = Some 1850000.0;
    owner_name = Some "Condominium HOA Member";
    is_hoa = true;
    is_rental = false;
    apn = Some "0122-045";
    last_roof_permit_date = Some "2008-04-10";
    roof_age_years = Some 18.0;
    year_built = Some 2005;
    phone_number = None;
    permits = [];
  } in
  let v_hoa = Scorer.verify_lead bench_fail_hoa in
  (match v_hoa.verdict with
   | Disqualified { failed_invariants; _ } ->
       assert_true "BENCH-FAIL-HOA: Disqualified as expected" true;
       assert_true "BENCH-FAIL-HOA: Contains INV-1 Physical failure code"
         (List.exists (fun v -> v.code = INV1_Physical) failed_invariants);
       assert_true "BENCH-FAIL-HOA: Contains INV-3 Economic failure code"
         (List.exists (fun v -> v.code = INV3_Economic) failed_invariants)
   | Qualified _ ->
       assert_true "BENCH-FAIL-HOA: Erroneously qualified" false);

  let bench_fail_recent : raw_lead = {
    address = "1500 Sutter St";
    zip_code = "94109";
    property_type = SingleFamily;
    roof_type = Flat;
    property_type_raw = Some "SingleFamily";
    roof_type_raw = Some "Flat";
    estimated_value = Some 2200000.0;
    owner_name = Some "Private Owner";
    is_hoa = false;
    is_rental = false;
    apn = Some "0674-002";
    last_roof_permit_date = Some "2023-08-15";
    roof_age_years = Some 3.0;
    year_built = Some 1900;
    phone_number = None;
    permits = [
      make_benchmark_permit ~num:"20230815" ~desc:"Complete roof replacement"
        ~issued:"2023-08-15" ~status:"COMPLETED" ~cost:42000.0 ~is_rep:true;
    ];
  } in
  let v_recent = Scorer.verify_lead bench_fail_recent in
  (match v_recent.verdict with
   | Disqualified { failed_invariants; _ } ->
       assert_true "BENCH-FAIL-RECENT: Disqualified as expected" true;
       assert_true "BENCH-FAIL-RECENT: Contains INV-2 Temporal failure code"
         (List.exists (fun v -> v.code = INV2_Temporal) failed_invariants);
       assert_true "BENCH-FAIL-RECENT: Contains INV-4 Permits failure code"
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
    estimated_value = Some 8500000.0;
    owner_name = Some "Montgomery Commercial LLC";
    is_hoa = false;
    is_rental = true;
    apn = Some "0240-008";
    last_roof_permit_date = Some "2004-10-02";
    roof_age_years = Some 22.0;
    year_built = Some 1920;
    phone_number = None;
    permits = [];
  } in
  let v_rental = Scorer.verify_lead bench_fail_rental in
  (match v_rental.verdict with
   | Disqualified { failed_invariants; _ } ->
       assert_true "BENCH-FAIL-RENTAL: Disqualified as expected" true;
       assert_true "BENCH-FAIL-RENTAL: Contains INV-1 Physical failure code"
         (List.exists (fun v -> v.code = INV1_Physical) failed_invariants);
       assert_true "BENCH-FAIL-RENTAL: Contains INV-3 Economic failure code"
         (List.exists (fun v -> v.code = INV3_Economic) failed_invariants)
   | Qualified _ ->
       assert_true "BENCH-FAIL-RENTAL: Erroneously qualified" false);

  let tampered_addr_digest = Crypto.sha256_string
    (Printf.sprintf "ROO4U-PROOF-V1|%s|%s|%s|%s|%s|%.2f|%s"
      "2224 Pacific Ave"
      bench_01.zip_code
      (string_of_property_type bench_01.property_type)
      (string_of_roof_type bench_01.roof_type)
      "QUALIFIED"
      91.58
      v1.timestamp)
  in
  assert_true "BENCH.TAMPER.ADDR: Modifying address breaks SHA-256 proof"
    (tampered_addr_digest <> v1.sha256_proof);

  let tampered_score_digest = Crypto.sha256_string
    (Printf.sprintf "ROO4U-PROOF-V1|%s|%s|%s|%s|%s|%.2f|%s"
      bench_01.address
      bench_01.zip_code
      (string_of_property_type bench_01.property_type)
      (string_of_roof_type bench_01.roof_type)
      "QUALIFIED"
      99.99
      v1.timestamp)
  in
  assert_true "BENCH.TAMPER.SCORE: Modifying score breaks SHA-256 proof"
    (tampered_score_digest <> v1.sha256_proof)

(** [test_cli_corridors ()] executes live CLI binary across all target SF wealthy corridors and verifies execution summary and exit code 0. *)
let test_cli_corridors () =
  Printf.printf "\n=== SUITE 2: Live CLI Binary Execution Across SF Corridors ===\n%!";

  let corridors = [
    ("Pacific Heights", ["--run"; "--neighborhood"; "Pacific Heights"]);
    ("Marina", ["--run"; "--neighborhood"; "Marina"]);
    ("Presidio Heights", ["--run"; "--neighborhood"; "Presidio Heights"]);
    ("Seacliff", ["--run"; "--neighborhood"; "Seacliff"]);
    ("Richmond (94118)", ["--run"; "--zips"; "94118"]);
    ("Sunset (94122)", ["--run"; "--zips"; "94122"]);
  ] in

  List.iter (fun (corridor_name, args) ->
    let temp_csv = Filename.temp_file "corridor_leads_" ".csv" in
    let temp_db = Filename.temp_file "corridor_db_" ".db" in
    let full_args = args @ ["--csv"; temp_csv; "--db"; temp_db] in
    let (code, stdout_out, _) = run_cli full_args in
    assert_equal_int (Printf.sprintf "CLI.RUN.%s: Exit code 0 on live execution" corridor_name) 0 code;
    assert_contains (Printf.sprintf "CLI.PHASE1.%s: Phase 1 GIS Discovery logged" corridor_name)
      "--- PHASE 1: GIS DISCOVERY ---" stdout_out;
    assert_contains (Printf.sprintf "CLI.SUMMARY.%s: Pipeline Execution Summary logged" corridor_name)
      "ROO4U PIPELINE EXECUTION SUMMARY" stdout_out;
    assert_true (Printf.sprintf "CLI.CSV_EXISTS.%s: CSV artifact exists on disk" corridor_name)
      (Sys.file_exists temp_csv);
    assert_true (Printf.sprintf "CLI.DB_EXISTS.%s: SQLite artifact exists on disk" corridor_name)
      (Sys.file_exists temp_db);
    (try Sys.remove temp_csv with _ -> ());
    (try Sys.remove temp_db with _ -> ())
  ) corridors;

  let multi_csv = Filename.temp_file "multi_corridor_" ".csv" in
  let multi_db = Filename.temp_file "multi_corridor_" ".db" in
  let (multi_code, multi_stdout, _) = run_cli [
    "--run";
    "--neighborhood"; "Pacific Heights,Marina,Presidio Heights,Seacliff";
    "--csv"; multi_csv;
    "--db"; multi_db;
  ] in
  assert_equal_int "CLI.MULTI_CORRIDOR.EXIT: Exit code 0 for multi-corridor execution" 0 multi_code;
  assert_contains "CLI.MULTI_CORRIDOR.BANNER: Multi-neighborhood corridors logged"
    "Target Corridors: [Neighborhoods: Pacific Heights, Marina, Presidio Heights, Seacliff]" multi_stdout;
  assert_true "CLI.MULTI_CORRIDOR.CSV: Multi-corridor CSV created" (Sys.file_exists multi_csv);
  (try Sys.remove multi_csv with _ -> ());
  (try Sys.remove multi_db with _ -> ());

  let (exit_inv, _, stderr_inv) = run_cli ["--run"; "--zips"; "941"] in
  assert_equal_int "CLI.INVALID_ZIP.EXIT: Invalid 3-digit zip exits with 1" 1 exit_inv;
  assert_contains "CLI.INVALID_ZIP.STDERR: Error message logged" "Invalid 5-digit zip code" stderr_inv;

  let single_disq_json = "{\"address\":\"200 Brannan St\",\"zip_code\":\"94107\",\"property_type\":\"Condo\",\"roof_type\":\"Flat\",\"estimated_value\":1850000.0,\"is_hoa\":true}" in
  let (exit_disq, stdout_disq, _) = run_cli ["--json"; single_disq_json] in
  assert_equal_int "CLI.SINGLE_DISQ.EXIT: Disqualified single lead exits with 2" 2 exit_disq;
  assert_contains "CLI.SINGLE_DISQ.VERDICT: Output contains Disqualified status" "DISQUALIFIED" stdout_disq

(** [test_csv_output_integrity ()] executes an end-to-end pipeline run and inspects the resulting CSV file line by line against RFC 4180 rules. *)
let test_csv_output_integrity () =
  Printf.printf "\n=== SUITE 3: Generated CSV Output Schema & Data Integrity ===\n%!";

  let temp_csv = Filename.temp_file "integ_leads_" ".csv" in
  let temp_db = Filename.temp_file "integ_leads_" ".db" in
  let (code, _, _) = run_cli [
    "--run";
    "--neighborhood"; "Pacific Heights,Marina,Presidio Heights";
    "--csv"; temp_csv;
    "--db"; temp_db;
    "--min-score"; "60.0";
  ] in
  assert_equal_int "CSV.RUN.EXIT: Live pipeline exits with 0" 0 code;
  assert_true "CSV.FILE.EXISTS: Export file exists on disk" (Sys.file_exists temp_csv);

  let lines = ref [] in
  let ic = open_in temp_csv in
  (try
     while true do
       let line = input_line ic in
       if String.trim line <> "" then lines := line :: !lines
     done
   with End_of_file -> ());
  close_in ic;
  let all_lines = List.rev !lines in

  assert_true "CSV.LINES.NON_EMPTY: CSV contains header plus data rows" (List.length all_lines >= 2);

  let header = List.hd all_lines in
  let expected_header = "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status" in
  assert_equal_str "CSV.HEADER.EXACT: Exact 10 required RFC 4180 columns" expected_header header;

  let data_rows = List.tl all_lines in
  List.iteri (fun idx row ->
    let cols = String.split_on_char ',' row in
    assert_equal_int (Printf.sprintf "CSV.ROW.%d.COL_COUNT: Exactly 10 columns in row" idx) 10 (List.length cols);

    let address = List.nth cols 0 in
    let zip_code = List.nth cols 1 in
    let prop_type = List.nth cols 2 in
    let roof_type = List.nth cols 3 in
    let assessed_val = List.nth cols 4 in
    let owner_name = List.nth cols 5 in
    let apn = List.nth cols 6 in
    let roof_age = List.nth cols 7 in
    let phone = List.nth cols 8 in
    let status = List.nth cols 9 in

    assert_true (Printf.sprintf "CSV.ROW.%d.ADDR: Non-empty address" idx) (String.length address > 0);
    assert_true (Printf.sprintf "CSV.ROW.%d.ZIP: Valid 5-digit zip" idx) (String.length zip_code = 5);
    assert_true (Printf.sprintf "CSV.ROW.%d.PROP_TYPE: Valid residential property type" idx)
      (prop_type = "Single-Family" || prop_type = "Multi-Unit (2-4 Units)" || prop_type = "SingleFamily" || prop_type = "TwoToFourUnits");
    assert_true (Printf.sprintf "CSV.ROW.%d.ROOF_TYPE: Valid roof morphology" idx)
      (roof_type = "Victorian" || roof_type = "Flat" || roof_type = "Mansard");
    assert_true (Printf.sprintf "CSV.ROW.%d.VAL: Assessed value >= 1000000" idx)
      (int_of_string assessed_val >= 1000000);
    assert_true (Printf.sprintf "CSV.ROW.%d.OWNER: Non-empty owner name" idx) (String.length owner_name > 0);
    if apn <> "" then
      assert_true (Printf.sprintf "CSV.ROW.%d.APN: Formatted APN" idx) (String.length apn >= 7);
    assert_true (Printf.sprintf "CSV.ROW.%d.ROOF_AGE: Roof age >= 15.0 years" idx)
      (float_of_string roof_age >= 15.0);
    assert_equal_str (Printf.sprintf "CSV.ROW.%d.STATUS: Status is VALIDATED" idx) "VALIDATED" status;

    if phone <> "" then (
      assert_true (Printf.sprintf "CSV.ROW.%d.PHONE: NANP phone format NXX-NXX-XXXX" idx)
        (Phone_validator.is_valid_phone phone);
      assert_true (Printf.sprintf "CSV.ROW.%d.NO_DUMMY_555: No fictitious 555-01XX dummy numbers" idx)
        (not (String.starts_with ~prefix:"555-01" (String.sub phone 4 6)))
    );

    assert_true (Printf.sprintf "CSV.ROW.%d.DDE_SAFE: No raw spreadsheet formula prefixes" idx)
      (not (String.starts_with ~prefix:"=" owner_name ||
            String.starts_with ~prefix:"+" owner_name ||
            String.starts_with ~prefix:"-" owner_name ||
            String.starts_with ~prefix:"@" owner_name))
  ) data_rows;

  (try Sys.remove temp_csv with _ -> ());
  (try Sys.remove temp_db with _ -> ())

(** [test_sqlite_persistence_and_wal ()] validates SQLite database tables, WAL journal mode, unique address index, and state transitions. *)
let test_sqlite_persistence_and_wal () =
  Printf.printf "\n=== SUITE 4: SQLite Database WAL Mode, Indexes & State Machine ===\n%!";

  let temp_db = Filename.temp_file "sqlite_challenger_" ".db" in
  let temp_csv = Filename.temp_file "sqlite_challenger_" ".csv" in
  let (code, _, _) = run_cli [
    "--run";
    "--neighborhood"; "Pacific Heights";
    "--csv"; temp_csv;
    "--db"; temp_db;
    "--min-score"; "60.0";
  ] in
  assert_equal_int "SQLITE.CLI.EXIT: Pipeline execution returns 0" 0 code;

  let wal_res = Db.run_sqlite_cmd temp_db "PRAGMA journal_mode;" in
  (match wal_res with
   | Ok jm -> assert_equal_str "SQLITE.JOURNAL_MODE.WAL: Database journal mode is WAL" "wal" (String.lowercase_ascii (String.trim jm))
   | Error e -> assert_true ("SQLITE.JOURNAL_MODE.FAIL: " ^ e) false);

  let idx_res = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_leads_address';" in
  (match idx_res with
   | Ok cnt -> assert_equal_str "SQLITE.INDEX.ADDRESS: Unique index idx_leads_address exists" "1" (String.trim cnt)
   | Error e -> assert_true ("SQLITE.INDEX.FAIL: " ^ e) false);

  let idx_status_res = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_leads_status';" in
  (match idx_status_res with
   | Ok cnt -> assert_equal_str "SQLITE.INDEX.STATUS: Index idx_leads_status exists" "1" (String.trim cnt)
   | Error e -> assert_true ("SQLITE.INDEX.STATUS.FAIL: " ^ e) false);

  let db = Db.create ~db_path:temp_db () in
  let all_leads = Db.list_leads db in
  assert_true "SQLITE.LEADS.POPULATED: Leads persisted into SQLite" (List.length all_leads > 0);

  let exported_leads = Db.list_leads ~status:Db.Exported db in
  assert_true "SQLITE.LEADS.EXPORTED: Exported leads stored with EXPORTED state"
    (List.length exported_leads > 0);

  List.iter (fun row ->
    assert_true "SQLITE.ROW.ADDRESS: Lead has valid non-empty address" (String.length row.Db.address > 0);
    assert_true "SQLITE.ROW.ZIP: Lead has valid 5-digit zip" (String.length row.Db.zip_code = 5);
    assert_true "SQLITE.ROW.ROOF_AGE: Persisted roof age >= 15.0"
      (match row.Db.roof_age_years with Some a -> a >= 15.0 | None -> false)
  ) exported_leads;

  (try Sys.remove temp_csv with _ -> ());
  (try Sys.remove temp_db with _ -> ())

(** [test_adversarial_boundaries_and_dde ()] tests boundary conditions and CSV formula injection neutralization. *)
let test_adversarial_boundaries_and_dde () =
  Printf.printf "\n=== SUITE 5: Adversarial Boundary Invariants & Formula Injection Defenses ===\n%!";

  let val_under = Invariants.check_inv3_economic (Some 999999.0) false false in
  assert_true "BOUNDARY.VAL.UNDER: Valuation $999,999 violates INV-3"
    (match val_under with Violated _ -> true | Satisfied _ -> false);

  let val_boundary = Invariants.check_inv3_economic (Some 1000000.0) false false in
  assert_true "BOUNDARY.VAL.EXACT: Valuation $1,000,000 satisfies INV-3"
    (match val_boundary with Satisfied _ -> true | Violated _ -> false);

  let age_under = Invariants.check_inv2_temporal ~current_year:2026 (Some 14.99) None in
  assert_true "BOUNDARY.AGE.UNDER: Roof age 14.99 years violates INV-2"
    (match age_under with Violated _ -> true | Satisfied _ -> false);

  let age_boundary = Invariants.check_inv2_temporal ~current_year:2026 (Some 15.0) None in
  assert_true "BOUNDARY.AGE.EXACT: Roof age 15.0 years satisfies INV-2"
    (match age_boundary with Satisfied _ -> true | Violated _ -> false);

  let built_1997 = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1997) in
  assert_true "BOUNDARY.BUILT.1997: Zero-permit built 1997 (29 yrs) violates INV-2"
    (match built_1997 with Violated _ -> true | Satisfied _ -> false);

  let built_1996 = Invariants.check_inv2_temporal ~current_year:2026 None (Some 1996) in
  assert_true "BOUNDARY.BUILT.1996: Zero-permit built 1996 (30 yrs) satisfies INV-2"
    (match built_1996 with Satisfied _ -> true | Violated _ -> false);

  let dde_vectors = [
    "=cmd|' /C calc'!A0";
    "+1-800-MALWARE";
    "-2+3*cmd";
    "@SUM(1+1)";
    "\t=1+1";
    "\r=cmd";
    "   =cmd|' /C calc'!A0";
  ] in
  List.iter (fun vec ->
    let sanitized = Csv_exporter.sanitize_csv_field vec in
    assert_true (Printf.sprintf "DDE.DEFENSE: '%s' neutralized with leading quote" (String.escaped vec))
      (String.starts_with ~prefix:"'" sanitized ||
       (String.length sanitized > 0 && sanitized.[0] <> '=' && sanitized.[0] <> '+' && sanitized.[0] <> '-' && sanitized.[0] <> '@'))
  ) dde_vectors

(** [main ()] runs all 5 challenger test suites and reports empirical pass/fail metrics. *)
let main () =
  Printf.printf "======================================================================\n";
  Printf.printf " ROO4U MILESTONE 5 FINAL INTEGRATION & BENCHMARK CHALLENGER SUITE\n";
  Printf.printf "======================================================================\n%!";

  test_benchmark_properties ();
  test_cli_corridors ();
  test_csv_output_integrity ();
  test_sqlite_persistence_and_wal ();
  test_adversarial_boundaries_and_dde ();

  Printf.printf "\n======================================================================\n";
  Printf.printf " CHALLENGER 5.2 SUMMARY: %d Passed, %d Failed\n" !passed_count !failed_count;
  Printf.printf "======================================================================\n%!";

  if !failed_count > 0 then exit 1
  else exit 0

let () = main ()
