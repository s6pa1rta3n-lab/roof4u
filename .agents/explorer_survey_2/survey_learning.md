# Roo4u Architectural Survey: R2 Learning Agent Pipeline & Memory / Failure Loop

**Author:** Explorer Agent (`explorer_survey_2`)  
**Workspace:** `/Users/solveetcoagula/Desktop/activeProjects/Roo4u`  
**Date:** 2026-09-01  
**Scope:** R2 Requirements from `ORIGINAL_REQUEST.md`, GitHub Issues #6–#10 & #14, and codebase survey.

---

## 1. Executive Summary

The objective of requirement **R2 (Learning Agent Pipeline)** is to transform Roo4u from a brittle, one-way web scraping script into a resilient, self-healing, closed-loop autonomous system.

### Current Codebase Baseline
1. **No Error Handling or Telemetry:** Current scraping prototypes (`main.py`, `agents/base_agent.py`, `agents/extractor.py`) execute synchronous operations with zero exception catching, retry mechanisms, or DOM state capture.
2. **Cloud API Hardcoding:** `agents/extractor.py` hardcodes `ChatGoogleGenerativeAI(model="gemini-3.1-pro")` requiring `GEMINI_API_KEY`, violating the offline, zero-cloud-API constraint.
3. **No Memory Layer:** There is currently no `lessons_learned.json`, no vector store, no persistent memory of scraping failures or workarounds, and no historical learning loop.
4. **GitHub Issue Logging Exists Only as Blueprint:** GitHub issue logging is documented in `README.md`, `orchestrator_prompt.md`, and repository issues (#6–#10, #14), but has zero Python implementation in the codebase.

### Target Architecture
A unified, closed-loop failure triage and memory system consisting of:
- **Observation & Failure Catching Loop:** Trapping and categorizing all runtime exceptions (DOM drift, anti-bot, schema mismatches, timeouts) with complete DOM/context telemetry.
- **GitHub Issue Auto-Logger:** Automatically logging deduplicated, structured GitHub issues via `github-mcp-server` (with direct REST API fallback).
- **Dual-Storage Memory Engine:**
  - **Structured Ground Truth:** `lessons_learned.json` for human inspection, auditability, and version control.
  - **Local Vector DB:** Lightweight, offline vector database (using local embeddings + NumPy/SQLite cosine indexing) for fast semantic retrieval.
- **Feedforward Adaptive Browsing Interface:** Browsing agents retrieve historical lessons *before* navigating target domains to proactively apply proven workarounds and prevent repeating past mistakes.

---

## 2. Scraping Observation Loop & Failure Catching

### 2.1 Codebase Assessment of Existing Agents
- **`main.py` (lines 42–60):** Simulates the pipeline using hardcoded `print()` statements and sample values (e.g. `$4.37M`, `18.0 years`). No real scraping occurs and no errors are caught or propagated.
- **`agents/base_agent.py` (lines 40–47):** `BaseAgent.get_html()` performs synchronous `self.page.goto(url, wait_until="domcontentloaded")`. It lacks `try...except`, custom timeouts, retry policies, proxy rotation, and anti-bot challenge detection.
- **`agents/extractor.py` (lines 18–44):** `LLMExtractor` invokes `ChatGoogleGenerativeAI` without catching network timeouts, JSON formatting errors, or Pydantic validation errors.

### 2.2 Taxonomy of Scraping Failures
To enable systematic diagnosis and automatic triage, all runtime failures must be categorized into standard error types:

| Category Code | Error Category | Trigger Scenario | Example in Roo4u Pipeline |
|---|---|---|---|
| `DOM_SELECTOR_DRIFT` | DOM Selector Drift | HTML element, table, or input ID changed on county/real estate portal. | SF PIM portal changing `#apn-table` or migrating to Shadow DOM. |
| `ANTI_BOT_BLOCKED` | Anti-Bot / WAF Challenge | Cloudflare Turnstile, PerimeterX, reCAPTCHA, HTTP 403 Forbidden. | Zillow or SF DBI returning anti-bot interstitial. |
| `NETWORK_TIMEOUT` | Network Timeout | Page load exceeds timeout threshold, DNS failure, HTTP 504 Gateway. | SF DBI permit lookup server lagging under high load. |
| `EXTRACTION_PARSE_ERROR` | HTML Extraction / Parse Error | Page loads but expected data fields (APN, permit date) are missing or blank. | Parcel has no permit records or unusual permit table formatting. |
| `SCHEMA_VALIDATION_ERROR` | Schema Validation Error | LLM output cannot be parsed into `PropertyExtraction` Pydantic model. | Local model returns malformed JSON or invalid data types. |
| `INFERENCE_ENDPOINT_ERROR` | Local LLM Inference Error | `localhost:8000` connection refused, out-of-memory (OOM), or timeout. | Local NVIDIA server down or VRAM exhausted. |
| `RATE_LIMIT_ERROR` | Rate Limit Encountered | HTTP 429 Too Many Requests. | Rapid requests to county assessor portal. |

### 2.3 Scraping Failure Observation Event Data Contract
When any scraper or extractor encounters an unhandled exception, it must construct a standardized `ScrapingFailureEvent` payload:

```python
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum

class FailureCategory(str, Enum):
    DOM_SELECTOR_DRIFT = "DOM_SELECTOR_DRIFT"
    ANTI_BOT_BLOCKED = "ANTI_BOT_BLOCKED"
    NETWORK_TIMEOUT = "NETWORK_TIMEOUT"
    EXTRACTION_PARSE_ERROR = "EXTRACTION_PARSE_ERROR"
    SCHEMA_VALIDATION_ERROR = "SCHEMA_VALIDATION_ERROR"
    INFERENCE_ENDPOINT_ERROR = "INFERENCE_ENDPOINT_ERROR"
    RATE_LIMIT_ERROR = "RATE_LIMIT_ERROR"
    UNKNOWN = "UNKNOWN"

class ScrapingFailureEvent(BaseModel):
    run_id: str = Field(description="Unique identifier for the current batch run")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="UTC timestamp of failure")
    domain: str = Field(description="Domain being scraped, e.g. sfplanninggis.org, zillow.com")
    source_url: str = Field(description="Exact URL where failure occurred")
    phase: str = Field(description="Pipeline phase: DISCOVERY, ASSESSOR, PERMIT, CONTACT, EXTRACTION")
    target_entity: str = Field(description="Address, APN, or identifier being processed")
    category: FailureCategory = Field(description="Classified failure category")
    exception_class: str = Field(description="Python exception class name")
    error_message: str = Field(description="Full string error message")
    stack_trace: str = Field(description="Formatted Python traceback")
    attempted_action: str = Field(description="Action description, e.g. wait_for_selector, extract_table")
    attempted_selector: Optional[str] = Field(default=None, description="CSS/XPath selector attempted")
    dom_snapshot_snippet: Optional[str] = Field(default=None, description="Truncated HTML/DOM snapshot (max 5000 chars)")
    retry_count: int = Field(default=0, description="Number of retries attempted prior to failure")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional contextual metadata")
```

---

## 3. GitHub Issue Logging Mechanism

### 3.1 Tooling & Transport Strategy
The system supports a robust dual-transport strategy:
1. **Primary Tool:** Native `github-mcp-server` MCP tools:
   - `issue_write`: Create new issues (`method="create"`) or update existing issues (`method="update"`).
   - `list_issues` / `search_issues`: Query existing repository issues for deduplication.
   - `add_issue_comment`: Add occurrence updates and notes to existing issues.
2. **Programmatic Fallback:** Direct GitHub REST API v3 via `httpx` or `requests` (using `GITHUB_TOKEN` or `GH_TOKEN` environment variable).

### 3.2 Target Repository Configuration
- **Repository Owner:** `s6pa1rta3n-lab` (configurable via `GITHUB_OWNER`)
- **Repository Name:** `roof4u` (configurable via `GITHUB_REPO`)
- **Repository URL:** `https://github.com/s6pa1rta3n-lab/roof4u`

### 3.3 Issue Naming, Labels, and Categorization Convention
- **Issue Title Convention:**  
  `[FAILURE][{CATEGORY}] {domain}: {short_summary} ({target_entity})`  
  *Example:* `[FAILURE][DOM_SELECTOR_DRIFT] sfplanninggis.org: APN table not found (2223 Pacific Ave)`
- **Labels:**  
  - `scraping-failure`
  - `automated-report`
  - `category:{category}`
  - `domain:{domain}`
  - `phase:{phase}`

### 3.4 GitHub Issue Body Template
```markdown
## 🤖 Automated Scraping Failure Report

- **Run ID:** `{run_id}`
- **Timestamp (UTC):** `{timestamp}`
- **Domain / Source:** `{domain}` (`{source_url}`)
- **Target Entity:** `{target_entity}`
- **Pipeline Phase:** `{phase}`
- **Error Category:** `{category}`

---

### ❌ Error Details
- **Exception Class:** `{exception_class}`
- **Error Message:** `{error_message}`
- **Attempted Action:** `{attempted_action}`
- **Attempted Selector:** `{attempted_selector}`
- **Retry Count:** `{retry_count}`

---

### 🔍 Stack Trace
```python
{stack_trace}
```

---

### 🌐 DOM / HTML Snapshot (Truncated)
```html
{dom_snapshot_snippet}
```

---

### 💡 Learning Agent Root Cause Diagnosis & Recommended Workaround
- **Root Cause:** {root_cause_analysis}
- **Recommended Tactic:** {recommended_workaround}
- **Code Patch Suggestion:** {code_patch_suggestion}
```

### 3.5 Deduplication and Aggregation Protocol
To prevent flooding the repository with hundreds of duplicate issues during continuous scraping batches:
1. **Search Before Create:** Before opening a new issue, query open issues matching `domain` and `category` via `list_issues(labels=["scraping-failure", f"domain:{domain}"])` or `search_issues`.
2. **Matching Criteria:** If an open issue exists with matching domain, category, and attempted selector:
   - Do NOT create a duplicate issue.
   - Call `add_issue_comment` on the existing issue with an update:  
     `"⚠️ Failure re-occurred at {timestamp} for target '{target_entity}'. Total occurrences: {count}."`
   - Increment `occurrence_count` in `lessons_learned.json`.
3. **New Failure Mode:** If no matching open issue is found, call `issue_write(method="create", ...)` and store the newly created issue number and URL.

---

## 4. Local Memory Storage Structure (`lessons_learned.json`)

### 4.1 Storage Location
- **Path:** `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/lessons_learned.json` (Root level as specified in `ORIGINAL_REQUEST.md`).
- **Backup / Secondary Mirror:** Programmatic alias support at `memory/lessons_learned.json`.

### 4.2 JSON Schema Specification
The schema is designed to be fully self-contained, typed, human-auditable, and version-controlled.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Roo4uLessonsLearned",
  "type": "object",
  "properties": {
    "schema_version": { "type": "string", "default": "1.0.0" },
    "last_updated": { "type": "string", "format": "date-time" },
    "total_lessons": { "type": "integer" },
    "lessons": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [
          "id",
          "timestamp",
          "domain",
          "phase",
          "error_category",
          "error_message",
          "root_cause_analysis",
          "recommended_workaround",
          "status"
        ],
        "properties": {
          "id": { "type": "string", "description": "Unique UUID or deterministic hash" },
          "timestamp": { "type": "string", "format": "date-time" },
          "domain": { "type": "string" },
          "source_url": { "type": "string" },
          "target_entity": { "type": "string" },
          "phase": { "type": "string", "enum": ["DISCOVERY", "ASSESSOR", "PERMIT", "CONTACT", "EXTRACTION"] },
          "error_category": { "type": "string" },
          "error_message": { "type": "string" },
          "root_cause_analysis": { "type": "string" },
          "strategy_attempted": { "type": "string" },
          "recommended_workaround": { "type": "string" },
          "code_patch_suggestion": { "type": ["string", "null"] },
          "github_issue_number": { "type": ["integer", "null"] },
          "github_issue_url": { "type": ["string", "null"] },
          "occurrence_count": { "type": "integer", "default": 1 },
          "success_count_after_workaround": { "type": "integer", "default": 0 },
          "status": { "type": "string", "enum": ["ACTIVE", "RESOLVED", "DEPRECATED"], "default": "ACTIVE" },
          "tags": { "type": "array", "items": { "type": "string" } }
        }
      }
    }
  }
}
```

### 4.3 Atomic File Persistence and Concurrency Control
To prevent file corruption during concurrent agent execution or abrupt termination:
1. **Atomic Write Pattern:** Write JSON to a temporary file in the same directory (`lessons_learned.json.tmp`) and perform an atomic rename (`os.replace`).
2. **Schema Validation on Read/Write:** Load and dump via Pydantic model (`LessonsLearnedStore`) to enforce type correctness and field integrity.

---

## 5. Local Vector DB Integration & Embedding Strategy

### 5.1 Offline & Zero-Cloud-API Constraint
`ORIGINAL_REQUEST.md` mandates 100% local, offline operation with no external cloud API keys (Google Gemini, OpenAI, etc.).

### 5.2 Local Vector Store Architecture Options

| Architecture | Description | Pros | Cons | Recommendation |
|---|---|---|---|---|
| **Option 1: NumPy + SQLite Embedded Vector Store** | In-process vector index using `numpy` (already in venv: 2.5.2) and SQLite table in `memory/vector_store.sqlite` or `leads.db`. | Zero additional heavyweight dependencies, fast startup, pure offline, lightweight cosine similarity. | Requires local embedding vector generation. | **Primary Recommended Architecture** |
| **Option 2: ChromaDB / FAISS Embedded Store** | Embedded Chroma / FAISS vector database stored in `memory/chromadb/`. | Built-in metadata filtering, collection management. | Additional C++ / binary dependencies that may conflict on Python 3.14. | Fallback / Optional Plugin |

### 5.3 Embedding Generation Strategy
1. **Local Endpoint Embeddings (`localhost:8000/v1/embeddings`):** When the local NVIDIA inference server exposes an OpenAI-compatible embedding endpoint (e.g., `nv-embed-qa-4` or `bge-large`), the Vector Store requests embeddings over local HTTP.
2. **Offline Fallback Embeddings (Zero-Dependency TF-IDF / Normalized Token Embeddings):** For deterministic offline testing or standalone execution without a GPU server running, a lightweight vectorizer generates deterministic sparse/dense embeddings so the entire retrieval pipeline functions without network or GPU dependencies.

### 5.4 Vector Database Schema & Document Format
- **Database Table (`memory/vector_store.sqlite`):**
  ```sql
  CREATE TABLE IF NOT EXISTS lesson_embeddings (
      lesson_id TEXT PRIMARY KEY,
      domain TEXT NOT NULL,
      phase TEXT NOT NULL,
      error_category TEXT NOT NULL,
      document_text TEXT NOT NULL,
      embedding_blob BLOB NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  CREATE INDEX IF NOT EXISTS idx_domain ON lesson_embeddings(domain);
  ```
- **Document Text Representation for Embedding:**
  ```python
  doc_text = (
      f"Domain: {lesson.domain} | Phase: {lesson.phase} | "
      f"Category: {lesson.error_category} | Error: {lesson.error_message} | "
      f"Root Cause: {lesson.root_cause_analysis} | Workaround: {lesson.recommended_workaround} | "
      f"Tags: {', '.join(lesson.tags)}"
  )
  ```

### 5.5 Semantic Retrieval & Prevention Loop
1. **Pre-Flight Query:** Before navigating a domain (e.g. `sfplanninggis.org`), Browsing Agent calls:
   ```python
   relevant_lessons = learning_agent.retrieve_lessons(
       domain="sfplanninggis.org",
       query="tax assessor parcel APN table lookup",
       top_k=3
   )
   ```
2. **Context Injection:** The retrieved `recommended_workaround` instructions are passed into the Browsing Agent's execution plan or local LLM prompt as negative constraints or adaptive rules:
   > *"Warning: Past failures on sfplanninggis.org indicate '#apn-table' is obsolete. Use shadow DOM selector 'pim-property-card >>> .apn-value' instead."*
3. **Feedback Update:** If the workaround succeeds, the Browsing Agent notifies the Learning Agent, which increments `success_count_after_workaround` in `lessons_learned.json`.

---

## 6. Interfaces Between Browsing Agent and Learning Agent

### 6.1 Data Flow Architecture

```
                      +-----------------------------+
                      |       Browsing Agent        |
                      +-----------------------------+
                        |                         ^
       1. Pre-Scrape    |                         |  2. Return Relevant
       Retrieve Lessons |                         |     Workarounds
                        v                         |
       +---------------------------------------------+
       |               Learning Agent                |
       +---------------------------------------------+
                        |                         ^
       3. On Scraping   |                         |  4. Yield Adaptive Retry
          Failure Event |                         |     Tactic & Action Plan
                        v                         |
       +---------------------------------------------+
       |             Self-Healing Pipeline           |
       |  - Root Cause Diagnosis (Local LLM/Rules)   |
       |  - Log/Update GitHub Issue (MCP / API)      |
       |  - Upsert lessons_learned.json (Atomic)     |
       |  - Embed & Index in Local Vector DB         |
       +---------------------------------------------+
```

### 6.2 Python Interface Signatures

```python
# agents/learning_agent.py

from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime

class Lesson(BaseModel):
    id: str
    timestamp: datetime
    domain: str
    source_url: str
    target_entity: str
    phase: str
    error_category: str
    error_message: str
    root_cause_analysis: str
    strategy_attempted: str
    recommended_workaround: str
    code_patch_suggestion: Optional[str] = None
    github_issue_number: Optional[int] = None
    github_issue_url: Optional[str] = None
    occurrence_count: int = 1
    success_count_after_workaround: int = 0
    status: str = "ACTIVE"
    tags: List[str] = []

class LessonResolution(BaseModel):
    lesson: Lesson
    github_issue_created: bool
    github_issue_number: Optional[int]
    vector_db_indexed: bool
    retry_recommended: bool
    suggested_retry_action: Optional[str]

class LearningAgent:
    def __init__(self, 
                 lessons_file: str = "lessons_learned.json", 
                 vector_db_path: str = "memory/vector_store.sqlite",
                 github_owner: str = "s6pa1rta3n-lab",
                 github_repo: str = "roof4u",
                 inference_endpoint: str = "http://localhost:8000/v1"):
        ...

    def observe_failure(self, event: ScrapingFailureEvent) -> LessonResolution:
        """
        Receives failure telemetry, diagnoses root cause, opens/updates GitHub issue,
        appends to lessons_learned.json, and indexes into Vector DB.
        """
        ...

    def observe_success(self, domain: str, target_entity: str, lesson_id: Optional[str] = None) -> None:
        """
        Records successful completion, incrementing workaround efficacy metrics.
        """
        ...

    def retrieve_lessons(self, domain: str, query: str, top_k: int = 3) -> List[Lesson]:
        """
        Performs hybrid semantic and domain-filtered vector search to retrieve past lessons.
        """
        ...

    def sync_github_issues(self) -> dict:
        """
        Synchronizes local lessons_learned.json state with open/closed GitHub issues.
        """
        ...
```

---

## 7. Implementation Breakdown & File Inventory

To implement R2 completely and cleanly without polluting `.agents/`, the following modular structure is proposed:

```
Roo4u/
├── agents/
│   ├── base_agent.py          # Updated with telemetry & observation hooks
│   ├── extractor.py           # Updated to use local model & catch validation errors
│   ├── learning_agent.py      # Core R2 Learning Agent & failure triage
│   └── browsing_agent.py      # Pure AI Browser with pre-scrape lesson retrieval
├── memory/
│   ├── __init__.py
│   ├── lesson_store.py        # Atomic read/write manager for lessons_learned.json
│   ├── vector_store.py        # Local Vector DB (NumPy + SQLite cosine similarity)
│   └── embeddings.py          # Local embedding client (endpoint + offline fallback)
├── integrations/
│   ├── __init__.py
│   └── github_client.py       # MCP & REST API GitHub issue logging & deduplication
├── lessons_learned.json       # Centralized ground truth lessons database
├── tests/
│   ├── test_learning_agent.py # Integration test for failure catching & memory updates
│   ├── test_github_logging.py # Live/real GitHub MCP issue logging test
│   └── test_vector_store.py   # Vector DB indexing and semantic retrieval tests
└── main.py                    # Connected pipeline with closed-loop failure handling
```

---

## 8. Summary of Findings & Next Steps

1. **Failure Observation Loop:** Current codebase has zero error handling. We have specified the full taxonomy and `ScrapingFailureEvent` contract.
2. **GitHub Issue Logging:** Repository is `s6pa1rta3n-lab/roof4u`. We designed a dual-transport system (MCP `github-mcp-server` + REST fallback) with strict title/body conventions and deduplication.
3. **Local Memory Storage:** `lessons_learned.json` schema and atomic storage lifecycle designed.
4. **Vector DB Integration:** Designed a zero-cloud-dependency `LocalVectorStore` leveraging local embeddings and in-process cosine similarity.
5. **Agent Interfaces:** Defined typed Pydantic models and method signatures bridging Browsing and Learning agents.
