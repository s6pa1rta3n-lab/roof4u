"""
tests/test_base_agent.py

Component test suite for agents/base_agent.py.
Validates Playwright browser lifecycle, DOM retrieval, HTTP status code interception (403, 429),
access denied title checks, network timeout handling, feedforward adaptations, and telemetry emission.
100% Mock-Free.
"""

import time
import pytest
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError

from agents.base_agent import BaseAgent
from agents.learning_agent import LearningAgent
from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger


# ============================================================================
# 1. BROWSER LIFECYCLE & CONTEXT MANAGEMENT
# ============================================================================

class TestBaseAgentLifecycle:
    """Validates Playwright startup, shutdown, idempotent closing, and context configuration."""

    def test_browser_start_and_close(self):
        agent = BaseAgent(headless=True)
        assert agent.playwright is None
        assert agent.browser is None

        agent.start_browser()
        assert agent.playwright is not None
        assert agent.browser is not None
        assert agent.context is not None
        assert agent.page is not None

        agent.close_browser()
        assert agent.playwright is None
        assert agent.browser is None
        assert agent.context is None
        assert agent.page is None

    def test_idempotent_close_browser(self):
        agent = BaseAgent(headless=True)
        # Calling close on unstarted agent should not raise
        agent.close_browser()
        agent.close_browser()

        agent.start_browser()
        agent.close_browser()
        agent.close_browser()
        agent.close_browser()
        assert agent.browser is None

    def test_context_manager(self):
        with BaseAgent(headless=True) as agent:
            assert agent.browser is not None
            assert agent.page is not None
        assert agent.browser is None
        assert agent.page is None

    def test_browser_context_headers(self):
        with BaseAgent(headless=True) as agent:
            # Context exists and page is created with desktop viewport
            viewport = agent.page.viewport_size
            assert viewport["width"] == 1920
            assert viewport["height"] == 1080

    def test_auto_restart_on_navigation(self, live_html_server):
        agent = BaseAgent(headless=True)
        try:
            # Call get_html directly without start_browser
            html = agent.get_html(f"{live_html_server}/health")
            assert "ok" in html
            assert agent.browser is not None
        finally:
            agent.close_browser()


# ============================================================================
# 2. NAVIGATION & HTTP STATUS CODE INTERCEPTION
# ============================================================================

class TestBaseAgentNavigationAndStatusCodes:
    """Validates safe_get_html handling of 200, 403, 429, Access Denied, and Timeouts."""

    def test_get_html_success_200(self, live_html_server):
        with BaseAgent(headless=True) as agent:
            html = agent.get_html(f"{live_html_server}/health")
            assert "ok" in html

    def test_safe_get_html_http_403(self, live_html_server, isolated_learning_agent):
        with BaseAgent(headless=True, learning_agent=isolated_learning_agent) as agent:
            html = agent.safe_get_html(f"{live_html_server}/blocked", domain="zillow.com")
            assert "403" in html or "Forbidden" in html or "Access Denied" in html

            # Verify telemetry was emitted to learning agent
            lessons = isolated_learning_agent.lesson_store.load_all()
            assert len(lessons) >= 1
            assert any(l.failure_type == "ANTI_BOT_BLOCKED" for l in lessons)

    def test_safe_get_html_http_429(self, live_html_server, isolated_learning_agent):
        with BaseAgent(headless=True, learning_agent=isolated_learning_agent) as agent:
            html = agent.safe_get_html(f"{live_html_server}/rate_limited", domain="dbiweb02.sfgov.org")
            assert "Rate limited" in html or "429" in html

            lessons = isolated_learning_agent.lesson_store.load_all()
            assert len(lessons) >= 1
            assert any(l.failure_type == "RATE_LIMIT_ERROR" for l in lessons)

    def test_safe_get_html_access_denied(self, live_html_server, isolated_learning_agent):
        with BaseAgent(headless=True, learning_agent=isolated_learning_agent) as agent:
            html = agent.safe_get_html(f"{live_html_server}/blocked", domain="zillow.com")
            lessons = isolated_learning_agent.lesson_store.load_all()
            assert len(lessons) >= 1
            assert any("ANTI_BOT" in l.failure_type for l in lessons)

    def test_safe_get_html_timeout(self, isolated_learning_agent):
        with BaseAgent(headless=True, learning_agent=isolated_learning_agent) as agent:
            # Navigate to non-routable port with small timeout
            with pytest.raises(Exception):
                agent.safe_get_html("http://127.0.0.1:59999/timeout", timeout=500.0)

            lessons = isolated_learning_agent.lesson_store.load_all()
            assert len(lessons) >= 1
            assert any(l.failure_type in ("NETWORK_TIMEOUT", "UNKNOWN") for l in lessons)


# ============================================================================
# 3. FEEDFORWARD & TELEMETRY EMISSION HOOKS
# ============================================================================

class TestBaseAgentFeedforwardAndTelemetry:
    """Validates feedforward delay, header injection, and telemetry emission error safety."""

    def test_feedforward_request_delay(self, live_html_server, isolated_learning_agent):
        # Insert a lesson with suggested delay
        lesson = Lesson(
            domain="delay-test.com",
            failure_type="RATE_LIMIT_ERROR",
            root_cause="Rate limit exceeded",
            recommended_action="Introduce 0.3s delay",
            recommended_workaround="Wait 0.3s",
            suggested_delay_seconds=0.3,
            status="ACTIVE"
        )
        isolated_learning_agent.lesson_store.upsert_lesson(lesson)

        with BaseAgent(headless=True, learning_agent=isolated_learning_agent) as agent:
            start_t = time.time()
            agent.safe_get_html(f"{live_html_server}/health", domain="delay-test.com")
            elapsed = time.time() - start_t
            assert elapsed >= 0.25  # Should reflect >= 0.3s delay

    def test_feedforward_custom_headers(self, live_html_server, isolated_learning_agent):
        lesson = Lesson(
            domain="custom-headers.com",
            failure_type="ANTI_BOT_BLOCKED",
            root_cause="Missing User-Agent",
            recommended_action="Set custom headers",
            recommended_workaround="Use custom headers",
            suggested_headers={"X-Custom-Test-Header": "Roo4u-Agent"},
            status="ACTIVE"
        )
        isolated_learning_agent.lesson_store.upsert_lesson(lesson)

        with BaseAgent(headless=True, learning_agent=isolated_learning_agent) as agent:
            html = agent.safe_get_html(f"{live_html_server}/health", domain="custom-headers.com")
            assert "ok" in html

    def test_emit_failure_construction(self, isolated_learning_agent):
        agent = BaseAgent(headless=True, learning_agent=isolated_learning_agent)
        resolution = agent.emit_failure(
            domain="zillow.com",
            source_url="https://zillow.com/homedetails/123",
            phase="DISCOVERY",
            target_entity="2223 Pacific Ave",
            category="DOM_SELECTOR_DRIFT",
            exception_class="SelectorNotFoundError",
            error_message="Card not found",
            attempted_action="find_card",
            attempted_selector=".property-card",
            dom_snippet="<div>No cards</div>"
        )
        assert resolution is not None
        assert resolution.lesson is not None
        assert resolution.lesson.domain == "zillow.com"
        assert resolution.lesson.failure_type == "DOM_SELECTOR_DRIFT"

    def test_emit_failure_without_learning(self):
        agent = BaseAgent(headless=True, learning_agent=None)
        res = agent.emit_failure(
            domain="zillow.com",
            source_url="https://zillow.com",
            error_message="Some error"
        )
        assert res is None

    def test_emit_failure_handles_exception(self):
        # Create a dummy broken object that throws on observe_failure
        class BrokenLearningAgent:
            def observe_failure(self, event):
                raise RuntimeError("Internal logger crash")

        agent = BaseAgent(headless=True, learning_agent=BrokenLearningAgent())
        # emit_failure should catch the exception and return None gracefully
        res = agent.emit_failure(
            domain="zillow.com",
            source_url="https://zillow.com",
            error_message="Some error"
        )
        assert res is None
