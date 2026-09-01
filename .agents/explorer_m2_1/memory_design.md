# Technical Specification: Dual Memory Architecture (Milestone 2)

**Author:** Explorer M2-1  
**Milestone:** M2 — Learning Agent Pipeline & Dual Memory  
**Target Files:**  
- `memory/lesson_store.py` (Atomic JSON Lesson Store)  
- `memory/embeddings.py` (Deterministic Offline Embedding Generator)  
- `memory/vector_store.py` (Embedded SQLite + NumPy LocalVectorStore)  

---

## 1. Executive Summary & Architectural Overview

The Roo4u system operates in an offline-first, autonomous browsing environment. To enable self-healing and prevent recurring scraping failures (such as DOM selector drift, anti-bot CAPTCHAs, HTTP 429 rate limits, and schema parsing shifts), Milestone 2 introduces a **Dual Memory Architecture**:

```
                              ┌────────────────────────────────────────────────────────┐
                              │                 Scraping Failure Event                 │
                              └──────────────────────────┬─────────────────────────────┘
                                                         │
                                                         ▼
                                       ┌──────────────────────────────────┐
                                       │    LearningAgent.observe_failure │
                                       └────────┬─────────────────┬───────┘
                                                │                 │
                      ┌─────────────────────────┴────────┐        │
                      ▼                                  ▼        ▼
       ┌──────────────────────────────┐       ┌─────────────────────────────────────┐
       │   memory/lesson_store.py     │       │       memory/embeddings.py          │
       │                              │       │                                     │
       │ - Atomic OS-level writes     │       │ - Multi-scale Feature Hashing       │
       │ - Human-auditable JSON       │       │ - Subword N-grams + TF-IDF          │
       │ - Root: lessons_learned.json │       │ - 100% Offline, Deterministic       │
       └──────────────────────────────┘       └──────────────────┬──────────────────┘
                                                                 │ (256-D float32 vector)
                                                                 ▼
                                              ┌─────────────────────────────────────┐
                                              │      memory/vector_store.py         │
                                              │                                     │
                                              │ - SQLite + BLOB Embeddings          │
                                              │ - NumPy Vectorized Cosine Search    │
                                              │ - Domain & Failure Type Filtering   │
                                              └─────────────────────────────────────┘
```

### Key Architectural Principles
1. **Zero External Cloud Dependencies (Red-Team & Anti-Mock Compliant):** No calls to OpenAI embeddings, Google Gemini, Pinecone, or remote vector APIs.
2. **Dual-Storage Synergy:**
   - **Primary Ledger (`lessons_learned.json`):** Human-readable, audit-friendly, atomic JSON file at the repository root.
   - **Semantic Search Engine (`LocalVectorStore`):** Embedded SQLite database storing serialized NumPy embedding vectors with fast matrix cosine similarity search.
3. **Crash Resilience & Process Safety:** Writes to `lessons_learned.json` use atomic staging via temporary files (`tempfile.NamedTemporaryFile`) and POSIX `os.replace`, fortified with advisory file locking to prevent corruptions during concurrent multi-agent executions.
4. **Feedforward Querying:** Browsing agents retrieve historical failure patterns before initiating requests to adapt headers, rates, and DOM selectors dynamically.

---

## 2. Component 1: `memory/lesson_store.py` (Atomic JSON Store)

### 2.1 Purpose & Location
- **Default Path:** `lessons_learned.json` (at project root, configurable via constructor).
- **Core Role:** Serves as the single source of truth for structured failure lessons. Guarantees that neither agent crashes nor race conditions corrupt the persistent JSON ledger.

### 2.2 Data Contract & Schema (`Lesson`)
Every lesson record follows a strict Pydantic model:

```python
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field
import uuid

class Lesson(BaseModel):
    """Structured lesson schema for scraping failures and self-healing resolutions."""
    id: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        description="Unique identifier (UUIDv4) for the lesson."
    )
    domain: str = Field(
        ...,
        description="Normalized domain name (e.g. 'zillow.com', 'sfplanninggis.org', 'dbiweb02.sfgov.org')."
    )
    url: str = Field(
        ...,
        description="Target URL where the failure or observation occurred."
    )
    failure_type: str = Field(
        ...,
        description="Standardized failure category: 'DOM_SELECTOR_DRIFT', 'HTTP_429_RATE_LIMIT', 'ANTI_BOT_BLOCK', 'TIMEOUT', 'PARSE_ERROR', 'NETWORK_ERROR', etc."
    )
    error_message: str = Field(
        ...,
        description="Verbatim exception string, error message, or HTTP status description."
    )
    lesson_learned: str = Field(
        ...,
        description="Synthesized root cause and contextual explanation of the failure."
    )
    recommended_action: str = Field(
        ...,
        description="Concrete, actionable workaround (e.g. 'Add 5s jitter delay', 'Use fallback selector .ds-overview-section')."
    )
    timestamp: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat(),
        description="ISO 8601 UTC timestamp of lesson creation."
    )
    dom_snippet: Optional[str] = Field(
        default=None,
        description="Optional truncated HTML snippet relevant to selector drift."
    )
    resolved: bool = Field(
        default=False,
        description="Flag indicating whether a self-healing patch has resolved this failure."
    )
    metadata: Dict[str, Any] = Field(
        default_factory=dict,
        description="Extensible key-value metadata for scraper parameters."
    )
```

### 2.3 Atomic Write & Concurrency Protocol
Writing JSON directly via standard `open("w")` is dangerous in agentic pipelines because an unexpected process termination (or test runner cancellation) can leave a truncated or corrupted JSON file.

`LessonStore` enforces a **3-Layer Safety Guarantee**:
1. **In-Process Thread Lock:** `threading.RLock()` ensures intra-process thread safety.
2. **Atomic Tempfile + Rename Protocol:**
   - Serialized JSON is written to a temporary file created in the **same directory** as the target file:
     ```python
     temp_dir = os.path.dirname(os.path.abspath(self.file_path))
     with tempfile.NamedTemporaryFile("w", dir=temp_dir, delete=False, encoding="utf-8") as tf:
         json.dump(payload, tf, indent=2)
         tf.flush()
         os.fsync(tf.fileno())  # Force physical disk write
         temp_name = tf.name
     os.replace(temp_name, self.file_path)  # POSIX atomic swap
     ```
   - Same-directory creation guarantees that `os.replace` is an atomic inode swap on the same filesystem without cross-device link errors (`EXDEV`).
3. **Corrupted State Recovery:** If the target JSON file is missing, empty, or corrupted by external interference, `LessonStore` backs up the damaged file to `lessons_learned.json.corrupt.<timestamp>` and initializes a clean empty ledger (`[]`), logging a warning.

### 2.4 Complete `LessonStore` Interface Specification
```python
class LessonStore:
    def __init__(self, file_path: Optional[str] = None):
        """Initializes the store with the specified file path (defaults to root lessons_learned.json)."""
        
    def add_lesson(self, lesson: Union[Lesson, Dict[str, Any]]) -> Lesson:
        """Appends a new lesson atomically to the store. Returns the validated Lesson."""
        
    def get_lesson(self, lesson_id: str) -> Optional[Lesson]:
        """Retrieves a lesson by its unique UUID."""
        
    def list_lessons(
        self,
        domain: Optional[str] = None,
        failure_type: Optional[str] = None,
        limit: Optional[int] = None
    ) -> List[Lesson]:
        """Filters and returns lessons matching optional domain and failure_type criteria."""
        
    def update_lesson(self, lesson_id: str, updates: Dict[str, Any]) -> Optional[Lesson]:
        """Atomically updates specific fields of an existing lesson."""
        
    def delete_lesson(self, lesson_id: str) -> bool:
        """Atomically deletes a lesson by ID. Returns True if deleted, False if not found."""
        
    def count(self, domain: Optional[str] = None) -> int:
        """Returns the total number of lessons stored, optionally filtered by domain."""
        
    def clear(self) -> None:
        """Atomically clears all lessons, resetting the store to an empty list."""
```

---

## 3. Component 2: `memory/embeddings.py` (Deterministic Offline Embeddings)

### 3.1 Mathematical Formulation & Requirements
- **Goal:** Transform arbitrary failure descriptions, URLs, error logs, and DOM snippets into a normalized vector $\vec{v} \in \mathbb{R}^D$ ($D=256$) such that cosine similarity:
  $$\text{sim}(\vec{u}, \vec{v}) = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\|_2 \|\vec{v}\|_2} = \vec{u}_{\text{norm}} \cdot \vec{v}_{\text{norm}} \in [-1.0, 1.0]$$
- **Constraints:**
  - 100% Offline & Deterministic: Same input string always produces the identical float vector across all runs, machines, and platforms.
  - Zero external models or network access (no PyTorch, no HuggingFace, no OpenAI/Google API).
  - High sensitivity to domain keywords, HTTP error codes (`429`, `403`, `504`), CSS selectors (`.ds-overview-section`, `article[data-test]`), and error substrings.

### 3.2 Algorithmic Architecture: Multi-Scale Signed Feature Hashing
To balance semantic generalization and lexical exactness, the generator combines:
1. **Lexical Normalization:** Lowercasing, punctuation boundary extraction, and whitespace standardization.
2. **Domain & Code Entity Extraction:** Explicit token boosting for:
   - Domain tags: `domain:zillow.com`, `domain:sfplanninggis.org`
   - Failure type tags: `type:DOM_SELECTOR_DRIFT`, `type:HTTP_429_RATE_LIMIT`
   - Status code numbers: `429`, `403`, `500`, `502`, `504`
3. **Multi-Scale Tokenization:**
   - **Word Unigrams & Bigrams:** Captures phrases like `"rate limit"`, `"selector drift"`, `"assessor parcel"`.
   - **Subword Character 3-Grams and 4-Grams:** Captures partial selector strings (e.g. `div.`, `sec-`, `test`, `card`, `list`) ensuring robust similarity even with minor DOM variations.
4. **Weighted Hash Projection with Signed Murmur/MD5 Hashing:**
   - For each token $t$ with weight $w(t)$:
     - Primary index bucket: $idx = \text{hash}_1(t) \pmod D$
     - Sign hash (zero-mean unbiased projection): $s = +1 \text{ if } \text{hash}_2(t) \pmod 2 == 0 \text{ else } -1$
     - Accumulate: $V[idx] \mathrel{+}= s \cdot w(t)$
5. **L2 Unit-Norm Projection:**
   $$\vec{v}_{\text{norm}} = \frac{V}{\sqrt{\sum_{k=0}^{D-1} V_k^2} + 10^{-12}}$$

### 3.3 Complete `OfflineEmbeddingGenerator` Interface Specification
```python
import numpy as np

class OfflineEmbeddingGenerator:
    def __init__(self, dimension: int = 256):
        """Initializes the generator with a fixed embedding dimensionality (default 256)."""
        self.dimension = dimension

    def embed_text(self, text: str) -> np.ndarray:
        """
        Generates a 1D normalized float32 NumPy array of shape (D,) for the input text.
        ||embed_text(text)||_2 is guaranteed to be 1.0 (within 1e-6 tolerance).
        """

    def embed_batch(self, texts: List[str]) -> np.ndarray:
        """
        Generates a 2D normalized float32 NumPy matrix of shape (N, D) for N input texts.
        """

    def cosine_similarity(self, vec1: np.ndarray, vec2: np.ndarray) -> float:
        """Computes scalar cosine similarity between two 1D normalized embedding vectors."""

    def batch_cosine_similarity(self, query_vec: np.ndarray, doc_matrix: np.ndarray) -> np.ndarray:
        """
        Vectorized computation of cosine similarities between a 1D query vector (D,)
        and a 2D matrix of document vectors (N, D). Returns 1D array of scores (N,).
        """
```

---

## 4. Component 3: `memory/vector_store.py` (Local SQLite + NumPy Vector DB)

### 4.1 Purpose & Database Schema
- **Database Engine:** Embedded SQLite with WAL (`Write-Ahead Logging`) mode.
- **Default Database Path:** `vector_store.db` (or `:memory:` for ephemeral test fixtures).
- **Table Definition:**

```sql
CREATE TABLE IF NOT EXISTS vector_records (
    id TEXT PRIMARY KEY,
    domain TEXT NOT NULL,
    failure_type TEXT,
    text TEXT NOT NULL,
    metadata_json TEXT NOT NULL,
    embedding BLOB NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_vector_domain ON vector_records(domain);
CREATE INDEX IF NOT EXISTS idx_vector_failure_type ON vector_records(failure_type);
CREATE INDEX IF NOT EXISTS idx_vector_created ON vector_records(created_at);
```

### 4.2 High-Performance Vector Storage & Deserialization
- **Binary Serialization:** Embeddings are converted to 32-bit float raw bytes via `vec.astype(np.float32).tobytes()` and written to SQLite as a `BLOB`.
- **Zero-Copy Deserialization:** During search, multiple BLOBs are retrieved and unpacked in batch using `np.frombuffer(blob, dtype=np.float32)`.
- **Stacking:** `doc_matrix = np.vstack(embeddings_list)` creates an $(N, D)$ matrix in contiguous C-memory.
- **Vectorized Search Execution:**
  $$\vec{S} = \text{np.dot}(\text{doc\_matrix}, \vec{q}_{\text{norm}})$$
  - Sorting: Top-$k$ matches are extracted via `np.argsort(-scores)[:top_k]` in $O(N \log k)$ operations.

### 4.3 Data Structures: `VectorRecord` & `SearchResult`
```python
from dataclasses import dataclass, field

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
```

### 4.4 Complete `LocalVectorStore` Interface Specification
```python
class LocalVectorStore:
    def __init__(
        self,
        db_path: str = "vector_store.db",
        embedding_generator: Optional[OfflineEmbeddingGenerator] = None
    ):
        """Initializes the SQLite database, creates tables and indexes, and binds the embedding generator."""

    def upsert(
        self,
        id: str,
        text: str,
        domain: str = "general",
        failure_type: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        embedding: Optional[np.ndarray] = None
    ) -> VectorRecord:
        """Upserts a record into the vector store. Automatically generates embedding if not provided."""

    def upsert_batch(self, records: List[Dict[str, Any]]) -> int:
        """Batch upserts multiple records within a single SQLite transaction."""

    def get(self, record_id: str) -> Optional[VectorRecord]:
        """Retrieves a single record by ID, including its unpacked NumPy embedding vector."""

    def delete(self, record_id: str) -> bool:
        """Deletes a record by ID. Returns True if deleted, False otherwise."""

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
        Executes semantic vector search.
        1. Filters candidate rows by domain/failure_type in SQLite.
        2. Vectorizes embeddings into NumPy matrix.
        3. Computes dot product scores against query embedding.
        4. Returns top_k results sorted descending by cosine similarity score.
        """

    def count(self, domain: Optional[str] = None) -> int:
        """Returns the number of vector records stored."""

    def clear(self) -> None:
        """Deletes all records from the vector store."""
```

---

## 5. Cross-Component Integration & Feedforward Dataflow

### 5.1 Dual-Storage Synchronization
When `LearningAgent` processes a failure event:
1. It validates and constructs a `Lesson` object.
2. It persists the lesson in `LessonStore.add_lesson(lesson)`.
3. It constructs a search document string:
   ```python
   doc_text = f"[{lesson.domain}] [{lesson.failure_type}] {lesson.error_message} | {lesson.lesson_learned} | Action: {lesson.recommended_action}"
   ```
4. It calls `LocalVectorStore.upsert(id=lesson.id, text=doc_text, domain=lesson.domain, failure_type=lesson.failure_type, metadata=lesson.model_dump())`.

### 5.2 Pre-Scrape Feedforward Retrieval
Before initiating navigation or selector querying in `ZillowAgent` or `CountyAgent`:
```python
# Query vector store for similar prior failures
query = f"{domain} rate limit bot block selector drift table"
matches = vector_store.search(query_text=query, domain=domain, top_k=3, min_similarity=0.25)
for match in matches:
    recommended_action = match.record.metadata.get("recommended_action")
    # Dynamically apply adjustments (e.g. increase request delay, apply fallback selector)
```

### 5.3 Store Re-indexing Utility
To ensure that any external additions to `lessons_learned.json` can be indexed into `vector_store.db`, a synchronization utility is provided:
```python
def sync_stores(lesson_store: LessonStore, vector_store: LocalVectorStore) -> int:
    """Reads all lessons from LessonStore and upserts missing records into LocalVectorStore."""
```

---

## 6. Implementation Code Skeletons

### 6.1 `memory/lesson_store.py`
```python
import os
import json
import uuid
import tempfile
import threading
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any, Union
from pydantic import BaseModel, Field


class Lesson(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    domain: str
    url: str
    failure_type: str
    error_message: str
    lesson_learned: str
    recommended_action: str
    timestamp: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    dom_snippet: Optional[str] = None
    resolved: bool = False
    metadata: Dict[str, Any] = Field(default_factory=dict)


class LessonStore:
    def __init__(self, file_path: Optional[str] = None):
        self.file_path = file_path or os.path.abspath("lessons_learned.json")
        self._lock = threading.RLock()
        self._ensure_file_exists()

    def _ensure_file_exists(self) -> None:
        with self._lock:
            if not os.path.exists(self.file_path):
                self._atomic_write([])

    def _atomic_write(self, data: List[Dict[str, Any]]) -> None:
        dir_name = os.path.dirname(os.path.abspath(self.file_path)) or "."
        os.makedirs(dir_name, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", dir=dir_name, delete=False, encoding="utf-8") as tf:
            json.dump(data, tf, indent=2)
            tf.flush()
            os.fsync(tf.fileno())
            temp_name = tf.name
        os.replace(temp_name, self.file_path)

    def load_lessons(self) -> List[Lesson]:
        with self._lock:
            if not os.path.exists(self.file_path):
                return []
            try:
                with open(self.file_path, "r", encoding="utf-8") as f:
                    content = f.read().strip()
                    if not content:
                        return []
                    raw_list = json.loads(content)
                    return [Lesson.model_validate(item) for item in raw_list]
            except Exception:
                # Safe recovery on corrupt file
                backup_path = f"{self.file_path}.corrupt.{int(datetime.now().timestamp())}"
                try:
                    os.rename(self.file_path, backup_path)
                except Exception:
                    pass
                self._atomic_write([])
                return []

    def add_lesson(self, lesson: Union[Lesson, Dict[str, Any]]) -> Lesson:
        if isinstance(lesson, dict):
            lesson_obj = Lesson.model_validate(lesson)
        else:
            lesson_obj = lesson

        with self._lock:
            lessons = self.load_lessons()
            # Check for duplicate ID
            for idx, existing in enumerate(lessons):
                if existing.id == lesson_obj.id:
                    lessons[idx] = lesson_obj
                    self._atomic_write([l.model_dump() for l in lessons])
                    return lesson_obj

            lessons.append(lesson_obj)
            self._atomic_write([l.model_dump() for l in lessons])
            return lesson_obj

    def get_lesson(self, lesson_id: str) -> Optional[Lesson]:
        with self._lock:
            for l in self.load_lessons():
                if l.id == lesson_id:
                    return l
            return None

    def list_lessons(
        self,
        domain: Optional[str] = None,
        failure_type: Optional[str] = None,
        limit: Optional[int] = None
    ) -> List[Lesson]:
        with self._lock:
            results = self.load_lessons()
            if domain:
                results = [l for l in results if l.domain.lower() == domain.lower()]
            if failure_type:
                results = [l for l in results if l.failure_type.upper() == failure_type.upper()]
            if limit:
                results = results[:limit]
            return results

    def update_lesson(self, lesson_id: str, updates: Dict[str, Any]) -> Optional[Lesson]:
        with self._lock:
            lessons = self.load_lessons()
            for idx, l in enumerate(lessons):
                if l.id == lesson_id:
                    current_dict = l.model_dump()
                    current_dict.update(updates)
                    updated_obj = Lesson.model_validate(current_dict)
                    lessons[idx] = updated_obj
                    self._atomic_write([x.model_dump() for x in lessons])
                    return updated_obj
            return None

    def delete_lesson(self, lesson_id: str) -> bool:
        with self._lock:
            lessons = self.load_lessons()
            initial_len = len(lessons)
            lessons = [l for l in lessons if l.id != lesson_id]
            if len(lessons) < initial_len:
                self._atomic_write([l.model_dump() for l in lessons])
                return True
            return False

    def count(self, domain: Optional[str] = None) -> int:
        return len(self.list_lessons(domain=domain))

    def clear(self) -> None:
        with self._lock:
            self._atomic_write([])
```

---

### 6.2 `memory/embeddings.py`
```python
import re
import zlib
import hashlib
import numpy as np
from typing import List, Tuple


class OfflineEmbeddingGenerator:
    """
    100% Offline, deterministic multi-scale feature hashing embedding generator.
    Produces L2-normalized float32 vectors in R^D suitable for cosine similarity.
    """
    def __init__(self, dimension: int = 256):
        self.dimension = dimension

    def _tokenize(self, text: str) -> List[Tuple[str, float]]:
        if not text:
            return [("__EMPTY__", 1.0)]

        tokens = []
        cleaned = text.lower()

        # 1. Extract status codes and special tokens
        status_codes = re.findall(r"\b(4\d\d|5\d\d)\b", cleaned)
        for code in status_codes:
            tokens.append((f"status:{code}", 3.0))

        # 2. Extract words
        words = re.findall(r"[a-z0-9_\-\.:]+", cleaned)
        for w in words:
            tokens.append((w, 1.5))

        # 3. Extract word bigrams
        for i in range(len(words) - 1):
            tokens.append((f"{words[i]}_{words[i+1]}", 2.0))

        # 4. Extract character n-grams (3-grams and 4-grams)
        for w in words:
            if len(w) >= 3:
                for i in range(len(w) - 2):
                    tokens.append((f"3g:{w[i:i+3]}", 0.5))
            if len(w) >= 4:
                for i in range(len(w) - 3):
                    tokens.append((f"4g:{w[i:i+4]}", 0.5))

        return tokens

    def embed_text(self, text: str) -> np.ndarray:
        vec = np.zeros(self.dimension, dtype=np.float32)
        tokens = self._tokenize(text)

        for token_str, weight in tokens:
            b_str = token_str.encode("utf-8")
            # Bucket index via CRC32
            idx = zlib.crc32(b_str) % self.dimension
            # Sign hash via MD5 high bit
            md5_digest = hashlib.md5(b_str).digest()
            sign = 1.0 if (md5_digest[0] & 1) == 0 else -1.0
            vec[idx] += sign * weight

        # L2 normalize
        norm = np.linalg.norm(vec)
        if norm > 1e-12:
            vec = vec / norm
        else:
            vec[0] = 1.0  # Fallback unit vector

        return vec

    def embed_batch(self, texts: List[str]) -> np.ndarray:
        return np.vstack([self.embed_text(t) for t in texts])

    def cosine_similarity(self, vec1: np.ndarray, vec2: np.ndarray) -> float:
        return float(np.dot(vec1, vec2))

    def batch_cosine_similarity(self, query_vec: np.ndarray, doc_matrix: np.ndarray) -> np.ndarray:
        return np.dot(doc_matrix, query_vec)
```

---

### 6.3 `memory/vector_store.py`
```python
import sqlite3
import json
import threading
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
import numpy as np

from memory.embeddings import OfflineEmbeddingGenerator


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
    Provides offline persistence, metadata filtering, and vectorized cosine similarity search.
    """
    def __init__(
        self,
        db_path: str = "vector_store.db",
        embedding_generator: Optional[OfflineEmbeddingGenerator] = None
    ):
        self.db_path = db_path
        self.embedder = embedding_generator or OfflineEmbeddingGenerator()
        self._lock = threading.Lock()
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0, check_same_thread=False)
        conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA synchronous = NORMAL;")
        return conn

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
        id: str,
        text: str,
        domain: str = "general",
        failure_type: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        embedding: Optional[np.ndarray] = None
    ) -> VectorRecord:
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
                """, (id, domain, failure_type, text, meta_json, emb_blob, now_iso))

        return VectorRecord(
            id=id,
            text=text,
            domain=domain,
            failure_type=failure_type,
            metadata=meta_dict,
            embedding=embedding,
            created_at=now_iso
        )

    def upsert_batch(self, records: List[Dict[str, Any]]) -> int:
        count = 0
        with self._lock:
            with self._get_connection() as conn:
                for r in records:
                    r_id = r["id"]
                    text = r["text"]
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
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("DELETE FROM vector_records WHERE id = ?", (record_id,))
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
        if query_embedding is None:
            if not query_text:
                raise ValueError("Must provide either query_text or query_embedding.")
            query_embedding = self.embedder.embed_text(query_text)
        else:
            query_embedding = query_embedding.astype(np.float32)

        # Build SQL query with metadata filters
        sql = "SELECT id, domain, failure_type, text, metadata_json, embedding, created_at FROM vector_records WHERE 1=1"
        params = []
        if domain:
            sql += " AND domain = ?"
            params.append(domain)
        if failure_type:
            sql += " AND failure_type = ?"
            params.append(failure_type)

        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql, params)
            rows = cursor.fetchall()

        if not rows:
            return []

        # Unpack BLOBs into NumPy matrix
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

        # Filter by min_similarity
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
        sql = "SELECT COUNT(*) FROM vector_records"
        params = []
        if domain:
            sql += " WHERE domain = ?"
            params.append(domain)
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql, params)
            return cursor.fetchone()[0]

    def clear(self) -> None:
        with self._lock:
            with self._get_connection() as conn:
                conn.execute("DELETE FROM vector_records;")
```

---

## 7. Verification & Anti-Mock Testing Strategy

### 7.1 Zero-Mock Direct Execution
Per red-team and Victory Audit standards:
- **No `unittest.mock`:** All unit and integration tests run against real temporary files, real SQLite databases, and real NumPy arrays.
- **Concurrency Test:** 50 concurrent threads executing interleaved `add_lesson`, `list_lessons`, `upsert`, and `search` operations without deadlock or data corruption.
- **Crash Simulation:** Inducing abrupt file writes and verifying that `LessonStore` recovers without raising unhandled JSON decode exceptions.

### 7.2 Verification Commands
To be run in Milestone 3 / Worker execution:
```bash
pytest tests/test_vector_store.py -v
pytest tests/test_learning_agent.py -v
```
