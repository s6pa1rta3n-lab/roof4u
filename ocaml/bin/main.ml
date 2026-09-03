(**
   main.ml - CLI Entrypoint for Roo4u Pure OCaml Engine (roof_pipeline).
   Supports end-to-end live pipeline execution, multi-zip acquisition,
   neighborhood filtering, single lead verification, and RFC 4180 CSV export.
*)

open Roof_engine
open Types
open Scorer
open Pipeline

let is_valid_zip (z : string) : bool =
  String.length z = 5 &&
  let rec check i =
    if i >= 5 then true
    else if z.[i] >= '0' && z.[i] <= '9' then check (i + 1)
    else false
  in
  check 0

let split_comma (s : string) : string list =
  String.split_on_char ',' s
  |> List.map String.trim
  |> List.filter (fun item -> String.length item > 0)

let read_stdin () : string =
  let buf = Buffer.create 1024 in
  try
    while true do
      let line = input_line stdin in
      Buffer.add_string buf line;
      Buffer.add_char buf '\n'
    done;
    Buffer.contents buf
  with End_of_file ->
    Buffer.contents buf

let read_file (filename : string) : (string, string) result =
  if not (Sys.file_exists filename) then
    Error ("File not found: " ^ filename)
  else
    try
      let ic = open_in filename in
      let len = in_channel_length ic in
      let buf = really_input_string ic len in
      close_in ic;
      Ok buf
    with exn ->
      Error ("Failed to read file: " ^ Printexc.to_string exn)

let process_json (json_str : string) =
  match parse_json_lead json_str with
  | Error err ->
      prerr_endline ("Failed to parse JSON lead: " ^ err);
      exit 1
  | Ok lead ->
      let verified = verify_lead lead in
      let out_json = verified_lead_to_json_string ~pretty:true verified in
      print_endline out_json;
      match verified.verdict with
      | Qualified _ -> exit 0
      | Disqualified _ -> exit 2

let usage ?(exit_code = 1) () =
  print_endline "Usage: roof_pipeline [OPTIONS]";
  print_endline "";
  print_endline "Public Records Microservices:";
  print_endline "  --homeowner-names <neighborhood>       Find homeowner names via public Assessor records";
  print_endline "  --homeowner-addresses <neighborhood>   Find homeowner addresses in a neighborhood";
  print_endline "  --gis-roofs <neighborhood>             Find GIS roof footprints & geometries";
  print_endline "  --roof-permits <zip_code>              Find DBI roofing permits for a neighborhood/zip";
  print_endline "  --property-tax-records <neighborhood>  Find County Property & Tax records";
  print_endline "  --acquire-public-records <neighborhood> Acquire and qualify leads across all 5 public record sources";
  print_endline "  --public-records-sources               Print data sources for all 5 public record inquiries";
  print_endline "";
  print_endline "Pipeline Execution:";
  print_endline "  --run                   Execute the end-to-end live pipeline";
  print_endline "  --neighborhood <string> Target SF neighborhood(s) (comma-separated, e.g. \"Marina,Pacific Heights\")";
  print_endline "  --neighborhoods <string> Alias for --neighborhood";
  print_endline "  --zips <string>         Target zip codes (comma-separated, default: \"94122,94118,94112,94115\")";
  print_endline "  --max-leads <int>       Maximum total leads to discover/export (> 0)";
  print_endline "  --limit <int>           Alias for --max-leads / record limit per zip code";
  print_endline "  --csv <path>            Output CSV file path (default: \"validated_leads.csv\")";
  print_endline "  --db <path>             SQLite database file path (default: \"leads.db\")";
  print_endline "  --min-score <float>     Minimum actionability score for export (0.0 to 100.0, default: 60.0)";
  print_endline "";
  print_endline "Single Lead Verification:";
  print_endline "  --stdin                 Read single JSON lead from standard input";
  print_endline "  --file <path>           Read single JSON lead from specified file";
  print_endline "  --json <string>         Verify JSON string passed directly";
  print_endline "  --verify-lead <string>  Alias for --json";
  print_endline "";
  print_endline "General:";
  print_endline "  --help, -h              Display this usage information";
  print_endline "";
  print_endline "Exit Codes:";
  print_endline "  0  Success / qualified lead / help display";
  print_endline "  1  Invalid CLI argument, missing argument, validation error, or pipeline failure";
  print_endline "  2  Single lead disqualified by invariants";
  exit exit_code

let run_homeowner_names (neighborhood : string) (limit : int) =
  match Homeowner_names.fetch_homeowner_names ~limit ~neighborhood () with
  | Ok records ->
      let json_arr = Json.Array (List.map homeowner_name_record_to_json records) in
      print_endline (Json.to_string_pretty json_arr);
      exit 0
  | Error err ->
      prerr_endline ("Error fetching homeowner names: " ^ err);
      exit 1

let run_homeowner_addresses (neighborhood : string) (limit : int) =
  match Homeowner_addresses.fetch_homeowner_addresses ~limit ~neighborhood () with
  | Ok records ->
      let json_arr = Json.Array (List.map homeowner_address_record_to_json records) in
      print_endline (Json.to_string_pretty json_arr);
      exit 0
  | Error err ->
      prerr_endline ("Error fetching homeowner addresses: " ^ err);
      exit 1

let run_gis_roofs (neighborhood : string) (limit : int) =
  match Gis_roofs.fetch_gis_roofs ~limit ~neighborhood () with
  | Ok records ->
      let json_arr = Json.Array (List.map gis_roof_record_to_json records) in
      print_endline (Json.to_string_pretty json_arr);
      exit 0
  | Error err ->
      prerr_endline ("Error fetching GIS roofs: " ^ err);
      exit 1

let run_roof_permits (zip_code : string) (limit : int) =
  if not (is_valid_zip zip_code) then (
    prerr_endline ("Invalid 5-digit zip code: " ^ zip_code);
    exit 1
  );
  match Roof_permits.fetch_roof_permits ~limit ~zip_code () with
  | Ok records ->
      let json_arr = Json.Array (List.map roof_permit_record_to_json records) in
      print_endline (Json.to_string_pretty json_arr);
      exit 0
  | Error err ->
      prerr_endline ("Error fetching roof permits: " ^ err);
      exit 1

let run_property_tax_records (neighborhood : string) (limit : int) =
  match Property_tax_records.fetch_property_tax_records ~limit ~neighborhood () with
  | Ok records ->
      let json_arr = Json.Array (List.map property_tax_record_to_json records) in
      print_endline (Json.to_string_pretty json_arr);
      exit 0
  | Error err ->
      prerr_endline ("Error fetching property tax records: " ^ err);
      exit 1

let run_acquire_public_records (neighborhood : string) (limit : int) =
  match Public_records_orchestrator.acquire_neighborhood_public_records ~limit ~neighborhood () with
  | Ok verified ->
      let json_arr = Json.Array (List.map verified_lead_to_json verified) in
      print_endline (Json.to_string_pretty json_arr);
      exit 0
  | Error err ->
      prerr_endline ("Error acquiring public records: " ^ err);
      exit 1

let print_public_records_sources () =
  let answers = Public_records_orchestrator.get_public_records_answers () in
  let ast = Json.Object [
    ("1_homeowner_names_source", Json.String answers.names_source);
    ("2_homeowner_addresses_source", Json.String answers.addresses_source);
    ("3_gis_roofs_source", Json.String answers.gis_source);
    ("4_roof_permits_source", Json.String answers.permits_source);
    ("5_property_tax_records_source", Json.String answers.tax_source);
  ] in
  print_endline (Json.to_string_pretty ast);
  exit 0

let main () =
  let args = Array.to_list Sys.argv |> List.tl in
  if args = [] then usage ~exit_code:0 ()
  else
    let run_mode = ref false in
    let neighborhoods = ref [] in
    let zips = ref ["94122"; "94118"; "94112"; "94115"] in
    let max_leads_opt = ref None in
    let limit_val = ref 15 in
    let csv_path = ref "validated_leads.csv" in
    let db_path = ref "leads.db" in
    let min_score = ref 60.0 in
    let json_arg = ref None in
    let file_arg = ref None in
    let stdin_arg = ref false in
    let names_arg = ref None in
    let addrs_arg = ref None in
    let gis_arg = ref None in
    let permits_arg = ref None in
    let tax_arg = ref None in
    let acquire_arg = ref None in
    let sources_arg = ref false in

    let rec parse = function
      | [] -> ()
      | "--sources" :: rest | "--public-records-sources" :: rest ->
          sources_arg := true;
          parse rest
      | "--homeowner-names" :: n :: rest ->
          names_arg := Some n;
          parse rest
      | "--homeowner-names" :: [] ->
          prerr_endline "Error: --homeowner-names requires a neighborhood argument";
          exit 1
      | "--homeowner-addresses" :: n :: rest | "--addresses" :: n :: rest ->
          addrs_arg := Some n;
          parse rest
      | "--homeowner-addresses" :: [] | "--addresses" :: [] ->
          prerr_endline "Error: --homeowner-addresses requires a neighborhood argument";
          exit 1
      | "--gis-roofs" :: n :: rest | "--gis" :: n :: rest ->
          gis_arg := Some n;
          parse rest
      | "--gis-roofs" :: [] | "--gis" :: [] ->
          prerr_endline "Error: --gis-roofs requires a neighborhood argument";
          exit 1
      | "--roof-permits" :: z :: rest | "--permits" :: z :: rest ->
          permits_arg := Some z;
          parse rest
      | "--roof-permits" :: [] | "--permits" :: [] ->
          prerr_endline "Error: --roof-permits requires a zip code argument";
          exit 1
      | "--property-tax-records" :: n :: rest | "--tax-records" :: n :: rest ->
          tax_arg := Some n;
          parse rest
      | "--property-tax-records" :: [] | "--tax-records" :: [] ->
          prerr_endline "Error: --property-tax-records requires a neighborhood argument";
          exit 1
      | "--acquire-public-records" :: n :: rest | "--acquire" :: n :: rest ->
          acquire_arg := Some n;
          parse rest
      | "--acquire-public-records" :: [] | "--acquire" :: [] ->
          prerr_endline "Error: --acquire-public-records requires a neighborhood argument";
          exit 1
      | "--neighborhood" :: n :: rest | "--neighborhoods" :: n :: rest ->
          neighborhoods := split_comma n;
          parse rest
      | "--neighborhood" :: [] | "--neighborhoods" :: [] ->
          prerr_endline "Error: --neighborhood requires an argument";
          exit 1
      | "--run" :: rest ->
          run_mode := true;
          parse rest
      | "--zips" :: z :: rest ->
          let parsed = split_comma z in
          List.iter (fun zip ->
            if not (is_valid_zip zip) then (
              prerr_endline ("Error: Invalid 5-digit zip code: " ^ zip);
              exit 1
            )
          ) parsed;
          zips := parsed;
          parse rest
      | "--zips" :: [] ->
          prerr_endline "Error: --zips requires a comma-separated list of zip codes";
          exit 1
      | "--max-leads" :: l :: rest ->
          (match int_of_string_opt l with
           | Some n when n > 0 ->
               max_leads_opt := Some n;
               limit_val := n
           | _ ->
               prerr_endline ("Error: --max-leads must be a positive integer, got: " ^ l);
               exit 1);
          parse rest
      | "--max-leads" :: [] ->
          prerr_endline "Error: --max-leads requires an integer argument";
          exit 1
      | "--limit" :: l :: rest ->
          (match int_of_string_opt l with
           | Some n when n > 0 ->
               limit_val := n;
               max_leads_opt := Some n
           | _ ->
               prerr_endline ("Error: --limit must be a positive integer, got: " ^ l);
               exit 1);
          parse rest
      | "--limit" :: [] ->
          prerr_endline "Error: --limit requires an integer argument";
          exit 1
      | "--csv" :: c :: rest ->
          if String.trim c = "" then (
            prerr_endline "Error: --csv path cannot be empty";
            exit 1
          );
          csv_path := c;
          parse rest
      | "--csv" :: [] ->
          prerr_endline "Error: --csv requires a filepath argument";
          exit 1
      | "--db" :: d :: rest ->
          if String.trim d = "" then (
            prerr_endline "Error: --db path cannot be empty";
            exit 1
          );
          db_path := d;
          parse rest
      | "--db" :: [] ->
          prerr_endline "Error: --db requires a database path argument";
          exit 1
      | "--min-score" :: m :: rest ->
          (match float_of_string_opt m with
           | Some score when score >= 0.0 && score <= 100.0 ->
               min_score := score
           | _ ->
               prerr_endline ("Error: --min-score must be a float between 0.0 and 100.0, got: " ^ m);
               exit 1);
          parse rest
      | "--min-score" :: [] ->
          prerr_endline "Error: --min-score requires a float argument";
          exit 1
      | "--json" :: j :: rest | "--verify-lead" :: j :: rest ->
          json_arg := Some j;
          parse rest
      | "--json" :: [] | "--verify-lead" :: [] ->
          prerr_endline "Error: --json requires a JSON string argument";
          exit 1
      | "--file" :: f :: rest ->
          file_arg := Some f;
          parse rest
      | "--file" :: [] ->
          prerr_endline "Error: --file requires a filepath argument";
          exit 1
      | "--stdin" :: rest ->
          stdin_arg := true;
          parse rest
      | "--help" :: _ | "-h" :: _ ->
          usage ~exit_code:0 ()
      | arg :: _ ->
          prerr_endline ("Unknown option: " ^ arg);
          usage ~exit_code:1 ()
    in
    parse args;

    if !sources_arg then print_public_records_sources ()
    else match !names_arg with
    | Some n -> run_homeowner_names n !limit_val
    | None ->
        match !addrs_arg with
        | Some n -> run_homeowner_addresses n !limit_val
        | None ->
            match !gis_arg with
            | Some n -> run_gis_roofs n !limit_val
            | None ->
                match !permits_arg with
                | Some z -> run_roof_permits z !limit_val
                | None ->
                    match !tax_arg with
                    | Some n -> run_property_tax_records n !limit_val
                    | None ->
                        match !acquire_arg with
                        | Some n -> run_acquire_public_records n !limit_val
                        | None ->
                            if !stdin_arg then
                              let content = read_stdin () in
                              process_json content
                            else match !file_arg with
                            | Some filename ->
                                (match read_file filename with
                                 | Ok content -> process_json content
                                 | Error err ->
                                     prerr_endline err;
                                     exit 1)
                            | None ->
                                match !json_arg with
                                | Some json_str ->
                                    process_json json_str
                                | None ->
                                    if !run_mode then
                                      try
                                        let cfg = {
                                          Pipeline.default_config with
                                          target_zips = !zips;
                                          limit_per_zip = !limit_val;
                                          csv_path = !csv_path;
                                          db_path = !db_path;
                                          min_score = !min_score;
                                        } in
                                        let summary =
                                          Pipeline.run_pipeline
                                            ~config:cfg
                                            ?target_neighborhoods:(if !neighborhoods <> [] then Some !neighborhoods else None)
                                            ?max_leads:!max_leads_opt
                                            ()
                                        in
                                        ignore summary;
                                        exit 0
                                      with exn ->
                                        prerr_endline ("Pipeline execution failed: " ^ Printexc.to_string exn);
                                        exit 1
                                    else
                                      usage ~exit_code:1 ()

let () = main ()
