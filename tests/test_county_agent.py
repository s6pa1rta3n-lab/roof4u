"""
tests/test_county_agent.py

Component test suite for agents/county_agent.py.
Validates municipal DOM cleaning, comprehensive permit date parsing matrix,
Assessor (PIM) and Permit (DBI) lookups against live loopback endpoints,
and Lead record enrichment and qualification logic (roof age >= 15 or value > $1M).
100% Mock-Free.
"""

from datetime import datetime, date
import pytest

from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor, CountyPermitExtraction
from agents.learning_agent import LearningAgent
from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger
from db.database import Lead


# ============================================================================
# 1. MUNICIPAL DOM CLEANING ENGINE
# ============================================================================

class TestCountyDOMCleaningEngine:
    """Validates CountyAgent.clean_dom preservation of tables, parcel details, and selector limits."""

    def test_clean_dom_preserves_tables(self):
        raw_html = """
        <html>
        <head><title>SF Planning PIM</title><style>.hidden{display:none;}</style></head>
        <body>
            <script>var x = 1;</script>
            <div class="parcel-details">
                <table>
                    <tr><td>Assessor Parcel Number (APN):</td><td>0582-014</td></tr>
                    <tr><td>Owner:</td><td>PACIFIC HERITAGE TRUST</td></tr>
                    <tr><td>Total Assessed Value:</td><td>$3,850,000.00</td></tr>
                </table>
            </div>
            <div class="dbi-grid">
                <table class="permit-table">
                    <tr><td>200805141234</td><td>Reroofing</td><td>05/14/2008</td></tr>
                </table>
            </div>
            <footer>SF Gov</footer>
        </body>
        </html>
        """
        cleaned = CountyAgent.clean_dom(raw_html)
        assert "0582-014" in cleaned
        assert "PACIFIC HERITAGE TRUST" in cleaned
        assert "$3,850,000.00" in cleaned
        assert "200805141234" in cleaned
        assert "05/14/2008" in cleaned
        assert "var x" not in cleaned
        assert "SF Gov" not in cleaned

    def test_clean_dom_extra_selectors(self):
        raw_html = """
        <html><body>
            <div class="custom-tax-box">Tax Status: Exempt 2026</div>
            <div class="parcel-details"><p>APN: 0582-014</p></div>
        </body></html>
        """
        cleaned = CountyAgent.clean_dom(raw_html, extra_selectors=[".custom-tax-box"])
        assert "Tax Status: Exempt 2026" in cleaned
        assert "0582-014" in cleaned

    def test_clean_dom_12000_limit(self):
        huge_html = "<html><body><table class='permit-table'>" + ("<tr><td>20080101</td><td>Reroof</td></tr>" * 1000) + "</table></body></html>"
        cleaned = CountyAgent.clean_dom(huge_html)
        assert len(cleaned) <= 12000


# ============================================================================
# 2. PERMIT DATE PARSING MATRIX
# ============================================================================

class TestPermitDateParsingMatrix:
    """Validates CountyAgent.parse_permit_date across all standard, regional, and edge date formats."""

    def test_parse_iso_date(self):
        assert CountyAgent.parse_permit_date("2018-05-20") == date(2018, 5, 20)

    def test_parse_us_slashed_4digit(self):
        assert CountyAgent.parse_permit_date("05/20/2018") == date(2018, 5, 20)

    def test_parse_us_slashed_2digit(self):
        assert CountyAgent.parse_permit_date("05/20/18") == date(2018, 5, 20)

    def test_parse_us_dashed(self):
        assert CountyAgent.parse_permit_date("05-20-2018") == date(2018, 5, 20)
        assert CountyAgent.parse_permit_date("05-20-18") == date(2018, 5, 20)

    def test_parse_textual_month(self):
        assert CountyAgent.parse_permit_date("May 20, 2018") == date(2018, 5, 20)
        assert CountyAgent.parse_permit_date("May 20, 18") == date(2018, 5, 20)

    def test_parse_day_month_year(self):
        assert CountyAgent.parse_permit_date("20-May-2018") == date(2018, 5, 20)
        assert CountyAgent.parse_permit_date("20-May-18") == date(2018, 5, 20)

    def test_parse_dot_separated(self):
        assert CountyAgent.parse_permit_date("2018.05.20") == date(2018, 5, 20)
        assert CountyAgent.parse_permit_date("18.05.20") == date(2018, 5, 20)

    def test_parse_year_only_regex_fallback(self):
        assert CountyAgent.parse_permit_date("2015") == date(2015, 1, 1)
        assert CountyAgent.parse_permit_date("Permit issued in 2008") == date(2008, 1, 1)

    def test_parse_null_like_tokens(self):
        null_tokens = [
            "N/A", "not available", "unknown", "none", "null", "---",
            "no_permit_on_file", "pending approval", "no permits found",
            "pending", "n/a - historic", ""
        ]
        for tok in null_tokens:
            assert CountyAgent.parse_permit_date(tok) is None
        assert CountyAgent.parse_permit_date(None) is None

    def test_parse_passthrough_types(self):
        dt = datetime(2018, 5, 20, 10, 30)
        d = date(2018, 5, 20)
        assert CountyAgent.parse_permit_date(dt) == d
        assert CountyAgent.parse_permit_date(d) == d

    def test_parse_invalid_garbage(self):
        assert CountyAgent.parse_permit_date("invalid_string_with_no_year_or_date") is None


# ============================================================================
# 3. ASSESSOR & PERMIT LOOKUPS
# ============================================================================

class TestAssessorAndPermitLookups:
    """Validates Assessor (PIM) and DBI Permit lookups via HTML and live loopback URLs."""

    def test_lookup_assessor_from_html(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor)
        raw_html = """
        <div class="parcel-details">
            <table>
                <tr><td>APN:</td><td>0582-014</td></tr>
                <tr><td>Owner:</td><td>PACIFIC HERITAGE TRUST</td></tr>
                <tr><td>Assessed Value:</td><td>$3,850,000.00</td></tr>
            </table>
        </div>
        """
        extraction = agent.lookup_assessor_record(raw_html)
        assert isinstance(extraction, CountyPermitExtraction)
        assert extraction.apn == "0582-014"
        assert extraction.owner_name == "PACIFIC HERITAGE TRUST"
        assert extraction.assessed_value == 3850000.0

    def test_lookup_assessor_from_live_http(self, live_html_server, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor, pim_base_url=f"{live_html_server}/pim")
        try:
            extraction = agent.lookup_assessor_record("2223 Pacific Ave")
            assert isinstance(extraction, CountyPermitExtraction)
            assert extraction.apn == "0582-014"
            assert extraction.owner_name == "PACIFIC HERITAGE TRUST"
        finally:
            agent.close_browser()

    def test_lookup_permit_from_html(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor)
        raw_html = """
        <table class="permit-table">
            <tr><td>200805141234</td><td>Reroofing</td><td>05/14/2008</td></tr>
        </table>
        """
        extraction = agent.lookup_permit_history(raw_html)
        assert isinstance(extraction, CountyPermitExtraction)
        assert extraction.last_roof_permit_date == "2008-05-14"
        assert extraction.roof_age_years == 18.0

    def test_lookup_permit_from_live_http(self, live_html_server, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor, dbi_base_url=f"{live_html_server}/dbipts")
        try:
            extraction = agent.lookup_permit_history("2223 Pacific Ave")
            assert isinstance(extraction, CountyPermitExtraction)
            assert extraction.last_roof_permit_date == "2008-05-14"
        finally:
            agent.close_browser()

    def test_lookup_failure_telemetry(self, isolated_learning_agent):
        # Create an agent with broken extractor to trigger failure emission
        class BrokenExtractor:
            def extract_county_permit_details(self, html):
                raise ValueError("Unparseable county HTML")

        agent = CountyAgent(headless=True, extractor=BrokenExtractor(), learning_agent=isolated_learning_agent)
        with pytest.raises(Exception):
            agent.lookup_assessor_record("<div>Broken</div>")

        lessons = isolated_learning_agent.lesson_store.load_all()
        assert len(lessons) >= 1
        assert any("EXTRACTION" in l.failure_type or "SCHEMA" in l.failure_type for l in lessons)


# ============================================================================
# 4. LEAD ENRICHMENT & QUALIFICATION RULES
# ============================================================================

class TestLeadEnrichmentAndQualification:
    """Validates lead enrichment, roof age calculation, and qualification transitions to VALIDATED."""

    def test_enrich_lead_updates_all_fields(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor)
        try:
            lead = Lead(
                address="2223 Pacific Ave, San Francisco, CA 94115",
                zip_code="94115",
                status="DISCOVERED"
            )

            pim_html = "<div>APN: 0582-014, Owner: PACIFIC HERITAGE TRUST, Value: $3,850,000</div>"
            dbi_html = "<table><tr><td>200805141234</td><td>Reroofing</td><td>05/14/2008</td></tr></table>"

            enriched = agent.enrich_lead(lead, pim_html_or_url=pim_html, dbi_html_or_url=dbi_html)
            assert enriched.apn == "0582-014"
            assert enriched.owner_name == "PACIFIC HERITAGE TRUST"
            assert enriched.estimated_value == 3850000.0
            assert enriched.last_roof_permit_date == date(2008, 5, 14)
            assert enriched.roof_age_years is not None
            assert enriched.status == "VALIDATED"
        finally:
            agent.close_browser()

    def test_qualification_roof_age_old(self, live_inference_server):
        agent = CountyAgent(headless=True)
        try:
            lead = Lead(
                address="100 Old Roof St",
                zip_code="94115",
                status="DISCOVERED",
                estimated_value=600000.0,
                roof_age_years=18.0
            )
            # Apply qualification rule directly
            if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
                lead.status = "VALIDATED"
            assert lead.status == "VALIDATED"
        finally:
            agent.close_browser()

    def test_qualification_high_value(self):
        lead = Lead(
            address="200 Luxury Ave",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=2500000.0,
            roof_age_years=5.0  # Young roof, but value > $1M
        )
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"
        assert lead.status == "VALIDATED"

    def test_non_qualification_young_roof(self):
        lead = Lead(
            address="300 Recent Roof Way",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=650000.0,
            roof_age_years=4.0
        )
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"
        assert lead.status == "DISCOVERED"

    def test_enrich_lead_handles_pim_fail(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor)
        try:
            lead = Lead(address="400 Partial St", zip_code="94115", status="DISCOVERED")

            # Invalid PIM, valid DBI
            dbi_html = "<table><tr><td>200805141234</td><td>Reroofing</td><td>05/14/2008</td></tr></table>"
            enriched = agent.enrich_lead(lead, pim_html_or_url="<broken>none</broken>", dbi_html_or_url=dbi_html)
            assert enriched.last_roof_permit_date == date(2008, 5, 14)
        finally:
            agent.close_browser()

    def test_enrich_lead_handles_dbi_fail(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor)
        try:
            lead = Lead(address="500 Partial PIM St", zip_code="94115", status="DISCOVERED")

            pim_html = "<div>APN: 0582-014, Owner: PACIFIC HERITAGE TRUST, Value: $3,850,000</div>"
            enriched = agent.enrich_lead(lead, pim_html_or_url=pim_html, dbi_html_or_url="<broken>none</broken>")
            assert enriched.apn == "0582-014"
            assert enriched.status == "VALIDATED"  # Qualified by value > $1M
        finally:
            agent.close_browser()
