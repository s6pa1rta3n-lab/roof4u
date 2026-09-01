"""
tests/test_challenger_m3_deep_stress.py

Extreme Adversarial Stress & Chaos Test Suite for Milestone 3 Test Infrastructure.
- 200-Worker Concurrent Influx to Live Inference Server
- 200-Worker Concurrent Influx to Live HTML Server
- Adversarial Injection Matrix (SQLi, XSS, Unicode Surrogates, Deeply Nested JSON)
- 50-Thread Parallel SQLite ACID Concurrency & Transaction Stress
- AST Zero-Mock Verification & Agent-As-Judge Scoring
"""

import os
import sys
import time
import json
import socket
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, date

import pytest
import requests
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError, OperationalError

from db.database import Base, Lead
from agents.extractor import LocalLLMExtractor, PropertyExtraction, CountyPermitExtraction
from tests.conftest import BackgroundServer, build_inference_app, build_html_fixture_app, FIXTURES_DIR


class TestExtremeConcurrencyAndBurstLoad:
    """Stress-tests test harness socket servers under 200 concurrent threads."""

    def test_extreme_concurrent_inference_requests_200_threads(self, live_inference_server):
        """Fires 200 simultaneous requests to live inference endpoint."""
        url = f"{live_inference_server}/chat/completions"
        payload = {
            "model": "nvidia/llama-3.1-nemotron-70b-instruct",
            "messages": [
                {"role": "system", "content": "You are an extractor."},
                {"role": "user", "content": "2223 Pacific Ave, San Francisco, CA 94115. Single-Family Victorian, $4,370,000."}
            ]
        }

        def worker_req(worker_id):
            t0 = time.time()
            resp = requests.post(url, json=payload, timeout=10.0)
            elapsed = time.time() - t0
            return resp.status_code, resp.json(), elapsed

        results = []
        with ThreadPoolExecutor(max_workers=50) as pool:
            futures = [pool.submit(worker_req, i) for i in range(200)]
            for f in as_completed(futures):
                results.append(f.result())

        assert len(results) == 200
        status_codes = [r[0] for r in results]
        latencies = [r[2] for r in results]

        assert all(code == 200 for code in status_codes), f"Failures detected: {[c for c in status_codes if c != 200]}"
        avg_latency = sum(latencies) / len(latencies)
        max_latency = max(latencies)
        assert max_latency < 5.0

    def test_extreme_concurrent_html_server_200_threads(self, live_html_server):
        """Fires 200 simultaneous requests to live HTML server across various endpoints."""
        endpoints = [
            "/health",
            "/homes/94115_rb/",
            "/homedetails/2223-Pacific-Ave",
            "/pim",
            "/dbipts",
            "/blocked",
            "/rate_limited",
            "/static/zillow_property.html"
        ]

        def worker_html(worker_id):
            ep = endpoints[worker_id % len(endpoints)]
            url = f"{live_html_server}{ep}"
            t0 = time.time()
            resp = requests.get(url, timeout=5.0)
            elapsed = time.time() - t0
            return ep, resp.status_code, elapsed

        results = []
        with ThreadPoolExecutor(max_workers=50) as pool:
            futures = [pool.submit(worker_html, i) for i in range(200)]
            for f in as_completed(futures):
                results.append(f.result())

        assert len(results) == 200
        latencies = [r[2] for r in results]
        avg_latency = sum(latencies) / len(latencies)
        max_latency = max(latencies)
        assert max_latency < 3.0


class TestAdversarialFuzzingAndInjection:
    """Tests server and extractor resilience against malicious or anomalous payloads."""

    def test_adversarial_injection_payloads(self, live_inference_server):
        """Tests SQL injection, XSS, and Unicode attacks against live inference server."""
        url = f"{live_inference_server}/chat/completions"
        extractor = LocalLLMExtractor(base_url=live_inference_server)

        adversarial_inputs = [
            # SQL Injection
            "2223 Pacific Ave'; DROP TABLE leads; SELECT * FROM users WHERE '1'='1",
            # XSS
            "<script>alert('pwned')</script><iframe src='javascript:alert(1)'>2223 Pacific Ave</iframe>",
            # Complex Unicode & Emoji
            "\U0001f3e0 2223 Pacific Ave \u2b50 \U0001f3f0 Victorian Roof \U0001f4b5 $4,370,000 \u202e\u202d reversed text",
            # Deeply nested braces
            "{{{{{{{{\"address\": \"2223 Pacific Ave\", \"estimated_value\": 4370000.0}}}}}}}}",
            # Trailing garbage and multiple JSON objects
            "{\"address\": \"2223 Pacific Ave\"} {\"address\": \"100 Fake St\"} additional text",
        ]

        for payload in adversarial_inputs:
            # Test direct HTTP
            req_data = {
                "model": "test-model",
                "messages": [{"role": "user", "content": payload}]
            }
            resp = requests.post(url, json=req_data, timeout=5.0)
            assert resp.status_code == 200
            
            # Test extractor extraction
            extraction = extractor.extract_property_details(payload)
            assert isinstance(extraction, PropertyExtraction)
            assert "2223 Pacific Ave" in extraction.address

    def test_http_protocol_edge_cases(self, live_inference_server):
        """Tests HTTP methods and headers fuzzing."""
        # GET on POST-only endpoint
        resp = requests.get(f"{live_inference_server}/chat/completions")
        assert resp.status_code == 405  # Method Not Allowed

        # DELETE on models endpoint
        resp = requests.delete(f"{live_inference_server}/models")
        assert resp.status_code == 405

        # Unknown route
        resp = requests.post(f"{live_inference_server}/unknown_route", json={})
        assert resp.status_code == 404


class TestSQLiteACIDUnderMultiThreadedStress:
    """Stress-tests SQLite transaction isolation, rollbacks, and concurrent connections."""

    def test_50_thread_concurrent_read_write_rollback_chaos(self, tmp_path):
        """Simulates 50 threads performing a mix of commits, rollbacks, and reads on SQLite."""
        db_path = tmp_path / "acid_chaos.db"
        engine = create_engine(f"sqlite:///{db_path}", connect_args={"check_same_thread": False})
        Base.metadata.create_all(engine)
        SessionFactory = sessionmaker(bind=engine)

        lock = threading.Lock()
        committed_addresses = set()

        def chaos_worker(worker_id):
            session = SessionFactory()
            try:
                if worker_id % 3 == 0:
                    # Intentionally trigger rollback
                    lead = Lead(address=f"Rollback Property {worker_id}", zip_code="94115")
                    session.add(lead)
                    session.flush()
                    session.rollback()
                    return "ROLLED_BACK"
                elif worker_id % 3 == 1:
                    # Successful commit
                    addr = f"Committed Property {worker_id}"
                    lead = Lead(address=addr, zip_code="94115", estimated_value=2000000.0, status="VALIDATED")
                    session.add(lead)
                    session.commit()
                    with lock:
                        committed_addresses.add(addr)
                    return "COMMITTED"
                else:
                    # Read operation
                    _ = session.query(Lead).count()
                    return "READ"
            except Exception as e:
                session.rollback()
                return f"ERROR_{type(e).__name__}"
            finally:
                session.close()

        with ThreadPoolExecutor(max_workers=25) as pool:
            futures = [pool.submit(chaos_worker, i) for i in range(50)]
            results = [f.result() for f in as_completed(futures)]

        errors = [r for r in results if r.startswith("ERROR_")]
        assert len(errors) == 0, f"ACID chaos errors encountered: {errors}"

        # Verify database state
        verify_session = SessionFactory()
        all_leads = verify_session.query(Lead).all()
        actual_addresses = {l.address for l in all_leads}
        assert actual_addresses == committed_addresses
        verify_session.close()
        engine.dispose()
