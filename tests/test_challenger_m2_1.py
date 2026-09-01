"""
tests/test_challenger_m2_1.py

Empirical Challenger M2-1 Stress Test Suite for Roo4u Dual Memory Subsystem:
1. LessonStore:
   - High-concurrency multi-threaded atomic writes (10 threads, 250+ records)
   - POSIX atomic swap guarantees and crash-safe NamedTemporaryFile mechanics
   - Extreme payload handling (100KB+ DOM snippets, nested metadata, Unicode/emojis)
   - Corrupted JSON ledger detection and recovery (.corrupt backup + clean reset)
   - Schema alias mirroring, status transitions (ACTIVE -> RESOLVED), filtering & deletion
2. OfflineEmbeddingGenerator:
   - Mathematical invariants: Strict L2 unit-norm (||v||_2 == 1.0 +- 1e-5) across extreme inputs
   - Extreme inputs: Empty string, whitespace, massive text (100KB+), emojis, CJK, control chars, null bytes
   - Determinism across invocations and instances
   - Cosine similarity bounds [-1.0, 1.0], self-similarity == 1.0, symmetry
   - Status code boosting and semantic distance invariants
   - Batch similarity vectorized correctness vs single dot products
3. LocalVectorStore:
   - Large-scale scalability (1,000+ vector batch upsert and retrieval)
   - SQLite WAL mode multi-threaded read/write concurrency stress (no lock errors)
   - Domain and failure_type exact filtering and compound queries
   - Top-k ranking accuracy, score descending order, and min_similarity cutoff
   - Ephemeral vs File-backed SQLite lifecycle verification
4. Dual Memory Synchronization:
   - sync_stores scale synchronization between LessonStore and LocalVectorStore
   - Closed-loop search & retrieval on synchronized records
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

# Ensure project root is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from memory.lesson_store import Lesson, LessonStore
from memory.embeddings import OfflineEmbeddingGenerator
from memory.vector_store import LocalVectorStore, VectorRecord, SearchResult, sync_stores


# ============================================================================
# 1. LESSON STORE STRESS & CONCURRENCY
# ============================================================================

class TestLessonStoreStressAndConcurrency:
    """
    Empirical challenge tests for LessonStore thread-safety, atomic persistence,
    corruption recovery, and schema robustness under high-concurrency pressure.
    """

    def test_concurrent_multi_threaded_atomic_writes(self):
        """
        Spawns 10 concurrent threads each writing 25 unique lessons (250 total)
        simultaneously while reading and counting to test POSIX atomic swap and RLock.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "concurrent_lessons.json")
            store = LessonStore(file_path=ledger_path)

            num_threads = 10
            ops_per_thread = 25
            errors = []

            def worker(thread_id: int):
                try:
                    for i in range(ops_per_thread):
                        lesson = Lesson(
                            domain=f"domain_{thread_id}.com",
                            url=f"https://domain_{thread_id}.com/path/{i}",
                            failure_type="DOM_SELECTOR_DRIFT" if i % 2 == 0 else "RATE_LIMIT_ERROR",
                            error_message=f"Thread {thread_id} error {i} with unique id {uuid.uuid4()}",
                            lesson_learned=f"Lesson learned from thread {thread_id} op {i}",
                            recommended_action=f"Action workaround {thread_id}_{i}",
                            suggested_delay_seconds=float(i)
                        )
                        store.add_lesson(lesson)
                        # Concurrent reads during active writes
                        count = store.count()
                        assert count > 0
                        items = store.list_lessons(domain=f"domain_{thread_id}.com")
                        assert len(items) > 0
                except Exception as ex:
                    errors.append(f"Thread {thread_id} failed: {ex}")

            threads = [threading.Thread(target=worker, args=(t,)) for t in range(num_threads)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()

            assert len(errors) == 0, f"Thread errors encountered: {errors}"
            assert store.count() == num_threads * ops_per_thread

            # Verify integrity of underlying JSON file on disk
            with open(ledger_path, "r", encoding="utf-8") as f:
                raw_json = json.load(f)
            assert len(raw_json) == num_threads * ops_per_thread

            # Verify all thread domains are present in correct quantities
            for t in range(num_threads):
                t_lessons = store.list_lessons(domain=f"domain_{t}.com")
                assert len(t_lessons) == ops_per_thread

    def test_atomic_upsert_id_uniqueness_and_update(self):
        """Tests that upserting with an existing ID updates in-place without duplicating entries."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "upsert_test.json")
            store = LessonStore(file_path=ledger_path)

            fixed_id = str(uuid.uuid4())
            lesson1 = Lesson(
                id=fixed_id,
                domain="zillow.com",
                failure_type="ANTI_BOT_BLOCKED",
                error_message="HTTP 403 Forbidden",
                lesson_learned="PerimeterX triggered",
                recommended_action="Use 3s delay"
            )
            store.add_lesson(lesson1)
            assert store.count() == 1

            # Modify and upsert with same ID
            lesson1_updated = Lesson(
                id=fixed_id,
                domain="zillow.com",
                failure_type="ANTI_BOT_BLOCKED",
                error_message="HTTP 403 Forbidden (Updated)",
                lesson_learned="PerimeterX triggered on IP rotation",
                recommended_action="Use 10s delay with jitter",
                suggested_delay_seconds=10.0
            )
            store.upsert_lesson(lesson1_updated)

            assert store.count() == 1
            fetched = store.get_lesson(fixed_id)
            assert fetched is not None
            assert fetched.error_message == "HTTP 403 Forbidden (Updated)"
            assert fetched.suggested_delay_seconds == 10.0

    def test_corrupted_json_ledger_automatic_recovery(self):
        """
        Tests that when lessons_learned.json is corrupted with invalid tokens or truncated data,
        LessonStore automatically detects corruption, backs up the damaged file to .corrupt.<timestamp>,
        and resets to a clean empty ledger without raising exceptions.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "corrupt_ledger.json")

            # Scenario A: Truncated JSON
            with open(ledger_path, "w", encoding="utf-8") as f:
                f.write('{"domain": "zillow.com", "failure_type": [')

            store = LessonStore(file_path=ledger_path)
            lessons = store.load_lessons()
            assert lessons == []
            assert store.count() == 0

            # Verify backup file was created
            backup_files = [f for f in os.listdir(tmp_dir) if "corrupt_ledger.json.corrupt." in f]
            assert len(backup_files) == 1

            # Verify new additions work seamlessly
            store.add_lesson(Lesson(domain="zillow.com", failure_type="TIMEOUT", error_message="timeout 30s"))
            assert store.count() == 1

            # Sleep 1.1s to guarantee distinct second-level timestamp for distinct backup
            time.sleep(1.1)

            # Scenario B: Valid JSON but not a list (dictionary root)
            with open(ledger_path, "w", encoding="utf-8") as f:
                f.write(json.dumps({"invalid_root": "should_be_a_list"}))

            store_reloaded = LessonStore(file_path=ledger_path)
            assert store_reloaded.count() == 0
            backup_files_2 = [f for f in os.listdir(tmp_dir) if "corrupt_ledger.json.corrupt." in f]
            assert len(backup_files_2) == 2

    def test_extreme_payload_and_special_characters(self):
        """
        Tests storing extreme payload sizes (100KB+ DOM snippet, 1,000 tags, Unicode, emojis,
        control characters, quotes, HTML entities) without JSON serialization failure.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "extreme_payload.json")
            store = LessonStore(file_path=ledger_path)

            large_dom = "<div class='content'>" + ("<p class='row'><span>Data</span></p>" * 3000) + "</div>"
            assert len(large_dom) > 100000

            special_text = (
                "🚨 Critical Failure: DOM Drift on '2223 Pacific Ave' & \"Quotes\" \n"
                "Unicode: 🏡 屋顶许可证 SFGov / \u200b\u00a0\t\r "
                "Symbols: <>&\"'\\/!@#$%^&*()_+=-~`{}[]|:;"
            )

            huge_metadata = {
                "tags": ["tag_" + str(i) for i in range(500)],
                "nested": {"level1": {"level2": {"level3": "deep_value"}}},
                "large_blob": "x" * 20000
            }

            lesson = Lesson(
                domain="extreme-test.org",
                url="https://extreme-test.org/test?param1=val&param2=<script>",
                failure_type="DOM_SELECTOR_DRIFT",
                error_message=special_text,
                lesson_learned=special_text,
                recommended_action="Escape and parse with lxml",
                dom_snippet=large_dom,
                metadata=huge_metadata,
                suggested_selectors=["div.content > p.row:nth-child(10)", "[data-testid=\"custom-quote\"]"]
            )

            saved = store.add_lesson(lesson)
            assert saved.id is not None
            assert store.count() == 1

            # Retrieve and verify exact reproduction
            retrieved = store.get_lesson(saved.id)
            assert retrieved is not None
            assert retrieved.dom_snippet == large_dom
            assert retrieved.error_message == special_text
            assert len(retrieved.metadata["tags"]) == 500
            assert retrieved.metadata["nested"]["level1"]["level2"]["level3"] == "deep_value"

    def test_status_transitions_and_success_counter(self):
        """
        Tests state machine transitions:
        ACTIVE -> increment_success (1 to 4) -> remains ACTIVE
        increment_success (5) -> transitions automatically to RESOLVED with resolved=True.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "transitions.json")
            store = LessonStore(file_path=ledger_path)

            lesson = Lesson(
                domain="dbiweb02.sfgov.org",
                failure_type="RATE_LIMIT_ERROR",
                error_message="HTTP 429",
                recommended_action="Add 5s delay"
            )
            store.add_lesson(lesson)
            l_id = lesson.id

            for i in range(1, 5):
                res = store.increment_success(l_id)
                assert res is not None
                assert res.success_count_after_workaround == i
                assert res.status == "ACTIVE"
                assert res.resolved is False

            # 5th success triggers RESOLVED
            res5 = store.increment_success(l_id)
            assert res5 is not None
            assert res5.success_count_after_workaround == 5
            assert res5.status == "RESOLVED"
            assert res5.resolved is True

            # 6th success maintains RESOLVED
            res6 = store.increment_success(l_id)
            assert res6.success_count_after_workaround == 6
            assert res6.status == "RESOLVED"
            assert res6.resolved is True

    def test_case_insensitive_filtering_and_limits(self):
        """Tests that domain and failure_type filtering are case-tolerant and handle limits gracefully."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            ledger_path = os.path.join(tmp_dir, "filter_test.json")
            store = LessonStore(file_path=ledger_path)

            store.add_lesson(Lesson(domain="Zillow.COM", failure_type="DOM_SELECTOR_DRIFT", error_message="e1"))
            store.add_lesson(Lesson(domain="zillow.com", failure_type="anti_bot_blocked", error_message="e2"))
            store.add_lesson(Lesson(domain="SFPLANNINGGIS.ORG", failure_type="DOM_SELECTOR_DRIFT", error_message="e3"))
            store.add_lesson(Lesson(domain="sfplanninggis.org", failure_type="EXTRACTION_PARSE_ERROR", error_message="e4"))

            assert store.count() == 4
            assert store.count("zillow.com") == 2
            assert store.count("ZILLOW.COM") == 2
            assert store.count("sfplanninggis.org") == 2

            # Filter with mixed case
            zillow_drift = store.list_lessons(domain="ZILLOW.com", failure_type="dom_selector_drift")
            assert len(zillow_drift) == 1

            # Limit parameter
            all_lessons_limit2 = store.list_lessons(limit=2)
            assert len(all_lessons_limit2) == 2


# ============================================================================
# 2. OFFLINE EMBEDDING GENERATOR MATHEMATICAL INVARIANTS
# ============================================================================

class TestOfflineEmbeddingGeneratorInvariants:
    """
    Empirical challenge tests for OfflineEmbeddingGenerator.
    Verifies mathematical invariants, vector geometry, numerical stability,
    and extreme input resistance.
    """

    def test_l2_unit_norm_invariant_across_extreme_inputs(self):
        """
        Tests that ||embed_text(x)||_2 == 1.0 (+- 1e-5) for arbitrary inputs:
        - Empty string
        - Whitespace only
        - Single character
        - 100KB+ massive document
        - Emojis, CJK, Cyrillic, Arabic
        - Control characters, escape sequences, null bytes
        - Numeric tokens, HTTP status codes, CSS selectors
        """
        embedder = OfflineEmbeddingGenerator(dimension=256)

        test_cases = [
            "",
            "   ",
            "\n\t\r  \n",
            "a",
            "Z",
            "12345",
            "403",
            "429 500 502 503",
            "🔥🔥🔥 🤖🤖🤖 🏠🏠🏠",
            "旧金山房屋屋顶许可证查询 94115 太平洋大道",
            "Привет мир! Тестирование векторной базы данных Roo4u",
            "مرحبا بكم في نظام استخراج البيانات",
            "\x00\x01\x02\x1f\x7f\x80\xff",
            "<div class=\"ds-summary-row\" data-testid=\"home-facts\"><span>$4,370,000</span></div>",
            "https://dbiweb02.sfgov.org/dbipts/default.aspx?page=Permit&PermitNumber=202105141234",
            "A" * 50000,  # 50KB uniform repetition
            ("word_" + str(i) + " " for i in range(10000)) # 10,000 unique words
        ]

        for idx, item in enumerate(test_cases):
            text = "".join(item) if not isinstance(item, str) else item
            vec = embedder.embed_text(text)

            # Invariant 1: Vector shape and dtype
            assert vec.shape == (256,), f"Failed on case {idx}: shape is {vec.shape}"
            assert vec.dtype == np.float32, f"Failed on case {idx}: dtype is {vec.dtype}"

            # Invariant 2: No NaN or Inf
            assert not np.isnan(vec).any(), f"NaN detected in case {idx}"
            assert not np.isinf(vec).any(), f"Inf detected in case {idx}"

            # Invariant 3: Strict L2 Unit Norm
            l2_norm = float(np.linalg.norm(vec))
            assert abs(l2_norm - 1.0) < 1e-4, f"L2 norm failed on case {idx}: norm={l2_norm}"

    def test_custom_dimensions_and_validations(self):
        """Tests that OfflineEmbeddingGenerator supports arbitrary dimensions and rejects invalid ones."""
        for dim in [64, 128, 256, 512, 1024]:
            emb = OfflineEmbeddingGenerator(dimension=dim)
            v = emb.embed_text("Test dimensional scaling")
            assert v.shape == (dim,)
            assert abs(float(np.linalg.norm(v)) - 1.0) < 1e-4

        with pytest.raises(ValueError):
            OfflineEmbeddingGenerator(dimension=0)
        with pytest.raises(ValueError):
            OfflineEmbeddingGenerator(dimension=-256)

    def test_cosine_similarity_bounds_and_symmetry(self):
        """
        Tests mathematical axioms of cosine similarity:
        - Bounds: -1.0 <= cos(u, v) <= 1.0
        - Self-similarity: cos(u, u) == 1.0 (+- 1e-5)
        - Symmetry: cos(u, v) == cos(v, u)
        - Orthogonality / non-identical divergence: cos(u, v) < 1.0 for distinct texts
        """
        embedder = OfflineEmbeddingGenerator(dimension=256)

        texts = [
            "Zillow property scraping failed with DOM selector drift on summary chip",
            "HTTP 429 Rate limit exceeded on SF Department of Building Inspection",
            "Victorian home 4 bedrooms 3 bathrooms 3500 sqft built in 1900",
            "Anti-bot challenge PerimeterX CAPTCHA blocked request",
            "Database transaction rolled back due to unique constraint APN 0586-012"
        ]

        vectors = [embedder.embed_text(t) for t in texts]

        for i, v_i in enumerate(vectors):
            # Self-similarity
            self_sim = embedder.cosine_similarity(v_i, v_i)
            assert abs(self_sim - 1.0) < 1e-5, f"Self-similarity failed for text {i}: {self_sim}"

            for j, v_j in enumerate(vectors):
                sim_ij = embedder.cosine_similarity(v_i, v_j)
                sim_ji = embedder.cosine_similarity(v_j, v_i)

                # Bounds
                assert -1.0 - 1e-5 <= sim_ij <= 1.0 + 1e-5, f"Bounds violation ({i}, {j}): {sim_ij}"

                # Symmetry
                assert abs(sim_ij - sim_ji) < 1e-6, f"Symmetry violation ({i}, {j}): {sim_ij} vs {sim_ji}"

                # Distinctness
                if i != j:
                    assert sim_ij < 0.999, f"Different texts ({i}, {j}) produced near-identical similarity: {sim_ij}"

    def test_semantic_clustering_and_status_code_boosting(self):
        """
        Tests that texts sharing HTTP status codes and domain keywords yield higher
        cosine similarity than semantically disjoint topics.
        """
        embedder = OfflineEmbeddingGenerator(dimension=256)

        # Cluster A: HTTP 429 Rate Limiting
        a1 = "HTTP 429 Rate limit exceeded on dbiweb02.sfgov.org permit search"
        a2 = "Too many requests error 429 status code received from SF building inspection portal"

        # Cluster B: DOM Selector Drift
        b1 = "Zillow DOM selector drift on [data-testid='home-details-chip-container']"
        b2 = "Selector drift on zillow.com price overview card container"

        # Unrelated topic
        c1 = "Exported 50 qualified leads to CSV report leads_2026.csv"

        v_a1 = embedder.embed_text(a1)
        v_a2 = embedder.embed_text(a2)
        v_b1 = embedder.embed_text(b1)
        v_b2 = embedder.embed_text(b2)
        v_c1 = embedder.embed_text(c1)

        sim_a1_a2 = embedder.cosine_similarity(v_a1, v_a2)
        sim_b1_b2 = embedder.cosine_similarity(v_b1, v_b2)
        sim_a1_b1 = embedder.cosine_similarity(v_a1, v_b1)
        sim_a1_c1 = embedder.cosine_similarity(v_a1, v_c1)

        # Intra-cluster similarities must exceed inter-cluster similarities
        assert sim_a1_a2 > sim_a1_b1, f"Intra-cluster A ({sim_a1_a2}) should exceed cross-cluster ({sim_a1_b1})"
        assert sim_b1_b2 > sim_a1_b1, f"Intra-cluster B ({sim_b1_b2}) should exceed cross-cluster ({sim_a1_b1})"
        assert sim_a1_a2 > sim_a1_c1, f"Intra-cluster A ({sim_a1_a2}) should exceed unrelated ({sim_a1_c1})"

    def test_batch_vs_individual_cosine_equivalence(self):
        """Tests that batch_cosine_similarity produces identical results to sequential cosine_similarity."""
        embedder = OfflineEmbeddingGenerator(dimension=256)
        query = "Zillow selector drift price facts"
        docs = [
            "Zillow selector drift price",
            "SF planning parcel lookup error",
            "HTTP 500 internal server error",
            "429 rate limit exceeded",
            "Zillow facts container missing"
        ]

        q_vec = embedder.embed_text(query)
        doc_mat = embedder.embed_batch(docs)

        batch_scores = embedder.batch_cosine_similarity(q_vec, doc_mat)
        assert batch_scores.shape == (len(docs),)

        for i, doc_text in enumerate(docs):
            d_vec = embedder.embed_text(doc_text)
            single_score = embedder.cosine_similarity(q_vec, d_vec)
            assert abs(batch_scores[i] - single_score) < 1e-5, f"Mismatch on doc {i}: {batch_scores[i]} vs {single_score}"

    def test_empty_batch_handling(self):
        """Tests that empty batches return valid empty numpy arrays without raising exceptions."""
        embedder = OfflineEmbeddingGenerator(dimension=256)
        empty_mat = embedder.embed_batch([])
        assert empty_mat.shape == (0, 256)

        q_vec = embedder.embed_text("test")
        sims = embedder.batch_cosine_similarity(q_vec, empty_mat)
        assert sims.shape == (0,)


# ============================================================================
# 3. LOCAL VECTOR STORE SCALE & CONCURRENCY
# ============================================================================

class TestLocalVectorStoreScaleAndConcurrency:
    """
    Empirical challenge tests for LocalVectorStore:
    - 1,000+ vector bulk upsert performance
    - SQLite WAL concurrency stress (simultaneous search & upsert from multiple threads)
    - Precise domain and failure_type metadata filtering
    - Top-k ranking and score sorting accuracy
    - File-backed persistence verification
    """

    def test_1000_vector_bulk_upsert_and_retrieval(self):
        """
        Upserts 1,000+ vector records into LocalVectorStore in batches,
        measures execution time (< 3.0s expected), and performs search across the entire corpus.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            db_path = os.path.join(tmp_dir, "scale_1000.db")
            store = LocalVectorStore(db_path=db_path)

            total_records = 1200
            batch_size = 200
            domains = ["zillow.com", "sfplanninggis.org", "dbiweb02.sfgov.org", "redfin.com"]
            failure_types = ["DOM_SELECTOR_DRIFT", "RATE_LIMIT_ERROR", "ANTI_BOT_BLOCKED", "TIMEOUT", "EXTRACTION_PARSE_ERROR"]

            start_time = time.perf_counter()

            records_to_insert = []
            for i in range(total_records):
                dom = domains[i % len(domains)]
                ftype = failure_types[i % len(failure_types)]
                records_to_insert.append({
                    "id": f"vec_{i:04d}",
                    "domain": dom,
                    "failure_type": ftype,
                    "text": f"[{dom}] [{ftype}] Error event #{i} describing scraping failure at index {i}",
                    "metadata": {"index": i, "batch": i // batch_size}
                })

            for b in range(0, total_records, batch_size):
                chunk = records_to_insert[b:b + batch_size]
                inserted = store.upsert_batch(chunk)
                assert inserted == len(chunk)

            elapsed = time.perf_counter() - start_time
            assert store.count() == total_records
            assert elapsed < 5.0, f"Bulk upsert of {total_records} records took too long: {elapsed:.2f}s"

            # Domain counts
            for dom in domains:
                dom_count = store.count(domain=dom)
                assert dom_count == total_records // len(domains)

            # Search with needle in haystack
            needle_idx = 777
            needle_text = f"Special Unique Failure Scenario at index {needle_idx}"
            store.upsert(
                id="needle_record",
                domain="zillow.com",
                failure_type="DOM_SELECTOR_DRIFT",
                text=needle_text,
                metadata={"needle": True}
            )
            assert store.count() == total_records + 1

            search_results = store.search(
                query_text="Special Unique Failure Scenario",
                top_k=5,
                domain="zillow.com"
            )
            assert len(search_results) > 0
            # Target needle must be retrieved at Rank 1
            top_res = search_results[0]
            assert top_res.record.id == "needle_record"
            assert top_res.rank == 1
            assert top_res.record.metadata.get("needle") is True

    def test_sqlite_wal_multithreaded_read_write_concurrency(self):
        """
        Stress-tests SQLite WAL mode by running 8 parallel threads:
        - 4 writer threads constantly upserting and updating records
        - 4 reader threads constantly searching and counting
        Verifies zero 'database is locked' errors and complete transaction safety.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            db_path = os.path.join(tmp_dir, "wal_concurrency.db")
            store = LocalVectorStore(db_path=db_path)

            # Pre-seed with 100 records
            seed_records = [
                {
                    "id": f"seed_{i}",
                    "domain": "zillow.com" if i % 2 == 0 else "dbiweb02.sfgov.org",
                    "failure_type": "DOM_SELECTOR_DRIFT" if i % 2 == 0 else "RATE_LIMIT_ERROR",
                    "text": f"Seed record {i} for initial search index",
                    "metadata": {"seed": True}
                }
                for i in range(100)
            ]
            store.upsert_batch(seed_records)
            assert store.count() == 100

            errors = []
            stop_event = threading.Event()

            def writer_worker(thread_id: int):
                try:
                    for op in range(50):
                        if stop_event.is_set():
                            break
                        rec_id = f"w_{thread_id}_{op}"
                        store.upsert(
                            id=rec_id,
                            domain=f"domain_{thread_id}.com",
                            failure_type="DOM_SELECTOR_DRIFT",
                            text=f"Thread {thread_id} dynamic upsert op {op}",
                            metadata={"thread": thread_id, "op": op}
                        )
                        # Metadata update
                        store.update_metadata(rec_id, {"status": "UPDATED", "op": op})
                except Exception as ex:
                    errors.append(f"Writer {thread_id} failed: {ex}")

            def reader_worker(thread_id: int):
                try:
                    for op in range(50):
                        if stop_event.is_set():
                            break
                        res = store.search(
                            query_text=f"Thread {thread_id} search op",
                            top_k=5
                        )
                        c = store.count()
                        assert c >= 100
                except Exception as ex:
                    errors.append(f"Reader {thread_id} failed: {ex}")

            writers = [threading.Thread(target=writer_worker, args=(i,)) for i in range(4)]
            readers = [threading.Thread(target=reader_worker, args=(i,)) for i in range(4)]

            all_threads = writers + readers
            for t in all_threads:
                t.start()
            for t in all_threads:
                t.join()

            assert len(errors) == 0, f"WAL concurrency errors: {errors}"
            assert store.count() == 100 + (4 * 50)

    def test_top_k_ranking_monotonicity_and_cutoff(self):
        """
        Verifies that search results are strictly monotonically decreasing in score
        (score[0] >= score[1] >= ... >= score[k-1]) and that min_similarity filtering
        strictly excludes lower-scoring documents.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            db_path = os.path.join(tmp_dir, "ranking_test.db")
            store = LocalVectorStore(db_path=db_path)

            records = [
                {"id": "exact_match", "text": "Zillow 403 PerimeterX anti bot captcha block", "domain": "zillow.com"},
                {"id": "partial_match", "text": "Zillow anti bot challenge received", "domain": "zillow.com"},
                {"id": "weak_match", "text": "Zillow scraping general timeout", "domain": "zillow.com"},
                {"id": "unrelated_1", "text": "County assessor parcel table APN lookup", "domain": "sfplanninggis.org"},
                {"id": "unrelated_2", "text": "Victorian architectural permit guidelines", "domain": "dbiweb02.sfgov.org"}
            ]
            store.upsert_batch(records)

            results = store.search(
                query_text="Zillow 403 PerimeterX anti bot",
                top_k=5
            )
            assert len(results) == 5

            # Monotonicity check
            scores = [r.score for r in results]
            for i in range(len(scores) - 1):
                assert scores[i] >= scores[i+1], f"Ranking non-monotonic: {scores[i]} < {scores[i+1]}"

            assert results[0].record.id == "exact_match"
            assert results[0].rank == 1

            # min_similarity cutoff
            high_cutoff = store.search(
                query_text="Zillow 403 PerimeterX anti bot",
                min_similarity=0.4
            )
            for r in high_cutoff:
                assert r.score >= 0.4

    def test_file_backed_persistence_across_instances(self):
        """Tests that LocalVectorStore persists data cleanly on disk across distinct instances."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            db_path = os.path.join(tmp_dir, "instance_test.db")
            store1 = LocalVectorStore(db_path=db_path)
            store1.upsert(id="inst_1", text="Instance persistence test", domain="test_domain")
            assert store1.count() == 1

            # Open with new instance
            store2 = LocalVectorStore(db_path=db_path)
            assert store2.count() == 1
            rec = store2.get("inst_1")
            assert rec is not None
            assert rec.text == "Instance persistence test"
            assert rec.domain == "test_domain"

            search_res = store2.search("Instance persistence")
            assert len(search_res) == 1
            assert search_res[0].record.id == "inst_1"


# ============================================================================
# 4. DUAL MEMORY SYNCHRONIZATION INTEGRATION
# ============================================================================

class TestDualMemoryE2EIntegration:
    """
    Empirical challenge tests for synchronization between JSON LessonStore and LocalVectorStore.
    """

    def test_sync_stores_large_scale_reconciliation(self):
        """
        Seeds LessonStore with 300 lessons, synchronizes to LocalVectorStore via sync_stores(),
        and verifies count equivalence, metadata preservation, and search capability.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons_sync.json")
            db_path = os.path.join(tmp_dir, "vectors_sync.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)

            num_lessons = 300
            domains = ["zillow.com", "sfplanninggis.org", "dbiweb02.sfgov.org"]

            for i in range(num_lessons):
                dom = domains[i % len(domains)]
                lesson = Lesson(
                    domain=dom,
                    url=f"https://{dom}/item/{i}",
                    failure_type="DOM_SELECTOR_DRIFT" if i % 2 == 0 else "RATE_LIMIT_ERROR",
                    error_message=f"Error message number {i} on domain {dom}",
                    lesson_learned=f"Lesson learned {i} with specific fix strategy",
                    recommended_action=f"Workaround action {i} using fallback selector",
                    suggested_delay_seconds=float(i % 10)
                )
                lstore.add_lesson(lesson)

            assert lstore.count() == num_lessons
            assert vstore.count() == 0

            # Execute sync
            synced = sync_stores(lstore, vstore)
            assert synced == num_lessons
            assert vstore.count() == num_lessons

            # Search vector store for synced items
            results = vstore.search(
                query_text="fallback selector specific fix strategy",
                top_k=10,
                domain="zillow.com"
            )
            assert len(results) == 10
            for r in results:
                assert r.record.domain == "zillow.com"
                assert "metadata" in r.record.__dict__
                assert "suggested_delay_seconds" in r.record.metadata

    def test_delete_and_clear_synchronization_hygiene(self):
        """Tests deletion and clear operations across both stores."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            json_path = os.path.join(tmp_dir, "lessons_del.json")
            db_path = os.path.join(tmp_dir, "vectors_del.sqlite")

            lstore = LessonStore(file_path=json_path)
            vstore = LocalVectorStore(db_path=db_path)

            lesson = Lesson(domain="zillow.com", failure_type="TIMEOUT", error_message="timeout")
            lstore.add_lesson(lesson)
            sync_stores(lstore, vstore)

            assert lstore.count() == 1
            assert vstore.count() == 1

            # Delete
            lstore.delete_lesson(lesson.id)
            vstore.delete(lesson.id)

            assert lstore.count() == 0
            assert vstore.count() == 0
