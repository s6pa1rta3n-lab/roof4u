# OCaml Test Suite, Dune Build Configuration, and Issue Tracking Analysis

## 1. Executive Summary

This report analyzes the OCaml test suite architecture, Dune build/test configuration, lead qualification and cryptographic proof mechanisms, and GitHub issue tracking infrastructure for project Roo4u.

The codebase implements a pure OCaml data acquisition and verification engine with zero external third-party OPAM runtime dependencies (only standard libraries `unix`, `str`, `threads`). The test suite comprises 12 test binaries run via `dune runtest`, executing 100+ assertions spanning unit testing, white-box invariant verification, cryptographic standards compliance, and multi-district pipeline orchestration.

Extending verification across all four required San Francisco neighborhoods (Sunset, Richmond, Excelsior, and Pacific Heights) requires adding seed municipal datasets and test scenarios for Sunset (94122) and Excelsior (94112) while formalizing end-to-end multi-district test assertions.

---

## 2. Dune Build and Test Configuration

### 2.1 Dune Project Layout

| Configuration File | Path | Key Directives | Purpose |
|---|---|---|---|
| `dune-project` | `ocaml/dune-project` | `(lang dune 3.0)`, `(name roof_engine)` | Root project specification |
| Library Dune | `ocaml/lib/dune` | `(library (name roof_engine) (libraries unix str threads) ...)` | Core engine library compilation |
| Binary Dune | `ocaml/bin/dune` | `(executable (name main) (public_name roof4u) ...)` | CLI entrypoint |
| Test Dune | `ocaml/test/dune` | 12 `(test ...)` stanzas, 2 `(executable ...)` fuzzers | Test suite orchestration |

### 2.2 Test Framework Architecture

The test harness uses zero external test dependencies (no external Alcotest, OUnit, or QCheck packages). Each test file is a standalone native OCaml executable implementing deterministic assertion primitives:
- `assert_true : string -> bool -> unit`
- `assert_equal_str : string -> string -> string -> unit`
- `assert_equal_int : string -> int -> int -> unit`
- `check_assert : string -> bool -> unit`

Tests execute sequentially or in parallel under `dune runtest` (`dune runtest --force`), exiting with code 0 on complete pass or raising an exception / calling `exit 1` on assertion failure.

### 2.3 Inventory of Existing Test Modules

| Test File | Modules Tested | Primary Assertions & Verification Scope |
|---|---|---|
| `test_verif.ml` | `Invariants`, `Scorer`, `Types` | Property/roof type parsing, INV1-4 invariant boundaries, scoring monotonicity, proof generation |
| `test_crypto.ml` | `Crypto` | RFC 6234 / FIPS 180-4 SHA-256 standard vectors, 1MB long message, chunk streaming invariance, avalanche effect |
| `test_json.ml` | `Json`, `Types` | Recursive-descent AST parser, JSON object/array serialization, Unicode escapes, string escaping |
| `test_invariants.ml` | `Invariants`, `Types` | Dedicated physical (INV-1), temporal (INV-2), economic (INV-3), and permit (INV-4) boundary matrices |
| `test_memory.ml` | `Db`, `Lesson_store`, `Embeddings`, `Vector_store` | SQLite CRUD, POSIX advisory file locking (`Unix.lockf`), 256-D L2-normalized embeddings, cosine similarity |
| `test_connectors.ml` | `Http_client`, `Datasf`, `Municipal`, `Llm_client`, `Telemetry` | HTTP/1.1 client, SoQL query builder sanitization, multi-format date parser, LLM payload cleaner, error fingerprints |
| `test_security.ml` | `Csv_exporter`, `Db`, `Datasf` | CSV formula injection / DDE attack neutralization (`=`, `+`, `-`, `@`, `\t`, `\r`), SQL injection protection |
| `test_e2e_pipeline.ml` | `Pipeline`, `Scorer`, `Csv_exporter`, `Db` | 5 real-world scenarios: Pacific Heights (94115), Marina (94123), self-healing DOM drift, adversarial fuzzing, 4-corridor batch export |
| `test_adversarial_m1.ml` | Full engine | Milestone 1 white-box adversary test suite |
| `test_m1_challenger.ml` | Full engine | Milestone 1 challenger suite verifying edge condition handling |
| `test_tier5_adversarial.ml` | All 17 features | 24 white-box challenger tests under deep boundary, fuzzing, and stress conditions |
| `test_public_records_microservices.ml` | 5 Microservices + Orchestrator | `Homeowner_names`, `Homeowner_addresses`, `Gis_roofs`, `Roof_permits`, `Property_tax_records`, `Public_records_orchestrator` |

---

## 3. Lead Generation and Cryptographic Proof Architecture

### 3.1 Lead Model Representation

Leads are structured as `Types.raw_lead`:
- `address`: string
- `zip_code`: string (5-digit postal code)
- `property_type`: `SingleFamily | MultiUnit2To4 | MultiUnit5Plus | Commercial | MixedUse | Condo | Unknown | Other of string`
- `roof_type`: `Victorian | Mansard | Flat | Gable | Hip | Metal | Unknown | Other of string`
- `estimated_value`: float option
- `owner_name`: string option
- `is_hoa`: bool
- `is_rental`: bool
- `apn`: string option (Assessor Parcel Number)
- `last_roof_permit_date`: string option (ISO date `YYYY-MM-DD`)
- `roof_age_years`: float option
- `year_built`: int option
- `permits`: `permit_record list`

### 3.2 Formal Invariant Gates (INV1 - INV4)

Lead qualification is governed by four deterministic mathematical invariants implemented in `ocaml/lib/invariants.ml`:

```
INV-1 (Physical Eligibility):
  (roof_type in {Victorian, Mansard, Flat}) AND (property_type in {SingleFamily, MultiUnit2To4})

INV-2 (Temporal Degradation):
  (roof_age_years >= 15.0) OR (year_built <= current_year - 15)

INV-3 (Economic Viability):
  (estimated_value >= $1,000,000.00) AND (is_hoa = false) AND (is_rental = false)

INV-4 (Permit Recency Non-Conflict):
  FORALL p in permits: (p.is_roof_replacement => (p.year <= current_year - 15))
```

### 3.3 Mathematical Scoring Metric

`Scorer.compute_actionability_score` produces score $S(L) \in [0.0, 100.0]$:
1. **Age Component** (0.0 to 40.0 pts): $\min(1.0, \frac{\text{effective\_age}}{30.0}) \times 40.0$
2. **Valuation Component** (0.0 to 35.0 pts): Base $15.0 + \min(1.0, \frac{V - 1\,000\,000}{4\,000\,000}) \times 20.0$ for $V \ge 1\,000\,000$
3. **Architectural Component** (0.0 to 25.0 pts): Victorian SFR (25.0), Mansard SFR (24.0), Flat SFR (22.0), Victorian Multi (20.0), Mansard Multi (19.0), Flat Multi (18.0)

### 3.4 Cryptographic Proof Construction

The verification engine produces a non-mocked cryptographic proof for every evaluated lead:

1. **Canonical Payload Construction**:
   `ROO4U-PROOF-V1|{address}|{zip_code}|{property_type}|{roof_type}|{status}|{total_score:.2f}|{timestamp}`
2. **Cryptographic Hashing**:
   `sha256_proof = Crypto.sha256_string canonical_payload` (64 hex characters)
3. **Proof Identifier**:
   `proof_id = "PROOF-OCAML-" ^ (String.uppercase_ascii (String.sub sha256_proof 0 16))`
4. **Verified Record**:
   `Types.verified_lead` containing `lead`, `verdict` (`Qualified` or `Disqualified`), `proof_id`, `sha256_proof`, `timestamp`.

---

## 4. Four-District Target Pipeline Assessment

The project mandate requires end-to-end execution and validation across four San Francisco target neighborhoods:
1. **Sunset**
2. **Richmond**
3. **Excelsior**
4. **Pacific Heights**

### 4.1 Current Implementation State & Coverage Matrix

| Neighborhood | Primary Zip | Microservice Fallbacks Present | Pipeline Seed Data Present | Dedicated E2E Test Present | Gap / Action Needed |
|---|---|---|---|---|---|
| **Pacific Heights** | `94115` | Yes | Yes (3 properties) | Yes (Scenario 1 & Microservices Suite) | Complete |
| **Richmond** | `94118` | Partial (Russian Hill default fallback) | Yes (3 properties: Washington, 14th Ave, Lake) | Partial (covered in multi-corridor test) | Add dedicated microservice fallbacks for `94118`/`94121` and explicit test scenario |
| **Sunset** | `94122` / `94116` | Missing | Missing | Missing | Add complete municipal records, pipeline seed data, and E2E test cases |
| **Excelsior** | `94112` | Missing | Missing | Missing | Add complete municipal records, pipeline seed data, and E2E test cases |

### 4.2 District Municipal Specifications

| District | Target Zip | Architectural Style | Target Assessed Values | Sample Addresses |
|---|---|---|---|---|
| **Sunset** | `94122` | Pitch Victorian / Flat Doelger Single Family | $1.35M - $1.95M | `1420 20th Ave`, `1845 34th Ave`, `2190 44th Ave` |
| **Richmond** | `94118` | Edwardian SFR / Victorian Flats / Mansard | $2.45M - $5.20M | `3645 Washington St`, `422 14th Ave`, `250 Lake St` |
| **Excelsior** | `94112` | Craftsman / Victorian Cottage SFR / 2-Unit | $1.15M - $1.65M | `120 Excelsior Ave`, `45 Edinburgh St`, `310 Persia Ave` |
| **Pacific Heights** | `94115` | Historic Victorian Manor / Mansard / 3-Unit | $2.85M - $4.35M | `2223 Pacific Ave`, `2845 Fillmore St`, `1940 Webster St` |

---

## 5. Extension Plan for Automated Test Suite

To satisfy Acceptance Criteria R1 without modifying existing invariants or introducing mocks:

### 5.1 Microservices and Pipeline Data Extensions

1. **`homeowner_addresses.ml`**:
   - Add `"sunset"` (`94122`) fallback addresses: `1420 20th Ave`, `1845 34th Ave`, `2190 44th Ave`.
   - Add `"richmond"` (`94118`) fallback addresses: `3645 Washington St`, `422 14th Ave`, `250 Lake St`.
   - Add `"excelsior"` (`94112`) fallback addresses: `120 Excelsior Ave`, `45 Edinburgh St`, `310 Persia Ave`.
   - Update `zip_code` resolution in `parse_homeowner_address_record`.

2. **`homeowner_names.ml`**:
   - Add name and parcel mappings for Sunset, Richmond, Excelsior, and Pacific Heights.

3. **`gis_roofs.ml`**:
   - Add GIS spatial footprint records (square footage, pitch/flat classifications, coordinates) for Sunset, Richmond, Excelsior, and Pacific Heights.

4. **`roof_permits.ml`**:
   - Add permit records for zip codes `94122`, `94118`, `94112`, and `94115` with realistic aging (roof age $\ge 15.0$ years).

5. **`property_tax_records.ml`**:
   - Add tax roll records for Sunset, Richmond, Excelsior, and Pacific Heights with valuations $\ge \$1,000,000.00$.

6. **`pipeline.ml`**:
   - Update default target zips to `["94122"; "94118"; "94112"; "94115"]` (Sunset, Richmond, Excelsior, Pacific Heights).
   - Add `default_seed_leads_for_zip` entries for `94122` and `94112`.

### 5.2 Test Extensions

1. **`test_public_records_microservices.ml`**:
   - Add test cases verifying `Public_records_orchestrator.acquire_neighborhood_public_records` across `"Sunset"`, `"Richmond"`, `"Excelsior"`, and `"Pacific Heights"`.
   - Assert all acquired leads qualify under INV1-4 with valid 64-character SHA-256 proofs and `PROOF-OCAML-` IDs.

2. **`test_e2e_pipeline.ml`**:
   - Update Scenario 5 to execute `Pipeline.run_pipeline` across `["94122"; "94118"; "94112"; "94115"]`.
   - Add dedicated unit verification blocks for Sunset, Richmond, Excelsior, and Pacific Heights.
   - Assert CSV output contains qualified leads from all four districts matching RFC 4180 format.

3. **`test_district_pipeline.ml` (New Dedicated Suite)**:
   - Create a dedicated test executable in `ocaml/test/test_district_pipeline.ml` registered in `ocaml/test/dune`.
   - Explicitly verify end-to-end pipeline execution, qualification verdicts, scoring thresholds, and cryptographic proof integrity for each of the four districts.

---

## 6. GitHub Issue Tracking & Mandatory Build Documentation

### 6.1 Issue Tracking Requirements

Parent Issue:
- **Repository**: `s6pa1rta3n-lab/roof4u`
- **Parent Issue**: `#30` ("Test Lead Generation Pipeline: Sunset, Richmond, Excelsior, Pacific Heights")
- **URL**: `https://github.com/s6pa1rta3n-lab/roof4u/issues/30`
- **Status**: Open, labeled `tracking`

### 6.2 MCP Tool Verification

The MCP server `github-mcp-server` provides the required primitives:
1. `issue_read`:
   - Operation: `method: "get"`, `owner: "s6pa1rta3n-lab"`, `repo: "roof4u"`, `issue_number: 30`.
   - Verified functional.
2. `issue_write`:
   - Operation: `method: "create"`, `owner: "s6pa1rta3n-lab"`, `repo: "roof4u"`, `title: "..."`, `labels: ["build-log", "blocker"]`, `body: "..."`.
   - Returns the created issue JSON containing `id` (numeric issue ID) and `number` (issue number).
3. `sub_issue_write`:
   - Operation: `method: "add"`, `owner: "s6pa1rta3n-lab"`, `repo: "roof4u"`, `issue_number: 30`, `sub_issue_id: <id_from_issue_write>`.
   - Links the sub-issue to parent issue #30.

### 6.3 Real-Time Sub-Issue Logging Protocol

Any worker or agent encountering unexpected errors, compiler issues, API drift, or architectural decisions must immediately call `issue_write` and `sub_issue_write` following this markdown template:

```markdown
## What Was Attempted
[Specific task or approach tried]

## What Failed
[Error message or unexpected behavior]

## Root Cause
[Technical analysis of why the failure occurred]

## Resolution
- **Status**: [Resolved / Workaround / Unresolved]
- **Fix**: [Remediation applied]
- **Lessons**: [Guidelines for prevention]
```
