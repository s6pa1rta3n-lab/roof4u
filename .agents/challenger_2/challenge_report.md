# Empirical Challenge Report: Cryptographic Proofs, Determinism, and State Machine Transitions

**Challenger**: Challenger 2 (Empirical Adversarial Reviewer)
**Target**: Roo4u Pure OCaml Engine across Sunset (94122), Richmond (94118), Excelsior (94112), and Pacific Heights (94115)
**Date**: 2026-09-02
**Verdict**: APPROVE

---

## Challenge Summary

**Overall risk assessment**: LOW

All empirical challenge tests for cryptographic proof formatting, hash determinism, avalanche bitflip sensitivity, cross-district non-malleability, zero collision resistance, and SQLite state machine transitions executed and passed with 100% success rate across all four San Francisco target districts.

---

## Challenges

### [Low] Challenge 1: Canonical Payload Score Precision Rounding Sensitivity

- **Assumption challenged**: That any sub-dollar change in property estimated value immediately alters the canonical cryptographic proof hash.
- **Attack scenario**: When property assessed value changes slightly (for instance, a $50 valuation delta on a $1.65M property), the continuous actionability score $S(L)$ changes by $0.00025$ points. Because the canonical proof payload formats score at two decimal places (`%.2f`), minor floating point deltas under $0.005$ points produce the identical canonical string `ROO4U-PROOF-V1|...|72.58|...`.
- **Blast radius**: Two lead records with identical physical/temporal properties and differing only by negligible valuation changes (< $1,000) produce identical proof hashes if evaluated at the same timestamp.
- **Mitigation**: This behavior is by design per the RFC proof specification, where score is discretized to 2 decimal places to ensure stable proof verification across floating-point engines. Significant valuation changes altering score by $\ge 0.01$ immediately produce distinct hashes.
- **Status**: Verified and accepted as compliant with specification.

### [Low] Challenge 2: Delimiter Injection in Unsanitized Address Strings

- **Assumption challenged**: An address containing pipe characters (`|`) could forge payload field boundaries to collide with another valid lead payload.
- **Attack scenario**: Injecting an address like `"100 California St|94122"` into a lead with zip `"94118"`.
- **Blast radius**: If field counts or delimiters were improperly parsed, a malicious lead could mimic the hash of a legitimate lead in another zip code.
- **Mitigation**: Field count assertion and fixed 8-field structure prevent spoofing. Cryptographic SHA-256 digest over the literal payload bytes produces completely distinct hashes (`v_del1 <> v_del2`).
- **Status**: Tested and verified secure.

---

## Stress Test Results

| Test Suite / Scenario | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|
| **Proof Format & Grammar (94122, 94118, 94112, 94115)** | Strict 8-field `ROO4U-PROOF-V1` payload, 64-char lowercase hex digest, `PROOF-OCAML-<16 HEX>` ID prefix | All 12 seed leads and control disqualified leads adhere to grammar | PASS |
| **Digest Determinism (500 Iterations)** | 500 identical executions on identical input produce identical SHA-256 and proof ID | 500/500 matches with zero drift | PASS |
| **Address Mutation Avalanche (1 char change)** | Single character address change produces distinct hash with 30-70% bitflip rate | Hamming distance = 129/256 (50.4% bitflip) | PASS |
| **Address Case Mutation Avalanche** | Lowercase address mutation produces distinct hash with 30-70% bitflip rate | Hamming distance = 115/256 (44.9% bitflip) | PASS |
| **District Zip Mutation Avalanche (94122 -> 94118/94112/94115)** | Single zip code mutation produces distinct hash with 30-70% bitflip rate | Hamming distances = 127, 125, 122 (47.7% - 49.6% bitflip) | PASS |
| **Roof Type Mutation Avalanche (Victorian -> Flat/Mansard)** | Roof type change produces distinct hash with 30-70% bitflip rate | Hamming distances = 136, 130 (50.8% - 53.1% bitflip) | PASS |
| **Property Type Mutation Avalanche (SFR -> MultiUnit)** | Property type change produces distinct hash with 30-70% bitflip rate | Hamming distance = 127 (49.6% bitflip) | PASS |
| **Timestamp Mutation Avalanche (1s / 1min flip)** | 1-second or 1-minute timestamp adjustment produces distinct hash | Hamming distances = 136, 137 (53.1% - 53.5% bitflip) | PASS |
| **Score Mutation Avalanche (Delta $\ge 0.01$)** | Score change alters `%.2f` field and produces distinct hash | Hamming distance = 118 (46.1% bitflip) | PASS |
| **Cross-District Collision Resistance (1,008 Leads)** | 1,008 synthetic permutations across 4 districts produce zero hash/ID collisions | Exactly 0 collisions across 1,008 leads (1,008 unique IDs) | PASS |
| **Pipe Delimiter Injection** | Delimiter in address cannot forge digest of natural split | `sha256_proof` differs completely | PASS |
| **SQLite State Progression (DISCOVERED -> ENRICHED -> VALIDATED -> DISQUALIFIED -> DISCARDED)** | Sequential transitions correctly update status in memory and SQLite disk storage | All transitions succeed and persist | PASS |
| **SQLite Duplicate Address Rejection** | Re-inserting existing address returns Error | Error returned; table integrity preserved | PASS |
| **SQLite Multi-Threaded Concurrency (10 threads, 200 leads)** | Concurrent upserts and status updates under Mutex complete with 0 errors | 0 errors; count reaches $\ge 200$ | PASS |
| **End-to-End Pipeline State Verification** | Full pipeline marks 12 qualified leads as `VALIDATED` in DB and exports 12 rows to CSV | 12 discovered, 12 enriched, 12 validated, 12 exported | PASS |
| **District Quota Distribution in DB** | SQLite contains $\ge 3$ VALIDATED leads for each of 94122, 94118, 94112, 94115 | All 4 districts have $\ge 3$ VALIDATED leads | PASS |

---

## Unchallenged Areas

- Live external SODA API network connectivity: Out of scope per offline testbed constraints; fallback municipal microservices and synthetic seed datasets were tested instead.
- Proprietary GPU hardware acceleration: OCaml engine relies on pure CPU standard library implementation.
