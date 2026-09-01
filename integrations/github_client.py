"""
integrations/github_client.py

Dual-transport GitHub issue manager and telemetry logger for Roo4u.
Supports:
- Primary transport: github-mcp-server tool calls (issue_write, list_issues, add_issue_comment).
- Fallback transport: GitHub REST API (v3).
- Offline fallback: Thread-safe local file queue (.github_issues_queue.json).
- Deterministic issue deduplication, anti-spam comment throttling, and structured telemetry formatting.
"""

import os
import re
import json
import time
import uuid
import hashlib
import logging
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any, Callable, Union, Tuple
from pydantic import BaseModel, Field, model_validator
import httpx

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------

class ScrapingFailureEvent(BaseModel):
    """Structured telemetry event generated upon browsing/extraction failure."""
    domain: str = Field(..., description="Target domain, e.g. 'zillow.com'")
    url: str = Field(default="", description="Full URL being scraped")
    source_url: Optional[str] = Field(default=None, description="Alias for url")
    failure_type: str = Field(
        default="UNKNOWN",
        description="DOM_SELECTOR_DRIFT, ANTI_BOT_BLOCKED, RATE_LIMIT_ERROR, NETWORK_TIMEOUT, EXTRACTION_PARSE_ERROR, SCHEMA_VALIDATION_ERROR"
    )
    category: Optional[Any] = Field(default=None, description="Alias for failure_type")
    error_message: str = Field(default="", description="Verbatim exception or error description")
    selector: Optional[str] = Field(default=None, description="CSS selector or XPath that failed")
    attempted_selector: Optional[str] = Field(default=None, description="Alias for selector")
    stack_trace: Optional[str] = Field(default=None, description="Formatted Python stack trace")
    dom_snippet: Optional[str] = Field(default=None, description="Sanitized HTML snippet around target element")
    dom_snapshot_snippet: Optional[str] = Field(default=None, description="Alias for dom_snippet")
    suggested_fix: Optional[str] = Field(default=None, description="Proposed selector workaround or self-healing fix")
    lead_address: Optional[str] = Field(default=None, description="Address being processed")
    target_entity: Optional[str] = Field(default=None, description="Alias for lead_address")
    phase: Optional[str] = Field(default=None, description="Pipeline phase")
    attempted_action: Optional[str] = Field(default=None, description="Action attempted")
    exception_class: Optional[str] = Field(default=None, description="Exception class name")
    retry_count: int = Field(default=0, description="Retry attempt count")
    metadata: Dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @model_validator(mode="before")
    @classmethod
    def sync_event_aliases(cls, values: Any) -> Any:
        if isinstance(values, dict):
            # Sync url and source_url
            if not values.get("url") and values.get("source_url"):
                values["url"] = values["source_url"]
            elif values.get("url") and not values.get("source_url"):
                values["source_url"] = values["url"]

            # Sync selector and attempted_selector
            if not values.get("selector") and values.get("attempted_selector"):
                values["selector"] = values["attempted_selector"]
            elif values.get("selector") and not values.get("attempted_selector"):
                values["attempted_selector"] = values["selector"]

            # Sync dom_snippet and dom_snapshot_snippet
            if not values.get("dom_snippet") and values.get("dom_snapshot_snippet"):
                values["dom_snippet"] = values["dom_snapshot_snippet"]
            elif values.get("dom_snippet") and not values.get("dom_snapshot_snippet"):
                values["dom_snapshot_snippet"] = values["dom_snippet"]

            # Sync lead_address and target_entity
            if not values.get("lead_address") and values.get("target_entity"):
                values["lead_address"] = values["target_entity"]
            elif values.get("lead_address") and not values.get("target_entity"):
                values["target_entity"] = values["lead_address"]

            # Sync failure_type and category
            if not values.get("failure_type") or values.get("failure_type") == "UNKNOWN":
                if values.get("category"):
                    values["failure_type"] = str(getattr(values["category"], "value", values["category"]))
            if not values.get("category") and values.get("failure_type"):
                values["category"] = values["failure_type"]

        return values

    @property
    def error_fingerprint(self) -> str:
        """Deterministic SHA-256 hash uniquely identifying the failure pattern."""
        raw = f"{self.domain}|{self.failure_type}|{self.selector or ''}|{self.error_message[:120]}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


class IssueLogResult(BaseModel):
    """Outcome of logging a scraping failure to GitHub or the local offline queue."""
    action: str = Field(..., description="'created', 'commented', 'queued', 'throttled', or 'error'")
    issue_number: Optional[int] = Field(default=None, description="GitHub issue number if created/commented")
    issue_url: Optional[str] = Field(default=None, description="HTML web URL for the issue")
    transport_used: str = Field(..., description="'mcp', 'rest', 'offline_queue', or 'none'")
    deduplicated: bool = Field(default=False, description="True if appended as a comment to an existing open issue")
    error_fingerprint: str = Field(..., description="Calculated error fingerprint")
    message: str = Field(default="", description="Diagnostic summary message")
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ---------------------------------------------------------------------------
# GitHub Client Implementation
# ---------------------------------------------------------------------------

class GitHubIssueLogger:
    """
    Dual-transport GitHub issue manager and telemetry logger for Roo4u.
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
        throttle_seconds: int = 60,
        enabled: bool = True
    ):
        self.owner = owner
        self.repo = repo
        self.token = token or os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        self.api_base_url = (api_base_url or os.getenv("GITHUB_API_BASE_URL", "https://api.github.com")).rstrip("/")
        self.mcp_caller = mcp_caller
        self.offline_queue_path = os.path.abspath(offline_queue_path)
        self.throttle_seconds = throttle_seconds
        self.enabled = enabled
        self._last_commented_time: Dict[str, float] = {}

    # -----------------------------------------------------------------------
    # Formatting Helpers
    # -----------------------------------------------------------------------

    def format_issue_title(self, event: ScrapingFailureEvent) -> str:
        """Constructs a clean, standardized issue title."""
        brief = event.selector if event.selector else event.error_message[:60].replace("\n", " ").strip()
        return f"[Scraping Failure] {event.domain} - {event.failure_type}: {brief}"

    def format_issue_body(self, event: ScrapingFailureEvent, lesson: Optional[Any] = None) -> str:
        """Constructs markdown issue body with embedded metadata comment block."""
        iso_time = event.timestamp.isoformat()
        fingerprint = event.error_fingerprint
        snippet = (event.dom_snippet or "<!-- No DOM snippet captured -->")[:4000]
        trace = event.stack_trace or "No stack trace provided."
        fix = event.suggested_fix or (getattr(lesson, "recommended_workaround", None) or getattr(lesson, "recommended_action", None)) or "Inspect target DOM hierarchy and update selector fallback list."

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
        snippet = (event.dom_snippet or "<!-- No DOM snippet captured -->")[:4000]

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

    def list_open_issues(self) -> Tuple[List[Dict[str, Any]], str]:
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
                if isinstance(res, list):
                    return res, "mcp"
                elif isinstance(res, dict):
                    if "issues" in res and isinstance(res["issues"], list):
                        return res["issues"], "mcp"
                    elif "data" in res and isinstance(res["data"], list):
                        return res["data"], "mcp"
            except Exception as e:
                logger.debug(f"MCP list_issues failed: {e}")

        # Try REST API
        try:
            url = f"{self.api_base_url}/repos/{self.owner}/{self.repo}/issues"
            params = {"state": "open", "per_page": 50}
            with httpx.Client(timeout=5.0) as client:
                resp = client.get(url, headers=self._get_rest_headers(), params=params)
                if resp.status_code == 200:
                    data = resp.json()
                    if isinstance(data, list):
                        return data, "rest"
        except Exception as e:
            logger.debug(f"REST list_open_issues failed: {e}")

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
        with httpx.Client(timeout=5.0) as client:
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
        with httpx.Client(timeout=5.0) as client:
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
                    if not isinstance(queue_data, list):
                        queue_data = []
            except Exception:
                queue_data = []

        item = {
            "id": str(uuid.uuid4()),
            "fingerprint": event.error_fingerprint,
            "event": event.model_dump(mode="json"),
            "title": title,
            "body": body,
            "labels": labels,
            "queued_at": datetime.now(timezone.utc).isoformat()
        }
        queue_data.append(item)

        # Atomic write
        q_dir = os.path.dirname(os.path.abspath(self.offline_queue_path)) or "."
        os.makedirs(q_dir, exist_ok=True)
        temp_file = f"{self.offline_queue_path}.tmp.{uuid.uuid4().hex[:8]}"
        with open(temp_file, "w", encoding="utf-8") as f:
            json.dump(queue_data, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
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
                if not isinstance(queue_data, list):
                    return []
        except Exception:
            return []

        results = []
        remaining = []

        for item in queue_data:
            try:
                event = ScrapingFailureEvent(**item["event"])
                res = self.log_scraping_failure(event, allow_queue=False)
                if res.action in ("created", "commented", "throttled"):
                    results.append(res)
                else:
                    remaining.append(item)
            except Exception:
                remaining.append(item)

        if remaining:
            temp_file = f"{self.offline_queue_path}.tmp.{uuid.uuid4().hex[:8]}"
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(remaining, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(temp_file, self.offline_queue_path)
        else:
            if os.path.exists(self.offline_queue_path):
                try:
                    os.remove(self.offline_queue_path)
                except Exception:
                    pass

        return results

    # -----------------------------------------------------------------------
    # Main Public Entrypoint
    # -----------------------------------------------------------------------

    def log_scraping_failure(
        self,
        event: ScrapingFailureEvent,
        lesson: Optional[Any] = None,
        allow_queue: bool = True
    ) -> IssueLogResult:
        """
        Processes a scraping failure:
        1. Checks open issues for deduplication.
        2. If duplicate exists, appends comment (with throttling).
        3. If no duplicate exists, creates new issue via MCP or REST fallback.
        4. Buffers to offline queue if remote transports fail.
        """
        if not self.enabled:
            return IssueLogResult(
                action="disabled",
                issue_number=None,
                issue_url=None,
                transport_used="none",
                deduplicated=False,
                error_fingerprint=event.error_fingerprint,
                message="GitHub logger is disabled"
            )

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

            # Check anti-spam throttling
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
        body = self.format_issue_body(event, lesson=lesson)

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
