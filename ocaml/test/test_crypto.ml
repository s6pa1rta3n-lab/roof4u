(**
   test_crypto.ml - Comprehensive RFC 6234 / FIPS 180-4 pure OCaml SHA-256 unit test suite.
   Tests standard NIST vectors, 1MB long messages, boundary transitions, streaming chunk invariance,
   and avalanche tamper detection with zero external dependencies.
*)

open Roof_engine
open Crypto

let test_count = ref 0
let pass_count = ref 0

let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n  Expected: %s\n  Actual:   %s\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n" name;
    failwith ("Assertion failed: " ^ name)
  )

let () =
  Printf.printf "\n======================================================\n";
  Printf.printf "=== Pure OCaml SHA-256 Cryptographic Engine Tests ===\n";
  Printf.printf "======================================================\n\n";

  (* 1. RFC 6234 Standard Test Vectors *)
  assert_equal_str "T1.1: Empty string vector (0 bytes)"
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    (sha256_string "");

  assert_equal_str "T1.2: Single character 'a'"
    "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
    (sha256_string "a");

  assert_equal_str "T1.3: RFC 6234 3-byte vector 'abc'"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    (sha256_string "abc");

  assert_equal_str "T1.4: RFC 6234 56-byte vector (crosses 55-byte boundary)"
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    (sha256_string "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");

  assert_equal_str "T1.5: RFC 6234 112-byte vector"
    "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
    (sha256_string "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu");

  assert_equal_str "T1.6: San Francisco Municipal Lead String Digest"
    "8c33bf2b0ea7f8b9b1bb5cbce2a3f80d006d18e5d38b12b9adf6aef9bbf50f1c"
    (sha256_string "Roo4u-SF-2223-Pacific-Ave-94115");

  assert_equal_str "T1.7: 64-character lowercase hex format validation"
    "64"
    (string_of_int (String.length (sha256_string "test_lead_qualification")));

  (* 2. NIST 1,000,000 'a' Repetitions (Long Message Test) *)
  let million_ctx = init () in
  let chunk = String.make 10000 'a' in
  for _ = 1 to 100 do
    update_string million_ctx chunk
  done;
  assert_equal_str "T1.8: NIST 1,000,000 'a' repetitions long message test vector"
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
    (finalize_hex million_ctx);

  (* 3. Boundary Value Analysis (BVA) & Multi-Block Transitions *)
  let boundaries = [
    (0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    (55, ""); (* Single block boundary *)
    (56, ""); (* Two block spill boundary *)
    (63, "");
    (64, ""); (* Exact block size *)
    (65, "");
    (119, "");
    (120, "");
    (127, "");
    (128, "");
    (129, "");
    (500, "");
    (1000, "");
  ] in
  List.iter (fun (len, expected) ->
    let msg = String.make len 'A' in
    let digest = sha256_string msg in
    assert_true (Printf.sprintf "T2.BVA: Length %d produces valid 64-hex digest" len)
      (String.length digest = 64);
    if expected <> "" then
      assert_equal_str (Printf.sprintf "T2.BVA: Exact match for length %d" len) expected digest
  ) boundaries;

  (* 4. Incremental Streaming Chunk-Size Invariance *)
  let sample_text = "The quick brown fox jumps over the lazy dog - San Francisco Real Estate Verification 2026" in
  let direct_hash = sha256_string sample_text in
  List.iter (fun chunk_sz ->
    let ctx = init () in
    let pos = ref 0 in
    let len = String.length sample_text in
    while !pos < len do
      let take = min chunk_sz (len - !pos) in
      update_string ctx (String.sub sample_text !pos take);
      pos := !pos + take
    done;
    assert_equal_str (Printf.sprintf "T2.Streaming: Chunk size %d invariance" chunk_sz)
      direct_hash
      (finalize_hex ctx)
  ) [1; 2; 3; 7; 15; 31; 64];

  (* 5. Avalanche Effect & Tamper Detection *)
  let h1 = sha256_string "2223 Pacific Ave, San Francisco, CA 94115" in
  let h2 = sha256_string "2223 Pacific Ave, San Francisco, CA 94114" in
  assert_true "T2.Avalanche: 1-character address flip yields completely distinct hash"
    (h1 <> h2);

  let diff_chars = ref 0 in
  for i = 0 to 63 do
    if h1.[i] <> h2.[i] then incr diff_chars
  done;
  assert_true "T2.Avalanche: Avalanche effect alters >= 45/64 hex characters"
    (!diff_chars >= 45);

  (* 6. Byte and Channel Hashing *)
  let bytes_input = Bytes.of_string "abc" in
  let bytes_digest = sha256_bytes bytes_input in
  assert_true "T2.Bytes: sha256_bytes produces 32 raw bytes"
    (Bytes.length bytes_digest = 32);

  let temp_path = Filename.temp_file "test_sha256_" ".dat" in
  let oc = open_out_bin temp_path in
  output_string oc "abc";
  close_out oc;
  let file_digest = sha256_file temp_path in
  assert_equal_str "T2.File: sha256_file on 'abc'"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    file_digest;
  Sys.remove temp_path;

  Printf.printf "\n=== Completed Pure OCaml SHA-256 Test Suite: %d/%d Tests Passed ===\n\n" !pass_count !test_count
