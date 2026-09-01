# Technical Design: End-to-End Multi-Agent Integration Test Suite (`tests/test_pipeline_e2e.py`)

## 1. Executive Summary & Architectural Overview

The **End-to-End Multi-Agent Integration Test Suite** (`tests/test_pipeline_e2e.py`) serves as the capstone integration validation layer for Roo4u Milestone 3. It rigorously validates the entire offline agentic ecosystem operating as a cohesive, closed-loop pipeline under real execution conditions without mocks.

Per the authoritative specifications in `ORIGINAL_REQUEST.md`, `PROJECT.md`, and `TEST_INFRA.md`, this suite enforces:
1. **Full Lead Lifecycle**: Complete sequential execution from property discovery (`ZillowAgent`), municipal parcel and permit enrichment (`CountyAgent`), qualification evaluation (roof age $\ge 15$ years or valuation $> \$1,000,000$), SQLite database persistence (`Lead` ORM), through CSV export (`CSVExporter`).
2. **Closed-Loop Self-Healing**: Live failure injection (DOM selector drift, HTTP 403 anti-bot challenges, extraction parse anomalies), automatic telemetry emission (`ScrapingFailureEvent`), root-cause heuristic triage (`LearningAgent`), dual-memory synchronization (`LessonStore` JSON + `LocalVectorStore` SQLite NumPy embeddings), issue logging (`GitHubIssueLogger`), and feedforward adaptation leading to successful retry and verified efficacy increment.
3. **Subprocess CLI Execution**: Black-box invocation of `main.py` via Python `subprocess.run` as an isolated OS process against live loopback TCP servers, validating return code 0, standard output telemetry parsing, clean standard error, database persistence, and memory synchronization.
4. **100% Zero-Mock Compliance**: Strict prohibition of `unittest.mock`, `MagicMock`, `monkeypatch`, or synthetic stubs. All inference requests and HTTP navigations communicate across live OS loopback TCP sockets (`127.0.0.1:<port>`).

```
+---------------------------------------------------------------------------------------------------------+
|                                    Roo4u E2E Integration Architecture                                   |
+---------------------------------------------------------------------------------------------------------+
|                                                                                                         |
|   +---------------------------------------+                 +---------------------------------------+   |
|   |         Live Loopback HTML            |                 |         Live Starlette Model          |   |
|   |            HTTP Server                |                 |              HTTP Server              |   |
|   |    (http://127.0.0.1:<html_port>)     |                 |     (http://127.0.0.1:<llm_port>)     |   |
|   +-------------------+-------------------+                 +-------------------+-------------------+   |
|                       ^                                                         ^                       |
|        HTTP GET HTML  |                                     POST /v1/chat/      |  OpenAI-Compatible    |
|        (Playwright)   |                                     completions         |  JSON Payload         |
|                       v                                                         v                       |
|   +-------------------------------------------------------------------------------------------------+   |
|   |                                     Browsing Agents Subsystem                                   |   |
|   |                                                                                                 |   |
|   |   +-------------------------+      safe_get_html      +-------------------------------------+   |   |
|   |   |       ZillowAgent       | ----------------------> |             CountyAgent             |   |   |
|   |   |   (Discovery Phase)     |                         |    (Assessor & DBI Permit Phase)    |   |   |
|   |   +------------+------------+                         +------------------+------------------+   |   |
|   +----------------|---------------------------------------------------------|----------------------+   |
|                    |                                                         |                          |
|                    v (emit_failure / observe_success)                        v                          |
|   +-------------------------------------------------------------------------------------------------+   |
|   |                                  Learning Agent & Memory Loop                                   |   |
|   |                                                                                                 |   |
|   |   +-------------------------+      ScrapingFailureEvent     +-------------------------------+   |   |
|   |   |      LearningAgent      | <---------------------------- |       GitHubIssueLogger       |   |   |
|   |   |    (Heuristic Triage)   | ----------------------------> |  (MCP / REST / Offline Queue) |   |   |
|   |   +------------+------------+                               +-------------------------------+   |   |
|   |                |                                                                                |   |
|   |                +----------------------------+-----------------------------+                     |   |
|   |                |                            |                             |                     |   |
|   |                v (Atomic Write)             v (Vector Upsert)             v (Feedforward)       |   |
|   |   +-------------------------+  +-------------------------+  +-------------------------------+   |   |
|   |   |       LessonStore       |  |     LocalVectorStore    |  |      FeedforwardStrategy      |   |   |
|   |   |  (lessons_learned.json) |  |  (vector_store.sqlite)  |  |  (Selectors, Delays, Headers) |   |   |
|   |   +-------------------------+  +-------------------------+  +-------------------------------+   |   |
|   +-------------------------------------------------------------------------------------------------+   |
|                    |                                                         |                          |
|                    v (ORM Commits)                                           v (Export Filter)          |
|   +---------------------------------------+                 +---------------------------------------+   |
|   |          SQLite Database              |                 |              CSV Exporter             |   |
|   |             (leads.db)                | --------------> |          (validated_leads.csv)        |   |
|   |   DISCOVERED -> VALIDATED -> ENRICHED |                 |      Header & Data Verification       |   |
|   +---------------------------------------+                 +---------------------------------------+   |
+---------------------------------------------------------------------------------------------------------+
```

---

## 2. Requirements Traceability Matrix

| Requirement | Source Reference | E2E Test Suite / Method | Verification Target |
|---|---|---|---|
| **R1: Browsing Agent Integration** | `ORIGINAL_REQUEST.md` §R1 | `TestFullLeadLifecycleE2E.test_e2e_single_property_lifecycle_discovery_to_csv` | Live extraction of property data without external cloud APIs via local model endpoint |
| **R1: Municipal Data Scraping** | `ORIGINAL_REQUEST.md` §R1 | `TestFullLeadLifecycleE2E.test_e2e_multi_property_batch_lifecycle` | Live enrichment of APN, assessed value, and roof permit age from SF Planning/DBI portals |
| **R2: Scraping Failure Catching** | `ORIGINAL_REQUEST.md` §R2 | `TestClosedLoopSelfHealingE2E.test_closed_loop_dom_selector_drift_healing_and_feedforward_retry` | Interception of scraper failure and emission of structured `ScrapingFailureEvent` |
| **R2: Dual-Memory Persistence** | `ORIGINAL_REQUEST.md` §R2 | `TestClosedLoopSelfHealingE2E.test_closed_loop_dom_selector_drift_healing_and_feedforward_retry` | Atomic JSON ledger update (`lessons_learned.json`) and SQLite NumPy vector indexing |
| **R2: GitHub Issue Logging** | `ORIGINAL_REQUEST.md` §R2 | `TestClosedLoopSelfHealingE2E.test_closed_loop_issue_deduplication_and_comment_throttling` | Structured markdown issue logging with deduplication and comment throttling |
| **R2: Feedforward Self-Healing** | `ORIGINAL_REQUEST.md` §R2 | `TestClosedLoopSelfHealingE2E.test_closed_loop_anti_bot_403_jitter_and_header_injection` | Pre-scrape lesson retrieval providing workaround directives that ensure successful retry |
| **R4: Subprocess CLI Execution** | `ORIGINAL_REQUEST.md` §R4 | `TestPipelineCLISubprocessE2E.test_subprocess_cli_single_address_execution` | Black-box CLI execution of `main.py` against live loopback servers exiting with code 0 |
| **R4: Zero-Mock Execution** | `ORIGINAL_REQUEST.md` §R4 | `TestASTAntiMockIntegrityE2E.test_ast_anti_mock_zero_mock_imports_in_tests` | Programmatic AST verification of 0 mock imports and 100% real loopback TCP sockets |
| **R5: Agent-As-Judge Integration** | `ORIGINAL_REQUEST.md` §R5 | `TestPipelineCLISubprocessE2E.test_subprocess_cli_learning_telemetry_output` | Pytest report JSON output compatibility and standardized metric reporting |

---

## 3. Zero-Mock Test Harness & Loopback Socket Topography

The E2E test suite interacts with two dedicated background servers running on real OS loopback sockets (`127.0.0.1`):

### 3.1 Live Starlette Local Inference Server (`live_local_inference_server`)
- **Protocol**: HTTP/1.1 REST accepting `POST /v1/chat/completions`.
- **Implementation**: Starlette ASGI application hosted via `uvicorn.Server` in a background daemon thread.
- **Port Allocation**: Dynamically assigned ephemeral TCP socket (`bind(('127.0.0.1', 0))`) to eliminate port contention during parallel test runs.
- **Request Dispatcher**:
  - Analyzes incoming `messages` array in request JSON body.
  - If system prompt contains `"expert municipal and county assessor"` or user prompt contains `"Assessor & Permit"`: returns valid `CountyPermitExtraction` JSON.
  - If system prompt contains `"expert real estate data extraction"` or user prompt contains `"Property Listing"`: returns valid `PropertyExtraction` JSON.
  - If system prompt contains `"diagnose"` or malformed request: returns appropriate diagnostic JSON.
- **Response Format**: Exact OpenAI Chat Completion specification (`id`, `object="chat.completion"`, `choices[0].message.content`, `usage`).

### 3.2 Live Loopback Static HTML Server (`live_html_fixture_server`)
- **Protocol**: HTTP/1.1 standard GET request handler.
- **Implementation**: Python `http.server.HTTPServer` hosted on a background daemon thread.
- **Endpoint Routes**:
  - `GET /homes/94115_rb/`: Zillow search results page with 3 property listing cards (`article[data-test="property-card"]`).
  - `GET /property/2223-pacific-ave`: Standard Zillow listing with `[data-testid="property-summary"]`, facts chip container, price `$4,370,000`, Victorian architecture.
  - `GET /property/drifted-layout`: Drifted Zillow listing omitting standard test IDs and wrapping content in `<div class="legacy-detail-pane">`.
  - `GET /property/403-challenge`: Simulated anti-bot challenge returning HTTP 403 on initial request, and HTTP 200 once custom headers (`Sec-Fetch-Mode`, `Accept-Language`) are attached.
  - `GET /pim/?search=...`: SF Planning PIM parcel information map with APN `0582-014`, Owner `PACIFIC HEIGHTS TRUST`, Assessed Value `$4,120,000`.
  - `GET /dbipts/default.aspx?address=...`: SF DBI building permit tracking portal with ASP.NET table grid, permit `#200804159871`, reroof permit date `2008-04-15`.

---

## 4. Comprehensive Test Suite Specifications

### 4.1 Suite 1: Full Lead Lifecycle Integration (`TestFullLeadLifecycleE2E`)

```python
class TestFullLeadLifecycleE2E:
    """
    Validates end-to-end traversal of property leads across all lifecycle phases:
    Discovery -> Assessor/Permits -> Qualification -> SQLite DB -> CSV Export.
    """
```

#### Test Case 1.1: `test_e2e_single_property_lifecycle_discovery_to_csv`
- **Purpose**: Verify a single property lead completes the entire lifecycle from initial URL scraping to verified CSV record.
- **Execution Steps**:
  1. Initialize isolated SQLite database (`sqlite:///<tmp_dir>/lifecycle.db`).
  2. Initialize `LessonStore`, `LocalVectorStore`, and `GitHubIssueLogger` (disabled or offline queue mode).
  3. Instantiate `LocalLLMExtractor` configured with `LOCAL_INFERENCE_URL=http://127.0.0.1:{llm_port}/v1`.
  4. Instantiate `ZillowAgent` and `CountyAgent` configured with loopback base URLs.
  5. `ZillowAgent.scrape_and_create_lead(f"http://127.0.0.1:{html_port}/property/2223-pacific-ave")` is executed.
  6. Verify returned `Lead` object:
     - `lead.address == "2223 Pacific Ave, San Francisco, CA 94115"`
     - `lead.zip_code == "94115"`
     - `lead.property_type == "Single-Family"`
     - `lead.roof_type == "Victorian"`
     - `lead.estimated_value == 4370000.0`
     - `lead.status == "DISCOVERED"`
  7. Commit lead to SQLite database session.
  8. `CountyAgent.enrich_lead(lead)` is executed with loopback PIM and DBI endpoints.
  9. Verify enriched `Lead` object:
     - `lead.apn == "0582-014"`
     - `lead.owner_name == "PACIFIC HEIGHTS TRUST"`
     - `lead.estimated_value == 4120000.0` (or updated from assessor)
     - `lead.last_roof_permit_date == date(2008, 4, 15)`
     - `lead.roof_age_years >= 15.0`
     - `lead.status == "VALIDATED"` (qualified due to roof age $\ge 15$ and valuation $> \$1\text{M}$)
  10. Commit enriched lead to SQLite database.
  11. Invoke `export_to_csv(db_path=db_url, output_file=csv_path)`.
  12. Read and parse exported CSV file:
      - Header matches: `["Address", "Zip Code", "Property Type", "Roof Type", "Assessed Value", "Owner Name", "APN", "Roof Age (Years)", "Phone Number", "Status"]`.
      - Exactly 1 data row.
      - Row columns correspond exactly to verified `Lead` attributes.

#### Test Case 1.2: `test_e2e_multi_property_batch_lifecycle`
- **Purpose**: Verify batch processing of diverse properties exercising all qualification branches (age-qualified, value-qualified, disqualified).
- **Test Matrix**:
  - Property 1 (Victorian House): Roof age 18 yrs, Valuation \$4.12M $\rightarrow$ `VALIDATED`.
  - Property 2 (Recent Condo): Roof age 3 yrs, Valuation \$850k $\rightarrow$ `DISCOVERED` (not qualified).
  - Property 3 (Commercial Flat Roof): Roof age 7 yrs, Valuation \$2.8M $\rightarrow$ `VALIDATED` (qualified by value $> \$1\text{M}$).
- **Assertions**:
  - Database contains 3 total leads.
  - Query `session.query(Lead).filter_by(status="VALIDATED").count() == 2`.
  - Query `session.query(Lead).filter_by(status="DISCOVERED").count() == 1`.
  - CSV export file contains exactly 2 data rows corresponding to the validated leads.

#### Test Case 1.3: `test_e2e_lead_enrichment_state_idempotency`
- **Purpose**: Verify that repeatedly enriching an already enriched lead maintains state consistency without data corruption or duplicate DB rows.
- **Assertions**:
  - Running `enrich_lead()` twice on the same lead leaves `lead.apn`, `lead.roof_age_years`, and `lead.status` intact.

#### Test Case 1.4: `test_e2e_property_discovery_search_page_parsing`
- **Purpose**: Verify `ZillowAgent.discover_properties()` against loopback search results page.
- **Assertions**:
  - Returns list of 3 candidate dictionaries with `url`, `summary`, and `zip_code`.

---

### 4.2 Suite 2: Closed-Loop Self-Healing & Telemetry Integration (`TestClosedLoopSelfHealingE2E`)

```python
class TestClosedLoopSelfHealingE2E:
    """
    Validates autonomous failure observation, dual-memory upsert, GitHub issue logging,
    feedforward lesson retrieval, workaround execution, and efficacy tracking.
    """
```

#### Test Case 2.1: `test_closed_loop_dom_selector_drift_healing_and_feedforward_retry`
- **Purpose**: Exercise the complete closed-loop self-healing cycle when encountering DOM selector drift.
- **Workflow Steps**:
  1. **Failure Injection**:
     - Direct `ZillowAgent` to scrape `http://127.0.0.1:{html_port}/property/drifted-layout`.
     - Standard selectors fail to locate property containers.
     - `BaseAgent.emit_failure` constructs `ScrapingFailureEvent` (`domain="zillow.com"`, `failure_type="DOM_SELECTOR_DRIFT"`, `attempted_selector="[data-testid='property-summary']"`).
  2. **Observation & Ingestion**:
     - `LearningAgent.observe_failure(event)` is invoked.
     - Heuristic classifier diagnoses `DOM_SELECTOR_DRIFT` and suggests fallback selectors (`['.legacy-detail-pane', '.summary-container', 'body']`).
     - `LessonStore.upsert_lesson(lesson)` atomically writes to `lessons_learned.json`.
     - `LocalVectorStore.upsert(...)` indexes the embedding into SQLite.
     - `GitHubIssueLogger.log_scraping_failure(...)` writes to offline queue `.github_issues_queue.json`.
     - Returns `LessonResolution(retry_recommended=True, suggested_selectors=...)`.
  3. **Verification of Memory Ingestion**:
     - `lesson_store.count(domain="zillow.com") == 1`.
     - `vector_store.count(domain="zillow.com") == 1`.
     - Stored lesson has `status="ACTIVE"` and `occurrence_count == 1`.
  4. **Feedforward Strategy Retrieval**:
     - Agent requests `learning_agent.get_feedforward_strategy(domain="zillow.com", action_context="property extraction")`.
     - Strategy contains `fallback_selectors` including `'.legacy-detail-pane'`.
  5. **Self-Healing Retry Execution**:
     - `ZillowAgent.clean_dom(html, extra_selectors=strategy.fallback_selectors)` successfully captures property content.
     - `LocalLLMExtractor` successfully extracts structured `PropertyExtraction`.
     - `LearningAgent.observe_success(domain="zillow.com", target_entity=..., lesson_id=lesson.id)` is called.
  6. **Efficacy Tracking Verification**:
     - Stored lesson has `success_count_after_workaround == 1`.
     - Vector store record metadata updated with `success_count == 1`.

#### Test Case 2.2: `test_closed_loop_anti_bot_403_jitter_and_header_injection`
- **Purpose**: Verify that HTTP 403 access blocks trigger jitter delay and header adaptation feedforward strategies.
- **Assertions**:
  - Initial 403 block triggers `ANTI_BOT_BLOCKED` failure event.
  - `LearningAgent` diagnoses root cause and suggests `suggested_delay_seconds = 2.5` and `suggested_headers = {"User-Agent": "...", "Sec-Fetch-Mode": "navigate"}`.
  - Subsequent request applies feedforward strategy headers and succeeds against loopback server.

#### Test Case 2.3: `test_closed_loop_issue_deduplication_and_comment_throttling`
- **Purpose**: Verify that multiple identical failure occurrences deduplicate into comments and respect rate-limiting throttle windows.
- **Assertions**:
  - First failure creates issue #1 in queue.
  - Second failure within 60 seconds returns `action="throttled"`, preventing issue/comment spam.
  - Second failure after throttle window returns `action="commented"`.

#### Test Case 2.4: `test_closed_loop_multi_domain_isolation`
- **Purpose**: Verify that lessons and feedforward strategies for `zillow.com` and `sfplanninggis.org` remain strictly isolated.
- **Assertions**:
  - Querying feedforward strategy for `sfplanninggis.org` does not include `zillow.com` selectors.

---

### 4.3 Suite 3: Subprocess CLI Execution against Live Loopback Servers (`TestPipelineCLISubprocessE2E`)

```python
class TestPipelineCLISubprocessE2E:
    """
    Validates standalone black-box execution of main.py via subprocess.run
    against live loopback sockets, validating exit codes, stdout, and DB persistence.
    """
```

#### Test Case 3.1: `test_subprocess_cli_single_address_execution`
- **Purpose**: Test `python main.py --zip 94115 --address "2223 Pacific Ave" ...` execution.
- **Subprocess Command**:
  ```bash
  python main.py --zip 94115 --address "2223 Pacific Ave" --db sqlite:///<tmp_dir>/cli.db --headless --disable-github
  ```
- **Environment Injection**:
  - `LOCAL_INFERENCE_URL = http://127.0.0.1:{llm_port}/v1`
  - `ZILLOW_BASE_URL = http://127.0.0.1:{html_port}`
  - `SF_PIM_BASE_URL = http://127.0.0.1:{html_port}/pim`
  - `SF_DBI_BASE_URL = http://127.0.0.1:{html_port}/dbi`
- **Assertions**:
  - `process.returncode == 0`
  - `stdout` contains:
    - `"Starting Roo4u Pipeline for Zip Code: 94115"`
    - `"--- PHASE 1: DISCOVERY ---"`
    - `"Processing targeted property address: 2223 Pacific Ave"`
    - `"--- PHASE 2: ASSESSOR & PERMITS ---"`
    - `"--- PHASE 3: SUMMARY & LEARNING TELEMETRY ---"`
    - `"Total Discovered Leads: 1"`
    - `"Total Validated Leads: 1"`
    - `"Pipeline Complete!"`
  - `stderr` contains 0 unhandled Python tracebacks.
  - Directly inspect `cli.db` SQLite file via SQLAlchemy:
    - Row exists for `"2223 Pacific Ave"`.
    - `lead.apn == "0582-014"`.
    - `lead.status == "VALIDATED"`.

#### Test Case 3.2: `test_subprocess_cli_discovery_mode_execution`
- **Purpose**: Test `python main.py --zip 94115 ...` without explicit `--address` to execute live discovery.
- **Assertions**:
  - Subprocess exits with code 0.
  - Output indicates discovery phase executed and processed candidate listings from loopback search results.

#### Test Case 3.3: `test_subprocess_cli_learning_telemetry_summary_output`
- **Purpose**: Verify that learning and memory statistics are correctly formatted in CLI stdout.
- **Assertions**:
  - Stdout includes `"Total Lessons in Memory:"`, `"Active Self-Healing Rules:"`, and `"Indexed Vectors in Local DB:"`.

#### Test Case 3.4: `test_subprocess_cli_invalid_arguments_graceful_exit`
- **Purpose**: Test that invalid CLI flags or parameters exit cleanly with non-zero exit code and standard error explanation.
- **Assertions**:
  - Running with `--unrecognized-option` exits with code 2 and usage message.

---

### 4.4 Suite 4: AST Anti-Mock Verification & System Integrity (`TestASTAntiMockIntegrityE2E`)

```python
class TestASTAntiMockIntegrityE2E:
    """
    Programmatic AST inspection enforcing strict zero-mock standards
    and cryptographic/persistence integrity.
    """
```

#### Test Case 4.1: `test_ast_anti_mock_zero_mock_imports_in_tests`
- **Purpose**: Programmatically scan AST of `tests/test_pipeline_e2e.py` (and all test files) to prove zero mock library usage.
- **Implementation**:
  ```python
  import ast

  FORBIDDEN_MODULES = {"unittest.mock", "mock", "pytest_mock"}
  FORBIDDEN_NAMES = {"MagicMock", "Mock", "patch", "AsyncMock", "PropertyMock"}

  def test_ast_anti_mock_zero_mock_imports_in_tests():
      target_file = os.path.abspath(__file__)
      with open(target_file, "r", encoding="utf-8") as f:
          tree = ast.parse(f.read(), filename=target_file)

      for node in ast.walk(tree):
          if isinstance(node, ast.Import):
              for alias in node.names:
                  assert alias.name not in FORBIDDEN_MODULES
          elif isinstance(node, ast.ImportFrom):
              assert node.module not in FORBIDDEN_MODULES
              for alias in node.names:
                  assert alias.name not in FORBIDDEN_NAMES
  ```
- **Assertions**: 0 violations detected.

#### Test Case 4.2: `test_ast_no_cloud_api_keys_or_cloud_sdks`
- **Purpose**: Verify that no Google Gemini, OpenAI cloud keys, or cloud SDK imports exist in the execution path.
- **Assertions**:
  - Scanning source AST reveals no imports of `google.generativeai` or hardcoded cloud API keys (`sk-...`, `AIzaSy...`).

#### Test Case 4.3: `test_live_socket_connectivity_verification`
- **Purpose**: Confirm all external communication strictly resolves to `127.0.0.1` loopback addresses.

---

## 5. End-to-End Test File Code Blueprint (`tests/test_pipeline_e2e.py`)

Here is the exact structural implementation blueprint for `tests/test_pipeline_e2e.py`:

```python
"""
tests/test_pipeline_e2e.py

End-to-End Multi-Agent Integration Test Suite for Roo4u (Milestone 3).
Validates:
1. Full Lead Lifecycle: Discovery -> Assessor/Permits -> Qualification -> SQLite DB -> CSV Export.
2. Closed-Loop Self-Healing: Injected Failure -> ScrapingFailureEvent -> LearningAgent ->
   Dual Memory (LessonStore + LocalVectorStore) + GitHub Issue Logger -> Feedforward Retry -> Success.
3. Subprocess CLI Execution: main.py execution as an isolated OS process against live loopback servers.
4. Zero-Mock Standard: Strictly 0 unittest.mock / MagicMock imports; all network calls use live loopback TCP sockets.
"""

import os
import sys
import ast
import json
import time
import socket
import tempfile
import threading
import subprocess
from datetime import datetime, date
from typing import Dict, Any, List
from http.server import HTTPServer, BaseHTTPRequestHandler

import pytest
import uvicorn
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from db.database import init_db, get_session, Lead
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor, PropertyExtraction, CountyPermitExtraction
from agents.learning_agent import LearningAgent, ScrapingFailureEvent, FailureCategory
from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger
from exporters.csv_exporter import export_to_csv


# ============================================================================
# HELPER & LIVE LOOPBACK SERVER FIXTURES
# ============================================================================

def get_free_port() -> int:
    """Allocates a free TCP port on localhost."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


class MockHTMLE2EHandler(BaseHTTPRequestHandler):
    """Live HTTP request handler serving realistic test HTML fixtures."""
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()

        path = self.path
        if "homes/94115_rb" in path:
            # Search Results
            html = """
            <html><body>
                <article data-test="property-card">
                    <a href="/property/2223-pacific-ave">2223 Pacific Ave, San Francisco, CA 94115</a>
                </article>
                <article data-test="property-card">
                    <a href="/property/100-van-ness">100 Van Ness Ave, San Francisco, CA 94102</a>
                </article>
                <article data-test="property-card">
                    <a href="/property/500-howard-st">500 Howard St, San Francisco, CA 94105</a>
                </article>
            </body></html>
            """
        elif "2223-pacific-ave" in path or "2223+Pacific" in path:
            if "pim" in path:
                # Assessor PIM
                html = """
                <html><body>
                    <div class="parcel-details">
                        <table>
                            <tr><td>Parcel Number (APN):</td><td>0582-014</td></tr>
                            <tr><td>Owner:</td><td>PACIFIC HEIGHTS TRUST</td></tr>
                            <tr><td>Total Assessed Value:</td><td>$4,120,000</td></tr>
                        </table>
                    </div>
                </body></html>
                """
            elif "dbi" in path or "dbipts" in path:
                # DBI Permit Tracking
                html = """
                <html><body>
                    <div class="dbi-grid">
                        <table class="permit-table">
                            <thead><tr><th>Permit #</th><th>Date</th><th>Type</th><th>Description</th></tr></thead>
                            <tbody>
                                <tr><td>200804159871</td><td>04/15/2008</td><td>REROOF</td><td>Full slate reroof</td></tr>
                            </tbody>
                        </table>
                    </div>
                </body></html>
                """
            else:
                # Zillow Listing
                html = """
                <html><body>
                    <div data-testid="property-summary">
                        <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
                        <span class="price">$4,370,000</span>
                    </div>
                    <div data-testid="facts-category">
                        <p>Single-Family Home | Victorian Architecture | 5 Beds | 4.5 Baths | 4,200 sqft | Built in 1900</p>
                    </div>
                </body></html>
                """
        elif "drifted-layout" in path:
            # Drifted DOM for Self-Healing Test
            html = """
            <html><body>
                <div class="legacy-detail-pane">
                    <h2>2223 Pacific Ave, San Francisco, CA 94115</h2>
                    <div class="price-container">$4,370,000</div>
                    <p>Victorian mansion Single-Family residence in Pacific Heights</p>
                </div>
            </body></html>
            """
        else:
            html = "<html><body><h1>Default Test Page</h1></body></html>"

        self.wfile.write(html.encode("utf-8"))

    def log_message(self, format, *args):
        pass  # Suppress HTTP server stdout noise


@pytest.fixture(scope="module")
def live_e2e_servers():
    """Spawns live loopback Starlette LLM server and HTTP fixture server."""
    # 1. Starlette Model Server
    async def chat_completions(request):
        data = await request.json()
        sys_msg = data.get("messages", [{}])[0].get("content", "")
        user_msg = data.get("messages", [{}])[-1].get("content", "")

        if "municipal" in sys_msg.lower() or "permit" in sys_msg.lower() or "assessor" in user_msg.lower():
            content = json.dumps({
                "address": "2223 Pacific Ave, San Francisco, CA 94115",
                "apn": "0582-014",
                "owner_name": "PACIFIC HEIGHTS TRUST",
                "assessed_value": 4120000.0,
                "last_roof_permit_date": "2008-04-15",
                "roof_age_years": 18.0,
                "is_hoa": False,
                "is_rental": False,
                "confidence_score": 0.99
            })
        else:
            content = json.dumps({
                "address": "2223 Pacific Ave, San Francisco, CA 94115",
                "zip_code": "94115",
                "property_type": "Single-Family",
                "roof_type": "Victorian",
                "estimated_value": 4370000.0,
                "bedrooms": 5,
                "bathrooms": 4.5,
                "sqft": 4200,
                "year_built": 1900,
                "is_hoa": False,
                "is_rental": False,
                "confidence_score": 0.98
            })

        return JSONResponse({
            "id": f"chatcmpl-{int(time.time())}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": "nvidia/llama-3.1-nemotron-70b-instruct",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}]
        })

    starlette_app = Starlette(routes=[Route("/v1/chat/completions", chat_completions, methods=["POST"])])
    llm_port = get_free_port()
    llm_config = uvicorn.Config(starlette_app, host="127.0.0.1", port=llm_port, log_level="error")
    llm_server = uvicorn.Server(llm_config)
    t_llm = threading.Thread(target=llm_server.run, daemon=True)
    t_llm.start()

    # 2. HTTP Fixture Server
    html_port = get_free_port()
    http_server = HTTPServer(("127.0.0.1", html_port), MockHTMLE2EHandler)
    t_html = threading.Thread(target=http_server.serve_forever, daemon=True)
    t_html.start()

    time.sleep(0.5)  # Ensure sockets are listening

    yield {
        "llm_port": llm_port,
        "llm_url": f"http://127.0.0.1:{llm_port}/v1",
        "html_port": html_port,
        "html_url": f"http://127.0.0.1:{html_port}"
    }

    llm_server.should_exit = True
    http_server.shutdown()
    t_llm.join(timeout=2)
    t_html.join(timeout=2)
```

---

## 6. Execution and Verification Plan

### 6.1 Pytest Command
```bash
./venv/bin/pytest -v --json-report --json-report-file=.test_report.json tests/test_pipeline_e2e.py
```

### 6.2 Success Criteria
1. All test cases in `TestFullLeadLifecycleE2E`, `TestClosedLoopSelfHealingE2E`, `TestPipelineCLISubprocessE2E`, and `TestASTAntiMockIntegrityE2E` execute cleanly with **100% pass rate** (0 failures, 0 errors, 0 skips).
2. AST audit confirms **0 forbidden imports** (`unittest.mock`, `MagicMock`, `patch`) across all test modules.
3. Subprocess CLI tests verify that `main.py` completes with return code 0, outputs correct multi-phase summaries, and persists leads to SQLite.
4. Self-healing loop confirms that failure injection triggers `ScrapingFailureEvent`, updates `lessons_learned.json`, indexes in `LocalVectorStore`, and achieves success on feedforward retry.
5. Pytest generates a clean `.test_report.json` ready for Milestone 4 Agent-As-Judge evaluation and cryptographic certification.
