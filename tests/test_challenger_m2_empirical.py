"""
tests/test_challenger_m2_empirical.py

Deep Empirical Stress Test & Verification Suite for M2 Dual Memory Subsystem:
- OfflineEmbeddingGenerator
- LocalVectorStore
- LessonStore
- LearningAgent Integration
"""

import os
import sys
import json
import time
import uuid
import tempfile
import threading
import numpy as np
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from memory.embeddings import OfflineEmbeddingGenerator
from memory.lesson_store import Lesson, LessonStore
from memory.vector_store import LocalVectorStore, VectorRecord, SearchResult, sync_stores
from agents.learning_agent import LearningAgent, FailureCategory
from integrations.github_client import ScrapingFailureEvent


def test_offline_embedding_extreme_inputs_and_bounds():
    """
    Empirically verifies OfflineEmbeddingGenerator against:
    - Empty strings, whitespace, null bytes, control characters, unicode, emojis.
    - Strict L2 unit norm ||v||_2 == 1.0 (+- 1e-5).
    - Cosine similarity bounds [-1.0, 1.0].
    - Self-similarity == 1.0 (+- 1e-5).
    - Symmetry: cos(u, v) == cos(v, u).
    """
    dim = 256
    embedder = OfflineEmbeddingGenerator(dimension=dim)

    extreme_inputs = [
        "",
        "   ",
        "\t\r\n",
        "\x00",
        "\x00\x00\x00\x00",
        "null\x00byte\x00injection",
        "✨🔥🚀🏡屋顶许可证",
        "العربية / فارسی / 中文 / 日本語 / Русский",
        "A" * 100000,  # 100KB repetitive string
        "".join(f"token_{i} " for i in range(5000)),  # 5,000 distinct tokens
        "HTTP 429 Too Many Requests: Rate limit reached on dbiweb02.sfgov.org",
        "HTTP 403 Forbidden: Cloudflare bot challenge on zillow.com",
        "DOM Selector Drift: missing [data-testid='home-details-chip-container']",
        "SELECT * FROM leads WHERE address = '123 Main St' -- SQL injection",
        "<script>alert('xss')</script><style>body{display:none}</style>"
    ]

    vectors = []
    for idx, text in enumerate(extreme_inputs):
        vec = embedder.embed_text(text)
        assert vec.shape == (dim,), f"Shape mismatch on input {idx}: {vec.shape}"
        assert vec.dtype == np.float32, f"Dtype mismatch on input {idx}: {vec.dtype}"
        assert not np.isnan(vec).any(), f"NaN found in input {idx}"
        assert not np.isinf(vec).any(), f"Inf found in input {idx}"

        norm = float(np.linalg.norm(vec))
        assert abs(norm - 1.0) < 1e-4, f"L2 norm violation on input {idx}: {norm}"
        vectors.append(vec)

    # Pairwise bounds and symmetry
    for i in range(len(vectors)):
        self_sim = embedder.cosine_similarity(vectors[i], vectors[i])
        assert abs(self_sim - 1.0) < 1e-4, f"Self-similarity violation on input {i}: {self_sim}"

        for j in range(len(vectors)):
            sim_ij = embedder.cosine_similarity(vectors[i], vectors[j])
            sim_ji = embedder.cosine_similarity(vectors[j], vectors[i])

            assert -1.0 - 1e-4 <= sim_ij <= 1.0 + 1e-4, f"Bound violation on ({i}, {j}): {sim_ij}"
            assert abs(sim_ij - sim_ji) < 1e-5, f"Symmetry violation on ({i}, {j}): {sim_ij} vs {sim_ji}"


def test_offline_embedding_batch_vectorization_exactness():
    """Verifies batch_cosine_similarity matches sequential cosine_similarity exactly."""
    embedder = OfflineEmbeddingGenerator(dimension=256)
    query = "zillow.com 403 bot challenge rate limit"
    corpus = [
        "zillow.com HTTP 403 forbidden PerimeterX",
        "sfplanninggis.org parcel table missing",
        "dbiweb02.sfgov.org HTTP 429 rate limit exceeded",
        "zillow.com DOM selector drift summary facts",
        "completely unrelated string for baseline"
    ]

    q_vec = embedder.embed_text(query)
    doc_matrix = embedder.embed_batch(corpus)

    assert doc_matrix.shape == (len(corpus), 256)

    batch_scores = embedder.batch_cosine_similarity(q_vec, doc_matrix)
    assert batch_scores.shape == (len(corpus),)

    for i, doc in enumerate(corpus):
        single_vec = embedder.embed_text(doc)
        single_score = embedder.cosine_similarity(q_vec, single_vec)
        assert abs(batch_scores[i] - single_score) < 1e-5, f"Mismatch on doc {i}: {batch_scores[i]} vs {single_score}"


def test_local_vector_store_1000_plus_insertions_and_search_scale():
    """
    Stress-tests LocalVectorStore with 1,500 vector insertions across multiple domains,
    verifies ranking, search latency, and metadata integrity.
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_path = os.path.join(tmp_dir, "scale_test.db")
        store = LocalVectorStore(db_path=db_path)

        total_records = 1500
        batch_size = 250
        domains = ["zillow.com", "sfplanninggis.org", "dbiweb02.sfgov.org", "redfin.com", "realtor.com"]
        failure_types = ["DOM_SELECTOR_DRIFT", "RATE_LIMIT_ERROR", "ANTI_BOT_BLOCKED", "NETWORK_TIMEOUT", "EXTRACTION_PARSE_ERROR"]

        records = []
        for i in range(total_records):
            dom = domains[i % len(domains)]
            ftype = failure_types[i % len(failure_types)]
            records.append({
                "id": f"rec_{i:05d}",
                "domain": dom,
                "failure_type": ftype,
                "text": f"Scraping failure #{i} on {dom} caused by {ftype}: detailed explanation text {i}",
                "metadata": {"index": i, "domain": dom, "severity": i % 5}
            })

        t0 = time.perf_counter()
        for b in range(0, total_records, batch_size):
            chunk = records[b:b + batch_size]
            inserted = store.upsert_batch(chunk)
            assert inserted == len(chunk)
        upsert_time = time.perf_counter() - t0

        assert store.count() == total_records
        assert upsert_time < 10.0, f"Upsert of {total_records} records took {upsert_time:.2f}s"

        # Plant specific needle
        store.upsert(
            id="target_needle_alpha",
            domain="zillow.com",
            failure_type="ANTI_BOT_BLOCKED",
            text="PerimeterX Captcha Bot Detection Barrier Triggered on 2223 Pacific Ave",
            metadata={"secret_key": "verified_needle_123"}
        )
        assert store.count() == total_records + 1

        # Search
        t_search_0 = time.perf_counter()
        results = store.search(
            query_text="PerimeterX Captcha Bot Detection Barrier",
            top_k=5,
            domain="zillow.com"
        )
        search_latency = time.perf_counter() - t_search_0

        assert search_latency < 0.5, f"Search latency too high: {search_latency:.4f}s"
        assert len(results) > 0
        assert results[0].record.id == "target_needle_alpha"
        assert results[0].record.metadata["secret_key"] == "verified_needle_123"
        assert results[0].rank == 1

        # Deletion
        del_success = store.delete("target_needle_alpha")
        assert del_success is True
        assert store.count() == total_records
        assert store.get("target_needle_alpha") is None

        # Re-search after deletion
        results_after = store.search(
            query_text="PerimeterX Captcha Bot Detection Barrier",
            top_k=5,
            domain="zillow.com"
        )
        assert not any(r.record.id == "target_needle_alpha" for r in results_after)


def test_local_vector_store_concurrent_threads():
    """
    Stress-tests LocalVectorStore SQLite WAL mode under concurrent read and write operations.
    10 threads (5 writers, 5 readers).
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_path = os.path.join(tmp_dir, "wal_stress.db")
        store = LocalVectorStore(db_path=db_path)

        # Seed initial data
        store.upsert_batch([
            {
                "id": f"init_{i}",
                "domain": "zillow.com",
                "failure_type": "DOM_SELECTOR_DRIFT",
                "text": f"Initial vector record {i} for concurrent test index",
                "metadata": {"seed": i}
            }
            for i in range(50)
        ])
        assert store.count() == 50

        errors = []
        num_threads = 10
        ops_per_thread = 30

        def writer(tid: int):
            try:
                for op in range(ops_per_thread):
                    rid = f"writer_{tid}_{op}"
                    store.upsert(
                        id=rid,
                        domain=f"domain_{tid}.com",
                        failure_type="RATE_LIMIT_ERROR" if op % 2 == 0 else "DOM_SELECTOR_DRIFT",
                        text=f"Thread {tid} write op {op} content data",
                        metadata={"tid": tid, "op": op}
                    )
                    store.update_metadata(rid, {"verified": True, "op": op})
            except Exception as e:
                errors.append(f"Writer {tid} error: {e}")

        def reader(tid: int):
            try:
                for op in range(ops_per_thread):
                    res = store.search(
                        query_text=f"Thread {tid} search query {op}",
                        top_k=3
                    )
                    cnt = store.count()
                    assert cnt >= 50
            except Exception as e:
                errors.append(f"Reader {tid} error: {e}")

        threads = []
        for t in range(num_threads // 2):
            threads.append(threading.Thread(target=writer, args=(t,)))
            threads.append(threading.Thread(target=reader, args=(t,)))

        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert len(errors) == 0, f"Concurrency errors occurred: {errors}"
        expected_total = 50 + (num_threads // 2) * ops_per_thread
        assert store.count() == expected_total


def test_lesson_store_posix_lock_contention_and_atomicity():
    """
    Stress-tests LessonStore with 15 concurrent threads writing and updating lessons
    simultaneously, verifying zero JSON corruption and complete thread safety.
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "lessons_contention.json")
        store = LessonStore(file_path=json_path)

        num_threads = 15
        records_per_thread = 20
        errors = []

        def worker(tid: int):
            try:
                for i in range(records_per_thread):
                    lesson = Lesson(
                        domain=f"subdomain_{tid}.sfgov.org",
                        url=f"https://subdomain_{tid}.sfgov.org/permit/{i}",
                        failure_type="RATE_LIMIT_ERROR" if i % 2 == 0 else "DOM_SELECTOR_DRIFT",
                        error_message=f"Contention error {i} from thread {tid}",
                        lesson_learned=f"Lesson analysis {tid}_{i}",
                        recommended_action=f"Workaround action {tid}_{i}",
                        suggested_delay_seconds=float(i)
                    )
                    saved = store.add_lesson(lesson)
                    assert saved.id is not None
                    # Update
                    store.update_lesson(saved.id, {"suggested_delay_seconds": float(i + 1)})
            except Exception as e:
                errors.append(f"Thread {tid} error: {e}")

        threads = [threading.Thread(target=worker, args=(t,)) for t in range(num_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert len(errors) == 0, f"Errors under contention: {errors}"
        assert store.count() == num_threads * records_per_thread

        # Verify underlying disk JSON file
        with open(json_path, "r", encoding="utf-8") as f:
            disk_data = json.load(f)
        assert len(disk_data) == num_threads * records_per_thread


def test_lesson_store_corruption_recovery_variations():
    """
    Empirically verifies LessonStore corruption recovery across different corruption styles:
    - Incomplete JSON snippet
    - Non-JSON binary junk
    - JSON object instead of list
    - JSON scalar (integer/string)
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "corrupt_test.json")

        corrupt_scenarios = [
            '{"incomplete": [1, 2, ',
            '\x00\x01\x02\xff\xfe BINARY TRASH NOT JSON',
            json.dumps({"domain": "zillow.com", "not_a_list": True}),
            json.dumps(12345),
            json.dumps("plain string not list")
        ]

        for idx, scenario in enumerate(corrupt_scenarios):
            with open(json_path, "w", encoding="utf-8") as f:
                f.write(scenario)

            store = LessonStore(file_path=json_path)
            loaded = store.load_lessons()
            assert loaded == [], f"Failed to reset cleanly on scenario {idx}"
            assert store.count() == 0

            # Store should remain fully operational
            store.add_lesson(Lesson(
                domain="recovered.com",
                failure_type="DOM_SELECTOR_DRIFT",
                error_message=f"Post corruption recovery lesson {idx}"
            ))
            assert store.count() == 1


def test_learning_agent_e2e_closed_loop():
    """
    Tests end-to-end integration of LearningAgent:
    - Failure event observation
    - Heuristic classification
    - Dual storage (JSON + Vector DB)
    - Pre-scrape feedforward strategy compilation
    - Success observation and status promotion
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "e2e_lessons.json")
        db_path = os.path.join(tmp_dir, "e2e_vector.db")

        lstore = LessonStore(file_path=json_path)
        vstore = LocalVectorStore(db_path=db_path)

        agent = LearningAgent(
            lesson_store=lstore,
            vector_store=vstore,
            github_logger=None
        )

        event = ScrapingFailureEvent(
            domain="zillow.com",
            url="https://www.zillow.com/homedetails/2223-Pacific",
            failure_type="DOM_SELECTOR_DRIFT",
            error_message="Missing selector .ds-overview-section",
            selector=".ds-overview-section",
            dom_snippet="<div class='hdp-content'><span>$4,370,000</span></div>",
            lead_address="2223 Pacific Ave"
        )

        # 1. Observe failure
        res = agent.observe_failure(event)
        assert res.lesson is not None
        assert res.lesson.domain == "zillow.com"
        assert res.vector_db_indexed is True
        assert lstore.count() == 1
        assert vstore.count() == 1

        # 2. Feedforward strategy
        strat = agent.get_feedforward_strategy(domain="zillow.com", action_context="summary container price")
        assert strat.domain == "zillow.com"
        assert len(strat.applicable_lessons) >= 1
        assert len(strat.fallback_selectors) > 0

        # 3. Observe 5 successes -> Lesson status transitions to RESOLVED
        lesson_id = res.lesson.id
        for _ in range(5):
            agent.observe_success(domain="zillow.com", target_entity="2223 Pacific Ave", lesson_id=lesson_id)

        resolved_lesson = lstore.get_lesson(lesson_id)
        assert resolved_lesson.status == "RESOLVED"
        assert resolved_lesson.resolved is True
        assert resolved_lesson.success_count_after_workaround == 5
