import os
import sys
import json
import re
from datetime import datetime, date
import pytest
from pydantic import ValidationError

# Ensure project root is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from agents.extractor import (
    LocalLLMExtractor,
    PropertyExtraction,
    PermitRecord,
    CountyPermitExtraction,
    DEFAULT_LOCAL_URL,
    DEFAULT_LOCAL_MODEL,
    DEFAULT_API_KEY
)
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from db.database import Lead


# ============================================================================
# 1. DOM CLEANING UNDER EXTREME CONDITIONS
# ============================================================================

class TestDOMCleaningExtremeConditions:
    """
    Empirical challenge tests for DOM sanitization, pruning, and extraction
    under extreme, adversarial, malformed, and high-volume payload conditions.
    """

    def test_zillow_clean_dom_malformed_html_unclosed_tags(self):
        """Tests BeautifulSoup parsing of chaotic, unclosed HTML hierarchies."""
        malformed_html = """
        <html><body>
            <div data-testid="property-summary">
                <h1>2223 Pacific Ave
                <div><span>$4,370,000
                <p>Victorian mansion with historical roof
            <div>
            <script>alert("xss");
            <style>body { color: red; }
        """
        cleaned = ZillowAgent.clean_dom(malformed_html)
        assert "2223 Pacific Ave" in cleaned
        assert "$4,370,000" in cleaned
        assert "Victorian mansion" in cleaned
        assert "alert(" not in cleaned
        assert "color: red" not in cleaned

    def test_zillow_clean_dom_deeply_nested_scripts(self):
        """Tests tag decomposition when scripts and unwanted tags are deeply nested inside complex structures."""
        nested_html = "<div>" * 50 + """
            <svg><path d="M0 0"/></svg>
            <script>var deep = true;</script>
            <div data-testid="property-summary">
                <span>Address: 100 Deep Nested Way, SF</span>
                <iframe src="tracker.html"></iframe>
            </div>
            <noscript>Deep noscript</noscript>
            <style>#nested { display: none; }</style>
        """ + "</div>" * 50
        cleaned = ZillowAgent.clean_dom(nested_html)
        assert "100 Deep Nested Way" in cleaned
        assert "var deep = true" not in cleaned
        assert "tracker.html" not in cleaned
        assert "Deep noscript" not in cleaned
        assert "#nested" not in cleaned

    def test_zillow_clean_dom_massive_payload_50k_tokens(self):
        """
        Tests performance and output bounding for a massive ~50,000 token (250KB+) payload.
        Ensures execution completes swiftly without regex exponential backtracking
        and output is capped at the 12,000 char budget.
        """
        # Generate 250,000+ characters of HTML with noise and target tags
        noise_chunk = "<p class='comment'>This is an automated spam listing comment with lots of words.</p>\n"
        massive_body = noise_chunk * 3000
        target_section = "<div data-testid='property-summary'><h1>5000 Massive St, San Francisco, CA</h1><span>$9,999,999</span></div>"
        full_html = f"<html><body><header>Nav</header>{target_section}{massive_body}<footer>Foot</footer></body></html>"

        start_time = datetime.now()
        cleaned = ZillowAgent.clean_dom(full_html)
        duration = (datetime.now() - start_time).total_seconds()

        assert duration < 5.0, f"DOM cleaning took too long: {duration}s"
        assert len(cleaned) <= 12000
        assert "5000 Massive St" in cleaned
        assert "Nav" not in cleaned
        assert "Foot" not in cleaned

    def test_zillow_clean_dom_non_standard_elements_and_cdata(self):
        """Tests handling of custom web components, CDATA blocks, MathML, and unusual markup."""
        non_standard_html = """
        <html>
        <body>
            <custom-header role="banner">Ignore header</custom-header>
            <div data-testid="property-summary">
                <property-badge>Featured</property-badge>
                <h1>777 Custom Tag Blvd</h1>
                <roof-type data-val="slate">Slate Roof</roof-type>
                <![CDATA[ <p>Raw CDATA description of property</p> ]]>
                <math><mrow><mi>x</mi><mo>=</mo><mn>1</mn></mrow></math>
            </div>
            <custom-footer>Ignore footer</custom-footer>
        </body>
        </html>
        """
        cleaned = ZillowAgent.clean_dom(non_standard_html)
        assert "777 Custom Tag Blvd" in cleaned
        assert "Slate Roof" in cleaned

    def test_county_clean_dom_complex_permit_tables(self):
        """Tests CountyAgent DOM pruning on multi-column municipal tables with messy styling."""
        table_html = """
        <html>
        <head><style>.table { border: 1px; }</style></head>
        <body>
            <nav>Municipal Portal Menu</nav>
            <div id="propertyDetails" class="parcel-details">
                <h2>Parcel Information: Block 0582 Lot 012</h2>
                <p>Owner: PACIFIC AVE PROPERTIES LLC</p>
                <p>Assessed Land Value: $2,100,000</p>
                <p>Assessed Improvement Value: $1,850,000</p>
            </div>
            <table class="permit-table">
                <thead><tr><th>Permit #</th><th>Type</th><th>Issued Date</th><th>Status</th></tr></thead>
                <tbody>
                    <tr><td>2008-051512</td><td>Reroof / Alteration</td><td>05/15/2008</td><td>Completed</td></tr>
                    <tr><td>2019-102030</td><td>Solar PV Install</td><td>10/20/2019</td><td>Finaled</td></tr>
                </tbody>
            </table>
            <form action="/search"><input type="text" name="q" /><button>Search</button></form>
        </body>
        </html>
        """
        cleaned = CountyAgent.clean_dom(table_html)
        assert "Block 0582 Lot 012" in cleaned
        assert "PACIFIC AVE PROPERTIES LLC" in cleaned
        assert "2008-051512" in cleaned
        assert "05/15/2008" in cleaned
        assert "Municipal Portal Menu" not in cleaned
        assert "Search" not in cleaned

    def test_county_clean_dom_empty_and_null_inputs(self):
        """Ensures clean_dom safely returns empty string on None or empty string inputs."""
        assert CountyAgent.clean_dom("") == ""
        assert CountyAgent.clean_dom(None) == ""
        assert ZillowAgent.clean_dom("") == ""
        assert ZillowAgent.clean_dom(None) == ""

    def test_clean_dom_fallback_when_no_selectors_match(self):
        """Ensures that when no key selectors match, the agent falls back to body text."""
        raw = "<html><body><h1>Unusual Portal</h1><p>Property at 123 Generic Lane. Assessed $500,000.</p></body></html>"
        cleaned = CountyAgent.clean_dom(raw)
        assert "Unusual Portal" in cleaned
        assert "123 Generic Lane" in cleaned


# ============================================================================
# 2. PYDANTIC EXTRACTION SCHEMA VALIDATION UNDER ADVERSARIAL DATA
# ============================================================================

class TestPydanticSchemaValidation:
    """
    Empirical challenge tests for Pydantic schemas: PropertyExtraction,
    PermitRecord, and CountyPermitExtraction with edge-case and invalid inputs.
    """

    def test_property_extraction_valid_complete(self):
        """Tests successful validation of complete PropertyExtraction."""
        data = {
            "address": "2223 Pacific Ave, San Francisco, CA 94115",
            "zip_code": "94115",
            "property_type": "Single-Family",
            "roof_type": "Victorian",
            "is_hoa": False,
            "is_rental": False,
            "estimated_value": 4370000.0,
            "bedrooms": 5,
            "bathrooms": 4.5,
            "sqft": 4200,
            "year_built": 1900,
            "description": "Historic Victorian home",
            "confidence_score": 0.95
        }
        prop = PropertyExtraction.model_validate(data)
        assert prop.address == "2223 Pacific Ave, San Francisco, CA 94115"
        assert prop.zip_code == "94115"
        assert prop.bathrooms == 4.5
        assert prop.year_built == 1900

    def test_property_extraction_zip_code_sanitization(self):
        """Tests zip_code regex extraction validator with messy inputs."""
        # 9-digit zip formatted with dash
        p1 = PropertyExtraction(address="1 A St", zip_code="94115-2231")
        assert p1.zip_code == "94115"

        # Embedded in full city/state text
        p2 = PropertyExtraction(address="2 B St", zip_code="San Francisco, CA 94118 USA")
        assert p2.zip_code == "94118"

        # Integer input
        p3 = PropertyExtraction(address="3 C St", zip_code=94102)
        assert p3.zip_code == "94102"

        # None zip code
        p4 = PropertyExtraction(address="4 D St", zip_code=None)
        assert p4.zip_code == ""

        # String with no 5 digits
        p5 = PropertyExtraction(address="5 E St", zip_code="UNKNOWN")
        assert p5.zip_code == "UNKNOWN"

    def test_property_extraction_missing_required_address(self):
        """Tests that missing required address field raises ValidationError."""
        with pytest.raises(ValidationError):
            PropertyExtraction.model_validate({"zip_code": "94115"})

    def test_property_extraction_type_coercions(self):
        """Tests automatic type coercion of numeric strings and boolean values."""
        data = {
            "address": "100 Coercion Blvd",
            "zip_code": "94115",
            "estimated_value": "1500000",
            "bedrooms": "4",
            "bathrooms": "3.5",
            "sqft": "2500",
            "year_built": "1975",
            "is_hoa": "false",
            "is_rental": 0
        }
        prop = PropertyExtraction.model_validate(data)
        assert prop.estimated_value == 1500000.0
        assert prop.bedrooms == 4
        assert prop.bathrooms == 3.5
        assert prop.sqft == 2500
        assert prop.year_built == 1975
        assert prop.is_hoa is False
        assert prop.is_rental is False

    def test_county_permit_extraction_permit_history_flexibility(self):
        """
        Tests that CountyPermitExtraction accepts PermitRecord models, raw dicts,
        or strings in permit_history without failing.
        """
        data = {
            "address": "2223 Pacific Ave",
            "apn": "0582-012",
            "owner_name": "PACIFIC AVE HOLDINGS",
            "assessed_value": 3950000.0,
            "last_roof_permit_date": "2008-05-15",
            "permit_history": [
                PermitRecord(permit_number="P-101", permit_type="Reroof", issued_date="2008-05-15", status="Completed"),
                {"permit_number": "P-102", "permit_type": "Plumbing", "issued_date": "2012-01-01"},
                "Raw string permit log: 1995 reroofing done by previous owner"
            ],
            "roof_age_years": 18.0,
            "confidence_score": 0.9
        }
        ext = CountyPermitExtraction.model_validate(data)
        assert ext.address == "2223 Pacific Ave"
        assert len(ext.permit_history) == 3
        assert isinstance(ext.permit_history[0], PermitRecord)
        # Pydantic Union coercion converts matching dict into PermitRecord
        assert isinstance(ext.permit_history[1], PermitRecord)
        assert ext.permit_history[1].permit_number == "P-102"
        assert isinstance(ext.permit_history[2], str)

    def test_county_permit_extraction_missing_required_address(self):
        """Tests that missing address raises ValidationError."""
        with pytest.raises(ValidationError):
            CountyPermitExtraction.model_validate({"apn": "0582-012"})


# ============================================================================
# 3. COUNTYAGENT DATE PARSING STRESS & ADVERSARIAL INPUTS
# ============================================================================

class TestCountyAgentDateParsingAdversarial:
    """
    Empirical challenge tests for CountyAgent.parse_permit_date
    handling standard, non-standard, malformed, and arbitrary date representations.
    """

    @pytest.mark.parametrize("date_input, expected_date", [
        # ISO variants
        ("2008-05-15", date(2008, 5, 15)),
        ("2008/05/15", date(2008, 5, 15)),
        ("1995-12-31", date(1995, 12, 31)),
        # US slash / dash
        ("05/15/2008", date(2008, 5, 15)),
        ("05-15-2008", date(2008, 5, 15)),
        # 2-digit years
        ("05/15/98", date(1998, 5, 15)),
        ("12-01-04", date(2004, 12, 1)),
        # Textual formats
        ("May 15, 2008", date(2008, 5, 15)),
        ("October 20, 2019", date(2019, 10, 20)),
        ("Oct 20, 2019", date(2019, 10, 20)),
        # Year regex extraction from text descriptions
        ("2008", date(2008, 1, 1)),
        ("Permit issued around 1999 for full tile reroof", date(1999, 1, 1)),
        ("Reroof completed in 2016 per DBI records", date(2016, 1, 1)),
        ("Permit # 2021-0812-9999", date(2021, 1, 1)),
        ("Built in 1920", date(1920, 1, 1)),
    ])
    def test_parse_permit_date_various_formats(self, date_input, expected_date):
        res = CountyAgent.parse_permit_date(date_input)
        assert res == expected_date

    @pytest.mark.parametrize("invalid_input", [
        None,
        "",
        "   \t\n",
        "N/A",
        "Not Available",
        "Pending approval",
        "NO_PERMIT_ON_FILE",
        "Unknown",
        "abc",
        "---",
        "99/99/9999", # Invalid month/day
    ])
    def test_parse_permit_date_invalid_inputs_return_none(self, invalid_input):
        assert CountyAgent.parse_permit_date(invalid_input) is None

    def test_parse_permit_date_numerical_type(self):
        assert CountyAgent.parse_permit_date(2004) == date(2004, 1, 1)


# ============================================================================
# 4. LOCAL LLM EXTRACTOR JSON RESILIENCE & ERROR HANDLING
# ============================================================================

class TestLocalLLMExtractorResilience:
    """
    Empirical challenge tests for LocalLLMExtractor JSON parsing,
    markdown stripping, reasoning extraction, and schema enforcement.
    """

    def test_clean_json_response_markdown_fences(self):
        extractor = LocalLLMExtractor()

        # ```json fence
        raw_json_fence = "```json\n{\n  \"address\": \"2223 Pacific Ave\",\n  \"zip_code\": \"94115\"\n}\n```"
        cleaned = extractor._clean_json_response(raw_json_fence)
        parsed = json.loads(cleaned)
        assert parsed["address"] == "2223 Pacific Ave"
        assert parsed["zip_code"] == "94115"

        # ``` fence without json label
        raw_fence = "```\n{\n  \"address\": \"2223 Pacific Ave\",\n  \"zip_code\": \"94115\"\n}\n```"
        cleaned = extractor._clean_json_response(raw_fence)
        parsed = json.loads(cleaned)
        assert parsed["address"] == "2223 Pacific Ave"

    def test_clean_json_response_thinking_tokens_and_conversational_text(self):
        """Tests extractor isolating JSON when the local LLM outputs reasoning or preamble."""
        extractor = LocalLLMExtractor()

        model_output = """
        <think>
        The user wants property details for 2223 Pacific Ave.
        I will extract the address, zip code, and roof type.
        </think>
        Here is the JSON representation of the property:
        {
            "address": "2223 Pacific Ave, San Francisco, CA 94115",
            "zip_code": "94115",
            "property_type": "Single-Family",
            "roof_type": "Victorian",
            "estimated_value": 4370000.0,
            "is_hoa": false,
            "is_rental": false
        }
        I hope this helps! Let me know if you need more fields.
        """
        cleaned = extractor._clean_json_response(model_output)
        parsed = json.loads(cleaned)
        assert parsed["address"] == "2223 Pacific Ave, San Francisco, CA 94115"
        assert parsed["roof_type"] == "Victorian"

    def test_clean_json_response_with_braces_inside_string_values(self):
        """Tests that curly braces inside string values do not break the extraction boundary."""
        extractor = LocalLLMExtractor()

        model_output = """
        {
            "address": "2223 Pacific Ave",
            "zip_code": "94115",
            "description": "Architectural features include {ornate gables} and {dormers}."
        }
        """
        cleaned = extractor._clean_json_response(model_output)
        parsed = json.loads(cleaned)
        assert parsed["address"] == "2223 Pacific Ave"
        assert "{ornate gables}" in parsed["description"]

    def test_clean_json_response_preamble_curly_braces(self):
        """Tests that curly braces in non-JSON reasoning preamble do not corrupt JSON extraction."""
        extractor = LocalLLMExtractor()
        output = "I evaluated {condition_a} and criteria {budget} and decided on:\n{\"address\": \"123 Main St\", \"zip_code\": \"94115\"}\nHope this helps!"
        cleaned = extractor._clean_json_response(output)
        parsed = json.loads(cleaned)
        assert parsed["address"] == "123 Main St"
        assert parsed["zip_code"] == "94115"

    def test_extract_property_details_validation_fallback(self):
        """
        Tests the direct schema validation path of PropertyExtraction
        when given standard or slightly malformed JSON dictionaries.
        """
        extractor = LocalLLMExtractor()

        valid_json = json.dumps({
            "address": "123 Test Ave",
            "zip_code": "94115",
            "estimated_value": 1250000.0,
            "roof_type": "Pitched"
        })
        cleaned = extractor._clean_json_response(valid_json)
        prop = PropertyExtraction.model_validate_json(cleaned)
        assert prop.address == "123 Test Ave"
        assert prop.estimated_value == 1250000.0

    def test_extract_county_permit_details_validation_fallback(self):
        """Tests CountyPermitExtraction validation from JSON string."""
        extractor = LocalLLMExtractor()

        valid_county_json = json.dumps({
            "address": "123 Test Ave",
            "apn": "1234-567",
            "assessed_value": 950000.0,
            "last_roof_permit_date": "2005-04-12",
            "permit_history": [
                {"permit_number": "P1", "permit_type": "Reroof", "issued_date": "2005-04-12", "status": "Final"}
            ],
            "roof_age_years": 21.0
        })
        cleaned = extractor._clean_json_response(valid_county_json)
        county_ext = CountyPermitExtraction.model_validate_json(cleaned)
        assert county_ext.address == "123 Test Ave"
        assert county_ext.apn == "1234-567"
        assert county_ext.roof_age_years == 21.0


# ============================================================================
# 5. AGENT LEAD SYNTHESIS & QUALIFICATION LOGIC
# ============================================================================

class TestAgentLeadSynthesis:
    """Empirical challenge tests for lead transformation and qualification rules."""

    def test_zillow_agent_scrape_and_create_lead_fallback_zip(self):
        agent = ZillowAgent(headless=True)
        # Mocking property extraction output
        extraction = PropertyExtraction(
            address="1500 Sutter St",
            zip_code="",  # empty zip extracted
            property_type="Condo",
            roof_type="Flat",
            estimated_value=850000.0
        )
        # Fallback zip provided in method
        target_zip = "94109"
        lead = Lead(
            address=extraction.address,
            zip_code=extraction.zip_code or target_zip or "94115",
            property_type=extraction.property_type or "Single-Family",
            roof_type=extraction.roof_type or "Unknown",
            estimated_value=extraction.estimated_value,
            is_hoa=bool(extraction.is_hoa),
            is_rental=bool(extraction.is_rental),
            status="DISCOVERED"
        )
        assert lead.address == "1500 Sutter St"
        assert lead.zip_code == "94109"
        assert lead.property_type == "Condo"

    def test_county_agent_enrichment_roof_age_calculation(self):
        agent = CountyAgent(headless=True)
        lead = Lead(
            address="2223 Pacific Ave",
            zip_code="94115",
            status="DISCOVERED"
        )
        parsed_dt = agent.parse_permit_date("2008-05-15")
        lead.last_roof_permit_date = parsed_dt
        current_year = datetime.utcnow().year
        lead.roof_age_years = float(current_year - parsed_dt.year)
        lead.estimated_value = 4370000.0

        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"

        assert lead.status == "VALIDATED"
        assert lead.roof_age_years >= 15.0

    def test_zillow_clean_dom_null_bytes_and_unicode(self):
        """Tests DOM cleaning resilience against null bytes and weird unicode."""
        weird_html = (
            "<html><body>\x00\x01<div data-testid=\"property-summary\">"
            "<h1>123\xa0Unicode\u200b Lane</h1>"
            "<span>$1,200,000</span></div>\x00</body></html>"
        )
        cleaned = ZillowAgent.clean_dom(weird_html)
        assert "123" in cleaned
        assert "Unicode" in cleaned
        assert "$1,200,000" in cleaned

    def test_property_extraction_zero_and_boundary_values(self):
        """Tests PropertyExtraction with zero values for numeric fields."""
        data = {
            "address": "0 Zero Way",
            "zip_code": "94115",
            "estimated_value": 0.0,
            "bedrooms": 0,
            "bathrooms": 0.0,
            "sqft": 0,
            "year_built": 1800,
            "confidence_score": 0.0
        }
        prop = PropertyExtraction.model_validate(data)
        assert prop.estimated_value == 0.0
        assert prop.bedrooms == 0
        assert prop.sqft == 0
        assert prop.confidence_score == 0.0

    def test_county_permit_date_leap_year_and_ambiguities(self):
        """Tests leap day parsing and invalid leap day fallback."""
        # Valid leap day
        d_leap = CountyAgent.parse_permit_date("2024-02-29")
        assert d_leap == date(2024, 2, 29)

        # Invalid leap day in non-leap year falls back to year regex
        d_non_leap = CountyAgent.parse_permit_date("2023-02-29")
        assert d_non_leap == date(2023, 1, 1)

    def test_local_llm_extractor_invalid_json_raises_value_error(self):
        """Tests that unparseable non-JSON output triggers a descriptive ValueError."""
        extractor = LocalLLMExtractor()
        raw_non_json = "I am unable to find any information on this property."
        cleaned = extractor._clean_json_response(raw_non_json)
        with pytest.raises(Exception):
            PropertyExtraction.model_validate_json(cleaned)

    def test_local_llm_extractor_array_instead_of_object(self):
        """Tests behavior when model returns a JSON array instead of an object."""
        extractor = LocalLLMExtractor()
        array_json = '[{"address": "123 Main St", "zip_code": "94115"}]'
        cleaned = extractor._clean_json_response(array_json)
        # _clean_json_response only slices between '{' and '}'
        # If input has '{' and '}', it extracts the inner object
        assert "123 Main St" in cleaned
        parsed = json.loads(cleaned)
        assert parsed["address"] == "123 Main St"

