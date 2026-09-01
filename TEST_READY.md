# TEST_READY: 4-Tier Opaque-Box E2E Test Suite Specification

> **Project**: Roo4u Pure OCaml Real Estate Qualification Engine  
> **Status**: APPROVED & PUBLISHED  
> **Integrity Mode**: Benchmark / Red-Team Strict Non-Mock  
> **Test Harness**: Dune Native Test Runner (`dune runtest`)  
> **Total Test Target**: >= 192 Test Cases across 4 Tiers  

---

## 1. Test Suite Architecture & Philosophy

The Roo4u test harness enforces strict opaque-box testing derived directly from `ORIGINAL_REQUEST.md`, `PROJECT.md`, and municipal San Francisco real estate qualification constraints.

- **Zero-Mock Red Team Standard**: No mock objects, monkeypatching, or simulated APIs. Every test runs against genuine RFC-compliant cryptography, AST JSON parsers, deterministic vector embedding algorithms, and municipal schemas.
- **Progressive Testability**: Modular OCaml test executables under `ocaml/test/` built and executed via Dune.
- **Formal Invariant Verification**: Exhaustive verification of INV1 (Physical), INV2 (Temporal), INV3 (Economic), and INV4 (Permit Non-Conflict).

```
ocaml/test/
├── test_crypto.ml         # Tier 1 & 2: RFC 6234 / FIPS 180-4 SHA-256 Test Vectors & Avalanche
├── test_json.ml           # Tier 1 & 2: AST JSON Parser, Escape Sequences & Syntax Traps
├── test_invariants.ml     # Tier 1, 2 & 3: INV1-4 Algebraic Proofs & Scoring Monotonicity
├── test_memory.ml         # Tier 1, 2 & 3: Atomic Lockf Store, 256-D Feature Hashing & Vector Search
├── test_connectors.ml     # Tier 1, 2 & 3: DataSF SODA Connector, Date Normalizer & Local LLM
├── test_security.ml       # Tier 1, 2 & 3: Adversarial SoQL Injection, CSV DDE & Path Traversal
├── test_e2e_pipeline.ml   # Tier 4: Real-World SF Neighborhood Pipelines & CSV Parity
└── test_verif.ml          # Mathematical Verification Harness
```

---

## 2. Feature Inventory & Coverage Mapping

| # | Feature | Milestone | Tier 1 (Coverage) | Tier 2 (Boundaries) | Tier 3 (Pairwise) | Tier 4 (E2E) |
|---|---------|-----------|:-----------------:|:-------------------:|:-----------------:|:------------:|
| F1 | Cryptographic SHA-256 Engine | M1 | 5 | 7 | T3.1, T3.7, T3.15 | S1, S4, S5 |
| F2 | Recursive Descent JSON AST Parser | M1 | 12 | 8 | T3.2, T3.6, T3.16 | S1, S4 |
| F3 | Invariant Qualification Engine (INV1-4) | M1 | 17 | 7 | T3.1, T3.2, T3.3, T3.5, T3.9 | S1, S2, S5 |
| F4 | Deterministic Actionability Scoring | M1 | 4 | 2 | T3.1, T3.9, T3.14 | S1, S2, S5 |
| F5 | Atomic JSON Lesson Store (`Unix.lockf`) | M2 | 2 | 1 | T3.2, T3.7, T3.11 | S3 |
| F6 | 256-D Offline Feature Hashing | M2 | 3 | 3 | T3.3, T3.12 | S3 |
| F7 | Embedded Vector Store & Cosine Search | M2 | 3 | 2 | T3.3, T3.12 | S3 |
| F8 | SQLite Lead Database Persistence | M2 | 5 | 5 | T3.4, T3.13, T3.15 | S1, S2, S5 |
| F9 | DataSF SODA API Connectors (`i98e-djp9`, `tyz3-vt28`) | M3 | 4 | 2 | T3.5, T3.10 | S1, S2, S4 |
| F10 | Municipal PIM & DBI Scrapers & Normalizer | M3 | 4 | 2 | T3.5, T3.14 | S2 |
| F11 | Local LLM Client (`localhost:8000`) & Extractor | M3 | 2 | 2 | T3.6, T3.16 | S3 |
| F12 | Git Telemetry & Dual-Transport Issue Logger | M3 | 5 | 5 | T3.7, T3.12 | S3 |
| F13 | Core Pipeline Orchestrator CLI (`roof_pipeline`) | M4 | 5 | 5 | T3.4, T3.17 | S1, S2, S3, S5 |
| F14 | RFC 4180 CSV Lead Exporter (`validated_leads.csv`) | M4 | 5 | 5 | T3.8, T3.9, T3.13, T3.15 | S1, S2, S4, S5 |
| F15 | Python Legacy Safe Deprecation | M4 | 5 | 5 | T3.17 | S5 |
| F16 | Adversarial Security Vulnerability Closing | M5 | 16 | 10 | T3.8, T3.10, T3.11, T3.16 | S4 |
| F17 | Security Audit Formal Report (`security_audit.md`) | M5 | 5 | 5 | T3.17 | S4 |
| **Total** | **17 Core Features** | — | **>= 99 Tests** | **>= 72 Tests** | **17 Tests** | **5 Scenarios** |

---

## 3. Tier 1: Feature Coverage Test Matrix (85+ Target, 99+ Designed)

### Feature 1: Cryptographic SHA-256 Engine
- **T1.F1.1**: Standard NIST Empty String digest (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
- **T1.F1.2**: NIST Standard 3-byte vector `"abc"` (`ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`).
- **T1.F1.3**: NIST Standard 56-byte vector `"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"`.
- **T1.F1.4**: San Francisco Municipal Lead String Digest verification.
- **T1.F1.5**: 64-character lowercase hex encoding validation.

### Feature 2: Recursive Descent JSON AST Parser & Serializer
- **T1.F2.1**: Parse `Null` primitive.
- **T1.F2.2**: Parse `Bool true` and `Bool false`.
- **T1.F2.3**: Parse `Number` float and integer representations.
- **T1.F2.4**: Parse `String` literals with spaces and punctuation.
- **T1.F2.5**: Parse multi-field JSON object structure.
- **T1.F2.6 - T1.F2.10**: Typed AST getter extraction (`get_string`, `get_float`, `get_bool`, `get_int`).
- **T1.F2.11**: Extract array field from JSON object.
- **T1.F2.12**: Round-trip AST serialization to JSON string.

### Feature 3: Invariant Qualification Engine (INV1-4)
- **T1.F3.1 - T1.F3.6**: Physical Eligibility (INV1) validation for Victorian SFR, Flat 2-4 Unit, Mansard SFR; rejection for Gable, Commercial, MultiUnit 5+.
- **T1.F3.7 - T1.F3.10**: Temporal Degradation (INV2) validation for roof age 18.0 yrs, rejection for 10.0 yrs; fallback for construction year 1985 (>= 30 yrs) vs 2010.
- **T1.F3.11 - T1.F3.14**: Economic Viability (INV3) validation for $2.5M SFR non-HOA; rejection for < $1.0M, HOA condo, and rental.
- **T1.F3.15 - T1.F3.17**: Permit Recency Non-Conflict (INV4) validation for 2004 reroof (22 yrs ago), rejection for 2023 reroof (3 yrs ago); acceptance of 2024 electrical permit.

### Feature 4: Deterministic Actionability Scoring
- **T1.F4.1**: Maximum composite score is exactly 100.0.
- **T1.F4.2**: Age component reaches 40.0 points at 30-year threshold.
- **T1.F4.3**: Valuation component reaches 35.0 points at $5.0M valuation.
- **T1.F4.4**: Architectural type component yields 25.0 points for Victorian SFR.

### Feature 5: Atomic JSON Lesson Store
- **T1.F5.1**: Atomic write with temporary file and rename produces persistent file.
- **T1.F5.2**: File size verification confirms non-empty serialized content.

### Feature 6: 256-D Offline Feature Hashing
- **T1.F6.1**: Vector output has strictly 256 dimensions.
- **T1.F6.2**: L2 vector norm strictly equals 1.0 (unit hypersphere).
- **T1.F6.3**: Embedding generation is 100% deterministic on identical input strings.

### Feature 7: Embedded Vector Store & Cosine Search
- **T1.F7.1**: Search returns top-k nearest candidates.
- **T1.F7.2**: Top candidate matches semantic failure class.
- **T1.F7.3**: Top similarity score is strictly positive.

### Feature 9: DataSF SODA API Connectors
- **T1.F9.1**: Valid SODA query URL constructed for Building Permits (`i98e-djp9`).
- **T1.F9.2**: URL contains valid dataset endpoint identifier.
- **T1.F9.3**: URL contains postal code filter.
- **T1.F9.4**: Rejects invalid zip code formats.

### Feature 10: Municipal Scrapers & Date Normalizer
- **T1.F10.1**: Normalize ISO 8601 timestamps (`2023-05-18T00:00:00.000` -> `2023-05-18`).
- **T1.F10.2**: Normalize US Date format (`08/24/2005` -> `2005-08-24`).
- **T1.F10.3**: Classify `"Complete tear-off and reroof"` as roof replacement.
- **T1.F10.4**: Classify `"Install 200A solar inverter"` as non-roof replacement.

### Feature 11: Local LLM Client
- **T1.F11.1**: Formats OpenAI-compatible chat completion payload with system prompt.
- **T1.F11.2**: Strips markdown triple-backtick code fences from LLM responses.

### Feature 16: Adversarial Security Remediation
- **T1.F16.1 - T1.F16.4**: CSV DDE Formula Injection neutralization for `=`, `+`, `-`, `@`.
- **T1.F16.5**: RFC 4180 escaping with double-quote wrapping.
- **T1.F16.6 - T1.F16.9**: Path traversal rejection for `../../etc/passwd`, `/etc/shadow`, `.env`.
- **T1.F16.10 - T1.F16.13**: SoQL injection blocking for `' OR '1'='1`, `; DROP TABLE`, `-- comment`.
- **T1.F16.14 - T1.F16.16**: Cryptographic anti-mock validation (rejection of zero/dummy hashes).

---

## 4. Tier 2: Boundary Value Analysis & Negative Tests (85+ Target)

- **T2.F1.1**: 55-byte boundary (single block fill with padding).
- **T2.F1.2**: 56-byte boundary (two-block spill).
- **T2.F1.3**: 64-byte boundary (exact single block).
- **T2.F1.4**: 128-byte boundary (exact dual block).
- **T2.F1.5**: 1000-byte multi-block payload hash determinism.
- **T2.F1.6 - T2.F1.7**: Avalanche effect verification: 1-character flip alters >= 45/64 hex characters.
- **T2.F2.1**: Parse empty JSON object `{}`.
- **T2.F2.2**: Parse empty JSON array `[]`.
- **T2.F2.3**: Parse deeply nested arrays (5 levels).
- **T2.F2.4**: Parse escaped control characters (`\n`, `\t`).
- **T2.F2.5 - T2.F2.7**: Syntax error detection on unclosed objects, trailing commas, garbage input.
- **T2.F2.8**: Parse negative exponent scientific notation (`-1.25e-3`).
- **T2.F3.1 - T2.F3.2**: Roof age boundary: exact 15.0 yrs (PASS) vs 14.999 yrs (FAIL).
- **T2.F3.3 - T2.F3.4**: Construction year boundary: 1996 (PASS: age 30) vs 1997 (FAIL: age 29).
- **T2.F3.5 - T2.F3.7**: Economic valuation boundary: $1,000,000.00 (PASS) vs $999,999.99 (FAIL) vs `None` (FAIL).
- **T2.F4.1 - T2.F4.2**: Scoring monotonicity and baseline minimum verification.
- **T2.F6.1 - T2.F6.3**: Zero vector handling on empty string, zero cosine similarity, 500-word norm verification.
- **T2.F9.1 - T2.F9.2**: SQL injection in zip code parameter rejected; upper bound query limit clamped to 1000.

---

## 5. Tier 3: Pairwise Cross-Feature Integration Matrix (17 Combinations)

1. **T3.1 (F1 + F3 + F4)**: Qualified prime Victorian lead computes score > 85.0 and SHA-256 proof.
2. **T3.2 (F3 + F4)**: Conflicting permit generates DISQUALIFIED verdict with retained partial score.
3. **T3.3 (F6 + F7)**: 256-D feature hashing accurately clusters rate limit failure fingerprints in Vector Store.
4. **T3.4 (F8 + F13)**: Ingest 20 discovered leads, transition 10 to validated, query by status.
5. **T3.5 (F9 + F10 + F3)**: Ingest raw SODA permit json, normalize date, classify roof replacement, verify INV4.
6. **T3.6 (F11 + F2)**: Format local LLM prompt, parse returned structured JSON lead AST.
7. **T3.7 (F12 + F1 + F5)**: Capture scraping failure, compute SHA-256 fingerprint, upsert atomic lesson.
8. **T3.8 (F14 + F16)**: Export lead containing malicious formula injection strings safely to RFC 4180 CSV.
9. **T3.9 (F3 + F4 + F14)**: Full qualification to CSV row formatting with actionability score.
10. **T3.10 (F9 + F16)**: SODA parameter query builder enforces strict whitelisting against SoQL injection.
11. **T3.11 (F5 + F16)**: Lesson store file path validator rejects directory traversal attacks.
12. **T3.12 (F6 + F12 + F7)**: Offline telemetry issue clustering via vector similarity search.
13. **T3.13 (F8 + F14)**: Stream validated leads from database into sanitized CSV export.
14. **T3.14 (F10 + F4)**: Parse complex multi-permit history to accurately determine effective roof age.
15. **T3.15 (F1 + F8 + F14)**: End-to-end cryptographic proof tamper detection across storage and export.
16. **T3.16 (F2 + F11 + F16)**: Handle malformed or adversarial LLM responses safely with syntax error traps.
17. **T3.17 (F13 + F15 + F17)**: Pure OCaml binary execution verifies zero Python dependencies and security compliance.

---

## 6. Tier 4: Real-World Application Scenarios (5 Comprehensive Workloads)

### Scenario 1: Pacific Heights Victorian Acquisition (`94115`)
- **Profile**: 1895 Queen Anne Victorian on Pacific Ave, assessed value $4.35M, roof age 28 yrs, last permit 1998.
- **Workflow**: SODA Discovery -> DBI Permits -> Invariant Proofs (INV1-4) -> Actionability Score (96.5) -> Qualified Verdict -> Digital Proof -> JSON/CSV Export.
- **Outcome**: `QUALIFIED`, Score = 96.5, Proof generated.

### Scenario 2: Marina & Cow Hollow Flat Roof Multi-Unit (`94123`)
- **Profile**: 1932 2-unit flat roof structure on Chestnut St, assessed value $2.75M, roof age 20 yrs, last permit 2006.
- **Workflow**: Multi-Unit Ingestion -> Flat Roof Classification -> INV1-4 Verification -> Actionability Score (68.4) -> Qualified Verdict.
- **Outcome**: `QUALIFIED`, Score = 68.4.

### Scenario 3: Self-Healing Closed Loop with Induced Scraping Drift
- **Profile**: Simulated HTTP 403 / DOM change on SF DBI parser.
- **Workflow**: Error Trapping -> SHA-256 Fingerprint -> Vector Match Workaround -> Issue Queued -> Success Counter Incremented.
- **Outcome**: Resolved via closed-loop learning.

### Scenario 4: Adversarial Fuzzing & Malicious Injection Ingestion
- **Profile**: Lead batch containing DDE payloads (`=cmd|' /C calc'!A0`), SQL injection (`' OR 1=1--`), XSS strings, path traversal (`../../etc/passwd`), spoofed hashes.
- **Workflow**: Security Sanitization -> Safe AST Parsing -> Formula Neutralization -> Rejection of Invalid Data.
- **Outcome**: 100% neutralized, zero crashes, zero leakages.

### Scenario 5: Complete Ingestion to CSV Parity Verification
- **Profile**: Batch processing of candidate leads across San Francisco zip codes (94115, 94123, 94109).
- **Workflow**: Ingest -> Qualify / Disqualify -> Score -> Export to `validated_leads.csv`.
- **Outcome**: Generates RFC 4180 compliant CSV matching v2 schema and scoring behavior.

---

## 7. Execution & Verification Guide

To execute the entire 4-Tier test suite:

```bash
# From the project root:
cd ocaml
dune clean
dune runtest
```

### Expected Output:
- All 8 test executables compile with zero warnings and exit code 0.
- 100% pass rate across all test cases.
