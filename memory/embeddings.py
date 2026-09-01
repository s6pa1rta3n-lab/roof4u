"""
memory/embeddings.py

Deterministic Offline Embedding Generator for Roo4u.
Uses multi-scale signed feature hashing with subwords and domain token boosting.
100% offline, zero external models, zero cloud APIs, zero mock dependencies.
"""

import re
import zlib
import hashlib
from typing import List, Tuple, Union
import numpy as np


class OfflineEmbeddingGenerator:
    """
    100% Offline, deterministic multi-scale feature hashing embedding generator.
    Produces L2-normalized float32 vectors in R^D suitable for cosine similarity search.
    """
    def __init__(self, dimension: int = 256):
        self.dimension = int(dimension)
        if self.dimension <= 0:
            raise ValueError(f"Embedding dimension must be positive: {dimension}")

    def _tokenize(self, text: str) -> List[Tuple[str, float]]:
        """
        Tokenizes text into multi-scale lexical, n-gram, and domain features with importance weights.
        """
        if not text or not str(text).strip():
            return [("__EMPTY__", 1.0)]

        tokens: List[Tuple[str, float]] = []
        cleaned = str(text).lower().strip()

        # 1. Extract status codes and special tokens (e.g., 403, 429, 500)
        status_codes = re.findall(r"\b(4\d\d|5\d\d)\b", cleaned)
        for code in status_codes:
            tokens.append((f"status:{code}", 3.0))

        # 2. Extract words and domain/path components
        words = re.findall(r"[a-z0-9_\-\.:#\[\]=\"]+", cleaned)
        for w in words:
            tokens.append((f"w:{w}", 1.5))

        # 3. Extract word bigrams
        for i in range(len(words) - 1):
            tokens.append((f"bi:{words[i]}_{words[i+1]}", 2.0))

        # 4. Extract character n-grams (3-grams and 4-grams) for selector and subword drift tolerance
        for w in words:
            if len(w) >= 3:
                for i in range(len(w) - 2):
                    tokens.append((f"3g:{w[i:i+3]}", 0.5))
            if len(w) >= 4:
                for i in range(len(w) - 3):
                    tokens.append((f"4g:{w[i:i+4]}", 0.5))

        return tokens

    def embed_text(self, text: str) -> np.ndarray:
        """
        Generates a 1D L2-normalized float32 NumPy array of shape (dimension,) for input text.
        Guarantees ||embed_text(text)||_2 == 1.0 within numerical precision.
        """
        vec = np.zeros(self.dimension, dtype=np.float32)
        tokens = self._tokenize(text)

        for token_str, weight in tokens:
            b_str = token_str.encode("utf-8")
            # Bucket index via CRC32
            idx = zlib.crc32(b_str) % self.dimension
            # Sign hash via MD5 high bit for zero-mean projection
            md5_digest = hashlib.md5(b_str).digest()
            sign = 1.0 if (md5_digest[0] & 1) == 0 else -1.0
            vec[idx] += sign * weight

        # L2 normalize
        norm = np.linalg.norm(vec)
        if norm > 1e-12:
            vec = vec / norm
        else:
            vec[0] = 1.0  # Fallback unit vector

        return vec.astype(np.float32)

    def embed_batch(self, texts: List[str]) -> np.ndarray:
        """
        Generates a 2D normalized float32 NumPy matrix of shape (N, dimension) for N texts.
        """
        if not texts:
            return np.empty((0, self.dimension), dtype=np.float32)
        return np.vstack([self.embed_text(t) for t in texts]).astype(np.float32)

    def cosine_similarity(self, vec1: np.ndarray, vec2: np.ndarray) -> float:
        """Computes scalar cosine similarity between two 1D normalized embedding vectors."""
        v1 = vec1.astype(np.float32)
        v2 = vec2.astype(np.float32)
        norm1 = np.linalg.norm(v1)
        norm2 = np.linalg.norm(v2)
        if norm1 > 1e-12:
            v1 = v1 / norm1
        if norm2 > 1e-12:
            v2 = v2 / norm2
        return float(np.dot(v1, v2))

    def batch_cosine_similarity(self, query_vec: np.ndarray, doc_matrix: np.ndarray) -> np.ndarray:
        """
        Vectorized computation of cosine similarities between a 1D query vector (dimension,)
        and a 2D matrix of document vectors (N, dimension). Returns 1D array of scores (N,).
        """
        if doc_matrix.size == 0:
            return np.empty(0, dtype=np.float32)
        q = query_vec.astype(np.float32)
        q_norm = np.linalg.norm(q)
        if q_norm > 1e-12:
            q = q / q_norm
        return np.dot(doc_matrix.astype(np.float32), q)
