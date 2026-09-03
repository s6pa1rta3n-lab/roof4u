(**
   test_boundaries.ml - Test exact boundary condition parity
*)

#use "verify_incremental.ml"

let () =
  let boundary_lengths = [0; 1; 54; 55; 56; 57; 63; 64; 65; 118; 119; 120; 121; 127; 128; 129; 500; 1000; 8192] in
  List.iter (fun len ->
    let str = String.init len (fun i -> Char.chr (i mod 256)) in
    let ocaml_hash = Crypto.sha256_string str in
    
    (* Run python to get reference hash *)
    let cmd = Printf.sprintf "python3 -c \"import hashlib; print(hashlib.sha256(bytes([i %% 256 for i in range(%d)])).hexdigest())\"" len in
    let ic = Unix.open_process_in cmd in
    let py_hash = String.trim (input_line ic) in
    let _ = Unix.close_process_in ic in

    if ocaml_hash <> py_hash then (
      Printf.printf "MISMATCH at len %d:\n  OCaml:  %s\n  Python: %s\n" len ocaml_hash py_hash;
      exit 1
    ) else (
      Printf.printf "  [MATCH] len %5d -> %s\n" len ocaml_hash
    )
  ) boundary_lengths;
  Printf.printf "\nALL BOUNDARY TESTS MATCH PYTHON HASHLIB 100%%!\n"
