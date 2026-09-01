"""
tests/test_extractor.py

Component test suite for agents/extractor.py.
Validates LocalLLMExtractor, JSON response sanitization (thinking tags, code fences, balanced braces),
Pydantic schema validation & coercion, and live OpenAI-compatible loopback inference over TCP sockets.
100% Mock-Free.
"""

import json
import pytest
from pydantic import ValidationError

from agents.extractor import (
    LocalLLMExtractor,
    PropertyExtraction,
    CountyPermitExtraction,
    PermitRecord,
    LLMExtractor
)


# ============================================================================
# 1. JSON CLEANING & SANITIZATION ENGINE
# ============================================================================

class TestJSONCleaningEngine:
    """Validates _clean_json_response across raw JSON, think tags, markdown fences, and noise."""

    @pytest.fixture
    def extractor(self):
        return LocalLLMExtractor(base_url="http://127.0.0.1:8000/v1")

    def test_clean_raw_json(self, extractor):
        raw = '{"address": "2223 Pacific Ave", "zip_code": "94115"}'
        assert extractor._clean_json_response(raw) == raw

    def test_clean_think_tags(self, extractor):
        raw = '<think>Analyzing DOM and extracting address details...</think>\n{"address": "2223 Pacific Ave", "zip_code": "94115"}'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "2223 Pacific Ave"
        assert "<think>" not in cleaned

    def test_clean_thought_tags(self, extractor):
        raw = '<thought>Deep reasoning step 1</thought>{"address": "100 Main St", "zip_code": "94105"}'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "100 Main St"

    def test_clean_markdown_json_block(self, extractor):
        raw = '```json\n{\n  "address": "500 Howard St",\n  "zip_code": "94105"\n}\n```'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "500 Howard St"

    def test_clean_markdown_generic_block(self, extractor):
        raw = '```\n{"address": "700 Market St", "zip_code": "94103"}\n```'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "700 Market St"

    def test_clean_preamble_with_braces(self, extractor):
        raw = 'Note: The result for {item_id} is: {"address": "123 Preamble Way", "zip_code": "94115"}'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "123 Preamble Way"

    def test_clean_nested_json_braces(self, extractor):
        raw = 'Here is the extraction: {"address": "10 Nested Ct", "features": {"roof": {"type": "Slate"}}} trailing comments'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "10 Nested Ct"
        assert data["features"]["roof"]["type"] == "Slate"

    def test_clean_escaped_strings(self, extractor):
        raw = '{"address": "100 O\'Farrell St", "description": "Victorian with \\"ornate\\" details"}'
        cleaned = extractor._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "100 O'Farrell St"
        assert 'ornate' in data["description"]

    def test_clean_empty_or_none(self, extractor):
        assert extractor._clean_json_response("") == ""
        assert extractor._clean_json_response(None) == ""

    def test_clean_malformed_no_braces(self, extractor):
        raw = "Sorry, I am an AI model and could not parse this page."
        assert extractor._clean_json_response(raw) == raw


# ============================================================================
# 2. PYDANTIC EXTRACTION SCHEMAS & FIELD COERCION
# ============================================================================

class TestPydanticExtractionSchemas:
    """Validates Pydantic model parsing, custom zip validators, defaults, and validation rules."""

    def test_property_extraction_valid(self):
        data = {
            "address": "2223 Pacific Ave, San Francisco, CA 94115",
            "zip_code": "94115",
            "property_type": "Single-Family",
            "roof_type": "Victorian",
            "is_hoa": False,
            "is_rental": False,
            "estimated_value": 4370000.0,
            "bedrooms": 4,
            "bathrooms": 3.5,
            "sqft": 3450,
            "year_built": 1908,
            "description": "Historic Victorian residence",
            "confidence_score": 0.98
        }
        extraction = PropertyExtraction.model_validate(data)
        assert extraction.address == "2223 Pacific Ave, San Francisco, CA 94115"
        assert extraction.zip_code == "94115"
        assert extraction.estimated_value == 4370000.0
        assert extraction.roof_type == "Victorian"

    def test_zip_code_validator_5digit(self):
        ext = PropertyExtraction(address="100 Main St", zip_code="94115")
        assert ext.zip_code == "94115"

    def test_zip_code_validator_extended(self):
        ext = PropertyExtraction(address="100 Main St", zip_code="CA 94115-4321")
        assert ext.zip_code == "94115"

    def test_zip_code_validator_integer(self):
        ext = PropertyExtraction(address="100 Main St", zip_code=94115)
        assert ext.zip_code == "94115"

    def test_zip_code_validator_none(self):
        ext = PropertyExtraction(address="100 Main St", zip_code=None)
        assert ext.zip_code == ""

    def test_property_extraction_defaults(self):
        ext = PropertyExtraction(address="100 Main St", zip_code="94115")
        assert ext.property_type == "Single-Family"
        assert ext.roof_type == "Unknown"
        assert ext.is_hoa is False
        assert ext.is_rental is False
        assert ext.estimated_value is None
        assert ext.confidence_score == 1.0

    def test_county_extraction_valid(self):
        data = {
            "address": "2223 Pacific Ave, San Francisco, CA 94115",
            "apn": "0582-014",
            "owner_name": "PACIFIC HERITAGE TRUST",
            "assessed_value": 3850000.0,
            "last_roof_permit_date": "2008-05-14",
            "permit_history": [
                {
                    "permit_number": "200805141234",
                    "permit_type": "Reroofing",
                    "description": "Slate reroof",
                    "issued_date": "2008-05-14",
                    "status": "Completed"
                }
            ],
            "roof_age_years": 18.0,
            "is_hoa": False,
            "is_rental": False,
            "confidence_score": 0.95
        }
        extraction = CountyPermitExtraction.model_validate(data)
        assert extraction.apn == "0582-014"
        assert extraction.owner_name == "PACIFIC HERITAGE TRUST"
        assert extraction.assessed_value == 3850000.0
        assert len(extraction.permit_history) == 1

    def test_permit_record_parsing(self):
        rec = PermitRecord(
            permit_number="200805141234",
            permit_type="Reroofing",
            description="Complete tear off",
            issued_date="2008-05-14",
            status="Completed"
        )
        assert rec.permit_number == "200805141234"
        assert rec.permit_type == "Reroofing"

    def test_schema_missing_required(self):
        # 'address' is required for both PropertyExtraction and CountyPermitExtraction
        with pytest.raises(ValidationError):
            PropertyExtraction.model_validate({"zip_code": "94115"})

        with pytest.raises(ValidationError):
            CountyPermitExtraction.model_validate({"apn": "0582-014"})


# ============================================================================
# 3. LIVE LOCAL LLM INFERENCE OVER TCP
# ============================================================================

class TestLocalLLMExtractorLiveInference:
    """Validates real network communication against live loopback Starlette server."""

    def test_live_extract_property_details(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        sample_html = """
        <div data-testid="property-summary">
            <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
            <span class="price">$4,370,000</span>
        </div>
        <div data-testid="facts-category">
            <p>Victorian Architecture | Slate Roof | Built 1908 | 4 Beds | 3.5 Baths</p>
        </div>
        """
        extraction = extractor.extract_property_details(sample_html)
        assert isinstance(extraction, PropertyExtraction)
        assert "2223 Pacific Ave" in extraction.address
        assert extraction.estimated_value == 4370000.0
        assert extraction.roof_type == "Victorian"

    def test_live_extract_county_details(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        sample_html = """
        <div class="parcel-details">
            <p>Assessor Parcel Number: 0582-014</p>
            <p>Owner: PACIFIC HERITAGE TRUST</p>
            <p>Total Assessed Value: $3,850,000.00</p>
            <p>Permit 200805141234 - Reroofing completed on 05/14/2008</p>
        </div>
        """
        extraction = extractor.extract_county_permit_details(sample_html)
        assert isinstance(extraction, CountyPermitExtraction)
        assert extraction.apn == "0582-014"
        assert extraction.owner_name == "PACIFIC HERITAGE TRUST"
        assert extraction.assessed_value == 3850000.0
        assert extraction.roof_age_years == 18.0

    def test_live_prompt_clipping_16000(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        huge_payload = "2223 Pacific Ave, San Francisco, CA 94115\n" + ("<div>Extra large content block</div>\n" * 1000)
        assert len(huge_payload) > 20000
        extraction = extractor.extract_property_details(huge_payload)
        assert isinstance(extraction, PropertyExtraction)

    def test_live_server_http_error(self, live_inference_server):
        # Use an invalid model endpoint port to trigger network error
        extractor = LocalLLMExtractor(base_url="http://127.0.0.1:59998/v1", timeout=1.0)
        with pytest.raises(RuntimeError):
            extractor.extract_property_details("2223 Pacific Ave")

    def test_live_server_malformed_json(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        prompt_with_malformed_inject = "[TEST_INJECT: MALFORMED_JSON] 2223 Pacific Ave"
        with pytest.raises((ValueError, RuntimeError)):
            extractor.extract_property_details(prompt_with_malformed_inject)

    def test_live_empty_model_response(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        prompt_with_empty_inject = "[TEST_INJECT: EMPTY_CONTENT] 2223 Pacific Ave"
        with pytest.raises(RuntimeError):
            extractor.extract_property_details(prompt_with_empty_inject)
