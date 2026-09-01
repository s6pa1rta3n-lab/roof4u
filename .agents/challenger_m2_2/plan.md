# Empirical Stress-Testing Plan — Challenger M2-2

## Objective
Thoroughly stress-test and challenge Milestone 2 deliverables:
1. `GitHubIssueLogger` deduplication engine, recurrence comment throttling, transport failover, and offline queue concurrency.
2. `LearningAgent` failure observation, root cause classification across all categories, feedforward strategy synthesis, and success efficacy tracking.
3. Closed-loop integration with `BaseAgent`, `ZillowAgent`, `CountyAgent`, and `main.py`.

## Test Dimensions & Stress Harnesses

### Section 1: GitHubIssueLogger Telemetry & Deduplication
- **Test 1.1**: Deduplication metadata regex stress (newlines, extra fields, trailing spaces, case variations, special characters in selectors).
- **Test 1.2**: Deduplication title fallback matching (matching titles without metadata blocks, partial selectors, long truncated titles).
- **Test 1.3**: Anti-spam comment recurrence throttling precision (sub-second bursts, clock boundaries, expiration transitions).
- **Test 1.4**: Multi-threaded concurrency stress on `log_scraping_failure` (10 simultaneous threads emitting identical and distinct errors).
- **Test 1.5**: Offline queue resilience under corrupted/truncated queue JSON, directory creation, atomic file swap verification.
- **Test 1.6**: Offline queue partial flush error handling (transport accepts first issue, fails second, verifies unflushed items remain preserved).
- **Test 1.7**: Large issue list pagination/scale handling (50+ open issues scanning).

### Section 2: LearningAgent Root-Cause Diagnostic & Strategy Synthesis
- **Test 2.1**: Exhaustive classification boundary tests across all 8 `FailureCategory` enums and arbitrary string aliases (case-insensitivity, substring triggers, status code tokens).
- **Test 2.2**: Domain-specific selector generation matrix (`zillow.com`, `sfplanninggis.org`, `dbiweb02.sfgov.org`, unknown domains).
- **Test 2.3**: Dual-memory atomic upsert consistency (verifying `LessonStore` JSON and `LocalVectorStore` SQLite remain in sync).
- **Test 2.4**: Semantic retrieval filtering and rank ordering (verifying domain isolation, occurrence weighting, and `DEPRECATED` status exclusion).
- **Test 2.5**: Feedforward strategy compilation stress (selector order preservation, deduplication, max delay selection, header propagation, blocker aggregation).
- **Test 2.6**: Closed-loop success tracking and auto-resolution transition after 5 consecutive workaround successes.

### Section 3: Agent Integration & Self-Healing Pipeline
- **Test 3.1**: `BaseAgent.safe_get_html` feedforward delay and header injection verification.
- **Test 3.2**: `BaseAgent.safe_get_html` automatic failure telemetry emission on HTTP 403 / 429 and network timeout exceptions.
- **Test 3.3**: `ZillowAgent.clean_dom` with dynamic feedforward selector prepending and token budget capping.
- **Test 3.4**: `ZillowAgent.scrape_property` adaptive fallback extraction retry upon extraction parse errors.
- **Test 3.5**: `ZillowAgent.discover_properties` selector drift anomaly detection when 0 cards found in non-empty HTML.
- **Test 3.6**: `CountyAgent.parse_permit_date` boundary tests (2-digit years, 4-digit years, historic formats, invalid dates).
- **Test 3.7**: `CountyAgent.enrich_lead` qualification rules (roof age >= 15 vs estimated value > $1M).
- **Test 3.8**: `main.py` CLI pipeline execution with custom flags (`--disable-learning`, `--disable-github`, `--address`, `--db`).
