(**
   crypto.ml - Pure OCaml RFC 6234 / FIPS 180-4 compliant SHA-256 implementation.
   Zero external dependencies, 100% pure standard library OCaml 5.
*)

let ( &&& ) = Int32.logand
let ( ||| ) = Int32.logor
let ( ^^^ ) = Int32.logxor
let ( +++ ) = Int32.add
let lnot32 = Int32.lognot

let rotr (x : int32) (n : int) : int32 =
  (Int32.shift_right_logical x n) ||| (Int32.shift_left x (32 - n))

let shr (x : int32) (n : int) : int32 =
  Int32.shift_right_logical x n

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

(** 64 Round Constants K *)
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

type ctx = {
  state : int32 array;
  buffer : bytes;
  mutable buf_len : int;
  mutable total_bytes : int64;
  w : int32 array;
}

let init () : ctx = {
  state = Array.copy initial_h;
  buffer = Bytes.make 64 '\x00';
  buf_len = 0;
  total_bytes = 0L;
  w = Array.make 64 0l;
}

let get_be_int32 (b : bytes) (offset : int) : int32 =
  let b0 = Int32.of_int (Char.code (Bytes.get b offset)) in
  let b1 = Int32.of_int (Char.code (Bytes.get b (offset + 1))) in
  let b2 = Int32.of_int (Char.code (Bytes.get b (offset + 2))) in
  let b3 = Int32.of_int (Char.code (Bytes.get b (offset + 3))) in
  (Int32.shift_left b0 24) |||
  (Int32.shift_left b1 16) |||
  (Int32.shift_left b2 8)  |||
  b3

let process_block (ctx : ctx) (block : bytes) (offset : int) : unit =
  let w = ctx.w in
  for t = 0 to 15 do
    w.(t) <- get_be_int32 block (offset + (t * 4))
  done;
  for t = 16 to 63 do
    let s0 = small_sigma0 w.(t - 15) in
    let s1 = small_sigma1 w.(t - 2) in
    w.(t) <- s1 +++ w.(t - 7) +++ s0 +++ w.(t - 16)
  done;

  let a = ref ctx.state.(0) in
  let b = ref ctx.state.(1) in
  let c = ref ctx.state.(2) in
  let d = ref ctx.state.(3) in
  let e = ref ctx.state.(4) in
  let f = ref ctx.state.(5) in
  let g = ref ctx.state.(6) in
  let h = ref ctx.state.(7) in

  for t = 0 to 63 do
    let t1 = !h +++ big_sigma1 !e +++ ch !e !f !g +++ k.(t) +++ w.(t) in
    let t2 = big_sigma0 !a +++ maj !a !b !c in
    h := !g;
    g := !f;
    f := !e;
    e := !d +++ t1;
    d := !c;
    c := !b;
    b := !a;
    a := t1 +++ t2
  done;

  ctx.state.(0) <- ctx.state.(0) +++ !a;
  ctx.state.(1) <- ctx.state.(1) +++ !b;
  ctx.state.(2) <- ctx.state.(2) +++ !c;
  ctx.state.(3) <- ctx.state.(3) +++ !d;
  ctx.state.(4) <- ctx.state.(4) +++ !e;
  ctx.state.(5) <- ctx.state.(5) +++ !f;
  ctx.state.(6) <- ctx.state.(6) +++ !g;
  ctx.state.(7) <- ctx.state.(7) +++ !h

let update_bytes (ctx : ctx) (data : bytes) (pos : int) (len : int) : unit =
  ctx.total_bytes <- Int64.add ctx.total_bytes (Int64.of_int len);
  let current_pos = ref pos in
  let remaining = ref len in

  if ctx.buf_len > 0 then (
    let needed = 64 - ctx.buf_len in
    if !remaining >= needed then (
      Bytes.blit data !current_pos ctx.buffer ctx.buf_len needed;
      process_block ctx ctx.buffer 0;
      ctx.buf_len <- 0;
      current_pos := !current_pos + needed;
      remaining := !remaining - needed
    ) else (
      Bytes.blit data !current_pos ctx.buffer ctx.buf_len !remaining;
      ctx.buf_len <- ctx.buf_len + !remaining;
      remaining := 0
    )
  );

  while !remaining >= 64 do
    process_block ctx data !current_pos;
    current_pos := !current_pos + 64;
    remaining := !remaining - 64
  done;

  if !remaining > 0 then (
    Bytes.blit data !current_pos ctx.buffer 0 !remaining;
    ctx.buf_len <- !remaining
  )

let update_string (ctx : ctx) (s : string) : unit =
  let b = Bytes.of_string s in
  update_bytes ctx b 0 (Bytes.length b)

let finalize_bytes (ctx : ctx) : bytes =
  let bit_len = Int64.mul ctx.total_bytes 8L in
  Bytes.set ctx.buffer ctx.buf_len '\x80';
  ctx.buf_len <- ctx.buf_len + 1;

  if ctx.buf_len > 56 then (
    Bytes.fill ctx.buffer ctx.buf_len (64 - ctx.buf_len) '\x00';
    process_block ctx ctx.buffer 0;
    Bytes.fill ctx.buffer 0 56 '\x00'
  ) else (
    Bytes.fill ctx.buffer ctx.buf_len (56 - ctx.buf_len) '\x00'
  );

  for i = 0 to 7 do
    let shift = (7 - i) * 8 in
    let byte_val = Int64.to_int (Int64.logand (Int64.shift_right_logical bit_len shift) 0xFFL) in
    Bytes.set ctx.buffer (56 + i) (Char.chr byte_val)
  done;
  process_block ctx ctx.buffer 0;

  let out = Bytes.create 32 in
  for i = 0 to 7 do
    let word = ctx.state.(i) in
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

let finalize_hex (ctx : ctx) : string =
  let digest_bytes = finalize_bytes ctx in
  let buf = Buffer.create 64 in
  for i = 0 to 31 do
    let byte_val = Char.code (Bytes.get digest_bytes i) in
    Buffer.add_string buf (Printf.sprintf "%02x" byte_val)
  done;
  Buffer.contents buf

let sha256_bytes (b : bytes) : bytes =
  let ctx = init () in
  update_bytes ctx b 0 (Bytes.length b);
  finalize_bytes ctx

let sha256_string (s : string) : string =
  let ctx = init () in
  update_string ctx s;
  finalize_hex ctx

let sha256_digest (s : string) : string =
  sha256_string s

let sha256_channel (ic : in_channel) : string =
  let ctx = init () in
  let buf = Bytes.create 4096 in
  let rec loop () =
    let n = input ic buf 0 4096 in
    if n > 0 then (
      update_bytes ctx buf 0 n;
      loop ()
    )
  in
  loop ();
  finalize_hex ctx

let sha256_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect (fun () -> sha256_channel ic) ~finally:(fun () -> close_in ic)
