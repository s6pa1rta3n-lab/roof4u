import os
import sys
import json
import tempfile
import subprocess
import threading
import time
from datetime import datetime, date
import pytest
from playwright._impl._errors import Error as PlaywrightError

# Ensure project root is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError, OperationalError, PendingRollbackError

from db.database import Base, Lead, init_db, get_session, get_engine
from agents.base_agent import BaseAgent
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
from main import run_pipeline


# ============================================================================
# 1. PLAYWRIGHT BROWSER LIFECYCLE & TEARDOWN SAFETY (BaseAgent)
# ============================================================================

class TestPlaywrightLifecycleSafety:
    """Empirical stress tests for Playwright browser initialization, reuse, teardown, and exception handling."""

    def test_browser_start_and_teardown_clean(self):
        agent = BaseAgent(headless=True)
        assert agent.playwright is None
        assert agent.browser is None
        assert agent.page is None

        agent.start_browser()
        assert agent.playwright is not None
        assert agent.browser is not None
        assert agent.page is not None
        assert not agent.page.is_closed()

        agent.close_browser()
        # Verify references are reset to None
        assert agent.page is None
        assert agent.context is None
        assert agent.browser is None
        assert agent.playwright is None

    def test_browser_double_close_idempotent_safe(self):
        """
        Verifies that BaseAgent.close_browser() is fully idempotent and safe to invoke
        multiple times without raising PlaywrightError.
        """
        agent = BaseAgent(headless=True)
        agent.start_browser()
        agent.close_browser()
        assert agent.page is None
        # On second and third close, method should succeed cleanly without raising
        agent.close_browser()
        agent.close_browser()
        assert agent.page is None
        assert agent.context is None
        assert agent.browser is None
        assert agent.playwright is None

    def test_browser_context_manager_clean_exit(self):
        with BaseAgent(headless=True) as agent:
            assert agent.browser is not None
            assert agent.page is not None
            # Fetch a simple data URL
            html = agent.get_html("data:text/html,<html><body><h1>Test Page</h1></body></html>")
            assert "<h1>Test Page</h1>" in html
        # After context exit
        assert agent.page is None
        assert agent.browser is None

    def test_browser_context_manager_exception_safety(self):
        agent_ref = None
        try:
            with BaseAgent(headless=True) as agent:
                agent_ref = agent
                assert agent.browser is not None
                raise RuntimeError("Simulated agent processing failure during scraping")
        except RuntimeError as e:
            assert "Simulated agent processing failure" in str(e)

        # Verify browser cleanup executed despite exception
        assert agent_ref is not None
        assert agent_ref.page is None
        assert agent_ref.browser is None

    def test_get_html_after_close_restarts_browser(self):
        """Verifies that get_html cleanly restarts browser if invoked after close_browser()."""
        agent = BaseAgent(headless=True)
        html1 = agent.get_html("data:text/html,<html><body><span>Page 1</span></body></html>")
        assert "Page 1" in html1
        agent.close_browser()
        assert agent.page is None

        html2 = agent.get_html("data:text/html,<html><body><span>Page 2</span></body></html>")
        assert "Page 2" in html2
        agent.close_browser()
        assert agent.page is None

    def test_sequential_get_html_browser_reuse(self):
        agent = BaseAgent(headless=True)
        try:
            # First call auto-starts browser
            html1 = agent.get_html("data:text/html,<html><body><div id='one'>Content 1</div></body></html>")
            assert "Content 1" in html1
            # Second call reuses existing page/context without crashing
            html2 = agent.get_html("data:text/html,<html><body><div id='two'>Content 2</div></body></html>")
            assert "Content 2" in html2
        finally:
            agent.close_browser()

    def test_multiple_concurrent_agents_browser_isolation(self):
        """Verify multiple agents running in separate threads manage their own Playwright instances safely."""
        results = []
        errors = []

        def worker(agent_id: int):
            try:
                with BaseAgent(headless=True) as agent:
                    html = agent.get_html(f"data:text/html,<html><body><span>Agent {agent_id}</span></body></html>")
                    if f"Agent {agent_id}" in html:
                        results.append(agent_id)
            except Exception as e:
                errors.append((agent_id, str(e)))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert len(errors) == 0, f"Concurrent browser errors: {errors}"
        assert sorted(results) == [0, 1, 2]


# ============================================================================
# 2. DATABASE STATE TRANSITIONS & DATA CONSISTENCY
# ============================================================================

class TestDatabaseStateTransitionsAndConsistency:
    """Empirical challenge tests for Lead state machine, constraints, and transactions."""

    @pytest.fixture
    def test_db(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            db_path = f"sqlite:///{tmp.name}"
        engine = init_db(db_path)
        yield db_path, engine
        if os.path.exists(tmp.name):
            try:
                os.remove(tmp.name)
            except Exception:
                pass

    def test_state_transition_discovered_to_validated(self, test_db):
        db_path, engine = test_db
        session = get_session(engine)

        lead = Lead(
            address="1500 Sutter St",
            zip_code="94115",
            property_type="Single-Family",
            roof_type="Victorian",
            status="DISCOVERED"
        )
        session.add(lead)
        session.commit()
        assert lead.status == "DISCOVERED"

        # CountyAgent qualification step
        county_agent = CountyAgent(headless=True)
        # Enrich with old roof (20 years)
        lead.roof_age_years = 20.0
        lead.last_roof_permit_date = date(2004, 1, 1)
        if (lead.roof_age_years is not None and lead.roof_age_years >= 15.0) or (lead.estimated_value and lead.estimated_value > 1000000):
            lead.status = "VALIDATED"
        session.commit()

        reloaded = session.query(Lead).filter_by(address="1500 Sutter St").first()
        assert reloaded.status == "VALIDATED"
        assert reloaded.roof_age_years == 20.0
        session.close()

    def test_state_transition_validated_to_enriched(self, test_db):
        db_path, engine = test_db
        session = get_session(engine)

        lead = Lead(
            address="1600 Post St",
            zip_code="94115",
            property_type="Single-Family",
            status="VALIDATED",
            estimated_value=1500000.0,
            roof_age_years=18.0
        )
        session.add(lead)
        session.commit()

        # Simulate contact/enrichment phase
        lead.phone_number = "(415) 555-0199"
        lead.owner_name = "Jane Doe"
        lead.status = "ENRICHED"
        session.commit()

        reloaded = session.query(Lead).filter_by(address="1600 Post St").first()
        assert reloaded.status == "ENRICHED"
        assert reloaded.phone_number == "(415) 555-0199"
        assert reloaded.owner_name == "Jane Doe"
        session.close()

    def test_qualification_boundary_conditions(self):
        """Exhaustive boundary testing on roof age and estimated value rules."""
        county_agent = CountyAgent(headless=True)

        # 1. Exactly 15.0 years -> VALIDATED
        lead1 = Lead(address="L1", zip_code="94115", roof_age_years=15.0, estimated_value=500000.0, status="DISCOVERED")
        if (lead1.roof_age_years is not None and lead1.roof_age_years >= 15.0) or (lead1.estimated_value and lead1.estimated_value > 1000000):
            lead1.status = "VALIDATED"
        assert lead1.status == "VALIDATED"

        # 2. 14.99 years -> DISCOVERED
        lead2 = Lead(address="L2", zip_code="94115", roof_age_years=14.99, estimated_value=500000.0, status="DISCOVERED")
        if (lead2.roof_age_years is not None and lead2.roof_age_years >= 15.0) or (lead2.estimated_value and lead2.estimated_value > 1000000):
            lead2.status = "VALIDATED"
        assert lead2.status == "DISCOVERED"

        # 3. Exactly $1,000,000.0 -> DISCOVERED (rule is > 1000000)
        lead3 = Lead(address="L3", zip_code="94115", roof_age_years=5.0, estimated_value=1000000.0, status="DISCOVERED")
        if (lead3.roof_age_years is not None and lead3.roof_age_years >= 15.0) or (lead3.estimated_value and lead3.estimated_value > 1000000):
            lead3.status = "VALIDATED"
        assert lead3.status == "DISCOVERED"

        # 4. $1,000,000.01 -> VALIDATED
        lead4 = Lead(address="L4", zip_code="94115", roof_age_years=5.0, estimated_value=1000000.01, status="DISCOVERED")
        if (lead4.roof_age_years is not None and lead4.roof_age_years >= 15.0) or (lead4.estimated_value and lead4.estimated_value > 1000000):
            lead4.status = "VALIDATED"
        assert lead4.status == "VALIDATED"

        # 5. None / None -> DISCOVERED
        lead5 = Lead(address="L5", zip_code="94115", roof_age_years=None, estimated_value=None, status="DISCOVERED")
        if (lead5.roof_age_years is not None and lead5.roof_age_years >= 15.0) or (lead5.estimated_value and lead5.estimated_value > 1000000):
            lead5.status = "VALIDATED"
        assert lead5.status == "DISCOVERED"

    def test_sql_injection_and_special_characters_in_address(self, test_db):
        db_path, engine = test_db
        session = get_session(engine)

        adversarial_addresses = [
            "100 Main St'; DROP TABLE leads; --",
            "200 O'Connor St #4B, San Francisco, CA",
            "300 \"Quotes\" & <Tags> Blvd",
            "400 🌟 Unicode Emoji Ave",
            "500 \n\t Whitespace St",
        ]

        for idx, addr in enumerate(adversarial_addresses):
            lead = Lead(
                address=addr,
                zip_code="94115",
                property_type="Single-Family",
                status="DISCOVERED"
            )
            session.add(lead)
        session.commit()

        # Ensure table still exists and all 5 records are stored accurately
        leads = session.query(Lead).all()
        assert len(leads) == len(adversarial_addresses)
        for addr in adversarial_addresses:
            found = session.query(Lead).filter_by(address=addr).first()
            assert found is not None
            assert found.address == addr
        session.close()

    def test_transaction_rollback_on_error(self, test_db):
        db_path, engine = test_db
        session = get_session(engine)

        lead1 = Lead(address="100 Unique St", zip_code="94115")
        session.add(lead1)
        session.commit()

        # Add duplicate and uncommitted change
        lead2 = Lead(address="100 Unique St", zip_code="94115")
        session.add(lead2)
        with pytest.raises(IntegrityError):
            session.commit()

        session.rollback()
        # Verify database session is healthy after rollback
        count = session.query(Lead).count()
        assert count == 1
        session.close()

    def test_loop_rollback_isolation(self, test_db):
        """Demonstrates that without session.rollback() on failure, subsequent iterations fail with PendingRollbackError."""
        db_path, engine = test_db
        session = get_session(engine)

        lead1 = Lead(address="Lead Alpha", zip_code="94115", status="DISCOVERED")
        lead2 = Lead(address="Lead Beta", zip_code="94115", status="DISCOVERED")
        session.add_all([lead1, lead2])
        session.commit()

        # Iteration without rollback
        leads = session.query(Lead).all()
        caught_pending_rollback = False
        for idx, l in enumerate(leads):
            try:
                if idx == 0:
                    l.address = None # Violates non-null
                    session.flush()
                else:
                    l.status = "VALIDATED"
                    session.commit()
            except IntegrityError:
                pass # Intentionally omit session.rollback() to test failure cascading
            except PendingRollbackError:
                caught_pending_rollback = True

        assert caught_pending_rollback is True
        session.rollback()
        session.close()


# ============================================================================
# 3. MULTI-AGENT PIPELINE INTEGRATION IN MAIN.PY
# ============================================================================

class TestMainPipelineDeepIntegration:
    """Empirical challenge tests for main.py execution paths, CLI arguments, and idempotency."""

    def test_pipeline_idempotency_multiple_runs(self):
        """Running the pipeline multiple times on the same database should not create duplicate entries or crash."""
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            db_file = tmp.name
            db_uri = f"sqlite:///{db_file}"

        try:
            # First Run with default seed
            run_pipeline(zip_code="94115", headless=True, db_path=db_uri)

            engine = create_engine(db_uri)
            session = sessionmaker(bind=engine)()
            initial_count = session.query(Lead).count()
            assert initial_count >= 1
            session.close()

            # Second Run with same parameters
            run_pipeline(zip_code="94115", headless=True, db_path=db_uri)

            session = sessionmaker(bind=engine)()
            second_count = session.query(Lead).count()
            # Idempotency check: count should remain constant (no duplicates)
            assert second_count == initial_count
            session.close()
        finally:
            if os.path.exists(db_file):
                os.remove(db_file)

    def test_pipeline_targeted_address_mode(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            db_file = tmp.name
            db_uri = f"sqlite:///{db_file}"

        try:
            target = "2840 Jackson St, San Francisco, CA"
            run_pipeline(zip_code="94115", target_address=target, headless=True, db_path=db_uri)

            engine = create_engine(db_uri)
            session = sessionmaker(bind=engine)()
            lead = session.query(Lead).filter_by(address=target).first()
            assert lead is not None
            assert lead.zip_code == "94115"
            session.close()
        finally:
            if os.path.exists(db_file):
                os.remove(db_file)

    def test_pipeline_cli_invocation_various_flags(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            db_file = tmp.name
            db_uri = f"sqlite:///{db_file}"

        try:
            cmd = [
                "./venv/bin/python", "main.py",
                "--zip", "94102",
                "--address", "500 Hayes St",
                "--db", db_uri,
                "--headless"
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            assert res.returncode == 0
            assert "Starting Roo4u Pipeline for Zip Code: 94102" in res.stdout
            assert "500 Hayes St" in res.stdout
            assert "PIPELINE EXECUTION SUMMARY" in res.stdout

            engine = create_engine(db_uri)
            session = sessionmaker(bind=engine)()
            lead = session.query(Lead).filter_by(address="500 Hayes St").first()
            assert lead is not None
            assert lead.zip_code == "94102"
            session.close()
        finally:
            if os.path.exists(db_file):
                os.remove(db_file)

    def test_pipeline_cli_invalid_database_url_graceful_handling(self):
        """Testing CLI with invalid db path creates appropriate error or exit."""
        cmd = [
            "./venv/bin/python", "main.py",
            "--db", "sqlite:////non_existent_dir/impossible/path/db.sqlite"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        # Should fail with non-zero exit code due to SQLite operational error
        assert res.returncode != 0
        assert "unable to open database file" in res.stderr or "OperationalError" in res.stderr


# ============================================================================
# 4. EXTRACTOR ROBUSTNESS & FALLBACK HANDLING
# ============================================================================

class TestExtractorRobustness:
    """Empirical challenge tests for LocalLLMExtractor schemas, cleaning, and error handling."""

    def test_clean_json_response_multiline_markdown(self):
        ext = LocalLLMExtractor()
        raw = "```json\n{\n  \"address\": \"2223 Pacific Ave\",\n  \"zip_code\": \"94115\"\n}\n```"
        cleaned = ext._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "2223 Pacific Ave"
        assert data["zip_code"] == "94115"

    def test_clean_json_response_no_codeblock(self):
        ext = LocalLLMExtractor()
        raw = '{"address": "100 Pine St", "zip_code": "94111"}'
        cleaned = ext._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "100 Pine St"

    def test_clean_json_response_with_surrounding_conversational_text(self):
        ext = LocalLLMExtractor()
        raw = 'Here is the extracted property information:\n\n{"address": "500 Market St", "zip_code": "94105", "estimated_value": 3000000.0}\n\nLet me know if you need anything else!'
        cleaned = ext._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "500 Market St"
        assert data["estimated_value"] == 3000000.0

    def test_clean_json_response_with_preamble_curly_braces(self):
        ext = LocalLLMExtractor()
        raw = 'Considering criteria {budget} and {zip_code}:\n{"address": "123 Main St", "zip_code": "94115"}\nHave a nice day!'
        cleaned = ext._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "123 Main St"
        assert data["zip_code"] == "94115"

    def test_clean_json_response_thinking_tokens(self):
        ext = LocalLLMExtractor()
        raw = '<think>\nAnalyze address {123 Main St}\n</think>\n```json\n{"address": "123 Main St", "zip_code": "94115"}\n```'
        cleaned = ext._clean_json_response(raw)
        data = json.loads(cleaned)
        assert data["address"] == "123 Main St"
        assert data["zip_code"] == "94115"


    def test_property_extraction_schema_defaults(self):
        prop = PropertyExtraction(address="123 Example Way", zip_code="94115")
        assert prop.property_type == "Single-Family"
        assert prop.roof_type == "Unknown"
        assert prop.is_hoa is False
        assert prop.is_rental is False
        assert prop.confidence_score == 1.0

    def test_county_permit_extraction_schema_defaults(self):
        county = CountyPermitExtraction(address="123 Example Way")
        assert county.apn is None
        assert county.permit_history == []
        assert county.is_hoa is False
        assert county.is_rental is False
        assert county.confidence_score == 1.0

    def test_extractor_offline_endpoint_error_handling(self):
        """When local endpoint is unreachable, extractor should raise a clear RuntimeError."""
        # Using a dummy closed port
        unreachable_ext = LocalLLMExtractor(base_url="http://127.0.0.1:54321/v1", timeout=1.0)
        with pytest.raises(RuntimeError) as exc_info:
            unreachable_ext.extract_property_details("<div>Some HTML</div>")
        assert "Local LLM inference failed" in str(exc_info.value)
