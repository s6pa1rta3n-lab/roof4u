# Project: Roo4u - Offline Agentic Architecture

## Architecture
Roo4u is an offline-first agentic web scraping, memory, and automated lead evaluation system for real estate and roofing leads. It completely decouples from cloud LLMs, routing all intelligence tasks to a local OpenAI-compatible inference endpoint (`http://localhost:8000/v1`) designed for open-source models (e.g., NVIDIA NIM / local LLM). It features a self-healing observation loop with dual-storage memory (`lessons_learned.json` and a local SQLite+NumPy `LocalVectorStore`), live GitHub issue logging via `github-mcp-server`, a live-endpoint pytest test suite (100% mock-free for external endpoints), and an independent Agent-As-Judge evaluator providing cryptographically verifiable PASS certifications.

### Core Modules
- **`agents/`**:
  - `base_agent.py`: Playwright browser lifecycle, DOM retrieval, failure hooks.
  - `extractor.py`: Local LLM extraction client routing to `http://localhost:8000/v1` with Pydantic validation.
  - `zillow_agent.py`: Zillow property data scraper with DOM preprocessing and error telemetry.
  - `county_agent.py`: County assessor and permit portal scraper with error telemetry.
  - `learning_agent.py`: Self-healing orchestrator managing failure observation, GitHub issue logging, dual-memory upsert, and pre-scrape lesson retrieval.
  - `judge_agent.py`: Independent Agent-As-Judge evaluating test outputs, AST security/mock checks, rubric scoring, and digital certification.
- **`memory/`**:
  - `lesson_store.py`: Atomic read/write operations on root `lessons_learned.json`.
  - `vector_store.py`: Embedded SQLite + NumPy vector database for offline cosine similarity search.
  - `embeddings.py`: Local embedding generator with deterministic offline fallback.
- **`integrations/`**:
  - `github_client.py`: Dual-transport GitHub issue manager using `github-mcp-server` tools with REST API fallback and deduplication.
- **`db/`**:
  - `database.py`: SQLAlchemy SQLite lead management and persistence (`leads.db`).
- **`exporters/`**:
  - `csv_exporter.py`: CSV export for validated and enriched leads.
- **`tests/`**:
  - Live network loopback test harness, static HTML servers, mock-free E2E test suites, and fixtures.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Cloud API Decoupling | Purge all Google Gemini, OpenAI cloud keys, and cloud SDKs from execution path | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Local Inference Routing | Refactor `extractor.py` to route inference to `http://localhost:8000/v1` via OpenAI-compatible API | M1 | ORIGINAL_REQUEST §R1 |
| 3 | Concrete Scraping Agents | Implement `zillow_agent.py` and `county_agent.py` with DOM preprocessing and failure hooks | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Main Pipeline Wiring | Wire concrete browsing agents into `main.py` pipeline | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Scraping Failure Observation | Intercept scraping failures in `BaseAgent` and convert to `ScrapingFailureEvent` | M2 | ORIGINAL_REQUEST §R2 |
| 6 | GitHub Issue Logger | Dual-transport issue logger via `github-mcp-server` & REST API with deduplication | M2 | ORIGINAL_REQUEST §R2 |
| 7 | Lessons Learned Storage | Atomic read/write manager for root `lessons_learned.json` | M2 | ORIGINAL_REQUEST §R2 |
| 8 | Local Vector DB | Embedded SQLite + NumPy cosine similarity vector database for offline retrieval | M2 | ORIGINAL_REQUEST §R2 |
| 9 | Feedforward Lesson Retrieval | Query past lessons before scraping to apply workarounds and prevent failure repeats | M2 | ORIGINAL_REQUEST §R2 |
| 10 | Zero-Mock Test Infrastructure | Live loopback Starlette inference server and HTML fixture servers in `conftest.py` | M3 | ORIGINAL_REQUEST §R4 |
| 11 | Comprehensive Test Suites | 100% passing pytest suites for DB, BaseAgent, Extractor, Zillow, County, Learning, VectorStore, Exporter, E2E | M3 | ORIGINAL_REQUEST §R4 |
| 12 | Test Log & Report Parser | Parser for pytest JSON/terminal reports and test metrics | M4 | ORIGINAL_REQUEST §R5 |
| 13 | AST Security & Anti-Mock Scanner | AST scanner detecting forbidden imports (`unittest.mock`, `MagicMock`), cloud keys, and secrets | M4 | ORIGINAL_REQUEST §R5 |
| 14 | 5-Dimension Rubric Engine | Scoring engine (Security, Anti-Mock, Correctness, Self-Healing, Performance) with zero-tolerance hard gates | M4 | ORIGINAL_REQUEST §R5 |
| 15 | Digital Sign-off & Certification | SHA-256 hashed `CERTIFIED_PASS.json` and human-readable certification markdown report | M4 | ORIGINAL_REQUEST §R5 |
| 16 | Final E2E Verification & Certification | 100% pass on all E2E test suites, Agent-As-Judge PASS certification, and clean audit | M5 | ORIGINAL_REQUEST §Acceptance Criteria |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Browsing Agent & Local Model Integration | Decouple cloud APIs, refactor extractor for `localhost:8000`, implement Zillow & County agents, wire `main.py` | none | DONE |
| 2 | M2: Learning Agent Pipeline & Dual Memory | Implement failure interception, `lessons_learned.json`, `LocalVectorStore`, GitHub issue logging | M1 | DONE |
| 3 | M3: Programmatic Test Suite (Zero-Mock) | Implement live loopback test server fixtures, test modules, achieve 100% pytest pass rate without `unittest.mock` | M1, M2 | IN_PROGRESS |
| 4 | M4: Agent-As-Judge Evaluator & Certification | Implement AST scanner, log parser, 5-dimension rubric engine, SHA-256 digital sign-off | M3 | PLANNED |
| 5 | M5: Final E2E Verification & Audit Gate | Execute full suite against live endpoints, run Judge certification, obtain clean Forensic Audit | M1, M2, M3, M4 | PLANNED |

## Interface Contracts

### Browsing Agent ↔ Local Inference Endpoint
- **URL**: `http://localhost:8000/v1/chat/completions` (configurable via `LOCAL_INFERENCE_URL` env var, default `http://localhost:8000/v1`)
- **Protocol**: OpenAI Chat Completions API format (`POST /v1/chat/completions`)
- **Request Payload**:
  ```json
  {
    "model": "nvidia/nemotron-3-8b-instruct",
    "messages": [
      {"role": "system", "content": "You are a real estate and permit data extraction engine..."},
      {"role": "user", "content": "<preprocessed_html_or_text>"}
    ],
    "temperature": 0.0,
    "response_format": {"type": "json_object"}
  }
  ```
- **Response Validation**: Validated via Pydantic model `PropertyExtraction` (`address`, `estimated_value`, `bedrooms`, `bathrooms`, `sqft`, `year_built`, `roof_type`, `permit_history`, `confidence_score`).

### Browsing Agent ↔ Learning Agent
- **Failure Telemetry Event (`ScrapingFailureEvent`)**:
  - `domain`: str (e.g. "zillow.com", "sfplanning.org")
  - `url`: str
  - `failure_type`: str (e.g. "DOM_SELECTOR_DRIFT", "TIMEOUT", "ANTI_BOT", "PARSE_ERROR")
  - `error_message`: str
  - `dom_snippet`: Optional[str]
  - `timestamp`: datetime
- **Bidirectional Methods**:
  - `observe_failure(event: ScrapingFailureEvent) -> Lesson`
  - `retrieve_lessons(domain: str, context_query: str) -> List[Lesson]`

### Learning Agent ↔ GitHub Logger
- **Transport**: Primary `github-mcp-server` tool calls (`issue_write`, `list_issues`, `add_issue_comment`); Fallback GitHub REST API (`https://api.github.com/repos/s6pa1rta3n-lab/roof4u/issues`).
- **Target Repository**: `s6pa1rta3n-lab/roof4u`
- **Issue Deduplication**: Check existing open issues for matching title/domain before creating new; append comment to existing if found.

### Agent-As-Judge ↔ Pipeline / CI
- **Input**: Pytest JSON output (`report.json`), stdout test logs, repository AST.
- **Output**: `CERTIFIED_PASS.json` with signature:
  ```json
  {
    "certification_id": "CERT-20260901-ROO4U",
    "status": "PASS",
    "overall_score": 100.0,
    "rubric_scores": {
      "security_and_credentials": 25.0,
      "anti_mock_integrity": 25.0,
      "functional_correctness": 25.0,
      "self_healing_and_learning": 15.0,
      "runtime_performance": 10.0
    },
    "sha256_digest": "...",
    "timestamp": "..."
  }
  ```

## Code Layout
- `agents/`:
  - `base_agent.py`
  - `extractor.py`
  - `zillow_agent.py`
  - `county_agent.py`
  - `learning_agent.py`
  - `judge_agent.py`
- `memory/`:
  - `lesson_store.py`
  - `vector_store.py`
  - `embeddings.py`
- `integrations/`:
  - `github_client.py`
- `db/`:
  - `database.py`
- `exporters/`:
  - `csv_exporter.py`
- `tests/`:
  - `conftest.py`
  - `fixtures/`
  - `test_database.py`
  - `test_base_agent.py`
  - `test_extractor.py`
  - `test_zillow_agent.py`
  - `test_county_agent.py`
  - `test_learning_agent.py`
  - `test_vector_store.py`
  - `test_github_client.py`
  - `test_exporter.py`
  - `test_pipeline_e2e.py`
- `scripts/`:
  - `run_judge.py`
  - `local_model_server.py`
- `lessons_learned.json`
- `main.py`
- `requirements.txt`
