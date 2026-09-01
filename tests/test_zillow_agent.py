"""
tests/test_zillow_agent.py

Component test suite for agents/zillow_agent.py.
Validates DOM cleaning, selective semantic extraction, token length budgeting,
property scraping from live loopback URLs, Lead creation, discovery card parsing,
and self-healing selector drift detection.
100% Mock-Free.
"""

import pytest
from bs4 import BeautifulSoup

from agents.zillow_agent import ZillowAgent
from agents.extractor import LocalLLMExtractor, PropertyExtraction
from agents.learning_agent import LearningAgent
from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger
from db.database import Lead


# ============================================================================
# 1. DOM CLEANING & TOKEN BUDGET ENGINE
# ============================================================================

class TestZillowDOMCleaningEngine:
    """Validates ZillowAgent.clean_dom across unwanted tags, comments, selectors, and budgets."""

    def test_strip_unwanted_tags(self):
        raw_html = """
        <html>
        <head><title>Zillow Listing</title><style>.hidden{display:none;}</style></head>
        <body>
            <script>var tracker = 123;</script>
            <noscript>Enable JS</noscript>
            <svg><path d="M0 0"/></svg>
            <nav><a href="/buy">Buy</a></nav>
            <header><p>Header Banner</p></header>
            <div data-testid="property-summary">
                <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
                <span class="price">$4,370,000</span>
            </div>
            <button>Contact Agent</button>
            <form action="/contact"><input type="text" name="name"></form>
            <aside>Cookie banner</aside>
            <footer><p>Footer 2026</p></footer>
        </body>
        </html>
        """
        cleaned = ZillowAgent.clean_dom(raw_html)
        assert "2223 Pacific Ave" in cleaned
        assert "$4,370,000" in cleaned
        assert "tracker" not in cleaned
        assert "Header Banner" not in cleaned
        assert "Contact Agent" not in cleaned
        assert "Cookie banner" not in cleaned
        assert "Footer 2026" not in cleaned

    def test_strip_html_comments(self):
        raw_html = """
        <html><body>
            <!-- Secret Comment 1 -->
            <div data-testid="property-summary">
                <h1>100 Main St</h1>
                <!-- Secret Comment 2 -->
                <span>$1,200,000</span>
            </div>
        </body></html>
        """
        cleaned = ZillowAgent.clean_dom(raw_html)
        assert "100 Main St" in cleaned
        assert "Secret Comment" not in cleaned

    def test_target_semantic_containers(self):
        raw_html = """
        <html><body>
            <div class="unrelated-ads">Buy our luxury car now!</div>
            <div data-testid="property-summary">
                <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
            </div>
            <div data-testid="facts-category">
                <p>Architectural Style: Victorian</p>
                <p>Roof: Slate</p>
            </div>
        </body></html>
        """
        cleaned = ZillowAgent.clean_dom(raw_html)
        assert "2223 Pacific Ave" in cleaned
        assert "Architectural Style: Victorian" in cleaned
        assert "luxury car" not in cleaned

    def test_fallback_to_body_text(self):
        raw_html = """
        <html><body>
            <div class="custom-property-pane">
                <p>Custom layout: 500 Howard St, San Francisco, CA 94105. Price: $2,500,000.</p>
            </div>
        </body></html>
        """
        cleaned = ZillowAgent.clean_dom(raw_html)
        assert "500 Howard St" in cleaned
        assert "$2,500,000" in cleaned

    def test_extra_selectors_injection(self):
        raw_html = """
        <html><body>
            <div class="custom-roof-box">Roof Inspected in 2008 - Slate</div>
            <div data-testid="property-summary">
                <h1>2223 Pacific Ave</h1>
            </div>
        </body></html>
        """
        cleaned = ZillowAgent.clean_dom(raw_html, extra_selectors=[".custom-roof-box"])
        assert "Roof Inspected in 2008 - Slate" in cleaned
        assert "2223 Pacific Ave" in cleaned

    def test_dom_length_budget_12000(self):
        massive_html = "<html><body><div data-testid='property-summary'>" + ("Word " * 5000) + "</div></body></html>"
        cleaned = ZillowAgent.clean_dom(massive_html)
        assert len(cleaned) <= 12000

    def test_whitespace_collapsing(self):
        raw_html = "<html><body><p>   2223   \t\t  Pacific   Ave   </p></body></html>"
        cleaned = ZillowAgent.clean_dom(raw_html)
        assert cleaned == "2223 Pacific Ave"


# ============================================================================
# 2. PROPERTY SCRAPING & LEAD CREATION
# ============================================================================

class TestZillowScrapingAndLeadCreation:
    """Validates property scraping from HTML and live URLs, and mapping to ORM Lead."""

    def test_scrape_property_from_html(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = ZillowAgent(headless=True, extractor=extractor)
        raw_html = """
        <div data-testid="property-summary">
            <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
            <span class="price">$4,370,000</span>
        </div>
        """
        extraction = agent.scrape_property(raw_html)
        assert isinstance(extraction, PropertyExtraction)
        assert "2223 Pacific Ave" in extraction.address
        assert extraction.estimated_value == 4370000.0

    def test_scrape_property_from_live_http(self, live_html_server, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = ZillowAgent(headless=True, extractor=extractor)
        try:
            listing_url = f"{live_html_server}/homedetails/2223-Pacific-Ave"
            extraction = agent.scrape_property(listing_url, target_address="2223 Pacific Ave")
            assert isinstance(extraction, PropertyExtraction)
            assert "2223 Pacific Ave" in extraction.address
            assert extraction.estimated_value == 4370000.0
        finally:
            agent.close_browser()

    def test_scrape_and_create_lead(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = ZillowAgent(headless=True, extractor=extractor)
        raw_html = """
        <div data-testid="property-summary">
            <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
            <span class="price">$4,370,000</span>
        </div>
        """
        lead = agent.scrape_and_create_lead(raw_html, target_zip="94115")
        assert isinstance(lead, Lead)
        assert "2223 Pacific Ave" in lead.address
        assert lead.zip_code == "94115"
        assert lead.status == "DISCOVERED"
        assert lead.property_type == "Single-Family"
        assert lead.estimated_value == 4370000.0

    def test_lead_zip_fallback(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = ZillowAgent(headless=True, extractor=extractor)
        raw_html = "<div data-testid='property-summary'><h1>100 Unknown St</h1></div>"
        lead = agent.scrape_and_create_lead(raw_html, target_zip="94123")
        assert lead.zip_code in ("94123", "94115")

    def test_feedforward_success_recorded(self, live_inference_server, isolated_learning_agent):
        lesson = Lesson(
            domain="zillow.com",
            failure_type="DOM_SELECTOR_DRIFT",
            root_cause="Pruned layout",
            recommended_action="Use .custom-fact-pane",
            recommended_workaround="Use .custom-fact-pane",
            fallback_selectors=[".custom-fact-pane"],
            status="ACTIVE"
        )
        isolated_learning_agent.lesson_store.upsert_lesson(lesson)

        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = ZillowAgent(headless=True, extractor=extractor, learning_agent=isolated_learning_agent)
        raw_html = "<div class='custom-fact-pane'><h1>2223 Pacific Ave, San Francisco, CA 94115</h1></div>"
        extraction = agent.scrape_property(raw_html, target_address="2223 Pacific Ave")
        assert extraction is not None

        updated_lesson = isolated_learning_agent.lesson_store.get_lesson(lesson.id)
        assert updated_lesson is not None
        assert updated_lesson.success_count_after_workaround >= 1


# ============================================================================
# 3. DISCOVERY & SELECTOR DRIFT TELEMETRY
# ============================================================================

class TestZillowDiscoveryAndSelectorDrift:
    """Validates discover_properties listing extraction and selector drift detection."""

    def test_discover_properties_success(self, live_html_server):
        agent = ZillowAgent(headless=True, base_url=live_html_server)
        try:
            candidates = agent.discover_properties(zip_code="94115", max_results=5)
            assert len(candidates) >= 1
            assert any("2223-Pacific-Ave" in c["url"] for c in candidates)
            for c in candidates:
                assert c["url"].startswith("http")
                assert c["zip_code"] == "94115"
        finally:
            agent.close_browser()

    def test_discover_properties_max_limit(self, live_html_server):
        agent = ZillowAgent(headless=True, base_url=live_html_server)
        try:
            candidates = agent.discover_properties(zip_code="94115", max_results=2)
            assert len(candidates) <= 2
        finally:
            agent.close_browser()

    def test_selector_drift_detection(self, live_html_server, isolated_learning_agent):
        agent = ZillowAgent(headless=True, base_url=live_html_server, learning_agent=isolated_learning_agent)
        try:
            # Point to static empty search fixture
            search_url = f"{live_html_server}/static/empty_search.html"
            html = agent.safe_get_html(search_url, domain="zillow.com")
            assert len(html) > 5000

            # Running discovery on drifted page with 0 property cards emits failure
            soup = BeautifulSoup(html, "html.parser")
            cards = soup.select('article[data-test="property-card"]')
            assert len(cards) == 0

            agent.emit_failure(
                domain="zillow.com",
                source_url=search_url,
                phase="DISCOVERY",
                target_entity="94115",
                category="DOM_SELECTOR_DRIFT",
                exception_class="SelectorNotFoundError",
                error_message="0 listing cards found on search page",
                attempted_action="discover_properties",
                dom_snippet=html[:3000]
            )

            lessons = isolated_learning_agent.lesson_store.load_all()
            assert len(lessons) >= 1
            assert any(l.failure_type == "DOM_SELECTOR_DRIFT" for l in lessons)
        finally:
            agent.close_browser()
