# Orchestration Plan: Roo4u Pure OCaml Rewrite & Adversarial Audit

## High-Level Objective
Execute complete pure OCaml rewrite of Roo4u pipeline and conduct rigorous adversarial security audit with automated remediation according to red team standards.

## Plan Stages
1. **Stage 0: Survey & Scope Mapping**
   - Dispatch 3 parallel Explorers to analyze:
     - Explorer 1: Python v2 pipeline, SF municipal database connectors, scoring models, and `validated_leads.csv` schema.
     - Explorer 2: Local LLM inference clients (localhost:8000), dual memory stores (SQLite & JSON), Git telemetry.
     - Explorer 3 / Spec Miner: OCaml toolchain/dune setup, dependencies (Ezjsonm, sqlite3, cohttp-eio/cohttp-lwt, etc.), existing security vulnerabilities and attack surfaces in v2.
2. **Stage 1: Architecture & Project Plan**
   - Merge findings into `PROJECT.md` (Feature Inventory, Architecture, Milestones, Interface Contracts, Code Layout).
   - Initialize `TEST_INFRA.md` for the E2E Testing Track.
3. **Stage 2: Dual-Track Execution**
   - **Track 1: Implementation Track (Sub-orchestrators for milestones)**
     - Milestone 1: OCaml Foundation, Config, and SF Municipal Database Integration (Data acquisition, schema mapping, lead scoring).
     - Milestone 2: OCaml Dual Memory Store (SQLite & JSON) and Git Telemetry Logging.
     - Milestone 3: Local LLM Inference Client & Agentic Pipeline Orchestration.
     - Milestone 4: Python Deprecation & Cleanup.
     - Milestone 5: Security Audit & Automated Remediation (Patching vulnerabilities, security_audit.md).
   - **Track 2: E2E Testing Track**
     - Sub-orchestrator / test writers to implement Tiers 1-4 opaque-box tests and publish `TEST_READY.md`.
4. **Stage 3: Final Milestone — E2E Passing & Adversarial Hardening**
   - Phase 1: Verify 100% E2E test suite passing against the live OCaml binary.
   - Phase 2: Adversarial Coverage Hardening (Tier 5 Challenger -> Worker -> Reviewer -> Forensic Auditor).
5. **Stage 4: Verification & Delivery**
   - Verify `dune build` & `dune runtest` clean.
   - Verify live pipeline run producing `validated_leads.csv`.
   - Verify `security_audit.md` and independent security tests.
   - Final Forensic Victory Audit & completion handoff.
