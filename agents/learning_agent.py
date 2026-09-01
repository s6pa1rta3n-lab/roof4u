"""
agents/learning_agent.py

Learning Agent & Feedforward Loop Coordinator for Roo4u.
Orchestrates:
1. Scraping failure observation & root-cause heuristic classification.
2. Dual-memory synchronization (atomic JSON LessonStore + SQLite NumPy LocalVectorStore).
3. Live GitHub issue logging with deduplication via GitHubIssueLogger.
4. Pre-scrape feedforward strategy generation for autonomous self-healing.
5. Workaround efficacy tracking upon successful retry.
"""

import os
import re
import hashlib
import traceback
import logging
from enum import Enum
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any, Tuple, Union
from pydantic import BaseModel, Field

from memory.lesson_store import LessonStore, Lesson
from memory.vector_store import LocalVectorStore, SearchResult
from integrations.github_client import GitHubIssueLogger, ScrapingFailureEvent, IssueLogResult
from agents.extractor import LocalLLMExtractor

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Enums and Data Models
# ---------------------------------------------------------------------------

class FailureCategory(str, Enum):
    """Standardized taxonomy of scraping and extraction failures."""
    DOM_SELECTOR_DRIFT = "DOM_SELECTOR_DRIFT"           # Target element selector missing or changed
    ANTI_BOT_BLOCKED = "ANTI_BOT_BLOCKED"               # HTTP 403, Cloudflare, Captcha, Bot Challenge
    RATE_LIMIT_ERROR = "RATE_LIMIT_ERROR"               # HTTP 429 Too Many Requests
    NETWORK_TIMEOUT = "NETWORK_TIMEOUT"                 # Navigation / connect timeout
    EXTRACTION_PARSE_ERROR = "EXTRACTION_PARSE_ERROR"   # Content loaded but fields unparseable
    SCHEMA_VALIDATION_ERROR = "SCHEMA_VALIDATION_ERROR" # Extracted fields violate Pydantic schema
    INFERENCE_ENDPOINT_ERROR = "INFERENCE_ENDPOINT_ERROR" # Local LLM endpoint unreachable
    UNKNOWN = "UNKNOWN"


class FeedforwardStrategy(BaseModel):
    """Actionable pre-scrape directives compiled from historical lessons."""
    domain: str
    primary_selectors: List[str] = Field(default_factory=list)
    fallback_selectors: List[str] = Field(default_factory=list)
    request_delay_seconds: float = 0.0
    custom_headers: Dict[str, str] = Field(default_factory=dict)
    known_blockers: List[str] = Field(default_factory=list)
    applicable_lessons: List[Lesson] = Field(default_factory=list)


class LessonResolution(BaseModel):
    """Result of failure triage, dual-memory upsert, and self-healing guidance."""
    lesson: Lesson
    github_issue_created: bool = False
    github_issue_number: Optional[int] = None
    vector_db_indexed: bool = False
    retry_recommended: bool = False
    suggested_retry_action: Optional[str] = None


# ---------------------------------------------------------------------------
# LearningAgent Implementation
# ---------------------------------------------------------------------------

class LearningAgent:
    """
    Coordinator of the Roo4u self-healing cognitive loop.
    Acts as the single point of failure analysis, memory ingestion,
    issue dispatch, and feedforward strategy delivery.
    """
    def __init__(
        self,
        lesson_store: Optional[LessonStore] = None,
        vector_store: Optional[LocalVectorStore] = None,
        github_logger: Optional[GitHubIssueLogger] = None,
        extractor: Optional[LocalLLMExtractor] = None,
        enable_local_llm_diagnosis: bool = True,
    ):
        self.lesson_store = lesson_store or LessonStore()
        self.vector_store = vector_store or LocalVectorStore()
        self.github_logger = github_logger or GitHubIssueLogger()
        self.extractor = extractor or LocalLLMExtractor()
        self.enable_local_llm_diagnosis = enable_local_llm_diagnosis

    # -----------------------------------------------------------------------
    # Root Cause Diagnostic Engine
    # -----------------------------------------------------------------------

    def _diagnose_root_cause(
        self, event: ScrapingFailureEvent
    ) -> Tuple[str, str, List[str], float, Dict[str, str]]:
        """
        Deterministic, 100% offline heuristic root-cause classifier.
        Returns:
            (root_cause_analysis, recommended_workaround, suggested_selectors, suggested_delay, suggested_headers)
        """
        category_str = str(getattr(event.category, "value", event.failure_type) or event.failure_type).upper()
        domain = event.domain.lower()
        selector = event.selector or ""

        suggested_selectors: List[str] = []
        suggested_delay = 0.0
        suggested_headers: Dict[str, str] = {}

        # 1. DOM_SELECTOR_DRIFT
        if "SELECTOR" in category_str or "DRIFT" in category_str or "NOTFOUND" in category_str:
            root_cause = f"DOM structure drift or layout update on {event.domain}. Failed selector: {selector or 'N/A'}."
            if "zillow" in domain:
                suggested_selectors = [
                    '[data-testid="home-details-chip-container"]',
                    '.ds-overview-section',
                    '.ds-home-facts-and-features',
                    '.hdp-content',
                    '.summary-container',
                    '#home-details-content',
                    '.home-details-card'
                ]
                workaround = "Prepend fallback semantic containers to selector hierarchy and extract from general body if necessary."
            elif "planning" in domain or "sfplanninggis" in domain:
                suggested_selectors = [
                    '.parcel-details',
                    '#propertyDetails',
                    '.assessment-info',
                    'table.data-table',
                    '.record-content',
                    '.parcel-info'
                ]
                workaround = "Query alternative parcel tables and PIM property detail cards."
            elif "dbi" in domain or "sfgov" in domain:
                suggested_selectors = [
                    '.dbi-grid',
                    '#permitList',
                    '.permit-table',
                    'table'
                ]
                workaround = "Inspect ASP.NET data grid wrappers and table elements."
            else:
                suggested_selectors = ["table", ".property-card", "article", ".content", "body"]
                workaround = "Attempt extraction against surrounding container elements."

        # 2. ANTI_BOT_BLOCKED / 403 / Captcha
        elif "BOT" in category_str or "403" in category_str or "CAPTCHA" in category_str or "BLOCK" in category_str:
            root_cause = f"Anti-bot defense challenge or HTTP 403 access restriction detected on {event.domain}."
            suggested_delay = 2.5
            suggested_headers = {
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                "Accept-Language": "en-US,en;q=0.9",
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate"
            }
            workaround = "Introduce 2.5s jitter delay and attach realistic browser navigation headers."

        # 3. RATE_LIMIT_ERROR / 429
        elif "RATE" in category_str or "429" in category_str or "LIMIT" in category_str:
            root_cause = f"Rate limit threshold exceeded (HTTP 429) on {event.domain}."
            suggested_delay = 5.0
            workaround = "Apply 5.0s exponential backoff delay before subsequent requests."

        # 4. NETWORK_TIMEOUT / TIMEOUT
        elif "TIMEOUT" in category_str:
            root_cause = f"Navigation or network timeout encountered while accessing {event.url}."
            suggested_delay = 1.0
            workaround = "Retry request with extended timeout (45000ms) and domcontentloaded wait state."

        # 5. SCHEMA_VALIDATION_ERROR
        elif "SCHEMA" in category_str or "VALIDATION" in category_str:
            root_cause = f"Extracted property or permit payload failed schema constraints: {event.error_message[:100]}."
            workaround = "Apply field-level regex normalization before Pydantic parsing."

        # 6. EXTRACTION_PARSE_ERROR / PARSE
        elif "PARSE" in category_str or "EXTRACTION" in category_str:
            root_cause = f"HTML was successfully loaded but target data fields were missing or unparseable: {event.error_message[:100]}."
            workaround = "Extract raw text from body container and supply to LLM extractor."

        # 7. UNKNOWN / Generic
        else:
            root_cause = f"Unclassified scraping anomaly on {event.domain}: {event.error_message[:100]}."
            workaround = "Inspect target URL manually or fall back to secondary data sources."

        return root_cause, workaround, suggested_selectors, suggested_delay, suggested_headers

    # -----------------------------------------------------------------------
    # Observation & Dual-Memory Upsert Flow
    # -----------------------------------------------------------------------

    def observe_failure(self, event: ScrapingFailureEvent) -> LessonResolution:
        """
        Primary entry point for failure ingestion:
        1. Derives deterministic lesson fingerprint ID.
        2. Triage & diagnosis of root cause.
        3. Upsert to lessons_learned.json (atomic write).
        4. Logs / comments on GitHub issue (with deduplication).
        5. Embeds and indexes in LocalVectorStore.
        6. Returns actionable LessonResolution.
        """
        # 1. Deterministic fingerprint ID
        cat_str = str(getattr(event.category, "value", event.failure_type) or event.failure_type)
        sel_str = event.selector or event.attempted_selector or event.attempted_action or "default"
        pattern_key = f"{event.domain.lower()}:{cat_str.upper()}:{sel_str}"
        lesson_id = hashlib.sha256(pattern_key.encode("utf-8")).hexdigest()[:16]

        # 2. Check existing lesson in LessonStore
        existing = self.lesson_store.get_lesson(lesson_id)
        if existing:
            existing.occurrence_count += 1
            existing.timestamp = datetime.now(timezone.utc).isoformat()
            existing.error_message = event.error_message or existing.error_message
            if event.dom_snippet:
                existing.dom_snippet = event.dom_snippet
            lesson = existing
        else:
            # Diagnose root cause
            root_cause, workaround, suggested_sel, delay, headers = self._diagnose_root_cause(event)
            lesson = Lesson(
                id=lesson_id,
                domain=event.domain.lower(),
                url=event.url or event.source_url or "",
                source_url=event.source_url or event.url or "",
                failure_type=cat_str,
                error_category=cat_str,
                error_message=event.error_message,
                lesson_learned=root_cause,
                root_cause_analysis=root_cause,
                recommended_action=workaround,
                recommended_workaround=workaround,
                suggested_selectors=suggested_sel,
                suggested_delay_seconds=delay,
                suggested_headers=headers,
                timestamp=datetime.now(timezone.utc).isoformat(),
                dom_snippet=event.dom_snippet,
                status="ACTIVE",
                occurrence_count=1,
                target_entity=event.lead_address or event.target_entity,
                phase=event.phase
            )

        # 3. Log to GitHub Issue Tracker
        github_result: Optional[IssueLogResult] = None
        if self.github_logger:
            try:
                github_result = self.github_logger.log_scraping_failure(event, lesson=lesson)
                if github_result:
                    if github_result.issue_number:
                        lesson.github_issue_number = github_result.issue_number
                    if github_result.issue_url:
                        lesson.github_issue_url = github_result.issue_url
            except Exception as e:
                logger.warning(f"GitHub issue logging failed: {e}")

        # 4. Upsert to LessonStore (atomic JSON write)
        self.lesson_store.upsert_lesson(lesson)

        # 5. Embed and Upsert to LocalVectorStore
        doc_text = (
            f"Domain: {lesson.domain} | Failure: {lesson.failure_type} | "
            f"Error: {lesson.error_message} | Root Cause: {lesson.root_cause_analysis} | "
            f"Workaround: {lesson.recommended_workaround} | "
            f"Selectors: {', '.join(lesson.suggested_selectors)}"
        )
        vector_indexed = False
        if self.vector_store:
            try:
                self.vector_store.upsert(
                    id=lesson.id,
                    text=doc_text,
                    domain=lesson.domain,
                    failure_type=lesson.failure_type,
                    metadata=lesson.model_dump()
                )
                vector_indexed = True
            except Exception as e:
                logger.warning(f"Vector store indexing failed: {e}")

        # 6. Build resolution
        retry_rec = bool(lesson.suggested_selectors or lesson.suggested_delay_seconds > 0)
        action_desc = f"Apply suggested selectors: {lesson.suggested_selectors}" if lesson.suggested_selectors else lesson.recommended_workaround

        return LessonResolution(
            lesson=lesson,
            github_issue_created=bool(github_result and github_result.action in ("created", "commented")),
            github_issue_number=lesson.github_issue_number,
            vector_db_indexed=vector_indexed,
            retry_recommended=retry_rec,
            suggested_retry_action=action_desc
        )

    # -----------------------------------------------------------------------
    # Retrieval & Feedforward Strategy
    # -----------------------------------------------------------------------

    def retrieve_lessons(
        self,
        domain: str,
        context_query: str = "",
        top_k: int = 3,
        category: Optional[Union[FailureCategory, str]] = None
    ) -> List[Lesson]:
        """
        Hybrid retrieval combining vector semantic similarity and domain ledger filtering.
        Filters out DEPRECATED lessons and returns top_k active results.
        """
        dom = domain.lower()
        results_map: Dict[str, Lesson] = {}

        # 1. Semantic search via VectorStore if query provided
        if context_query and self.vector_store:
            try:
                search_results = self.vector_store.search(
                    query_text=context_query,
                    domain=dom,
                    top_k=top_k,
                    min_similarity=0.05
                )
                for s in search_results:
                    l = self.lesson_store.get_lesson(s.record.id)
                    if l and l.status != "DEPRECATED":
                        results_map[l.id] = l
            except Exception as e:
                logger.debug(f"Vector search exception: {e}")

        # 2. Filter from LessonStore
        cat_filter = str(getattr(category, "value", category)) if category else None
        store_lessons = self.lesson_store.list_lessons(domain=dom, failure_type=cat_filter)
        for l in store_lessons:
            if l.status != "DEPRECATED" and l.id not in results_map:
                results_map[l.id] = l

        # Sort by occurrence_count descending then timestamp
        sorted_lessons = sorted(
            results_map.values(),
            key=lambda item: (item.occurrence_count, item.timestamp),
            reverse=True
        )
        return sorted_lessons[:top_k]

    def get_feedforward_strategy(
        self, domain: str, action_context: str = ""
    ) -> FeedforwardStrategy:
        """
        Compiles all active lessons for a target domain into a concrete pre-scrape strategy.
        """
        lessons = self.retrieve_lessons(domain=domain, context_query=action_context, top_k=5)
        strategy = FeedforwardStrategy(domain=domain, applicable_lessons=lessons)

        for l in lessons:
            if l.status != "ACTIVE":
                continue
            strategy.fallback_selectors.extend(l.suggested_selectors)
            if l.suggested_delay_seconds > strategy.request_delay_seconds:
                strategy.request_delay_seconds = l.suggested_delay_seconds
            strategy.custom_headers.update(l.suggested_headers)
            if l.failure_type in ("ANTI_BOT_BLOCKED", "RATE_LIMIT_ERROR"):
                strategy.known_blockers.append(f"{l.failure_type}: {l.recommended_workaround}")

        # Deduplicate selectors preserving insertion order
        strategy.fallback_selectors = list(dict.fromkeys(strategy.fallback_selectors))
        return strategy

    # -----------------------------------------------------------------------
    # Success Tracking
    # -----------------------------------------------------------------------

    def observe_success(
        self, domain: str, target_entity: str, lesson_id: Optional[str] = None
    ) -> None:
        """
        Invoked when a scraping or extraction operation succeeds after applying a workaround.
        Increments success counts and marks verified lessons.
        """
        if lesson_id:
            updated = self.lesson_store.increment_success(lesson_id)
            if updated and self.vector_store:
                try:
                    self.vector_store.update_metadata(
                        lesson_id,
                        {
                            "success_count": updated.success_count_after_workaround,
                            "status": updated.status,
                            "resolved": updated.resolved
                        }
                    )
                except Exception:
                    pass
