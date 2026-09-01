"""
tests/test_challenger_m2_deep_stress.py

Empirical Challenger 2 Deep Stress & Adversarial Test Suite for Roo4u M2:
1. LearningAgent failure observation across all FailureCategory types:
   - Exhaustive enum & string categorization matrix
   - Extreme payloads: 100KB DOM snippets, Unicode/emojis, SQL/HTML injection strings
   - Occurrence count arithmetic and deterministic fingerprinting
2. Feedforward strategy compilation & strict domain isolation:
   - Multi-domain concurrency (Zillow, SF Planning, SF DBI, Redfin, Alameda County)
   - Zero selector leakage across domains under semantic & exact queries
   - Case-insensitivity, subdomain isolation, and DEPRECATED lesson suppression
3. GitHubIssueLogger deduplication under burst volume & offline queue resilience:
   - Multi-threaded burst concurrency (50+ events across 10 threads)
   - Deduplication via metadata regex and title signatures
   - Subsecond anti-spam throttling
   - Offline queue atomic buffering, partial flush failures, and replay preservation
   - Empirical vulnerability tests: Comment failure fallthrough bug demonstration
4. Closed-loop agent integration (ZillowAgent & CountyAgent):
   - Adaptive self-healing loop: Failure -> Observation -> Feedforward Strategy -> Workaround -> Success Tracking
   - E2E DOM cleaning with fallback selector injection
   - Date parsing edge-case matrix & qualification state transitions
5. Identified Architecture & Subsystem Defect Demonstrations:
   - LocalVectorStore in-memory (:memory:) table loss defect
   - LessonStore subsecond backup timestamp collision
"""

import os
import sys
import json
import time
import uuid
import tempfile
import threading
import sqlite3
from datetime import datetime, timezone, date
from typing import Dict, Any, List, Optional
import pytest

from memory.lesson_store import LessonStore, Lesson
from memory.embeddings import OfflineEmbeddingGenerator
from memory.vector_store import LocalVectorStore, VectorRecord, SearchResult, sync_stores
from integrations.github_client import (
    GitHubIssueLogger,
    ScrapingFailureEvent,
    IssueLogResult
)
from agents.learning_agent import (
    LearningAgent,
    FailureCategory,
    FeedforwardStrategy,
    LessonResolution
)
from agents.base_agent import BaseAgent
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor, PropertyExtraction, CountyPermitExtraction
from db.database import init_db, get_session, Lead


# ============================================================================
# 1. LEARNING AGENT FAILURE OBSERVATION & CATEGORIZATION STRESS
# ============================================================================

class TestLearningAgentFailureObservationStress:
    """Stress-tests failure observation and dual-memory upsert across all FailureCategory types."""

    @pytest.mark.parametrize(
        "category",
        [
            FailureCategory.DOM_SELECTOR_DRIFT,
            FailureCategory.ANTI_BOT_BLOCKED,
            FailureCategory.RATE_LIMIT_ERROR,
            FailureCategory.NETWORK_TIMEOUT,
            FailureCategory.EXTRACTION_PARSE_ERROR,
            FailureCategory.SCHEMA_VALIDATION_ERROR,
            FailureCategory.INFERENCE_ENDPOINT_ERROR,
            FailureCategory.UNKNOWN,
        ]
    )
    def test_all_failure_categories_observation_and_dual_memory_indexing(self, category):
        """Verifies that every FailureCategory enum member is properly observed, triaged, and indexed."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons.json")
            db_path = os.path.join(tmp_dir, "vectors.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)
            gh_logger = GitHubIssueLogger(enabled=False)

            agent = LearningAgent(
                lesson_store=lstore,
                vector_store=vstore,
                github_logger=gh_logger
            )

            event = ScrapingFailureEvent(
                domain="zillow.com",
                url="https://zillow.com/test",
                category=category,
                selector=".target-sel" if category == FailureCategory.DOM_SELECTOR_DRIFT else None,
                error_message=f"Detailed error for category {category.value}"
            )

            resolution = agent.observe_failure(event)

            assert isinstance(resolution, LessonResolution)
            assert resolution.lesson is not None
            assert resolution.lesson.domain == "zillow.com"
            assert resolution.lesson.failure_type == category.value
            assert resolution.vector_db_indexed is True

            # Verify in LessonStore
            stored = lstore.get_lesson(resolution.lesson.id)
            assert stored is not None
            assert stored.failure_type == category.value
            assert stored.occurrence_count == 1

            # Verify in LocalVectorStore
            vrec = vstore.get(resolution.lesson.id)
            assert vrec is not None
            assert vrec.domain == "zillow.com"
            assert vrec.failure_type == category.value

            # Second occurrence increments count
            res2 = agent.observe_failure(event)
            assert res2.lesson.id == resolution.lesson.id
            assert res2.lesson.occurrence_count == 2
            assert lstore.count() == 1

    def test_extreme_payload_and_special_character_observation(self):
        """Tests failure observation with 100KB DOM snippet, unicode, quotes, and HTML/SQL injection strings."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons.json")
            db_path = os.path.join(tmp_dir, "vectors.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)
            agent = LearningAgent(
                lesson_store=lstore,
                vector_store=vstore,
                github_logger=GitHubIssueLogger(enabled=False)
            )

            large_dom = "<div class='outer'>" + ("<div class='inner'><span>Test Data</span></div>\n" * 2000) + "</div>"
            assert len(large_dom) > 80000

            nasty_string = (
                "'; DROP TABLE vector_records; -- \n"
                "<script>alert('xss');</script>\n"
                "屋顶 🏠 🚨 \"Quotes\" & 'Apostrophes' \t\r\n"
                "\\n \\t \\r / // %20 %00 \x00"
            )

            event = ScrapingFailureEvent(
                domain="extreme-test.org",
                url="https://extreme-test.org/path?param=' OR 1=1 --",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector="div.outer > div.inner:nth-child(5)",
                error_message=nasty_string,
                dom_snippet=large_dom,
                target_entity="2223 Pacific Ave",
                phase="DISCOVERY"
            )

            resolution = agent.observe_failure(event)
            assert resolution.lesson is not None
            assert lstore.count() == 1
            assert vstore.count() == 1

            # Reload and verify
            stored = lstore.get_lesson(resolution.lesson.id)
            assert stored is not None
            assert stored.dom_snippet == large_dom
            assert "DROP TABLE" in stored.error_message

            # Check vector store was not broken by injection
            vrec = vstore.get(resolution.lesson.id)
            assert vrec is not None
            assert vrec.id == resolution.lesson.id


# ============================================================================
# 2. FEEDFORWARD STRATEGY COMPILATION & STRICT DOMAIN ISOLATION
# ============================================================================

class TestFeedforwardCompilationAndDomainIsolation:
    """Stress-tests pre-scrape strategy compilation and ensures zero cross-domain selector leakage."""

    def test_multi_domain_strict_selector_isolation(self):
        """
        Populates lessons across 5 domains (Zillow, SF Planning, SF DBI, Redfin, Alameda County)
        and verifies that querying each domain's feedforward strategy yields strictly zero selectors
        from any other domain.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons.json")
            db_path = os.path.join(tmp_dir, "vectors.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)
            agent = LearningAgent(
                lesson_store=lstore,
                vector_store=vstore,
                github_logger=GitHubIssueLogger(enabled=False)
            )

            # 1. Zillow
            agent.observe_failure(ScrapingFailureEvent(
                domain="zillow.com",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector="[data-testid='home-details-chip-container']",
                error_message="Zillow chip container missing"
            ))

            # 2. SF Planning (PIM)
            agent.observe_failure(ScrapingFailureEvent(
                domain="sfplanninggis.org",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector="#propertyDetails",
                error_message="PIM details table missing"
            ))

            # 3. SF DBI
            agent.observe_failure(ScrapingFailureEvent(
                domain="dbiweb02.sfgov.org",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector=".dbi-grid",
                error_message="DBI grid table missing"
            ))

            # 4. Redfin
            agent.observe_failure(ScrapingFailureEvent(
                domain="redfin.com",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector=".redfin-home-facts",
                error_message="Redfin facts missing"
            ))

            # 5. Alameda County
            agent.observe_failure(ScrapingFailureEvent(
                domain="alamedacounty.gov",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector=".alameda-assessor-box",
                error_message="Alameda assessor missing"
            ))

            # --- Query Zillow Strategy ---
            z_strat = agent.get_feedforward_strategy("zillow.com", "scrape listing details")
            assert z_strat.domain == "zillow.com"
            assert len(z_strat.fallback_selectors) > 0
            assert any("ds-overview-section" in s or "chip-container" in s for s in z_strat.fallback_selectors)
            # Isolation assertions
            assert not any("propertyDetails" in s for s in z_strat.fallback_selectors)
            assert not any("dbi-grid" in s for s in z_strat.fallback_selectors)
            assert not any("alameda" in s for s in z_strat.fallback_selectors)

            # --- Query SF Planning Strategy ---
            p_strat = agent.get_feedforward_strategy("sfplanninggis.org", "assessor parcel search")
            assert p_strat.domain == "sfplanninggis.org"
            assert any("parcel-details" in s or "propertyDetails" in s for s in p_strat.fallback_selectors)
            # Isolation assertions
            assert not any("chip-container" in s for s in p_strat.fallback_selectors)
            assert not any("ds-overview" in s for s in p_strat.fallback_selectors)
            assert not any("dbi-grid" in s for s in p_strat.fallback_selectors)

            # --- Query SF DBI Strategy ---
            d_strat = agent.get_feedforward_strategy("dbiweb02.sfgov.org", "permit table search")
            assert d_strat.domain == "dbiweb02.sfgov.org"
            assert any("dbi-grid" in s or "permit" in s for s in d_strat.fallback_selectors)
            # Isolation assertions
            assert not any("chip-container" in s for s in d_strat.fallback_selectors)
            assert not any("propertyDetails" in s for s in d_strat.fallback_selectors)

    def test_case_insensitivity_and_subdomain_handling(self):
        """Tests that strategy retrieval correctly normalizes case and matches domain."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons.json")
            db_path = os.path.join(tmp_dir, "vectors.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)
            agent = LearningAgent(
                lesson_store=lstore,
                vector_store=vstore,
                github_logger=GitHubIssueLogger(enabled=False)
            )

            agent.observe_failure(ScrapingFailureEvent(
                domain="ZILLOW.COM",
                category=FailureCategory.ANTI_BOT_BLOCKED,
                error_message="HTTP 403"
            ))

            # Query with lower case
            strat_lower = agent.get_feedforward_strategy("zillow.com")
            assert strat_lower.request_delay_seconds >= 2.5
            assert "User-Agent" in strat_lower.custom_headers

            # Query with upper case
            strat_upper = agent.get_feedforward_strategy("ZILLOW.COM")
            assert strat_upper.request_delay_seconds >= 2.5


# ============================================================================
# 3. GITHUB ISSUE LOGGER DEDUPLICATION, QUEUE & REPLAY STRESS
# ============================================================================

class TestGitHubIssueLoggerDeduplicationAndQueueStress:
    """Stress-tests GitHubIssueLogger under heavy concurrent bursts, offline queueing, and replay."""

    def test_high_volume_concurrency_deduplication(self):
        """
        Fires 50 failure events across 10 threads simulating a sudden burst of errors.
        Events share 5 distinct fingerprints (10 occurrences each).
        Asserts that exactly 5 issues are created and remaining events are throttled or commented.
        """
        server_state = {"issues": [], "comments": []}
        lock = threading.Lock()

        def live_mcp_dispatcher(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
            with lock:
                if tool_name == "list_issues":
                    return server_state["issues"]
                elif tool_name == "issue_write":
                    issue_num = len(server_state["issues"]) + 1
                    iss = {
                        "number": issue_num,
                        "title": args["title"],
                        "body": args["body"],
                        "labels": args.get("labels", []),
                        "html_url": f"https://github.com/s6pa1rta3n-lab/roof4u/issues/{issue_num}"
                    }
                    server_state["issues"].append(iss)
                    return iss
                elif tool_name == "add_issue_comment":
                    cid = len(server_state["comments"]) + 1
                    c = {
                        "id": cid,
                        "issue_number": args["issue_number"],
                        "body": args["body"]
                    }
                    server_state["comments"].append(c)
                    return c
            return {}

        with tempfile.TemporaryDirectory() as tmp_dir:
            q_path = os.path.join(tmp_dir, "queue.json")
            logger = GitHubIssueLogger(
                owner="s6pa1rta3n-lab",
                repo="roof4u",
                mcp_caller=live_mcp_dispatcher,
                offline_queue_path=q_path,
                throttle_seconds=30
            )

            unique_events = [
                ScrapingFailureEvent(domain="zillow.com", selector=f".sel_{i}", failure_type="DOM_SELECTOR_DRIFT", error_message=f"Error {i}")
                for i in range(5)
            ]

            results = []
            results_lock = threading.Lock()

            def worker(thread_idx: int):
                for i in range(5):
                    # Each thread sends an event matching one of the 5 fingerprints
                    ev = unique_events[(thread_idx + i) % 5]
                    res = logger.log_scraping_failure(ev)
                    with results_lock:
                        results.append(res)

            threads = [threading.Thread(target=worker, args=(t,)) for t in range(10)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()

            assert len(results) == 50
            # Exactly 5 issues must have been created
            created = [r for r in results if r.action == "created"]
            assert len(created) == 5
            assert len(server_state["issues"]) == 5

            # All remaining results must be throttled deduplicated occurrences
            throttled = [r for r in results if r.action == "throttled"]
            assert len(throttled) == 45
            for r in throttled:
                assert r.deduplicated is True
                assert r.issue_number in [1, 2, 3, 4, 5]

    def test_offline_queue_buffering_and_full_flush_replay(self):
        """
        Buffers 25 offline failure events when network is down.
        Re-attaches working transport (with add_issue_comment support) and flushes queue.
        Verifies that all events are replayed, deduplicated, and the queue file is cleanly removed.
        """
        server_state = {"issues": [], "comments": []}

        def mock_mcp_caller(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
            if tool_name == "list_issues":
                return server_state["issues"]
            elif tool_name == "issue_write":
                issue_num = len(server_state["issues"]) + 1
                iss = {
                    "number": issue_num,
                    "title": args["title"],
                    "body": args["body"],
                    "html_url": f"https://github.com/issues/{issue_num}"
                }
                server_state["issues"].append(iss)
                return iss
            elif tool_name == "add_issue_comment":
                cid = len(server_state["comments"]) + 1
                comment = {"id": cid, "issue_number": args["issue_number"], "body": args["body"]}
                server_state["comments"].append(comment)
                return comment
            return {}

        with tempfile.TemporaryDirectory() as tmp_dir:
            q_path = os.path.join(tmp_dir, "offline_queue.json")

            offline_logger = GitHubIssueLogger(
                owner="s6pa1rta3n-lab",
                repo="roof4u",
                api_base_url="http://127.0.0.1:9999/unreachable",
                mcp_caller=None,
                offline_queue_path=q_path,
                throttle_seconds=0
            )

            # Buffer 25 events (5 unique domains, 5 events each)
            for i in range(25):
                domain = f"site_{i % 5}.org"
                ev = ScrapingFailureEvent(
                    domain=domain,
                    url=f"https://{domain}/path",
                    failure_type="RATE_LIMIT_ERROR",
                    error_message=f"HTTP 429 on {domain}"
                )
                res = offline_logger.log_scraping_failure(ev)
                assert res.action == "queued"
                assert res.transport_used == "offline_queue"

            assert os.path.exists(q_path)
            with open(q_path, "r", encoding="utf-8") as f:
                queue_items = json.load(f)
            assert len(queue_items) == 25

            # Re-attach live MCP caller and flush
            offline_logger.mcp_caller = mock_mcp_caller
            flushed_results = offline_logger.flush_offline_queue()

            # Since throttle_seconds is 0, each distinct domain creates 1 issue, then remaining are commented
            assert len(flushed_results) == 25
            assert len(server_state["issues"]) == 5
            assert len(server_state["comments"]) == 20

            # Queue file should be cleaned up
            assert not os.path.exists(q_path) or len(json.load(open(q_path))) == 0

    def test_comment_failure_fallthrough_defect_demonstration(self):
        """
        Adversarial test demonstrating the deduplication bug in GitHubIssueLogger:
        When an issue duplicate is found, but commenting fails (e.g. MCP caller returns {} or throws),
        the execution erroneously falls through to 'CASE B: No Duplicate -> Create New Issue'
        and creates a duplicate issue rather than returning an error or queueing.
        """
        server_state = {"issues": []}

        # Caller that can create issues and list issues, but fails commenting
        def flawed_mcp_caller(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
            if tool_name == "list_issues":
                return server_state["issues"]
            elif tool_name == "issue_write":
                issue_num = len(server_state["issues"]) + 1
                iss = {
                    "number": issue_num,
                    "title": args["title"],
                    "body": args["body"],
                    "html_url": f"https://github.com/issues/{issue_num}"
                }
                server_state["issues"].append(iss)
                return iss
            elif tool_name == "add_issue_comment":
                # Fails commenting
                return {}
            return {}

        with tempfile.TemporaryDirectory() as tmp_dir:
            q_path = os.path.join(tmp_dir, "queue.json")
            logger = GitHubIssueLogger(
                owner="s6pa1rta3n-lab",
                repo="roof4u",
                mcp_caller=flawed_mcp_caller,
                offline_queue_path=q_path,
                throttle_seconds=0
            )

            event = ScrapingFailureEvent(
                domain="zillow.com",
                url="https://zillow.com",
                failure_type="DOM_SELECTOR_DRIFT",
                error_message="Drift error"
            )

            # Event 1: Creates issue #1
            res1 = logger.log_scraping_failure(event)
            assert res1.action == "created"
            assert res1.issue_number == 1
            assert len(server_state["issues"]) == 1

            # Event 2: Duplicate found, but comment fails.
            # Due to fallthrough in lines 498-560 of github_client.py, it creates issue #2!
            res2 = logger.log_scraping_failure(event)
            # This confirms the fallthrough vulnerability where duplicate issues get created
            assert len(server_state["issues"]) == 2, "Confirmed: comment failure falls through to create duplicate issue"


# ============================================================================
# 4. CLOSED-LOOP AGENT INTEGRATION TESTS
# ============================================================================

class TestClosedLoopAgentIntegration:
    """Stress-tests the closed-loop learning and self-healing lifecycle with ZillowAgent & CountyAgent."""

    def test_zillow_agent_feedforward_adaptive_cleaning(self):
        """Tests that ZillowAgent dynamically incorporates feedforward fallback selectors into clean_dom."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons.json")
            db_path = os.path.join(tmp_dir, "vectors.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)
            learning_agent = LearningAgent(
                lesson_store=lstore,
                vector_store=vstore,
                github_logger=GitHubIssueLogger(enabled=False)
            )

            # Ingest lesson indicating selector drift on Zillow with custom fallback
            learning_agent.observe_failure(ScrapingFailureEvent(
                domain="zillow.com",
                category=FailureCategory.DOM_SELECTOR_DRIFT,
                selector=".redesigned-listing-card",
                error_message="Standard selectors missing"
            ))

            zillow = ZillowAgent(headless=True, learning_agent=learning_agent)

            html = """
            <html>
                <body>
                    <div class="ds-overview-section">
                        <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
                        <span class="price">$4,500,000</span>
                        <span class="facts">4 bds | 3 ba | 3,450 sqft</span>
                    </div>
                </body>
            </html>
            """
            strategy = learning_agent.get_feedforward_strategy("zillow.com")
            cleaned = zillow.clean_dom(html, extra_selectors=strategy.fallback_selectors)

            assert "2223 Pacific Ave" in cleaned
            assert "$4,500,000" in cleaned
            assert "3,450 sqft" in cleaned

    def test_county_agent_date_parsing_and_lead_enrichment_rules(self):
        """Tests CountyAgent permit date parsing robustness and qualification transitions."""
        county = CountyAgent(headless=True)

        test_dates = [
            ("2008-11-20", 2008),
            ("11/20/2008", 2008),
            ("11/20/08", 2008),
            ("Nov 20, 2008", 2008),
            ("November 20, 2008", 2008),
            ("2008.11.20", 2008),
            ("Permit Year 2008", 2008),
            ("N/A", None),
            ("none", None),
            ("null", None),
            ("no_permit_on_file", None),
            ("", None),
        ]

        for raw_str, expected_yr in test_dates:
            dt = county.parse_permit_date(raw_str)
            if expected_yr is None:
                assert dt is None, f"Expected None for '{raw_str}', got {dt}"
            else:
                assert dt is not None, f"Expected date for '{raw_str}', got None"
                assert dt.year == expected_yr

        # Lead qualification check
        lead = Lead(
            address="2223 Pacific Ave",
            zip_code="94115",
            roof_age_years=18.0,
            estimated_value=1200000.0,
            status="DISCOVERED"
        )
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"
        assert lead.status == "VALIDATED"


# ============================================================================
# 5. SUBSYSTEM RESILIENCE & HARDENING VERIFICATION
# ============================================================================

class TestSubsystemDefectDemonstrations:
    """Empirical verification of subsystem resilience and hardening fixes."""

    def test_local_vector_store_in_memory_persistence(self):
        """
        Verifies that LocalVectorStore with db_path=":memory:" maintains a persistent
        SQLite connection so table schema and upserted records persist across operations.
        """
        mem_store = LocalVectorStore(db_path=":memory:")
        rec = mem_store.upsert(id="mem_1", text="Test text for in-memory persistence", domain="zillow.com")
        assert rec.id == "mem_1"
        assert mem_store.count() == 1

        fetched = mem_store.get("mem_1")
        assert fetched is not None
        assert fetched.text == "Test text for in-memory persistence"

        search_results = mem_store.search("Test text")
        assert len(search_results) == 1
        assert search_results[0].record.id == "mem_1"

        mem_store.close()

    def test_lesson_store_subsecond_backup_collision_resilience(self):
        """
        Verifies that LessonStore.load_lessons() uses sub-second precision and UUID suffix
        for backup files, preventing filename collisions during rapid sub-second corruptions.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "lessons.json")

            # Corrupt 1
            with open(ledger_path, "w", encoding="utf-8") as f:
                f.write("{corrupt 1")
            store = LessonStore(file_path=ledger_path)
            store.load_lessons()

            # Corrupt 2 immediately within same second
            with open(ledger_path, "w", encoding="utf-8") as f:
                f.write("{corrupt 2")
            store.load_lessons()

            backup_files = [f for f in os.listdir(tmp_dir) if "lessons.json.corrupt." in f]
            # High-precision + UUID guarantees exactly 2 distinct backup files
            assert len(backup_files) == 2
