"""
agents/base_agent.py

Base Agent class providing a synchronous Playwright browser instance,
safe navigation with feedforward request adaptations, and telemetry emission hooks
for closed-loop learning.
"""

import os
import time
import traceback
from typing import Optional, Any, Dict
from playwright.sync_api import sync_playwright


class BaseAgent:
    """
    Base Agent class that provides a synchronous Playwright browser instance
    for autonomous navigation, scraping, and failure telemetry emission.
    """
    def __init__(self, headless: bool = True, learning_agent: Optional[Any] = None):
        self.headless = headless
        self.learning_agent = learning_agent
        self.playwright = None
        self.browser = None
        self.context = None
        self.page = None

    def start_browser(self):
        """Initializes the Playwright browser context."""
        try:
            import asyncio
            try:
                loop = asyncio.get_event_loop_policy().get_event_loop()
                if loop.is_closed():
                    asyncio.set_event_loop(asyncio.new_event_loop())
            except Exception:
                asyncio.set_event_loop(asyncio.new_event_loop())
        except Exception:
            pass

        self.playwright = sync_playwright().start()
        # Use chromium for default fast scraping
        self.browser = self.playwright.chromium.launch(headless=self.headless)
        
        # Create a realistic context to avoid bot detection
        self.context = self.browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36",
            viewport={"width": 1920, "height": 1080}
        )
        self.page = self.context.new_page()
        
    def close_browser(self):
        """Cleans up the Playwright instance idempotently."""
        try:
            if self.page:
                if not getattr(self.page, "is_closed", lambda: False)():
                    self.page.close()
        except Exception:
            pass
        finally:
            self.page = None

        try:
            if self.context:
                self.context.close()
        except Exception:
            pass
        finally:
            self.context = None

        try:
            if self.browser:
                self.browser.close()
        except Exception:
            pass
        finally:
            self.browser = None

        try:
            if self.playwright:
                self.playwright.stop()
        except Exception:
            pass
        finally:
            self.playwright = None

    def emit_failure(
        self,
        domain: str,
        source_url: str,
        phase: str = "SCRAPING",
        target_entity: str = "",
        category: Any = "UNKNOWN",
        exception_class: str = "Exception",
        error_message: str = "",
        attempted_action: str = "",
        attempted_selector: Optional[str] = None,
        dom_snippet: Optional[str] = None,
        stack_trace: Optional[str] = None,
        retry_count: int = 0
    ) -> Optional[Any]:
        """Constructs ScrapingFailureEvent and forwards to LearningAgent if attached."""
        if not self.learning_agent:
            return None
        try:
            from integrations.github_client import ScrapingFailureEvent
            event = ScrapingFailureEvent(
                domain=domain,
                url=source_url,
                source_url=source_url,
                phase=phase,
                target_entity=target_entity,
                lead_address=target_entity,
                failure_type=str(getattr(category, "value", category)),
                category=category,
                exception_class=exception_class,
                error_message=error_message,
                stack_trace=stack_trace,
                attempted_action=attempted_action,
                selector=attempted_selector,
                attempted_selector=attempted_selector,
                dom_snippet=dom_snippet,
                retry_count=retry_count
            )
            return self.learning_agent.observe_failure(event)
        except Exception:
            return None

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
        Navigates to URL with feedforward adaptations, exception trapping,
        and automatic telemetry emission on failure.
        """
        domain_name = domain or (url.split("/")[2] if "://" in url else "unknown")

        # 1. Apply feedforward directives if LearningAgent is attached
        if self.learning_agent:
            try:
                strategy = self.learning_agent.get_feedforward_strategy(domain_name, f"navigate {url}")
                if strategy.request_delay_seconds > 0:
                    time.sleep(strategy.request_delay_seconds)
                if strategy.custom_headers and self.context:
                    try:
                        self.context.set_extra_http_headers(strategy.custom_headers)
                    except Exception:
                        pass
            except Exception:
                pass

        # 2. Execute Navigation
        try:
            if not self.page or (hasattr(self.page, "is_closed") and self.page.is_closed()):
                self.start_browser()

            response = self.page.goto(url, wait_until=wait_until, timeout=timeout)
            status_code = response.status if response else 200

            if status_code in (403, 429) or (self.page and "access denied" in (self.page.title() or "").lower()):
                cat = "ANTI_BOT_BLOCKED" if status_code == 403 else "RATE_LIMIT_ERROR"
                self.emit_failure(
                    domain=domain_name,
                    source_url=url,
                    phase=phase,
                    target_entity=target_entity,
                    category=cat,
                    exception_class="HttpBlockError",
                    error_message=f"HTTP {status_code} detected on {url}",
                    attempted_action="safe_get_html",
                    dom_snippet=self.page.content()[:3000] if self.page else None
                )

            return self.page.content()
        except Exception as exc:
            dom_snippet = None
            try:
                if self.page:
                    dom_snippet = self.page.content()[:3000]
            except Exception:
                pass

            cat = "NETWORK_TIMEOUT" if "timeout" in str(exc).lower() else "UNKNOWN"
            self.emit_failure(
                domain=domain_name,
                source_url=url,
                phase=phase,
                target_entity=target_entity,
                category=cat,
                exception_class=exc.__class__.__name__,
                error_message=str(exc),
                stack_trace=traceback.format_exc(),
                attempted_action="safe_get_html",
                dom_snippet=dom_snippet
            )
            raise exc

    def get_html(self, url: str) -> str:
        """Navigates to a URL and returns the page HTML."""
        if not self.page or (hasattr(self.page, "is_closed") and self.page.is_closed()):
            self.start_browser()
        
        self.page.goto(url, wait_until="domcontentloaded")
        return self.page.content()

    def __enter__(self):
        self.start_browser()
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close_browser()
