# Handoff Report: Live Loopback Test Harness (Milestone 3)

**Agent**: Explorer M3-1  
**Working Directory**: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m3_1`  
**Target Milestone**: M3 — Programmatic Test Suite (Zero-Mock)  
**Deliverable**: `.agents/explorer_m3_1/test_harness_design.md`  
**Handoff Type**: Hard (Investigation & Architecture Complete)  

---

## 1. Observation

1. **Test Environment & Dependencies**:
   - Python virtual environment is at `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/venv/bin/python` running Python `3.14.7` and Pytest `9.1.1`.
   - Core libraries installed: `starlette==1.6.0`, `uvicorn==0.52.4`, `playwright==1.62.0`, `pydantic==2.13.5`, `openai==3.6.0`, `pytest-json-report==1.5.0`, `sqlalchemy==2.0.52`, `httpx==0.28.1`, `beautifulsoup4==4.15.0`.
   - Full baseline test suite execution (`./venv/bin/pytest tests/`) executed **246 tests with 100% pass rate** in 91.24s.

2. **Extractor Integration Contract (`agents/extractor.py:12-185`)**:
   - `LocalLLMExtractor` initializes `openai.OpenAI(base_url=self.base_url, api_key=self.api_key, timeout=self.timeout)`.
   - Defaults: `DEFAULT_LOCAL_URL = "http://localhost:8000/v1"`, `DEFAULT_LOCAL_MODEL = "nvidia/llama-3.1-nemotron-70b-instruct"`.
   - Sends `client.chat.completions.create(model=self.model, messages=[{"role": "system", ...}, {"role": "user", ...}], temperature=0.0, response_format={"type": "json_object"})`.
   - Validates output using `PropertyExtraction.model_validate_json()` (`agents/extractor.py:217`) and `CountyPermitExtraction.model_validate_json()` (`agents/extractor.py:256`).

3. **Browsing Agent Dynamic URL Discovery (`agents/zillow_agent.py:34`, `agents/county_agent.py:38-39`)**:
   - `ZillowAgent.base_url` defaults to `os.getenv("ZILLOW_BASE_URL", "https://www.zillow.com")`.
   - `CountyAgent.pim_base_url` defaults to `os.getenv("SF_PIM_BASE_URL", "https://sfplanninggis.org/pim/")`.
   - `CountyAgent.dbi_base_url` defaults to `os.getenv("SF_DBI_BASE_URL", "https://dbiweb02.sfgov.org/dbipts/")`.

4. **Zero-Mock Requirement (`ORIGINAL_REQUEST.md:18-29`, `TEST_INFRA.md:4-28`)**:
   - Strictly ZERO usage of `unittest.mock` or monkeypatched API responses.
   - Network interactions must bind to real TCP loopback sockets on `127.0.0.1`.

---

## 2. Logic Chain

1. **Inference Server Design**:
   - Because `LocalLLMExtractor` communicates via `openai.OpenAI` over HTTP to `http://localhost:8000/v1`, creating an ASGI Starlette application running on a background daemon thread with `uvicorn.Server` provides a real TCP socket endpoint (`127.0.0.1:8000`).
   - The Starlette server implements `/health`, `/v1/models`, and `POST /v1/chat/completions`.
   - By analyzing the system and user messages in the chat request, the server dynamically distinguishes between `PropertyExtraction` and `CountyPermitExtraction` requests and returns realistic, schema-valid JSON envelopes matching OpenAI ChatCompletion specifications.
   - Fault injection modes (malformed JSON, thinking tokens `<think>`, markdown fences, 429 rate limit, 500 server error, latency delays) are supported via request headers (`X-Test-Behavior`) and prompt markers to allow comprehensive error-handling and learning agent tests without mocks.

2. **HTML Fixture Server Design**:
   - Because `ZillowAgent` and `CountyAgent` query external web pages, running a secondary Starlette static fixture server on `127.0.0.1:8080` serving realistic HTML files from `tests/fixtures/` (`zillow_listing.html`, `zillow_search.html`, `sf_pim_assessor.html`, `sf_dbi_permits.html`, `blocked_403.html`) allows real Playwright browser navigation (`BaseAgent.safe_get_html`) against live local HTTP sockets.
   - Injecting `ZILLOW_BASE_URL`, `SF_PIM_BASE_URL`, and `SF_DBI_BASE_URL` environment variables redirects browsing agents to the local fixture server seamlessly.

3. **Database Isolation**:
   - SQLite tests require complete isolation to avoid concurrency locks or state contamination across tests.
   - Function-scoped `db_session` fixture creates an ephemeral SQLite database file per test, initializes the schema via `Base.metadata.create_all(engine)`, and tears it down cleanly upon fixture exit.

4. **Pytest JSON Reporting**:
   - Configuring `pytest.ini` with `-v --json-report --json-report-file=.test_report.json --json-report-summary` and adding `pytest_json_modifyreport` in `conftest.py` ensures that test run metrics, execution timestamps, and zero-mock verification metadata are preserved in `.test_report.json` for downstream Agent-As-Judge evaluation in Milestone 4.

---

## 3. Caveats

1. **Port Collisions**: If port 8000 or 8080 is already in use by an external service on the host, `BackgroundServer` will raise an `OSError: Address already in use`. The design supports ephemeral port binding or setting `LOCAL_INFERENCE_URL` / `ZILLOW_BASE_URL` overrides if necessary.
2. **Playwright Headless Performance**: Launching Playwright browser contexts for tests against the local HTML server takes ~100-300ms per browser launch. Tests should reuse session-scoped browser contexts where appropriate or use headless mode.
3. **Red-Team Anti-Mock Scanners**: Milestone 4 AST scanner will verify 0 occurrences of `from unittest.mock import ...` or `import unittest.mock` across the entire codebase. The designed `conftest.py` contains 0 mock imports.

---

## 4. Conclusion

The complete architectural blueprint and drop-in code for the Live Loopback Test Harness have been formulated in `.agents/explorer_m3_1/test_harness_design.md`.

Key components designed:
- **`tests/conftest.py`**: Starlette/Uvicorn live background inference server (`127.0.0.1:8000/v1`) + static HTML server (`127.0.0.1:8080`) + isolated SQLite database fixtures + JSON report hooks.
- **`tests/fixtures/`**: Realistic fixture pages for Zillow listing, search discovery, SF PIM assessor, SF DBI permit histories, 403 blocks, and empty search pages.
- **`pytest.ini`**: Automated JSON report output configuration.

This design enables Milestones 3, 4, and 5 to execute 100% mock-free tests, achieve 100% pass rates, and pass the independent Agent-As-Judge Victory Audit.

---

## 5. Verification Method

1. **Inspect Design Artifact**:
   - File: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m3_1/test_harness_design.md`
   - Verify that all endpoints, fixtures, thread lifecycles, and code blocks match requirements.
2. **Mock-Free AST Audit**:
   - Verify that `test_harness_design.md` specifies 0 imports of `unittest.mock` or `MagicMock`.
3. **Execution Command (Post-Implementation in Worker step)**:
   ```bash
   ./venv/bin/pytest -v --json-report --json-report-file=.test_report.json tests/
   ```
4. **Invalidation Conditions**:
   - If any test in `tests/` imports `unittest.mock` or mocks HTTP requests.
   - If the inference server fails to respond on `POST /v1/chat/completions` with valid JSON adhering to `PropertyExtraction` and `CountyPermitExtraction` schemas.
