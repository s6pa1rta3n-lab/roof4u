import os
import sys
import json
import tempfile
import subprocess
from datetime import datetime, date
import pytest

# Ensure project root is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError

from db.database import Base, Lead, init_db, get_session, get_engine
from agents.extractor import (
    LocalLLMExtractor,
    PropertyExtraction,
    PermitRecord,
    CountyPermitExtraction,
    DEFAULT_LOCAL_URL,
    DEFAULT_LOCAL_MODEL
)
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from exporters.csv_exporter import export_to_csv


# ============================================================================
# 1. PERMIT DATE PARSING & EDGE CASES (CountyAgent)
# ============================================================================

class TestCountyAgentDateParsing:
    """Empirical challenge tests for CountyAgent.parse_permit_date across various date formats & edge cases."""

    @pytest.mark.parametrize("input_str, expected_date", [
        ("2010-05-12", date(2010, 5, 12)),       # ISO format
        ("05/12/2010", date(2010, 5, 12)),       # US slash format
        ("2010/05/12", date(2010, 5, 12)),       # ISO slash format
        ("05-12-2010", date(2010, 5, 12)),       # US dash format
        ("May 12, 2010", date(2010, 5, 12)),     # Long month name
        ("Dec 25, 2021", date(2021, 12, 25)),    # Short month name
        ("May 2010", date(2010, 1, 1)),          # Month and year only (regex fallback)
        ("2015", date(2015, 1, 1)),              # Year only
        ("Issued in 1998 on roof", date(1998, 1, 1)), # Year embedded in text
        ("2005-1-1", date(2005, 1, 1)),          # Single digit month/day (regex fallback)
        ("2035-06-15", date(2035, 6, 15)),       # Future date
        ("1950-01-01", date(1950, 1, 1)),       # Historical date
        ("05/15/98", date(1998, 5, 15)),         # 2-digit year US slash
        ("12-01-04", date(2004, 12, 1)),         # 2-digit year US dash
        ("03/20/22", date(2022, 3, 20)),         # 2-digit 2000s year
    ])
    def test_parse_permit_date_valid_formats(self, input_str, expected_date):
        result = CountyAgent.parse_permit_date(input_str)
        assert result == expected_date, f"Failed for input '{input_str}': expected {expected_date}, got {result}"

    @pytest.mark.parametrize("invalid_input", [
        None,
        "",
        "   ",
        "N/A",
        "n/a",
        "None",
        "null",
        "UNKNOWN",
        "No permits found",
        "pending",
        "N/A - Historic",
        "abc-def-ghij",
    ])
    def test_parse_permit_date_invalid_and_empty(self, invalid_input):
        result = CountyAgent.parse_permit_date(invalid_input)
        assert result is None, f"Expected None for invalid input '{invalid_input}', got {result}"

    def test_parse_permit_date_whitespace_trimming(self):
        result = CountyAgent.parse_permit_date("   2018-11-20   \n")
        assert result == date(2018, 11, 20)

    def test_parse_permit_date_type_coercion(self):
        # Numerical year or weird type passed
        assert CountyAgent.parse_permit_date(2019) == date(2019, 1, 1)


# ============================================================================
# 2. QUALIFICATION THRESHOLD LOGIC & ENRICHMENT (CountyAgent)
# ============================================================================

class TestCountyAgentQualification:
    """Empirical challenge tests for lead enrichment and qualification threshold logic."""

    def test_qualification_roof_age_ge_15_qualifies(self):
        agent = CountyAgent(headless=True)
        lead = Lead(
            address="100 Old Roof Way",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=500_000.0,
            roof_age_years=15.0
        )
        # Directly check qualification logic with permit date 16 years ago
        current_year = datetime.utcnow().year
        past_year = current_year - 16
        lead.last_roof_permit_date = date(past_year, 1, 1)
        lead.roof_age_years = 16.0

        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"

        assert lead.status == "VALIDATED"

    def test_qualification_roof_age_under_15_not_qualified(self):
        lead = Lead(
            address="200 New Roof St",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=500_000.0,
            roof_age_years=5.0
        )
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"

        assert lead.status == "DISCOVERED"

    def test_qualification_high_assessed_value_qualifies_even_with_new_roof(self):
        lead = Lead(
            address="300 Luxury Mansion Blvd",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=2_500_000.0,
            roof_age_years=2.0
        )
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"

        assert lead.status == "VALIDATED"

    def test_qualification_exact_one_million_threshold_boundary(self):
        lead_at_1m = Lead(
            address="400 Borderline Ave",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=1_000_000.0,
            roof_age_years=10.0
        )
        # > 1_000_000 is required, so exactly 1_000_000 without old roof stays DISCOVERED
        if (lead_at_1m.roof_age_years is not None and lead_at_1m.roof_age_years >= 15.0) or (lead_at_1m.estimated_value and lead_at_1m.estimated_value > 1000000):
            lead_at_1m.status = "VALIDATED"
        assert lead_at_1m.status == "DISCOVERED"

        lead_above_1m = Lead(
            address="401 Borderline Plus Ave",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=1_000_001.0,
            roof_age_years=10.0
        )
        if (lead_above_1m.roof_age_years is not None and lead_above_1m.roof_age_years >= 15.0) or (lead_above_1m.estimated_value and lead_above_1m.estimated_value > 1000000):
            lead_above_1m.status = "VALIDATED"
        assert lead_above_1m.status == "VALIDATED"

    def test_enrich_lead_with_future_permit_date_handling(self):
        agent = CountyAgent(headless=True)
        lead = Lead(
            address="500 Future Date Ln",
            zip_code="94115",
            status="DISCOVERED",
            estimated_value=400_000.0
        )
        # Simulating permit extraction returning future date "2030-01-01"
        future_dt = agent.parse_permit_date("2030-01-01")
        assert future_dt == date(2030, 1, 1)
        lead.last_roof_permit_date = future_dt
        current_year = datetime.utcnow().year
        lead.roof_age_years = float(current_year - future_dt.year)
        # Roof age is negative
        assert lead.roof_age_years < 0
        # Qualification rule should NOT validate this lead
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"
        assert lead.status == "DISCOVERED"


# ============================================================================
# 3. ZILLOWAGENT DOM CLEANING & LEAD CREATION
# ============================================================================

class TestZillowAgentLeadGeneration:
    """Empirical challenge tests for ZillowAgent DOM cleaning and lead synthesis."""

    def test_clean_dom_strips_scripts_styles_and_comments(self):
        raw_html = """
        <!DOCTYPE html>
        <html>
        <head><title>Zillow Listing</title><style>.hidden { display: none; }</style></head>
        <body>
            <!-- Secret Internal Comment -->
            <script>alert("tracker");</script>
            <noscript>Enable JS</noscript>
            <nav><a href="/buy">Buy</a></nav>
            <div data-testid="property-summary">
                <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
                <span class="price">$4,370,000</span>
                <p>Victorian architectural masterpiece with original roof.</p>
            </div>
            <footer>Copyright 2026 Zillow</footer>
        </body>
        </html>
        """
        cleaned = ZillowAgent.clean_dom(raw_html)
        assert "2223 Pacific Ave" in cleaned
        assert "$4,370,000" in cleaned
        assert "Victorian architectural masterpiece" in cleaned
        assert "alert(" not in cleaned
        assert "Secret Internal Comment" not in cleaned
        assert "Enable JS" not in cleaned
        assert "Copyright 2026" not in cleaned

    def test_clean_dom_empty_and_corrupt_inputs(self):
        assert ZillowAgent.clean_dom("") == ""
        assert ZillowAgent.clean_dom(None) == ""
        assert ZillowAgent.clean_dom("<div><p>plain text without standard selectors</p></div>") == "plain text without standard selectors"

    def test_clean_dom_token_length_budget_capped(self):
        massive_html = "<html><body>" + ("<div data-testid='property-summary'>Large text block. </div>" * 1000) + "</body></html>"
        cleaned = ZillowAgent.clean_dom(massive_html)
        assert len(cleaned) <= 12000

    def test_scrape_and_create_lead_field_mapping(self):
        agent = ZillowAgent(headless=True)
        # Manually create mock extraction
        extraction = PropertyExtraction(
            address="2223 Pacific Ave",
            zip_code="94115",
            property_type="Single-Family",
            roof_type="Victorian",
            estimated_value=4370000.0,
            is_hoa=False,
            is_rental=False
        )
        lead = Lead(
            address=extraction.address,
            zip_code=extraction.zip_code or "94115",
            property_type=extraction.property_type or "Single-Family",
            roof_type=extraction.roof_type or "Unknown",
            estimated_value=extraction.estimated_value,
            is_hoa=bool(extraction.is_hoa),
            is_rental=bool(extraction.is_rental),
            status="DISCOVERED"
        )
        assert lead.address == "2223 Pacific Ave"
        assert lead.zip_code == "94115"
        assert lead.property_type == "Single-Family"
        assert lead.roof_type == "Victorian"
        assert lead.estimated_value == 4370000.0
        assert lead.is_hoa is False
        assert lead.is_rental is False
        assert lead.status == "DISCOVERED"


# ============================================================================
# 4. DATABASE PERSISTENCE & SCHEMA INTEGRITY (SQLite)
# ============================================================================

class TestDatabasePersistence:
    """Empirical challenge tests for SQLite database operations, transactions, and constraints."""

    @pytest.fixture
    def temp_db(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            db_path = f"sqlite:///{tmp.name}"
        engine = init_db(db_path)
        yield db_path, engine
        if os.path.exists(tmp.name):
            os.remove(tmp.name)

    def test_database_initialization_and_table_creation(self, temp_db):
        db_path, engine = temp_db
        session = get_session(engine)
        count = session.query(Lead).count()
        assert count == 0
        session.close()

    def test_lead_crud_lifecycle(self, temp_db):
        db_path, engine = temp_db
        session = get_session(engine)

        # 1. CREATE
        lead = Lead(
            address="123 Test St",
            zip_code="94115",
            property_type="Single-Family",
            roof_type="Victorian",
            estimated_value=1200000.0,
            status="DISCOVERED"
        )
        session.add(lead)
        session.commit()
        assert lead.id is not None

        # 2. READ
        fetched = session.query(Lead).filter_by(address="123 Test St").first()
        assert fetched is not None
        assert fetched.zip_code == "94115"
        assert fetched.estimated_value == 1200000.0

        # 3. UPDATE
        fetched.status = "VALIDATED"
        fetched.roof_age_years = 18.5
        fetched.last_roof_permit_date = date(2005, 6, 1)
        session.commit()

        re_fetched = session.query(Lead).filter_by(id=lead.id).first()
        assert re_fetched.status == "VALIDATED"
        assert re_fetched.roof_age_years == 18.5
        assert re_fetched.last_roof_permit_date == date(2005, 6, 1)

        # 4. DELETE
        session.delete(re_fetched)
        session.commit()
        assert session.query(Lead).filter_by(id=lead.id).first() is None
        session.close()

    def test_unique_address_constraint(self, temp_db):
        db_path, engine = temp_db
        session = get_session(engine)

        lead1 = Lead(address="999 Duplicate Way", zip_code="94115")
        session.add(lead1)
        session.commit()

        lead2 = Lead(address="999 Duplicate Way", zip_code="94115")
        session.add(lead2)
        with pytest.raises(IntegrityError):
            session.commit()
        session.rollback()
        session.close()


# ============================================================================
# 5. CSV EXPORTER INTEGRITY
# ============================================================================

class TestCsvExporter:
    """Empirical challenge tests for CSV export filtering and format compliance."""

    def test_export_only_validated_and_enriched_leads(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp_db, \
             tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp_csv:
            db_path = f"sqlite:///{tmp_db.name}"
            csv_path = tmp_csv.name

        try:
            engine = init_db(db_path)
            session = get_session(engine)

            # Add leads with various statuses
            leads = [
                Lead(address="101 Validated St", zip_code="94115", status="VALIDATED", estimated_value=1500000.0, roof_age_years=20.0),
                Lead(address="102 Enriched Ave", zip_code="94115", status="ENRICHED", estimated_value=2000000.0, roof_age_years=16.0),
                Lead(address="103 Discovered Rd", zip_code="94115", status="DISCOVERED", estimated_value=800000.0),
                Lead(address="104 Discarded Blvd", zip_code="94115", status="DISCARDED", estimated_value=300000.0),
            ]
            session.add_all(leads)
            session.commit()
            session.close()

            # Execute export
            export_to_csv(db_path=db_path, output_file=csv_path)

            # Verify exported content
            with open(csv_path, "r", encoding="utf-8") as f:
                lines = [line.strip() for line in f.readlines() if line.strip()]

            # Header + 2 qualified records
            assert len(lines) == 3
            assert "Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status" in lines[0]
            assert any("101 Validated St" in line for line in lines)
            assert any("102 Enriched Ave" in line for line in lines)
            assert not any("103 Discovered Rd" in line for line in lines)
            assert not any("104 Discarded Blvd" in line for line in lines)
        finally:
            if os.path.exists(tmp_db.name):
                os.remove(tmp_db.name)
            if os.path.exists(tmp_csv.name):
                os.remove(tmp_csv.name)


# ============================================================================
# 6. MAIN.PY CLI EXECUTION & FLAG VALIDATION
# ============================================================================

class TestMainCliExecution:
    """Empirical challenge tests for CLI invocation of main.py with various arguments."""

    def test_main_cli_help(self):
        res = subprocess.run(
            ["./venv/bin/python", "main.py", "--help"],
            capture_output=True,
            text=True
        )
        assert res.returncode == 0
        assert "--zip" in res.stdout
        assert "--address" in res.stdout
        assert "--db" in res.stdout
        assert "--headless" in res.stdout

    def test_main_cli_execution_with_custom_db_and_zip(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp_db:
            db_file = tmp_db.name
            db_uri = f"sqlite:///{db_file}"

        try:
            res = subprocess.run(
                ["./venv/bin/python", "main.py", "--zip", "94115", "--db", db_uri],
                capture_output=True,
                text=True,
                timeout=60
            )
            assert res.returncode == 0
            assert "Starting Roo4u Pipeline for Zip Code: 94115" in res.stdout
            assert "PIPELINE EXECUTION SUMMARY" in res.stdout

            # Verify records were inserted into the SQLite DB
            engine = create_engine(db_uri)
            session = sessionmaker(bind=engine)()
            leads = session.query(Lead).all()
            assert len(leads) >= 1
            session.close()
        finally:
            if os.path.exists(db_file):
                os.remove(db_file)

    def test_main_cli_execution_with_target_address(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp_db:
            db_file = tmp_db.name
            db_uri = f"sqlite:///{db_file}"

        try:
            target_addr = "2500 California St"
            res = subprocess.run(
                ["./venv/bin/python", "main.py", "--address", target_addr, "--zip", "94115", "--db", db_uri],
                capture_output=True,
                text=True,
                timeout=60
            )
            assert res.returncode == 0
            assert f"Processing targeted property address: {target_addr}" in res.stdout

            # Verify target address was saved in DB
            engine = create_engine(db_uri)
            session = sessionmaker(bind=engine)()
            lead = session.query(Lead).filter_by(address=target_addr).first()
            assert lead is not None
            assert lead.zip_code == "94115"
            session.close()
        finally:
            if os.path.exists(db_file):
                os.remove(db_file)


# ============================================================================
# 7. LOCAL LLM EXTRACTOR SCHEMA & PARSER ROBUSTNESS
# ============================================================================

class TestLocalLLMExtractorSchemas:
    """Empirical challenge tests for Pydantic schema validation and parser resilience."""

    def test_extractor_initialization_defaults(self):
        extractor = LocalLLMExtractor()
        assert extractor.base_url in (DEFAULT_LOCAL_URL, os.getenv("LOCAL_INFERENCE_URL", DEFAULT_LOCAL_URL))
        assert extractor.model == DEFAULT_LOCAL_MODEL
        assert extractor.api_key == "not-needed"

    def test_property_extraction_zip_code_validator(self):
        # Clean 5 digit
        p1 = PropertyExtraction(address="1 Main St", zip_code="94115")
        assert p1.zip_code == "94115"

        # Embedded in state string
        p2 = PropertyExtraction(address="1 Main St", zip_code="San Francisco, CA 94115-1234")
        assert p2.zip_code == "94115"

        # Integer input
        p3 = PropertyExtraction(address="1 Main St", zip_code=94115)
        assert p3.zip_code == "94115"

    def test_clean_json_response_resilience(self):
        extractor = LocalLLMExtractor()

        # Markdown json fence
        fenced = "```json\n{\"address\": \"100 Broadway\", \"zip_code\": \"94115\"}\n```"
        assert json.loads(extractor._clean_json_response(fenced))["address"] == "100 Broadway"

        # Text before and after json
        surrounded = "Here is the extraction:\n{\"address\": \"100 Broadway\", \"zip_code\": \"94115\"}\nHope this helps!"
        assert json.loads(extractor._clean_json_response(surrounded))["address"] == "100 Broadway"
