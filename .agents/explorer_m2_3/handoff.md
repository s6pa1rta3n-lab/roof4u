# Handoff Report — Explorer M2-3 (Learning Agent & Feedforward Loop)

## 1. Observation

1. **Current Codebase State:**
   - `agents/base_agent.py` (lines 40–47): `BaseAgent.get_html()` navigates via `self.page.goto(url, wait_until="domcontentloaded")` with zero `try/except` blocks, no timeout handling, no HTTP status code checks (403/429), and no failure event emission.
   - `agents/zillow_agent.py` (lines 84–96, 116–140): `scrape_property()` and `discover_properties()` rely on static CSS selectors (e.g. `[data-testid="property-summary"]`, `article[data-test="property-card"]`). In `discover_properties()` (lines 139–140), errors are swallowed via `except Exception: return []` without telemetry or root-cause logging.
   - `agents/county_agent.py` (lines 95–125, 127–179): Municipal assessor and permit lookups (`lookup_assessor_record`, `lookup_permit_history`) use static URL queries and CSS selectors with silent `except Exception: pass` blocks (lines 154, 173).
   - `main.py` (lines 28–31, 57–93, 100–111): `ZillowAgent` and `CountyAgent` are instantiated directly without any learning agent, memory store, or telemetry interception.
2. **Requirements & Blueprints:**
   - `ORIGINAL_REQUEST.md §R2`: "Implement the observation and memory loop. The agent must catch scraping failures, log them as GitHub issues (via MCP or API), and update a local `lessons_learned.json` and Vector DB."
   - `PROJECT.md §Interface Contracts`: Defines `ScrapingFailureEvent`, `observe_failure()`, and `retrieve_lessons()`.
3. **Peer Agent Interfaces:**
   - `explorer_m2_1` (`memory/`): Specifies `LessonStore` (`lessons_learned.json` atomic reader/writer) and `LocalVectorStore` (`memory/vector_store.sqlite` NumPy + SQLite cosine similarity index).
   - `explorer_m2_2` (`integrations/`): Specifies `GitHubIssueLogger` supporting MCP `issue_write`/`add_issue_comment` with REST fallback and title/domain deduplication targeting `s6pa1rta3n-lab/roof4u`.

---

## 2. Logic Chain

1. **Failure Interception Necessity:** From Observation 1, because existing agents either crash or silently swallow exceptions, an explicit `ScrapingFailureEvent` telemetry schema and `emit_failure()` helper must be added to `BaseAgent` so all subclasses (`ZillowAgent`, `CountyAgent`) can uniformly report failures without code duplication.
2. **Deterministic Root-Cause Diagnosis:** To comply with the offline zero-cloud-API requirement (`ORIGINAL_REQUEST.md §Acceptance Criteria`), `LearningAgent` must implement a deterministic, rule-based heuristic classifier (Tier 1) for DOM drift, 403 bot blocks, 429 rate limits, and schema validation errors, with an optional local LLM diagnostic path (Tier 2 via `http://localhost:8000/v1`).
3. **Dual-Memory Synchronization:** By binding `LessonStore.upsert_lesson()` and `LocalVectorStore.upsert()` inside `LearningAgent.observe_failure()`, every newly diagnosed failure mode is immediately available for human inspection (`lessons_learned.json`) and semantic search (`vector_store.sqlite`).
4. **Feedforward Prevention Loop:** Rather than only reacting post-failure, scrapers calling `LearningAgent.get_feedforward_strategy(domain)` before navigating can inject fallback selectors, apply request delays, and attach custom headers dynamically, eliminating repeated failures.
5. **Immediate In-Process Self-Healing:** When a scraper catches an extraction or selector exception, passing the event to `observe_failure()` yields a `LessonResolution` containing a `suggested_retry_action`, allowing the scraper to perform an instant fallback attempt in the same process before failing the lead.

---

## 3. Caveats

1. **Local Model Availability:** The Tier 2 local LLM diagnostic path assumes `http://localhost:8000/v1` is running; if unreachable, the system falls back entirely to Tier 1 heuristic classification without disruption.
2. **Browser Context Headers:** In Playwright sync mode, setting extra HTTP headers is performed per `BrowserContext`; if `context` is recreated across requests, headers must be re-applied via `get_feedforward_strategy()`.
3. **Selector Heuristic Scope:** Initial heuristic rules cover Zillow, SF PIM, and SF DBI portals. Additional municipal portals will benefit from the local LLM root cause analysis or manual rule additions.

---

## 4. Conclusion

The Learning Agent and Feedforward Observation Loop architecture has been fully specified in `.agents/explorer_m2_3/learning_loop_design.md`. It provides:
- A complete `LearningAgent` class in `agents/learning_agent.py` supporting `observe_failure()`, dual-memory synchronization, GitHub issue logging, and `retrieve_lessons()`.
- Non-invasive, robust telemetry hooks in `BaseAgent`, `ZillowAgent`, and `CountyAgent`.
- A dynamic feedforward strategy engine enabling pre-scrape selector fallback and anti-bot mitigation.
- Full pipeline integration and summary telemetry reporting in `main.py`.
- Complete interface compatibility with Explorer M2-1 (`LessonStore`, `LocalVectorStore`) and Explorer M2-2 (`GitHubIssueLogger`).

---

## 5. Verification Method

To independently verify the specification and deliverables:

1. **Inspect Design Specification:**
   - Read `.agents/explorer_m2_3/learning_loop_design.md` to verify all method signatures, data models (`ScrapingFailureEvent`, `Lesson`, `FeedforwardStrategy`, `LessonResolution`), and wiring patterns.
2. **Check Interface Alignment:**
   - Compare `learning_loop_design.md` against `.agents/explorer_m2_1/BRIEFING.md` (`LessonStore`, `LocalVectorStore`) and `.agents/explorer_m2_2/BRIEFING.md` (`GitHubIssueLogger`) to confirm exact parameter and model compatibility.
3. **Implementation Plan Validation:**
   - Verify that all proposed changes in `agents/base_agent.py`, `agents/zillow_agent.py`, `agents/county_agent.py`, `agents/learning_agent.py`, and `main.py` are mock-free and offline-compliant.
4. **Test Suite Verification (for Milestone 3 implementers):**
   - Execute `pytest tests/test_learning_agent.py` once implemented to verify zero-mock loopback testing of failure observation, memory updates, and feedforward retrieval.
