(**
   main.ml - CLI entrypoint for the OCaml Mathematical Lead Verification Engine.
   Provides deterministic proof generation, schema validation, and invariant checking.
*)

open Roof_verif
open Types
open Invariants
open Parser

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
  let lead = parse_json_lead json_str in
  let verified = verify_lead lead in
  let out_json = verified_lead_to_json verified in
  print_endline out_json;
  match verified.verdict with
  | Qualified _ -> exit 0
  | Disqualified _ -> exit 2

let usage () =
  print_endline "Usage: roof_verif_cli [OPTIONS]";
  print_endline "Options:";
  print_endline "  --stdin                 Read single JSON lead from stdin";
  print_endline "  --file <path>           Read single JSON lead from specified file";
  print_endline "  --json <string>         Verify JSON string passed directly";
  print_endline "  --help                  Display this message";
  exit 1

let () =
  let args = Array.to_list Sys.argv in
  match args with
  | [_; "--stdin"] ->
      let content = read_stdin () in
      process_json content
  | [_; "--file"; filename] ->
      let content = read_file filename in
      process_json content
  | [_; "--json"; json_str] ->
      process_json json_str
  | [_; "--help"] | [_] ->
      usage ()
  | _ ->
      usage ()
