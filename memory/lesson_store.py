"""
memory/lesson_store.py

Atomic, thread-safe JSON Lesson Store for Roo4u.
Provides persistence for failure telemetry, self-healing workarounds,
and feedforward lessons learned with POSIX atomic swaps and corruption recovery.
"""

import os
import json
import time
import uuid
import tempfile
import threading
import logging
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any, Union
from pydantic import BaseModel, Field, model_validator

logger = logging.getLogger(__name__)


class Lesson(BaseModel):
    """
    Structured lesson schema for scraping failures and self-healing resolutions.
    Compatible with both memory_design.md and learning_loop_design.md contracts.
    """
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    domain: str
    url: str = ""
    source_url: Optional[str] = None
    failure_type: str = "UNKNOWN"
    error_category: Optional[str] = None
    error_message: str = ""
    lesson_learned: str = ""
    recommended_action: str = ""
    root_cause_analysis: Optional[str] = None
    strategy_attempted: Optional[str] = None
    recommended_workaround: Optional[str] = None
    suggested_selectors: List[str] = Field(default_factory=list)
    suggested_delay_seconds: float = 0.0
    suggested_headers: Dict[str, str] = Field(default_factory=dict)
    code_patch_suggestion: Optional[str] = None
    github_issue_number: Optional[int] = None
    github_issue_url: Optional[str] = None
    timestamp: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    dom_snippet: Optional[str] = None
    resolved: bool = False
    status: str = "ACTIVE"
    occurrence_count: int = 1
    success_count_after_workaround: int = 0
    metadata: Dict[str, Any] = Field(default_factory=dict)
    tags: List[str] = Field(default_factory=list)
    target_entity: Optional[str] = None
    phase: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def sync_aliases(cls, values: Any) -> Any:
        if isinstance(values, dict):
            # Sync url and source_url
            if not values.get("url") and values.get("source_url"):
                values["url"] = values["source_url"]
            elif values.get("url") and not values.get("source_url"):
                values["source_url"] = values["url"]

            # Sync failure_type and error_category
            if not values.get("failure_type") or values.get("failure_type") == "UNKNOWN":
                if values.get("error_category"):
                    values["failure_type"] = str(values["error_category"])
            if not values.get("error_category") and values.get("failure_type"):
                values["error_category"] = values["failure_type"]

            # Sync lesson_learned and root_cause_analysis
            if not values.get("lesson_learned") and values.get("root_cause_analysis"):
                values["lesson_learned"] = values["root_cause_analysis"]
            elif values.get("lesson_learned") and not values.get("root_cause_analysis"):
                values["root_cause_analysis"] = values["lesson_learned"]

            # Sync recommended_action and recommended_workaround
            if not values.get("recommended_action") and values.get("recommended_workaround"):
                values["recommended_action"] = values["recommended_workaround"]
            elif values.get("recommended_action") and not values.get("recommended_workaround"):
                values["recommended_workaround"] = values["recommended_action"]

        return values


class LessonStore:
    """
    Thread-safe and process-safe manager for lessons_learned.json.
    Enforces atomic file writes, crash resilience, and corruption recovery.
    """
    def __init__(self, file_path: Optional[str] = None):
        self.file_path = os.path.abspath(file_path or "lessons_learned.json")
        self._lock = threading.RLock()
        self._ensure_file_exists()

    def _ensure_file_exists(self) -> None:
        with self._lock:
            if not os.path.exists(self.file_path):
                self._atomic_write([])

    def _atomic_write(self, data: List[Dict[str, Any]]) -> None:
        """
        Executes POSIX atomic file replacement using a temporary file in the same directory.
        Forces disk flush via os.fsync to survive abrupt crashes.
        """
        dir_name = os.path.dirname(os.path.abspath(self.file_path)) or "."
        os.makedirs(dir_name, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", dir=dir_name, delete=False, encoding="utf-8") as tf:
            json.dump(data, tf, indent=2)
            tf.flush()
            os.fsync(tf.fileno())
            temp_name = tf.name
        os.replace(temp_name, self.file_path)

    def load_lessons(self) -> List[Lesson]:
        """Loads and validates all lessons from the JSON ledger with corruption recovery."""
        with self._lock:
            if not os.path.exists(self.file_path):
                return []
            try:
                with open(self.file_path, "r", encoding="utf-8") as f:
                    content = f.read().strip()
                    if not content:
                        return []
                    raw_list = json.loads(content)
                    if not isinstance(raw_list, list):
                        raise ValueError(f"Root JSON is not a list: {type(raw_list)}")
                    return [Lesson.model_validate(item) for item in raw_list]
            except Exception as e:
                logger.warning(f"Corrupted lesson store detected: {e}. Backing up and resetting.")
                backup_path = f"{self.file_path}.corrupt.{time.time():.6f}_{uuid.uuid4().hex[:6]}"
                try:
                    os.rename(self.file_path, backup_path)
                except Exception:
                    pass
                self._atomic_write([])
                return []

    def _load_lessons(self) -> List[Lesson]:
        """Internal/alias method for load_lessons."""
        return self.load_lessons()

    def load_all(self) -> List[Lesson]:
        """Alias for load_lessons."""
        return self.load_lessons()

    def add_lesson(self, lesson: Union[Lesson, Dict[str, Any]]) -> Lesson:
        """
        Appends or updates a lesson atomically.
        If a lesson with the same ID already exists, it is updated in-place.
        """
        if isinstance(lesson, dict):
            lesson_obj = Lesson.model_validate(lesson)
        else:
            lesson_obj = lesson

        with self._lock:
            lessons = self.load_lessons()
            found = False
            for idx, existing in enumerate(lessons):
                if existing.id == lesson_obj.id:
                    lessons[idx] = lesson_obj
                    found = True
                    break

            if not found:
                lessons.append(lesson_obj)

            self._atomic_write([l.model_dump() for l in lessons])
            return lesson_obj

    def upsert_lesson(self, lesson: Union[Lesson, Dict[str, Any]]) -> Lesson:
        """Alias for add_lesson."""
        return self.add_lesson(lesson)

    def get_lesson(self, lesson_id: str) -> Optional[Lesson]:
        """Retrieves a lesson by its unique ID."""
        with self._lock:
            for l in self.load_lessons():
                if l.id == lesson_id:
                    return l
            return None

    def get(self, lesson_id: str) -> Optional[Lesson]:
        """Alias for get_lesson."""
        return self.get_lesson(lesson_id)

    def list_lessons(
        self,
        domain: Optional[str] = None,
        failure_type: Optional[str] = None,
        limit: Optional[int] = None
    ) -> List[Lesson]:
        """Filters and returns lessons matching optional domain and failure_type criteria."""
        with self._lock:
            results = self.load_lessons()
            if domain:
                results = [l for l in results if l.domain.lower() == domain.lower()]
            if failure_type:
                results = [
                    l for l in results
                    if l.failure_type.upper() == failure_type.upper()
                    or (l.error_category and l.error_category.upper() == failure_type.upper())
                ]
            if limit is not None and limit > 0:
                results = results[:limit]
            return results

    def filter_by_domain(self, domain: str) -> List[Lesson]:
        """Retrieves all lessons for a specific domain."""
        return self.list_lessons(domain=domain)

    def update_lesson(self, lesson_id: str, updates: Dict[str, Any]) -> Optional[Lesson]:
        """Atomically updates specific fields of an existing lesson."""
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

    def increment_success(self, lesson_id: str) -> Optional[Lesson]:
        """Increments the success_count_after_workaround counter for a lesson."""
        with self._lock:
            lessons = self.load_lessons()
            for idx, l in enumerate(lessons):
                if l.id == lesson_id:
                    l.success_count_after_workaround += 1
                    if l.success_count_after_workaround >= 5 and l.status == "ACTIVE":
                        l.status = "RESOLVED"
                        l.resolved = True
                    lessons[idx] = l
                    self._atomic_write([x.model_dump() for x in lessons])
                    return l
            return None

    def delete_lesson(self, lesson_id: str) -> bool:
        """Atomically deletes a lesson by ID."""
        with self._lock:
            lessons = self.load_lessons()
            initial_len = len(lessons)
            lessons = [l for l in lessons if l.id != lesson_id]
            if len(lessons) < initial_len:
                self._atomic_write([l.model_dump() for l in lessons])
                return True
            return False

    def count(self, domain: Optional[str] = None) -> int:
        """Returns the count of stored lessons, optionally filtered by domain."""
        return len(self.list_lessons(domain=domain))

    def clear(self) -> None:
        """Atomically resets the store to an empty list."""
        with self._lock:
            self._atomic_write([])
