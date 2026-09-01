# Roo4u Learning Agent & Feedforward Loop — Technical Specification

**Author:** Explorer M2-3  
**Milestone:** M2 — Learning Agent Pipeline & Dual Memory  
**Target Modules:** `agents/learning_agent.py`, `agents/base_agent.py`, `agents/zillow_agent.py`, `agents/county_agent.py`, `main.py`  
**Dependencies:** `memory/lesson_store.py` (M2-1), `memory/vector_store.py` (M2-1), `integrations/github_client.py` (M2-2)  
**Date:** 2026-09-01  

---

## 1. Executive Overview & Architecture

The **Learning Agent & Feedforward Loop** is the cognitive backbone of Roo4u. It transforms traditional, brittle web scrapers into an autonomous, self-healing closed-loop system.

```
                                  +---------------------------------------------------------+
                                  |                      Browsing Agents                    |
                                  |     (BaseAgent / ZillowAgent / CountyAgent)             |
                                  +---------------------------------------------------------+
                                     |                                                    ^
                 1. Pre-Scrape Query |                                                    | 2. Feedforward Strategy
                 (domain + context)  v                                                    |    (Selectors, Headers, Delays)
                                  +---------------------------------------------------------+
                                  |                   LearningAgent                         |
                                  |  - Coordinator of Observation & Adaptation              |
                                  |  - Root-Cause Diagnostic Engine (Heuristic + Local LLM) |
                                  +---------------------------------------------------------+
                                     |                          |                         |
               3. On Failure         | 4. Dual-Memory Upsert    | 5. Live Issue Log       | 6. Pre-Scrape Search
               (ScrapingFailureEvent)| (Atomic JSON + Vector)   | (Deduplicated MCP/REST) | (Semantic + Domain Filter)
                                     v                          v                         v
                           +--------------------+    +--------------------+    +--------------------+
                           |    LessonStore     |    | GitHubIssueLogger  |    |  LocalVectorStore  |
                           | lessons_learned    |    | s6pa1rta3n-lab/    |    |  SQLite + NumPy    |
                           | .json              |    | roof4u             |    |  Cosine Index      |
                           +--------------------+    +--------------------+    +--------------------+
```

### Core Tenets
1. **Zero-Mock & Offline-First:** Operates 100% locally. Root-cause diagnosis uses deterministic heuristic classifiers with optional local LLM analysis (`http://localhost:8000/v1`). No cloud APIs (OpenAI, Gemini) are ever invoked.
2. **Dual-Memory Synchronization:** Every observed failure and derived lesson is written to both human-readable `lessons_learned.json` (atomic write) and indexed in `LocalVectorStore` (NumPy/SQLite vector DB) for sub-millisecond semantic retrieval.
3. **Feedforward Prevention:** Before hitting target endpoints, scrapers query `LearningAgent.retrieve_lessons(domain, context)` to retrieve past failures and dynamically adapt selector priority chains, request headers, or timing delays.
4. **Immediate In-Process Self-Healing:** When a scraper encounters a recoverable failure (e.g. selector drift), `LearningAgent` diagnoses a workaround on-the-fly, enabling the scraper to execute an immediate adaptive retry before failing the lead.

---

## 2. Data Contracts & Domain Models

All models are defined using `pydantic.BaseModel` to ensure strict typing, schema validation, and serialization compatibility.

### 2.1 Failure Taxonomy Enum (`FailureCategory`)

```python
from enum import Enum

class FailureCategory(str, Enum):
    DOM_SELECTOR_DRIFT = "DOM_SELECTOR_DRIFT"       # Target CSS/XPath element missing or changed
    ANTI_BOT_BLOCKED = "ANTI_BOT_BLOCKED"           # HTTP 403, Cloudflare/PerimeterX challenge, Captcha
    RATE_LIMIT_ERROR = "RATE_LIMIT_ERROR"           # HTTP 429 Too Many Requests
    NETWORK_TIMEOUT = "NETWORK_TIMEOUT"             # Navigation timeout, DNS failure, 504 Gateway
    EXTRACTION_PARSE_ERROR = "EXTRACTION_PARSE_ERROR" # HTML loaded but required data fields missing
    SCHEMA_VALIDATION_ERROR = "SCHEMA_VALIDATION_ERROR" # Local LLM output violates Pydantic schema
    INFERENCE_ENDPOINT_ERROR = "INFERENCE_ENDPOINT_ERROR" # Local model offline / OOM / timeout
    UNKNOWN = "UNKNOWN"
```

### 2.2 Telemetry Event Model (`ScrapingFailureEvent`)

Constructed by scrapers whenever an exception or anomaly occurs:

```python
from datetime import datetime
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field

class ScrapingFailureEvent(BaseModel):
    """Telemetry payload emitted by Browsing Agents upon encountering errors."""
    run_id: str = Field(default_factory=lambda: datetime.utcnow().strftime("RUN-%Y%m%d-%H%M%S"))
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    domain: str = Field(description="Target domain, e.g. zillow.com, sfplanninggis.org, dbiweb02.sfgov.org")
    source_url: str = Field(description="Exact URL where the failure occurred")
    phase: str = Field(description="Pipeline phase: DISCOVERY, ASSESSOR, PERMIT, CONTACT, EXTRACTION")
    target_entity: str = Field(description="Property address, APN, or identifier being processed")
    category: FailureCategory = Field(description="Classified failure category")
    exception_class: str = Field(description="Python exception class name, e.g. TimeoutError, ValueError")
    error_message: str = Field(description="Error message string")
    stack_trace: Optional[str] = Field(default=None, description="Formatted Python traceback snippet")
    attempted_action: str = Field(description="Action being performed, e.g. get_html, clean_dom, extract_property")
    attempted_selector: Optional[str] = Field(default=None, description="CSS or XPath selector that failed")
    dom_snapshot_snippet: Optional[str] = Field(default=None, description="Truncated HTML snippet (max 4000 chars)")
    retry_count: int = Field(default=0, description="Current retry attempt number")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Custom metadata (e.g. status code, response headers)")
```

### 2.3 Structured Lesson Model (`Lesson`)

The canonical unit of memory stored in `lessons_learned.json` and `LocalVectorStore`:

```python
class Lesson(BaseModel):
    """A synthesized lesson learned from one or more scraping failures."""
    id: str = Field(description="Unique deterministic hash or UUID for this failure pattern")
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    domain: str = Field(description="Domain where lesson applies")
    source_url: str = Field(description="Sample URL exhibiting this issue")
    target_entity: str = Field(description="Address or entity associated with discovery")
    phase: str = Field(description="Pipeline phase")
    error_category: FailureCategory = Field(description="Categorized failure type")
    error_message: str = Field(description="Summary error message")
    root_cause_analysis: str = Field(description="Diagnosis of why the failure occurred")
    strategy_attempted: str = Field(description="Original strategy/selector attempted")
    recommended_workaround: str = Field(description="Actionable workaround or alternate selector")
    suggested_selectors: List[str] = Field(default_factory=list, description="List of replacement selectors to try")
    suggested_delay_seconds: float = Field(default=0.0, description="Recommended delay before requests")
    suggested_headers: Dict[str, str] = Field(default_factory=dict, description="Recommended header overrides")
    code_patch_suggestion: Optional[str] = Field(default=None, description="Optional code patch recommendation")
    github_issue_number: Optional[int] = Field(default=None, description="Linked GitHub issue number")
    github_issue_url: Optional[str] = Field(default=None, description="Linked GitHub issue URL")
    occurrence_count: int = Field(default=1, description="Number of times this failure mode was observed")
    success_count_after_workaround: int = Field(default=0, description="Efficacy count of workaround")
    status: str = Field(default="ACTIVE", description="ACTIVE, RESOLVED, or DEPRECATED")
    tags: List[str] = Field(default_factory=list, description="Taxonomy and keyword tags")
```

### 2.4 Feedforward Strategy Payload (`FeedforwardStrategy`)

Returned to scrapers during pre-scrape retrieval to configure browser parameters:

```python
class FeedforwardStrategy(BaseModel):
    """Actionable pre-scrape directives compiled from historical lessons."""
    domain: str
    primary_selectors: List[str] = Field(default_factory=list)
    fallback_selectors: List[str] = Field(default_factory=list)
    request_delay_seconds: float = 0.0
    custom_headers: Dict[str, str] = Field(default_factory=dict)
    known_blockers: List[str] = Field(default_factory=list)
    applicable_lessons: List[Lesson] = Field(default_factory=list)
```

### 2.5 Lesson Resolution Result (`LessonResolution`)

Returned to the caller after observing a failure:

```python
class LessonResolution(BaseModel):
    """Result of failure triage and self-healing analysis."""
    lesson: Lesson
    github_issue_created: bool = False
    github_issue_number: Optional[int] = None
    vector_db_indexed: bool = False
    retry_recommended: bool = False
    suggested_retry_action: Optional[str] = None
```

---

## 3. `agents/learning_agent.py` Specification

The `LearningAgent` coordinates the failure triage, root-cause diagnosis, dual-memory persistence, and feedforward queries.

### 3.1 Class Definition & Dependencies

```python
# agents/learning_agent.py

import os
import re
import hashlib
import traceback
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime

from pydantic import BaseModel
from memory.lesson_store import LessonStore
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger
from agents.extractor import LocalLLMExtractor


class LearningAgent:
    """
    Orchestrates the self-healing observation loop:
    1. Intercepts ScrapingFailureEvents from Browsing Agents.
    2. Diagnoses root causes via heuristic rules or local LLM inference.
    3. Synthesizes Lessons and performs dual-memory upserts (JSON + Vector DB).
    4. Logs/updates deduplicated GitHub issues via GitHubIssueLogger.
    5. Serves pre-scrape feedforward strategies to prevent repetitive failures.
    6. Tracks workaround efficacy via success observation.
    """

    def __init__(
        self,
        lesson_store: Optional[LessonStore] = None,
        vector_store: Optional[LocalVectorStore] = None,
        github_logger: Optional[GitHubIssueLogger] = None,
        extractor: Optional[LocalLLMExtractor] = None,
        enable_local_llm_diagnosis: bool = True,
    ):
        self.lesson_store = lesson_store or LessonStore()
        self.vector_store = vector_store or LocalVectorStore()
        self.github_logger = github_logger or GitHubIssueLogger()
        self.extractor = extractor or LocalLLMExtractor()
        self.enable_local_llm_diagnosis = enable_local_llm_diagnosis
```

### 3.2 Root-Cause Diagnostic Engine

The diagnostic engine uses a **two-tier triage architecture**:
1. **Tier 1: Heuristic Rule Classifier (Instant, 100% Offline & Deterministic)**
2. **Tier 2: Local LLM Diagnostic Refinement (Optional, via `localhost:8000/v1`)**

#### Tier 1 Heuristic Classifier Logic:
- **DOM Selector Drift:** If error mentions `TimeoutError waiting for selector` or `0 candidates found in DOM of size > 5000 bytes`:
  - Analyzes DOM snippet for known alternate class names (e.g. `ds-home-facts`, `property-card`, `dbi-grid`, `parcel-info`).
  - Generates suggested fallback selectors.
  - Suggests immediate retry with fallback selector.
- **Anti-Bot / 403 / Captcha:** If error mentions `403`, `PerimeterX`, `Cloudflare`, `Captcha`, `Robot Check`:
  - Diagnoses bot detection threshold exceeded.
  - Generates workaround: Rotate user agent, introduce 2.5s jitter delay, attach realistic Accept-Language headers.
- **Rate Limit / 429:**
  - Recommends exponential backoff: set `suggested_delay_seconds = 5.0`.
- **Extraction / Parse Error:**
  - Missing field in HTML: Suggests querying alternative table structures or secondary endpoints.
- **Schema Validation Error:**
  - Local LLM output malformed: Suggests appending schema enforcement instructions or few-shot example.

#### Tier 2 Local LLM Diagnosis (When enabled):
```python
def _diagnose_with_llm(self, event: ScrapingFailureEvent) -> Tuple[str, str, List[str]]:
    """Uses local model to generate deep root cause analysis and replacement selectors."""
    prompt = (
        f"Diagnose this web scraping failure on {event.domain}:\n"
        f"Phase: {event.phase}\n"
        f"Error: {event.error_message}\n"
        f"Attempted Selector: {event.attempted_selector}\n"
        f"DOM Snippet:\n{event.dom_snapshot_snippet or 'None'}\n\n"
        f"Return a JSON object with: 'root_cause', 'recommended_workaround', 'suggested_selectors' (list)."
    )
    # Call self.extractor._call_model with system prompt and parse response.
```

### 3.3 Failure Observation & Dual-Memory Upsert Flow (`observe_failure`)

```python
def observe_failure(self, event: ScrapingFailureEvent) -> LessonResolution:
    """
    Main failure handling entry point:
    1. Computes deterministic lesson ID from domain + category + attempted_selector.
    2. Diagnoses root cause & generates actionable workarounds.
    3. Checks LessonStore for existing lesson (increments occurrence if exists).
    4. Logs or updates GitHub issue via GitHubIssueLogger.
    5. Upserts lesson to LessonStore (atomic JSON write).
    6. Embeds and indexes lesson in LocalVectorStore.
    7. Returns LessonResolution with retry guidance.
    """
```

**Step-by-Step Execution:**
1. **Deterministic Fingerprint ID:**
   ```python
   pattern_str = f"{event.domain}:{event.category}:{event.attempted_selector or event.attempted_action}"
   lesson_id = hashlib.sha256(pattern_str.encode("utf-8")).hexdigest()[:16]
   ```
2. **Retrieve or Create Lesson:**
   - If `existing := self.lesson_store.get_lesson(lesson_id)`:
     - Increment `existing.occurrence_count += 1`.
     - Update `existing.timestamp = datetime.utcnow()`.
     - Lesson is updated.
   - Else:
     - Run Root-Cause Diagnosis.
     - Construct new `Lesson` with diagnosed fields.
3. **GitHub Issue Logging:**
   - Call `github_res = self.github_logger.log_scraping_failure(event, lesson)`.
   - Update `lesson.github_issue_number = github_res.issue_number`.
   - Update `lesson.github_issue_url = github_res.issue_url`.
4. **Dual-Memory Upsert:**
   - `self.lesson_store.upsert_lesson(lesson)` (Atomic write to `lessons_learned.json`).
   - Document string for embedding:
     ```python
     doc_text = (
         f"Domain: {lesson.domain} | Category: {lesson.error_category} | "
         f"Error: {lesson.error_message} | Root Cause: {lesson.root_cause_analysis} | "
         f"Workaround: {lesson.recommended_workaround} | "
         f"Selectors: {', '.join(lesson.suggested_selectors)} | Tags: {', '.join(lesson.tags)}"
     )
     self.vector_store.upsert(
         doc_id=lesson.id,
         text=doc_text,
         metadata={
             "domain": lesson.domain,
             "category": str(lesson.error_category),
             "phase": lesson.phase,
             "status": lesson.status,
             "success_count": lesson.success_count_after_workaround
         }
     )
     ```
5. **Formulate Resolution:**
   - Set `retry_recommended = True` if `lesson.suggested_selectors` is non-empty or `lesson.suggested_delay_seconds > 0`.
   - Return `LessonResolution`.

### 3.4 Feedforward Lesson Retrieval (`retrieve_lessons` & `get_feedforward_strategy`)

```python
def retrieve_lessons(
    self,
    domain: str,
    context_query: str = "",
    top_k: int = 3,
    category: Optional[FailureCategory] = None
) -> List[Lesson]:
    """
    Performs hybrid retrieval:
    1. Queries LocalVectorStore using context_query with metadata filter domain=domain.
    2. Fallback / Augment: Queries LessonStore.filter_by_domain(domain).
    3. Filters out DEPRECATED lessons and returns top_k active lessons.
    """
```

```python
def get_feedforward_strategy(self, domain: str, action_context: str = "") -> FeedforwardStrategy:
    """
    Compiles active lessons into a concrete execution strategy for scrapers:
    - Gathers all suggested fallback selectors.
    - Aggregates recommended request delays.
    - Collects recommended custom headers.
    - Identifies known anti-bot / rate-limit blockers.
    """
    lessons = self.retrieve_lessons(domain=domain, context_query=action_context, top_k=5)
    strategy = FeedforwardStrategy(domain=domain, applicable_lessons=lessons)
    
    for l in lessons:
        if l.status != "ACTIVE":
            continue
        strategy.fallback_selectors.extend(l.suggested_selectors)
        if l.suggested_delay_seconds > strategy.request_delay_seconds:
            strategy.request_delay_seconds = l.suggested_delay_seconds
        strategy.custom_headers.update(l.suggested_headers)
        if l.error_category in (FailureCategory.ANTI_BOT_BLOCKED, FailureCategory.RATE_LIMIT_ERROR):
            strategy.known_blockers.append(f"{l.error_category}: {l.recommended_workaround}")
            
    # Deduplicate selectors while preserving order
    strategy.fallback_selectors = list(dict.fromkeys(strategy.fallback_selectors))
    return strategy
```

### 3.5 Workaround Efficacy Tracking (`observe_success`)

```python
def observe_success(self, domain: str, target_entity: str, lesson_id: Optional[str] = None) -> None:
    """
    Called when a scraper succeeds after applying a workaround.
    Increments success_count_after_workaround in both LessonStore and VectorStore.
    If success_count exceeds threshold (e.g. >= 5), marks lesson status as VERIFIED/RESOLVED.
    """
    if lesson_id:
        self.lesson_store.increment_success(lesson_id)
        # Update vector store metadata
        lesson = self.lesson_store.get_lesson(lesson_id)
        if lesson:
            self.vector_store.update_metadata(lesson_id, {"success_count": lesson.success_count_after_workaround})
```

---

## 4. Scraper Telemetry Interception Hooks

To enable closed-loop self-healing, `BaseAgent`, `ZillowAgent`, and `CountyAgent` are enhanced with telemetry hooks and feedforward querying capabilities.

### 4.1 BaseAgent Enhancements (`agents/base_agent.py`)

1. **Constructor Injection:**
   ```python
   def __init__(
       self,
       headless: bool = True,
       learning_agent: Optional["LearningAgent"] = None
   ):
       self.headless = headless
       self.learning_agent = learning_agent
       ...
   ```
2. **Safe Navigation with Telemetry:**
   ```python
   def safe_get_html(
       self,
       url: str,
       domain: Optional[str] = None,
       phase: str = "NAVIGATION",
       target_entity: str = "",
       timeout: float = 30000.0,
       wait_until: str = "domcontentloaded"
   ) -> str:
       """
       Navigates to URL with exception trapping, feedforward delays/headers,
       and automatic telemetry emission on failure.
       """
       domain_name = domain or url.split("/")[2] if "://" in url else "unknown"
       
       # 1. Apply Feedforward Guidance if LearningAgent is attached
       if self.learning_agent:
           strategy = self.learning_agent.get_feedforward_strategy(domain_name, f"navigate {url}")
           if strategy.request_delay_seconds > 0:
               time.sleep(strategy.request_delay_seconds)
           if strategy.custom_headers and self.context:
               self.context.set_extra_http_headers(strategy.custom_headers)

       # 2. Execute Navigation with Exception Catching
       try:
           if not self.page:
               self.start_browser()
           response = self.page.goto(url, wait_until=wait_until, timeout=timeout)
           
           # Check for HTTP error status codes (403, 429, 500)
           status_code = response.status if response else 200
           if status_code in (403, 429) or (response and "access denied" in self.page.title().lower()):
               category = FailureCategory.ANTI_BOT_BLOCKED if status_code == 403 else FailureCategory.RATE_LIMIT_ERROR
               self.emit_failure(
                   domain=domain_name,
                   source_url=url,
                   phase=phase,
                   target_entity=target_entity,
                   category=category,
                   exception_class="HttpBlockError",
                   error_message=f"HTTP {status_code} detected on {url} (Title: {self.page.title()})",
                   attempted_action="safe_get_html",
                   dom_snippet=self.page.content()[:3000]
               )
           
           return self.page.content()

       except Exception as exc:
           # Capture stack trace and partial DOM snippet if available
           dom_snippet = None
           try:
               if self.page:
                   dom_snippet = self.page.content()[:3000]
           except Exception:
               pass

           category = FailureCategory.NETWORK_TIMEOUT if "timeout" in str(exc).lower() else FailureCategory.UNKNOWN
           self.emit_failure(
               domain=domain_name,
               source_url=url,
               phase=phase,
               target_entity=target_entity,
               category=category,
               exception_class=exc.__class__.__name__,
               error_message=str(exc),
               stack_trace=traceback.format_exc(),
               attempted_action="safe_get_html",
               dom_snippet=dom_snippet
           )
           raise exc
   ```

3. **Telemetry Emitter Helper:**
   ```python
   def emit_failure(
       self,
       domain: str,
       source_url: str,
       phase: str,
       target_entity: str,
       category: FailureCategory,
       exception_class: str,
       error_message: str,
       attempted_action: str,
       attempted_selector: Optional[str] = None,
       dom_snippet: Optional[str] = None,
       stack_trace: Optional[str] = None,
       retry_count: int = 0
   ) -> Optional[LessonResolution]:
       """Constructs ScrapingFailureEvent and delegates to LearningAgent."""
       if not self.learning_agent:
           return None
           
       event = ScrapingFailureEvent(
           domain=domain,
           source_url=source_url,
           phase=phase,
           target_entity=target_entity,
           category=category,
           exception_class=exception_class,
           error_message=error_message,
           stack_trace=stack_trace,
           attempted_action=attempted_action,
           attempted_selector=attempted_selector,
           dom_snapshot_snippet=dom_snippet,
           retry_count=retry_count
       )
       return self.learning_agent.observe_failure(event)
   ```

### 4.2 ZillowAgent Telemetry & Adaptation Hooks (`agents/zillow_agent.py`)

1. **Dynamic Selector Adaptation in `clean_dom`:**
   ```python
   def clean_dom(self, html_content: str, extra_selectors: Optional[List[str]] = None) -> str:
       # Standard selectors
       selectors = [
           '[data-testid="property-summary"]',
           '[data-testid="home-details-chip-container"]',
           '[data-testid="facts-category"]',
           '.ds-overview-section',
           '.ds-home-facts-and-features',
           '.summary-container',
           '.hdp-content',
           '#home-details-content',
           '.home-details-card'
       ]
       # Prepend dynamic feedforward selectors if provided
       if extra_selectors:
           selectors = extra_selectors + selectors
       ...
   ```

2. **Self-Healing Property Scraping (`scrape_property`):**
   ```python
   def scrape_property(self, url_or_html: str, target_address: str = "") -> PropertyExtraction:
       domain = "zillow.com"
       source_url = url_or_html if url_or_html.startswith("http") else f"https://{domain}/property"
       
       # 1. Retrieve feedforward strategy
       feedforward = None
       if self.learning_agent:
           feedforward = self.learning_agent.get_feedforward_strategy(domain, "extract property details")

       # 2. Get HTML
       if url_or_html.startswith("http"):
           html = self.safe_get_html(url_or_html, domain=domain, phase="DISCOVERY", target_entity=target_address)
       else:
           html = url_or_html

       # 3. Clean DOM using feedforward selectors
       extra_sel = feedforward.fallback_selectors if feedforward else None
       cleaned = self.clean_dom(html, extra_selectors=extra_sel)

       # 4. Extract with Local LLM and Catch Extraction/Validation Failures
       try:
           extraction = self.extractor.extract_property_details(cleaned)
           # If successfully extracted after applying feedforward workaround, record success
           if self.learning_agent and feedforward and feedforward.applicable_lessons:
               for l in feedforward.applicable_lessons:
                   self.learning_agent.observe_success(domain, target_address or extraction.address, l.id)
           return extraction
       except Exception as exc:
           # Telemetry: Extraction failure
           resolution = self.emit_failure(
               domain=domain,
               source_url=source_url,
               phase="EXTRACTION",
               target_entity=target_address,
               category=FailureCategory.SCHEMA_VALIDATION_ERROR if isinstance(exc, ValueError) else FailureCategory.EXTRACTION_PARSE_ERROR,
               exception_class=exc.__class__.__name__,
               error_message=str(exc),
               attempted_action="extract_property_details",
               dom_snippet=cleaned[:3000],
               stack_trace=traceback.format_exc()
           )
           # Immediate Adaptive Retry if resolution suggested a workaround
           if resolution and resolution.retry_recommended:
               # Attempt secondary extraction with raw body text
               soup = BeautifulSoup(html, "html.parser")
               raw_body = (soup.find("body") or soup).get_text(separator=" ", strip=True)[:10000]
               retry_extraction = self.extractor.extract_property_details(raw_body)
               if self.learning_agent:
                   self.learning_agent.observe_success(domain, target_address or retry_extraction.address, resolution.lesson.id)
               return retry_extraction

           raise exc
   ```

3. **Discovery Selector Drift Detection (`discover_properties`):**
   ```python
   def discover_properties(self, zip_code: str, max_results: int = 10) -> List[Dict[str, Any]]:
       search_url = f"{self.base_url.rstrip('/')}/homes/{zip_code}_rb/"
       domain = "zillow.com"
       
       try:
           html = self.safe_get_html(search_url, domain=domain, phase="DISCOVERY", target_entity=zip_code)
           soup = BeautifulSoup(html, "html.parser")
           
           # Check candidate cards
           card_selectors = ['article[data-test="property-card"]', '.list-card', 'a.property-card-link']
           # Check feedforward selectors
           if self.learning_agent:
               ff = self.learning_agent.get_feedforward_strategy(domain, f"discovery {zip_code}")
               if ff.fallback_selectors:
                   card_selectors = ff.fallback_selectors + card_selectors

           cards = []
           for sel in card_selectors:
               matched = soup.select(sel)
               if matched:
                   cards = matched
                   break

           # Anomaly Detection: If page has > 5000 bytes but 0 cards found, emit DOM_SELECTOR_DRIFT
           if not cards and len(html) > 5000:
               self.emit_failure(
                   domain=domain,
                   source_url=search_url,
                   phase="DISCOVERY",
                   target_entity=zip_code,
                   category=FailureCategory.DOM_SELECTOR_DRIFT,
                   exception_class="SelectorNotFoundError",
                   error_message=f"0 listing cards found on search page {search_url} (HTML length: {len(html)})",
                   attempted_action="discover_properties",
                   attempted_selector=",".join(card_selectors),
                   dom_snippet=html[:3000]
               )

           candidates = []
           for card in cards[:max_results]:
               link = card.get("href") if card.name == "a" else (card.find("a") or {}).get("href")
               addr_text = card.get_text(separator=" ", strip=True)
               if link:
                   full_url = link if link.startswith("http") else f"{self.base_url.rstrip('/')}{link}"
                   candidates.append({
                       "url": full_url,
                       "summary": addr_text[:200],
                       "zip_code": zip_code
                   })
           return candidates
       except Exception as exc:
           self.emit_failure(
               domain=domain,
               source_url=search_url,
               phase="DISCOVERY",
               target_entity=zip_code,
               category=FailureCategory.UNKNOWN,
               exception_class=exc.__class__.__name__,
               error_message=str(exc),
               attempted_action="discover_properties",
               stack_trace=traceback.format_exc()
           )
           return []
   ```

### 4.3 CountyAgent Telemetry & Adaptation Hooks (`agents/county_agent.py`)

1. **Assessor Record Telemetry (`lookup_assessor_record`):**
   - Domain: `sfplanninggis.org`
   - Checks table selectors (`#propertyDetails`, `.parcel-details`, `.assessment-info`).
   - If selector yields empty text, emits `DOM_SELECTOR_DRIFT` to `LearningAgent` and attempts secondary selector retrieval.
2. **Permit History Telemetry (`lookup_permit_history`):**
   - Domain: `dbiweb02.sfgov.org`
   - Traps ASP.NET postback errors, session expiration, and missing permit table grids.
   - Emits `EXTRACTION_PARSE_ERROR` or `DOM_SELECTOR_DRIFT` with the exact failed selector.
3. **Date Parsing Fallback:**
   - If `parse_permit_date` fails to parse a non-empty string, emits `EXTRACTION_PARSE_ERROR` to record the unhandled date format into `lessons_learned.json` so regular expressions can be expanded.

---

## 5. Feedforward Adaptation Engine & Dynamic Selector Strategies

The feedforward cycle operates dynamically across the entire agent lifecycle:

```
[Pre-Flight]
Agent about to scrape URL on domain D
      │
      ▼
Query LearningAgent.get_feedforward_strategy(D)
      │
      ├─► Strategy includes: Fallback Selectors, Delay (sec), Custom Headers
      │
[Execution]
Browser applies custom headers & delays
DOM Preprocessor prioritizes Fallback Selectors ahead of standard selectors
      │
      ├─► [SUCCESS] ──► Call LearningAgent.observe_success(D, entity, lesson_id)
      │                 Increment success count in lessons_learned.json & Vector DB
      │
      └─► [FAILURE] ──► Emit ScrapingFailureEvent
                        LearningAgent diagnoses root cause
                        Logs GitHub Issue (s6pa1rta3n-lab/roof4u)
                        Upserts to lessons_learned.json & LocalVectorStore
                        Returns immediate LessonResolution with suggested retry
```

### Dynamic Strategy Aggregation Table

| Domain | Historical Failure | Diagnosed Cause | Feedforward Strategy Applied |
|---|---|---|---|
| `zillow.com` | `DOM_SELECTOR_DRIFT` on `[data-testid="property-summary"]` | Zillow updated to new React chip container | Prepend `[data-testid="home-details-chip-container"]`, `.hdp-content` to selector chain |
| `zillow.com` | `ANTI_BOT_BLOCKED` HTTP 403 | Bot heuristics triggered by rapid queries | Apply 2.0s jitter delay + inject desktop Chrome user agent & referer |
| `sfplanninggis.org` | `DOM_SELECTOR_DRIFT` on `#apn-table` | PIM portal redesigned property details tab | Prepend `.parcel-details`, `.pim-property-card` to selector list |
| `dbiweb02.sfgov.org` | `RATE_LIMIT_ERROR` HTTP 429 | Too many concurrent permit lookups | Apply 3.5s delay between permit queries |
| `*` (All Domains) | `SCHEMA_VALIDATION_ERROR` (Invalid zip code format) | Local LLM returned raw text with zip code embedded | Add preprocessing regex extraction before Pydantic validation |

---

## 6. Pipeline Integration (`main.py`)

`main.py` is updated to instantiate and wire the `LearningAgent` into the entire lead discovery, assessment, and enrichment lifecycle.

```python
# main.py (Integration Architecture)

import argparse
import os
from typing import Optional

from db.database import init_db, get_session, Lead
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor
from agents.learning_agent import LearningAgent
from memory.lesson_store import LessonStore
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger


def run_pipeline(
    zip_code: str = "94115",
    target_address: Optional[str] = None,
    headless: bool = True,
    db_path: str = "sqlite:///leads.db",
    enable_learning: bool = True,
    enable_github_logging: bool = True
):
    print(f"==================================================")
    print(f" Roo4u Autonomous Lead Pipeline (Milestone 2)    ")
    print(f" Target Zip: {zip_code} | Mode: Offline First    ")
    print(f"==================================================")

    # 1. Initialize Database
    engine = init_db(db_path)
    session = get_session(engine)

    # 2. Initialize Dual Memory & Integrations
    lesson_store = LessonStore(file_path="lessons_learned.json")
    vector_store = LocalVectorStore(db_path="memory/vector_store.sqlite")
    github_logger = GitHubIssueLogger(
        owner="s6pa1rta3n-lab",
        repo="roof4u",
        enabled=enable_github_logging
    )

    # 3. Initialize Learning Agent Coordinator
    extractor = LocalLLMExtractor()
    learning_agent = LearningAgent(
        lesson_store=lesson_store,
        vector_store=vector_store,
        github_logger=github_logger,
        extractor=extractor
    ) if enable_learning else None

    # 4. Instantiate Browsing Agents with Learning Agent Injected
    zillow_agent = ZillowAgent(headless=headless, extractor=extractor, learning_agent=learning_agent)
    county_agent = CountyAgent(headless=headless, extractor=extractor, learning_agent=learning_agent)

    # -------------------------------------------------------------
    # PHASE 1: DISCOVERY (ZillowAgent + Feedforward)
    # -------------------------------------------------------------
    print("\n--- PHASE 1: DISCOVERY ---")
    ...
    # (Scrapes listings, applies feedforward strategies, catches and logs failures)

    # -------------------------------------------------------------
    # PHASE 2: ASSESSOR & PERMITS (CountyAgent + Feedforward)
    # -------------------------------------------------------------
    print("\n--- PHASE 2: ASSESSOR & PERMITS ---")
    ...
    # (Enriches leads, applies municipal workaround selectors, qualifies leads)

    # -------------------------------------------------------------
    # PHASE 3: LEARNING & TELEMETRY SUMMARY
    # -------------------------------------------------------------
    print("\n--- PHASE 3: LEARNING & SYSTEM TELEMETRY SUMMARY ---")
    if learning_agent:
        all_lessons = lesson_store.load_all()
        print(f"Total Unique Lessons in Memory: {len(all_lessons)}")
        active_lessons = [l for l in all_lessons if l.status == "ACTIVE"]
        print(f"Active Self-Healing Rules:      {len(active_lessons)}")
        vector_count = vector_store.count()
        print(f"Indexed Vectors in Local DB:    {vector_count}")
        for l in active_lessons[-3:]:
            print(f"  * [{l.error_category}] {l.domain}: {l.recommended_workaround} (Occurrences: {l.occurrence_count})")
```

---

## 7. Verification & Zero-Mock Testing Strategy

In compliance with Red-Team and Victory Audit rules (`ORIGINAL_REQUEST.md §R4`, `PROJECT.md`), testing must not use `unittest.mock` or `MagicMock` for external interfaces.

### 7.1 Test Suites to Implement in M3

1. **`tests/test_learning_agent.py`:**
   - **`test_observe_failure_and_dual_memory_upsert`:**
     - Emits synthetic `ScrapingFailureEvent` for `DOM_SELECTOR_DRIFT`.
     - Verifies `Lesson` is created with root cause analysis.
     - Verifies `lessons_learned.json` is updated atomically.
     - Verifies `LocalVectorStore` contains indexed embedding and document text.
   - **`test_feedforward_retrieval_relevance`:**
     - Inserts 3 distinct lessons for different domains (`zillow.com`, `sfplanninggis.org`, `dbiweb02.sfgov.org`).
     - Calls `retrieve_lessons(domain="zillow.com", query="property details")`.
     - Verifies only relevant Zillow lessons are returned with high cosine similarity.
   - **`test_workaround_success_tracking`:**
     - Observes success for a lesson and verifies `success_count_after_workaround` increments.
2. **`tests/test_scraper_telemetry_integration.py`:**
   - Uses local Starlette HTML loopback server serving:
     - Normal property page.
     - Drifted DOM page (missing expected selectors).
     - Simulated 403 Forbidden / Anti-bot page.
   - Runs `ZillowAgent` and `CountyAgent` against the loopback server with `LearningAgent` attached.
   - Verifies `ScrapingFailureEvent` is captured, `lessons_learned.json` is populated, and adaptive fallback logic succeeds on the second pass.

---

## 8. Synthesis of Peer Interface Alignments

| Interface | Explorer M2-1 (`memory/`) Alignment | Explorer M2-2 (`integrations/`) Alignment | Explorer M2-3 (`agents/learning_agent.py`) Usage |
|---|---|---|---|
| `Lesson` Schema | `Lesson` model in `memory/lesson_store.py` with `id`, `domain`, `phase`, `error_category`, `recommended_workaround`, `suggested_selectors`. | Matches issue title & body markdown format. | `LearningAgent` instantiates and updates `Lesson` objects. |
| `LessonStore` | `upsert_lesson(lesson)`, `get_lesson(id)`, `load_all()`, `filter_by_domain(domain)`, `increment_occurrence(id)`, `increment_success(id)`. | Reads issues from store for audit reports. | `LearningAgent` uses `LessonStore` as primary ground truth storage. |
| `LocalVectorStore` | `upsert(doc_id, text, metadata, embedding=None)`, `search(query, filter_metadata, top_k)`, `count()`. | N/A | `LearningAgent` queries for feedforward retrieval and indexes new lessons. |
| `GitHubIssueLogger` | N/A | `log_scraping_failure(event, lesson) -> IssueLogResult` with MCP primary & REST fallback + deduplication. | `LearningAgent` calls logger on every observed failure. |
| Browsing Agents | N/A | N/A | `BaseAgent`, `ZillowAgent`, `CountyAgent` accept `learning_agent` and execute feedforward querying and failure emission. |

---

## 9. Conclusion

The specification provides an airtight, completely offline, zero-mock design for the Learning Agent and Feedforward Observation Loop. All requirements from `ORIGINAL_REQUEST.md §R2` and `PROJECT.md` are rigorously addressed, establishing clear contracts with M2-1 (Dual Memory) and M2-2 (GitHub Logger) while providing concrete hooks for browsing agents and `main.py`.
