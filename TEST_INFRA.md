# E2E Test Infra: Roo4u

## Test Philosophy
- **Requirement-Driven & Opaque-Box**: Derived directly from `ORIGINAL_REQUEST.md`.
- **Zero-Mock Standard**: Strictly zero usage of `unittest.mock`, `MagicMock`, or monkeypatched API responses for external/model endpoints. All network calls during tests bind to live loopback TCP sockets (`127.0.0.1:8000`, `127.0.0.1:<port>`) or live GitHub MCP connections.
- **Methodology**: Category-Partition + Boundary Value Analysis + Pairwise Combinations + Real-World Workload Testing.

## Feature Inventory
| # | Feature | Source (Requirement) | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---------|----------------------|:------:|:------:|:------:|:------:|
| 1 | Local Inference Extractor | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ | ✓ |
| 2 | Browsing & Scraping Agents | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ | ✓ |
| 3 | Cloud API Decoupling | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ | ✓ |
| 4 | Failure Observation Loop | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ | ✓ |
| 5 | Dual-Storage Memory (`lessons_learned.json` & Vector DB) | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ | ✓ |
| 6 | Live GitHub MCP Issue Logger | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ | ✓ |
| 7 | Agent-As-Judge Evaluator & Rubric | ORIGINAL_REQUEST §R5 | 5 | 5 | ✓ | ✓ |
| 8 | Digital Certification & Sign-off | ORIGINAL_REQUEST §R5 | 5 | 5 | ✓ | ✓ |

## Test Architecture
- **Test Runner**: `pytest -v --json-report --json-report-file=.test_report.json tests/`
- **Pass/Fail Semantics**: All tests must exit with code 0. Agent-As-Judge verifies 0 failures and 0 mock violations.
- **Live Fixture Harness (`tests/conftest.py`)**:
  - `live_local_inference_server`: Spawns a lightweight live Starlette/Uvicorn HTTP server at `http://127.0.0.1:8000/v1` serving real OpenAI-compatible `/v1/chat/completions` JSON responses over real TCP sockets.
  - `live_html_fixture_server`: Spawns a background Python `http.server` serving realistic Zillow and SF Planning HTML fixtures over local TCP.
  - `live_db_session`: Fresh SQLite in-memory / temporary database session for lead management.
  - `live_github_client`: Interacts with real `github-mcp-server` / GitHub endpoints.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | End-to-End Zillow Property Extraction with Local Model | F1, F2, F3 | Medium |
| 2 | End-to-End County Permit Portal Scraping with Local Model | F1, F2, F3 | Medium |
| 3 | Scraping Failure Interception, GitHub Issue Creation & Vector Upsert | F4, F5, F6 | High |
| 4 | Feedforward Lesson Retrieval Preventing Re-Failure | F2, F4, F5 | High |
| 5 | Full Pipeline Run: Scraping → Enrichment → DB Commit → CSV Export → Learning Loop | F1, F2, F4, F5, F6 | High |
| 6 | Agent-As-Judge End-to-End Evaluation & Digital PASS Sign-off | F7, F8 | Medium |

## Coverage Thresholds
- Tier 1 (Feature Coverage): ≥40 test cases across all 8 features
- Tier 2 (Boundary & Corner Cases): ≥40 test cases covering empty inputs, malformed HTML, timeouts, selector drift, vector collisions
- Tier 3 (Cross-Feature): Multi-agent interaction pairs (Extractor ↔ Local Server, Browsing ↔ Learning, Learning ↔ VectorStore, Pipeline ↔ Judge)
- Tier 4 (Real-World Application): ≥6 complete workflow test cases
- **Total Minimum Target**: ≥100 test cases
