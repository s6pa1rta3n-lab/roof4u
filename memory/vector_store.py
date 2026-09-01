"""
memory/vector_store.py

Embedded SQLite + NumPy LocalVectorStore for Roo4u.
Provides 100% offline, persistent vector storage with metadata filtering,
zero-copy BLOB deserialization, and vectorized cosine similarity search.
"""

import os
import sqlite3
import json
import threading
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any, Union
from dataclasses import dataclass, field
import numpy as np

from memory.embeddings import OfflineEmbeddingGenerator
from memory.lesson_store import LessonStore, Lesson


@dataclass
class VectorRecord:
    id: str
    text: str
    domain: str = "general"
    failure_type: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    embedding: Optional[np.ndarray] = None
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


@dataclass
class SearchResult:
    record: VectorRecord
    score: float
    rank: int


class LocalVectorStore:
    """
    Embedded SQLite + NumPy vector database.
    Stores high-dimensional float32 embeddings as raw BLOBs and computes
    vectorized matrix dot products for sub-millisecond similarity retrieval.
    """
    def __init__(
        self,
        db_path: str = "memory/vector_store.sqlite",
        embedding_generator: Optional[OfflineEmbeddingGenerator] = None
    ):
        self.db_path = db_path
        self._mem_conn: Optional[sqlite3.Connection] = None
        # Ensure parent directory exists for file-backed SQLite
        if self.db_path != ":memory:":
            db_dir = os.path.dirname(os.path.abspath(self.db_path))
            if db_dir:
                os.makedirs(db_dir, exist_ok=True)
        else:
            self._mem_conn = sqlite3.connect(":memory:", timeout=30.0, check_same_thread=False)

        self.embedder = embedding_generator or OfflineEmbeddingGenerator()
        self._lock = threading.RLock()
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        if self.db_path == ":memory:":
            if self._mem_conn is None:
                self._mem_conn = sqlite3.connect(":memory:", timeout=30.0, check_same_thread=False)
            return self._mem_conn
        conn = sqlite3.connect(self.db_path, timeout=30.0, check_same_thread=False)
        conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA synchronous = NORMAL;")
        return conn

    def close(self) -> None:
        """Closes any persistent in-memory connection."""
        with self._lock:
            if self._mem_conn is not None:
                try:
                    self._mem_conn.close()
                except Exception:
                    pass
                self._mem_conn = None

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass

    def __enter__(self) -> "LocalVectorStore":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()

    def _init_db(self) -> None:
        with self._lock:
            with self._get_connection() as conn:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS vector_records (
                        id TEXT PRIMARY KEY,
                        domain TEXT NOT NULL,
                        failure_type TEXT,
                        text TEXT NOT NULL,
                        metadata_json TEXT NOT NULL,
                        embedding BLOB NOT NULL,
                        created_at TEXT NOT NULL
                    );
                """)
                conn.execute("CREATE INDEX IF NOT EXISTS idx_vrec_domain ON vector_records(domain);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_vrec_ftype ON vector_records(failure_type);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_vrec_created ON vector_records(created_at);")

    def upsert(
        self,
        id: Optional[str] = None,
        text: str = "",
        domain: str = "general",
        failure_type: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        embedding: Optional[np.ndarray] = None,
        doc_id: Optional[str] = None
    ) -> VectorRecord:
        """
        Upserts a single document vector record into SQLite.
        Accepts both `id` and `doc_id` for interface flexibility.
        """
        rec_id = id or doc_id
        if not rec_id:
            raise ValueError("Must provide either 'id' or 'doc_id' for vector record upsert.")

        if embedding is None:
            embedding = self.embedder.embed_text(text)
        else:
            embedding = embedding.astype(np.float32)

        meta_dict = metadata or {}
        meta_json = json.dumps(meta_dict)
        emb_blob = embedding.tobytes()
        now_iso = datetime.now(timezone.utc).isoformat()

        with self._lock:
            with self._get_connection() as conn:
                conn.execute("""
                    INSERT INTO vector_records (id, domain, failure_type, text, metadata_json, embedding, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        domain = excluded.domain,
                        failure_type = excluded.failure_type,
                        text = excluded.text,
                        metadata_json = excluded.metadata_json,
                        embedding = excluded.embedding,
                        created_at = excluded.created_at;
                """, (rec_id, domain, failure_type, text, meta_json, emb_blob, now_iso))

        return VectorRecord(
            id=rec_id,
            text=text,
            domain=domain,
            failure_type=failure_type,
            metadata=meta_dict,
            embedding=embedding,
            created_at=now_iso
        )

    def upsert_batch(self, records: List[Dict[str, Any]]) -> int:
        """
        Batch upserts multiple records within a single transaction.
        """
        if not records:
            return 0

        count = 0
        with self._lock:
            with self._get_connection() as conn:
                for r in records:
                    r_id = r.get("id") or r.get("doc_id")
                    if not r_id:
                        continue
                    text = r.get("text", "")
                    domain = r.get("domain", "general")
                    failure_type = r.get("failure_type")
                    metadata = r.get("metadata", {})
                    emb = r.get("embedding")
                    if emb is None:
                        emb = self.embedder.embed_text(text)
                    else:
                        emb = emb.astype(np.float32)

                    emb_blob = emb.tobytes()
                    now_iso = datetime.now(timezone.utc).isoformat()

                    conn.execute("""
                        INSERT INTO vector_records (id, domain, failure_type, text, metadata_json, embedding, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            domain = excluded.domain,
                            failure_type = excluded.failure_type,
                            text = excluded.text,
                            metadata_json = excluded.metadata_json,
                            embedding = excluded.embedding,
                            created_at = excluded.created_at;
                    """, (r_id, domain, failure_type, text, json.dumps(metadata), emb_blob, now_iso))
                    count += 1
        return count

    def get(self, record_id: str) -> Optional[VectorRecord]:
        """Retrieves a single record by ID with its unpacked NumPy embedding vector."""
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "SELECT id, domain, failure_type, text, metadata_json, embedding, created_at FROM vector_records WHERE id = ?",
                    (record_id,)
                )
                row = cursor.fetchone()
                if not row:
                    return None
                r_id, domain, ftype, text, meta_json, blob, created_at = row
                emb = np.frombuffer(blob, dtype=np.float32)
                return VectorRecord(
                    id=r_id,
                    domain=domain,
                    failure_type=ftype,
                    text=text,
                    metadata=json.loads(meta_json),
                    embedding=emb,
                    created_at=created_at
                )

    def delete(self, record_id: str) -> bool:
        """Deletes a record by ID. Returns True if deleted."""
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("DELETE FROM vector_records WHERE id = ?", (record_id,))
                return cursor.rowcount > 0

    def update_metadata(self, record_id: str, metadata_updates: Dict[str, Any]) -> bool:
        """Updates metadata dictionary for an existing record."""
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT metadata_json FROM vector_records WHERE id = ?", (record_id,))
                row = cursor.fetchone()
                if not row:
                    return False
                curr_meta = json.loads(row[0])
                curr_meta.update(metadata_updates)
                cursor.execute(
                    "UPDATE vector_records SET metadata_json = ? WHERE id = ?",
                    (json.dumps(curr_meta), record_id)
                )
                return cursor.rowcount > 0

    def search(
        self,
        query_text: Optional[str] = None,
        query_embedding: Optional[np.ndarray] = None,
        top_k: int = 5,
        domain: Optional[str] = None,
        failure_type: Optional[str] = None,
        min_similarity: float = -1.0
    ) -> List[SearchResult]:
        """
        Executes semantic vector search:
        1. Queries candidate rows in SQLite (applying domain/failure_type filters).
        2. Unpacks binary BLOBs into contiguous float32 NumPy matrix.
        3. Computes batch cosine dot products.
        4. Sorts descending and returns top_k matches exceeding min_similarity.
        """
        if query_embedding is None:
            if not query_text:
                raise ValueError("Must provide either query_text or query_embedding for search.")
            query_embedding = self.embedder.embed_text(query_text)
        else:
            query_embedding = query_embedding.astype(np.float32)

        sql = "SELECT id, domain, failure_type, text, metadata_json, embedding, created_at FROM vector_records WHERE 1=1"
        params: List[Any] = []
        if domain:
            sql += " AND domain = ?"
            params.append(domain)
        if failure_type:
            sql += " AND failure_type = ?"
            params.append(failure_type)

        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(sql, params)
                rows = cursor.fetchall()

        if not rows:
            return []

        records = []
        embeddings = []
        for r_id, r_dom, r_ftype, r_text, r_meta_json, r_blob, r_created in rows:
            emb = np.frombuffer(r_blob, dtype=np.float32)
            rec = VectorRecord(
                id=r_id,
                domain=r_dom,
                failure_type=r_ftype,
                text=r_text,
                metadata=json.loads(r_meta_json),
                embedding=emb,
                created_at=r_created
            )
            records.append(rec)
            embeddings.append(emb)

        doc_matrix = np.vstack(embeddings)
        scores = self.embedder.batch_cosine_similarity(query_embedding, doc_matrix)

        valid_indices = np.where(scores >= min_similarity)[0]
        if len(valid_indices) == 0:
            return []

        filtered_scores = scores[valid_indices]
        sorted_order = np.argsort(-filtered_scores)[:top_k]

        results = []
        for rank, idx_in_valid in enumerate(sorted_order, start=1):
            orig_idx = valid_indices[idx_in_valid]
            results.append(
                SearchResult(
                    record=records[orig_idx],
                    score=float(scores[orig_idx]),
                    rank=rank
                )
            )
        return results

    def count(self, domain: Optional[str] = None) -> int:
        """Returns the number of vector records stored."""
        sql = "SELECT COUNT(*) FROM vector_records"
        params: List[Any] = []
        if domain:
            sql += " WHERE domain = ?"
            params.append(domain)
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(sql, params)
                return int(cursor.fetchone()[0])

    def clear(self) -> None:
        """Deletes all records from the vector store."""
        with self._lock:
            with self._get_connection() as conn:
                conn.execute("DELETE FROM vector_records;")


def sync_stores(lesson_store: LessonStore, vector_store: LocalVectorStore) -> int:
    """
    Reads all lessons from LessonStore and indexes any missing records into LocalVectorStore.
    Returns the count of synchronized records.
    """
    lessons = lesson_store.load_lessons()
    synced_count = 0
    for l in lessons:
        doc_text = (
            f"[{l.domain}] [{l.failure_type}] {l.error_message} | "
            f"{l.lesson_learned or l.root_cause_analysis} | "
            f"Action: {l.recommended_action or l.recommended_workaround}"
        )
        vector_store.upsert(
            id=l.id,
            text=doc_text,
            domain=l.domain,
            failure_type=l.failure_type,
            metadata=l.model_dump()
        )
        synced_count += 1
    return synced_count
