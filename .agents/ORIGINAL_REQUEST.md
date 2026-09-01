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
