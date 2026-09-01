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

    let rec parse = function
      | [] -> ()
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
