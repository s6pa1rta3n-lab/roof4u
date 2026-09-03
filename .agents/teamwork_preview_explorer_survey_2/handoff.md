# Comprehensive Survey Report: Roo4u Pure OCaml Architecture & Migration Blueprint

**Working Directory**: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/teamwork_preview_explorer_survey_2`  
**Project Root**: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u`  
**Date**: 2026-09-01  
**Author**: Explorer Survey Agent (`teamwork_preview_explorer_survey_2`)  
**Mission**: Complete architectural mapping of Roo4u Python components for a 100% pure OCaml rewrite.

---

## 1. Observation

Direct investigation of the Roo4u repository revealed the complete structure, implementation contracts, data schemas, and runtime dependencies of the existing system:

### 1.1 Project Structure & File Catalog
```
/Users/solveetcoagula/Desktop/activeProjects/Roo4u/
├── ORIGINAL_REQUEST.md               # Requirements & Acceptance Criteria
├── PROJECT.md                        # Architecture, feature inventory, milestones, contracts
├── README.md                         # Project overview and specifications
├── TEST_INFRA.md                     # Zero-mock test philosophy & coverage tiers
├── CERTIFIED_PASS.json               # Signed cryptographic certification artifact (M4)
├── CERTIFICATION_REPORT.md           # Markdown evaluation audit report
├── main.py                           # Python orchestration pipeline (lines 1-204)
├── requirements.txt                  # Python dependencies
├── lessons_learned.json              # Root JSON memory ledger (323 lines)
├── leads.db                          # SQLite lead database
├── validated_leads.csv               # CSV export artifact
├── agents/
│   ├── base_agent.py                 # Playwright lifecycle & telemetry emission (lines 1-219)
│   ├── extractor.py                  # Local LLM client & Pydantic models (lines 1-267)
│   ├── zillow_agent.py               # Property discovery agent & DOM pruning (lines 1-254)
│   ├── county_agent.py               # Assessor (PIM) & DBI permit agent (lines 1-279)
│   ├── learning_agent.py             # Closed-loop cognitive healer & dual memory (lines 1-391)
│   └── judge_agent.py                # AST security scanner & 5D rubric certifier (lines 1-593)
├── db/
│   └── database.py                   # SQLAlchemy SQLite Lead model (lines 1-52)
├── memory/
│   ├── embeddings.py                 # Deterministic 256-D feature hashing generator (lines 1-119)
│   ├── lesson_store.py               # Thread-safe atomic JSON lesson store (lines 1-264)
│   ├── vector_store.py               # Embedded SQLite + NumPy vector database (lines 1-378)
│   └── vector_store.sqlite           # SQLite vector database file
├── integrations/
│   ├── github_client.py              # Dual-transport MCP/REST issue manager (lines 1-615)
│   └── ocaml_verifier.py             # Subprocess bridge to roof_verif_cli (lines 1-100)
├── exporters/
│   └── csv_exporter.py               # CSV export engine (lines 1-37)
├── scripts/
│   ├── acquire_live_data.py          # DataSF municipal pipeline & OCaml verifier (lines 1-342)
│   └── run_judge.py                  # CLI runner for Agent-As-Judge (lines 1-122)
├── skills/                           # Antigravity skill definitions (5 subdirectories)
│   ├── mathematical-qualification/SKILL.md
│   ├── self-healing-learning/SKILL.md
│   ├── lead-export-actionability/SKILL.md
│   ├── discovery-agent/SKILL.md
│   └── assessor-permit-enrichment/SKILL.md
├── ocaml/                            # Existing OCaml mathematical verification library
│   ├── dune-project                  # (lang dune 3.0), name roof_verif, version 2.0.0
│   ├── roof_verif.opam               # Opam package definition
│   ├── bin/
│   │   ├── dune                      # Executable roof_verif_cli (libraries: roof_verif str)
│   │   └── main.ml                   # CLI entrypoint for verification (lines 1-63)
│   ├── lib/
│   │   ├── dune                      # Library roof_verif (libraries: str; modules: types invariants parser)
│   │   ├── types.ml                  # Formal algebraic data types (lines 1-78)
│   │   ├── invariants.ml             # 4 Formal invariants & scoring engine (lines 1-232)
│   │   └── parser.ml                 # Zero-dependency JSON parser/serializer (lines 1-231)
│   └── test/
│       ├── dune                      # Test runner definition
│       └── test_verif.ml             # Unit tests for invariants and parser (lines 1-137)
└── tests/                            # 468 zero-mock Python test cases
```

### 1.2 OCaml Toolchain Environment
- **OCaml Version**: `5.5.0` (`/opt/homebrew/bin/ocamlc`)
- **Dune Version**: `3.24.2` (`/opt/homebrew/bin/dune`)
- **Installed Standard Libraries**: `unix`, `str`, `threads`, `dynlink`, `camlinternalFormat`, `digest` (MD5), `sys`, `buffer`, `hashtbl`, `scanf`, `printf`.
- **External Opam Package Manager**: Not installed in PATH; code must rely on pure OCaml standard libraries and self-contained modules.
- **Build Status**: `dune build` and `dune runtest` in `ocaml/` succeed with exit code 0.

---

## 2. Logic Chain: Component-by-Component Analysis

### 2.1 Component 1: Local LLM Inference Client
#### Exact Python Architecture (`agents/extractor.py`)
- **Inference URL**: Configurable via `LOCAL_INFERENCE_URL` (default `http://localhost:8000/v1`).
- **Target Model**: `nvidia/llama-3.1-nemotron-70b-instruct` (or `LOCAL_MODEL_NAME`).
- **Endpoint Protocol**: OpenAI Chat Completions API (`POST /v1/chat/completions`).
- **Payload Schema**:
  ```json
  {
    "model": "nvidia/llama-3.1-nemotron-70b-instruct",
    "messages": [
      {"role": "system", "content": "<SYSTEM_PROMPT>"},
      {"role": "user", "content": "<USER_CONTENT>"}
    ],
    "temperature": 0.0,
    "response_format": {"type": "json_object"}
  }
  ```
- **Prompt Specifications**:
  1. *Property Extraction Prompt* (`extract_property_details`): Analyzes raw listing HTML/text (truncated to 16,000 characters) and requests a JSON object with:
     - `address` (string), `zip_code` (5-digit string), `property_type` (Single-Family, Condo, Multi-Family), `roof_type` (Victorian, Flat, Pitched, Mansard, Unknown), `is_hoa` (boolean), `is_rental` (boolean), `estimated_value` (number/null), `bedrooms` (int/null), `bathrooms` (number/null), `sqft` (int/null), `year_built` (int/null), `description` (string/null), `confidence_score` (number 0.0-1.0).
  2. *County Permit Prompt* (`extract_county_permit_details`): Analyzes municipal portal HTML/text (truncated to 16,000 characters) and requests a JSON object with:
     - `address` (string), `apn` (string/null), `owner_name` (string/null), `assessed_value` (number/null), `last_roof_permit_date` (string/null), `permit_history` (list of `{permit_number, permit_type, description, issued_date, status}`), `roof_age_years` (number/null), `is_hoa` (boolean), `is_rental` (boolean), `confidence_score` (number).
- **Response Cleaning & Fallback Cleansing Engine (`_clean_json_response`)**:
  1. Regex removal of thinking/reasoning tags: `<think(?:ing)?>.*?</think(?:ing)?>` and `<thought>.*?</thought>`.
  2. Extraction of fenced markdown codeblocks: ```` ```(?:json)?\s*([\s\S]*?)\s*``` ````.
  3. Balanced brace scanner: Iterates character-by-character tracking nesting `depth`, handling string escaping `\"`, `\\` to isolate valid `{ ... }` blocks.
  4. Trimming and fallback substring search between first `{` and last `}`.
  5. Schema normalization (e.g. zip code extraction via `\b\d{5}\b`, default values for `roof_type='Unknown'`, `is_hoa=false`, `confidence_score=1.0`).

#### OCaml Port Requirements for Component 1
- **Module `Llm_client`**:
  - Implements an HTTP 1.1 client using `Unix` sockets to connect to `localhost:8000`.
  - Builds the `POST /v1/chat/completions` request headers and JSON payload.
  - Receives response chunks, parses HTTP status line and chunked/content-length response bodies.
- **Module `Json_cleaner`**:
  - Pure functional regex and character-scanning parser removing `<think>` blocks and extracting balanced `{...}` JSON substrings.
- **Data Types in OCaml**:
  ```ocaml
  type property_extraction = {
    address : string;
    zip_code : string;
    property_type : string;
    roof_type : string;
    is_hoa : bool;
    is_rental : bool;
    estimated_value : float option;
    bedrooms : int option;
    bathrooms : float option;
    sqft : int option;
    year_built : int option;
    description : string option;
    confidence_score : float;
  }
  ```

---

### 2.2 Component 2: Dual Memory Stores (SQLite & JSON File Store)
#### 2.2.1 SQLite Database (`db/database.py`, `leads.db`)
- **Table `leads`**:
  ```sql
  CREATE TABLE leads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      address TEXT NOT NULL UNIQUE,
      zip_code TEXT NOT NULL,
      property_type TEXT,
      roof_type TEXT,
      estimated_value REAL,
      owner_name TEXT,
      is_hoa BOOLEAN DEFAULT 0,
      is_rental BOOLEAN DEFAULT 0,
      apn TEXT,
      last_roof_permit_date DATE,
      roof_age_years REAL,
      phone_number TEXT,
      created_at DATE DEFAULT CURRENT_TIMESTAMP,
      status TEXT DEFAULT 'DISCOVERED'
  );
  ```
- **State Machine**:
  - `DISCOVERED`: Discovered from Zillow or DataSF initial search.
  - `ENRICHED`: Assessor parcel number (APN) and permit history attached.
  - `VALIDATED`: Formally qualified by passing all mathematical invariants ($S(L) \ge 60.0$).
  - `DISCARDED` / `DISQUALIFIED`: Fails physical, temporal, or economic invariants.

#### 2.2.2 Local Vector Database (`memory/vector_store.py`, `memory/vector_store.sqlite`)
- **Table `vector_records`**:
  ```sql
  CREATE TABLE vector_records (
      id TEXT PRIMARY KEY,
      domain TEXT NOT NULL,
      failure_type TEXT,
      text TEXT NOT NULL,
      metadata_json TEXT NOT NULL,
      embedding BLOB NOT NULL,
      created_at TEXT NOT NULL
  );
  CREATE INDEX idx_vrec_domain ON vector_records(domain);
  CREATE INDEX idx_vrec_ftype ON vector_records(failure_type);
  CREATE INDEX idx_vrec_created ON vector_records(created_at);
  ```
- **Embedding Algorithm (`memory/embeddings.py`)**:
  - Fixed dimensionality: $D = 256$ float32 values ($1024$ bytes per BLOB).
  - Multi-scale tokenization:
    * HTTP status codes `\b(4\d\d|5\d\d)\b` -> `status:<code>` with weight $3.0$.
    * Lexical words `[a-z0-9_\-\.:#\[\]=\"]+` -> `w:<word>` with weight $1.5$.
    * Word bigrams -> `bi:<w1>_<w2>` with weight $2.0$.
    * Subword character 3-grams -> `3g:<tri>` with weight $0.5$.
    * Subword character 4-grams -> `4g:<quad>` with weight $0.5$.
  - Feature hashing:
    * Bucket index $i = \text{CRC32}(\text{token}) \pmod{256}$.
    * Sign $s = (\text{MD5}(\text{token})[0] \ \& \ 1 == 0) \ ? \ +1.0 : -1.0$.
    * Accumulation: $V[i] \mathrel{+}= s \times \text{weight}$.
    * L2 Normalization: $V = V / \sqrt{\sum V_j^2}$.
  - Search Mechanism: Batch dot product matrix multiplication $\mathbf{S} = \mathbf{M} \cdot Q$, sorting descending, filtering by domain, failure_type, and minimum similarity threshold.

#### 2.2.3 JSON File Store (`memory/lesson_store.py`, `lessons_learned.json`)
- **Schema (`Lesson`)**:
  - `id` (string, deterministic SHA-256 fingerprint), `domain` (string), `url` / `source_url` (string), `failure_type` / `error_category` (string), `error_message` (string), `lesson_learned` / `root_cause_analysis` (string), `recommended_action` / `recommended_workaround` (string), `suggested_selectors` (list of string), `suggested_delay_seconds` (float), `suggested_headers` (dict of string:string), `github_issue_number` (int/null), `github_issue_url` (string/null), `timestamp` (ISO-8601 string), `dom_snippet` (string/null), `resolved` (bool), `status` (`ACTIVE`, `RESOLVED`, `PROBATION`, `DEPRECATED`), `occurrence_count` (int), `success_count_after_workaround` (int), `target_entity` (string/null), `phase` (string/null).
- **Atomic POSIX Persistence**:
  - Creates a temporary file in the same directory (`tempfile.NamedTemporaryFile` / `.tmp`).
  - Dumps indented JSON.
  - Flushes buffer and executes `os.fsync` (or `Unix.fsync`).
  - Atomically replaces target file via `os.replace` (or `Sys.rename`).
- **Corruption Recovery**:
  - On JSON parse error or empty file, backs up corrupted file to `lessons_learned.json.corrupt.<timestamp>_<id>` and writes a fresh empty JSON array `[]`.
- **Self-Healing Resolution**:
  - When a scraping task succeeds after applying a workaround, `increment_success(lesson_id)` increments `success_count_after_workaround`.
  - Once count reaches $\ge 5$, status transitions to `RESOLVED` and `resolved = true`.

#### OCaml Port Requirements for Component 2
- **Module `Embeddings`**:
  - Pure OCaml 256-D feature hasher using `Digest.string` for MD5 signs, custom CRC32 calculation, and float array arithmetic.
- **Module `Lesson_store`**:
  - Full CRUD operations with atomic file write (`openfile`, `fsync`, `rename`) and corruption recovery.
- **Module `Vector_store`**:
  - SQLite database interface or memory-mapped binary vector store supporting cosine similarity search across 256-D float vectors.
- **Module `Db`**:
  - SQLite persistence layer for `leads.db` executing standard SQL statements via Unix command interface or direct C/file database routines.

---

### 2.3 Component 3: Git Telemetry & Failure Logging
#### Exact Python Architecture (`integrations/github_client.py`)
- **Telemetry Event Model (`ScrapingFailureEvent`)**:
  - Captures `domain`, `url`, `failure_type`, `error_message`, `selector`, `stack_trace`, `dom_snippet`, `suggested_fix`, `lead_address`, `phase`, `timestamp`.
  - Error Fingerprint: `sha256(f"{domain}|{failure_type}|{selector or ''}|{error_message[:120]}").hexdigest()[:16]`.
- **Dual-Transport GitHub Issue Logger**:
  - **Primary Transport**: `github-mcp-server` tool calls (`list_issues`, `issue_write`, `add_issue_comment`).
  - **Fallback Transport**: GitHub REST API (`https://api.github.com/repos/s6pa1rta3n-lab/roof4u/issues`).
  - **Offline Fallback Queue**: `.github_issues_queue.json` with atomic append and `flush_offline_queue`.
- **Deduplication Engine (`find_duplicate_issue`)**:
  - Searches open issues for embedded telemetry block:
    ```markdown
    <!-- ROO4U_TELEMETRY_START
    domain: zillow.com
    url: https://www.zillow.com/homes/94115_rb/
    failure_type: DOM_SELECTOR_DRIFT
    selector: article[data-test="property-card"]
    fingerprint: 5f2f01cfecd2e2ec
    timestamp: 2026-09-01T09:23:24.775388+00:00
    lead_address: 94115
    ROO4U_TELEMETRY_END -->
    ```
  - If a matching fingerprint or `domain + failure_type + selector` is found, appends a recurrence comment instead of creating a duplicate issue.
- **Anti-Spam Throttling**:
  - Enforces a 60-second cooldown per fingerprint before posting recurrence comments.
- **Audit Trails & Agent-As-Judge Certification (`agents/judge_agent.py`)**:
  - AST Scanner: Traverses Python/OCaml ASTs detecting forbidden mock libraries and hardcoded cloud keys.
  - File Tree Digest: Computes SHA-256 hash for every project file and generates combined `file_tree_hash`.
  - Digital Certificate: Generates `CERTIFIED_PASS.json` and `CERTIFICATION_REPORT.md` with SHA-256 signature.

#### OCaml Port Requirements for Component 3
- **Module `Telemetry`**:
  - Record types for `scraping_failure_event` and `issue_log_result`.
  - SHA-256 fingerprint generation function.
  - Markdown telemetry block formatter and parser.
- **Module `Github_client`**:
  - HTTPS / MCP client managing issue creation, deduplication search, comment appending, and offline file queuing.
- **Module `Audit_certifier`**:
  - Repository integrity scanner computing SHA-256 file digests and emitting digital sign-off certificates.

---

### 2.4 Component 4: Core Pipeline Orchestration & Agent Loop
#### Exact Python Workflow (`main.py` & `scripts/acquire_live_data.py`)
1. **Initialization**:
   - Initializes database `leads.db`.
   - Initializes `LessonStore("lessons_learned.json")`, `LocalVectorStore("memory/vector_store.sqlite")`, and `GitHubIssueLogger`.
   - Injects stores into `LearningAgent`.
2. **Phase 1: Discovery (`ZillowAgent` / `DataSF` API)**:
   - Queries target zip codes (`94115`, `94123`, `94118`, `94109`).
   - Retrieves active feedforward directives (`get_feedforward_strategy`): injects delay, rotated headers, and fallback CSS selectors.
   - Fetches HTML / API data -> prunes DOM (`clean_dom` removing scripts, styles, nav, footer, limiting to 12,000 chars).
   - Local LLM extracts structured property attributes.
   - Saves lead as `DISCOVERED` in `leads.db`.
   - On error: triggers `LearningAgent.observe_failure` -> diagnoses failure -> upserts lesson & vector DB -> logs to GitHub -> adaptive retry.
3. **Phase 2: Assessor & Permit Enrichment (`CountyAgent` / `DataSF`)**:
   - Queries SF Planning PIM for APN, owner name, assessed valuation, HOA/rental flags.
   - Queries SF DBI PTS / DataSF permit records for reroofing permits and dates.
   - Multi-format date parsing normalizes permit dates to `YYYY-MM-DD`.
   - Calculates `roof_age_years = current_year - last_permit_year` (or `year_built`).
   - Updates lead record in `leads.db` to status `ENRICHED`.
4. **Phase 3: Mathematical Verification & Invariant Enforcement (`roof_verif_cli`)**:
   - Enforces 4 formal algebraic invariants:
     * $\text{INV}_1$ (Physical): $\text{Roof} \in \{\text{Victorian}, \text{Flat}, \text{Mansard}\} \land \text{Type} \in \{\text{SingleFamily}, \text{MultiUnit2To4}\}$.
     * $\text{INV}_2$ (Temporal): $\text{RoofAge} \ge 15.0 \lor (\text{YearBuilt} \le 1996 \land \text{NoPermit})$.
     * $\text{INV}_3$ (Economic): $\text{AssessedValue} \ge \$1,000,000 \land \neg\text{HOA} \land \neg\text{Rental}$.
     * $\text{INV}_4$ (Permit Recency): $\forall p \in \text{Permits}, \text{is\_roof} \implies (\text{CurrentYear} - p.\text{year}) \ge 15$.
   - Computes deterministic actionability score $S(L) = C_{\text{age}} + C_{\text{val}} + C_{\text{type}} \in [0.0, 100.0]$.
   - Qualified leads transition to status `VALIDATED`.
5. **Phase 4: CSV Export (`csv_exporter.py`)**:
   - Exports all `VALIDATED` leads to `validated_leads.csv`.
6. **Phase 5: Self-Healing Success Loop**:
   - Calls `observe_success(domain, address, lesson_id)` when a workaround succeeds, incrementing success counters and resolving active lessons.

#### OCaml Port Requirements for Component 4
- **Module `Pipeline`**:
  - Full native OCaml pipeline executing Discovery $\to$ Enrichment $\to$ Invariant Verification $\to$ SQLite Persistence $\to$ CSV Export $\to$ Learning Loop.
- **Module `Csv_exporter`**:
  - Standardized CSV export generating `validated_leads.csv` with exact schema parity.

---

## 3. Caveats

1. **External Package Availability**: The system environment possesses standard OCaml 5.5.0 and Dune 3.24.2 with standard libraries (`unix`, `str`, `threads`, `dynlink`), but no external opam packages are installed. All OCaml modules (HTTP client, JSON parser, SHA-256, embedding math, CSV export, SQLite interface) must be implemented using pure standard OCaml and standard Unix system libraries or self-contained modules.
2. **Browser Execution in OCaml**: Playwright is a Node.js/Python library. For OCaml data acquisition, the system must interface directly with live municipal JSON endpoints (DataSF `i98e-djp9.json`, `tyz3-vt28.json`), local HTML fixture loopback servers, or lightweight headless HTTP/DOM retrieval via Unix sockets / curl.
3. **Database Concurrency**: The SQLite database files (`leads.db` and `vector_store.sqlite`) require WAL mode and lock management to guarantee multi-threaded and multi-process integrity during pipeline runs.

---

## 4. Conclusion

The Roo4u Python codebase consists of well-defined, modular subsystems that map cleanly to standard OCaml modules:

| Subsystem | Existing Python Modules | Proposed OCaml Module |
|---|---|---|
| **Local LLM Inference** | `agents/extractor.py` | `Llm_client.ml`, `Json_cleaner.ml` |
| **Mathematical Qualification** | `integrations/ocaml_verifier.py` | `Roof_verif.Invariants`, `Roof_verif.Types` |
| **Dual Memory (JSON Store)** | `memory/lesson_store.py` | `Lesson_store.ml` |
| **Dual Memory (Vector DB)** | `memory/vector_store.py`, `memory/embeddings.py` | `Embeddings.ml`, `Vector_store.ml` |
| **Database & Persistence** | `db/database.py` | `Db.ml` |
| **Git & Telemetry Logger** | `integrations/github_client.py` | `Telemetry.ml`, `Github_client.ml` |
| **Self-Healing Learning Agent** | `agents/learning_agent.py` | `Learning_agent.ml` |
| **Browsing & Municipal Data** | `agents/zillow_agent.py`, `agents/county_agent.py`, `scripts/acquire_live_data.py` | `Data_acquisition.ml` |
| **Actionable Lead Exporter** | `exporters/csv_exporter.py` | `Csv_exporter.ml` |
| **Core Orchestration Engine** | `main.py` | `Main.ml` (or `Pipeline.ml`) |
| **Security & Rubric Evaluator** | `agents/judge_agent.py`, `scripts/run_judge.py` | `Judge_evaluator.ml` |

---

## 5. Verification Method

To independently verify the facts, observations, and findings in this survey report:

1. **Verify OCaml Toolchain & Existing Build**:
   ```bash
   cd /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml
   dune build
   dune runtest
   ```
   *Expected outcome*: Zero compilation warnings/errors, 100% test pass on `test_verif.ml`.

2. **Inspect Existing Data and Schema Stores**:
   ```bash
   sqlite3 /Users/solveetcoagula/Desktop/activeProjects/Roo4u/leads.db ".schema leads"
   sqlite3 /Users/solveetcoagula/Desktop/activeProjects/Roo4u/memory/vector_store.sqlite ".schema vector_records"
   head -n 30 /Users/solveetcoagula/Desktop/activeProjects/Roo4u/lessons_learned.json
   ```

3. **Verify Existing Verification Proof Execution**:
   ```bash
   /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml/_build/default/bin/main.exe --json '{"address": "2223 Pacific Ave", "zip_code": "94115", "property_type": "Single-Family", "roof_type": "Victorian", "estimated_value": 3500000.0, "roof_age_years": 22.0, "is_hoa": false, "is_rental": false}'
   ```
   *Expected outcome*: Outputs JSON proof with `"status": "QUALIFIED"`, actionability score $\ge 85.0$, and proof digest.

4. **Verify Digital Certification Artifacts**:
   ```bash
   cat /Users/solveetcoagula/Desktop/activeProjects/Roo4u/CERTIFIED_PASS.json
   ```
   *Expected outcome*: Valid JSON with 100.0 rubric score and status `PASS`.
