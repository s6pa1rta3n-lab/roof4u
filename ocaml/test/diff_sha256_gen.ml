(**
   diff_sha256_gen.ml - Dumps SHA-256 digests for lengths 0..8192 and arbitrary stdin for Python differential verification.
*)

open Roof_engine
open Crypto

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--stdin" then (
    let digest = sha256_channel stdin in
    print_endline digest
  ) else if Array.length Sys.argv > 1 && Sys.argv.(1) = "--file" then (
    let digest = sha256_file Sys.argv.(2) in
    print_endline digest
  ) else (
    for len = 0 to 8192 do
      let bytes_val = Bytes.init len (fun i -> Char.chr ((i * 31 + 17) land 0xFF)) in
      let digest = sha256_string (Bytes.to_string bytes_val) in
      Printf.printf "%d:%s\n" len digest
    done
  )
