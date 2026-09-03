# Original User Request

## Initial Request — 2026-09-01T04:05:45-04:00

Implement the complete offline agentic architecture for Roo4u, encompassing three main epics: the Browsing Agent (local model integration), the Learning Agent (self-healing observation loop), and the Deployment Agent (CI/CD code integration).

Working directory: ~/Desktop/activeProjects/Roo4u
Integrity mode: development

## Requirements

### R1. Browsing Agent Integration
Refactor the web scraping agents to decouple from external cloud APIs. Implement routing to a local inference endpoint (e.g., `localhost:8000`) designed for an open-source NVIDIA model.

### R2. Learning Agent Pipeline
Implement the observation and memory loop. The agent must catch scraping failures, log them as GitHub issues (via MCP or API), and update a local `lessons_learned.json` and Vector DB.

### R4. Programmatic Test Suite
Develop end-to-end integration tests that run against the real local model inference endpoint and live GitHub MCP integrations. No mocks or simulated APIs are permitted per red-team standards.

### R5. Agent-As-Judge Evaluator
Implement an independent evaluator agent that reviews the output of the programmatic tests, scores the code against a strict security/functionality rubric, and digitally signs off (certifies) before deployment.

## Acceptance Criteria

### Verification & Red-Team Standards
- [ ] Test suite executes `pytest` and confirms a 100% pass rate without using the `unittest.mock` library for external endpoints.
- [ ] Agent-As-Judge successfully parses the test logs, applies the evaluation rubric, and outputs a documented 'PASS' certification.
- [ ] No external API keys (e.g., Google Gemini, OpenAI) are utilized anywhere in the execution path of the Browsing Agent.

## Follow-up — 2026-09-01T06:10:41-04:00

# Teamwork Project Prompt — Draft

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: Standard full agent team

Rewrite the existing Python data acquisition and pipeline integration layers entirely in OCaml, maintaining strict focus on San Francisco municipal databases. Concurrently, perform a rigorous adversarial security and integrity audit on the `v2` architecture.

Working directory: ~/Desktop/activeProjects/Roo4u
Integrity mode: benchmark

## Requirements

### R1. Complete Pure OCaml Rewrite
Rewrite all remaining Python components—including local LLM inference clients, dual memory stores (SQLite and JSON), Git telemetry logging, and the core pipeline orchestration—into pure OCaml. The system must retain its exact current capabilities and focus exclusively on San Francisco municipal databases.

### R2. Adversarial Audit & Automatic Remediation
Conduct a rigorous adversarial security and integrity audit of the `v2` architecture. The agent team must automatically patch and remediate any vulnerabilities discovered during the audit process. 

### R3. Strict Red Team Standards
Develop the solutions using completely custom logic under strict red team standards. The team must not copy code from existing open-source projects or use unauthorized shortcuts to bypass core logic implementation.

## Acceptance Criteria

### OCaml Architecture Parity
- [ ] The `dune build` and `dune runtest` commands complete with zero compilation errors or warnings.
- [ ] All Python files related to pipeline execution and memory are safely deprecated or removed, with their functions fully replaced by OCaml modules.
- [ ] The new OCaml pipeline successfully executes a live run and generates a `validated_leads.csv` file identical in schema and scoring behavior to the previous `v2` implementation.

### Security Remediation Verification
- [ ] A formal audit report (`security_audit.md`) is generated documenting the identified vulnerabilities, attack vectors, and the specific OCaml patches applied.
- [ ] All patched vulnerabilities are verified as closed via an independent programmatic test or agent-as-judge evaluation.

## Follow-up — 2026-09-02T16:11:39-04:00

# Teamwork Project Prompt — Launched

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: Full team

Execute and validate the Roo4u end-to-end lead generation pipeline across four target San Francisco neighborhoods: Sunset, Richmond, Excelsior, and Pacific Heights.

Working directory: ~/Desktop/activeProjects/Roo4u
Integrity mode: development (strict red team standards)

## Requirements

### R1. Automated Pipeline Verification
Extend the OCaml automated test suite to programmatically verify the lead generation pipeline for the four target districts. The tests must execute the end-to-end workflow and assert successful lead qualification and cryptographic proof generation.

### R2. Mandatory Build Process Documentation
Document every blocker, unexpected error, failed approach, or debugging cycle encountered during the testing and implementation process as a GitHub sub-issue linked to parent issue #30 on `s6pa1rta3n-lab/roof4u` in real-time.

## Acceptance Criteria

### Automated Tests
- [ ] `dune runtest` completes successfully with the new district test cases fully integrated.
- [ ] No cryptographic proofs or invariants are mocked or bypassed in the test suite.

### Process Integrity
- [ ] Any encountered failures or blockers are documented as sub-issues on issue #30 using the `issue_write` and `sub_issue_write` MCP tools.

