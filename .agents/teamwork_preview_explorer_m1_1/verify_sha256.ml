(**
   verify_sha256.ml - Standalone verification of pure OCaml SHA-256 implementation
*)

module Sha256 = struct
  (* 32-bit word operations *)
  let ( &&& ) = Int32.logand
  let ( ||| ) = Int32.logor
  let ( ^^^ ) = Int32.logxor
  let ( +++ ) = Int32.add
  let lnot32 = Int32.lognot

  let rotr (x : int32) (n : int) : int32 =
    (Int32.shift_right_logical x n) ||| (Int32.shift_left x (32 - n))

  let shr (x : int32) (n : int) : int32 =
    Int32.shift_right_logical x n

  (* Logical functions as defined in RFC 6234 / FIPS 180-4 *)
  let ch (x : int32) (y : int32) (z : int32) : int32 =
    (x &&& y) ^^^ ((lnot32 x) &&& z)

  let maj (x : int32) (y : int32) (z : int32) : int32 =
    (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

  let big_sigma0 (x : int32) : int32 =
    (rotr x 2) ^^^ (rotr x 13) ^^^ (rotr x 22)

  let big_sigma1 (x : int32) : int32 =
    (rotr x 6) ^^^ (rotr x 11) ^^^ (rotr x 25)

  let small_sigma0 (x : int32) : int32 =
    (rotr x 7) ^^^ (rotr x 18) ^^^ (shr x 3)

  let small_sigma1 (x : int32) : int32 =
    (rotr x 17) ^^^ (rotr x 19) ^^^ (shr x 10)

  (* Round constants K *)
  let k = [|
    0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l;
    0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
    0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l;
    0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
    0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl;
    0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
    0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l;
    0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
    0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l;
    0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
    0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l;
    0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
    0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l;
    0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
    0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
    0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l;
  |]

  (* Initial hash state *)
  let initial_h = [|
    0x6a09e667l;
    0xbb67ae85l;
    0x3c6ef372l;
    0xa54ff53al;
    0x510e527fl;
    0x9b05688cl;
    0x1f83d9abl;
    0x5be0cd19l;
  |]

  let get_be_int32 (b : bytes) (offset : int) : int32 =
    let b0 = Int32.of_int (Char.code (Bytes.get b offset)) in
    let b1 = Int32.of_int (Char.code (Bytes.get b (offset + 1))) in
    let b2 = Int32.of_int (Char.code (Bytes.get b (offset + 2))) in
    let b3 = Int32.of_int (Char.code (Bytes.get b (offset + 3))) in
    (Int32.shift_left b0 24) |||
    (Int32.shift_left b1 16) |||
    (Int32.shift_left b2 8)  |||
    b3

  let pad_message (msg : bytes) : bytes =
    let len = Bytes.length msg in
    let bit_len = Int64.mul (Int64.of_int len) 8L in
    (* Remainder mod 64 *)
    let r = len mod 64 in
    let k_zeros = if r < 56 then 56 - 1 - r else 64 + 56 - 1 - r in
    let total_len = len + 1 + k_zeros + 8 in
    let padded = Bytes.make total_len '\x00' in
    Bytes.blit msg 0 padded 0 len;
    Bytes.set padded len '\x80';
    (* Append 64-bit big-endian bit length *)
    for i = 0 to 7 do
      let shift = (7 - i) * 8 in
      let byte_val = Int64.to_int (Int64.logand (Int64.shift_right_logical bit_len shift) 0xFFL) in
      Bytes.set padded (total_len - 8 + i) (Char.chr byte_val)
    done;
    padded

  let sha256_bytes (msg : bytes) : bytes =
    let padded = pad_message msg in
    let num_blocks = Bytes.length padded / 64 in
    let h = Array.copy initial_h in
    let w = Array.make 64 0l in

    for b = 0 to num_blocks - 1 do
      let block_offset = b * 64 in
      (* 1. Prepare message schedule W *)
      for t = 0 to 15 do
        w.(t) <- get_be_int32 padded (block_offset + (t * 4))
      done;
      for t = 16 to 63 do
        let s0 = small_sigma0 w.(t - 15) in
        let s1 = small_sigma1 w.(t - 2) in
        w.(t) <- s1 +++ w.(t - 7) +++ s0 +++ w.(t - 16)
      done;

      (* 2. Initialize working variables *)
      let a = ref h.(0) in
      let b_var = ref h.(1) in
      let c = ref h.(2) in
      let d = ref h.(3) in
      let e = ref h.(4) in
      let f = ref h.(5) in
      let g = ref h.(6) in
      let h_var = ref h.(7) in

      (* 3. 64 compression rounds *)
      for t = 0 to 63 do
        let t1 = !h_var +++ big_sigma1 !e +++ ch !e !f !g +++ k.(t) +++ w.(t) in
        let t2 = big_sigma0 !a +++ maj !a !b_var !c in
        h_var := !g;
        g := !f;
        f := !e;
        e := !d +++ t1;
        d := !c;
        c := !b_var;
        b_var := !a;
        a := t1 +++ t2
      done;

      (* 4. Compute intermediate hash values *)
      h.(0) <- h.(0) +++ !a;
      h.(1) <- h.(1) +++ !b_var;
      h.(2) <- h.(2) +++ !c;
      h.(3) <- h.(3) +++ !d;
      h.(4) <- h.(4) +++ !e;
      h.(5) <- h.(5) +++ !f;
      h.(6) <- h.(6) +++ !g;
      h.(7) <- h.(7) +++ !h_var
    done;

    (* Serialize to 32 bytes *)
    let out = Bytes.create 32 in
    for i = 0 to 7 do
      let word = h.(i) in
      let b0 = Int32.to_int (Int32.shift_right_logical word 24) land 0xFF in
      let b1 = Int32.to_int (Int32.shift_right_logical word 16) land 0xFF in
      let b2 = Int32.to_int (Int32.shift_right_logical word 8) land 0xFF in
      let b3 = Int32.to_int word land 0xFF in
      Bytes.set out (i * 4) (Char.chr b0);
      Bytes.set out (i * 4 + 1) (Char.chr b1);
      Bytes.set out (i * 4 + 2) (Char.chr b2);
      Bytes.set out (i * 4 + 3) (Char.chr b3)
    done;
    out

  let sha256_string (s : string) : string =
    let digest_bytes = sha256_bytes (Bytes.of_string s) in
    let buf = Buffer.create 64 in
    for i = 0 to 31 do
      let byte_val = Char.code (Bytes.get digest_bytes i) in
      Buffer.add_string buf (Printf.sprintf "%02x" byte_val)
    done;
    Buffer.contents buf

  let sha256_digest (s : string) : string =
    sha256_string s
end

let () =
  let test_vectors = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
     "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1");
  ] in

  Printf.printf "Running RFC 6234 / FIPS 180-4 SHA-256 Test Vectors...\n";
  List.iter (fun (input, expected) ->
    let actual = Sha256.sha256_string input in
    if actual = expected then
      Printf.printf "  [PASS] input len %d -> %s\n" (String.length input) actual
    else (
      Printf.printf "  [FAIL] input '%s'\n    expected: %s\n    actual:   %s\n" input expected actual;
      exit 1
    )
  ) test_vectors;

  (* 1,000,000 repetitions of 'a' *)
  let million_a = String.make 1000000 'a' in
  let expected_million = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" in
  let actual_million = Sha256.sha256_string million_a in
  if actual_million = expected_million then
    Printf.printf "  [PASS] 1,000,000 'a' test vector -> %s\n" actual_million
  else (
    Printf.printf "  [FAIL] million 'a'\n    expected: %s\n    actual:   %s\n" expected_million actual_million;
    exit 1
  );

  Printf.printf "\nALL SHA-256 TEST VECTORS PASSED PERFECTLY!\n"
