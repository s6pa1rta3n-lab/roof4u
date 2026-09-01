import os
from playwright.sync_api import sync_playwright

class BaseAgent:
    """
    Base Agent class that provides a synchronous Playwright browser instance
    for autonomous navigation and scraping.
    """
    def __init__(self, headless=True):
        self.headless = headless
        self.playwright = None
        self.browser = None
        self.context = None
        self.page = None

    def start_browser(self):
        """Initializes the Playwright browser context."""
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
        """Cleans up the Playwright instance."""
        if self.page:
            self.page.close()
        if self.context:
            self.context.close()
        if self.browser:
            self.browser.close()
        if self.playwright:
            self.playwright.stop()

    def get_html(self, url: str) -> str:
        """Navigates to a URL and returns the page HTML."""
        if not self.page:
            self.start_browser()
        
        self.page.goto(url, wait_until="domcontentloaded")
        return self.page.content()

    def __enter__(self):
        self.start_browser()
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close_browser()
