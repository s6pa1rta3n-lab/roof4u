# Dispatch for Explorer M3-2 (Zero-Mock Component Test Suites)

You are Explorer M3-2.
Working directory: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m3_2
Project root: /Users/solveetcoagula/Desktop/activeProjects/Roo4u

Authoritative User Request: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ORIGINAL_REQUEST.md
Project Blueprint: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/PROJECT.md
Test Infrastructure Spec: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/TEST_INFRA.md

Task:
Investigate and design the Zero-Mock Component Test Suites for Milestone 3:
1. `tests/test_database.py`: SQLAlchemy schema creation, Lead CRUD operations, state transitions (`DISCOVERED` -> `VALIDATED` -> `ENRICHED`), and unique constraints.
2. `tests/test_base_agent.py`: Playwright browser lifecycle, DOM retrieval, timeout handling, and failure telemetry hooks.
3. `tests/test_extractor.py`: `LocalLLMExtractor` communicating over real loopback HTTP socket to the Starlette model server, testing Pydantic validation for `PropertyExtraction` and `CountyPermitExtraction`.
4. `tests/test_zillow_agent.py`: DOM cleaning, semantic selector extraction, and lead creation using the live loopback HTML server.
5. `tests/test_county_agent.py`: Permit date parsing, assessor lookup, and qualification rules using the live loopback HTML server.
6. `tests/test_exporter.py`: CSV export validation and schema verification.

Deliverables:
- Detailed test suite specifications in `.agents/explorer_m3_2/component_tests_design.md`
- 5-component handoff report in `.agents/explorer_m3_2/handoff.md`
- Notify parent when complete via `send_message`.
