(**
   test_cli_runner.ml - End-to-End Pipeline & CLI Execution Test Suite.
   Verifies CLI flag parsing, input validation, exit codes (0, 1, 2),
   live zip 94123 execution, SQLite WAL mode, schema indexes, state transitions,
   RFC 4180 CSV export schema, formula injection defenses, and idempotency.
*)

open Roof_engine
open Types

let passed_count = ref 0
let failed_count = ref 0

let assert_true (label : string) (cond : bool) =
  if cond then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s\n" label
  )

let assert_equal_int (label : string) (expected : int) (actual : int) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s (expected %d, got %d)\n" label expected actual
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected %d, got %d)\n" label expected actual
  )

let assert_equal_string (label : string) (expected : string) (actual : string) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected '%s', got '%s')\n" label expected actual
  )

let assert_contains (label : string) (needle : string) (haystack : string) =
  let len_n = String.length needle in
  let len_h = String.length haystack in
  let rec search i =
    if i + len_n > len_h then false
    else if String.sub haystack i len_n = needle then true
    else search (i + 1)
  in
  let found = search 0 in
  if found then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (needle '%s' not found in output)\n" label needle
  )

let resolve_main_exe () : string =
  let candidates = [
    "../bin/main.exe";
    "./_build/default/bin/main.exe";
    "ocaml/_build/default/bin/main.exe";
    "/Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml/_build/default/bin/main.exe";
  ] in
  match List.find_opt Sys.file_exists candidates with
  | Some path -> path
  | None -> "roof_pipeline"

let run_cli (args : string list) : int * string * string =
  let exe = resolve_main_exe () in
  let quoted_args = List.map Filename.quote args in
  let stdout_file = Filename.temp_file "cli_stdout_" ".txt" in
  let stderr_file = Filename.temp_file "cli_stderr_" ".txt" in
  let cmd = Printf.sprintf "%s %s > %s 2> %s"
    (Filename.quote exe)
    (String.concat " " quoted_args)
    (Filename.quote stdout_file)
    (Filename.quote stderr_file)
  in
  let raw_status = Sys.command cmd in
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

let test_cli_help_and_version () =
  Printf.printf "\n=== Tier 1: CLI Flags & Help Display ===\n";
  let (code_help, stdout_help, _) = run_cli ["--help"] in
  assert_equal_int "CLI.HELP.0: --help exit code is 0" 0 code_help;
  assert_contains "CLI.HELP.1: --help contains Usage banner" "Usage: roof_pipeline [OPTIONS]" stdout_help;
  assert_contains "CLI.HELP.2: --help contains --run flag" "--run" stdout_help;
  assert_contains "CLI.HELP.3: --help contains --neighborhood flag" "--neighborhood" stdout_help;
  assert_contains "CLI.HELP.4: --help contains --zips flag" "--zips" stdout_help;
  assert_contains "CLI.HELP.5: --help contains --max-leads flag" "--max-leads" stdout_help;
  assert_contains "CLI.HELP.6: --help contains --min-score flag" "--min-score" stdout_help;
  assert_contains "CLI.HELP.7: --help contains Exit Codes documentation" "Exit Codes:" stdout_help;

  let (code_h, stdout_h, _) = run_cli ["-h"] in
  assert_equal_int "CLI.HELP.8: -h exit code is 0" 0 code_h;
  assert_contains "CLI.HELP.9: -h contains Usage banner" "Usage: roof_pipeline [OPTIONS]" stdout_h;

  let (code_no_args, stdout_no_args, _) = run_cli [] in
  assert_equal_int "CLI.NOARGS.0: Invoking with no args displays usage with exit code 0" 0 code_no_args;
  assert_contains "CLI.NOARGS.1: No args contains Usage banner" "Usage: roof_pipeline [OPTIONS]" stdout_no_args

let test_cli_input_validation () =
  Printf.printf "\n=== Tier 2: CLI Argument Validation & Exit Codes ===\n";

  let (code_bad_zip, _, stderr_bad_zip) = run_cli ["--run"; "--zips"; "9412"] in
  assert_equal_int "CLI.VAL.ZIP.0: 4-digit zip code rejected with exit code 1" 1 code_bad_zip;
  assert_contains "CLI.VAL.ZIP.1: Diagnostics explain zip format error" "Invalid 5-digit zip code: 9412" stderr_bad_zip;

  let (code_long_zip, _, stderr_long_zip) = run_cli ["--run"; "--zips"; "941188"] in
  assert_equal_int "CLI.VAL.ZIP.2: 6-digit zip code rejected with exit code 1" 1 code_long_zip;
  assert_contains "CLI.VAL.ZIP.3: Diagnostics explain long zip error" "Invalid 5-digit zip code: 941188" stderr_long_zip;

  let (code_alpha_zip, _, stderr_alpha_zip) = run_cli ["--run"; "--zips"; "ABCDE"] in
  assert_equal_int "CLI.VAL.ZIP.4: Alphabetic zip code rejected with exit code 1" 1 code_alpha_zip;
  assert_contains "CLI.VAL.ZIP.5: Diagnostics explain non-numeric zip error" "Invalid 5-digit zip code: ABCDE" stderr_alpha_zip;

  let (code_missing_zip, _, stderr_missing_zip) = run_cli ["--run"; "--zips"] in
  assert_equal_int "CLI.VAL.ZIP.6: Missing zip argument rejected with exit code 1" 1 code_missing_zip;
  assert_contains "CLI.VAL.ZIP.7: Diagnostics explain missing zip argument" "requires a comma-separated list of zip codes" stderr_missing_zip;

  let (code_neg_score, _, stderr_neg_score) = run_cli ["--run"; "--min-score"; "-5.0"] in
  assert_equal_int "CLI.VAL.SCORE.0: Negative min-score rejected with exit code 1" 1 code_neg_score;
  assert_contains "CLI.VAL.SCORE.1: Diagnostics explain min-score range" "must be a float between 0.0 and 100.0" stderr_neg_score;

  let (code_high_score, _, stderr_high_score) = run_cli ["--run"; "--min-score"; "105.0"] in
  assert_equal_int "CLI.VAL.SCORE.2: Score > 100.0 rejected with exit code 1" 1 code_high_score;
  assert_contains "CLI.VAL.SCORE.3: Diagnostics explain min-score ceiling" "must be a float between 0.0 and 100.0" stderr_high_score;

  let (code_alpha_score, _, stderr_alpha_score) = run_cli ["--run"; "--min-score"; "high_score"] in
  assert_equal_int "CLI.VAL.SCORE.4: Non-numeric min-score rejected with exit code 1" 1 code_alpha_score;
  assert_contains "CLI.VAL.SCORE.5: Diagnostics explain non-numeric min-score" "must be a float between 0.0 and 100.0" stderr_alpha_score;

  let (code_zero_leads, _, stderr_zero_leads) = run_cli ["--run"; "--max-leads"; "0"] in
  assert_equal_int "CLI.VAL.LEADS.0: Zero max-leads rejected with exit code 1" 1 code_zero_leads;
  assert_contains "CLI.VAL.LEADS.1: Diagnostics explain positive integer requirement" "must be a positive integer" stderr_zero_leads;

  let (code_neg_leads, _, stderr_neg_leads) = run_cli ["--run"; "--max-leads"; "-10"] in
  assert_equal_int "CLI.VAL.LEADS.2: Negative max-leads rejected with exit code 1" 1 code_neg_leads;
  assert_contains "CLI.VAL.LEADS.3: Diagnostics explain positive integer requirement" "must be a positive integer" stderr_neg_leads;

  let (code_unknown, _, stderr_unknown) = run_cli ["--unknown-flag"] in
  assert_equal_int "CLI.VAL.UNK.0: Unknown option rejected with exit code 1" 1 code_unknown;
  assert_contains "CLI.VAL.UNK.1: Diagnostics report unknown option" "Unknown option: --unknown-flag" stderr_unknown;

  let (code_bad_file, _, stderr_bad_file) = run_cli ["--file"; "/tmp/nonexistent_lead_file_12345.json"] in
  assert_equal_int "CLI.VAL.FILE.0: Non-existent file rejected with exit code 1" 1 code_bad_file;
  assert_contains "CLI.VAL.FILE.1: Diagnostics report file not found" "File not found" stderr_bad_file

let test_single_lead_json_verification () =
  Printf.printf "\n=== Tier 3: Single Lead JSON Verification via CLI ===\n";

  let valid_json =
    "{\"address\": \"1840 Chestnut St\", \"zip_code\": \"94123\", \"property_type\": \"Multi-Unit (2-4 Units)\", " ^
    "\"roof_type\": \"Flat\", \"estimated_value\": 2750000.0, \"owner_name\": \"Marina Residential Trust\", " ^
    "\"is_hoa\": false, \"is_rental\": false, \"apn\": \"0452-018\", \"last_roof_permit_date\": \"2004-06-15\", " ^
    "\"roof_age_years\": 20.0, \"phone_number\": \"415-922-2310\"}"
  in
  let (code_valid, stdout_valid, _) = run_cli ["--json"; valid_json] in
  assert_equal_int "CLI.LEAD.VAL.0: Valid lead JSON verification returns exit code 0" 0 code_valid;
  assert_contains "CLI.LEAD.VAL.1: Output contains verified verdict Qualified" "\"status\": \"QUALIFIED\"" stdout_valid;
  assert_contains "CLI.LEAD.VAL.2: Output contains cryptographic proof" "PROOF-OCAML-" stdout_valid;

  let disqualified_json =
    "{\"address\": \"999 Highrise Blvd\", \"zip_code\": \"94105\", \"property_type\": \"High-Rise (5+ Stories)\", " ^
    "\"roof_type\": \"Flat\", \"estimated_value\": 15000000.0, \"owner_name\": \"Corporate Tower LLC\", " ^
    "\"is_hoa\": true, \"is_rental\": true, \"roof_age_years\": 2.0}"
  in
  let (code_disq, stdout_disq, _) = run_cli ["--json"; disqualified_json] in
  assert_equal_int "CLI.LEAD.DISQ.0: Disqualified lead verification returns exit code 2" 2 code_disq;
  assert_contains "CLI.LEAD.DISQ.1: Output contains Disqualified verdict" "\"status\": \"DISQUALIFIED\"" stdout_disq;
  assert_contains "CLI.LEAD.DISQ.2: Output contains failed invariants" "failed_invariants" stdout_disq;

  let malformed_json = "{not_json_syntax: true}" in
  let (code_syntax, _, stderr_syntax) = run_cli ["--json"; malformed_json] in
  assert_equal_int "CLI.LEAD.SYN.0: Malformed JSON syntax returns exit code 1" 1 code_syntax;
  assert_contains "CLI.LEAD.SYN.1: Output reports JSON parse failure" "Failed to parse JSON lead" stderr_syntax

let test_e2e_pipeline_and_db_persistence () =
  Printf.printf "\n=== Tier 4: End-to-End Live Pipeline Execution (Zip 94123) ===\n";

  let temp_db = Filename.temp_file "test_m4_db_" ".sqlite" in
  let temp_csv = Filename.temp_file "test_m4_out_" ".csv" in

  let (code_run, stdout_run, stderr_run) =
    run_cli [
      "--run";
      "--zips"; "94123";
      "--limit"; "5";
      "--db"; temp_db;
      "--csv"; temp_csv;
      "--min-score"; "60.0";
    ]
  in
  assert_equal_int "CLI.RUN.0: Live pipeline execution on zip 94123 exits with code 0" 0 code_run;
  if code_run <> 0 then Printf.printf "    Stderr: %s\n" stderr_run;

  assert_contains "CLI.RUN.P1: Phase 1 GIS Discovery header logged" "--- PHASE 1: GIS DISCOVERY ---" stdout_run;
  assert_contains "CLI.RUN.P2: Phase 2 Contact Enrichment header logged" "--- PHASE 2: CONTACT ENRICHMENT ---" stdout_run;
  assert_contains "CLI.RUN.P3: Phase 3 Public Records Validation header logged" "--- PHASE 3: PUBLIC RECORDS & TAX VALIDATION ---" stdout_run;
  assert_contains "CLI.RUN.P4: Phase 4 Invariant Qualification header logged" "--- PHASE 4: INVARIANT QUALIFICATION & ACTIONABILITY SCORING ---" stdout_run;
  assert_contains "CLI.RUN.P5: Phase 5 Persistence & CSV Export header logged" "--- PHASE 5: PERSISTENCE & RFC 4180 CSV EXPORT ---" stdout_run;
  assert_contains "CLI.RUN.SUMMARY: Summary banner with Success exit code" "Exit Code:                      0 (Success)" stdout_run;

  assert_true "CLI.CSV.EXISTS: CSV file created on disk" (Sys.file_exists temp_csv);
  let csv_lines = ref [] in
  let ic_csv = open_in temp_csv in
  (try
    while true do
      csv_lines := input_line ic_csv :: !csv_lines
    done
  with End_of_file -> close_in ic_csv);
  let lines = List.rev !csv_lines in

  assert_true "CLI.CSV.ROWS: CSV has at least header + 1 row" (List.length lines >= 2);
  let header = List.hd lines in
  let expected_header = "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status" in
  assert_equal_string "CLI.CSV.HEADER: Exact 10 RFC 4180 column headers in required order" expected_header header;

  List.iter (fun row ->
    let cols = String.split_on_char ',' row in
    assert_true "CLI.CSV.COL_COUNT: Data row has 10 columns" (List.length cols = 10);
    let status_col = List.nth cols 9 in
    assert_equal_string "CLI.CSV.STATUS_COL: Exported lead status column is VALIDATED" "VALIDATED" status_col
  ) (List.tl lines);

  let db = Db.create ~db_path:temp_db () in
  let wal_res = Db.run_sqlite_cmd temp_db "PRAGMA journal_mode;" in
  (match wal_res with
   | Ok mode -> assert_equal_string "CLI.DB.WAL: SQLite database journal mode is WAL" "wal" (String.trim mode)
   | Error err -> assert_true ("CLI.DB.WAL error: " ^ err) false);

  let idx_res = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_leads_address';" in
  (match idx_res with
   | Ok c -> assert_equal_string "CLI.DB.INDEX: idx_leads_address index created" "1" (String.trim c)
   | Error err -> assert_true ("CLI.DB.INDEX error: " ^ err) false);

  let exported_leads = Db.list_leads ~status:Db.Exported db in
  assert_true "CLI.DB.EXPORTED: Leads stored in SQLite with EXPORTED status" (List.length exported_leads >= 1);

  let validated_leads = Db.list_leads ~status:Db.Validated db in
  assert_true "CLI.DB.VALIDATED_MATCH: list_leads ~status:Validated matches EXPORTED rows"
    (List.length validated_leads >= List.length exported_leads);

  Printf.printf "\n=== Tier 5: CLI Idempotency & Repeat Execution ===\n";
  let (code_rerun, _, _) =
    run_cli [
      "--run";
      "--zips"; "94123";
      "--limit"; "5";
      "--db"; temp_db;
      "--csv"; temp_csv;
      "--min-score"; "60.0";
    ]
  in
  assert_equal_int "CLI.IDEMP.0: Re-running pipeline exits with code 0" 0 code_rerun;

  let count_res = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM leads;" in
  (match count_res with
   | Ok c ->
       let total_leads = int_of_string (String.trim c) in
       assert_equal_int "CLI.IDEMP.1: Total leads count unchanged after second execution" (List.length exported_leads) total_leads
   | Error err -> assert_true ("CLI.IDEMP.1 error: " ^ err) false);

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove (temp_db ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv with _ -> ())

let test_neighborhood_cli_execution () =
  Printf.printf "\n=== Tier 6: Neighborhood Flag Pipeline Execution ===\n";

  let temp_db = Filename.temp_file "test_m4_nh_db_" ".sqlite" in
  let temp_csv = Filename.temp_file "test_m4_nh_csv_" ".csv" in

  let (code_nh, stdout_nh, _) =
    run_cli [
      "--run";
      "--neighborhood"; "Marina";
      "--limit"; "5";
      "--db"; temp_db;
      "--csv"; temp_csv;
      "--min-score"; "60.0";
    ]
  in
  assert_equal_int "CLI.NH.0: Pipeline execution with --neighborhood exits with code 0" 0 code_nh;
  assert_contains "CLI.NH.1: Corridor logged in banner" "Target Corridors: [Neighborhoods: Marina]" stdout_nh;
  assert_contains "CLI.NH.2: Candidate discovery for Marina logged" "Discovering candidate leads for Neighborhood: Marina" stdout_nh;
  assert_true "CLI.NH.3: CSV output created on disk" (Sys.file_exists temp_csv);

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove (temp_db ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv with _ -> ())

let test_formula_injection_and_quotes () =
  Printf.printf "\n=== Tier 7: Formula Injection Sanitization & Phone Formatting ===\n";

  let sanitized_equal = Csv_exporter.sanitize_csv_field "=cmd|' /C calc'!A0" in
  assert_equal_string "CSV.DDE.EQ: Prepends apostrophe to =" "'=cmd|' /C calc'!A0" sanitized_equal;

  let sanitized_plus = Csv_exporter.sanitize_csv_field "+1-800-MALWARE" in
  assert_equal_string "CSV.DDE.PLUS: Prepends apostrophe to +" "'+1-800-MALWARE" sanitized_plus;

  let sanitized_at = Csv_exporter.sanitize_csv_field "@SUM(1+1)" in
  assert_equal_string "CSV.DDE.AT: Prepends apostrophe to @" "'@SUM(1+1)" sanitized_at;

  let sanitized_ws = Csv_exporter.sanitize_csv_field "   =cmd" in
  assert_equal_string "CSV.DDE.WS: Prepends apostrophe to whitespace-prefixed =" "'   =cmd" sanitized_ws;

  let normal_phone = "415-346-1234" in
  let escaped_phone = Csv_exporter.escape_csv_field normal_phone in
  assert_equal_string "CSV.PHONE.RAW: Canonical phone number has no quotes" normal_phone escaped_phone;

  let raw_lead_test = {
    address = "100 Test St";
    zip_code = "94122";
    property_type = SingleFamily;
    roof_type = Flat;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Flat";
    estimated_value = Some 1500000.0;
    owner_name = Some "=InjectedOwner";
    is_hoa = false;
    is_rental = false;
    apn = Some "1234-567";
    last_roof_permit_date = Some "2000-01-01";
    roof_age_years = Some 24.0;
    year_built = Some 1940;
    phone_number = Some "415-555-0199";
    permits = [];
  } in
  let csv_row = Csv_exporter.row_of_raw_lead raw_lead_test in
  let owner_cell = List.nth csv_row 5 in
  assert_equal_string "CSV.DDE.ROW: Owner name cell sanitized with leading quote" "'=InjectedOwner" owner_cell;
  let phone_cell = List.nth csv_row 8 in
  assert_equal_string "CSV.PHONE.ROW: Phone cell exported without quoting" "415-555-0199" phone_cell

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf " Roo4u Milestone 4: End-to-End Pipeline & CLI Runner Test Suite\n";
  Printf.printf "======================================================================\n";

  test_cli_help_and_version ();
  test_cli_input_validation ();
  test_single_lead_json_verification ();
  test_e2e_pipeline_and_db_persistence ();
  test_neighborhood_cli_execution ();
  test_formula_injection_and_quotes ();

  Printf.printf "\n======================================================================\n";
  Printf.printf " TEST SUITE SUMMARY: %d Passed, %d Failed\n" !passed_count !failed_count;
  Printf.printf "======================================================================\n\n";

  if !failed_count > 0 then exit 1 else exit 0
