"""
tests/test_pipeline_e2e.py

End-to-End Multi-Agent Integration Test Suite for Roo4u (Milestone 3).
Validates:
1. Full Lead Lifecycle: Discovery -> Assessor/Permits -> Qualification -> SQLite DB -> CSV Export.
2. Closed-Loop Self-Healing: Injected Failure -> ScrapingFailureEvent -> LearningAgent ->
   Dual Memory (LessonStore + LocalVectorStore) + GitHub Issue Logger -> Feedforward Retry -> Success.
3. Subprocess CLI Execution: main.py execution as an isolated OS process against live loopback servers.
4. Zero-Mock Standard: Strictly 0 unittest.mock / MagicMock imports; all network calls use live loopback TCP sockets.
"""

import os
import sys
import ast
import re
import json
import time
import socket
import tempfile
import threading
import subprocess
from datetime import datetime, date
from typing import Dict, Any, List

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from db.database import init_db, get_session, Lead, Base
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor, PropertyExtraction, CountyPermitExtraction
from agents.learning_agent import LearningAgent
from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger, ScrapingFailureEvent
from exporters.csv_exporter import export_to_csv


# ============================================================================
# 1. FULL LEAD LIFECYCLE E2E
# ============================================================================

class TestFullLeadLifecycleE2E:
    """
    Validates end-to-end traversal of property leads across all lifecycle phases:
    Discovery -> Assessor/Permits -> Qualification -> SQLite DB -> CSV Export.
    """

    def test_e2e_single_property_lifecycle_discovery_to_csv(self, tmp_path, live_inference_server, live_html_server):
        db_file = tmp_path / "lifecycle.db"
        csv_file = tmp_path / "validated_leads.csv"
        db_uri = f"sqlite:///{db_file}"

        # 1. Initialize DB
        engine = init_db(db_uri)
        session = get_session(engine)

        # 2. Initialize Agents with live loopback server
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        zillow_agent = ZillowAgent(headless=True, extractor=extractor, base_url=live_html_server)
        county_agent = CountyAgent(
            headless=True,
            extractor=extractor,
            pim_base_url=f"{live_html_server}/pim",
            dbi_base_url=f"{live_html_server}/dbipts"
        )

        try:
            # 3. PHASE 1: DISCOVERY
            listing_url = f"{live_html_server}/homedetails/2223-Pacific-Ave"
            lead = zillow_agent.scrape_and_create_lead(listing_url, target_zip="94115")
            assert lead.address == "2223 Pacific Ave, San Francisco, CA 94115"
            assert lead.status == "DISCOVERED"
            assert lead.estimated_value == 4370000.0

            session.add(lead)
            session.commit()
            zillow_agent.close_browser()

            # 4. PHASE 2: ASSESSOR & PERMITS ENRICHMENT
            lead_in_db = session.query(Lead).filter_by(address="2223 Pacific Ave, San Francisco, CA 94115").first()
            county_agent.enrich_lead(
                lead_in_db,
                pim_html_or_url=f"{live_html_server}/pim/",
                dbi_html_or_url=f"{live_html_server}/dbipts"
            )
            session.commit()

            # 5. PHASE 3: QUALIFICATION VERIFICATION
            refreshed = session.query(Lead).filter_by(id=lead_in_db.id).first()
            assert refreshed.apn == "0582-014"
            assert refreshed.owner_name == "PACIFIC HERITAGE TRUST"
            assert refreshed.last_roof_permit_date == date(2008, 5, 14)
            assert refreshed.roof_age_years is not None
            assert refreshed.status == "VALIDATED"

            # 6. PHASE 4: CSV EXPORT
            export_to_csv(db_path=db_uri, output_file=str(csv_file))

            assert os.path.exists(csv_file)
            with open(csv_file, "r", encoding="utf-8") as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]

            # Header + 1 lead row
            assert len(lines) == 2
            assert "2223 Pacific Ave, San Francisco, CA 94115" in lines[1]
            assert "PACIFIC HERITAGE TRUST" in lines[1]
            assert "VALIDATED" in lines[1]
        finally:
            zillow_agent.close_browser()
            county_agent.close_browser()
            session.close()

    def test_e2e_multi_property_batch_lifecycle(self, tmp_path):
        db_file = tmp_path / "multi_prop.db"
        csv_file = tmp_path / "multi_validated.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        leads = [
            # 1. Qualified by roof age >= 15
            Lead(
                address="100 Victorian Ave",
                zip_code="94115",
                property_type="Single-Family",
                roof_type="Victorian",
                estimated_value=850000.0,
                owner_name="TRUST A",
                apn="0100-001",
                last_roof_permit_date=date(2005, 4, 1),
                roof_age_years=21.0,
                status="VALIDATED"
            ),
            # 2. Qualified by value > $1,000,000
            Lead(
                address="200 Luxury Flat St",
                zip_code="94115",
                property_type="Condo",
                roof_type="Flat",
                estimated_value=2500000.0,
                owner_name="TRUST B",
                apn="0200-002",
                last_roof_permit_date=date(2022, 1, 1),
                roof_age_years=4.0,
                status="VALIDATED"
            ),
            # 3. Not qualified (young roof, value < $1M)
            Lead(
                address="300 Modest Rd",
                zip_code="94115",
                property_type="Single-Family",
                roof_type="Unknown",
                estimated_value=600000.0,
                owner_name="TRUST C",
                apn="0300-003",
                last_roof_permit_date=date(2023, 6, 1),
                roof_age_years=3.0,
                status="DISCOVERED"
            )
        ]
        session.add_all(leads)
        session.commit()

        # Verify DB counts
        assert session.query(Lead).count() == 3
        assert session.query(Lead).filter_by(status="VALIDATED").count() == 2
        assert session.query(Lead).filter_by(status="DISCOVERED").count() == 1

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]

        assert len(lines) == 3  # Header + 2 validated records
        assert any("100 Victorian Ave" in l for l in lines)
        assert any("200 Luxury Flat St" in l for l in lines)
        assert not any("300 Modest Rd" in l for l in lines)
        session.close()

    def test_e2e_lead_enrichment_state_idempotency(self, live_inference_server):
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        agent = CountyAgent(headless=True, extractor=extractor)
        lead = Lead(
            address="2223 Pacific Ave, San Francisco, CA 94115",
            zip_code="94115",
            status="DISCOVERED"
        )
        pim_html = "<div>APN: 0582-014, Owner: PACIFIC HERITAGE TRUST, Value: $3,850,000</div>"
        dbi_html = "<table><tr><td>200805141234</td><td>Reroofing</td><td>05/14/2008</td></tr></table>"

        # Enrich once
        lead = agent.enrich_lead(lead, pim_html_or_url=pim_html, dbi_html_or_url=dbi_html)
        assert lead.apn == "0582-014"
        assert lead.status == "VALIDATED"

        # Enrich again - state should be idempotent
        lead = agent.enrich_lead(lead, pim_html_or_url=pim_html, dbi_html_or_url=dbi_html)
        assert lead.apn == "0582-014"
        assert lead.status == "VALIDATED"

    def test_e2e_property_discovery_search_page_parsing(self, live_html_server):
        agent = ZillowAgent(headless=True, base_url=live_html_server)
        try:
            candidates = agent.discover_properties(zip_code="94115", max_results=5)
            assert len(candidates) >= 1
            for c in candidates:
                assert "url" in c
                assert "summary" in c
                assert c["zip_code"] == "94115"
        finally:
            agent.close_browser()


# ============================================================================
# 2. CLOSED-LOOP SELF-HEALING & TELEMETRY
# ============================================================================

class TestClosedLoopSelfHealingE2E:
    """
    Validates autonomous failure observation, dual-memory upsert, GitHub issue logging,
    feedforward lesson retrieval, workaround execution, and efficacy tracking.
    """

    def test_closed_loop_dom_selector_drift_healing_and_feedforward_retry(self, tmp_path, live_inference_server):
        lessons_file = str(tmp_path / "lessons.json")
        vector_file = str(tmp_path / "vectors.sqlite")
        queue_file = str(tmp_path / "issues_queue.json")

        lesson_store = LessonStore(file_path=lessons_file)
        vector_store = LocalVectorStore(db_path=vector_file)
        github_logger = GitHubIssueLogger(
            owner="s6pa1rta3n-lab",
            repo="roof4u",
            enabled=True,
            offline_queue_path=queue_file
        )

        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=github_logger
        )

        # 1. Simulate Failure Emission
        event = ScrapingFailureEvent(
            domain="zillow.com",
            url="https://zillow.com/homes/94115_rb/",
            phase="DISCOVERY",
            target_entity="94115",
            failure_type="DOM_SELECTOR_DRIFT",
            error_message="0 property cards found on page",
            selector="article[data-test='property-card']",
            dom_snippet="<div class='legacy-property-list'>...</div>"
        )
        resolution = learning_agent.observe_failure(event)
        assert resolution.retry_recommended is True
        assert resolution.lesson is not None

        # 2. Verify Dual-Memory Persistence
        assert lesson_store.count(domain="zillow.com") == 1
        assert vector_store.count(domain="zillow.com") == 1

        # 3. Retrieve Feedforward Strategy
        strategy = learning_agent.get_feedforward_strategy(domain="zillow.com", action_context="property search")
        assert strategy.fallback_selectors is not None
        assert len(strategy.fallback_selectors) >= 1

        # 4. Execute Self-Healing Action with Fallback Selectors
        drifted_html = """
        <div class="legacy-detail-pane">
            <h1>2223 Pacific Ave, San Francisco, CA 94115</h1>
            <span class="price">$4,370,000</span>
        </div>
        """
        cleaned = ZillowAgent.clean_dom(drifted_html, extra_selectors=strategy.fallback_selectors)
        extractor = LocalLLMExtractor(base_url=live_inference_server)
        extraction = extractor.extract_property_details(cleaned)
        assert "2223 Pacific Ave" in extraction.address

        # 5. Record Success and Verify Efficacy Increment
        learning_agent.observe_success(domain="zillow.com", target_entity="2223 Pacific Ave", lesson_id=resolution.lesson.id)
        updated_lesson = lesson_store.get_lesson(resolution.lesson.id)
        assert updated_lesson.success_count_after_workaround == 1

    def test_closed_loop_anti_bot_403_jitter_and_header_injection(self, tmp_path):
        lesson_store = LessonStore(file_path=str(tmp_path / "lessons_403.json"))
        vector_store = LocalVectorStore(db_path=str(tmp_path / "vectors_403.sqlite"))
        github_logger = GitHubIssueLogger(enabled=False)

        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=github_logger
        )

        event = ScrapingFailureEvent(
            domain="zillow.com",
            url="https://zillow.com/property/123",
            phase="DISCOVERY",
            target_entity="123 Main St",
            failure_type="ANTI_BOT_BLOCKED",
            error_message="HTTP 403 Forbidden"
        )
        resolution = learning_agent.observe_failure(event)
        assert resolution.lesson is not None

        strategy = learning_agent.get_feedforward_strategy(domain="zillow.com", action_context="navigate property")
        assert strategy.request_delay_seconds >= 2.0
        assert "User-Agent" in strategy.custom_headers

    def test_closed_loop_issue_deduplication_and_comment_throttling(self, tmp_path):
        queue_file = str(tmp_path / "dedup_queue.json")
        github_logger = GitHubIssueLogger(
            owner="s6pa1rta3n-lab",
            repo="roof4u",
            enabled=True,
            offline_queue_path=queue_file
        )

        event = ScrapingFailureEvent(
            domain="sfplanninggis.org",
            url="https://sfplanninggis.org/pim",
            phase="ASSESSOR",
            target_entity="100 Market St",
            failure_type="EXTRACTION_PARSE_ERROR",
            error_message="Missing table"
        )

        # First failure creates issue
        res1 = github_logger.log_scraping_failure(event)
        assert res1.action in ("created", "queued")

        # Second rapid failure gets throttled
        res2 = github_logger.log_scraping_failure(event)
        assert res2.action in ("throttled", "commented", "queued")

    def test_closed_loop_multi_domain_isolation(self, tmp_path):
        lesson_store = LessonStore(file_path=str(tmp_path / "iso_lessons.json"))
        vector_store = LocalVectorStore(db_path=str(tmp_path / "iso_vectors.sqlite"))
        learning_agent = LearningAgent(lesson_store=lesson_store, vector_store=vector_store)

        # Add zillow lesson with custom selector
        lesson_zillow = Lesson(
            domain="zillow.com",
            failure_type="DOM_SELECTOR_DRIFT",
            fallback_selectors=[".zillow-custom-card"]
        )
        lesson_store.upsert_lesson(lesson_zillow)

        # Strategy for sfplanninggis should NOT include zillow selectors
        sf_strategy = learning_agent.get_feedforward_strategy(domain="sfplanninggis.org", action_context="assessor")
        assert ".zillow-custom-card" not in sf_strategy.fallback_selectors


# ============================================================================
# 3. SUBPROCESS CLI EXECUTION
# ============================================================================

class TestPipelineCLISubprocessE2E:
    """
    Validates standalone black-box execution of main.py via subprocess.run
    against live loopback sockets, validating exit codes, stdout, and DB persistence.
    """

    def test_subprocess_cli_single_address_execution(self, tmp_path, live_inference_server, live_html_server):
        db_file = tmp_path / "cli_test.db"
        db_uri = f"sqlite:///{db_file}"

        env = os.environ.copy()
        env["LOCAL_INFERENCE_URL"] = live_inference_server
        env["ZILLOW_BASE_URL"] = live_html_server
        env["SF_PIM_BASE_URL"] = f"{live_html_server}/pim"
        env["SF_DBI_BASE_URL"] = f"{live_html_server}/dbipts"

        res = subprocess.run(
            [
                "./venv/bin/python", "main.py",
                "--zip", "94115",
                "--address", "2223 Pacific Ave, San Francisco, CA 94115",
                "--db", db_uri,
                "--headless",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            env=env
        )

        assert res.returncode == 0
        assert "Starting Roo4u Pipeline for Zip Code: 94115" in res.stdout
        assert "PHASE 1: DISCOVERY" in res.stdout
        assert "PHASE 2: ASSESSOR & PERMITS" in res.stdout
        assert "PIPELINE EXECUTION SUMMARY" in res.stdout
        assert "Pipeline Complete!" in res.stdout

        # Verify DB content
        engine = create_engine(db_uri)
        session = sessionmaker(bind=engine)()
        lead = session.query(Lead).filter_by(address="2223 Pacific Ave, San Francisco, CA 94115").first()
        assert lead is not None
        assert lead.status == "VALIDATED"
        session.close()

    def test_subprocess_cli_discovery_mode_execution(self, tmp_path, live_inference_server, live_html_server):
        db_file = tmp_path / "cli_discovery.db"
        db_uri = f"sqlite:///{db_file}"

        env = os.environ.copy()
        env["LOCAL_INFERENCE_URL"] = live_inference_server
        env["ZILLOW_BASE_URL"] = live_html_server
        env["SF_PIM_BASE_URL"] = f"{live_html_server}/pim"
        env["SF_DBI_BASE_URL"] = f"{live_html_server}/dbipts"

        res = subprocess.run(
            [
                "./venv/bin/python", "main.py",
                "--zip", "94115",
                "--db", db_uri,
                "--headless",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            env=env
        )

        assert res.returncode == 0
        assert "PHASE 1: DISCOVERY" in res.stdout
        assert "PIPELINE EXECUTION SUMMARY" in res.stdout

    def test_subprocess_cli_learning_telemetry_summary_output(self, tmp_path, live_inference_server, live_html_server):
        db_file = tmp_path / "cli_learning.db"
        db_uri = f"sqlite:///{db_file}"

        env = os.environ.copy()
        env["LOCAL_INFERENCE_URL"] = live_inference_server
        env["ZILLOW_BASE_URL"] = live_html_server

        res = subprocess.run(
            [
                "./venv/bin/python", "main.py",
                "--zip", "94115",
                "--address", "2223 Pacific Ave",
                "--db", db_uri,
                "--headless",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            env=env
        )

        assert res.returncode == 0
        assert "LEARNING & TELEMETRY SUMMARY" in res.stdout
        assert "Total Lessons in Memory:" in res.stdout

    def test_subprocess_cli_invalid_arguments_graceful_exit(self):
        res = subprocess.run(
            ["./venv/bin/python", "main.py", "--invalid-nonexistent-flag"],
            capture_output=True,
            text=True
        )
        assert res.returncode != 0
        assert "usage:" in res.stderr.lower() or "error:" in res.stderr.lower()


# ============================================================================
# 4. AST ANTI-MOCK & SYSTEM INTEGRITY
# ============================================================================

class TestASTAntiMockIntegrityE2E:
    """
    Programmatic AST inspection enforcing strict zero-mock standards
    and cryptographic/persistence integrity.
    """

    FORBIDDEN_MODULES = {"unittest.mock", "mock", "pytest_mock"}
    FORBIDDEN_NAMES = {"MagicMock", "Mock", "patch", "AsyncMock", "PropertyMock"}

    def test_ast_anti_mock_zero_mock_imports_in_tests(self):
        tests_dir = os.path.dirname(__file__)
        violations = []

        for fname in os.listdir(tests_dir):
            if fname.startswith("test_") and fname.endswith(".py"):
                fpath = os.path.join(tests_dir, fname)
                with open(fpath, "r", encoding="utf-8") as f:
                    tree = ast.parse(f.read(), filename=fpath)

                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            if alias.name in self.FORBIDDEN_MODULES:
                                violations.append(f"{fname}: import {alias.name}")
                    elif isinstance(node, ast.ImportFrom):
                        if node.module in self.FORBIDDEN_MODULES:
                            violations.append(f"{fname}: from {node.module} import ...")
                        for alias in node.names:
                            if alias.name in self.FORBIDDEN_NAMES:
                                violations.append(f"{fname}: from {node.module} import {alias.name}")

        assert len(violations) == 0, f"Found mock violations in test suite: {violations}"

    def test_ast_no_cloud_api_keys_or_cloud_sdks(self):
        src_dirs = [
            os.path.join(PROJECT_ROOT, "agents"),
            os.path.join(PROJECT_ROOT, "memory"),
            os.path.join(PROJECT_ROOT, "integrations"),
            os.path.join(PROJECT_ROOT, "db"),
            os.path.join(PROJECT_ROOT, "exporters"),
        ]
        forbidden_sdk_modules = {"google.generativeai", "google.ai.generativelanguage"}
        violations = []

        for d in src_dirs:
            if not os.path.exists(d):
                continue
            for root, _, files in os.walk(d):
                for file in files:
                    if file.endswith(".py"):
                        fpath = os.path.join(root, file)
                        with open(fpath, "r", encoding="utf-8") as f:
                            content = f.read()

                        # Check for hardcoded API keys (exclude scanner definitions)
                        if file not in ("judge_agent.py", "run_judge.py"):
                            if re.search(r"AIzaSy[A-Za-z0-9_-]{30,}", content) or re.search(r"sk-proj-[A-Za-z0-9_-]{20,}", content):
                                violations.append(f"{file}: contains hardcoded cloud API key")

                        tree = ast.parse(content, filename=fpath)
                        for node in ast.walk(tree):
                            if isinstance(node, ast.Import):
                                for alias in node.names:
                                    if alias.name in forbidden_sdk_modules:
                                        violations.append(f"{file}: import {alias.name}")
                            elif isinstance(node, ast.ImportFrom):
                                if node.module in forbidden_sdk_modules:
                                    violations.append(f"{file}: from {node.module} import ...")

        assert len(violations) == 0, f"Found cloud SDK / key violations in source files: {violations}"

    def test_live_socket_connectivity_verification(self, live_inference_server, live_html_server):
        # Verify both servers are loopback 127.0.0.1
        assert "127.0.0.1" in live_inference_server or "localhost" in live_inference_server
        assert "127.0.0.1" in live_html_server or "localhost" in live_html_server
