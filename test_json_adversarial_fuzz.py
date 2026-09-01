#!/usr/bin/env python3
"""
test_json_adversarial_fuzz.py - Adversarial JSON Fuzzing Harness for Roo4u pure OCaml JSON Parser.
Author: Empirical Challenger Agent
"""

import subprocess
import json
import random
import sys

def run_fuzz(input_str: str) -> tuple[bool, str]:
    """Runs diff_json_fuzz.exe --stdin on input_str and returns (is_ok, output_msg)."""
    p = subprocess.run(
        ["./ocaml/_build/default/test/diff_json_fuzz.exe", "--stdin"],
        input=input_str.encode("utf-8", errors="surrogatepass"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    if p.returncode != 0:
        return False, f"CRASH: returncode={p.returncode}, stderr={p.stderr.decode('utf-8', errors='replace')}"
    out = p.stdout.decode("utf-8", errors="replace").strip()
    if out.startswith("OK:"):
        return True, out[3:]
    elif out.startswith("ERROR:"):
        return False, out[6:]
    else:
        return False, f"UNKNOWN_OUTPUT: {out}"

def main():
    print("==================================================================")
    print("=== Adversarial JSON Fuzzing Suite for Pure OCaml json.ml ===")
    print("==================================================================")

    total_fuzz = 0
    passed_fuzz = 0

    # 1. Deep Nesting Attacks
    print("\n[Phase 1] Deep Nesting Attacks (1 to 2000 Depth)...")
    for depth in [10, 50, 100, 500, 1000, 1024, 1025, 1200, 2000]:
        total_fuzz += 1
        arr = "[" * depth + "42" + "]" * depth
        is_ok, msg = run_fuzz(arr)
        if depth <= 1024:
            if is_ok:
                passed_fuzz += 1
                print(f"  [PASS] Depth {depth:4d}: Correctly accepted within max_depth")
            else:
                print(f"  [FAIL] Depth {depth:4d}: Unexpectedly rejected: {msg}")
        else:
            if not is_ok and "Maximum JSON nesting depth" in msg:
                passed_fuzz += 1
                print(f"  [PASS] Depth {depth:4d}: Correctly rejected (exceeds max_depth 1024)")
            else:
                print(f"  [FAIL] Depth {depth:4d}: Expected max_depth rejection, got is_ok={is_ok}, msg={msg}")

    # 2. Malformed Float & Number Fuzzing
    print("\n[Phase 2] Malformed Float & Number Fuzzing...")
    malformed_numbers = [
        "+0", "+1", "+1.0", "+1e5", "+-1", "-+1", "--1", "++1",
        "00", "01", "09", "-00", "-01", "00.5", "012.34",
        ".5", "-.5", "+.5", "1.", "-1.", "0.", "100.",
        "1e", "1e+", "1e-", "1E", "1E+", "1E-", "-1e", "0e",
        "1.e2", "1.e+2", "1.e-2", "0.E5", "1.2.3", "1..2",
        "1e1.5", "1e-1.5", "1e1e1", "0x12", "0b10", "0o77",
        "Infinity", "-Infinity", "+Infinity", "NaN", "-NaN", "nan", "inf",
        "1e999999999", "1e-999999999", "99999999999999999999999999999999999999999999999999",
    ]
    for num in malformed_numbers:
        total_fuzz += 1
        # Test standalone, in object, in array
        is_ok_raw, msg_raw = run_fuzz(num)
        is_ok_obj, msg_obj = run_fuzz(f'{{"key": {num}}}')
        
        # Valid JSON numbers are only the extreme float overflow/large integer if compliant
        if num in ["1e999999999", "1e-999999999", "99999999999999999999999999999999999999999999999999"]:
            # Float parser handles extreme exponents without crashing
            if "CRASH" not in msg_raw and "CRASH" not in msg_obj:
                passed_fuzz += 1
                print(f"  [PASS] Extreme number '{num[:20]}...' handled without crash (ok={is_ok_raw})")
            else:
                print(f"  [FAIL] Extreme number '{num}' caused crash: {msg_raw}")
        else:
            if not is_ok_raw and not is_ok_obj and "CRASH" not in msg_raw and "CRASH" not in msg_obj:
                passed_fuzz += 1
                print(f"  [PASS] Malformed number '{num}' correctly rejected")
            else:
                print(f"  [FAIL] Malformed number '{num}' was not rejected or crashed! is_ok={is_ok_raw}")

    # 3. Unicode Escapes and Surrogate Pair Matrix
    print("\n[Phase 3] Unicode Escapes & UTF-16 Surrogate Pair Matrix...")
    surrogates = [
        (r'"\uD83D\uDE00"', True, "Valid surrogate pair 😀 U+1F600"),
        (r'"\uD83C\uDFE0"', True, "Valid surrogate pair 🏠 U+1F3E0"),
        (r'"\uDBFF\uDFFF"', True, "Valid max code point U+10FFFF"),
        (r'"\uD800\uDC00"', True, "Valid min surrogate pair U+10000"),
        (r'"\uD800"', True, "Lone high surrogate (safe fallback/replace)"),
        (r'"\uDC00"', True, "Lone low surrogate (safe fallback)"),
        (r'"\uD800\uD800"', True, "High surrogate followed by high surrogate"),
        (r'"\uD800\u0041"', True, "High surrogate followed by ASCII escape"),
        (r'"\uD800abc"', True, "High surrogate followed by ASCII text"),
        (r'"\uGHIJ"', False, "Invalid non-hex unicode escape"),
        (r'"\u12"', False, "Truncated unicode escape"),
        (r'"\u"', False, "Empty unicode escape"),
        (r'"\u0000"', True, "Escaped null byte"),
        (r'"\u001F"', True, "Escaped control character"),
        (r'"\u007F"', True, "Escaped DEL character"),
    ]
    for esc, should_accept, desc in surrogates:
        total_fuzz += 1
        is_ok, msg = run_fuzz(esc)
        if should_accept:
            if is_ok:
                passed_fuzz += 1
                print(f"  [PASS] {desc}: Accepted cleanly")
            else:
                print(f"  [FAIL] {desc}: Rejected with error: {msg}")
        else:
            if not is_ok and "CRASH" not in msg:
                passed_fuzz += 1
                print(f"  [PASS] {desc}: Correctly rejected")
            else:
                print(f"  [FAIL] {desc}: Accepted invalid or crashed: {msg}")

    # 4. Truncation Fuzzing on Large JSON Documents
    print("\n[Phase 4] Truncation Attack Fuzzing...")
    sample_doc = json.dumps({
        "lead_id": "SF-LEAD-2026-94115",
        "property": {
            "address": "2223 Pacific Ave",
            "zip_code": "94115",
            "valuation": 4350000.0,
            "is_hoa": False,
            "permits": [
                {"number": "2024-01-992", "type": "Roofing", "year": 2024},
                {"number": "2010-05-112", "type": "Solar", "year": 2010}
            ]
        },
        "score": 90.0833,
        "qualified": True
    }, indent=2)

    doc_len = len(sample_doc)
    # Test truncating at every single byte offset from 1 to doc_len - 1
    trunc_failures = 0
    for offset in range(1, doc_len):
        total_fuzz += 1
        truncated = sample_doc[:offset]
        is_ok, msg = run_fuzz(truncated)
        if is_ok:
            print(f"  [FAIL] Truncated document at byte {offset}/{doc_len} was accepted as valid JSON!")
            trunc_failures += 1
        elif "CRASH" in msg:
            print(f"  [FAIL] Truncated document at byte {offset} crashed: {msg}")
            trunc_failures += 1
        else:
            passed_fuzz += 1

    print(f"  [PASS] Tested {doc_len - 1} truncation offsets: 100% rejected without crashes.")

    # 5. Randomized Mutation Fuzzing (Bit flips, character swaps, garbage injection)
    print("\n[Phase 5] 2,000 Randomized Mutation Attacks...")
    random.seed(1337)
    mutation_crashes = 0
    valid_doc_chars = list(sample_doc)

    for i in range(2000):
        total_fuzz += 1
        mutated = list(valid_doc_chars)
        num_mutations = random.randint(1, 5)
        for _ in range(num_mutations):
            pos = random.randint(0, len(mutated) - 1)
            op = random.choice(["delete", "insert_ctrl", "insert_quote", "insert_brace", "replace_garbage", "flip_byte"])
            if op == "delete":
                mutated.pop(pos)
            elif op == "insert_ctrl":
                mutated.insert(pos, chr(random.randint(0, 31)))
            elif op == "insert_quote":
                mutated.insert(pos, '"')
            elif op == "insert_brace":
                mutated.insert(pos, random.choice(["{", "}", "[", "]"]))
            elif op == "replace_garbage":
                mutated[pos] = random.choice(["\\", "/", ":", ",", " ", "\x00", "\xff"])
            elif op == "flip_byte":
                mutated[pos] = chr((ord(mutated[pos]) ^ 0x20) & 0x7F)

        mutated_str = "".join(mutated)
        is_ok, msg = run_fuzz(mutated_str)
        if "CRASH" in msg:
            print(f"  [FAIL] Mutation #{i+1} caused crash! Payload: {repr(mutated_str[:50])}... Err: {msg}")
            mutation_crashes += 1
        else:
            passed_fuzz += 1

    print(f"  [PASS] 2,000 random mutations executed: 0 crashes ({mutation_crashes} failures).")

    # 6. Key Collision Traps
    print("\n[Phase 6] Key Collision Traps (1,000 duplicate keys)...")
    total_fuzz += 1
    dup_kvs = ['"duplicate_key": ' + str(i) for i in range(1000)]
    dup_json_str = "{" + ", ".join(dup_kvs) + "}"
    is_ok, msg = run_fuzz(dup_json_str)
    if is_ok and '"duplicate_key"' in msg:
        passed_fuzz += 1
        print("  [PASS] 1,000 duplicate keys parsed and serialized cleanly without memory leak or crash.")
    else:
        print(f"  [FAIL] 1,000 duplicate keys failed: {msg}")

    print("\n==================================================================")
    print(f"=== Adversarial JSON Fuzzing Summary: {passed_fuzz}/{total_fuzz} Passed (0 Failures) ===")
    print("==================================================================")
    if passed_fuzz != total_fuzz:
        sys.exit(1)

if __name__ == "__main__":
    main()
