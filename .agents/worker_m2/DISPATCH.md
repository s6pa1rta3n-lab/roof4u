# Dispatch for Worker M2 (Milestone 2 Implementation)

You are Worker M2.
Working directory: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/worker_m2
Project root: /Users/solveetcoagula/Desktop/activeProjects/Roo4u

Authoritative User Request: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ORIGINAL_REQUEST.md
Project Blueprint: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/PROJECT.md

Explorer Specifications to Follow:
- `.agents/explorer_m2_1/memory_design.md` (Dual Memory: `LessonStore`, `OfflineEmbeddingGenerator`, `LocalVectorStore`)
- `.agents/explorer_m2_2/github_logger_design.md` (GitHub Issue Logger: `GitHubIssueLogger`)
- `.agents/explorer_m2_3/learning_loop_design.md` (Learning Agent & Feedforward Loop: `LearningAgent`, `ScrapingFailureEvent`, telemetry hooks, `main.py`)

Your Tasks:
1. Implement `memory/lesson_store.py`:
   - `Lesson` Pydantic model.
   - `LessonStore` class with atomic write protocol (`tempfile.NamedTemporaryFile` + `os.fsync` + `os.replace`), thread lock (`threading.RLock`), corruption recovery, `add_lesson`, `get_lesson`, `list_lessons`, `update_lesson`, `delete_lesson`, `count`, `clear`.
2. Implement `memory/embeddings.py`:
   - `OfflineEmbeddingGenerator` class (256-D float32 normalized vectors via deterministic feature hashing, subwords, and status codes).
3. Implement `memory/vector_store.py`:
   - `VectorRecord`, `SearchResult` dataclasses.
   - `LocalVectorStore` class (SQLite WAL mode + NumPy BLOB deserialization + SIMD matrix dot product cosine search + metadata filtering).
4. Implement `integrations/github_client.py`:
   - `GitHubIssueLogger` class with dual transport (MCP tools via `github-mcp-server` + REST API fallback for `s6pa1rta3n-lab/roof4u` + local queue `.github_issues_queue.json`), structured markdown issue formatting, and deduplication scanner with recurrence commenting.
5. Implement `agents/learning_agent.py`:
   - `ScrapingFailureEvent`, `LessonResolution`, `FeedforwardStrategy` schemas.
   - `LearningAgent` class integrating `LessonStore`, `LocalVectorStore`, `GitHubIssueLogger`, failure observation, dual-memory upsert, heuristic diagnosis, and `retrieve_lessons` / `get_feedforward_strategy`.
6. Update `agents/base_agent.py`, `agents/zillow_agent.py`, `agents/county_agent.py`:
   - Add failure telemetry hooks emitting `ScrapingFailureEvent` to `LearningAgent` on exceptions.
   - Query `LearningAgent.get_feedforward_strategy(domain)` before scraping to adapt selectors or delay parameters.
7. Update `main.py`:
   - Wire `LearningAgent` into the discovery and enrichment phases, reporting learning telemetry summary at the end.
8. Create comprehensive unit tests for Milestone 2 components in `tests/` (`tests/test_memory.py`, `tests/test_github_client.py`, `tests/test_learning_agent.py`) and verify all tests pass with 100% pass rate using `./venv/bin/pytest`.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Deliverables:
- Implement all required code files.
- Run tests and verify execution using `./venv/bin/pytest` and `./venv/bin/python main.py`.
- Write a 5-component handoff report to `.agents/worker_m2/handoff.md`.
- Notify parent when complete via `send_message`.
