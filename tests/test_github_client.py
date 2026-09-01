"""
tests/test_github_client.py

Comprehensive zero-mock unit tests for Roo4u Dual-Transport GitHub Client:
- ScrapingFailureEvent fingerprinting and structured markdown telemetry formatting
- Deduplication scanner matching by metadata comment block and title signature
- MCP tool transport caller integration
- Anti-spam comment recurrence throttling
- Offline file queue buffering (.github_issues_queue.json) and queue flushing
- Disabled logger state handling
"""

import os
import json
import tempfile
import time
from typing import Dict, Any, List
import pytest

from integrations.github_client import (
    ScrapingFailureEvent,
    IssueLogResult,
    GitHubIssueLogger
)


# ============================================================================
# 1. Event Model & Formatting Tests
# ============================================================================

def test_failure_event_fingerprinting_and_aliases():
    event = ScrapingFailureEvent(
        domain="zillow.com",
        source_url="https://www.zillow.com/homedetails/94115",
        category="DOM_SELECTOR_DRIFT",
        error_message="Waiting for selector [data-testid='property-summary'] timed out",
        attempted_selector="[data-testid='property-summary']",
        target_entity="2223 Pacific Ave"
    )

    # Aliases
    assert event.url == "https://www.zillow.com/homedetails/94115"
    assert event.failure_type == "DOM_SELECTOR_DRIFT"
    assert event.selector == "[data-testid='property-summary']"
    assert event.lead_address == "2223 Pacific Ave"

    # Deterministic fingerprint
    fp1 = event.error_fingerprint
    assert len(fp1) == 16
    assert fp1 == event.error_fingerprint

    # Fingerprint changes if domain or error pattern changes
    event2 = ScrapingFailureEvent(
        domain="sfplanninggis.org",
        source_url="https://sfplanninggis.org",
        category="DOM_SELECTOR_DRIFT",
        error_message="Different error",
        attempted_selector="#other"
    )
    assert event2.error_fingerprint != fp1


def test_issue_formatting_markdown_contracts():
    logger = GitHubIssueLogger(owner="s6pa1rta3n-lab", repo="roof4u")
    event = ScrapingFailureEvent(
        domain="zillow.com",
        url="https://www.zillow.com/homedetails/123",
        failure_type="DOM_SELECTOR_DRIFT",
        selector="[data-testid='property-summary']",
        error_message="Element not found in DOM",
        dom_snippet="<div class='page'><p>No summary</p></div>",
        lead_address="100 Main St"
    )

    title = logger.format_issue_title(event)
    assert title.startswith("[Scraping Failure] zillow.com - DOM_SELECTOR_DRIFT")
    assert "[data-testid='property-summary']" in title

    body = logger.format_issue_body(event)
    assert "<!-- ROO4U_TELEMETRY_START" in body
    assert "ROO4U_TELEMETRY_END -->" in body
    assert f"fingerprint: {event.error_fingerprint}" in body
    assert "domain: zillow.com" in body
    assert "lead_address: 100 Main St" in body
    assert "<div class='page'>" in body

    comment = logger.format_comment_body(event)
    assert "### 🔄 Scraping Failure Recurrence Logged" in comment
    assert event.error_fingerprint in comment


# ============================================================================
# 2. Deduplication Scanner Tests
# ============================================================================

def test_find_duplicate_issue_by_metadata_and_title():
    logger = GitHubIssueLogger(owner="s6pa1rta3n-lab", repo="roof4u")

    event = ScrapingFailureEvent(
        domain="zillow.com",
        url="https://zillow.com/p",
        failure_type="DOM_SELECTOR_DRIFT",
        selector=".summary-box",
        error_message="Missing summary box"
    )

    # 1. Open issue with matching metadata fingerprint
    matching_body = f"""
    <!-- ROO4U_TELEMETRY_START
    domain: zillow.com
    url: https://zillow.com/p
    failure_type: DOM_SELECTOR_DRIFT
    selector: .summary-box
    fingerprint: {event.error_fingerprint}
    ROO4U_TELEMETRY_END -->
    """
    open_issues = [
        {"number": 101, "title": "Other issue", "body": "some text", "html_url": "https://github.com/issues/101"},
        {"number": 102, "title": "Existing failure", "body": matching_body, "html_url": "https://github.com/issues/102"}
    ]
    dup = logger.find_duplicate_issue(event, open_issues)
    assert dup is not None
    assert dup["number"] == 102

    # 2. Fallback match by title prefix and selector
    open_issues_title_only = [
        {
            "number": 103,
            "title": "[Scraping Failure] zillow.com - DOM_SELECTOR_DRIFT: .summary-box",
            "body": "No metadata block here",
            "html_url": "https://github.com/issues/103"
        }
    ]
    dup_title = logger.find_duplicate_issue(event, open_issues_title_only)
    assert dup_title is not None
    assert dup_title["number"] == 103

    # 3. No match
    unrelated_event = ScrapingFailureEvent(
        domain="sfplanninggis.org",
        url="https://sfplanninggis.org",
        failure_type="RATE_LIMIT_ERROR",
        error_message="HTTP 429"
    )
    assert logger.find_duplicate_issue(unrelated_event, open_issues_title_only) is None


# ============================================================================
# 3. Dual-Transport & Live MCP Adapter Tests
# ============================================================================

def test_mcp_transport_issue_creation_and_recurrence():
    # In-memory MCP transport mock-free adapter (simulates real MCP server tool dispatch)
    server_state = {
        "issues": [],
        "comments": []
    }

    def in_process_mcp_caller(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        if tool_name == "list_issues":
            return server_state["issues"]
        elif tool_name == "issue_write":
            issue_num = len(server_state["issues"]) + 1
            issue = {
                "number": issue_num,
                "title": args["title"],
                "body": args["body"],
                "labels": args.get("labels", []),
                "html_url": f"https://github.com/s6pa1rta3n-lab/roof4u/issues/{issue_num}"
            }
            server_state["issues"].append(issue)
            return issue
        elif tool_name == "add_issue_comment":
            comment_id = len(server_state["comments"]) + 1
            comment = {
                "id": comment_id,
                "issue_number": args["issue_number"],
                "body": args["body"]
            }
            server_state["comments"].append(comment)
            return comment
        raise ValueError(f"Unknown tool: {tool_name}")

    with tempfile.TemporaryDirectory() as tmp_dir:
        q_path = os.path.join(tmp_dir, "queue.json")
        logger = GitHubIssueLogger(
            owner="s6pa1rta3n-lab",
            repo="roof4u",
            mcp_caller=in_process_mcp_caller,
            offline_queue_path=q_path,
            throttle_seconds=2
        )

        event = ScrapingFailureEvent(
            domain="zillow.com",
            url="https://zillow.com/p",
            failure_type="DOM_SELECTOR_DRIFT",
            selector=".chip-container",
            error_message="Selector missing"
        )

        # 1. First occurrence: creates new issue via MCP
        res1 = logger.log_scraping_failure(event)
        assert res1.action == "created"
        assert res1.transport_used == "mcp"
        assert res1.issue_number == 1
        assert len(server_state["issues"]) == 1

        # 2. Immediate recurrence: throttled
        res2 = logger.log_scraping_failure(event)
        assert res2.action == "throttled"
        assert res2.deduplicated is True
        assert res2.issue_number == 1

        # 3. Recurrence after throttle period: comments on existing issue
        time.sleep(2.1)
        res3 = logger.log_scraping_failure(event)
        assert res3.action == "commented"
        assert res3.transport_used == "mcp"
        assert res3.issue_number == 1
        assert len(server_state["comments"]) == 1


# ============================================================================
# 4. Offline Queue Buffering & Replay Tests
# ============================================================================

def test_offline_queue_buffering_and_flushing():
    server_state = {"issues": []}

    def working_mcp_caller(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        if tool_name == "list_issues":
            return server_state["issues"]
        elif tool_name == "issue_write":
            issue_num = len(server_state["issues"]) + 1
            issue = {
                "number": issue_num,
                "title": args["title"],
                "body": args["body"],
                "html_url": f"https://github.com/issues/{issue_num}"
            }
            server_state["issues"].append(issue)
            return issue
        return {}

    with tempfile.TemporaryDirectory() as tmp_dir:
        q_path = os.path.join(tmp_dir, "queue.json")

        # 1. Logger with no remote transports (simulating offline mode)
        offline_logger = GitHubIssueLogger(
            owner="s6pa1rta3n-lab",
            repo="roof4u",
            api_base_url="http://127.0.0.1:9999/unreachable",
            mcp_caller=None,
            offline_queue_path=q_path
        )

        event = ScrapingFailureEvent(
            domain="sfplanninggis.org",
            url="https://sfplanninggis.org/pim",
            failure_type="NETWORK_TIMEOUT",
            error_message="Connection timed out"
        )

        res = offline_logger.log_scraping_failure(event)
        assert res.action == "queued"
        assert res.transport_used == "offline_queue"
        assert os.path.exists(q_path)

        with open(q_path, "r", encoding="utf-8") as f:
            q_data = json.load(f)
        assert len(q_data) == 1
        assert q_data[0]["event"]["domain"] == "sfplanninggis.org"

        # 2. Re-attach working transport and flush
        offline_logger.mcp_caller = working_mcp_caller
        flushed_results = offline_logger.flush_offline_queue()
        assert len(flushed_results) == 1
        assert flushed_results[0].action == "created"
        assert len(server_state["issues"]) == 1

        # Queue file should be cleaned up
        assert not os.path.exists(q_path) or len(json.load(open(q_path))) == 0


def test_disabled_logger():
    logger = GitHubIssueLogger(enabled=False)
    event = ScrapingFailureEvent(
        domain="zillow.com",
        url="https://zillow.com",
        failure_type="UNKNOWN",
        error_message="test"
    )
    res = logger.log_scraping_failure(event)
    assert res.action == "disabled"
    assert res.transport_used == "none"
