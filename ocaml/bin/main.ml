(**
   main.ml - CLI Entrypoint for Roo4u Pure OCaml Engine (roof_pipeline).
   Supports end-to-end live pipeline execution, multi-zip acquisition,
   single lead verification, and RFC 4180 CSV export.
*)

open Roof_engine
open Types
open Scorer
open Pipeline

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

let read_file (filename : string) : string =
  let ic = open_in filename in
  let len = in_channel_length ic in
  let buf = really_input_string ic len in
  close_in ic;
  buf

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
  print_endline "  --zips <string>         Target zip codes (comma-separated, default: \"94115,94123,94118,94109\")";
  print_endline "  --limit <int>           Record limit per zip code (default: 15)";
  print_endline "  --csv <path>            Output CSV file path (default: \"validated_leads.csv\")";
  print_endline "  --db <path>             SQLite database file path (default: \"leads.db\")";
  print_endline "  --min-score <float>     Minimum actionability score for export (default: 60.0)";
  print_endline "";
  print_endline "Single Lead Verification:";
  print_endline "  --stdin                 Read single JSON lead from standard input";
  print_endline "  --file <path>           Read single JSON lead from specified file";
  print_endline "  --json <string>         Verify JSON string passed directly";
  print_endline "  --verify-lead <string>  Alias for --json";
  print_endline "";
  print_endline "General:";
  print_endline "  --help, -h              Display this usage information";
  exit exit_code

let split_comma (s : string) : string list =
  String.split_on_char ',' s
  |> List.map String.trim
  |> List.filter (fun item -> String.length item > 0)

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
    let zips = ref ["94115"; "94123"; "94118"; "94109"] in
    let limit = ref 15 in
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
      | "--homeowner-addresses" :: n :: rest | "--addresses" :: n :: rest ->
          addrs_arg := Some n;
          parse rest
      | "--gis-roofs" :: n :: rest | "--gis" :: n :: rest ->
          gis_arg := Some n;
          parse rest
      | "--roof-permits" :: z :: rest | "--permits" :: z :: rest ->
          permits_arg := Some z;
          parse rest
      | "--property-tax-records" :: n :: rest | "--tax-records" :: n :: rest ->
          tax_arg := Some n;
          parse rest
      | "--acquire-public-records" :: n :: rest | "--acquire" :: n :: rest ->
          acquire_arg := Some n;
          parse rest
      | "--run" :: rest ->
          run_mode := true;
          parse rest
      | "--zips" :: z :: rest ->
          zips := split_comma z;
          parse rest
      | "--limit" :: l :: rest ->
          (try limit := int_of_string l with _ -> ());
          parse rest
      | "--csv" :: c :: rest ->
          csv_path := c;
          parse rest
      | "--db" :: d :: rest ->
          db_path := d;
          parse rest
      | "--min-score" :: m :: rest ->
          (try min_score := float_of_string m with _ -> ());
          parse rest
      | "--json" :: j :: rest | "--verify-lead" :: j :: rest ->
          json_arg := Some j;
          parse rest
      | "--file" :: f :: rest ->
          file_arg := Some f;
          parse rest
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
    | Some n -> run_homeowner_names n !limit
    | None ->
        match !addrs_arg with
        | Some n -> run_homeowner_addresses n !limit
        | None ->
            match !gis_arg with
            | Some n -> run_gis_roofs n !limit
            | None ->
                match !permits_arg with
                | Some z -> run_roof_permits z !limit
                | None ->
                    match !tax_arg with
                    | Some n -> run_property_tax_records n !limit
                    | None ->
                        match !acquire_arg with
                        | Some n -> run_acquire_public_records n !limit
                        | None ->
                            if !stdin_arg then
                              let content = read_stdin () in
                              process_json content
                            else match !file_arg with
                            | Some filename ->
                                let content = read_file filename in
                                process_json content
                            | None ->
                                match !json_arg with
                                | Some json_str ->
                                    process_json json_str
                                | None ->
                                    if !run_mode then
                                      let cfg = {
                                        Pipeline.default_config with
                                        target_zips = !zips;
                                        limit_per_zip = !limit;
                                        csv_path = !csv_path;
                                        db_path = !db_path;
                                        min_score = !min_score;
                                      } in
                                      let summary = Pipeline.run_pipeline ~config:cfg () in
                                      if summary.leads_exported > 0 then exit 0 else exit 0
                                    else
                                      usage ()

let () = main ()

