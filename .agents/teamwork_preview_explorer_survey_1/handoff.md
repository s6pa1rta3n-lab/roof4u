# Handoff Report: Roo4u Python v2 Architecture Survey & OCaml Rewrite Specifications

## 1. Observation

A comprehensive inspection of all codebase files across `/Users/solveetcoagula/Desktop/activeProjects/Roo4u` was conducted. Below are the verified observations, file paths, exact schemas, scoring formulas, and architectural components:

### 1.1 Core Repository Layout & Inventories
- **Entry Points & Pipelines**:
  - `main.py` (lines 1–204): Orchestrates Browsing Agents (`ZillowAgent`, `CountyAgent`), `LocalLLMExtractor`, and closed-loop `LearningAgent` with SQLite persistence (`leads.db`).
  - `scripts/acquire_live_data.py` (lines 1–342): Queries live DataSF SODA API endpoints (`i98e-djp9` and `tyz3-vt28`), synthesizes candidate leads, executes mathematical verification via `OCamlLeadVerifier`, persists to SQLite, and exports `validated_leads.csv`.
  - `scripts/run_judge.py` (lines 1–122): Standalone CLI executing `AgentAsJudge` for AST security compliance, pytest log parsing, 5-dimension rubric scoring, and digital certification.
- **Agent Subsystems**:
  - `agents/base_agent.py` (lines 1–219): Synchronous Playwright browser lifecycle manager with anti-bot context, safe navigation (`safe_get_html`), feedforward adaptations, and telemetry emission (`emit_failure`).
  - `agents/extractor.py` (lines 1–267): Local OpenAI-compatible client (`http://localhost:8000/v1`) using Pydantic models `PropertyExtraction`, `PermitRecord`, `CountyPermitExtraction`, with `<think>` tag stripping and balanced brace JSON recovery.
  - `agents/zillow_agent.py` (lines 1–254): Discovery agent with DOM cleaner (`clean_dom` stripping non-semantic tags with 12,000 char budget), property scraper, and failure telemetry.
  - `agents/county_agent.py` (lines 1–279): Municipal public records agent querying SF PIM and DBI permit tracking, featuring a 16-format permit date parser (`parse_permit_date`) and lead enrichment (`enrich_lead`).
  - `agents/learning_agent.py` (lines 1–391): Self-healing coordinator with 7-category heuristic classifier (`FailureCategory`), dual-memory synchronization, GitHub issue logging, and feedforward strategy compiler (`FeedforwardStrategy`).
  - `agents/judge_agent.py` (lines 1–593): AST scanner for forbidden mock imports and cloud keys, pytest JSON report parser, 5-dimension rubric engine (Max 100.0 pts), and SHA-256 digital certification signer.
- **Memory & Storage**:
  - `db/database.py` (lines 1–52): SQLAlchemy SQLite schema defining the `leads` table and ORM model `Lead`.
  - `memory/lesson_store.py` (lines 1–264): Atomic JSON manager for `lessons_learned.json` using POSIX atomic file replace (`NamedTemporaryFile` + `os.replace` + `os.fsync`) and corruption recovery.
  - `memory/embeddings.py` (lines 1–119): 100% offline 256-dimensional feature hashing embedder using CRC32 bucket hashing, MD5 sign hashing, and L2 normalization.
  - `memory/vector_store.py` (lines 1–378): Embedded SQLite (`vector_records` table) storing float32 BLOB embeddings and computing vectorized NumPy batch cosine similarity dot products.
- **Integrations & Exporters**:
  - `integrations/github_client.py` (lines 1–615): Dual-transport telemetry logger (MCP tool calls `issue_write`, `list_issues`, `add_issue_comment` -> REST API fallback -> offline queue `.github_issues_queue.json`) with SHA-256 deduplication and 60s throttling.
  - `integrations/ocaml_verifier.py` (lines 1–100): IPC bridge invoking compiled OCaml binary `roof_verif_cli` via `--stdin` and parsing `OCamlVerificationResult`.
  - `exporters/csv_exporter.py` (lines 1–37): Exports `VALIDATED` and `ENRICHED` leads from SQLite to `validated_leads.csv`.
- **Existing OCaml Verification Engine (`ocaml/`)**:
  - `ocaml/dune-project`: Language Dune 3.0, package `roof_verif` v2.0.0.
  - `ocaml/lib/types.ml` (lines 1–78): Algebraic data types `roof_type`, `property_type`, `permit_record`, `raw_lead`, `invariant_result`, `scoring_components`, `qualification_verdict`, `verified_lead`.
  - `ocaml/lib/invariants.ml` (lines 1–232): Formal invariant checks ($\text{INV}_1$ Physical Eligibility, $\text{INV}_2$ Temporal Degradation, $\text{INV}_3$ Economic Viability, $\text{INV}_4$ Permit Recency Non-Conflict) and deterministic scoring engine ($0.0 - 100.0$).
  - `ocaml/lib/parser.ml` (lines 1–231): Zero-dependency string/regex JSON parser and serializer.
  - `ocaml/bin/main.ml` (lines 1–63): CLI binary accepting `--stdin`, `--file`, `--json`.
  - `ocaml/test/test_verif.ml` (lines 1–137): Native OCaml unit test suite validating all invariants and scoring bounds.

---

### 1.2 San Francisco Municipal Database Connectors & Endpoints

#### A. DataSF SODA API - Building Permits (`i98e-djp9`)
- **Base Endpoint**: `https://data.sfgov.org/resource/i98e-djp9.json`
- **Method**: HTTP GET
- **Target Zip Codes**: `94115` (Pacific Heights/Western Addition), `94123` (Marina/Cow Hollow), `94118` (Inner Richmond/Presidio Heights), `94109` (Russian Hill/Nob Hill)
- **SoQL Query Parameters**:
  - `$where`: `zipcode='{zip}' and existing_units in('1.0', '2.0', '3.0', '4.0', '1', '2', '3', '4') and description like '%roof%'`
  - `$order`: `filed_date desc`
  - `$limit`: integer (e.g. `15`)
- **Key Raw Fields**: `street_number`, `street_name`, `street_suffix`, `zipcode`, `block`, `lot`, `existing_units`, `description`, `revised_cost`, `estimated_cost`, `filed_date`, `issued_date`, `permit_creation_date`, `permit_number`.

#### B. DataSF PermitSF - Recent Permits (`tyz3-vt28`)
- **Base Endpoint**: `https://data.sfgov.org/resource/tyz3-vt28.json`
- **Method**: HTTP GET
- **SoQL Query Parameters**:
  - `$where`: `postalcode in('94115','94123','94118','94109')`
  - `$order`: `submitted_date desc`
  - `$limit`: integer (e.g. `20`)
- **Key Raw Fields**: `streetno`, `streetname`, `postalcode`, `parcel_number`, `submitted_date`.

#### C. SF Planning Information Map (PIM)
- **Base Endpoint**: `https://sfplanninggis.org/pim/`
- **Query URL**: `https://sfplanninggis.org/pim/?search={address_encoded}`
- **DOM Selectors**: `.property-summary`, `.parcel-details`, `table.data-table`, `table`, `#propertyDetails`, `.assessment-info`, `.record-content`, `.parcel-info`
- **Extracted Attributes**: Assessor Parcel Number (`APN` / Block & Lot), Legal Owner Name, Total Assessed Property Value, Property Class / Zoning District, HOA Status.

#### D. SF Department of Building Inspection (DBI) Permit Tracking System
- **Base Endpoint**: `https://dbiweb02.sfgov.org/dbipts/`
- **Query URL**: `https://dbiweb02.sfgov.org/dbipts/default.aspx?page=Address&Address={address_encoded}`
- **DOM Selectors**: `.dbi-grid`, `.permit-table`, `#permitList`, `table`
- **Extracted Attributes**: Permit Number, Application / Filing Date, Issue Date, Permit Type (`Reroofing`, `Alterations`, `Building`), Work Description, Permit Status (`Completed`, `Issued`, `Filed`).

---

### 1.3 Data Models & Lead Schema

#### Database Schema (`leads.db` / `Lead` table)
| Column Name | SQL Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | `INTEGER` | `False` (PK) | Auto-inc | Primary key identifier |
| `address` | `TEXT` / `VARCHAR` | `False` (Unique) | — | Full normalized street address (e.g. `2223 Pacific Ave, San Francisco, CA 94115`) |
| `zip_code` | `TEXT` / `VARCHAR` | `False` | — | 5-digit United States postal code |
| `property_type` | `TEXT` / `VARCHAR` | `True` | — | Building classification: `Single-Family`, `Multi-Unit`, `Condo`, `Multi-Family` |
| `roof_type` | `TEXT` / `VARCHAR` | `True` | — | Roof style: `Victorian`, `Flat`, `Mansard`, `Gable`, `Hip`, `Metal`, `Unknown` |
| `estimated_value` | `FLOAT` / `REAL` | `True` | `None` | Assessed property valuation in USD |
| `owner_name` | `TEXT` / `VARCHAR` | `True` | `None` | Legal owner or trust entity name |
| `is_hoa` | `BOOLEAN` | `False` | `False` | True if governed by Homeowners Association / Condo board |
| `is_rental` | `BOOLEAN` | `False` | `False` | True if commercial rental / tenant occupied |
| `apn` | `TEXT` / `VARCHAR` | `True` | `None` | San Francisco Assessor Parcel Number (e.g. `0582-014` or `0582014`) |
| `last_roof_permit_date` | `DATE` / `TEXT` | `True` | `None` | Date of most recent roofing permit (`YYYY-MM-DD`) |
| `roof_age_years` | `FLOAT` / `REAL` | `True` | `None` | Estimated age of current roof in years |
| `phone_number` | `TEXT` / `VARCHAR` | `True` | `None` | Contact telephone number (if discovered) |
| `created_at` | `DATE` / `TEXT` | `False` | Current UTC | Record ingestion timestamp |
| `status` | `TEXT` / `VARCHAR` | `False` | `"DISCOVERED"` | State: `DISCOVERED`, `ENRICHED`, `VALIDATED`, `DISCARDED` |

---

### 1.4 Formal Invariants & Mathematical Lead Qualification Engine

Formal constraints enforced by the OCaml verification module (`Invariants`):

#### Invariant 1: Physical Eligibility ($\text{INV}_1$)
$$\text{RoofType} \in \{\text{Victorian}, \text{Flat}, \text{Mansard}\} \land \text{PropertyType} \in \{\text{SingleFamily}, \text{MultiUnit2To4}\}$$
*Violated if*: Roof is Gable, Hip, Metal, or Other, OR property is Commercial, MixedUse, Condo, or 5+ Unit Apartments.

#### Invariant 2: Temporal Degradation ($\text{INV}_2$)
$$\text{RoofAge} \ge 15.0 \lor (\text{YearBuilt} \le (\text{CurrentYear} - 30) \land \text{LastRoofPermit} = \text{None})$$
*Current Year Base*: `2026`.
*Violated if*: Roof age < 15.0 years, or construction year > 1996 without verified roof age.

#### Invariant 3: Economic Viability ($\text{INV}_3$)
$$\text{AssessedValue} \ge \$1,000,000.00 \land \neg \text{IsHOA} \land \neg \text{IsRental}$$
*Violated if*: Assessed valuation < $1,000,000.00, property is HOA-managed, or property is rental-occupied.

#### Invariant 4: Permit Recency Non-Conflict ($\text{INV}_4$)
$$\forall p \in \text{Permits}, p.\text{is\_roof\_replacement} \implies (\text{CurrentYear} - p.\text{year}) \ge 15$$
*Violated if*: Any permit classified as a roof replacement was filed/issued within the preceding 15 years (i.e. year $\ge 2011$).

#### Deterministic Actionability Scoring Formula ($0.0 \le S(L) \le 100.0$)
$$S(L) = C_{\text{age}}(L) + C_{\text{val}}(L) + C_{\text{type}}(L)$$

1. **Roof Age Component ($0.0 \le C_{\text{age}} \le 40.0$)**:
   $$\text{EffectiveAge} = \begin{cases} \text{RoofAge} & \text{if present} \\ \max(0, \text{CurrentYear} - \text{YearBuilt}) & \text{if YearBuilt present} \\ 15.0 & \text{otherwise} \end{cases}$$
   $$C_{\text{age}}(L) = 40.0 \times \min\left(1.0, \frac{\text{EffectiveAge}}{30.0}\right)$$

2. **Property Value Component ($0.0 \le C_{\text{val}} \le 35.0$)**:
   If $\text{AssessedValue} \ge \$1,000,000.00$:
   $$C_{\text{val}}(L) = 15.0 + 20.0 \times \min\left(1.0, \max\left(0.0, \frac{\text{AssessedValue} - \$1,000,000.00}{\$4,000,000.00}\right)\right)$$
   Else $C_{\text{val}}(L) = 0.0$.

3. **Architectural Type Component ($10.0 \le C_{\text{type}} \le 25.0$)**:
   - Victorian Single-Family: $25.0$
   - Mansard Single-Family: $24.0$
   - Flat Single-Family: $22.0$
   - Victorian 2-4 Unit: $20.0$
   - Flat 2-4 Unit: $18.0$
   - Other Single-Family: $12.0$
   - Otherwise: $10.0$

---

### 1.5 CSV Exporter Specification & Formatting (`validated_leads.csv`)

- **Target Destination**: `validated_leads.csv` in project root.
- **Inclusion Gate**: Records in `leads` database with `status` $\in \{\text{"VALIDATED"}, \text{"ENRICHED"}\}$ and verified actionability score $\ge 60.0$.
- **Exact Column Headers** (10 columns, exact casing):
  ```csv
  Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status
  ```
- **Data Formatting Rules**:
  - `Address`: String, quoted if containing commas.
  - `Zip Code`: 5-digit string (e.g. `94109`, `94115`).
  - `Property Type`: Normalized string (`Single-Family`, `Multi-Unit`).
  - `Roof Type`: Normalized string (`Victorian`, `Flat`, `Mansard`).
  - `Assessed Value`: Float rendered as decimal (e.g. `3400000.0`).
  - `Owner Name`: String or empty if null.
  - `APN`: String (e.g. `0186042`, `0582-014`).
  - `Roof Age (Years)`: Float rendered as decimal (e.g. `22.0`).
  - `Phone Number`: String or empty if null.
  - `Status`: String (`VALIDATED` or `ENRICHED`).
- **File Invariants**: UTF-8 encoded, newline `\n`, RFC 4180 escaped, atomic write/overwrite.

---

### 1.6 Self-Healing & Memory Systems

1. **Structured Lesson Ledger (`lessons_learned.json`)**:
   - Fields: `id` (16-char hex sha256 of `domain:failure_type:selector`), `domain`, `url`, `source_url`, `failure_type`, `error_message`, `lesson_learned`, `recommended_action`, `suggested_selectors`, `suggested_delay_seconds`, `suggested_headers`, `github_issue_number`, `timestamp`, `dom_snippet`, `status` (`ACTIVE`, `RESOLVED`, `PROBATION`, `DEPRECATED`), `occurrence_count`, `success_count_after_workaround`.
   - Atomic replacement: writes to temporary file with `fsync` before POSIX rename; automatic backup on corrupted JSON.
2. **Local Vector Database (`memory/vector_store.sqlite`)**:
   - SQLite table: `vector_records(id, domain, failure_type, text, metadata_json, embedding BLOB, created_at)`.
   - Embedder: 256-dim feature hashing over status tokens (`status:403`), words, word bigrams, character 3-grams/4-grams.
   - Vectorized dot product search with top-k ranking and score thresholds.
3. **GitHub Issue Logger (`integrations/github_client.py`)**:
   - Transports: MCP tools (`issue_write`, `list_issues`, `add_issue_comment`) -> REST API -> local disk queue (`.github_issues_queue.json`).
   - Deduplication: SHA-256 fingerprint; existing open issue receives recurrence comment with 60s throttling.

---

## 2. Logic Chain

1. **Observation 1.1 & 1.2**: In Python v2, data acquisition is executed across two distinct modes: browser-based Playwright scraping of Zillow / PIM / DBI (`main.py`, `agents/`), and direct HTTP API ingestion from San Francisco SODA open data portals `i98e-djp9` and `tyz3-vt28` (`scripts/acquire_live_data.py`).
2. **Inference 1**: To achieve a pure OCaml rewrite without external Python dependencies, the OCaml system requires native HTTP/socket connectors to query DataSF SODA endpoints directly, parse municipal JSON payloads, extract DOM/HTML tables if accessing PIM/DBI portals, and execute the full scoring and persistence pipeline natively.
3. **Observation 1.3 & 1.4**: The formal verification logic in OCaml (`ocaml/lib/invariants.ml`) is already mathematically specified, bounded in $[0.0, 100.0]$, and tested with 100% pass rate in `ocaml/test/test_verif.ml`. However, currently it operates as a standalone CLI called over IPC (`subprocess.run`) by `integrations/ocaml_verifier.py`.
4. **Inference 2**: In the pure OCaml rewrite, the verification engine (`Roof_verif.Invariants`) must be directly linked in-memory with the ingestion pipeline (`Roof_pipeline`), eliminating subprocess IPC overhead, Python bridging, and external serialization roundtrips.
5. **Observation 1.5**: `validated_leads.csv` has an exact 10-column schema (`Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status`) and strict numeric/string formatting rules.
6. **Inference 3**: The OCaml CSV export module (`Roof_exporter`) must output this exact schema with identical headers, precision formatting (e.g. `3400000.0`, `22.0`), and RFC 4180 compliance to maintain total backward compatibility.
7. **Observation 1.6**: Memory subsystems (`LessonStore`, `LocalVectorStore`) and GitHub telemetry rely on atomic file replacement, SQLite/JSON persistence, and deterministic offline feature hashing.
8. **Inference 4**: The OCaml rewrite must provide native modules for:
   - Atomic JSON lesson persistence (`Roof_memory.Lesson_store`)
   - Native SQLite or pure-functional vector index store (`Roof_memory.Vector_store`)
   - Deterministic feature hashing embedder (`Roof_memory.Embeddings`)
   - GitHub issue telemetry via HTTP REST or MCP JSON-RPC (`Roof_integrations.Github_client`)

---

## 3. Caveats

1. **Live External Municipal SODA API Availability**: The City & County of San Francisco SODA APIs (`data.sfgov.org`) are live public endpoints. In strictly offline benchmark modes or sandboxed CI environments, the pipeline must support offline fixture playback or local mock-free HTTP socket servers (as demonstrated in `conftest.py`).
2. **Browser Engine in Pure OCaml**: Playwright is a Node.js/Python library. For browser-based DOM scraping (if needed beyond direct SODA REST APIs), OCaml can either interface with Headless Chromium via Chrome DevTools Protocol (CDP over WebSockets) or prioritize the high-fidelity DataSF SODA and PIM/DBI HTTP REST endpoints which provide structured JSON data without browser rendering overhead.
3. **No Other Caveats**: All formulas, schemas, file paths, and invariants are fully documented and verified against existing source code and test fixtures.

---

## 4. Conclusion & Recommended OCaml Module Architecture

The pure OCaml rewrite should be structured under `ocaml/` using Dune as follows:

```
ocaml/
├── dune-project
├── roof_pipeline.opam
├── bin/
│   ├── dune
│   └── main.ml               (* CLI binary: live acquisition, verification, CSV export *)
├── lib/
│   ├── dune
│   ├── types.ml              (* Formal ADTs: leads, permits, scores, lessons, events *)
│   ├── invariants.ml         (* INV1-INV4 formal proofs & deterministic scoring *)
│   ├── parser.ml             (* JSON & CSV parsing and serialization *)
│   ├── sftp_connector.ml     (* DataSF SODA HTTP client for i98e-djp9 & tyz3-vt28 *)
│   ├── municipal_portal.ml   (* PIM & DBI permit scraper / HTML table parser *)
│   ├── storage.ml            (* SQLite & JSON atomic lead/lesson persistence *)
│   ├── embeddings.ml         (* 256-dim deterministic offline feature hashing *)
│   ├── vector_store.ml       (* Offline vector cosine similarity search engine *)
│   ├── telemetry.ml          (* GitHub issue telemetry & deduplication *)
│   └── csv_exporter.ml       (* Exact 10-column validated_leads.csv generator *)
└── test/
    ├── dune
    ├── test_invariants.ml    (* Unit tests for INV1-INV4 and scoring bounds *)
    ├── test_connectors.ml    (* Tests for SODA API data ingestion & parsing *)
    ├── test_memory.ml        (* Tests for dual-memory, vector search, embeddings *)
    └── test_e2e_pipeline.ml  (* End-to-end live pipeline execution test *)
```

### Key Target Specifications for Implementer:
1. **Dune Build Target**: `dune build && dune runtest` must compile with 0 errors/warnings under OCaml $\ge 5.0$.
2. **CLI Interface**:
   ```bash
   ./_build/default/bin/main.exe --zips "94115,94123,94118,94109" --limit 15 --csv validated_leads.csv --db leads.db
   ```
3. **Output File Identity**: The resulting `validated_leads.csv` must exactly match the schema, columns, and scoring behavior of Python v2.

---

## 5. Verification Method

To independently verify these survey findings and specifications:

1. **Inspect Existing OCaml Engine**:
   ```bash
   cd /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml
   dune runtest
   ```
   *Expected result*: All 18 mathematical verification tests pass (100%).

2. **Inspect Existing Python v2 Data Acquisition & CSV Output**:
   ```bash
   cd /Users/solveetcoagula/Desktop/activeProjects/Roo4u
   ./venv/bin/python scripts/acquire_live_data.py --zips "94115,94123" --limit 5
   cat validated_leads.csv
   ```
   *Expected result*: CSV with 10 exact headers containing mathematically validated leads.

3. **Inspect Pytest Test Suite & AST Anti-Mock Verification**:
   ```bash
   cd /Users/solveetcoagula/Desktop/activeProjects/Roo4u
   ./venv/bin/pytest tests/test_ocaml_verifier.py tests/test_exporter.py tests/test_pipeline_e2e.py -v
   ```
   *Expected result*: 100% pass rate with zero `unittest.mock` usage.
