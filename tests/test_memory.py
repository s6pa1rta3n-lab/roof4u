"""
tests/test_memory.py

Comprehensive zero-mock unit test suite for Roo4u Dual-Memory Architecture:
- Lesson Pydantic model contracts & alias syncing
- Atomic POSIX file operations & corruption recovery in LessonStore
- Deterministic 256-D OfflineEmbeddingGenerator & cosine similarity metrics
- LocalVectorStore SQLite WAL mode persistence, BLOB unpacking, and matrix search
- Multi-threaded concurrency safety and sync_stores synchronization
"""

import os
import json
import tempfile
import threading
import numpy as np
import pytest

from memory.lesson_store import Lesson, LessonStore
from memory.embeddings import OfflineEmbeddingGenerator
from memory.vector_store import LocalVectorStore, VectorRecord, SearchResult, sync_stores


# ============================================================================
# 1. Lesson Schema & Data Contract Tests
# ============================================================================

def test_lesson_model_instantiation_and_defaults():
    lesson = Lesson(
        domain="zillow.com",
        url="https://www.zillow.com/homedetails/123",
        failure_type="DOM_SELECTOR_DRIFT",
        error_message="Selector .ds-overview-section not found",
        lesson_learned="Zillow changed React summary container",
        recommended_action="Use [data-testid='home-details-chip-container']"
    )
    assert lesson.id is not None
    assert len(lesson.id) > 0
    assert lesson.domain == "zillow.com"
    assert lesson.source_url == "https://www.zillow.com/homedetails/123"
    assert lesson.error_category == "DOM_SELECTOR_DRIFT"
    assert lesson.root_cause_analysis == "Zillow changed React summary container"
    assert lesson.recommended_workaround == "Use [data-testid='home-details-chip-container']"
    assert lesson.status == "ACTIVE"
    assert lesson.occurrence_count == 1
    assert lesson.success_count_after_workaround == 0
    assert not lesson.resolved


def test_lesson_model_alias_mirroring():
    # Test constructing with explorer 3 style aliases
    lesson = Lesson(
        domain="sfplanninggis.org",
        source_url="https://sfplanninggis.org/pim/?search=2223+Pacific",
        error_category="EXTRACTION_PARSE_ERROR",
        error_message="Parcel table missing",
        root_cause_analysis="Planning portal redesign",
        recommended_workaround="Query fallback assessment tab",
        suggested_selectors=[".parcel-details", "#propertyDetails"],
        suggested_delay_seconds=1.5
    )
    assert lesson.url == "https://sfplanninggis.org/pim/?search=2223+Pacific"
    assert lesson.failure_type == "EXTRACTION_PARSE_ERROR"
    assert lesson.lesson_learned == "Planning portal redesign"
    assert lesson.recommended_action == "Query fallback assessment tab"
    assert len(lesson.suggested_selectors) == 2
    assert lesson.suggested_delay_seconds == 1.5


# ============================================================================
# 2. LessonStore Atomic Operations & Corruption Recovery
# ============================================================================

def test_lesson_store_atomic_write_and_reload():
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "test_lessons.json")
        store = LessonStore(file_path=json_path)

        assert os.path.exists(json_path)
        assert store.count() == 0

        lesson1 = Lesson(
            domain="zillow.com",
            url="https://zillow.com/p1",
            failure_type="DOM_SELECTOR_DRIFT",
            error_message="Missing selector",
            lesson_learned="Card moved",
            recommended_action="Use article tag"
        )
        saved = store.add_lesson(lesson1)
        assert saved.id == lesson1.id
        assert store.count() == 1

        # Read directly from disk
        with open(json_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        assert len(raw) == 1
        assert raw[0]["domain"] == "zillow.com"

        # Reload with second store instance
        store2 = LessonStore(file_path=json_path)
        assert store2.count() == 1
        retrieved = store2.get_lesson(lesson1.id)
        assert retrieved is not None
        assert retrieved.domain == "zillow.com"


def test_lesson_store_update_and_success_increment():
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "test_lessons.json")
        store = LessonStore(file_path=json_path)

        lesson = Lesson(
            domain="dbiweb02.sfgov.org",
            url="https://dbiweb02.sfgov.org/dbipts",
            failure_type="RATE_LIMIT_ERROR",
            error_message="HTTP 429",
            lesson_learned="Too many requests",
            recommended_action="Add 5s delay"
        )
        store.add_lesson(lesson)

        # Update
        updated = store.update_lesson(lesson.id, {"suggested_delay_seconds": 6.0})
        assert updated is not None
        assert updated.suggested_delay_seconds == 6.0

        # Increment successes up to 5
        for i in range(1, 6):
            res = store.increment_success(lesson.id)
            assert res is not None
            assert res.success_count_after_workaround == i

        # After 5 successes, status should transition to RESOLVED
        final_l = store.get_lesson(lesson.id)
        assert final_l.status == "RESOLVED"
        assert final_l.resolved is True


def test_lesson_store_filtering_and_deletion():
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "test_lessons.json")
        store = LessonStore(file_path=json_path)

        store.add_lesson(Lesson(domain="zillow.com", url="u1", failure_type="DOM_SELECTOR_DRIFT", error_message="e1", lesson_learned="l1", recommended_action="a1"))
        store.add_lesson(Lesson(domain="zillow.com", url="u2", failure_type="ANTI_BOT_BLOCKED", error_message="e2", lesson_learned="l2", recommended_action="a2"))
        store.add_lesson(Lesson(domain="sfplanninggis.org", url="u3", failure_type="DOM_SELECTOR_DRIFT", error_message="e3", lesson_learned="l3", recommended_action="a3"))

        assert store.count() == 3
        assert store.count(domain="zillow.com") == 2
        assert store.count(domain="sfplanninggis.org") == 1

        zillow_drift = store.list_lessons(domain="zillow.com", failure_type="DOM_SELECTOR_DRIFT")
        assert len(zillow_drift) == 1

        all_zillow = store.filter_by_domain("zillow.com")
        assert len(all_zillow) == 2

        # Delete
        to_del_id = all_zillow[0].id
        deleted = store.delete_lesson(to_del_id)
        assert deleted is True
        assert store.count() == 2
        assert store.get_lesson(to_del_id) is None

        # Clear
        store.clear()
        assert store.count() == 0


def test_lesson_store_corrupted_file_recovery():
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "test_corrupt.json")
        with open(json_path, "w", encoding="utf-8") as f:
            f.write("{THIS IS CORRUPT NOT VALID JSON [123")

        store = LessonStore(file_path=json_path)
        # Should not raise; should reset cleanly to empty list
        lessons = store.load_lessons()
        assert lessons == []
        assert store.count() == 0

        # Adding new lesson should work normally
        store.add_lesson(Lesson(domain="zillow.com", url="u", failure_type="TIMEOUT", error_message="e", lesson_learned="l", recommended_action="a"))
        assert store.count() == 1


def test_lesson_store_multithreaded_concurrency():
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "test_concurrent.json")
        store = LessonStore(file_path=json_path)

        def worker(thread_idx: int):
            for i in range(10):
                l = Lesson(
                    domain=f"domain_{thread_idx}.com",
                    url=f"https://domain_{thread_idx}.com/{i}",
                    failure_type="DOM_SELECTOR_DRIFT",
                    error_message=f"Error {i} from thread {thread_idx}",
                    lesson_learned=f"Lesson {i}",
                    recommended_action=f"Action {i}"
                )
                store.add_lesson(l)
                store.list_lessons()
                store.count()

        threads = [threading.Thread(target=worker, args=(t,)) for t in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert store.count() == 50


# ============================================================================
# 3. OfflineEmbeddingGenerator Tests
# ============================================================================

def test_embedding_generator_determinism_and_norm():
    embedder = OfflineEmbeddingGenerator(dimension=256)
    text = "Zillow scraping failed with DOM selector drift on [data-testid='property-summary']"

    vec1 = embedder.embed_text(text)
    vec2 = embedder.embed_text(text)

    # 1. Output shape & type
    assert vec1.shape == (256,)
    assert vec1.dtype == np.float32

    # 2. Determinism
    np.testing.assert_array_equal(vec1, vec2)

    # 3. L2 Unit Norm
    norm = float(np.linalg.norm(vec1))
    assert abs(norm - 1.0) < 1e-5


def test_embedding_generator_batch_and_cosine_similarity():
    embedder = OfflineEmbeddingGenerator(dimension=256)

    t1 = "HTTP 429 Rate limit exceeded on dbiweb02.sfgov.org"
    t2 = "Too many requests 429 status code on building permit portal"
    t3 = "Victorian single family home roof permit details"

    batch = embedder.embed_batch([t1, t2, t3])
    assert batch.shape == (3, 256)

    sim_1_2 = embedder.cosine_similarity(batch[0], batch[1])
    sim_1_3 = embedder.cosine_similarity(batch[0], batch[2])

    # t1 and t2 both share 429 and rate limit semantics, should have higher similarity than t1 and t3
    assert sim_1_2 > sim_1_3
    assert -1.0 <= sim_1_2 <= 1.0

    batch_sims = embedder.batch_cosine_similarity(batch[0], batch)
    assert batch_sims.shape == (3,)
    assert abs(batch_sims[0] - 1.0) < 1e-5


# ============================================================================
# 4. LocalVectorStore Tests
# ============================================================================

def test_local_vector_store_crud():
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_path = os.path.join(tmp_dir, "test_vector.db")
        store = LocalVectorStore(db_path=db_path)

        rec = store.upsert(
            id="rec_1",
            text="[zillow.com] DOM selector drift on summary chip",
            domain="zillow.com",
            failure_type="DOM_SELECTOR_DRIFT",
            metadata={"action": "use fallback"}
        )
        assert rec.id == "rec_1"
        assert rec.embedding is not None
        assert rec.embedding.shape == (256,)
        assert store.count() == 1

        # Get
        fetched = store.get("rec_1")
        assert fetched is not None
        assert fetched.id == "rec_1"
        assert fetched.domain == "zillow.com"
        assert fetched.metadata["action"] == "use fallback"

        # Update metadata
        store.update_metadata("rec_1", {"action": "updated action", "status": "RESOLVED"})
        fetched2 = store.get("rec_1")
        assert fetched2.metadata["action"] == "updated action"
        assert fetched2.metadata["status"] == "RESOLVED"

        # Delete
        assert store.delete("rec_1") is True
        assert store.count() == 0
        assert store.get("rec_1") is None


def test_local_vector_store_semantic_search_and_filters():
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_path = os.path.join(tmp_dir, "test_search.db")
        store = LocalVectorStore(db_path=db_path)

        records = [
            {
                "id": "zillow_drift",
                "text": "zillow.com DOM selector drift on price and facts container",
                "domain": "zillow.com",
                "failure_type": "DOM_SELECTOR_DRIFT",
                "metadata": {"fix": "use chip container"}
            },
            {
                "id": "zillow_bot",
                "text": "zillow.com 403 anti bot challenge perimeterx blocked request",
                "domain": "zillow.com",
                "failure_type": "ANTI_BOT_BLOCKED",
                "metadata": {"fix": "add jitter delay"}
            },
            {
                "id": "sf_planning_drift",
                "text": "sfplanninggis.org parcel table selector drift missing details",
                "domain": "sfplanninggis.org",
                "failure_type": "DOM_SELECTOR_DRIFT",
                "metadata": {"fix": "query assessment card"}
            },
            {
                "id": "dbi_rate_limit",
                "text": "dbiweb02.sfgov.org 429 rate limit too many permit requests",
                "domain": "dbiweb02.sfgov.org",
                "failure_type": "RATE_LIMIT_ERROR",
                "metadata": {"fix": "backoff 5s"}
            }
        ]
        count = store.upsert_batch(records)
        assert count == 4
        assert store.count() == 4

        # Search 1: Query for selector drift on zillow
        results = store.search(
            query_text="zillow selector missing",
            top_k=2,
            domain="zillow.com"
        )
        assert len(results) == 2
        # Top result should be zillow_drift
        assert results[0].record.id == "zillow_drift"
        assert results[0].rank == 1
        assert results[0].score >= results[1].score

        # Search 2: Query with failure_type filter
        bot_results = store.search(
            query_text="bot challenge",
            failure_type="ANTI_BOT_BLOCKED"
        )
        assert len(bot_results) == 1
        assert bot_results[0].record.id == "zillow_bot"

        # Search 3: Query cross-domain rate limit
        rate_results = store.search(
            query_text="429 rate limit backoff",
            top_k=1
        )
        assert len(rate_results) == 1
        assert rate_results[0].record.id == "dbi_rate_limit"


def test_sync_stores_integration():
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "lessons.json")
        db_path = os.path.join(tmp_dir, "vectors.sqlite")

        lstore = LessonStore(file_path=json_path)
        vstore = LocalVectorStore(db_path=db_path)

        lstore.add_lesson(Lesson(domain="zillow.com", url="u1", failure_type="DOM_SELECTOR_DRIFT", error_message="e1", lesson_learned="l1", recommended_action="a1"))
        lstore.add_lesson(Lesson(domain="sfplanninggis.org", url="u2", failure_type="EXTRACTION_PARSE_ERROR", error_message="e2", lesson_learned="l2", recommended_action="a2"))

        assert vstore.count() == 0
        synced = sync_stores(lstore, vstore)
        assert synced == 2
        assert vstore.count() == 2

        results = vstore.search("zillow DOM drift", domain="zillow.com")
        assert len(results) > 0


def test_local_vector_store_in_memory_mode_lifecycle_and_crud():
    """Verifies that LocalVectorStore(':memory:') maintains persistence and functions identically to file-backed."""
    with LocalVectorStore(db_path=":memory:") as store:
        assert store.count() == 0

        # Upsert
        rec1 = store.upsert(
            id="mem_rec_1",
            text="[zillow.com] In-memory persistence verification test",
            domain="zillow.com",
            failure_type="DOM_SELECTOR_DRIFT"
        )
        assert rec1.id == "mem_rec_1"
        assert store.count() == 1

        # Get
        fetched = store.get("mem_rec_1")
        assert fetched is not None
        assert fetched.text == "[zillow.com] In-memory persistence verification test"

        # Search
        results = store.search(query_text="persistence verification", domain="zillow.com")
        assert len(results) == 1
        assert results[0].record.id == "mem_rec_1"
        assert results[0].rank == 1

        # Batch upsert
        store.upsert_batch([
            {"id": "mem_rec_2", "text": "Batch text 2", "domain": "zillow.com"},
            {"id": "mem_rec_3", "text": "Batch text 3", "domain": "sfplanninggis.org"}
        ])
        assert store.count() == 3
        assert store.count(domain="zillow.com") == 2

        # Delete & Clear
        assert store.delete("mem_rec_2") is True
        assert store.count() == 2
        store.clear()
        assert store.count() == 0


def test_lesson_store_subsecond_corruption_backup_uniqueness():
    """Verifies that rapid sub-second corruptions produce distinct backup files with high-precision timestamp + uuid."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        ledger_path = os.path.join(tmp_dir, "test_rapid_corrupt.json")

        store = LessonStore(file_path=ledger_path)
        # Create 3 successive corrupted states in rapid succession
        for i in range(3):
            with open(ledger_path, "w", encoding="utf-8") as f:
                f.write(f"{{INVALID_JSON_CORRUPTION_{i}_NOT_A_LIST")
            loaded = store.load_lessons()
            assert loaded == []
            assert store.count() == 0

        backup_files = [f for f in os.listdir(tmp_dir) if "test_rapid_corrupt.json.corrupt." in f]
        assert len(backup_files) == 3, f"Expected 3 distinct backup files, found {len(backup_files)}: {backup_files}"
        for bf in backup_files:
            # Check format: .corrupt.<float>_<uuid>
            suffix = bf.split(".corrupt.")[1]
            assert "_" in suffix
            ts_part, uuid_part = suffix.split("_", 1)
            assert float(ts_part) > 0
            assert len(uuid_part) == 6

