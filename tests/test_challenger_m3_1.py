"""
tests/test_challenger_m3_1.py

Adversarial Stress Test Suite for Milestone 3 Live Test Harness and Sockets.
Tests:
1. Live Inference Server Concurrency, Burst Traffic, and Fault Injection.
2. Live HTML Server Concurrent Requests, Large Payloads, and Route Isolation.
3. SQLite Database Multi-Threaded Isolation, Rollback Integrity, and Rapid Fixture Lifecycles.
4. Extractor ↔ Live Server High-Concurrency Integration & Resiliency.
"""

import os
import sys
import time
import json
import socket
import tempfile
import threading
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date

import pytest
import requests
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError

from db.database import Base, Lead, init_db, get_session
from agents.extractor import LocalLLMExtractor, PropertyExtraction, CountyPermitExtraction
from tests.conftest import BackgroundServer, build_inference_app, build_html_fixture_app, FIXTURES_DIR


class TestLiveInferenceServerStress:
    """Stress-tests the Starlette live inference server under heavy concurrent load and fault injection."""

    def test_concurrent_completions_burst_50_threads(self, live_inference_server):
        """Executes 50 simultaneous chat completion requests across a thread pool."""
        url = f"{live_inference_server}/chat/completions"
        payload = {
            "model": "nvidia/llama-3.1-nemotron-70b-instruct",
            "messages": [
                {"role": "system", "content": "You are a real estate extraction engine."},
                {"role": "user", "content": "Property: 2223 Pacific Ave, San Francisco, CA 94115. Victorian single family home, 4 bed 3.5 bath, ,370,000."}
            ]
        }

        def make_request(idx):
            start = time.time()
            resp = requests.post(url, json=payload, timeout=5.0)
            elapsed = time.time() - start
            return resp.status_code, resp.json(), elapsed

        results = []
        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = [executor.submit(make_request, i) for i in range(50)]
            for f in as_completed(futures):
                results.append(f.result())

        assert len(results) == 50
        status_codes = [r[0] for r in results]
        latencies = [r[2] for r in results]
        
        assert all(code == 200 for code in status_codes), f"Non-200 status codes observed: {status_codes}"
        assert max(latencies) < 3.0, f"Max latency too high: {max(latencies):.3f}s"
        
        for _, body, _ in results:
            content = body["choices"][0]["message"]["content"]
            data = json.loads(content)
            assert "2223 Pacific Ave" in data["address"]
            assert data["roof_type"] == "Victorian"

    def test_concurrent_fault_injection_matrix(self, live_inference_server):
        """Tests concurrent execution mixing valid, malformed, 429, 500, thinking tokens, and markdown fenced requests."""
        url = f"{live_inference_server}/chat/completions"

        scenarios = [
            ("valid_zillow", {"x-test-behavior": ""}, "2223 Pacific Ave", 200),
            ("valid_county", {"x-test-behavior": ""}, "municipal county assessor APN 0582-014", 200),
            ("malformed_header", {"x-test-behavior": "malformed_json"}, "2223 Pacific Ave", 200),
            ("rate_limit_header", {"x-test-behavior": "rate_limit_429"}, "2223 Pacific Ave", 429),
            ("server_error_header", {"x-test-behavior": "server_error_500"}, "2223 Pacific Ave", 500),
            ("thinking_tokens", {"x-test-behavior": "thinking_tokens"}, "2223 Pacific Ave", 200),
            ("markdown_fenced", {"x-test-behavior": "markdown_fenced"}, "2223 Pacific Ave", 200),
        ] * 10  # 70 total requests

        def fire_scenario(scenario_tuple):
            name, headers, prompt, expected_status = scenario_tuple
            payload = {
                "model": "test-model",
                "messages": [{"role": "user", "content": prompt}]
            }
            resp = requests.post(url, json=payload, headers=headers, timeout=5.0)
            return name, resp.status_code, resp.text, expected_status

        outcomes = []
        with ThreadPoolExecutor(max_workers=15) as executor:
            futures = [executor.submit(fire_scenario, s) for s in scenarios]
            for f in as_completed(futures):
                outcomes.append(f.result())

        assert len(outcomes) == 70
        mismatches = [o for o in outcomes if o[1] != o[3]]
        assert len(mismatches) == 0, f"Status code mismatches under concurrent fault injection: {mismatches}"

    def test_invalid_http_body_handling(self, live_inference_server):
        """Sends non-JSON and corrupt raw byte streams to the chat completions endpoint."""
        url = f"{live_inference_server}/chat/completions"
        headers = {"Content-Type": "application/json"}

        # Raw non-JSON string
        resp = requests.post(url, data="this is not json at all", headers=headers, timeout=5.0)
        assert resp.status_code == 400
        assert "invalid_request_error" in resp.text

        # Empty body
        resp = requests.post(url, data="", headers=headers, timeout=5.0)
        assert resp.status_code == 400

    def test_oversized_payload_stress(self, live_inference_server):
        """Sends 100KB+ large text prompts to test memory and token counting stability."""
        url = f"{live_inference_server}/chat/completions"
        huge_text = "2223 Pacific Ave, San Francisco, CA 94115. " * 2000  # ~90KB
        payload = {
            "model": "nvidia/llama-3.1-nemotron-70b-instruct",
            "messages": [{"role": "user", "content": huge_text}]
        }
        resp = requests.post(url, json=payload, timeout=5.0)
        assert resp.status_code == 200
        data = resp.json()
        assert data["usage"]["prompt_tokens"] > 1000
        content = json.loads(data["choices"][0]["message"]["content"])
        assert "2223 Pacific Ave" in content["address"]

    def test_server_lifecycle_and_restart_resilience(self):
        """Tests BackgroundServer start/stop/restart cleanly binds and unbinds socket."""
        app = build_inference_app()
        test_port = 8019
        server = BackgroundServer(app=app, host="127.0.0.1", port=test_port, expected_service="local-llm-loopback")
        
        for iteration in range(3):
            server.start()
            assert server.is_healthy()
            
            # Verify HTTP works
            resp = requests.get(f"http://127.0.0.1:{test_port}/health", timeout=2.0)
            assert resp.status_code == 200
            assert resp.json()["status"] == "healthy"
            
            server.stop()
            time.sleep(0.1)
            assert not server.is_healthy()


class TestLiveHTMLServerStress:
    """Stress-tests the Starlette static HTML fixture server under high concurrency and diverse routes."""

    def test_concurrent_html_route_requests_60_threads(self, live_html_server):
        """Tests 60 simultaneous requests across all supported routes."""
        routes = [
            ("/health", 200),
            ("/homes/94115_rb/", 200),
            ("/homedetails/2223-Pacific-Ave", 200),
            ("/property/2223-Pacific-Ave", 200),
            ("/pim", 200),
            ("/dbipts", 200),
            ("/blocked", 403),
            ("/rate_limited", 429),
            ("/static/zillow_property.html", 200),
            ("/nonexistent_route_404", 404),
        ] * 6  # 60 requests

        def fetch_route(route_tuple):
            path, expected_status = route_tuple
            url = f"{live_html_server}{path}"
            resp = requests.get(url, timeout=3.0)
            return path, resp.status_code, expected_status

        results = []
        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = [executor.submit(fetch_route, r) for r in routes]
            for f in as_completed(futures):
                results.append(f.result())

        assert len(results) == 60
        mismatches = [r for r in results if r[1] != r[2]]
        assert len(mismatches) == 0, f"Route status mismatches: {mismatches}"

    def test_rapid_sequential_get_requests(self, live_html_server):
        """Executes 100 rapid sequential GET requests verifying no connection leak or latency degradation."""
        url = f"{live_html_server}/homedetails/2223-Pacific-Ave"
        session = requests.Session()
        latencies = []
        for _ in range(100):
            t0 = time.time()
            resp = session.get(url, timeout=2.0)
            latencies.append(time.time() - t0)
            assert resp.status_code == 200
            assert "2223 Pacific Ave" in resp.text
        
        avg_latency = sum(latencies) / len(latencies)
        assert avg_latency < 0.05, f"Average latency too slow: {avg_latency:.4f}s"


class TestSQLiteDatabaseIsolationAndTransactionStress:
    """Stress-tests SQLite transaction isolation, rollback guarantees, and parallel session access."""

    def test_multi_threaded_isolated_writes(self, tmp_path):
        """Runs 20 worker threads concurrently writing distinct records to separate database sessions."""
        db_path = tmp_path / "stress_leads.db"
        db_url = f"sqlite:///{db_path}"
        engine = create_engine(db_url, connect_args={"check_same_thread": False})
        Base.metadata.create_all(engine)
        SessionFactory = sessionmaker(bind=engine)

        def write_lead(worker_id):
            session = SessionFactory()
            try:
                lead = Lead(
                    address=f"{worker_id} Stress Lane, San Francisco, CA 94115",
                    zip_code="94115",
                    property_type="Single-Family",
                    roof_type="Tile",
                    estimated_value=1500000.0 + worker_id * 1000,
                    status="DISCOVERED"
                )
                session.add(lead)
                session.commit()
                return True
            except Exception as e:
                session.rollback()
                return False
            finally:
                session.close()

        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(write_lead, i) for i in range(20)]
            results = [f.result() for f in as_completed(futures)]

        assert all(results)
        
        # Verify total committed count in fresh session
        verify_session = SessionFactory()
        count = verify_session.query(Lead).count()
        verify_session.close()
        engine.dispose()
        assert count == 20

    def test_transaction_rollback_isolation_under_concurrency(self, tmp_path):
        """Verifies that failed transactions rollback cleanly without leaving phantom records or locking DB."""
        db_path = tmp_path / "rollback_leads.db"
        engine = create_engine(f"sqlite:///{db_path}", connect_args={"check_same_thread": False})
        Base.metadata.create_all(engine)
        SessionFactory = sessionmaker(bind=engine)

        # Pre-seed 1 valid lead
        s0 = SessionFactory()
        s0.add(Lead(address="100 Main St", zip_code="94105", status="VALIDATED"))
        s0.commit()
        s0.close()

        def try_duplicate_write(worker_id):
            session = SessionFactory()
            try:
                # Attempt to insert identical address which triggers unique constraint error
                bad_lead = Lead(address="100 Main St", zip_code="94105", status="DISCOVERED")
                session.add(bad_lead)
                session.commit()
                return "COMMITTED"
            except IntegrityError:
                session.rollback()
                return "ROLLED_BACK"
            finally:
                session.close()

        with ThreadPoolExecutor(max_workers=8) as executor:
            futures = [executor.submit(try_duplicate_write, i) for i in range(16)]
            results = [f.result() for f in as_completed(futures)]

        assert all(r == "ROLLED_BACK" for r in results)

        # Verify DB still consistent and contains only the original record
        verify_session = SessionFactory()
        leads = verify_session.query(Lead).all()
        assert len(leads) == 1
        assert leads[0].status == "VALIDATED"
        verify_session.close()
        engine.dispose()

    def test_rapid_fixture_lifecycle_churn(self, tmp_path):
        """Simulates 50 rapid sequential fixture creations and disposals to test SQLite file descriptor cleanup."""
        for i in range(50):
            db_file = tmp_path / f"churn_{i}.db"
            engine = create_engine(f"sqlite:///{db_file}", connect_args={"check_same_thread": False})
            Base.metadata.create_all(engine)
            Session = sessionmaker(bind=engine)
            session = Session()
            
            lead = Lead(address=f"{i} Churn St", zip_code="94115", estimated_value=1000000.0)
            session.add(lead)
            session.commit()
            
            assert session.query(Lead).count() == 1
            session.close()
            engine.dispose()
            
            # File should exist and be readable
            assert os.path.exists(db_file)


class TestExtractorLiveServerIntegrationStress:
    """Stress-tests LocalLLMExtractor interacting with live_inference_server under concurrency."""

    def test_concurrent_extractor_property_extractions(self, live_inference_server):
        """Runs 25 concurrent LocalLLMExtractor instances against live Starlette server."""
        extractor = LocalLLMExtractor(base_url=live_inference_server)

        def extract_task(idx):
            dom_text = f"Property at 2223 Pacific Ave, San Francisco. Price ,370,000. Built 1908. Victorian slate roof. 4 bed 3.5 bath. Worker {idx}."
            return extractor.extract_property_details(dom_text)

        results = []
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(extract_task, i) for i in range(25)]
            for f in as_completed(futures):
                results.append(f.result())

        assert len(results) == 25
        for res in results:
            assert isinstance(res, PropertyExtraction)
            assert "2223 Pacific Ave" in res.address
            assert res.roof_type == "Victorian"
            assert res.estimated_value == 4370000.0

    def test_concurrent_extractor_county_extractions(self, live_inference_server):
        """Runs 25 concurrent county permit extractions against live Starlette server."""
        extractor = LocalLLMExtractor(base_url=live_inference_server)

        def extract_county_task(idx):
            text_context = f"Municipal Assessor & Permit record for 2223 Pacific Ave. APN 0582-014. Roof replacement in 2008. Worker {idx}."
            return extractor.extract_county_permit_details(text_context)

        results = []
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(extract_county_task, i) for i in range(25)]
            for f in as_completed(futures):
                results.append(f.result())

        assert len(results) == 25
        for res in results:
            assert isinstance(res, CountyPermitExtraction)
            assert res.apn == "0582-014"
            assert res.last_roof_permit_date == "2008-05-14"
            assert len(res.permit_history) >= 1
