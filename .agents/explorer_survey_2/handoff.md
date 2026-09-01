# Handoff Report: R2 Learning Agent Pipeline & Memory / Failure Loop Survey

**Author:** Explorer Agent (`explorer_survey_2`)  
**Workspace:** `/Users/solveetcoagula/Desktop/activeProjects/Roo4u`  
**Date:** 2026-09-01  
**Target Milestone:** R2 Learning Agent Pipeline, Memory & Failure Loop  
**Report Artifact:** `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_survey_2/survey_learning.md`

---

## 1. Observation

1. **User Requirements (`ORIGINAL_REQUEST.md:15-17`):**
   - *"R2. Learning Agent Pipeline: Implement the observation and memory loop. The agent must catch scraping failures, log them as GitHub issues (via MCP or API), and update a local `lessons_learned.json` and Vector DB."*
   - *"No external API keys (e.g., Google Gemini, OpenAI) are utilized anywhere in the execution path of the Browsing Agent."* (`ORIGINAL_REQUEST.md:29`).

2. **Existing GitHub Issues on Repository (`s6pa1rta3n-lab/roof4u`):**
   - Issue #6: *"Feature: The Learning Agent (Self-Healing & Optimization Loop)"*
   - Issue #7: *"Learning Loop Step 1 & 2: Observation Logging & Knowledge Base Updates - Parse Browsing Agent's daily logs, success rates, and errors ... Automatically create a new GitHub Issue documenting the specific 'lesson' or failure ... Update a centralized lessons_learned.json file ... Simultaneously update a local Vector DB. This dual-storage approach is critical for cross-validation and hallucination prevention..."*
   - Issue #14: *"Test Suite: Live GitHub MCP Integration Tests - Build integration tests for the Learning Agent's self-healing loop. The test must trigger a real web scraper failure and verify that the agent successfully uses the GitHub MCP to open a real issue on a staging repository. No simulated API responses allowed."*

3. **Current Agent Implementation State:**
   - `main.py` lines 42–60: Uses simulated print statements for county planning and permit extraction without actual Playwright or extractor execution.
   - `agents/base_agent.py` lines 40–47: `BaseAgent.get_html(url)` runs `self.page.goto(url, wait_until="domcontentloaded")` with no `try...except`, no failure capture, no retry policies, and no telemetry.
   - `agents/extractor.py` lines 19–25: Instantiates `ChatGoogleGenerativeAI(model="gemini-3.1-pro")` requiring `GEMINI_API_KEY`, lacking structured exception recovery or local model routing.
   - `requirements.txt`: Lists `playwright`, `pydantic`, `pydantic-ai`, `langchain`, `langchain-google-genai`, `google-genai`, `python-dotenv`, `pandas`, `sqlalchemy`, `requests`, `beautifulsoup4`.
   - Virtual environment inspection (`./venv/bin/pip list`): Python 3.14.7 runtime with `numpy 2.5.2`, `SQLAlchemy 2.0.52`, `pydantic 2.13.5`, `fastmcp-slim 4.0.0`, `mcp 2.1.1`, `httpx 0.28.1`, `requests 2.34.2`. No Vector DB package (Chroma/FAISS) is installed.

4. **MCP and System Tool Availability:**
   - `github-mcp-server` is active with tools `issue_write`, `list_issues`, `search_issues`, and `add_issue_comment`.
   - Local database `leads.db` exists with SQLite table `leads`.
   - Currently, no `lessons_learned.json` or vector store exists in the repository.

---

## 2. Logic Chain

1. **Absence of Self-Healing Loop:**
   - *From Observation 3:* `BaseAgent` and `LLMExtractor` have no exception interception. Any failure (e.g. timeout, selector drift, 403 bot block) terminates execution without logging or telemetry.
   - *Inference:* A centralized error observation interceptor is required to catch all scraping exceptions and translate them into standardized `ScrapingFailureEvent` payloads containing full error context (DOM snippet, stack trace, target address, phase).

2. **GitHub Issue Logging Architecture:**
   - *From Observation 2 & 4:* The project repository is `s6pa1rta3n-lab/roof4u`. `github-mcp-server` is configured and operational.
   - *Inference:* An integration module (`integrations/github_client.py`) must be built using `github-mcp-server`'s `issue_write` (with direct GitHub REST API v3 fallback via `httpx`/`requests`). It must enforce issue deduplication (querying open issues before opening new ones and appending comments if a failure reoccurs).

3. **Dual-Storage Memory Strategy:**
   - *From Observation 1, 2, & 3:* Requirements dictate both `lessons_learned.json` and a local Vector DB. `numpy` and `sqlite3` are pre-installed in the environment.
   - *Inference:*
     - `lessons_learned.json` should reside at root `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/lessons_learned.json` as the ground truth audit log with atomic write protection.
     - A local, zero-cloud-dependency Vector Store (`LocalVectorStore` in `memory/vector_store.py`) can store vectors in SQLite and perform fast cosine similarity searches using `numpy`. This guarantees 100% offline compliance without introducing fragile binary dependencies.

4. **Browsing-Learning Bidirectional Interface:**
   - *From Observation 1 & 3:* The Browsing Agent must avoid repeating known failures.
   - *Inference:* Before navigating a domain, the Browsing Agent must query the Learning Agent (`retrieve_lessons(domain, query)`) to obtain proven workarounds (e.g., fallback selectors or wait strategies). On failure, the Browsing Agent emits a `ScrapingFailureEvent`, which triggers the Learning Agent's diagnosis and memory update loop.

---

## 3. Caveats

1. **Local Model Availability:** The local inference server on `localhost:8000` is currently not running in this environment (`curl http://localhost:8000/v1/models` returned "Server not reachable"). The vector store and learning agent must support fallback offline vectorization and deterministic rule-based root-cause diagnosis when the GPU server is offline.
2. **GitHub Token for REST Fallback:** In automated headless CLI test runners where MCP is not active, a valid `GITHUB_TOKEN` environment variable is needed for direct GitHub REST API calls.
3. **No Direct Code Changes:** Per explorer identity and orchestrator constraints, this investigation did not modify any source code files outside of `.agents/explorer_survey_2/`.

---

## 4. Conclusion

The R2 Learning Agent Pipeline design is complete and documented in `survey_learning.md`. The implementation plan comprises:
1. **Data Models:** `ScrapingFailureEvent`, `Lesson`, `LessonResolution` (Pydantic).
2. **Memory Subsystem:**
   - `memory/lesson_store.py`: Atomic read/write for `lessons_learned.json`.
   - `memory/vector_store.py`: Embedded SQLite + NumPy vector database for offline semantic retrieval.
   - `memory/embeddings.py`: Local endpoint client with deterministic offline embedding fallback.
3. **GitHub Issue Logger:**
   - `integrations/github_client.py`: Dual-transport logger supporting `github-mcp-server` and GitHub REST API with deduplication.
4. **Learning Agent Orchestrator:**
   - `agents/learning_agent.py`: Bridges failure observation, issue logging, dual-memory upserts, and pre-scrape lesson retrieval.

---

## 5. Verification Method

To independently verify the findings and architectural alignment:
1. **Inspect Survey Report:**
   ```bash
   cat /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_survey_2/survey_learning.md
   ```
2. **Verify GitHub MCP Functionality:**
   - Call MCP tool `github-mcp-server` / `list_issues` on repo `s6pa1rta3n-lab/roof4u` to verify issue reading.
3. **Verify Python Environment & Dependencies:**
   ```bash
   /Users/solveetcoagula/Desktop/activeProjects/Roo4u/venv/bin/python -c "import numpy, sqlalchemy, pydantic, mcp, fastmcp; print('Core dependencies OK')"
   ```
4. **Invalidation Conditions:**
   - If requirement mandates a cloud vector database (e.g. Pinecone) instead of local offline vector store (conflicts with `ORIGINAL_REQUEST.md:29`).
   - If GitHub repository target changes from `s6pa1rta3n-lab/roof4u`.
