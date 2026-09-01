# Roo4u: Zero-Mock Component Test Suites Technical Design
**Milestone**: Milestone 3 (Programmatic Test Suite)  
**Author**: Explorer M3-2  
**Date**: 2026-09-01  
**Integrity Level**: Zero-Mock Red-Team Standard (100% Mock-Free for Network & Inference Endpoints)

---

## 1. Executive Summary & Zero-Mock Architecture Blueprint

### 1.1 Test Philosophy & Constraints
Per `ORIGINAL_REQUEST.md` (§R4, §Acceptance Criteria) and `TEST_INFRA.md`, the test suites must adhere to the **Zero-Mock Standard**:
1. **Strict Elimination of Mocks**: Zero usage of `unittest.mock`, `MagicMock`, `pytest.monkeypatch` of API endpoints, or dummy stubs for external/model endpoints.
2. **Live Socket Binding**: All network and inference interactions are tested against real TCP loopback sockets (`http://127.0.0.1:8000/v1` or dynamically allocated ephemeral loopback ports) serving OpenAI-compatible Chat Completion JSON responses and live HTTP HTML fixtures.
3. **Requirement-Driven & Opaque-Box**: Derived directly from the system specification using Category-Partition Analysis, Boundary Value Analysis, Pairwise State Combinations, and Negative/Error Injection paths.
4. **Agent-As-Judge Certifiable**: Output format, error reporting, and test results are structured for AST anti-mock scanning and digital PASS certification.

```
+---------------------------------------------------------------------------------------+
|                              ROO4U ZERO-MOCK TEST HARNESS                             |
+---------------------------------------------------------------------------------------+
|                                                                                       |
|   +--------------------------+                         +--------------------------+   |
|   |  Live Starlette Server   |                         |  Live HTTP Static Server |   |
|   |  (Local Model Inference) |                         |  (Zillow & SF DBI HTML)  |   |
|   |  http://127.0.0.1:8000/v1|                         |  http://127.0.0.1:<port> |   |
|   +------------+-------------+                         +------------+-------------+   |
|                ^                                                    ^                 |
|                | OpenAI HTTP JSON                                   | Playwright HTTP |
|                | (Real TCP Socket)                                  | (Real TCP Socket)
|                v                                                    v                 |
|   +------------+-------------+                         +------------+-------------+   |
|   |    LocalLLMExtractor     |                         |  ZillowAgent/CountyAgent |   |
|   |  (Pydantic Validation)   |                         |  (DOM Pruning & Scraping)|   |
|   +------------+-------------+                         +------------+-------------+   |
|                |                                                    |                 |
|                +-----------------------+   +------------------------+                 |
|                                        v   v                                          |
|                              +---------+---+--------+                                 |
|                              |  SQLAlchemy Lead DB  |                                 |
|                              | (Isolated SQLite DB) |                                 |
|                              +---------+------------+                                 |
|                                        |                                              |
|                                        v                                              |
|                              +---------+------------+                                 |
|                              |     CSVExporter      |                                 |
|                              | (Validated Leads CSV)|                                 |
|                              +----------------------+                                 |
+---------------------------------------------------------------------------------------+
```

---

## 2. Component Test Suite 1: `tests/test_database.py`

### 2.1 Scope & Target Component
- **Target File**: `db/database.py`
- **Classes/Functions**: `Lead`, `get_engine()`, `init_db()`, `get_session()`, `Base`
- **Objective**: Verify SQLite schema creation, full CRUD operations, ORM field serialization, column constraints, defaults, state transitions (`DISCOVERED` -> `VALIDATED` -> `ENRICHED` -> `DISCARDED`), query filtering, and transaction rollback integrity.

### 2.2 Test Architecture & Zero-Mock Environment
- Uses real SQLite database instances (`sqlite:///:memory:` or ephemeral temporary file-based SQLite databases per test function).
- Strictly zero mocking of SQLAlchemy engine, sessions, or queries.

### 2.3 Test Specifications & Partition Matrix

```
+-------------------------------------------------------------------------------------------------------------+
| Class: TestDatabaseInitialization                                                                           |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_init_db_in_memory             | init_db("sqlite:///:memory:")             | Returns engine, creates    |
|                                    |                                           | 'leads' table in metadata  |
| test_init_db_file_path             | init_db(f"sqlite:///{tmp_path}/leads.db") | Generates physical file on |
|                                    |                                           | disk with valid schema     |
| test_get_session_lifecycle         | get_session(engine)                       | Returns active Session,    |
|                                    |                                           | closes cleanly             |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestLeadCRUDOperations                                                                               |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_create_and_read_lead          | Insert full Lead with all 15 fields       | Lead committed, retrieved  |
|                                    | populated                                 | with matching attributes   |
| test_update_lead_fields            | Update APN, owner, roof_age_years         | Modified fields persisted, |
|                                    | on existing Lead                          | query reflects updates     |
| test_delete_lead                   | Delete Lead from session                  | Lead removed from DB,      |
|                                    |                                           | count decreases to 0       |
| test_lead_float_precision          | estimated_value = 14250000.75,            | Exact float values stored  |
|                                    | roof_age_years = 18.5                     | and retrieved without loss |
| test_lead_date_storage             | last_roof_permit_date = date(2012, 4, 15),| Date stored as real date,  |
|                                    | created_at = datetime.utcnow().date()     | correctly retrieved        |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestDatabaseConstraintsAndDefaults                                                                   |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_unique_address_constraint     | Insert 2 leads with identical 'address'   | Raises IntegrityError      |
|                                    |                                           | on session.commit()        |
| test_nullable_address_constraint   | Insert Lead with address=None             | Raises IntegrityError      |
| test_nullable_zip_constraint       | Insert Lead with zip_code=None            | Raises IntegrityError      |
| test_default_status_discovered     | Insert Lead without specifying status     | lead.status == "DISCOVERED"|
| test_default_boolean_flags         | Insert Lead without is_hoa or is_rental   | is_hoa is False,           |
|                                    |                                           | is_rental is False         |
| test_default_created_at_timestamp  | Insert Lead without created_at            | lead.created_at is set to  |
|                                    |                                           | current date               |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestLeadStateMachineAndFiltering                                                                     |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_state_transition_lifecycle    | DISCOVERED -> VALIDATED -> ENRICHED       | Transitions succeed and    |
|                                    | -> DISCARDED                              | persist at each stage      |
| test_query_filter_by_status        | Populate 2 DISCOVERED, 3 VALIDATED,       | Querying by status returns |
|                                    | 1 ENRICHED, 1 DISCARDED                   | exact subsets              |
| test_filter_validated_and_enriched | filter(Lead.status.in_(["VALIDATED",      | Returns exactly 4 leads    |
|                                    | "ENRICHED"]))                             | for exporter pipeline      |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestDatabaseTransactionsAndEdgeCases                                                                 |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_transaction_rollback          | Insert Lead, error on 2nd insert,         | First lead rolled back     |
|                                    | call session.rollback()                   | cleanly, DB stays clean    |
| test_special_characters_address    | Address: "123 O'Connor St #4-B,           | Special characters and SQL |
|                                    | San Francisco, CA"                        | quotes stored without bug  |
| test_unicode_owner_names           | Owner: "José Ramón Peña & Sons LLC"       | Unicode stored cleanly     |
| test_large_number_of_leads         | Bulk insert 500 leads                     | All 500 committed & queried|
+------------------------------------+-------------------------------------------+----------------------------+
```

---

## 3. Component Test Suite 2: `tests/test_base_agent.py`

### 3.1 Scope & Target Component
- **Target File**: `agents/base_agent.py`
- **Classes/Functions**: `BaseAgent`, `start_browser()`, `close_browser()`, `get_html()`, `safe_get_html()`, `emit_failure()`, `__enter__()`, `__exit__()`
- **Objective**: Verify Playwright browser lifecycle, DOM retrieval, HTTP status code interception (403, 429), access denied title checks, network timeout handling, feedforward request delays/headers, and closed-loop telemetry emission to `LearningAgent`.

### 3.2 Test Architecture & Zero-Mock Environment
- Uses real Playwright Chromium browser (`headless=True`).
- Uses real background HTTP server (`http.server` / Starlette on `127.0.0.1:<port>`) serving configurable HTTP status codes (200, 403, 429) and custom HTML headers.
- Uses real `LearningAgent` instance with real `LessonStore` / `LocalVectorStore` to verify end-to-end failure telemetry routing without mocks.

### 3.3 Test Specifications & Partition Matrix

```
+-------------------------------------------------------------------------------------------------------------+
| Class: TestBaseAgentLifecycle                                                                               |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_browser_start_and_close       | Call start_browser() then close_browser() | browser, context, page     |
|                                    |                                           | initialized and closed     |
| test_idempotent_close_browser      | Call close_browser() multiple times in row| No exceptions raised,      |
|                                    |                                           | resources safely nullified |
| test_context_manager               | with BaseAgent(headless=True) as agent:   | Browser active inside 'with',|
|                                    |     pass                                  | automatically closed after |
| test_browser_context_headers       | Verify user_agent and viewport in context | User agent matches realistic|
|                                    |                                           | Chrome, viewport 1920x1080 |
| test_auto_restart_on_navigation    | Call get_html() without prior             | Automatically starts       |
|                                    | start_browser()                           | browser and completes nav  |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestBaseAgentNavigationAndStatusCodes                                                                |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_get_html_success_200          | Navigate to live loopback 200 OK page     | Returns HTML content string|
| test_safe_get_html_http_403        | Navigate to live loopback 403 page with   | Emits 'ANTI_BOT_BLOCKED'   |
|                                    | learning agent attached                   | telemetry event            |
| test_safe_get_html_http_429        | Navigate to live loopback 429 page with   | Emits 'RATE_LIMIT_ERROR'   |
|                                    | learning agent attached                   | telemetry event            |
| test_safe_get_html_access_denied   | Navigate to page with HTML title          | Emits 'ANTI_BOT_BLOCKED'   |
|                                    | '<title>Access Denied</title>'            | telemetry event            |
| test_safe_get_html_timeout         | Navigate to un-responding socket with     | Emits 'NETWORK_TIMEOUT',   |
|                                    | timeout=200ms                             | raises Playwright Timeout  |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestBaseAgentFeedforwardAndTelemetry                                                                 |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_feedforward_request_delay     | Learning agent provides 0.2s delay        | Measures execution time >= |
|                                    | directive for domain                      | 0.2s before navigation     |
| test_feedforward_custom_headers    | Learning agent provides custom header     | Live loopback server       |
|                                    | 'X-Custom-Agent: Roo4u'                   | verifies received header   |
| test_emit_failure_construction     | Call emit_failure with full metadata and  | LearningAgent receives     |
|                                    | dom_snippet                               | ScrapingFailureEvent object|
| test_emit_failure_without_learning | Call emit_failure when learning_agent=None| Returns None gracefully    |
| test_emit_failure_handles_exception| Learning agent observe_failure raises     | emit_failure catches exc   |
|                                    | internal error                            | and returns None           |
+------------------------------------+-------------------------------------------+----------------------------+
```

---

## 4. Component Test Suite 3: `tests/test_extractor.py`

### 4.1 Scope & Target Component
- **Target File**: `agents/extractor.py`
- **Classes/Functions**: `LocalLLMExtractor`, `PropertyExtraction`, `CountyPermitExtraction`, `PermitRecord`, `_clean_json_response()`, `_call_model()`, `extract_property_details()`, `extract_county_permit_details()`
- **Objective**: Verify local model HTTP communication over loopback TCP sockets (`/v1/chat/completions`), JSON response parsing (stripping `<think>` tags, markdown code blocks, balanced brace extraction), Pydantic validation and field coercions, boundary value handling, and error handling.

### 4.2 Test Architecture & Zero-Mock Environment
- Uses real `LocalLLMExtractor` instance configured with `base_url="http://127.0.0.1:8000/v1"`.
- Real Starlette / Uvicorn test server running in a daemon thread on `127.0.0.1:8000` (or dynamic port) accepting real HTTP POST requests to `/v1/chat/completions` and returning OpenAI-compatible JSON responses.
- Tests raw string manipulation functions (`_clean_json_response`) across a battery of adversarial model outputs.

### 4.3 Test Specifications & Partition Matrix

```
+-------------------------------------------------------------------------------------------------------------+
| Class: TestJSONCleaningEngine                                                                               |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_clean_raw_json                | '{"address": "2223 Pacific Ave"}'         | '{"address": "2223 ...'    |
| test_clean_think_tags              | '<think>Analysis here</think>{"addr":"X"}'| '{"addr": "X"}'            |
| test_clean_thought_tags            | '<thought>Deep reasoning</thought>{"a":1}'| '{"a": 1}'                 |
| test_clean_markdown_json_block     | '```json\n{"address": "123 Main"}\n```'   | '{"address": "123 Main"}'  |
| test_clean_markdown_generic_block  | '```\n{"address": "123 Main"}\n```'       | '{"address": "123 Main"}'  |
| test_clean_preamble_with_braces    | 'Result is {foo}: {"address": "123 Main"}'| '{"address": "123 Main"}'  |
| test_clean_nested_json_braces      | '{"a": {"b": {"c": 123}}} trailing notes' | '{"a": {"b": {"c": 123}}}' |
| test_clean_escaped_strings         | '{"desc": "Text with \"quotes\" and \\"}' | Valid JSON string returned |
| test_clean_empty_or_none           | '' or None                                | ''                         |
| test_clean_malformed_no_braces     | 'Sorry, I could not parse this page.'     | 'Sorry, I could not ...'   |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestPydanticExtractionSchemas                                                                        |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_property_extraction_valid     | Valid dict with all fields                | PropertyExtraction instance|
| test_zip_code_validator_5digit     | zip_code="94115"                          | extraction.zip_code=="94115|
| test_zip_code_validator_extended   | zip_code="CA 94115-4321"                  | extraction.zip_code=="94115|
| test_zip_code_validator_integer    | zip_code=94115                            | extraction.zip_code=="94115|
| test_zip_code_validator_none       | zip_code=None                             | extraction.zip_code==""    |
| test_property_extraction_defaults  | Only address="100 Main St" provided       | property_type="Single-Fam",|
|                                    |                                           | roof_type="Unknown",       |
|                                    |                                           | is_hoa=False, is_rental=F  |
| test_county_extraction_valid       | Valid county dict with permit_history     | CountyPermitExtraction inst|
| test_permit_record_parsing         | Dict inside permit_history                | Parsed to PermitRecord or  |
|                                    |                                           | dict cleanly               |
| test_schema_missing_required       | Dict without 'address' field              | Raises ValidationError     |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestLocalLLMExtractorLiveInference                                                                    |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_live_extract_property_details | Send preprocessed HTML over TCP to live   | Returns validated          |
|                                    | Starlette /v1/chat/completions server     | PropertyExtraction instance|
| test_live_extract_county_details   | Send municipal HTML over TCP to live      | Returns validated          |
|                                    | Starlette /v1/chat/completions server     | CountyPermitExtraction inst|
| test_live_prompt_clipping_16000    | Send 25,000 character HTML string         | Extractor clips to 16,000  |
|                                    |                                           | characters without crashing|
| test_live_server_http_error        | Starlette server returns HTTP 500         | Extractor catches and      |
|                                    |                                           | raises RuntimeError        |
| test_live_server_malformed_json    | Starlette server returns invalid JSON     | Extractor catches and      |
|                                    |                                           | raises ValueError          |
| test_live_empty_model_response     | Starlette server returns empty content "" | Extractor catches and      |
|                                    |                                           | raises RuntimeError        |
+------------------------------------+-------------------------------------------+----------------------------+
```

---

## 5. Component Test Suite 4: `tests/test_zillow_agent.py`

### 5.1 Scope & Target Component
- **Target File**: `agents/zillow_agent.py`
- **Classes/Functions**: `ZillowAgent`, `clean_dom()`, `scrape_property()`, `scrape_and_create_lead()`, `discover_properties()`
- **Objective**: Verify Zillow DOM pruning and token reduction, extraction of structured property data via live loopback inference, Lead ORM object creation, search discovery card parsing, DOM selector drift detection, and self-healing retry logic.

### 5.2 Test Architecture & Zero-Mock Environment
- Uses real `ZillowAgent` with Playwright Chromium (`headless=True`).
- Real live HTTP server serving Zillow property detail and search fixture HTML.
- Real live Starlette model server handling `/v1/chat/completions`.
- Real `LearningAgent` verifying self-healing retry on extraction failure.

### 5.3 Test Specifications & Partition Matrix

```
+-------------------------------------------------------------------------------------------------------------+
| Class: TestZillowDOMCleaningEngine                                                                          |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_strip_unwanted_tags           | HTML containing script, style, svg, nav,  | All unwanted tags removed, |
|                                    | footer, header, form, button, iframe      | clean text preserved       |
| test_strip_html_comments           | HTML with <!-- secret comment -->         | Comments fully extracted   |
| test_target_semantic_containers    | HTML with [data-testid="property-summary"]| Only key semantic text     |
|                                    | and .ds-home-facts-and-features           | extracted                  |
| test_fallback_to_body_text         | HTML without standard Zillow testid tags  | Fallback extracts entire   |
|                                    |                                           | body text                  |
| test_extra_selectors_injection     | Feedforward passes ['.custom-fact-box']   | Injected selector content  |
|                                    |                                           | extracted first            |
| test_dom_length_budget_12000       | 30,000 char HTML payload                  | Output strictly pruned to  |
|                                    |                                           | <= 12,000 characters       |
| test_whitespace_collapsing         | HTML with tabs, multiple newlines & spaces| Normalized single spaces   |
|                                    |                                           | and clean newlines         |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestZillowScrapingAndLeadCreation                                                                    |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_scrape_property_from_html     | Pass realistic Zillow raw HTML string     | Returns PropertyExtraction |
|                                    |                                           | with address, value, roof  |
| test_scrape_property_from_live_http| Pass http://127.0.0.1:<port>/zillow_1.html| Playwright fetches page,   |
|                                    |                                           | model extracts details     |
| test_scrape_and_create_lead        | Call scrape_and_create_lead() with HTML   | Returns Lead ORM object in |
|                                    |                                           | 'DISCOVERED' status        |
| test_lead_zip_fallback             | Extraction has no zip, pass target_zip    | Lead takes target_zip or   |
|                                    |                                           | default '94115'            |
| test_feedforward_success_recorded  | Scrape with learning agent + active lesson| Calls observe_success()    |
|                                    |                                           | on learning agent          |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestZillowDiscoveryAndSelectorDrift                                                                  |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_discover_properties_success   | Serve search page with 3 property cards   | Returns list of 3 candidate|
|                                    | (article[data-test="property-card"])      | dicts with full URLs       |
| test_discover_properties_relative_u| Listing cards have href="/homedetails/123"| Resolved to full URLs      |
|                                    |                                           | http://127.0.0.1:...       |
| test_discover_properties_max_limit | Search page has 10 cards, max_results=2   | Returns exactly 2 items    |
| test_selector_drift_detection      | Serve 6,000 byte page with 0 cards        | Emits 'DOM_SELECTOR_DRIFT' |
|                                    | (simulating anti-bot or markup redesign)  | telemetry event            |
| test_self_healing_retry_on_failure | Extractor fails on pruned DOM, learning   | Fallback raw body extract  |
|                                    | agent returns retry_recommended=True      | executes and succeeds      |
+------------------------------------+-------------------------------------------+----------------------------+
```

---

## 6. Component Test Suite 5: `tests/test_county_agent.py`

### 6.1 Scope & Target Component
- **Target File**: `agents/county_agent.py`
- **Classes/Functions**: `CountyAgent`, `clean_dom()`, `parse_permit_date()`, `lookup_assessor_record()`, `lookup_permit_history()`, `enrich_lead()`
- **Objective**: Verify municipal portal DOM cleaning, robust permit date parsing across 15+ date formats and null tokens, Assessor (PIM) and Permit (DBI) lookup via live HTTP/local model, Lead record enrichment (APN, owner, assessed value, roof age calculation), and the lead qualification rule engine (`DISCOVERED` -> `VALIDATED`).

### 6.2 Test Architecture & Zero-Mock Environment
- Uses real `CountyAgent` with Playwright Chromium (`headless=True`).
- Real live HTTP server serving SF Planning PIM parcel details and SF DBI permit table fixtures.
- Real live Starlette model server handling `/v1/chat/completions`.
- Real SQLite database instance storing `Lead` records.

### 6.3 Test Specifications & Partition Matrix

```
+-------------------------------------------------------------------------------------------------------------+
| Class: TestCountyDOMCleaningEngine                                                                          |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_clean_dom_preserves_tables    | HTML with <table>, .permit-table, .dbi-grid| Table markup text kept,    |
|                                    | and <script> tags                         | scripts stripped           |
| test_clean_dom_extra_selectors     | Pass extra_selectors=['.custom-tax-box']  | Target section prioritized |
| test_clean_dom_12000_limit         | 25,000 character municipal portal HTML    | Pruned to <= 12,000 chars  |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestPermitDateParsingMatrix                                                                          |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_parse_iso_date                | "2018-05-20"                              | date(2018, 5, 20)          |
| test_parse_us_slashed_4digit       | "05/20/2018"                              | date(2018, 5, 20)          |
| test_parse_us_slashed_2digit       | "05/20/18"                                | date(2018, 5, 20)          |
| test_parse_us_dashed               | "05-20-2018", "05-20-18"                  | date(2018, 5, 20)          |
| test_parse_textual_month           | "May 20, 2018", "May 20, 18"              | date(2018, 5, 20)          |
| test_parse_day_month_year          | "20-May-2018", "20-May-18"                | date(2018, 5, 20)          |
| test_parse_dot_separated           | "2018.05.20", "18.05.20"                  | date(2018, 5, 20)          |
| test_parse_year_only_regex_fallback| "2015", "Permit issued in 2008"           | date(2015, 1, 1) / (2008)  |
| test_parse_null_like_tokens        | "N/A", "unknown", "none", "null", "---",  | None                       |
|                                    | "no_permit_on_file", "pending approval"   |                            |
| test_parse_passthrough_types       | datetime(2018, 5, 20, 10, 0), date(2018)  | date(2018, 5, 20)          |
| test_parse_invalid_garbage         | "invalid_string_with_no_date_123"         | None                       |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestAssessorAndPermitLookups                                                                         |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_lookup_assessor_from_html     | Raw PIM HTML snippet                      | CountyPermitExtraction with|
|                                    |                                           | apn, owner, assessed_value |
| test_lookup_assessor_from_live_http| http://127.0.0.1:<port>/pim_fixture.html  | Fetches via Playwright,    |
|                                    |                                           | model extracts details     |
| test_lookup_permit_from_html       | Raw SF DBI permit table HTML              | CountyPermitExtraction with|
|                                    |                                           | permit history & dates     |
| test_lookup_permit_from_live_http  | http://127.0.0.1:<port>/dbi_fixture.html  | Fetches via Playwright,    |
|                                    |                                           | model extracts details     |
| test_lookup_failure_telemetry      | Malformed input triggering exception      | Emits 'EXTRACTION_PARSE_ERR|
|                                    | with learning agent attached              | telemetry and raises exc   |
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestLeadEnrichmentAndQualification                                                                   |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_enrich_lead_updates_all_fields| Lead + PIM HTML + DBI HTML                | Lead populated with APN,   |
|                                    |                                           | owner, permit date, roofage|
| test_qualification_roof_age_old    | Lead with last permit 2005 (age >= 15 yrs)| lead.status == "VALIDATED" |
| test_qualification_high_value      | Lead with estimated_value = $2,500,000    | lead.status == "VALIDATED" |
|                                    | (even if roof age is young)               |                            |
| test_non_qualification_young_roof  | Lead with last permit 2022 (age 4 yrs)    | lead.status == "DISCOVERED"|
|                                    | and estimated_value = $650,000            | (not qualified)            |
| test_enrich_lead_handles_pim_fail  | PIM lookup raises error, DBI succeeds     | DBI data applied, roof age |
|                                    |                                           | calculated without crash   |
| test_enrich_lead_handles_dbi_fail  | DBI lookup raises error, PIM succeeds     | PIM data applied, status   |
|                                    |                                           | updated if value > $1M     |
+------------------------------------+-------------------------------------------+----------------------------+
```

---

## 7. Component Test Suite 6: `tests/test_exporter.py`

### 7.1 Scope & Target Component
- **Target File**: `exporters/csv_exporter.py`
- **Classes/Functions**: `export_to_csv()`, `headers`, `Lead`
- **Objective**: Verify CSV lead export filtering (`VALIDATED` and `ENRICHED` only), CSV header accuracy, schema compliance, field ordering, special character/quote escaping, NULL/None handling, and empty database edge cases.

### 7.2 Test Architecture & Zero-Mock Environment
- Uses real SQLite database instances with real `Lead` ORM objects.
- Uses real file system operations (temporary directory paths for output CSV files).
- Reads and parses the generated CSV files using Python's standard `csv.reader` and `csv.DictReader` to guarantee format compliance.

### 7.3 Test Specifications & Partition Matrix

```
+-------------------------------------------------------------------------------------------------------------+
| Class: TestCSVExporterFilteringAndSchema                                                                    |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_export_only_validated_enriched| DB with 2 DISCOVERED, 2 VALIDATED,        | Exactly 3 rows exported    |
|                                    | 1 ENRICHED, 1 DISCARDED                   | (2 VALIDATED + 1 ENRICHED) |
| test_csv_exact_headers             | Export validated leads                    | Row 0 matches exact 10     |
|                                    |                                           | headers in order           |
| test_csv_column_mapping            | Export lead with full attributes          | Each column maps to correct|
|                                    |                                           | lead field value           |
| test_csv_empty_database            | DB with 0 leads                           | Returns without crashing,  |
|                                    |                                           | prints message             |
| test_csv_no_qualified_leads        | DB with 5 DISCOVERED leads only           | No qualified leads exported|
+------------------------------------+-------------------------------------------+----------------------------+

+-------------------------------------------------------------------------------------------------------------+
| Class: TestCSVDataIntegrityAndFormatting                                                                    |
+------------------------------------+-------------------------------------------+----------------------------+
| Test Method                        | Input / Scenario                          | Expected Outcome           |
+------------------------------------+-------------------------------------------+----------------------------+
| test_csv_special_characters_quotes | Address: "100 O'Farrell St, Suite \"A\""  | Comma and quotes escaped   |
|                                    | Owner: "Smith & Jones, LLC"               | properly per RFC 4180      |
| test_csv_unicode_encoding          | Owner: "José María González"              | UTF-8 encoding preserved   |
| test_csv_null_field_handling       | Lead with apn=None, phone_number=None     | Written as empty strings,  |
|                                    |                                           | not string "None"          |
| test_csv_float_values              | estimated_value = 1850000.50,             | Exact numeric values in CSV|
|                                    | roof_age_years = 19.5                     | matches DB                 |
| test_csv_overwrite_existing_file  | Export to file path that already exists   | File overwritten cleanly   |
+------------------------------------+-------------------------------------------+----------------------------+
```

---

## 8. Summary Test Matrix & Red-Team Audit Verification

| Test Suite File | Tested Modules | Test Classes | Test Methods Count | Zero-Mock Verification Strategy |
|---|---|---|:---:|---|
| `tests/test_database.py` | `db/database.py` | 5 | 16 | Real SQLite in-memory/file DB session |
| `tests/test_base_agent.py` | `agents/base_agent.py` | 3 | 14 | Real Playwright browser + live HTTP socket server |
| `tests/test_extractor.py` | `agents/extractor.py` | 3 | 20 | Real Starlette `/v1` server over TCP + Pydantic |
| `tests/test_zillow_agent.py` | `agents/zillow_agent.py` | 3 | 14 | Real Playwright + Live HTML + Starlette inference |
| `tests/test_county_agent.py` | `agents/county_agent.py` | 4 | 22 | Real Playwright + Live HTML + Starlette inference |
| `tests/test_exporter.py` | `exporters/csv_exporter.py` | 2 | 11 | Real SQLite DB + Real CSV filesystem reads |
| **Total Target** | **6 Modules** | **20 Classes** | **97 Tests** | **100% Mock-Free Across All External Endpoints** |

---

## 9. Red-Team Anti-Cheating & Audit Gate Compliance
1. **No `unittest.mock` or `MagicMock`**: All tests interact with real objects, real Playwright browser instances, real local network sockets, and real SQLite engines.
2. **No External Cloud Keys**: Zero cloud API dependencies (`OPENAI_API_KEY`, `GEMINI_API_KEY`).
3. **Deterministic Test Execution**: Ephemeral ports, isolated databases, and idempotent cleanup ensure repeatable, zero-flakiness test runs.
