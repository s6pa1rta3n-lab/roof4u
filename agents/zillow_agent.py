"""
agents/zillow_agent.py

Browsing agent specialized in real estate discovery (e.g. Zillow listings).
Inherits from BaseAgent for Playwright browser automation, uses BeautifulSoup
for DOM pruning, and routes extraction to the local LLM with self-healing feedback hooks.
"""

import os
import re
import traceback
from typing import Optional, List, Dict, Any, Union
from bs4 import BeautifulSoup, Comment
from agents.base_agent import BaseAgent
from agents.extractor import LocalLLMExtractor, PropertyExtraction, LLMExtractor
from db.database import Lead


class ZillowAgent(BaseAgent):
    """
    Browsing agent specialized in real estate discovery (e.g. Zillow listings).
    Inherits from BaseAgent for Playwright browser automation, uses BeautifulSoup
    for DOM pruning, and routes extraction to the local LLM.
    """
    def __init__(
        self,
        headless: bool = True,
        extractor: Optional[LocalLLMExtractor] = None,
        base_url: Optional[str] = None,
        learning_agent: Optional[Any] = None
    ):
        super().__init__(headless=headless, learning_agent=learning_agent)
        self.extractor = extractor or LocalLLMExtractor()
        self.base_url = base_url or os.getenv("ZILLOW_BASE_URL", "https://www.zillow.com")

    @staticmethod
    def clean_dom(html_content: str, extra_selectors: Optional[List[str]] = None) -> str:
        """
        Strips noisy HTML elements (scripts, styles, SVGs, iframes, nav, footer, etc.)
        and extracts key property sections (price, home facts, roof, features, description)
        to minimize token load for the local model. Supports dynamic feedforward selector injection.
        """
        if not html_content:
            return ""

        soup = BeautifulSoup(html_content, "html.parser")

        # 1. Remove comments
        for comment in soup.find_all(string=lambda text: isinstance(text, Comment)):
            comment.extract()

        # 2. Decompose script, style, SVG, media, and navigation tags
        unwanted_tags = [
            "script", "style", "svg", "noscript", "iframe", "nav",
            "footer", "header", "button", "input", "form", "aside",
            "picture", "source", "meta", "link", "canvas"
        ]
        for tag in soup.find_all(unwanted_tags):
            tag.decompose()

        # 3. Target high-value semantic containers if present
        key_selectors = [
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

        if extra_selectors:
            key_selectors = list(dict.fromkeys(extra_selectors + key_selectors))

        extracted_sections = []
        for selector in key_selectors:
            try:
                elements = soup.select(selector)
                for elem in elements:
                    extracted_sections.append(elem.get_text(separator=" ", strip=True))
            except Exception:
                pass

        if extracted_sections:
            combined_text = "\n".join(extracted_sections)
        else:
            # Fallback to entire body text
            body = soup.find("body") or soup
            combined_text = body.get_text(separator=" ", strip=True)

        # 4. Collapse whitespace
        cleaned = re.sub(r"[ \t]+", " ", combined_text)
        cleaned = re.sub(r"\n\s*\n+", "\n", cleaned).strip()

        # Limit to 12000 characters to stay within local LLM prompt budget
        return cleaned[:12000]

    def scrape_property(self, url_or_html: str, target_address: str = "") -> PropertyExtraction:
        """
        Navigates to a property listing URL (or accepts raw HTML), preprocesses the DOM,
        and uses LocalLLMExtractor to return structured property data with adaptive self-healing.
        """
        domain = "zillow.com"
        source_url = url_or_html if (isinstance(url_or_html, str) and url_or_html.startswith("http")) else f"https://{domain}/property"

        feedforward = None
        if self.learning_agent:
            try:
                feedforward = self.learning_agent.get_feedforward_strategy(domain, "extract property details")
            except Exception:
                pass

        if isinstance(url_or_html, str) and (url_or_html.startswith("http://") or url_or_html.startswith("https://")):
            html = self.safe_get_html(url_or_html, domain=domain, phase="DISCOVERY", target_entity=target_address)
        else:
            html = str(url_or_html)

        extra_sel = feedforward.fallback_selectors if feedforward else None
        cleaned = self.clean_dom(html, extra_selectors=extra_sel)

        try:
            extraction = self.extractor.extract_property_details(cleaned)
            # Record success if feedforward was applied
            if self.learning_agent and feedforward and feedforward.applicable_lessons:
                for l in feedforward.applicable_lessons:
                    try:
                        self.learning_agent.observe_success(domain, target_address or extraction.address, l.id)
                    except Exception:
                        pass
            return extraction
        except Exception as exc:
            # Emit failure telemetry
            resolution = self.emit_failure(
                domain=domain,
                source_url=source_url,
                phase="EXTRACTION",
                target_entity=target_address,
                category="SCHEMA_VALIDATION_ERROR" if isinstance(exc, ValueError) else "EXTRACTION_PARSE_ERROR",
                exception_class=exc.__class__.__name__,
                error_message=str(exc),
                attempted_action="extract_property_details",
                dom_snippet=cleaned[:3000],
                stack_trace=traceback.format_exc()
            )

            # Adaptive retry if suggested by learning agent
            if resolution and resolution.retry_recommended:
                try:
                    soup = BeautifulSoup(html, "html.parser")
                    raw_body = (soup.find("body") or soup).get_text(separator=" ", strip=True)[:10000]
                    retry_extraction = self.extractor.extract_property_details(raw_body)
                    if self.learning_agent and resolution.lesson:
                        self.learning_agent.observe_success(domain, target_address or retry_extraction.address, resolution.lesson.id)
                    return retry_extraction
                except Exception:
                    pass

            raise exc

    def scrape_and_create_lead(self, url_or_html: str, target_zip: Optional[str] = None) -> Lead:
        """
        Scrapes a property listing and maps the extracted attributes into an ORM Lead object.
        """
        extraction = self.scrape_property(url_or_html)
        zip_code = extraction.zip_code or target_zip or "94115"

        lead = Lead(
            address=extraction.address,
            zip_code=zip_code,
            property_type=extraction.property_type or "Single-Family",
            roof_type=extraction.roof_type or "Unknown",
            estimated_value=extraction.estimated_value,
            is_hoa=bool(extraction.is_hoa),
            is_rental=bool(extraction.is_rental),
            status="DISCOVERED"
        )
        return lead

    def discover_properties(self, zip_code: str, max_results: int = 10) -> List[Dict[str, Any]]:
        """
        Searches for listings in a target zip code and extracts candidate property links/summaries.
        """
        search_url = f"{self.base_url.rstrip('/')}/homes/{zip_code}_rb/"
        domain = "zillow.com"
        try:
            if self.learning_agent:
                html = self.safe_get_html(search_url, domain=domain, phase="DISCOVERY", target_entity=zip_code)
            else:
                html = self.get_html(search_url)

            soup = BeautifulSoup(html, "html.parser")

            card_selectors = ['article[data-test="property-card"]', '.list-card', 'a.property-card-link']
            if self.learning_agent:
                try:
                    ff = self.learning_agent.get_feedforward_strategy(domain, f"discovery {zip_code}")
                    if ff.fallback_selectors:
                        card_selectors = list(dict.fromkeys(ff.fallback_selectors + card_selectors))
                except Exception:
                    pass

            cards = []
            for sel in card_selectors:
                try:
                    matched = soup.select(sel)
                    if matched:
                        cards = matched
                        break
                except Exception:
                    pass

            # Detect selector drift anomaly if page is large but 0 cards found
            if not cards and len(html) > 5000:
                self.emit_failure(
                    domain=domain,
                    source_url=search_url,
                    phase="DISCOVERY",
                    target_entity=zip_code,
                    category="DOM_SELECTOR_DRIFT",
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
                category="UNKNOWN",
                exception_class=exc.__class__.__name__,
                error_message=str(exc),
                attempted_action="discover_properties",
                stack_trace=traceback.format_exc()
            )
            return []
