"""
agents/county_agent.py

Browsing agent specialized in municipal county assessor and building permit records
(e.g., SF Planning Information Map PIM and DBI Permit Tracking).
Inherits from BaseAgent for browser control, prunes DOMs with BeautifulSoup,
and extracts structured parcel/permit intelligence using LocalLLMExtractor with self-healing hooks.
"""

import os
import re
import traceback
from typing import Optional, List, Dict, Any, Union
from datetime import datetime, date
from bs4 import BeautifulSoup, Comment
from agents.base_agent import BaseAgent
from agents.extractor import LocalLLMExtractor, CountyPermitExtraction, LLMExtractor
from db.database import Lead


class CountyAgent(BaseAgent):
    """
    Browsing agent specialized in municipal county assessor and building permit records
    (e.g., SF Planning Information Map PIM and DBI Permit Tracking).
    Inherits from BaseAgent for browser control, prunes DOMs with BeautifulSoup,
    and extracts structured parcel/permit intelligence using LocalLLMExtractor.
    """
    def __init__(
        self,
        headless: bool = True,
        extractor: Optional[LocalLLMExtractor] = None,
        pim_base_url: Optional[str] = None,
        dbi_base_url: Optional[str] = None,
        learning_agent: Optional[Any] = None
    ):
        super().__init__(headless=headless, learning_agent=learning_agent)
        self.extractor = extractor or LocalLLMExtractor()
        self.pim_base_url = pim_base_url or os.getenv("SF_PIM_BASE_URL", "https://sfplanninggis.org/pim/")
        self.dbi_base_url = dbi_base_url or os.getenv("SF_DBI_BASE_URL", "https://dbiweb02.sfgov.org/dbipts/")

    @staticmethod
    def clean_dom(html_content: str, extra_selectors: Optional[List[str]] = None) -> str:
        """
        Strips scripts, styles, SVGs, and irrelevant markup from municipal portals,
        focusing on tables, property record details, parcel numbers, and permit grids.
        """
        if not html_content:
            return ""

        soup = BeautifulSoup(html_content, "html.parser")

        # 1. Remove comments
        for comment in soup.find_all(string=lambda text: isinstance(text, Comment)):
            comment.extract()

        # 2. Decompose scripts, styles, svg, and generic wrappers
        unwanted_tags = [
            "script", "style", "svg", "noscript", "iframe", "nav",
            "footer", "header", "button", "input", "form", "aside",
            "meta", "link", "canvas"
        ]
        for tag in soup.find_all(unwanted_tags):
            tag.decompose()

        # 3. Focus on tables, grids, and record containers
        key_selectors = [
            "table", ".permit-table", ".parcel-details", "#propertyDetails",
            ".assessment-info", "#permitList", ".dbi-grid", ".data-table",
            ".property-summary", ".record-content", ".parcel-info"
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
            body = soup.find("body") or soup
            combined_text = body.get_text(separator=" ", strip=True)

        cleaned = re.sub(r"[ \t]+", " ", combined_text)
        cleaned = re.sub(r"\n\s*\n+", "\n", cleaned).strip()

        return cleaned[:12000]

    @staticmethod
    def parse_permit_date(date_str: Optional[Union[str, int, date, datetime]]) -> Optional[date]:
        """Parses a raw permit date string into a datetime.date object with 2-digit and 4-digit year support."""
        if not date_str:
            return None
        if isinstance(date_str, datetime):
            return date_str.date()
        if isinstance(date_str, date):
            return date_str
        s = str(date_str).strip()
        if not s or s.lower() in (
            "n/a", "not available", "unknown", "none", "null", "---",
            "no_permit_on_file", "pending approval", "no permits found",
            "pending", "n/a - historic"
        ):
            return None
        formats = (
            "%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y",
            "%Y/%m/%d", "%y/%m/%d",
            "%m-%d-%Y", "%m-%d-%y",
            "%b %d, %Y", "%B %d, %Y",
            "%b %d, %y", "%B %d, %y",
            "%d-%b-%Y", "%d-%b-%y",
            "%Y.%m.%d", "%y.%m.%d",
        )
        for fmt in formats:
            try:
                return datetime.strptime(s, fmt).date()
            except ValueError:
                pass
        m = re.search(r"\b(19\d\d|20\d\d)\b", s)
        if m:
            year = int(m.group(1))
            return date(year, 1, 1)
        return None

    def lookup_assessor_record(self, address_or_url: str) -> CountyPermitExtraction:
        """
        Retrieves and extracts assessor parcel number (APN), ownership, and assessed value.
        """
        domain = "sfplanninggis.org"
        feedforward = None
        if self.learning_agent:
            try:
                feedforward = self.learning_agent.get_feedforward_strategy(domain, "assessor lookup")
            except Exception:
                pass

        try:
            if address_or_url.startswith("http://") or address_or_url.startswith("https://"):
                html = self.safe_get_html(address_or_url, domain=domain, phase="ASSESSOR", target_entity=address_or_url)
            else:
                if "<" in address_or_url and ">" in address_or_url:
                    html = address_or_url
                else:
                    search_url = f"{self.pim_base_url.rstrip('/')}/?search={address_or_url.replace(' ', '+')}"
                    html = self.safe_get_html(search_url, domain=domain, phase="ASSESSOR", target_entity=address_or_url)

            extra_sel = feedforward.fallback_selectors if feedforward else None
            cleaned = self.clean_dom(html, extra_selectors=extra_sel)
            extraction = self.extractor.extract_county_permit_details(cleaned)

            if self.learning_agent and feedforward and feedforward.applicable_lessons:
                for l in feedforward.applicable_lessons:
                    try:
                        self.learning_agent.observe_success(domain, address_or_url, l.id)
                    except Exception:
                        pass

            return extraction
        except Exception as exc:
            self.emit_failure(
                domain=domain,
                source_url=address_or_url,
                phase="ASSESSOR",
                target_entity=address_or_url,
                category="EXTRACTION_PARSE_ERROR",
                exception_class=exc.__class__.__name__,
                error_message=str(exc),
                attempted_action="lookup_assessor_record",
                stack_trace=traceback.format_exc()
            )
            raise exc

    def lookup_permit_history(self, address_or_url: str) -> CountyPermitExtraction:
        """
        Retrieves and extracts building and roofing permit history from DBI permit portal.
        """
        domain = "dbiweb02.sfgov.org"
        feedforward = None
        if self.learning_agent:
            try:
                feedforward = self.learning_agent.get_feedforward_strategy(domain, "permit history lookup")
            except Exception:
                pass

        try:
            if address_or_url.startswith("http://") or address_or_url.startswith("https://"):
                html = self.safe_get_html(address_or_url, domain=domain, phase="PERMIT", target_entity=address_or_url)
            else:
                if "<" in address_or_url and ">" in address_or_url:
                    html = address_or_url
                else:
                    search_url = f"{self.dbi_base_url.rstrip('/')}/default.aspx?page=Address&Address={address_or_url.replace(' ', '+')}"
                    html = self.safe_get_html(search_url, domain=domain, phase="PERMIT", target_entity=address_or_url)

            extra_sel = feedforward.fallback_selectors if feedforward else None
            cleaned = self.clean_dom(html, extra_selectors=extra_sel)
            extraction = self.extractor.extract_county_permit_details(cleaned)

            if self.learning_agent and feedforward and feedforward.applicable_lessons:
                for l in feedforward.applicable_lessons:
                    try:
                        self.learning_agent.observe_success(domain, address_or_url, l.id)
                    except Exception:
                        pass

            return extraction
        except Exception as exc:
            self.emit_failure(
                domain=domain,
                source_url=address_or_url,
                phase="PERMIT",
                target_entity=address_or_url,
                category="EXTRACTION_PARSE_ERROR",
                exception_class=exc.__class__.__name__,
                error_message=str(exc),
                attempted_action="lookup_permit_history",
                stack_trace=traceback.format_exc()
            )
            raise exc

    def enrich_lead(
        self,
        lead: Lead,
        pim_html_or_url: Optional[str] = None,
        dbi_html_or_url: Optional[str] = None
    ) -> Lead:
        """
        Queries assessor and permit portals for a given Lead and updates its records.
        Calculates roof age and transitions qualified leads to VALIDATED status.
        """
        address_query = lead.address

        # 1. Lookup Assessor Info (PIM)
        pim_target = pim_html_or_url or address_query
        try:
            assessor_info = self.lookup_assessor_record(pim_target)
            if assessor_info.apn:
                lead.apn = assessor_info.apn
            if assessor_info.owner_name:
                lead.owner_name = assessor_info.owner_name
            if assessor_info.assessed_value:
                lead.estimated_value = assessor_info.assessed_value
            if assessor_info.is_hoa is not None:
                lead.is_hoa = bool(assessor_info.is_hoa)
            if assessor_info.is_rental is not None:
                lead.is_rental = bool(assessor_info.is_rental)
        except Exception:
            pass

        # 2. Lookup Permit History (DBI)
        dbi_target = dbi_html_or_url or address_query
        try:
            permit_info = self.lookup_permit_history(dbi_target)
            if permit_info.last_roof_permit_date:
                parsed_dt = self.parse_permit_date(permit_info.last_roof_permit_date)
                if parsed_dt:
                    lead.last_roof_permit_date = parsed_dt
                    current_year = datetime.now().year
                    lead.roof_age_years = float(current_year - parsed_dt.year)
            elif permit_info.roof_age_years is not None:
                lead.roof_age_years = permit_info.roof_age_years

            if permit_info.apn and not lead.apn:
                lead.apn = permit_info.apn
        except Exception:
            pass

        # 3. Qualification rule: roof age >= 15 years or high assessed value
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"

        return lead
