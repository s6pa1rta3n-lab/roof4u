# E2E Test Infra: Roo4u Pure OCaml Engine

## Test Philosophy
- **Opaque-Box, Requirement-Driven**: Derived strictly from `ORIGINAL_REQUEST.md` and user specifications, not implementation internals.
- **Strict Red Team Standards**: Zero mock objects, zero simulated fake APIs, zero `unittest.mock` usage. Real local sockets, live municipal formats, real cryptographic digests.
- **Methodology**: Category-Partition + Boundary Value Analysis (BVA) + Pairwise Combinatorial Testing + Real-World Workload Testing.

## Feature Inventory
| # | Feature | Source (Requirement) | Tier 1 (Coverage) | Tier 2 (Boundaries) | Tier 3 (Pairwise) |
|---|---------|----------------------|:-----------------:|:-------------------:|:-----------------:|
| 1 | Cryptographic SHA-256 Engine | ORIGINAL_REQUEST §R2, §R3 | 5 | 5 | ✓ |
| 2 | Recursive Descent JSON AST Parser | ORIGINAL_REQUEST §R1, §R2 | 5 | 5 | ✓ |
| 3 | Invariant Qualification Engine (INV1-4) | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 4 | Deterministic Actionability Scoring | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 5 | Atomic JSON Lesson Store & File Locking | ORIGINAL_REQUEST §R1, §R2 | 5 | 5 | ✓ |
| 6 | 256-D Offline Feature Hashing Embedder | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 7 | Embedded Vector Store & Cosine Search | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 8 | SQLite Lead Database Persistence | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 9 | DataSF SODA API Connectors | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 10 | Municipal PIM & DBI Scrapers | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 11 | Local LLM Client (`localhost:8000`) | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 12 | Git Telemetry & Dual-Transport Issue Logging | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 13 | Core Pipeline Orchestration | ORIGINAL_REQUEST §R1, §R3 | 5 | 5 | ✓ |
| 14 | RFC 4180 CSV Lead Exporter (`validated_leads.csv`) | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 15 | Python Legacy Safe Deprecation | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 16 | Adversarial Security Vulnerability Closing | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 17 | Formal Security Audit Report | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |

## Test Architecture
- **Test Runner**: Dune native test runner (`dune runtest`) invoking OCaml test executables in `ocaml/test/`.
- **Pass/Fail Semantics**: All test suites must complete with exit code 0 and zero runtime assertions failed.
- **Directory Layout**:
  - `ocaml/test/test_crypto.ml`: Tier 1 & 2 tests for SHA-256 standard test vectors.
  - `ocaml/test/test_json.ml`: Tier 1 & 2 tests for AST JSON parsing, escaping, and fuzz-resistant syntax.
  - `ocaml/test/test_invariants.ml`: Tier 1, 2, 3 tests for formal invariant qualification & deterministic scoring.
  - `ocaml/test/test_memory.ml`: Tier 1, 2, 3 tests for lesson storage concurrency, embedding hashing, and vector search.
  - `ocaml/test/test_connectors.ml`: Tier 1, 2, 3 tests for municipal SODA queries, SoQL sanitation, and lead synthesis.
  - `ocaml/test/test_security.ml`: Tier 2 & 3 adversarial test suite for SoQL injection, JSON parser spoofing, CSV DDE, path traversal, and concurrency race conditions.
  - `ocaml/test/test_e2e_pipeline.ml`: Tier 4 real-world full pipeline execution test producing `validated_leads.csv` and cryptographic proofs.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Full Pacific Heights (`94115`) Victorian Acquisition | F1, F2, F3, F4, F8, F9, F13, F14 | High |
| 2 | Marina & Cow Hollow (`94123`) Flat Roof Multi-Unit | F3, F4, F8, F9, F10, F13, F14 | High |
| 3 | Self-Healing Closed Loop with Induced Scraping Drift | F5, F6, F7, F11, F12, F13 | High |
| 4 | Adversarial Fuzzing & Malicious Injection Ingestion | F1, F2, F9, F14, F16, F17 | High |
| 5 | Complete Live Ingestion to `validated_leads.csv` Verification | F1, F3, F4, F8, F13, F14, F15 | High |

## Coverage Thresholds
- **Tier 1 (Feature Coverage)**: >= 85 test cases (>=5 per feature)
- **Tier 2 (Boundary & Corner Cases)**: >= 85 test cases (>=5 per feature)
- **Tier 3 (Cross-Feature Combinations)**: >= 17 pairwise test cases
- **Tier 4 (Real-World Scenarios)**: >= 5 comprehensive end-to-end scenarios
- **Total Minimum Test Count**: >= 192 test cases
