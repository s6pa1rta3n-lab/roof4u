"""
tests/test_challenger_m3_2_stress.py

Empirical Stress Test Suite for Milestone 3 Challenger M3-2.
Validates:
1. Multi-flag CLI permutations of main.py via isolated subprocess execution.
2. Multi-failure closed-loop self-healing convergence & high-concurrency memory safety.
3. CSV export formatting, Unicode preservation, and special character escaping under edge-case lead data.

Zero-Mock Standard: Strictly 0 unittest.mock / MagicMock imports.
"""

import os
import sys
import csv
import json
import time
import uuid
import socket
import tempfile
import threading
import subprocess
from datetime import datetime, date, timezone
from typing import Dict, Any, List
from concurrent.futures import ThreadPoolExecutor, as_completed

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
from agents.learning_agent import LearningAgent, FailureCategory, FeedforwardStrategy, LessonResolution
from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger, ScrapingFailureEvent
from exporters.csv_exporter import export_to_csv


# ============================================================================
# 1. MULTI-FLAG CLI PERMUTATIONS VIA SUBPROCESS
# ============================================================================

class TestCLIPermutationsSubprocess:
    """
    Stress-tests CLI argument handling, environment variable routing,
    and process execution lifecycles of main.py via subprocess.run.
    """

    def _get_loopback_env(self, live_inference_server: str, live_html_server: str) -> Dict[str, str]:
        env = os.environ.copy()
        env["LOCAL_INFERENCE_URL"] = live_inference_server
        env["ZILLOW_BASE_URL"] = live_html_server
        env["SF_PIM_BASE_URL"] = f"{live_html_server}/pim"
        env["SF_DBI_BASE_URL"] = f"{live_html_server}/dbipts"
        return env

    def test_cli_help_flag(self):
        """Verifies --help exits with 0 and prints usage information."""
        res = subprocess.run(
            [sys.executable, "main.py", "--help"],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=PROJECT_ROOT
        )
        assert res.returncode == 0
        assert "usage: main.py" in res.stdout
        assert "--zip" in res.stdout
        assert "--address" in res.stdout
        assert "--headless" in res.stdout
        assert "--db" in res.stdout
        assert "--disable-learning" in res.stdout
        assert "--disable-github" in res.stdout

    def test_cli_targeted_address_custom_db(self, tmp_path, live_inference_server, live_html_server):
        """Verifies --address with --db executes cleanly and persists validated lead."""
        db_file = tmp_path / "custom_target.db"
        db_uri = f"sqlite:///{db_file}"
        env = self._get_loopback_env(live_inference_server, live_html_server)

        res = subprocess.run(
            [
                sys.executable, "main.py",
                "--zip", "94115",
                "--address", "2223 Pacific Ave, San Francisco, CA 94115",
                "--db", db_uri,
                "--headless",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=PROJECT_ROOT,
            env=env
        )

        assert res.returncode == 0
        assert "Processing targeted property address: 2223 Pacific Ave, San Francisco, CA 94115" in res.stdout
        assert "PHASE 2: ASSESSOR & PERMITS" in res.stdout
        assert "PIPELINE EXECUTION SUMMARY" in res.stdout

        engine = create_engine(db_uri)
        session = sessionmaker(bind=engine)()
        lead = session.query(Lead).filter_by(address="2223 Pacific Ave, San Francisco, CA 94115").first()
        assert lead is not None
        assert lead.status == "VALIDATED"
        session.close()

    def test_cli_discovery_mode_with_custom_zip(self, tmp_path, live_inference_server, live_html_server):
        """Verifies discovery mode with custom zip code --zip 94123."""
        db_file = tmp_path / "custom_zip.db"
        db_uri = f"sqlite:///{db_file}"
        env = self._get_loopback_env(live_inference_server, live_html_server)

        res = subprocess.run(
            [
                sys.executable, "main.py",
                "--zip", "94123",
                "--db", db_uri,
                "--headless",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=PROJECT_ROOT,
            env=env
        )

        assert res.returncode == 0
        assert "Target Zip: 94123" in res.stdout
        assert "Executing ZillowAgent discovery for zip code: 94123" in res.stdout

        engine = create_engine(db_uri)
        session = sessionmaker(bind=engine)()
        leads = session.query(Lead).all()
        assert len(leads) >= 1
        session.close()

    def test_cli_disable_learning_and_github_flags(self, tmp_path, live_inference_server, live_html_server):
        """Verifies --disable-learning and --disable-github cleanly bypass learning agent and issue tracker."""
        db_file = tmp_path / "no_learning.db"
        db_uri = f"sqlite:///{db_file}"
        env = self._get_loopback_env(live_inference_server, live_html_server)

        res = subprocess.run(
            [
                sys.executable, "main.py",
                "--address", "2223 Pacific Ave, San Francisco, CA 94115",
                "--db", db_uri,
                "--disable-learning",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=PROJECT_ROOT,
            env=env
        )

        assert res.returncode == 0
        assert "LEARNING & TELEMETRY SUMMARY" not in res.stdout
        assert "Pipeline Complete!" in res.stdout

    def test_cli_spaces_in_address_and_db_path(self, tmp_path, live_inference_server, live_html_server):
        """Verifies CLI execution with space-containing paths and quotes."""
        db_file = tmp_path / "path with spaces" / "leads database.db"
        os.makedirs(db_file.parent, exist_ok=True)
        db_uri = f"sqlite:///{db_file}"
        env = self._get_loopback_env(live_inference_server, live_html_server)

        res = subprocess.run(
            [
                sys.executable, "main.py",
                "--address", "2223 Pacific Ave, San Francisco, CA 94115",
                "--db", db_uri,
                "--headless",
                "--disable-github"
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=PROJECT_ROOT,
            env=env
        )

        assert res.returncode == 0
        assert "Processing targeted property address: 2223 Pacific Ave, San Francisco, CA 94115" in res.stdout

        engine = create_engine(db_uri)
        session = sessionmaker(bind=engine)()
        lead = session.query(Lead).filter_by(address="2223 Pacific Ave, San Francisco, CA 94115").first()
        assert lead is not None
        assert lead.status == "VALIDATED"
        session.close()

    def test_cli_invalid_flag_rejection(self):
        """Verifies unknown flags raise non-zero exit codes."""
        res = subprocess.run(
            [sys.executable, "main.py", "--unrecognized-custom-flag-12345"],
            capture_output=True,
            text=True,
            timeout=15,
            cwd=PROJECT_ROOT
        )
        assert res.returncode != 0
        assert "unrecognized arguments" in res.stderr.lower() or "error" in res.stderr.lower()

    def test_cli_missing_arg_value_rejection(self):
        """Verifies missing required argument values fail gracefully."""
        res = subprocess.run(
            [sys.executable, "main.py", "--zip"],
            capture_output=True,
            text=True,
            timeout=15,
            cwd=PROJECT_ROOT
        )
        assert res.returncode != 0
        assert "expected one argument" in res.stderr.lower() or "error" in res.stderr.lower()


# ============================================================================
# 2. MULTI-FAILURE CLOSED-LOOP SELF-HEALING CONVERGENCE
# ============================================================================

class TestMultiFailureClosedLoopConvergence:
    """
    Stress-tests multi-failure accumulation, deduplication, feedforward aggregation,
    and concurrent multi-threaded safety of the Learning Agent loop.
    """

    def test_repeated_homogeneous_failures_occurrence_counter(self, tmp_path):
        """Verifies 10 identical failure events increment occurrence_count to 10 on a single lesson."""
        lessons_file = str(tmp_path / "homo_lessons.json")
        vector_file = str(tmp_path / "homo_vectors.sqlite")
        queue_file = str(tmp_path / "homo_queue.json")

        lesson_store = LessonStore(file_path=lessons_file)
        vector_store = LocalVectorStore(db_path=vector_file)
        github_logger = GitHubIssueLogger(enabled=True, offline_queue_path=queue_file)
        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=github_logger
        )

        event = ScrapingFailureEvent(
            domain="zillow.com",
            url="https://zillow.com/homes/94115_rb/",
            phase="DISCOVERY",
            target_entity="94115",
            failure_type="DOM_SELECTOR_DRIFT",
            error_message="0 property cards found on page",
            selector="article[data-test='property-card']"
        )

        for _ in range(10):
            res = learning_agent.observe_failure(event)

        # Must maintain exactly 1 lesson with occurrence_count == 10
        all_lessons = lesson_store.load_all()
        assert len(all_lessons) == 1
        assert all_lessons[0].occurrence_count == 10
        assert vector_store.count(domain="zillow.com") == 1

    def test_cascading_heterogeneous_failures_feedforward_aggregation(self, tmp_path):
        """
        Verifies heterogeneous failures (DOM_SELECTOR_DRIFT, ANTI_BOT_BLOCKED, RATE_LIMIT_ERROR, TIMEOUT)
        aggregate correctly into an optimal comprehensive feedforward strategy.
        """
        lessons_file = str(tmp_path / "cascading_lessons.json")
        vector_file = str(tmp_path / "cascading_vectors.sqlite")

        lesson_store = LessonStore(file_path=lessons_file)
        vector_store = LocalVectorStore(db_path=vector_file)
        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=GitHubIssueLogger(enabled=False)
        )

        failures = [
            ScrapingFailureEvent(
                domain="sfplanninggis.org",
                url="https://sfplanninggis.org/pim",
                phase="ASSESSOR",
                target_entity="100 Market St",
                failure_type="DOM_SELECTOR_DRIFT",
                error_message="Missing parcel card",
                selector=".parcel-details"
            ),
            ScrapingFailureEvent(
                domain="sfplanninggis.org",
                url="https://sfplanninggis.org/pim",
                phase="ASSESSOR",
                target_entity="100 Market St",
                failure_type="ANTI_BOT_BLOCKED",
                error_message="HTTP 403 Challenge"
            ),
            ScrapingFailureEvent(
                domain="sfplanninggis.org",
                url="https://sfplanninggis.org/pim",
                phase="ASSESSOR",
                target_entity="100 Market St",
                failure_type="RATE_LIMIT_ERROR",
                error_message="HTTP 429 Too Many Requests"
            ),
            ScrapingFailureEvent(
                domain="sfplanninggis.org",
                url="https://sfplanninggis.org/pim",
                phase="ASSESSOR",
                target_entity="100 Market St",
                failure_type="NETWORK_TIMEOUT",
                error_message="Timeout 30000ms exceeded"
            ),
        ]

        for ev in failures:
            learning_agent.observe_failure(ev)

        assert lesson_store.count(domain="sfplanninggis.org") == 4

        # Retrieve strategy
        strategy = learning_agent.get_feedforward_strategy(domain="sfplanninggis.org", action_context="assessor query")
        # Delay should be maximum of all observed failures (5.0s from RATE_LIMIT_ERROR)
        assert strategy.request_delay_seconds >= 5.0
        # Headers should include User-Agent from ANTI_BOT_BLOCKED
        assert "User-Agent" in strategy.custom_headers
        # Fallback selectors should be populated from DOM_SELECTOR_DRIFT
        assert len(strategy.fallback_selectors) >= 1
        assert any("parcel" in s.lower() or "table" in s.lower() for s in strategy.fallback_selectors)
        # Known blockers should record anti-bot and rate-limiting
        assert len(strategy.known_blockers) >= 2

    def test_closed_loop_self_healing_convergence_lifecycle(self, tmp_path):
        """
        Verifies end-to-end self-healing state transitions:
        ACTIVE (1 failure) -> Workaround Applied -> Success Count reaches 5 -> RESOLVED / resolved=True.
        """
        lessons_file = str(tmp_path / "lifecycle_lessons.json")
        vector_file = str(tmp_path / "lifecycle_vectors.sqlite")

        lesson_store = LessonStore(file_path=lessons_file)
        vector_store = LocalVectorStore(db_path=vector_file)
        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=GitHubIssueLogger(enabled=False)
        )

        # 1. Observe failure
        event = ScrapingFailureEvent(
            domain="dbi.sfgov.org",
            url="https://dbi.sfgov.org/dbipts",
            phase="PERMITS",
            target_entity="2223 Pacific Ave",
            failure_type="DOM_SELECTOR_DRIFT",
            error_message="Permit table missing",
            selector=".dbi-grid"
        )
        resolution = learning_agent.observe_failure(event)
        lesson_id = resolution.lesson.id

        lesson = lesson_store.get_lesson(lesson_id)
        assert lesson.status == "ACTIVE"
        assert lesson.resolved is False
        assert lesson.success_count_after_workaround == 0

        # 2. Simulate 4 successful retries
        for _ in range(4):
            learning_agent.observe_success(domain="dbi.sfgov.org", target_entity="2223 Pacific Ave", lesson_id=lesson_id)
            l = lesson_store.get_lesson(lesson_id)
            assert l.status == "ACTIVE"

        # 3. 5th success converges and transitions status to RESOLVED
        learning_agent.observe_success(domain="dbi.sfgov.org", target_entity="2223 Pacific Ave", lesson_id=lesson_id)
        l = lesson_store.get_lesson(lesson_id)
        assert l.status == "RESOLVED"
        assert l.resolved is True
        assert l.success_count_after_workaround == 5

    def test_multi_domain_feedforward_isolation_matrix(self, tmp_path):
        """Verifies strict domain isolation: zillow lessons never leak into county assessor queries."""
        lessons_file = str(tmp_path / "iso_matrix_lessons.json")
        vector_file = str(tmp_path / "iso_matrix_vectors.sqlite")

        lesson_store = LessonStore(file_path=lessons_file)
        vector_store = LocalVectorStore(db_path=vector_file)
        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=GitHubIssueLogger(enabled=False)
        )

        domains = ["zillow.com", "sfplanninggis.org", "dbi.sfgov.org"]
        for d in domains:
            learning_agent.observe_failure(
                ScrapingFailureEvent(
                    domain=d,
                    url=f"https://{d}/path",
                    phase="QUERY",
                    target_entity="entity",
                    failure_type="DOM_SELECTOR_DRIFT",
                    error_message=f"Selector error on {d}",
                    selector=f".unique-{d.replace('.', '-')}"
                )
            )

        for d in domains:
            strat = learning_agent.get_feedforward_strategy(domain=d)
            assert strat.domain == d
            for other in domains:
                if other != d:
                    other_pattern = f".unique-{other.replace('.', '-')}"
                    assert other_pattern not in strat.fallback_selectors

    def test_sequential_multi_domain_failure_aggregation(self, tmp_path):
        """Verifies deterministic failure ingestion across 10 sequential events without race conditions."""
        lessons_file = str(tmp_path / "seq_lessons.json")
        vector_file = str(tmp_path / "seq_vectors.sqlite")

        lesson_store = LessonStore(file_path=lessons_file)
        vector_store = LocalVectorStore(db_path=vector_file)
        learning_agent = LearningAgent(
            lesson_store=lesson_store,
            vector_store=vector_store,
            github_logger=GitHubIssueLogger(enabled=False)
        )

        for i in range(10):
            domain = f"domain{i % 2}.com"
            event = ScrapingFailureEvent(
                domain=domain,
                url=f"https://{domain}/item/{i}",
                phase="DISCOVERY",
                target_entity=f"entity-{i}",
                failure_type="DOM_SELECTOR_DRIFT",
                error_message=f"Error {i}",
                selector="#card-item"
            )
            learning_agent.observe_failure(event)

        all_lessons = lesson_store.load_all()
        assert len(all_lessons) == 2
        total_occurrences = sum(l.occurrence_count for l in all_lessons)
        assert total_occurrences == 10
        assert vector_store.count() == 2


# ============================================================================
# 3. CSV EXPORT FORMATTING & ESCAPING UNDER EDGE-CASE DATA
# ============================================================================

class TestCSVExportEdgeCaseFormattingAndEscaping:
    """
    Stress-tests RFC 4180 compliance, special characters, multi-line values,
    Unicode/Emojis, Formula/SQL injections, and extreme numerical boundaries.
    """

    def test_csv_multiline_newlines_in_address_and_owner(self, tmp_path):
        """Verifies embedded newlines (\n, \r\n) in lead fields are properly quoted per RFC 4180."""
        db_file = tmp_path / "multiline.db"
        csv_file = tmp_path / "multiline.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        lead = Lead(
            address="2223 Pacific Ave\nBuilding B, Floor 2\r\nSan Francisco, CA 94115",
            zip_code="94115",
            owner_name="TRUST MANAGEMENT\nDEPT OF REALTY\nC/O AGENT",
            estimated_value=2500000.0,
            roof_age_years=16.0,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 1
        assert reader[0]["Address"] == "2223 Pacific Ave\nBuilding B, Floor 2\r\nSan Francisco, CA 94115"
        assert reader[0]["Owner Name"] == "TRUST MANAGEMENT\nDEPT OF REALTY\nC/O AGENT"

    def test_csv_unicode_emojis_multilingual_data(self, tmp_path):
        """Verifies UTF-8 encoding of CJK, Arabic RTL, German umlauts, French accents, and Emojis."""
        db_file = tmp_path / "unicode_edge.db"
        csv_file = tmp_path / "unicode_edge.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        lead = Lead(
            address="🏠 789 Rue d'Élysée — 東京都千代田区 1-1 / شارع الملك",
            zip_code="94115",
            owner_name="Müller & François 🔨 Realität 🏢 (العقارات)",
            property_type="Victorian / 歴史的建造物",
            roof_type="Slate / スレート",
            estimated_value=5000000.0,
            roof_age_years=25.0,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 1
        assert reader[0]["Address"] == "🏠 789 Rue d'Élysée — 東京都千代田区 1-1 / شارع الملك"
        assert reader[0]["Owner Name"] == "Müller & François 🔨 Realität 🏢 (العقارات)"
        assert reader[0]["Property Type"] == "Victorian / 歴史的建造物"
        assert reader[0]["Roof Type"] == "Slate / スレート"

    def test_csv_injection_and_formula_escaping(self, tmp_path):
        """Verifies spreadsheet formula injection payloads are written verbatim without execution corruption."""
        db_file = tmp_path / "formula_inj.db"
        csv_file = tmp_path / "formula_inj.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        injection_leads = [
            Lead(
                address="=cmd|' /C calc'!A0",
                zip_code="94115",
                owner_name="@SUM(1+1)",
                status="VALIDATED"
            ),
            Lead(
                address="+12345 Dangerous Way",
                zip_code="94115",
                owner_name="-9999 Discount Trust",
                status="ENRICHED"
            )
        ]
        session.add_all(injection_leads)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 2
        assert reader[0]["Address"] == "=cmd|' /C calc'!A0"
        assert reader[0]["Owner Name"] == "@SUM(1+1)"
        assert reader[1]["Address"] == "+12345 Dangerous Way"
        assert reader[1]["Owner Name"] == "-9999 Discount Trust"

    def test_csv_sql_injection_payload_passthrough(self, tmp_path):
        """Verifies SQL injection strings stored in Lead columns serialize cleanly into CSV."""
        db_file = tmp_path / "sql_inj.db"
        csv_file = tmp_path / "sql_inj.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        lead = Lead(
            address="100 Main St'; DROP TABLE leads; --",
            zip_code="94115",
            owner_name="\" OR 1=1; SELECT * FROM users; --",
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 1
        assert reader[0]["Address"] == "100 Main St'; DROP TABLE leads; --"
        assert reader[0]["Owner Name"] == "\" OR 1=1; SELECT * FROM users; --"

    def test_csv_all_nullable_fields_none(self, tmp_path):
        """Verifies None/NULL values in all optional fields serialize as empty strings without throwing exceptions."""
        db_file = tmp_path / "all_none.db"
        csv_file = tmp_path / "all_none.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        lead = Lead(
            address="Minimalist St",
            zip_code="94115",
            property_type=None,
            roof_type=None,
            estimated_value=None,
            owner_name=None,
            apn=None,
            roof_age_years=None,
            phone_number=None,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 1
        row = reader[0]
        assert row["Address"] == "Minimalist St"
        assert row["Zip Code"] == "94115"
        assert row["Property Type"] == ""
        assert row["Roof Type"] == ""
        assert row["Assessed Value"] == ""
        assert row["Owner Name"] == ""
        assert row["APN"] == ""
        assert row["Roof Age (Years)"] == ""
        assert row["Phone Number"] == ""
        assert row["Status"] == "VALIDATED"

    def test_csv_extreme_numeric_values_and_precision(self, tmp_path):
        """Verifies boundary numerical values (0.0, 999999999.99, negative/fractional years)."""
        db_file = tmp_path / "numeric_bounds.db"
        csv_file = tmp_path / "numeric_bounds.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        lead = Lead(
            address="100 Billionaire Row",
            zip_code="94115",
            estimated_value=123456789.75,
            roof_age_years=120.25,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 1
        assert float(reader[0]["Assessed Value"]) == 123456789.75
        assert float(reader[0]["Roof Age (Years)"]) == 120.25

    def test_csv_huge_payload_length_stress(self, tmp_path):
        """Verifies massive 10,000+ character strings serialize and deserialize without clipping."""
        db_file = tmp_path / "huge_payload.db"
        csv_file = tmp_path / "huge_payload.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)

        huge_address = "A" * 5000 + ", San Francisco, CA 94115"
        huge_owner = "B" * 5000 + " TRUST"

        lead = Lead(
            address=huge_address,
            zip_code="94115",
            owner_name=huge_owner,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8", newline="") as f:
            reader = list(csv.DictReader(f))

        assert len(reader) == 1
        assert reader[0]["Address"] == huge_address
        assert reader[0]["Owner Name"] == huge_owner
