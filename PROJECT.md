# Project: Roo4u Pure OCaml Architecture & Adversarial Security Remediation

## Architecture
Roo4u is an autonomous, 100% offline agentic real estate qualification and lead generation engine focused exclusively on San Francisco municipal databases. The architecture is rewritten entirely in pure OCaml 5 using Dune, eliminating all Python execution dependencies, mock bypasses, and external cloud APIs.

```
+----------------------------------------------------------------------------------------------------+
|                                    Roo4u Pure OCaml Engine                                         |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|  +----------------------------------------------------------------------------------------------+  |
|  | 1. Data Acquisition & Municipal Ingestion                                                   |  |
|  |    - DataSF SODA API Connector (Building Permits `i98e-djp9`, PermitSF `tyz3-vt28`)          |  |
|  |    - SF Planning Information Map (PIM) & SF DBI Permit Tracking Table Parsers                |  |
|  |    - Parameter-validated SoQL Query Builder (Anti-Injection Whitelisting)                   |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | 2. Local LLM Inference & Extraction (`localhost:8000`)                                       |  |
|  |    - Pure OCaml HTTP 1.1 Client (Unix sockets, zero cloud dependency)                        |  |
|  |    - OpenAI Chat Completion payload formatter & balanced-brace JSON cleaner                 |  |
|  |    - Structured Property & Permit Attribute Extraction Models                                |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | 3. Mathematical Qualification & Invariant Proof Engine                                       |  |
|  |    - INV1 Physical Eligibility (Victorian / Flat / Mansard; SFR / 2-4 Units)                 |  |
|  |    - INV2 Temporal Degradation (RoofAge >= 15.0 yrs or YearBuilt <= 1996)                   |  |
|  |    - INV3 Economic Viability (AssessedValue >= $1.0M, non-HOA, non-Rental)                   |  |
|  |    - INV4 Permit Recency Non-Conflict (No roof permits within last 15 yrs)                   |  |
|  |    - Deterministic Actionability Scoring Engine (Age 40pts + Value 35pts + Type 25pts)       |  |
|  |    - Pure OCaml RFC 6234 / FIPS 180-4 SHA-256 Cryptographic Proof Digest Generator           |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | 4. Dual Memory System & Closed-Loop Learning                                                 |  |
|  |    - Atomic POSIX JSON Lesson Store (`lessons_learned.json`) with `Unix.lockf`               |  |
|  |    - 256-D Deterministic Offline Feature Hashing Embeddings (CRC32 + MD5 sign)               |  |
|  |    - Embedded Vector Store & Cosine Similarity Search Engine                                 |  |
|  |    - Native SQLite Persistence for Discovered, Enriched & Validated Leads (`leads.db`)       |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | 5. Git Telemetry & Dual-Transport Issue Logging                                              |  |
|  |    - ScrapingFailureEvent & SHA-256 Fingerprinting                                           |  |
|  |    - Dual Transport (MCP Tools -> REST API Fallback -> Disk Queue `.github_issues_queue.json`) |
|  |    - Deduplication & 60-Second Anti-Spam Recurrence Throttling                               |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | 6. Export & Security Verification                                                            |  |
|  |    - RFC 4180 CSV Exporter with Formula Injection Neutralization (`validated_leads.csv`)     |  |
|  |    - Security Audit Remediation Engine & Formal Report (`security_audit.md`)                 |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                                                                    |
+----------------------------------------------------------------------------------------------------+
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Cryptographic SHA-256 Engine | Pure OCaml RFC 6234 / FIPS 180-4 implementation for digital proofs & fingerprints | M1 | Survey |
| 2 | Recursive Descent JSON AST Parser | Full JSON AST parser/serializer supporting escaped strings, arrays, objects | M1 | Survey |
| 3 | Invariant Qualification Engine | Formal algebraic verification of INV1, INV2, INV3, INV4 | M1 | Survey |
| 4 | Actionability Scoring Engine | Deterministic 0.0 to 100.0 score calculator (Age, Value, Architectural Type) | M1 | Survey |
| 5 | Atomic JSON Lesson Store | POSIX atomic write/fsync/rename with `Unix.lockf` advisory locking & corruption recovery | M2 | Survey |
| 6 | 256-D Offline Feature Hashing | Multi-scale tokenization (status, words, bigrams, 3-grams, 4-grams) to 256-D unit vector | M2 | Survey |
| 7 | Embedded Vector Store | Cosine similarity vector search engine over 256-D float embeddings | M2 | Survey |
| 8 | SQLite Lead Database Layer | Native SQLite lead persistence for DISCOVERED, ENRICHED, VALIDATED states | M2 | Survey |
| 9 | DataSF SODA API Connectors | HTTP client for building permits (`i98e-djp9`) & PermitSF (`tyz3-vt28`) with parameter validation | M3 | Survey |
| 10 | Municipal PIM & DBI Scrapers | San Francisco Planning GIS and DBI permit tracking parsers & date normalizers | M3 | Survey |
| 11 | Local LLM Inference Client | Pure OCaml HTTP 1.1 client for `localhost:8000` with prompt formatting & clean parsing | M3 | Survey |
| 12 | Git Telemetry & Issue Logger | ScrapingFailureEvent capture, SHA-256 fingerprinting, deduplication & offline queuing | M3 | Survey |
| 13 | Core Pipeline Orchestrator | CLI binary (`roof_pipeline`) executing discovery, enrichment, qualification, and learning loop | M4 | Survey |
| 14 | RFC 4180 CSV Lead Exporter | 10-column `validated_leads.csv` generator with DDE formula injection protection | M4 | Survey |
| 15 | Python v2 Safe Deprecation | Safe deprecation/removal of legacy Python pipeline and memory files | M4 | Survey |
| 16 | Adversarial Security Remediation | Formal patches for SoQL injection, JSON regex spoofing, hash mocking, CSV injection, path traversal, concurrency | M5 | Survey |
| 17 | Security Audit Formal Report | Comprehensive `security_audit.md` documenting vulnerabilities, attack vectors, and patches | M5 | Survey |
| 18 | E2E Opaque-Box Test Suite | 4-Tier test suite (Tiers 1-4) verifying functional, boundary, combinatorial, and real-world workloads | E2E | Survey |
| 19 | Adversarial Coverage Hardening | Tier 5 white-box challenger tests stress-testing all edge cases and closing coverage gaps | M_FINAL | Survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | OCaml Core Cryptography, JSON & Invariants | Pure SHA-256, AST JSON Parser/Serializer, INV1-INV4 Invariant Engine, Actionability Scorer, Formal Types | none | DONE |
| M2 | OCaml Dual Memory Store & Persistence | Atomic Lesson Store with `Unix.lockf`, 256-D Feature Hashing, Vector Store, SQLite DB layer | M1 | IN_PROGRESS |
| M3 | Municipal DataSF Connectors, Local LLM Client & Telemetry | DataSF SODA connector, PIM/DBI parser, Local LLM inference client (`localhost:8000`), Git telemetry & issue logger | M1 | IN_PROGRESS |
| M4 | Core Pipeline Orchestration, CSV Export & Python Deprecation | `roof_pipeline` CLI binary, 10-column `validated_leads.csv` export with DDE protection, live pipeline run, legacy Python deprecation | M1, M2, M3 | PLANNED |
| M5 | Adversarial Security Remediation & Audit Report | Vulnerability patches verification, programmatic security tests, formal `security_audit.md` artifact generation | M1, M2, M3, M4 | PLANNED |
| E2E | Opaque-Box E2E Testing Track | Independent 4-tier opaque-box test suite for all features, published via `TEST_READY.md` | none | DONE |
| M_FINAL | Final E2E Pass & Tier 5 Adversarial Coverage Hardening | 100% E2E test suite pass (Tiers 1-4) + Tier 5 Adversarial Coverage Hardening loop | M1-M5, E2E | PLANNED |

## Interface Contracts

### Module `Roof_crypto` (SHA-256)
```ocaml
val sha256_bytes : bytes -> bytes
val sha256_string : string -> string (* returns 64-character lowercase hex string *)
val sha256_digest : string -> string
```

### Module `Roof_json` (Recursive Descent AST Parser & Serializer)
```ocaml
type t =
  | Null
  | Bool of bool
  | Number of float
  | String of string
  | Array of t list
  | Object of (string * t) list

val parse : string -> (t, string) result
val to_string : t -> string
val get_field : string -> t -> t option
val get_string : string -> t -> string option
val get_float : string -> t -> float option
val get_int : string -> t -> int option
val get_bool : string -> t -> bool option
val get_array : string -> t -> t list option
```

### Module `Roof_invariants` & `Roof_types`
```ocaml
type roof_type = Victorian | Flat | Mansard | Gable | Hip | Metal | Unknown
type property_type = SingleFamily | MultiUnit2To4 | Commercial | MixedUse | Condo | Other
type permit_record = { permit_number: string; permit_type: string; description: string; issued_date: string; status: string; year: int; is_roof_replacement: bool }
type raw_lead = { address: string; zip_code: string; property_type: property_type; roof_type: roof_type; estimated_value: float option; owner_name: string option; is_hoa: bool; is_rental: bool; apn: string option; last_roof_permit_date: string option; roof_age_years: float option; phone_number: string option; permits: permit_record list; year_built: int option }
type scoring_components = { age_score: float; value_score: float; type_score: float; total_score: float }
type qualification_verdict = Qualified of scoring_components | Disqualified of string list
type verified_lead = { raw: raw_lead; verdict: qualification_verdict; proof_id: string; sha256_proof: string; timestamp: string }

val check_inv1_physical : raw_lead -> (unit, string) result
val check_inv2_temporal : raw_lead -> (unit, string) result
val check_inv3_economic : raw_lead -> (unit, string) result
val check_inv4_permits  : raw_lead -> (unit, string) result
val calculate_score     : raw_lead -> scoring_components
val verify_lead         : raw_lead -> verified_lead
```

### Module `Roof_memory` (Lesson Store, Embeddings, Vector Store, SQLite)
```ocaml
type lesson = {
  id : string;
  domain : string;
  url : string;
  failure_type : string;
  error_message : string;
  lesson_learned : string;
  recommended_action : string;
  suggested_selectors : string list;
  suggested_delay_seconds : float;
  suggested_headers : (string * string) list;
  github_issue_number : int option;
  timestamp : string;
  dom_snippet : string option;
  status : string; (* ACTIVE | RESOLVED | PROBATION | DEPRECATED *)
  occurrence_count : int;
  success_count_after_workaround : int;
}

val load_lessons : string -> lesson list
val save_lessons_atomic : string -> lesson list -> unit
val upsert_lesson : string -> lesson -> lesson
val increment_success : string -> string -> bool

val generate_embedding : string -> float array (* 256-D unit normalized *)
val cosine_similarity : float array -> float array -> float
```

### Module `Roof_exporter` (CSV Exporter)
```ocaml
val sanitize_csv_field : string -> string (* Neutralizes =, +, -, @, \t, \r *)
val export_validated_leads_csv : string -> verified_lead list -> unit
```

## Code Layout
```
ocaml/
├── dune-project                  # Dune project definition (roof_engine)
├── roof_engine.opam              # Opam packaging metadata
├── bin/
│   ├── dune                      # Executable build configuration
│   └── main.ml                   # CLI entrypoint: live run, verification, export
├── lib/
│   ├── dune                      # Library build configuration
│   ├── types.ml                  # Formal algebraic data types
│   ├── crypto.ml                 # Pure RFC 6234 / FIPS 180-4 SHA-256
│   ├── json.ml                   # Pure recursive-descent JSON AST parser & serializer
│   ├── invariants.ml             # Formal invariants INV1-INV4 and qualification
│   ├── scorer.ml                 # Deterministic 0.0-100.0 actionability scorer
│   ├── embeddings.ml             # Deterministic 256-D offline feature hashing
│   ├── lesson_store.ml           # POSIX atomic JSON lesson store with Unix.lockf
│   ├── vector_store.ml           # 256-D vector database and cosine similarity search
│   ├── db.ml                     # SQLite lead persistence and query layer
│   ├── http_client.ml            # Pure OCaml HTTP 1.1 client (Unix sockets)
│   ├── datasf.ml                 # DataSF SODA API connector (i98e-djp9 & tyz3-vt28)
│   ├── municipal.ml              # SF PIM & DBI permit scraping & date normalization
│   ├── llm_client.ml             # Local LLM client (localhost:8000) & extractor
│   ├── telemetry.ml              # ScrapingFailureEvent & GitHub issue manager
│   ├── csv_exporter.ml           # 10-column validated_leads.csv with DDE protection
│   └── pipeline.ml               # Core orchestration workflow
└── test/
    ├── dune                      # Test suite build configuration
    ├── test_crypto.ml            # SHA-256 test vectors (RFC 6234)
    ├── test_json.ml              # AST JSON parser test suite & security edge cases
    ├── test_invariants.ml        # Formal invariant qualification & scoring unit tests
    ├── test_memory.ml            # Lesson store locking, embeddings & vector search
    ├── test_connectors.ml        # Municipal connectors & SoQL injection protection
    ├── test_security.ml          # Adversarial vulnerability closing tests
    └── test_e2e_pipeline.ml      # Complete live pipeline execution test
```
