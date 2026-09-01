"""
tests/test_learning_agent.py

Comprehensive zero-mock unit tests for Roo4u Learning Agent & Feedforward Loop:
- Observation of scraping failures and dual-memory upsert (JSON + VectorStore)
- Root-cause heuristic classification across all FailureCategory types
- Feedforward pre-scrape strategy compilation & domain isolation
- Workaround efficacy tracking (observe_success) and resolution transition
- Closed-loop integration with ZillowAgent and CountyAgent
"""

import os
import tempfile
import pytest

from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger, ScrapingFailureEvent
from agents.learning_agent import (
    LearningAgent,
    FailureCategory,
    FeedforwardStrategy,
    LessonResolution
)
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor, PropertyExtraction


# ============================================================================
# 1. Observation & Dual-Memory Upsert Tests
# ============================================================================

def test_observe_failure_and_dual_memory_upsert():
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
            source_url="https://www.zillow.com/homedetails/94115_rb",
            phase="DISCOVERY",
            target_entity="94115",
            category=FailureCategory.DOM_SELECTOR_DRIFT,
            exception_class="SelectorNotFoundError",
            error_message="0 property cards found on search page",
            attempted_action="discover_properties",
            attempted_selector="[data-testid='property-card']",
            dom_snapshot_snippet="<div class='results-container'></div>"
        )

        resolution = agent.observe_failure(event)

        # 1. Resolution checks
        assert isinstance(resolution, LessonResolution)
        assert resolution.lesson is not None
        assert resolution.lesson.domain == "zillow.com"
        assert resolution.lesson.failure_type == "DOM_SELECTOR_DRIFT"
        assert resolution.vector_db_indexed is True
        assert resolution.retry_recommended is True
        assert len(resolution.lesson.suggested_selectors) > 0

        # 2. LessonStore persistence
        assert lstore.count() == 1
        stored_lesson = lstore.get_lesson(resolution.lesson.id)
        assert stored_lesson is not None
        assert stored_lesson.domain == "zillow.com"
        assert stored_lesson.occurrence_count == 1

        # 3. VectorStore indexing
        assert vstore.count() == 1
        rec = vstore.get(resolution.lesson.id)
        assert rec is not None
        assert rec.domain == "zillow.com"
        assert rec.metadata["failure_type"] == "DOM_SELECTOR_DRIFT"

        # 4. Repeat occurrence increments counter
        res2 = agent.observe_failure(event)
        assert res2.lesson.id == resolution.lesson.id
        assert res2.lesson.occurrence_count == 2
        assert lstore.count() == 1


# ============================================================================
# 2. Heuristic Classification Tests Across Categories
# ============================================================================

@pytest.mark.parametrize(
    "category,domain,selector,expected_cause_kw,expected_delay",
    [
        (FailureCategory.DOM_SELECTOR_DRIFT, "zillow.com", ".ds-overview-section", "drift", 0.0),
        (FailureCategory.ANTI_BOT_BLOCKED, "zillow.com", None, "Anti-bot", 2.5),
        (FailureCategory.RATE_LIMIT_ERROR, "dbiweb02.sfgov.org", None, "Rate limit", 5.0),
        (FailureCategory.NETWORK_TIMEOUT, "sfplanninggis.org", None, "timeout", 1.0),
        (FailureCategory.SCHEMA_VALIDATION_ERROR, "zillow.com", None, "schema", 0.0),
        (FailureCategory.EXTRACTION_PARSE_ERROR, "sfplanninggis.org", None, "unparseable", 0.0),
        (FailureCategory.UNKNOWN, "general.com", None, "Unclassified", 0.0),
    ]
)
def test_heuristic_root_cause_diagnosis(category, domain, selector, expected_cause_kw, expected_delay):
    agent = LearningAgent(
        lesson_store=LessonStore(file_path=":memory:"),
        vector_store=LocalVectorStore(db_path=":memory:"),
        github_logger=GitHubIssueLogger(enabled=False)
    )

    event = ScrapingFailureEvent(
        domain=domain,
        url=f"https://{domain}/test",
        failure_type=category.value,
        category=category,
        error_message="Test failure message",
        selector=selector
    )

    root_cause, workaround, selectors, delay, headers = agent._diagnose_root_cause(event)
    assert expected_cause_kw.lower() in root_cause.lower()
    assert delay == expected_delay
    if category == FailureCategory.ANTI_BOT_BLOCKED:
        assert "User-Agent" in headers


# ============================================================================
# 3. Feedforward Retrieval & Domain Isolation Tests
# ============================================================================

def test_feedforward_strategy_compilation_and_isolation():
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

        # Ingest Zillow lessons
        agent.observe_failure(ScrapingFailureEvent(
            domain="zillow.com",
            url="https://zillow.com",
            category=FailureCategory.DOM_SELECTOR_DRIFT,
            selector=".ds-overview-section",
            error_message="Selector drift"
        ))
        agent.observe_failure(ScrapingFailureEvent(
            domain="zillow.com",
            url="https://zillow.com",
            category=FailureCategory.ANTI_BOT_BLOCKED,
            error_message="403 Bot Block"
        ))

        # Ingest County lesson
        agent.observe_failure(ScrapingFailureEvent(
            domain="sfplanninggis.org",
            url="https://sfplanninggis.org",
            category=FailureCategory.DOM_SELECTOR_DRIFT,
            selector="#propertyDetails",
            error_message="PIM table missing"
        ))

        # 1. Query Zillow Feedforward Strategy
        zillow_strategy = agent.get_feedforward_strategy("zillow.com", "scrape property")
        assert isinstance(zillow_strategy, FeedforwardStrategy)
        assert zillow_strategy.domain == "zillow.com"
        assert zillow_strategy.request_delay_seconds >= 2.5
        assert len(zillow_strategy.fallback_selectors) > 0
        assert "User-Agent" in zillow_strategy.custom_headers
        assert any("ANTI_BOT_BLOCKED" in b for b in zillow_strategy.known_blockers)

        # Ensure no SF Planning selectors leak into Zillow strategy
        assert "#propertyDetails" not in zillow_strategy.fallback_selectors
        assert ".parcel-details" not in zillow_strategy.fallback_selectors

        # 2. Query County Feedforward Strategy
        county_strategy = agent.get_feedforward_strategy("sfplanninggis.org", "assessor lookup")
        assert county_strategy.domain == "sfplanninggis.org"
        assert any(".parcel-details" in s for s in county_strategy.fallback_selectors)


# ============================================================================
# 4. Success Efficacy Tracking Tests
# ============================================================================

def test_observe_success_and_status_resolution():
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

        res = agent.observe_failure(ScrapingFailureEvent(
            domain="dbiweb02.sfgov.org",
            url="https://dbiweb02.sfgov.org",
            category=FailureCategory.RATE_LIMIT_ERROR,
            error_message="HTTP 429"
        ))
        lesson_id = res.lesson.id

        # Observe 5 successes
        for _ in range(5):
            agent.observe_success("dbiweb02.sfgov.org", "2223 Pacific Ave", lesson_id=lesson_id)

        lesson = lstore.get_lesson(lesson_id)
        assert lesson is not None
        assert lesson.success_count_after_workaround == 5
        assert lesson.status == "RESOLVED"
        assert lesson.resolved is True

        # Check vector metadata updated
        rec = vstore.get(lesson_id)
        assert rec.metadata["status"] == "RESOLVED"


# ============================================================================
# 5. Browsing Agent Closed-Loop Integration Tests
# ============================================================================

def test_zillow_and_county_agents_learning_loop_integration():
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

        zillow = ZillowAgent(headless=True, learning_agent=learning_agent)
        county = CountyAgent(headless=True, learning_agent=learning_agent)

        # Test Zillow clean_dom with extra selectors
        html = """
        <html>
            <body>
                <div class="custom-workaround-card">
                    <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
                    <span class="price">$4,500,000</span>
                    <span class="roof">Slate Roof</span>
                </div>
            </body>
        </html>
        """
        cleaned = zillow.clean_dom(html, extra_selectors=[".custom-workaround-card"])
        assert "2223 Pacific Ave" in cleaned
        assert "Slate Roof" in cleaned

        # Test County date parsing
        d = county.parse_permit_date("2018-05-12")
        assert d is not None
        assert d.year == 2018
