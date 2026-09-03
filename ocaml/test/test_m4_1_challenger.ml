(**
   test_m4_1_challenger.ml - Empirical Challenger Stress Test Suite for Roo4u CLI Entrypoint.
   Verifies:
     1. Help flags (--help, -h) and no-argument invocations.
     2. Input validation for zips, limits, min-scores, filepaths, and unknown options with exit code 1.
     3. Microservice subcommands and parameter enforcement.
     4. Single lead evaluation via --json, --verify-lead, --file, and --stdin (qualified exit 0, disqualified exit 2).
     5. Live pipeline flag combinations and execution contracts.
*)

let passed_count = ref 0
let failed_count = ref 0

(** [assert_true label cond] asserts that [cond] evaluates to true. *)
let assert_true (label : string) (cond : bool) =
  if cond then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s\n%!" label
  )

(** [assert_equal_int label expected actual] asserts that two integer values are equal. *)
let assert_equal_int (label : string) (expected : int) (actual : int) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s (expected %d, got %d)\n%!" label expected actual
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected %d, got %d)\n%!" label expected actual
  )

(** [assert_contains label needle haystack] asserts that [needle] is a substring of [haystack]. *)
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

(** [resolve_main_exe ()] locates the compiled binary for test execution. *)
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

(** [run_cli ?stdin_content args] executes the CLI binary with given arguments and optional stdin. *)
let run_cli ?(stdin_content = "") (args : string list) : int * string * string =
  let exe = resolve_main_exe () in
  let quoted_args = List.map Filename.quote args in
  let stdout_file = Filename.temp_file "cli_m4_stdout_" ".txt" in
  let stderr_file = Filename.temp_file "cli_m4_stderr_" ".txt" in
  let (cmd, cleanup_stdin) =
    if stdin_content = "" then
      (Printf.sprintf "%s %s > %s 2> %s"
        (Filename.quote exe)
        (String.concat " " quoted_args)
        (Filename.quote stdout_file)
        (Filename.quote stderr_file),
       fun () -> ())
    else
      let stdin_file = Filename.temp_file "cli_m4_stdin_" ".txt" in
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

(** [test_help_and_usage ()] tests help flags and parameterless CLI execution. *)
let test_help_and_usage () =
  Printf.printf "\n=== CHALLENGE SUITE 1: Help Flags and Default Invocations ===\n%!";

  let (code_help, stdout_help, _) = run_cli ["--help"] in
  assert_equal_int "CLI.HELP.LONG: --help exits with 0" 0 code_help;
  assert_contains "CLI.HELP.BANNER: --help shows usage banner" "Usage: roof_pipeline [OPTIONS]" stdout_help;
  assert_contains "CLI.HELP.EXIT_CODES: --help lists exit code 0, 1, 2" "Exit Codes:" stdout_help;

  let (code_h, stdout_h, _) = run_cli ["-h"] in
  assert_equal_int "CLI.HELP.SHORT: -h exits with 0" 0 code_h;
  assert_contains "CLI.HELP.SHORT_BANNER: -h shows usage banner" "Usage: roof_pipeline [OPTIONS]" stdout_h;

  let (code_none, stdout_none, _) = run_cli [] in
  assert_equal_int "CLI.USAGE.NOARGS: invocation without arguments exits with 0" 0 code_none;
  assert_contains "CLI.USAGE.NOARGS_BANNER: parameterless run prints usage banner" "Usage: roof_pipeline [OPTIONS]" stdout_none

(** [test_invalid_inputs ()] tests rejection of invalid inputs and exit code 1. *)
let test_invalid_inputs () =
  Printf.printf "\n=== CHALLENGE SUITE 2: Invalid Inputs and Input Validation (Exit Code 1) ===\n%!";

  let check_invalid_zip zip_label zip_val =
    let (code, _, stderr_msg) = run_cli ["--run"; "--zips"; zip_val] in
    assert_equal_int ("CLI.INV_ZIP." ^ zip_label ^ ": exit code is 1") 1 code;
    assert_contains ("CLI.INV_ZIP." ^ zip_label ^ ": error diagnostics") "Invalid 5-digit zip code" stderr_msg
  in
  check_invalid_zip "SHORT_4DIGIT" "9412";
  check_invalid_zip "LONG_6DIGIT" "941188";
  check_invalid_zip "ALPHA" "ABCDE";
  check_invalid_zip "SPECIAL_CHAR" "9412!";
  check_invalid_zip "MULTI_ONE_BAD" "94123,9412";

  let check_invalid_limit limit_label flag val_str =
    let (code, _, stderr_msg) = run_cli ["--run"; flag; val_str] in
    assert_equal_int ("CLI.INV_LIMIT." ^ limit_label ^ ": exit code is 1") 1 code;
    assert_contains ("CLI.INV_LIMIT." ^ limit_label ^ ": error diagnostics") "must be a positive integer" stderr_msg
  in
  check_invalid_limit "LIMIT_NEGATIVE" "--limit" "-1";
  check_invalid_limit "LIMIT_ZERO" "--limit" "0";
  check_invalid_limit "LIMIT_ALPHA" "--limit" "none";
  check_invalid_limit "MAX_LEADS_NEGATIVE" "--max-leads" "-5";
  check_invalid_limit "MAX_LEADS_ZERO" "--max-leads" "0";
  check_invalid_limit "MAX_LEADS_ALPHA" "--max-leads" "all";

  let check_invalid_score score_label val_str =
    let (code, _, stderr_msg) = run_cli ["--run"; "--min-score"; val_str] in
    assert_equal_int ("CLI.INV_SCORE." ^ score_label ^ ": exit code is 1") 1 code;
    assert_contains ("CLI.INV_SCORE." ^ score_label ^ ": error diagnostics") "must be a float between 0.0 and 100.0" stderr_msg
  in
  check_invalid_score "NEGATIVE_TEN" "-10.0";
  check_invalid_score "NEGATIVE_SMALL" "-0.1";
  check_invalid_score "EXCEED_150" "150.0";
  check_invalid_score "EXCEED_100_POINT_ONE" "100.1";
  check_invalid_score "NOT_FLOAT" "maximum";

  let (code_nonexistent, _, stderr_nonexistent) = run_cli ["--file"; "/tmp/non_existent_file_roo4u_99999.json"] in
  assert_equal_int "CLI.INV_FILE.NONEXISTENT: non-existent file exits with 1" 1 code_nonexistent;
  assert_contains "CLI.INV_FILE.MSG: diagnostics report file not found" "File not found" stderr_nonexistent;

  let (code_empty_csv, _, stderr_empty_csv) = run_cli ["--run"; "--csv"; "  "] in
  assert_equal_int "CLI.INV_PATH.EMPTY_CSV: empty csv path rejected with exit 1" 1 code_empty_csv;
  assert_contains "CLI.INV_PATH.CSV_MSG: diagnostics report empty path" "cannot be empty" stderr_empty_csv;

  let (code_empty_db, _, stderr_empty_db) = run_cli ["--run"; "--db"; "  "] in
  assert_equal_int "CLI.INV_PATH.EMPTY_DB: empty db path rejected with exit 1" 1 code_empty_db;
  assert_contains "CLI.INV_PATH.DB_MSG: diagnostics report empty path" "cannot be empty" stderr_empty_db;

  let (code_unknown, _, stderr_unknown) = run_cli ["--invalid-option-flag"] in
  assert_equal_int "CLI.INV_OPT.UNKNOWN: unknown option rejected with exit 1" 1 code_unknown;
  assert_contains "CLI.INV_OPT.MSG: diagnostics show unknown option" "Unknown option: --invalid-option-flag" stderr_unknown;

  let check_missing_arg flag_label flag =
    let (code, _, stderr_msg) = run_cli [flag] in
    assert_equal_int ("CLI.MISSING_ARG." ^ flag_label ^ ": exit code is 1") 1 code;
    assert_contains ("CLI.MISSING_ARG." ^ flag_label ^ ": error diagnostics") "requires" stderr_msg
  in
  check_missing_arg "HOMEOWNER_NAMES" "--homeowner-names";
  check_missing_arg "HOMEOWNER_ADDRESSES" "--homeowner-addresses";
  check_missing_arg "GIS_ROOFS" "--gis-roofs";
  check_missing_arg "ROOF_PERMITS" "--roof-permits";
  check_missing_arg "PROPERTY_TAX" "--property-tax-records";
  check_missing_arg "ACQUIRE_PUBLIC" "--acquire-public-records";
  check_missing_arg "NEIGHBORHOOD" "--neighborhood";
  check_missing_arg "ZIPS" "--zips";
  check_missing_arg "MAX_LEADS" "--max-leads";
  check_missing_arg "LIMIT" "--limit";
  check_missing_arg "CSV" "--csv";
  check_missing_arg "DB" "--db";
  check_missing_arg "MIN_SCORE" "--min-score";
  check_missing_arg "JSON" "--json";
  check_missing_arg "FILE" "--file"

(** [test_microservices ()] tests public record microservice CLI options. *)
let test_microservices () =
  Printf.printf "\n=== CHALLENGE SUITE 3: Microservice CLI Subcommands ===\n%!";

  let (code_src, stdout_src, _) = run_cli ["--public-records-sources"] in
  assert_equal_int "CLI.MICRO.SOURCES: --public-records-sources exits with 0" 0 code_src;
  assert_contains "CLI.MICRO.SRC_NAMES: names source in JSON" "1_homeowner_names_source" stdout_src;
  assert_contains "CLI.MICRO.SRC_ADDRS: addresses source in JSON" "2_homeowner_addresses_source" stdout_src;
  assert_contains "CLI.MICRO.SRC_GIS: gis source in JSON" "3_gis_roofs_source" stdout_src;
  assert_contains "CLI.MICRO.SRC_PERMITS: permits source in JSON" "4_roof_permits_source" stdout_src;
  assert_contains "CLI.MICRO.SRC_TAX: tax source in JSON" "5_property_tax_records_source" stdout_src;

  let (code_perm_bad, _, stderr_perm_bad) = run_cli ["--roof-permits"; "123"] in
  assert_equal_int "CLI.MICRO.PERMITS_BAD_ZIP: invalid zip rejected with exit 1" 1 code_perm_bad;
  assert_contains "CLI.MICRO.PERMITS_BAD_MSG: diagnostics indicate invalid zip" "Invalid 5-digit zip code" stderr_perm_bad;

  let (code_perm_good, stdout_perm_good, _) = run_cli ["--roof-permits"; "94122"; "--limit"; "2"] in
  assert_equal_int "CLI.MICRO.PERMITS_OK: valid zip permits query exits with 0" 0 code_perm_good;
  assert_contains "CLI.MICRO.PERMITS_JSON: returns JSON array" "permit_number" stdout_perm_good;

  let (code_names, stdout_names, _) = run_cli ["--homeowner-names"; "Pacific Heights"; "--limit"; "2"] in
  assert_equal_int "CLI.MICRO.NAMES: homeowner names query exits with 0" 0 code_names;
  assert_contains "CLI.MICRO.NAMES_JSON: returns parcel owner JSON" "owner_name" stdout_names;

  let (code_addrs, stdout_addrs, _) = run_cli ["--homeowner-addresses"; "Pacific Heights"; "--limit"; "2"] in
  assert_equal_int "CLI.MICRO.ADDRS: homeowner addresses query exits with 0" 0 code_addrs;
  assert_contains "CLI.MICRO.ADDRS_JSON: returns address JSON" "property_location" stdout_addrs;

  let (code_gis, stdout_gis, _) = run_cli ["--gis-roofs"; "Pacific Heights"; "--limit"; "2"] in
  assert_equal_int "CLI.MICRO.GIS: gis roofs query exits with 0" 0 code_gis;
  assert_contains "CLI.MICRO.GIS_JSON: returns roof size JSON" "roof_size_sqft" stdout_gis;

  let (code_tax, stdout_tax, _) = run_cli ["--property-tax-records"; "Pacific Heights"; "--limit"; "2"] in
  assert_equal_int "CLI.MICRO.TAX: property tax records query exits with 0" 0 code_tax;
  assert_contains "CLI.MICRO.TAX_JSON: returns total assessed value JSON" "total_assessed_value" stdout_tax;

  let (code_acq, stdout_acq, _) = run_cli ["--acquire-public-records"; "Pacific Heights"; "--limit"; "2"] in
  assert_equal_int "CLI.MICRO.ACQUIRE: acquire public records query exits with 0" 0 code_acq;
  assert_contains "CLI.MICRO.ACQUIRE_VERDICT: returns verified leads JSON" "verdict" stdout_acq

(** [test_single_lead_evaluations ()] tests single lead evaluation across formats and invariants. *)
let test_single_lead_evaluations () =
  Printf.printf "\n=== CHALLENGE SUITE 4: Single-Lead Evaluation (Exit 0 vs Exit 2) ===\n%!";

  let qualified_json =
    "{\"address\": \"2450 Vallejo St\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 2500000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": false, \"is_rental\": false, \"owner_name\": \"Heritage Pacific Trust\", " ^
    "\"phone_number\": \"415-922-1000\"}"
  in

  let (code_q_json, stdout_q_json, _) = run_cli ["--json"; qualified_json] in
  assert_equal_int "CLI.LEAD.QUAL_JSON.CODE: qualified lead via --json exits with 0" 0 code_q_json;
  assert_contains "CLI.LEAD.QUAL_JSON.STATUS: output contains QUALIFIED status" "\"status\": \"QUALIFIED\"" stdout_q_json;
  assert_contains "CLI.LEAD.QUAL_JSON.PROOF: output contains proof ID" "PROOF-OCAML-" stdout_q_json;

  let (code_q_alias, stdout_q_alias, _) = run_cli ["--verify-lead"; qualified_json] in
  assert_equal_int "CLI.LEAD.QUAL_ALIAS.CODE: qualified lead via --verify-lead alias exits with 0" 0 code_q_alias;
  assert_contains "CLI.LEAD.QUAL_ALIAS.STATUS: alias output contains QUALIFIED status" "\"status\": \"QUALIFIED\"" stdout_q_alias;

  let temp_q_file = Filename.temp_file "lead_qual_" ".json" in
  let oc_q = open_out temp_q_file in
  output_string oc_q qualified_json;
  close_out oc_q;

  let (code_q_file, stdout_q_file, _) = run_cli ["--file"; temp_q_file] in
  assert_equal_int "CLI.LEAD.QUAL_FILE.CODE: qualified lead via --file exits with 0" 0 code_q_file;
  assert_contains "CLI.LEAD.QUAL_FILE.STATUS: file output contains QUALIFIED status" "\"status\": \"QUALIFIED\"" stdout_q_file;
  (try Sys.remove temp_q_file with _ -> ());

  let (code_q_stdin, stdout_q_stdin, _) = run_cli ~stdin_content:qualified_json ["--stdin"] in
  assert_equal_int "CLI.LEAD.QUAL_STDIN.CODE: qualified lead via --stdin exits with 0" 0 code_q_stdin;
  assert_contains "CLI.LEAD.QUAL_STDIN.STATUS: stdin output contains QUALIFIED status" "\"status\": \"QUALIFIED\"" stdout_q_stdin;

  let test_disqualified_scenario label json_payload inv_substring =
    let (code, stdout_msg, _) = run_cli ["--json"; json_payload] in
    assert_equal_int ("CLI.LEAD.DISQ." ^ label ^ ".CODE: exit code is 2") 2 code;
    assert_contains ("CLI.LEAD.DISQ." ^ label ^ ".STATUS: output status is DISQUALIFIED") "\"status\": \"DISQUALIFIED\"" stdout_msg;
    assert_contains ("CLI.LEAD.DISQ." ^ label ^ ".VIOLATION: output indicates failed invariant") inv_substring stdout_msg
  in

  let disq_hoa =
    "{\"address\": \"100 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 2500000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": true, \"is_rental\": false}"
  in
  test_disqualified_scenario "HOA" disq_hoa "INV-3: Economic Viability";

  let disq_rental =
    "{\"address\": \"102 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 2500000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": false, \"is_rental\": true}"
  in
  test_disqualified_scenario "RENTAL" disq_rental "INV-3: Economic Viability";

  let disq_low_value =
    "{\"address\": \"104 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 750000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": false, \"is_rental\": false}"
  in
  test_disqualified_scenario "LOW_VAL" disq_low_value "INV-3: Economic Viability";

  let disq_roof_arch =
    "{\"address\": \"106 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Metal\", \"estimated_value\": 2500000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": false, \"is_rental\": false}"
  in
  test_disqualified_scenario "ROOF_ARCH" disq_roof_arch "INV-1: Physical Eligibility";

  let disq_prop_type =
    "{\"address\": \"108 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"Commercial\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 2500000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": false, \"is_rental\": false}"
  in
  test_disqualified_scenario "PROP_TYPE" disq_prop_type "INV-1: Physical Eligibility";

  let disq_new_roof =
    "{\"address\": \"110 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 2500000.0, \"roof_age_years\": 4.0, " ^
    "\"is_hoa\": false, \"is_rental\": false}"
  in
  test_disqualified_scenario "NEW_ROOF" disq_new_roof "INV-2: Temporal Degradation";

  let disq_recent_permit =
    "{\"address\": \"112 Marina Blvd\", \"zip_code\": \"94123\", \"property_type\": \"SingleFamily\", " ^
    "\"roof_type\": \"Victorian\", \"estimated_value\": 2500000.0, \"roof_age_years\": 22.0, " ^
    "\"is_hoa\": false, \"is_rental\": false, \"permits\": [" ^
    "{\"permit_number\": \"2024-001\", \"description\": \"Complete roof replacement\", " ^
    "\"is_roof_replacement\": true, \"year\": 2024}]}"
  in
  test_disqualified_scenario "PERMIT_CONFLICT" disq_recent_permit "INV-4: Permit Recency Non-Conflict";

  let temp_d_file = Filename.temp_file "lead_disq_" ".json" in
  let oc_d = open_out temp_d_file in
  output_string oc_d disq_hoa;
  close_out oc_d;

  let (code_d_file, stdout_d_file, _) = run_cli ["--file"; temp_d_file] in
  assert_equal_int "CLI.LEAD.DISQ_FILE.CODE: disqualified lead via --file exits with 2" 2 code_d_file;
  assert_contains "CLI.LEAD.DISQ_FILE.STATUS: file output contains DISQUALIFIED status" "\"status\": \"DISQUALIFIED\"" stdout_d_file;
  (try Sys.remove temp_d_file with _ -> ());

  let (code_d_stdin, stdout_d_stdin, _) = run_cli ~stdin_content:disq_hoa ["--stdin"] in
  assert_equal_int "CLI.LEAD.DISQ_STDIN.CODE: disqualified lead via --stdin exits with 2" 2 code_d_stdin;
  assert_contains "CLI.LEAD.DISQ_STDIN.STATUS: stdin output contains DISQUALIFIED status" "\"status\": \"DISQUALIFIED\"" stdout_d_stdin;

  let malformed_str = "{\"invalid_json\": true," in
  let (code_malformed, _, stderr_malformed) = run_cli ["--json"; malformed_str] in
  assert_equal_int "CLI.LEAD.MALFORMED_JSON: syntax error in --json exits with 1" 1 code_malformed;
  assert_contains "CLI.LEAD.MALFORMED_MSG: reports JSON parse error" "Failed to parse JSON lead" stderr_malformed;

  let (code_malformed_stdin, _, stderr_malformed_stdin) = run_cli ~stdin_content:malformed_str ["--stdin"] in
  assert_equal_int "CLI.LEAD.MALFORMED_STDIN: syntax error in --stdin exits with 1" 1 code_malformed_stdin;
  assert_contains "CLI.LEAD.MALFORMED_STDIN_MSG: reports JSON parse error" "Failed to parse JSON lead" stderr_malformed_stdin

(** [test_pipeline_flag_combinations ()] tests multi-flag pipeline execution runs. *)
let test_pipeline_flag_combinations () =
  Printf.printf "\n=== CHALLENGE SUITE 5: Live Pipeline Flag Combinations ===\n%!";

  let temp_db1 = Filename.temp_file "pipe_c1_db_" ".sqlite" in
  let temp_csv1 = Filename.temp_file "pipe_c1_csv_" ".csv" in
  let (code_c1, stdout_c1, _) =
    run_cli [
      "--run";
      "--zips"; "94123";
      "--db"; temp_db1;
      "--csv"; temp_csv1;
    ]
  in
  assert_equal_int "CLI.COMB1.CODE: --run --zips 94123 exits with 0" 0 code_c1;
  assert_contains "CLI.COMB1.ZIP: target zip logged" "Target SF Zip Codes: 94123" stdout_c1;
  assert_contains "CLI.COMB1.P1: Phase 1 logged" "--- PHASE 1: GIS DISCOVERY ---" stdout_c1;
  assert_contains "CLI.COMB1.P2: Phase 2 logged" "--- PHASE 2: CONTACT ENRICHMENT ---" stdout_c1;
  assert_contains "CLI.COMB1.P3: Phase 3 logged" "--- PHASE 3: PUBLIC RECORDS & TAX VALIDATION ---" stdout_c1;
  assert_contains "CLI.COMB1.P4: Phase 4 logged" "--- PHASE 4: INVARIANT QUALIFICATION & ACTIONABILITY SCORING ---" stdout_c1;
  assert_contains "CLI.COMB1.P5: Phase 5 logged" "--- PHASE 5: PERSISTENCE & RFC 4180 CSV EXPORT ---" stdout_c1;
  assert_contains "CLI.COMB1.SUMMARY: execution summary logged" "ROO4U PIPELINE EXECUTION SUMMARY" stdout_c1;
  assert_true "CLI.COMB1.CSV_EXISTS: CSV file generated" (Sys.file_exists temp_csv1);
  (try Sys.remove temp_db1 with _ -> ());
  (try Sys.remove (temp_db1 ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db1 ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv1 with _ -> ());

  let temp_db2 = Filename.temp_file "pipe_c2_db_" ".sqlite" in
  let temp_csv2 = Filename.temp_file "pipe_c2_csv_" ".csv" in
  let (code_c2, stdout_c2, _) =
    run_cli [
      "--run";
      "--neighborhood"; "Pacific Heights";
      "--db"; temp_db2;
      "--csv"; temp_csv2;
    ]
  in
  assert_equal_int "CLI.COMB2.CODE: --run --neighborhood \"Pacific Heights\" exits with 0" 0 code_c2;
  assert_contains "CLI.COMB2.NEIGHBORHOOD: target neighborhood logged" "Target Corridors: [Neighborhoods: Pacific Heights]" stdout_c2;
  assert_contains "CLI.COMB2.SUMMARY: execution summary logged" "Exit Code:                      0 (Success)" stdout_c2;
  assert_true "CLI.COMB2.CSV_EXISTS: CSV file generated" (Sys.file_exists temp_csv2);
  (try Sys.remove temp_db2 with _ -> ());
  (try Sys.remove (temp_db2 ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db2 ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv2 with _ -> ());

  let temp_db3 = Filename.temp_file "pipe_c3_db_" ".sqlite" in
  let temp_csv3 = Filename.temp_file "pipe_c3_csv_" ".csv" in
  let (code_c3, stdout_c3, _) =
    run_cli [
      "--run";
      "--zips"; "94115,94118";
      "--max-leads"; "10";
      "--min-score"; "70.0";
      "--db"; temp_db3;
      "--csv"; temp_csv3;
    ]
  in
  assert_equal_int "CLI.COMB3.CODE: --run --zips 94115,94118 --max-leads 10 --min-score 70.0 exits with 0" 0 code_c3;
  assert_contains "CLI.COMB3.ZIPS: multi-zips logged" "Target SF Zip Codes: 94115, 94118" stdout_c3;
  assert_contains "CLI.COMB3.MIN_SCORE: min score 70.0 logged" "Minimum Score: 70.0" stdout_c3;
  assert_contains "CLI.COMB3.MAX_LEADS: max leads 10 logged" "Max Leads: 10" stdout_c3;
  assert_true "CLI.COMB3.CSV_EXISTS: CSV file generated" (Sys.file_exists temp_csv3);
  (try Sys.remove temp_db3 with _ -> ());
  (try Sys.remove (temp_db3 ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db3 ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv3 with _ -> ());

  let temp_db4 = Filename.temp_file "pipe_c4_db_" ".sqlite" in
  let temp_csv4 = Filename.temp_file "pipe_c4_csv_" ".csv" in
  let (code_c4, stdout_c4, _) =
    run_cli [
      "--run";
      "--zips"; "94123";
      "--min-score"; "0.0";
      "--db"; temp_db4;
      "--csv"; temp_csv4;
    ]
  in
  assert_equal_int "CLI.COMB4.MIN_SCORE_ZERO: min-score 0.0 boundary accepted with exit 0" 0 code_c4;
  assert_contains "CLI.COMB4.MIN_SCORE_LOG: min-score 0.0 logged" "Minimum Score: 0.0" stdout_c4;
  (try Sys.remove temp_db4 with _ -> ());
  (try Sys.remove (temp_db4 ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db4 ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv4 with _ -> ());

  let temp_db5 = Filename.temp_file "pipe_c5_db_" ".sqlite" in
  let temp_csv5 = Filename.temp_file "pipe_c5_csv_" ".csv" in
  let (code_c5, stdout_c5, _) =
    run_cli [
      "--run";
      "--zips"; "94123";
      "--min-score"; "100.0";
      "--db"; temp_db5;
      "--csv"; temp_csv5;
    ]
  in
  assert_equal_int "CLI.COMB5.MIN_SCORE_HUNDRED: min-score 100.0 boundary accepted with exit 0" 0 code_c5;
  assert_contains "CLI.COMB5.MIN_SCORE_LOG: min-score 100.0 logged" "Minimum Score: 100.0" stdout_c5;
  (try Sys.remove temp_db5 with _ -> ());
  (try Sys.remove (temp_db5 ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db5 ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv5 with _ -> ())

let () =
  Printf.printf "======================================================================\n";
  Printf.printf " Roo4u Milestone 4.1: Empirical CLI Runner Challenger Stress Suite\n";
  Printf.printf "======================================================================\n%!";

  test_help_and_usage ();
  test_invalid_inputs ();
  test_microservices ();
  test_single_lead_evaluations ();
  test_pipeline_flag_combinations ();

  Printf.printf "\n======================================================================\n";
  Printf.printf " EMPIRICAL CHALLENGER 4.1 SUMMARY: %d Passed, %d Failed\n" !passed_count !failed_count;
  Printf.printf "======================================================================\n%!";

  if !failed_count > 0 then exit 1 else exit 0
