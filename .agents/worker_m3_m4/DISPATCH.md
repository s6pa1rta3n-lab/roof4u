## 2026-09-01T04:45:50-04:00

You are the Worker assigned to implement Milestone 3 (Programmatic Test Suite Zero-Mock) and Milestone 4 (Agent-As-Judge Evaluator & Digital Sign-off) in Roo4u.

Your working directory is: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/worker_m3_m4
Project workspace root: /Users/solveetcoagula/Desktop/activeProjects/Roo4u
Original user request: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ORIGINAL_REQUEST.md
Architecture blueprint: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/PROJECT.md
Test infrastructure blueprint: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/TEST_INFRA.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your Tasks:
1. Initialize DISPATCH.md, BRIEFING.md, and progress.md in your working directory.
2. Implement Milestone 3 (Programmatic Zero-Mock Test Infrastructure & E2E Suites):
   a. In `tests/conftest.py`:
      - Implement a real, live loopback inference server fixture using `starlette` and `uvicorn` (or `http.server`) running on `http://127.0.0.1:8000/v1` in a background daemon thread that handles real TCP socket requests to `/v1/chat/completions` and `/v1/models` in OpenAI-compatible JSON format.
      - Implement a real live local HTML fixture server fixture serving realistic HTML fixtures for Zillow property pages and SF Planning / DBI permit pages over local TCP sockets.
      - Ensure fixtures cleanly start, bind to ports, and terminate without hanging.
   b. In `tests/test_pipeline_e2e.py`:
      - Implement end-to-end integration tests that exercise the full multi-agent flow (Discovery with ZillowAgent -> Assessor & Permits with CountyAgent -> DB persistence in SQLite -> CSV Export -> Scraping failure interception -> GitHub issue queueing -> Vector store feedforward retrieval) against live local loopback servers.
      - Strictly zero usage of `unittest.mock` or monkeypatching for external/model endpoints.
3. Implement Milestone 4 (Agent-As-Judge Evaluator & Certification):
   a. In `agents/judge_agent.py`:
      - Implement `AgentAsJudge` class with full evaluation capabilities:
        - `scan_ast(repo_path: str)`: Scans all Python source and test files using `ast.walk` to detect forbidden imports (`unittest.mock`, `MagicMock`, `mock`, monkeypatching in core code), hardcoded API keys (`sk-...`, `AIza...`), and empty facade functions.
        - `parse_test_report(report_path: str)`: Parses pytest JSON report (`.test_report.json` or `report.json`) and test execution stdout logs, verifying 100% pass rate, total tests executed, and failure counts.
        - `evaluate_5d_rubric(...)`: Evaluates across the 5 dimensions from `PROJECT.md §14`:
          1. Security & Credentials (25 pts)
          2. Anti-Mock Integrity (25 pts)
          3. Functional Correctness (25 pts)
          4. Self-Healing & Learning (15 pts)
          5. Runtime Performance (10 pts)
        - `certify(test_report_path: str, output_path: str)`: Produces `CERTIFIED_PASS.json` and human-readable `CERTIFICATION_REPORT.md` with SHA-256 digital signature over results, repository commit/file tree state, rubric scores, and timestamp.
   b. In `scripts/run_judge.py`:
      - CLI runner that executes the full pytest suite with `--json-report`, runs `AgentAsJudge`, prints rubric score table, and outputs `CERTIFIED_PASS.json`.
4. Execute the test suite and run judge script:
   - `./venv/bin/pytest -v --json-report --json-report-file=.test_report.json`
   - `./venv/bin/python scripts/run_judge.py`
5. Verify that `CERTIFIED_PASS.json` is generated with 100.0 score and PASS status.
6. Write a 5-component `handoff.md` in your working directory and report back.
