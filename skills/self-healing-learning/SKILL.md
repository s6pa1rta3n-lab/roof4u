---
name: self-healing-learning-agent
description: Autonomous failure observation, dual-memory management (lessons_learned.json + SQLite vector store), and feedforward rule synthesis.
---

# Self-Healing Learning Agent Skill

## 1. Overview
The Self-Healing Learning Agent observes runtime scraping anomalies, HTTP blocks, and DOM selector drift. It diagnoses root causes, persists lessons to dual memory stores, logs issues to GitHub with SHA-256 deduplication, and compiles feedforward strategies for browsing agents.

## 2. Dual Memory Architecture
1. **Primary Structured Store (`lessons_learned.json`)**:
   - Atomic atomic read/write updates with sub-second corruption backup.
   - Tracks error categories: `DOM_SELECTOR_DRIFT`, `ANTI_BOT_CHALLENGE`, `HTTP_403_FORBIDDEN`, `HTTP_429_RATE_LIMIT`, `TIMEOUT_ERROR`, `SCHEMA_VALIDATION_ERROR`.
   - Tracks occurrence count, success count, confidence score, and status (`ACTIVE`, `RESOLVED`, `PROBATION`).
2. **Local Vector Database (`memory/vector_store.sqlite`)**:
   - Embedded SQLite + NumPy vector storage.
   - Deterministic offline embedding generator using normalized hash-trigram embeddings.
   - Cosine similarity search for semantic lesson retrieval.

## 3. Telemetry & GitHub Issue Sync
- Intercepts failure telemetry events (`ScrapingFailureEvent`).
- Formats structured issue body with error stack, DOM snippet, and attempted selector.
- Emits GitHub issue via `github-mcp-server` tools (`issue_write`, `list_issues`, `add_issue_comment`) with REST API fallback.
- Implements SHA-256 fingerprint deduplication to prevent duplicate open issues.

## 4. Feedforward Strategy Execution
Before any scraping request, agents invoke `get_feedforward_strategy(domain, task_context)`:
- Injects validated fallback CSS/XPath selectors.
- Applies adaptive exponential backoff request delays ($0.5\text{s} \to 2.0\text{s} \to 5.0\text{s}$).
- Injects rotated browser headers and user-agent strings.
