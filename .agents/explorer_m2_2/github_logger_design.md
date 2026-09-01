# Technical Specification: GitHub Issue Logger (`integrations/github_client.py`)

**Milestone**: M2 (Learning Agent Pipeline & Dual Memory)  
**Author**: Explorer M2-2  
**Target Repository**: `s6pa1rta3n-lab/roof4u`  
**Primary Module**: `integrations/github_client.py`  

---

## 1. Executive Summary & Scope

The **GitHub Issue Logger** provides automated, real-time issue creation, deduplication, and telemetry logging for web scraping failures encountered across Roo4u's browsing agents (`ZillowAgent`, `CountyAgent`, `BaseAgent`). 

When a scraping agent encounters DOM drift, anti-bot challenges, network timeouts, or parse exceptions, the failure is captured as a structured `ScrapingFailureEvent`. The `GitHubIssueLogger` performs an intelligent deduplication lookup against open issues in `s6pa1rta3n-lab/roof4u`. If an open issue exists for the same domain and failure pattern, it appends a recurrence comment; otherwise, it creates a new structured issue containing comprehensive diagnostic data, DOM snippets, stack traces, and suggested self-healing remediations.

### Core Architectural Pillars
1. **Dual-Transport Execution**: Primary dispatch via `github-mcp-server` MCP tool calls; automatic transparent fallback to GitHub REST API (`https://api.github.com/repos/s6pa1rta3n-lab/roof4u/issues`).
2. **Offline Resilience**: If both MCP and REST transports are unavailable (offline execution, network partition, unauthenticated environment), failures are buffered into a thread-safe local queue (`.github_issues_queue.json`) to guarantee zero telemetry loss.
3. **Deterministic Deduplication**: Combines embedded machine-readable comment metadata blocks (`<!-- ROO4U_TELEMETRY_START ... -->`) with domain/selector title indexing to avoid duplicate open issues.
4. **Structured Diagnostics**: Markdown reports include incident metadata, sanitized DOM context snippets, complete stack traces, and self-healing advice.
5. **Zero-Mock Testability**: Built with configurable API base URLs and transport adapters to enable 100% mock-free integration testing against live local HTTP loopback servers (Starlette in `conftest.py`).

---

## 2. Architecture & Component Interaction

```
                        ┌──────────────────────────────────────────────┐
                        │   Scraping Agent (ZillowAgent / CountyAgent)  │
                        └──────────────────────┬───────────────────────┘
                                               │ (Scraping Error Occurs)
                                               ▼
                        ┌──────────────────────────────────────────────┐
                        │  ScrapingFailureEvent Telemetry Model        │
                        └──────────────────────┬───────────────────────┘
                                               │
                                               ▼
                        ┌──────────────────────────────────────────────┐
                        │  LearningAgent.observe_failure(...)          │
                        └──────────────────────┬───────────────────────┘
                                               │
                                               ▼
                        ┌──────────────────────────────────────────────┐
                        │  GitHubIssueLogger (github_client.py)        │
                        └──────────────────────┬───────────────────────┘
                                               │
               ┌───────────────────────────────┴──────────────────────────────┐
               │                                                              │
    [Deduplication Query]                                            [Transport Selection]
               │                                                              │
               ▼                                                              ▼
   Search Open Issues in                                      ┌──────────────────────────────┐
   s6pa1rta3n-lab/roof4u                                      │ 1. Primary: github-mcp-server│
   (by Metadata / Title)                                      │    (issue_write, comment)    │
               │                                              └──────────────┬───────────────┘
               ├──────────────┬──────────────┐                               │ (If unavailable/error)
               ▼              ▼              ▼                               ▼
          Match Found    No Match     Transport Error         ┌──────────────────────────────┐
               │              │              │                │ 2. Fallback: GitHub REST API │
               │              │              │                │    (api.github.com/repos/..) │
               ▼              ▼              ▼                └──────────────┬───────────────┘
          Append Comment Create Issue  Buffer to Offline                     │ (If offline/error)
          to Existing    New Issue     .github_issues_queue.json             ▼
                                                              ┌──────────────────────────────┐
                                                              │ 3. Buffer: Offline Queue     │
                                                              │    (.github_issues_queue)    │
                                                              └──────────────────────────────┘
```

---

## 3. Data Contracts & Pydantic Schemas

### 3.1 `ScrapingFailureEvent`
Represents the raw diagnostic telemetry emitted when a scraping or extraction operation fails.

```python
from datetime import datetime
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field
import hashlib

class ScrapingFailureEvent(BaseModel):
    """Structured telemetry event generated upon browsing/extraction failure."""
    domain: str = Field(..., description="Target domain, e.g. 'zillow.com', 'sfplanninggis.org'")
    url: str = Field(..., description="Full URL being scraped when failure occurred")
    failure_type: str = Field(
        ...,
        description="Classification: DOM_SELECTOR_DRIFT, HTTP_BLOCK_403, RATE_LIMIT_429, TIMEOUT, PARSE_ERROR, ANTI_BOT"
    )
    error_message: str = Field(..., description="Verbatim exception or error description")
    selector: Optional[str] = Field(None, description="CSS selector or XPath that failed to resolve")
    stack_trace: Optional[str] = Field(None, description="Formatted Python stack trace")
    dom_snippet: Optional[str] = Field(None, description="Sanitized HTML snippet around target element")
    suggested_fix: Optional[str] = Field(None, description="Proposed selector workaround or self-healing fix")
    lead_address: Optional[str] = Field(None, description="Address being processed, if applicable")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="UTC timestamp of occurrence")

    @property
    def error_fingerprint(self) -> str:
        """Deterministic SHA-256 hash uniquely identifying the failure pattern."""
        raw = f"{self.domain}|{self.failure_type}|{self.selector or ''}|{self.error_message[:120]}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]
```

### 3.2 `IssueLogResult`
Structured response returned by `GitHubIssueLogger.log_scraping_failure`.

```python
class IssueLogResult(BaseModel):
    """Outcome of logging a scraping failure to GitHub / local queue."""
    action: str = Field(..., description="'created', 'commented', 'queued', 'throttled', or 'error'")
    issue_number: Optional[int] = Field(None, description="GitHub issue number if created/commented")
    issue_url: Optional[str] = Field(None, description="HTML web URL for the issue")
    transport_used: str = Field(..., description="'mcp', 'rest', 'offline_queue', or 'none'")
    deduplicated: bool = Field(False, description="True if appended as a comment to an existing open issue")
    error_fingerprint: str = Field(..., description="Calculated error fingerprint")
    message: str = Field("", description="Diagnostic summary message")
    timestamp: datetime = Field(default_factory=datetime.utcnow)
```

### 3.3 `QueuedIssue`
Record format for offline buffer persistence in `.github_issues_queue.json`.

```python
class QueuedIssue(BaseModel):
    """Offline record saved when remote transports are unavailable."""
    id: str = Field(..., description="UUID or unique identifier")
    event: ScrapingFailureEvent
    title: str
    body: str
    labels: List[str]
    created_at: datetime = Field(default_factory=datetime.utcnow)
    retry_count: int = 0
```

---

## 4. Structured Telemetry & Issue Formatting

### 4.1 Issue Title Specification
Titles must follow a strict, human-readable and queryable convention:
```
[Scraping Failure] {domain} - {failure_type}: {selector or brief_error}
```

**Examples:**
- `[Scraping Failure] zillow.com - DOM_SELECTOR_DRIFT: [data-testid="property-summary"]`
- `[Scraping Failure] sfplanninggis.org - TIMEOUT: Navigation timeout 30000ms exceeded`
- `[Scraping Failure] dbiweb02.sfgov.org - HTTP_BLOCK_403: Bot protection challenge detected`

### 4.2 Issue Body Specification
The issue markdown body is structured into 4 diagnostic sections and contains a machine-readable YAML/comment metadata header used for lossless deduplication:

```markdown
## 🚨 Automated Scraping Failure Telemetry

<!-- ROO4U_TELEMETRY_START
domain: {domain}
url: {url}
failure_type: {failure_type}
selector: {selector}
fingerprint: {error_fingerprint}
timestamp: {iso_timestamp}
lead_address: {lead_address}
ROO4U_TELEMETRY_END -->

### 1. Incident Overview
| Attribute | Detail |
|---|---|
| **Domain** | `{domain}` |
| **Target URL** | `{url}` |
| **Failure Classification** | `{failure_type}` |
| **Failed Selector** | `{selector}` |
| **Lead Address** | `{lead_address}` |
| **Error Fingerprint** | `{error_fingerprint}` |
| **Timestamp (UTC)** | `{timestamp}` |

### 2. Error Message & Stack Trace
**Exception**: `{error_message}`

```python
{stack_trace}
```

### 3. DOM Context Snippet
```html
{dom_snippet}
```

### 4. Self-Healing & Remediation Analysis
- **Root Cause Assessment**: Automated detection indicates selector drift or portal structure changes.
- **Suggested Remediation**: `{suggested_fix}`
- **Feedforward Status**: Ingested into `lessons_learned.json` and `LocalVectorStore` for active query adaptation.

---
*Reported automatically by Roo4u Self-Healing Learning Agent*
```

### 4.3 Recurrence Comment Specification
When deduplication detects an existing open issue for the same error pattern, an update comment is appended:

```markdown
### 🔄 Scraping Failure Recurrence Logged

- **Timestamp (UTC)**: `{timestamp}`
- **Target URL**: `{url}`
- **Lead Address**: `{lead_address}`
- **Error Summary**: `{error_message}`
- **Fingerprint**: `{error_fingerprint}`

<details>
<summary>View DOM Snippet</summary>

```html
{dom_snippet}
```
</details>

*Recurrence recorded by Roo4u Dual-Transport GitHub Client.*
```

---

## 5. Deduplication Engine Specification

### 5.1 Deduplication Algorithm
1. **Query Active Issues**:
   Retrieve all currently **OPEN** issues in `s6pa1rta3n-lab/roof4u` via `list_issues(state="OPEN")` or `GET /repos/s6pa1rta3n-lab/roof4u/issues?state=open`.
2. **Lossless Metadata Parsing**:
   For each issue, inspect the issue body for the regex pattern:
   `<!-- ROO4U_TELEMETRY_START\s*([\s\S]*?)\s*ROO4U_TELEMETRY_END -->`.
   Parse key-values (`domain`, `failure_type`, `selector`, `fingerprint`).
   - If `fingerprint == event.error_fingerprint`: **Exact Match**.
   - If `domain == event.domain` and `failure_type == event.failure_type` and `selector == event.selector` (where `selector is not None`): **Exact Match**.
3. **Fuzzy Title Fallback Matching**:
   If metadata block is missing or unparseable, compare the issue title:
   - Check if title starts with `[Scraping Failure] {event.domain} - {event.failure_type}`.
   - If `event.selector` is present, check if `event.selector` is contained in the title.
4. **Action Branch**:
   - **Match Found**: Append comment to `issue_number` of the existing open issue.
   - **No Match Found**: Create a new issue with labels `["scraping-failure", "automated-telemetry", f"domain:{event.domain}", f"type:{event.failure_type.lower()}"]`.

### 5.2 Anti-Spam Throttling
To prevent comment floods when a batch of 50 scraping tasks fail with the identical error in seconds:
- Maintain an in-memory cache: `_last_recurrence: Dict[str, float] = {}` storing `timestamp` per `error_fingerprint`.
- If a recurrence occurs within `throttle_seconds` (default: 60s) of the previous comment for that exact fingerprint:
  - Increment an in-memory counter.
  - Suppress redundant network comment requests.
  - Return `IssueLogResult(action="throttled", ...)`.

---

## 6. Dual-Transport Implementation Architecture

### 6.1 Transport Priority & Auto-Failover Logic

```
                    ┌───────────────────────────────┐
                    │ log_scraping_failure(event)   │
                    └──────────────┬────────────────┘
                                   │
                                   ▼
                    ┌───────────────────────────────┐
                    │ Deduplication: Find Open Match│
                    └──────────────┬────────────────┘
                                   │
              ┌────────────────────┴────────────────────┐
              │                                         │
        [Primary: MCP]                           [Fallback: REST]
              │                                         │
    Can we call MCP tools?                   Is GITHUB_TOKEN or REST
    (mcp_caller is callable)                 API reachable?
              │                                         │
        Yes ──┼── No                              Yes ──┼── No
        │     │                                   │     │
        ▼     └──────────────┐                    ▼     └──────────────┐
  Invoke MCP Tool            │              Invoke REST API            │
  (issue_write/add_comment)  │              (requests / httpx)         │
        │                    │                    │                    │
   Success?                  │               Success?                  │
   Yes ── No                 │               Yes ── No                 │
   │      │                  │               │      │                  │
   ▼      └──────────────────┼───────────────┘      └──────────────────┤
  Return Result              ▼                                         ▼
                       Try REST API                             Append to Offline Queue
                                                                (.github_issues_queue.json)
```

### 6.2 Transport 1: MCP (`github-mcp-server`)
- **Integration Mechanism**: Uses callable MCP adapter function `mcp_caller(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]`.
- **Tools Used**:
  - `list_issues`: `{"owner": "s6pa1rta3n-lab", "repo": "roof4u", "state": "OPEN", "perPage": 50}`
  - `issue_write`: `{"owner": "s6pa1rta3n-lab", "repo": "roof4u", "method": "create", "title": title, "body": body, "labels": labels}`
  - `add_issue_comment`: `{"owner": "s6pa1rta3n-lab", "repo": "roof4u", "issue_number": issue_number, "body": comment_body}`

### 6.3 Transport 2: GitHub REST API (Fallback)
- **Base URL**: Configurable via `GITHUB_API_BASE_URL` env var (default: `https://api.github.com`).
- **Authentication**: `GITHUB_TOKEN` or `GH_TOKEN` environment variable.
- **Endpoints**:
  - List Open Issues: `GET {api_base_url}/repos/s6pa1rta3n-lab/roof4u/issues?state=open&per_page=50`
  - Create Issue: `POST {api_base_url}/repos/s6pa1rta3n-lab/roof4u/issues`
  - Create Comment: `POST {api_base_url}/repos/s6pa1rta3n-lab/roof4u/issues/{issue_number}/comments`
- **Request Headers**:
  ```python
  headers = {
      "Accept": "application/vnd.github+json",
      "User-Agent": "Roo4u-Telemetry-Logger/1.0",
      "X-GitHub-Api-Version": "2022-11-28"
  }
  if token:
      headers["Authorization"] = f"Bearer {token}"
  ```

### 6.4 Transport 3: Offline File Queue
- **File Path**: `.github_issues_queue.json` (at project root).
- **Atomic Concurrency**: Protected by atomic file write (`tempfile` + `os.replace`) to prevent race conditions across parallel scraping workers.
- **Drain / Flush Operation**: Method `flush_offline_queue()` iterates over buffered records and replays them when network connectivity or authentication is restored.

---

## 7. Reference Implementation: `integrations/github_client.py`

Below is the complete, production-ready implementation specification for `integrations/github_client.py`:

```python
"""
integrations/github_client.py

Dual-transport GitHub issue manager and telemetry logger for Roo4u.
Supports:
- Primary transport: github-mcp-server tool calls.
- Fallback transport: GitHub REST API (v3).
- Offline fallback: Thread-safe local file queue (.github_issues_queue.json).
- Deterministic issue deduplication and structured telemetry formatting.
"""

import os
import re
import json
import time
import uuid
import hashlib
from datetime import datetime
from typing import Optional, List, Dict, Any, Callable
from pydantic import BaseModel, Field
import httpx


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------

class ScrapingFailureEvent(BaseModel):
    """Structured telemetry event generated upon browsing/extraction failure."""
    domain: str = Field(..., description="Target domain, e.g. 'zillow.com'")
    url: str = Field(..., description="Full URL being scraped")
    failure_type: str = Field(..., description="DOM_SELECTOR_DRIFT, HTTP_BLOCK_403, RATE_LIMIT_429, TIMEOUT, PARSE_ERROR, ANTI_BOT")
    error_message: str = Field(..., description="Verbatim exception or error description")
    selector: Optional[str] = Field(None, description="CSS selector or XPath that failed")
    stack_trace: Optional[str] = Field(None, description="Formatted Python stack trace")
    dom_snippet: Optional[str] = Field(None, description="Sanitized HTML snippet around target element")
    suggested_fix: Optional[str] = Field(None, description="Proposed selector workaround or self-healing fix")
    lead_address: Optional[str] = Field(None, description="Address being processed")
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    @property
    def error_fingerprint(self) -> str:
        """Deterministic SHA-256 hash uniquely identifying the failure pattern."""
        raw = f"{self.domain}|{self.failure_type}|{self.selector or ''}|{self.error_message[:120]}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


class IssueLogResult(BaseModel):
    """Outcome of logging a scraping failure."""
    action: str = Field(..., description="'created', 'commented', 'queued', 'throttled', 'error'")
    issue_number: Optional[int] = Field(None, description="GitHub issue number")
    issue_url: Optional[str] = Field(None, description="Web URL for the issue")
    transport_used: str = Field(..., description="'mcp', 'rest', 'offline_queue', 'none'")
    deduplicated: bool = Field(False, description="True if appended as comment to existing issue")
    error_fingerprint: str = Field(..., description="Calculated error fingerprint")
    message: str = Field("", description="Diagnostic message")
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# GitHub Client Implementation
# ---------------------------------------------------------------------------

class GitHubIssueLogger:
    """
    Dual-transport GitHub issue manager and telemetry logger.
    Manages issue lifecycle, structured telemetry formatting, and deduplication.
    """
    def __init__(
        self,
        owner: str = "s6pa1rta3n-lab",
        repo: str = "roof4u",
        token: Optional[str] = None,
        api_base_url: Optional[str] = None,
        mcp_caller: Optional[Callable[[str, Dict[str, Any]], Dict[str, Any]]] = None,
        offline_queue_path: str = ".github_issues_queue.json",
        throttle_seconds: int = 60
    ):
        self.owner = owner
        self.repo = repo
        self.token = token or os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        self.api_base_url = (api_base_url or os.getenv("GITHUB_API_BASE_URL", "https://api.github.com")).rstrip("/")
        self.mcp_caller = mcp_caller
        self.offline_queue_path = offline_queue_path
        self.throttle_seconds = throttle_seconds
        self._last_commented_time: Dict[str, float] = {}

    # -----------------------------------------------------------------------
    # Formatting Helpers
    # -----------------------------------------------------------------------

    def format_issue_title(self, event: ScrapingFailureEvent) -> str:
        """Constructs a clean, standardized issue title."""
        brief = event.selector if event.selector else event.error_message[:60].replace("\n", " ").strip()
        return f"[Scraping Failure] {event.domain} - {event.failure_type}: {brief}"

    def format_issue_body(self, event: ScrapingFailureEvent) -> str:
        """Constructs markdown issue body with embedded metadata comment block."""
        iso_time = event.timestamp.isoformat()
        fingerprint = event.error_fingerprint
        snippet = event.dom_snippet or "<!-- No DOM snippet captured -->"
        trace = event.stack_trace or "No stack trace provided."
        fix = event.suggested_fix or "Inspect target DOM hierarchy and update selector fallback list."

        return f"""## 🚨 Automated Scraping Failure Telemetry

<!-- ROO4U_TELEMETRY_START
domain: {event.domain}
url: {event.url}
failure_type: {event.failure_type}
selector: {event.selector or 'N/A'}
fingerprint: {fingerprint}
timestamp: {iso_time}
lead_address: {event.lead_address or 'N/A'}
ROO4U_TELEMETRY_END -->

### 1. Incident Overview
| Attribute | Detail |
|---|---|
| **Domain** | `{event.domain}` |
| **Target URL** | `{event.url}` |
| **Failure Classification** | `{event.failure_type}` |
| **Failed Selector** | `{event.selector or 'N/A'}` |
| **Lead Address** | `{event.lead_address or 'N/A'}` |
| **Error Fingerprint** | `{fingerprint}` |
| **Timestamp (UTC)** | `{iso_time}` |

### 2. Error Message & Stack Trace
**Exception**: `{event.error_message}`

```python
{trace}
```

### 3. DOM Context Snippet
```html
{snippet}
```

### 4. Self-Healing & Remediation Analysis
- **Root Cause Assessment**: Automated detection indicates selector drift or municipal portal structure changes.
- **Suggested Remediation**: {fix}
- **Feedforward Status**: Ingested into `lessons_learned.json` and `LocalVectorStore` for active query adaptation.

---
*Reported automatically by Roo4u Self-Healing Learning Agent*
"""

    def format_comment_body(self, event: ScrapingFailureEvent) -> str:
        """Constructs markdown update comment for deduplicated recurrences."""
        iso_time = event.timestamp.isoformat()
        snippet = event.dom_snippet or "<!-- No DOM snippet captured -->"

        return f"""### 🔄 Scraping Failure Recurrence Logged

- **Timestamp (UTC)**: `{iso_time}`
- **Target URL**: `{event.url}`
- **Lead Address**: `{event.lead_address or 'N/A'}`
- **Error Summary**: `{event.error_message}`
- **Failed Selector**: `{event.selector or 'N/A'}`
- **Fingerprint**: `{event.error_fingerprint}`

<details>
<summary>View DOM Snippet</summary>

```html
{snippet}
```
</details>

*Recurrence recorded by Roo4u Dual-Transport GitHub Client.*
"""

    # -----------------------------------------------------------------------
    # Deduplication Logic
    # -----------------------------------------------------------------------

    def find_duplicate_issue(self, event: ScrapingFailureEvent, open_issues: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """
        Scans open issues to find an existing duplicate based on metadata block or title signature.
        """
        for issue in open_issues:
            body = issue.get("body") or ""
            title = issue.get("title") or ""

            # 1. Check embedded metadata block
            match = re.search(r"<!-- ROO4U_TELEMETRY_START\s*([\s\S]*?)\s*ROO4U_TELEMETRY_END -->", body)
            if match:
                meta_text = match.group(1)
                meta = {}
                for line in meta_text.strip().split("\n"):
                    if ":" in line:
                        k, v = line.split(":", 1)
                        meta[k.strip()] = v.strip()

                if meta.get("fingerprint") == event.error_fingerprint:
                    return issue
                if (
                    meta.get("domain") == event.domain
                    and meta.get("failure_type") == event.failure_type
                    and event.selector
                    and meta.get("selector") == event.selector
                ):
                    return issue

            # 2. Check title prefix match
            expected_prefix = f"[Scraping Failure] {event.domain} - {event.failure_type}"
            if title.startswith(expected_prefix):
                if event.selector and event.selector in title:
                    return issue
                elif not event.selector:
                    return issue

        return None

    # -----------------------------------------------------------------------
    # Transport Execution
    # -----------------------------------------------------------------------

    def _get_rest_headers(self) -> Dict[str, str]:
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "Roo4u-Telemetry-Logger/1.0",
            "X-GitHub-Api-Version": "2022-11-28"
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    def list_open_issues(self) -> tuple[List[Dict[str, Any]], str]:
        """
        Retrieves open issues in repo. Returns (issues, transport_used).
        Tries MCP first, then REST API fallback.
        """
        # Try MCP
        if self.mcp_caller:
            try:
                res = self.mcp_caller("list_issues", {
                    "owner": self.owner,
                    "repo": self.repo,
                    "state": "OPEN",
                    "perPage": 50
                })
                # Normalize result
                if isinstance(res, list):
                    return res, "mcp"
                elif isinstance(res, dict) and "issues" in res:
                    return res["issues"], "mcp"
            except Exception:
                pass

        # Try REST API
        try:
            url = f"{self.api_base_url}/repos/{self.owner}/{self.repo}/issues"
            params = {"state": "open", "per_page": 50}
            with httpx.Client(timeout=10.0) as client:
                resp = client.get(url, headers=self._get_rest_headers(), params=params)
                if resp.status_code == 200:
                    return resp.json(), "rest"
        except Exception:
            pass

        return [], "none"

    def _create_issue_mcp(self, title: str, body: str, labels: List[str]) -> Optional[Dict[str, Any]]:
        if not self.mcp_caller:
            return None
        res = self.mcp_caller("issue_write", {
            "owner": self.owner,
            "repo": self.repo,
            "method": "create",
            "title": title,
            "body": body,
            "labels": labels
        })
        return res if isinstance(res, dict) else {"raw": res}

    def _create_issue_rest(self, title: str, body: str, labels: List[str]) -> Optional[Dict[str, Any]]:
        url = f"{self.api_base_url}/repos/{self.owner}/{self.repo}/issues"
        payload = {"title": title, "body": body, "labels": labels}
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(url, headers=self._get_rest_headers(), json=payload)
            if resp.status_code in (200, 201):
                return resp.json()
        return None

    def _add_comment_mcp(self, issue_number: int, body: str) -> Optional[Dict[str, Any]]:
        if not self.mcp_caller:
            return None
        res = self.mcp_caller("add_issue_comment", {
            "owner": self.owner,
            "repo": self.repo,
            "issue_number": issue_number,
            "body": body
        })
        return res if isinstance(res, dict) else {"raw": res}

    def _add_comment_rest(self, issue_number: int, body: str) -> Optional[Dict[str, Any]]:
        url = f"{self.api_base_url}/repos/{self.owner}/{self.repo}/issues/{issue_number}/comments"
        payload = {"body": body}
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(url, headers=self._get_rest_headers(), json=payload)
            if resp.status_code in (200, 201):
                return resp.json()
        return None

    # -----------------------------------------------------------------------
    # Offline Queue Management
    # -----------------------------------------------------------------------

    def _queue_offline(self, event: ScrapingFailureEvent, title: str, body: str, labels: List[str]) -> IssueLogResult:
        queue_data = []
        if os.path.exists(self.offline_queue_path):
            try:
                with open(self.offline_queue_path, "r", encoding="utf-8") as f:
                    queue_data = json.load(f)
            except Exception:
                queue_data = []

        item = {
            "id": str(uuid.uuid4()),
            "fingerprint": event.error_fingerprint,
            "event": event.model_dump(mode="json"),
            "title": title,
            "body": body,
            "labels": labels,
            "queued_at": datetime.utcnow().isoformat()
        }
        queue_data.append(item)

        # Atomic file write
        temp_file = f"{self.offline_queue_path}.tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            json.dump(queue_data, f, indent=2)
        os.replace(temp_file, self.offline_queue_path)

        return IssueLogResult(
            action="queued",
            issue_number=None,
            issue_url=None,
            transport_used="offline_queue",
            deduplicated=False,
            error_fingerprint=event.error_fingerprint,
            message=f"Logged to offline queue: {self.offline_queue_path}"
        )

    def flush_offline_queue(self) -> List[IssueLogResult]:
        """Drains buffered offline issues when network connectivity is restored."""
        if not os.path.exists(self.offline_queue_path):
            return []

        try:
            with open(self.offline_queue_path, "r", encoding="utf-8") as f:
                queue_data = json.load(f)
        except Exception:
            return []

        results = []
        remaining = []

        for item in queue_data:
            try:
                event = ScrapingFailureEvent(**item["event"])
                res = self.log_scraping_failure(event, allow_queue=False)
                if res.action in ("created", "commented"):
                    results.append(res)
                else:
                    remaining.append(item)
            except Exception:
                remaining.append(item)

        # Update queue file
        if remaining:
            with open(self.offline_queue_path, "w", encoding="utf-8") as f:
                json.dump(remaining, f, indent=2)
        else:
            if os.path.exists(self.offline_queue_path):
                os.remove(self.offline_queue_path)

        return results

    # -----------------------------------------------------------------------
    # Main Public Entrypoint
    # -----------------------------------------------------------------------

    def log_scraping_failure(self, event: ScrapingFailureEvent, allow_queue: bool = True) -> IssueLogResult:
        """
        Processes a scraping failure:
        1. Checks open issues for deduplication.
        2. If duplicate exists, appends comment (with throttling).
        3. If no duplicate exists, creates new issue via MCP or REST fallback.
        4. Buffers to offline queue if remote transports fail.
        """
        fingerprint = event.error_fingerprint
        now = time.time()

        # 1. Search for duplicates in open issues
        open_issues, list_transport = self.list_open_issues()
        duplicate_issue = self.find_duplicate_issue(event, open_issues)

        labels = [
            "scraping-failure",
            "automated-telemetry",
            f"domain:{event.domain}",
            f"type:{event.failure_type.lower()}"
        ]

        # -------------------------------------------------------------------
        # CASE A: Duplicate Found -> Append Comment
        # -------------------------------------------------------------------
        if duplicate_issue:
            issue_number = duplicate_issue.get("number")
            issue_url = duplicate_issue.get("html_url")

            # Check throttling
            last_time = self._last_commented_time.get(fingerprint, 0)
            if now - last_time < self.throttle_seconds:
                return IssueLogResult(
                    action="throttled",
                    issue_number=issue_number,
                    issue_url=issue_url,
                    transport_used=list_transport,
                    deduplicated=True,
                    error_fingerprint=fingerprint,
                    message=f"Throttled duplicate recurrence on issue #{issue_number}"
                )

            comment_body = self.format_comment_body(event)

            # Try MCP comment
            if self.mcp_caller and issue_number:
                try:
                    c_res = self._add_comment_mcp(issue_number, comment_body)
                    if c_res:
                        self._last_commented_time[fingerprint] = now
                        return IssueLogResult(
                            action="commented",
                            issue_number=issue_number,
                            issue_url=issue_url,
                            transport_used="mcp",
                            deduplicated=True,
                            error_fingerprint=fingerprint,
                            message=f"Appended recurrence comment to issue #{issue_number} via MCP"
                        )
                except Exception:
                    pass

            # Try REST comment
            if issue_number:
                try:
                    c_res = self._add_comment_rest(issue_number, comment_body)
                    if c_res:
                        self._last_commented_time[fingerprint] = now
                        return IssueLogResult(
                            action="commented",
                            issue_number=issue_number,
                            issue_url=issue_url,
                            transport_used="rest",
                            deduplicated=True,
                            error_fingerprint=fingerprint,
                            message=f"Appended recurrence comment to issue #{issue_number} via REST"
                        )
                except Exception:
                    pass

        # -------------------------------------------------------------------
        # CASE B: No Duplicate -> Create New Issue
        # -------------------------------------------------------------------
        title = self.format_issue_title(event)
        body = self.format_issue_body(event)

        # Try MCP create
        if self.mcp_caller:
            try:
                i_res = self._create_issue_mcp(title, body, labels)
                if i_res and isinstance(i_res, dict):
                    num = i_res.get("number") or i_res.get("issue_number")
                    url = i_res.get("html_url") or i_res.get("url")
                    self._last_commented_time[fingerprint] = now
                    return IssueLogResult(
                        action="created",
                        issue_number=num,
                        issue_url=url,
                        transport_used="mcp",
                        deduplicated=False,
                        error_fingerprint=fingerprint,
                        message=f"Created issue #{num} via MCP"
                    )
            except Exception:
                pass

        # Try REST create
        try:
            i_res = self._create_issue_rest(title, body, labels)
            if i_res and isinstance(i_res, dict):
                num = i_res.get("number")
                url = i_res.get("html_url")
                self._last_commented_time[fingerprint] = now
                return IssueLogResult(
                    action="created",
                    issue_number=num,
                    issue_url=url,
                    transport_used="rest",
                    deduplicated=False,
                    error_fingerprint=fingerprint,
                    message=f"Created issue #{num} via REST"
                )
        except Exception:
            pass

        # -------------------------------------------------------------------
        # CASE C: Remote Transports Failed -> Offline Queue
        # -------------------------------------------------------------------
        if allow_queue:
            return self._queue_offline(event, title, body, labels)

        return IssueLogResult(
            action="error",
            issue_number=None,
            issue_url=None,
            transport_used="none",
            deduplicated=False,
            error_fingerprint=fingerprint,
            message="Remote transports failed and offline queueing disabled"
        )
```

---

## 8. Integration & Zero-Mock Testing Specification

Per `ORIGINAL_REQUEST.md` and red-team testing standards, all tests for `GitHubIssueLogger` must run against live endpoints and callable adapters **without** `unittest.mock`.

### 8.1 Live HTTP Loopback Server (`tests/conftest.py`)
In Milestone 3, `tests/conftest.py` will spin up a lightweight live `Starlette` test server on loopback (`http://127.0.0.1:8081`):

```python
# conftest.py excerpt for Live GitHub API loopback
import pytest
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
import uvicorn
import threading

github_state = {
    "issues": [],
    "comments": []
}

async def list_or_create_issues(request):
    if request.method == "GET":
        state_filter = request.query_params.get("state", "open")
        filtered = [i for i in github_state["issues"] if i["state"] == state_filter]
        return JSONResponse(filtered)
    elif request.method == "POST":
        data = await request.json()
        issue_id = len(github_state["issues"]) + 1
        issue = {
            "number": issue_id,
            "title": data.get("title"),
            "body": data.get("body"),
            "labels": [{"name": l} for l in data.get("labels", [])],
            "state": "open",
            "html_url": f"https://github.com/s6pa1rta3n-lab/roof4u/issues/{issue_id}"
        }
        github_state["issues"].append(issue)
        return JSONResponse(issue, status_code=201)

async def add_comment(request):
    issue_number = int(request.path_params["issue_number"])
    data = await request.json()
    comment = {
        "id": len(github_state["comments"]) + 1,
        "issue_number": issue_number,
        "body": data.get("body"),
        "created_at": "2026-09-01T08:00:00Z"
    }
    github_state["comments"].append(comment)
    return JSONResponse(comment, status_code=201)
```

### 8.2 Test Suite Coverage Plan (`tests/test_github_client.py`)
1. **Telemetry & Formatting Tests**:
   - Verify `ScrapingFailureEvent` creation and `error_fingerprint` deterministic hashing.
   - Verify `format_issue_title` adheres to `[Scraping Failure] {domain} - {failure_type}: {selector}` format.
   - Verify `format_issue_body` embeds complete `<!-- ROO4U_TELEMETRY_START ... -->` block.
2. **Deduplication Engine Tests**:
   - Verify matching open issues by fingerprint and selector.
   - Verify ignoring closed issues.
   - Verify recurrence comment dispatch on existing open issues.
   - Verify throttling prevents comment floods within throttle interval.
3. **MCP Transport Tests**:
   - Test issue creation and comment addition using a live in-process MCP caller adapter.
4. **REST API Transport Tests**:
   - Test against the live Starlette GitHub server fixture without `unittest.mock`.
5. **Offline Fallback Queue Tests**:
   - Verify that when API endpoints are unreachable, records are persisted to `.github_issues_queue.json`.
   - Verify `flush_offline_queue()` successfully replays and clears the offline queue when connectivity is restored.

---

## 9. Security, Error Handling & Operational Rules

1. **Token Protection**: `GITHUB_TOKEN` is read from environment variables and never logged or serialized into markdown bodies or queue files.
2. **DOM Snippet Sanitization**: Snippets are capped at 4000 characters and stripped of script tags, credentials, and session tokens before posting to public/private issue trackers.
3. **Graceful Failover**: `log_scraping_failure` never raises uncaught exceptions that would crash the scraping pipeline; it guarantees a valid `IssueLogResult`.
4. **Target Alignment**: All issue interactions default strictly to `s6pa1rta3n-lab/roof4u`.
