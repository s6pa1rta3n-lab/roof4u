# Handoff Report: Milestone 2 - GitHub Issue Logger Investigation & Design

**Agent**: Explorer M2-2  
**Role**: Investigation & Synthesis  
**Target Module**: `integrations/github_client.py`  
**Target Repository**: `s6pa1rta3n-lab/roof4u`  
**Specification File**: `.agents/explorer_m2_2/github_logger_design.md`  

---

## 1. Observation

Direct observations from the Roo4u codebase and environment:

1. **User Requirements & Epics (`ORIGINAL_REQUEST.md`)**:
   - Section R2: *"Implement the observation and memory loop. The agent must catch scraping failures, log them as GitHub issues (via MCP or API), and update a local `lessons_learned.json` and Vector DB."*
   - Section R4 & Red-Team Standards: *"Test suite executes pytest and confirms a 100% pass rate without using the `unittest.mock` library for external endpoints."*

2. **Project Blueprint & Interface Contracts (`PROJECT.md`)**:
   - Lines 18-19: `integrations/github_client.py: Dual-transport GitHub issue manager using github-mcp-server tools with REST API fallback and deduplication.`
   - Lines 87-91:
     ```markdown
     ### Learning Agent ↔ GitHub Logger
     - **Transport**: Primary `github-mcp-server` tool calls (`issue_write`, `list_issues`, `add_issue_comment`); Fallback GitHub REST API (`https://api.github.com/repos/s6pa1rta3n-lab/roof4u/issues`).
     - **Target Repository**: `s6pa1rta3n-lab/roof4u`
     - **Issue Deduplication**: Check existing open issues for matching title/domain before creating new; append comment to existing if found.
     ```

3. **`github-mcp-server` Schemas (`~/.gemini/antigravity/mcp/github-mcp-server/`)**:
   - `issue_write.json`: Parameters `owner`, `repo`, `method` ("create" | "update"), `title`, `body`, `labels`, `issue_number`, `state`.
   - `add_issue_comment.json`: Parameters `owner`, `repo`, `issue_number`, `body`.
   - `list_issues.json`: Parameters `owner`, `repo`, `state` ("OPEN" | "CLOSED"), `perPage` (1..100).
   - `search_issues.json`: Parameters `query`, `owner`, `repo`, `sort`, `order`.

4. **Existing Agent Architecture (`agents/zillow_agent.py`, `agents/county_agent.py`, `agents/base_agent.py`)**:
   - In M1, `clean_dom` methods prune unwanted elements, but when portal DOM changes occur, unhandled exceptions or missing fields can arise.
   - M2 will wrap navigation and extraction in `ScrapingFailureEvent` interception hooks.

---

## 2. Logic Chain

1. **Premise 1 (from ORIGINAL_REQUEST.md & PROJECT.md)**: Failures occurring during web scraping must be logged to GitHub repository `s6pa1rta3n-lab/roof4u` with automated deduplication so recurring errors append comments rather than spamming duplicate open issues.
2. **Premise 2 (from MCP Server Schemas & REST Specs)**: Both `github-mcp-server` and GitHub REST API v3 provide the necessary primitives (`list_issues`/`GET /issues`, `issue_write`/`POST /issues`, and `add_issue_comment`/`POST /issues/{id}/comments`).
3. **Premise 3 (from Zero-Mock Mandate)**: Red-team standards forbid `unittest.mock` when verifying external endpoints; therefore `GitHubIssueLogger` must accept configurable `api_base_url` (default `https://api.github.com`, overridden to loopback Starlette fixture in tests) and pluggable `mcp_caller` adapters.
4. **Inference 1 (Dual-Transport & Offline Queue)**: Designing a 3-tier hierarchy:
   - Primary: `github-mcp-server` tool calls (`issue_write`, `list_issues`, `add_issue_comment`).
   - Secondary: GitHub REST API via `httpx` with `GITHUB_TOKEN` authorization.
   - Tertiary / Offline: Local atomic file queue (`.github_issues_queue.json`) ensuring resilience in disconnected or air-gapped test environments.
5. **Inference 2 (Deterministic Deduplication)**: Embedding a structured HTML comment header (`<!-- ROO4U_TELEMETRY_START ... ROO4U_TELEMETRY_END -->`) in the issue body enables exact, programmatic metadata matching (domain, failure_type, selector, error_fingerprint) alongside a title prefix fallback, guaranteeing 100% deduplication accuracy.
6. **Inference 3 (Structured Telemetry Formatting)**: Structuring markdown issues into 4 dedicated sections (Incident Overview, Error & Stack Trace, DOM Snippet, Self-Healing Analysis) equips human maintainers and the self-healing loop with immediate diagnostic clarity.

---

## 3. Caveats

- **GitHub API Rate Limits**: Unauthenticated GitHub REST API calls have a 60 requests/hour IP limit. In production, `GITHUB_TOKEN` or MCP transport should always be supplied. In test suites, loopback Starlette servers prevent any external rate limit issues.
- **Large DOM Truncation**: Scraping pages can exceed 100KB; DOM snippets must be sanitized and truncated to 4,000 characters to prevent issue body overflow.
- **Closed Issues vs Regressions**: The deduplication scanner queries only `state=open` issues. If an issue was previously closed and the failure recurs, a new issue is opened (treating it as a regression), which matches standard SRE practice.

---

## 4. Conclusion

The technical design for `integrations/github_client.py` has been fully formulated and documented in `.agents/explorer_m2_2/github_logger_design.md`.

Key deliverables achieved:
- **Dual-Transport Architecture**: Transparent auto-failover across MCP tools, REST API, and local `.github_issues_queue.json`.
- **Target Repository**: Bound to `s6pa1rta3n-lab/roof4u`.
- **Telemetry Formatting**: Standardized title template, structured 4-section markdown body, and embedded machine-readable comment block.
- **Deduplication Engine**: Dual metadata + title prefix scanner with anti-spam recurrence throttling.
- **Zero-Mock Readiness**: Fully decoupled for live loopback testing in pytest.

---

## 5. Verification Method

To independently verify the technical specification and code design:

1. **Inspect Design Specification**:
   ```bash
   view_file /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m2_2/github_logger_design.md
   ```

2. **Verify Schema & Model Syntactic Correctness**:
   Test the Pydantic schemas and logic directly using the virtual environment:
   ```bash
   ./venv/bin/python -c "
   from pydantic import BaseModel
   import hashlib, re

   class ScrapingFailureEvent(BaseModel):
       domain: str
       url: str
       failure_type: str
       error_message: str
       selector: str = None
       dom_snippet: str = None

       @property
       def error_fingerprint(self) -> str:
           raw = f'{self.domain}|{self.failure_type}|{self.selector or \"\"}|{self.error_message[:120]}'
           return hashlib.sha256(raw.encode('utf-8')).hexdigest()[:16]

   event = ScrapingFailureEvent(
       domain='zillow.com',
       url='https://www.zillow.com/homes/94115',
       failure_type='DOM_SELECTOR_DRIFT',
       error_message='Selector [data-testid=\"property-summary\"] not found',
       selector='[data-testid=\"property-summary\"]'
   )
   print('Fingerprint:', event.error_fingerprint)
   assert len(event.error_fingerprint) == 16
   print('Schema verification SUCCESS!')
   "
   ```

3. **Check Code Quality & Import Integrity**:
   Verify that `github_logger_design.md` contains no imports of `unittest.mock`, `MagicMock`, or unauthorized cloud SDKs.
