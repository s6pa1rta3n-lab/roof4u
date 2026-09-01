(**
   diff_json_fuzz.ml - JSON fuzzing test runner for batch verification and differential checks.
*)

open Roof_engine
open Json

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--stdin" then (
    let content = In_channel.input_all stdin in
    match parse content with
    | Ok ast ->
        print_endline ("OK:" ^ (to_string ast))
    | Error msg ->
        print_endline ("ERROR:" ^ msg)
  ) else if Array.length Sys.argv > 1 && Sys.argv.(1) = "--batch" then (
    let rec loop count =
      try
        let line = input_line stdin in
        let res = parse line in
        (match res with
         | Ok _ -> Printf.printf "OK\n"
         | Error msg -> Printf.printf "ERROR:%s\n" msg);
        loop (count + 1)
      with End_of_file -> ()
    in
    loop 0
  ) else (
    Printf.printf "Usage: diff_json_fuzz.exe [--stdin | --batch]\n"
  )
