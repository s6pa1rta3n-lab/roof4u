#!/usr/bin/env python3
"""
diff_test_hashlib.py - Independent Differential Testing of Pure OCaml SHA-256 Engine vs Python hashlib.
Author: Empirical Challenger Agent
"""

import subprocess
import hashlib
import sys
import random

def main():
    print("==================================================================")
    print("=== Python hashlib vs Pure OCaml SHA-256 Differential Harness ===")
    print("==================================================================")

    # 1. Run diff_sha256_gen.exe to get all 8193 digests
    cmd = ["./ocaml/_build/default/test/diff_sha256_gen.exe"]
    print(f"Executing: {' '.join(cmd)}")
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)

    lines = proc.stdout.strip().split("\n")
    print(f"Received {len(lines)} outputs from OCaml SHA-256 engine.")

    assert len(lines) == 8193, f"Expected 8193 lines, got {len(lines)}"

    mismatches = 0
    for line in lines:
        if not line:
            continue
        len_str, ocaml_hash = line.split(":")
        length = int(len_str)

        # Generate exact byte array in Python
        py_bytes = bytes([(i * 31 + 17) & 0xFF for i in range(length)])
        py_hash = hashlib.sha256(py_bytes).hexdigest()

        if ocaml_hash != py_hash:
            print(f"[FAIL] Mismatch at length {length}!\n  OCaml:  {ocaml_hash}\n  Python: {py_hash}")
            mismatches += 1
            if mismatches > 10:
                print("Too many mismatches, aborting...")
                sys.exit(1)

    if mismatches == 0:
        print(f"[PASS] 100% Differential Match across all 8,193 lengths (0 to 8192 bytes)!")
    else:
        print(f"[FAIL] {mismatches} mismatches found!")
        sys.exit(1)

    # 2. Additional NIST & Extreme Vectors via Stdin Pipe
    test_vectors = [
        b"",
        b"a",
        b"abc",
        b"message digest",
        b"abcdefghijklmnopqrstuvwxyz",
        b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        b"The quick brown fox jumps over the lazy dog",
        b"The quick brown fox jumps over the lazy cog",
        b"\x00" * 55,
        b"\x00" * 56,
        b"\x00" * 64,
        b"\xff" * 55,
        b"\xff" * 56,
        b"\xff" * 64,
        b"\x55" * 128,
        b"\xAA" * 128,
        b"A" * 1000000, # 1MB NIST vector
    ]

    # Add 100 random byte strings with variable lengths up to 65536 bytes
    random.seed(42)
    for _ in range(100):
        rlen = random.randint(0, 65536)
        rbytes = random.randbytes(rlen)
        test_vectors.append(rbytes)

    print(f"\n--- Testing {len(test_vectors)} Custom & Random Edge Vectors via Stdin ---")
    edge_mismatches = 0
    for idx, vec in enumerate(test_vectors):
        py_digest = hashlib.sha256(vec).hexdigest()
        
        p = subprocess.run(
            ["./ocaml/_build/default/test/diff_sha256_gen.exe", "--stdin"],
            input=vec,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        ocaml_digest = p.stdout.decode("ascii").strip()
        if ocaml_digest != py_digest:
            print(f"  [FAIL] Vector #{idx+1} (len={len(vec)}): OCaml {ocaml_digest} != Python {py_digest}")
            edge_mismatches += 1
        else:
            if idx < 17 or idx % 20 == 0:
                print(f"  [PASS] Vector #{idx+1} (length {len(vec):6d} bytes): SHA-256 match {ocaml_digest[:16]}...")

    if edge_mismatches == 0:
        print(f"\n[PASS] All {len(test_vectors)} edge & random vectors matched hashlib perfectly!")
    else:
        print(f"\n[FAIL] {edge_mismatches} edge vector mismatches!")
        sys.exit(1)

    print("\n==================================================================")
    print("=== Differential Verification Summary: 8,310/8,310 Passed (0 Failures) ===")
    print("==================================================================")

if __name__ == "__main__":
    main()
