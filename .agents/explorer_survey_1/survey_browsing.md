# Survey Report: Browsing Agent Integration & Local Model Inference (R1)

**Date:** 2026-09-01  
**Agent:** explorer_survey_1  
**Project:** Roo4u (Agentic Lead Generation Pipeline)  
**Target Milestone:** R1 - Browsing Agent Integration & Local Model Inference  

---

## 1. Executive Summary

This survey provides an in-depth architectural and code-level investigation of the Roo4u repository to guide the implementation of **R1: Browsing Agent Integration**. The primary goals are:
1. Identifying all existing modules, browsing tools, and pipeline entrypoints.
2. Locating all hardcoded dependencies on external cloud APIs (Google Gemini, OpenAI, Anthropic) and API keys.
3. Defining the decoupling architecture and technical interfaces required to route inference requests to a local endpoint (`http://localhost:8000/v1`) hosting an open-source model (e.g., NVIDIA Nemotron / Llama-3-Nemotron).
4. Specifying exact request/response schemas, failure handling, and DOM preprocessing requirements.

---

## 2. Codebase Inventory & Structure

The repository `/Users/solveetcoagula/Desktop/activeProjects/Roo4u` consists of the following structure:

```
Roo4u/
├── .agents/                      # Swarm workspace metadata & coordination files
├── agents/
│   ├── base_agent.py            # Playwright headless browser wrapper (BaseAgent)
│   └── extractor.py             # PropertyExtraction schema & LLMExtractor (Gemini-coupled)
├── db/
│   └── database.py              # SQLAlchemy Lead model & SQLite session management
├── exporters/
│   └── csv_exporter.py          # CSV export script for VALIDATED and ENRICHED leads
├── leads.db                     # SQLite database file
├── main.py                      # Pipeline CLI entry point
├── orchestrator_prompt.md       # Antigravity scheduled task prompt template
├── ORIGINAL_REQUEST.md          # Authoritative user requirements & acceptance criteria
├── README.md                    # Architecture and local swarm documentation
├── requirements.txt             # Python project dependencies
├── validated_leads.csv          # Sample exported lead dataset
└── venv/                        # Virtual environment (Python 3.14.7)
```

### Detailed Component Analysis

| File Path | Role / Purpose | Current Status | Cloud Dependencies |
| :--- | :--- | :--- | :--- |
| `main.py` | CLI Entrypoint (`--zip`) | Mock/POC simulation: hardcoded logs and seed test property (`2223 Pacific Ave`). Commented imports for `ZillowAgent` and `CountyAgent`. | None directly, but pipeline is stubbed. |
| `agents/base_agent.py` | Browser Automation Base Class | Implements `BaseAgent` with Playwright (`sync_playwright`), Chromium launcher, realistic User-Agent, viewport configuration, and `get_html(url)`. | None. Clean headless browser foundation. |
| `agents/extractor.py` | Information Extraction | Implements `PropertyExtraction` (Pydantic) and `LLMExtractor` using `langchain_google_genai.ChatGoogleGenerativeAI(model="gemini-3.1-pro")`. | **CRITICAL VIOLATION**: Hard-coupled to Google Gemini API and requires `GEMINI_API_KEY`. |
| `db/database.py` | Data Persistence | SQLAlchemy ORM model `Lead` capturing full funnel state (`DISCOVERED`, `VALIDATED`, `ENRICHED`, `DISCARDED`), APN, estimated value, roof age, permit dates, etc. | None. Pure SQLite3 + SQLAlchemy. |
| `exporters/csv_exporter.py` | Data Export | Reads `VALIDATED`/`ENRICHED` records from SQLite and writes formatted CSV. | None. |
| `requirements.txt` | Dependency Manifest | Lists: `playwright`, `pydantic`, `pydantic-ai`, `langchain`, `langchain-google-genai`, `google-genai`, `python-dotenv`, `pandas`, `sqlalchemy`, `requests`, `beautifulsoup4`. | Contains `langchain-google-genai` and `google-genai`. |

---

## 3. Web Scraping & Browsing Architecture

### Current Browsing Infrastructure (`agents/base_agent.py`)
- **Engine:** Playwright synchronous API (`playwright.sync_api.sync_playwright`).
- **Browser:** Chromium launched in headless mode (`headless=True` by default).
- **Anti-Detection Measures:** Configured context with desktop User-Agent (`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36`) and standard 1920x1080 viewport.
- **Context Lifecycle:** Supports Python context manager (`__enter__` and `__exit__`), clean teardown (`close_browser`).

### Missing Scraping Components
1. **Discovery Agent (`agents/zillow_agent.py` or `agents/discovery_agent.py`):**
   - Must search property listings in target zip codes (e.g., San Francisco 94115).
   - Must filter single-family/Victorian candidates and insert raw property leads into `leads.db` with status `DISCOVERED`.
2. **County Assessor & Permits Agent (`agents/county_agent.py`):**
   - Must navigate San Francisco Planning Information Map (PIM: `sfplanninggis.org/pim/`) to query APN and assessed tax values.
   - Must navigate Department of Building Inspection (DBI) Permit Tracking system to verify reroofing permits, permit history, and calculate roof age (e.g., > 15 years for roofing contractor qualification).
3. **HTML / DOM Preprocessor:**
   - Raw HTML pages from real estate and municipal portals often exceed 200KB-1MB.
   - Local open-source models (such as NVIDIA 8B/70B Nemotron or Llama-3 variants) operate most effectively on cleaned text or pruned DOM trees (removing `<script>`, `<style>`, SVG elements, comments, and redundant whitespace).
   - An HTML cleaning utility using `beautifulsoup4` (already installed) is essential before passing payloads to local inference.

---

## 4. Cloud API Audit & Decoupling Requirements

### Detected Cloud API Violations
1. **`agents/extractor.py:4`**:
   ```python
   from langchain_google_genai import ChatGoogleGenerativeAI
   ```
2. **`agents/extractor.py:20-25`**:
   ```python
   # Requires GEMINI_API_KEY to be set in environment variables
   self.llm = ChatGoogleGenerativeAI(
       model="gemini-3.1-pro", # Using the high-tier model for complex HTML parsing
       temperature=0
   )
   ```
3. **`requirements.txt:5-6`**:
   ```
   langchain-google-genai
   google-genai
   ```
4. **Runtime Verification Error:**
   Executing `from agents.extractor import LLMExtractor; LLMExtractor()` without credentials produces:
   ```
   pydantic_core._pydantic_core.ValidationError: 1 validation error for ChatGoogleGenerativeAI
   Value error, API key required for Gemini Developer API. Provide api_key parameter or set GOOGLE_API_KEY/GEMINI_API_KEY environment variable.
   ```

### Decoupling Mandate
Per `ORIGINAL_REQUEST.md` (R1 & Acceptance Criteria):
- **Zero External API Keys:** No calls to Google Gemini, OpenAI, Anthropic, or external endpoints are permitted anywhere in the execution path.
- **Local Inference Routing:** All LLM inference for extraction, reasoning, or summarization must target a local endpoint (defaulting to `http://localhost:8000/v1`).

---

## 5. Local Model Inference Architecture (`localhost:8000`)

### Endpoint Protocol & Compatibility
The local server (e.g., NVIDIA NIM, vLLM, Ollama, Triton, or LocalAI) exposes an OpenAI-compatible REST API at `http://localhost:8000/v1`.

- **Inference URL:** `http://localhost:8000/v1/chat/completions` (configurable via `LOCAL_INFERENCE_URL` environment variable).
- **Default Model Identifier:** `nvidia/llama-3.1-nemotron-70b-instruct` or `local-model` (configurable via `LOCAL_MODEL_NAME`).
- **Authentication:** Dummy or omitted (`api_key="not-needed"`).

### Client SDK Options Available in Workspace
- The virtual environment contains `openai 3.6.0`, `httpx 0.28.1`, `requests 2.34.2`, and `pydantic-ai 2.37.0`.
- The cleanest, standard approach is utilizing the native `openai.OpenAI` client pointed to `base_url="http://localhost:8000/v1"` or direct `httpx` HTTP requests, paired with Pydantic model validation.

### Request Payload Specification

```http
POST /v1/chat/completions HTTP/1.1
Host: localhost:8000
Content-Type: application/json

{
  "model": "nvidia/llama-3.1-nemotron-70b-instruct",
  "messages": [
    {
      "role": "system",
      "content": "You are an expert real estate data extraction agent. Analyze the provided property text/HTML and return ONLY a JSON object with the following fields:\n- address (string): Full street address\n- zip_code (string): 5-digit zip code\n- property_type (string): e.g., 'Single-Family', 'Condo', 'Multi-Family'\n- roof_type (string): 'Victorian', 'Flat', 'Pitched', or 'Unknown'\n- is_hoa (boolean): true if HOA exists, else false\n- is_rental (boolean): true if explicitly listed as rental, else false"
    },
    {
      "role": "user",
      "content": "Property HTML/Content:\n<div class=\"details\"><span class=\"addr\">2223 Pacific Ave, San Francisco, CA 94115</span><span class=\"type\">Single Family Victorian Residence</span></div>"
    }
  ],
  "temperature": 0.0,
  "response_format": {
    "type": "json_object"
  }
}
```

### Expected Response Payload Specification

```json
{
  "id": "chatcmpl-local-001",
  "object": "chat.completion",
  "created": 1725177600,
  "model": "nvidia/llama-3.1-nemotron-70b-instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "{\n  \"address\": \"2223 Pacific Ave\",\n  \"zip_code\": \"94115\",\n  \"property_type\": \"Single-Family\",\n  \"roof_type\": \"Victorian\",\n  \"is_hoa\": false,\n  \"is_rental\": false\n}"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 128,
    "completion_tokens": 42,
    "total_tokens": 170
  }
}
```

### Target Data Schema (`PropertyExtraction`)

```python
from pydantic import BaseModel, Field
from typing import Optional

class PropertyExtraction(BaseModel):
    """Pydantic schema for property details extracted via local model."""
    address: str = Field(description="The full street address of the property.")
    zip_code: str = Field(description="The 5-digit zip code.")
    property_type: str = Field(default="Single-Family", description="Property classification.")
    roof_type: str = Field(default="Unknown", description="Inferred roof type: Victorian, Flat, Pitched, Unknown.")
    is_hoa: bool = Field(default=False, description="True if HOA property.")
    is_rental: bool = Field(default=False, description="True if rental listing.")
```

---

## 6. Architecture & Implementation Plan for R1

```
+-------------------------------------------------------------+
|                      Roo4u Pipeline                         |
|                         main.py                             |
+------------------------------+------------------------------+
                               |
            +------------------+------------------+
            |                                     |
            v                                     v
+-----------------------+             +-----------------------+
|     DiscoveryAgent    |             |      CountyAgent      |
| (Zillow / Real Estate)|             |  (SF PIM & DBI Permits|
+-----------+-----------+             +-----------+-----------+
            |                                     |
            +------------------+------------------+
                               |
                               v
               +-------------------------------+
               |           BaseAgent           |
               | (Playwright Headless Browser) |
               +---------------+---------------+
                               |
                               | Cleaned HTML / DOM
                               v
               +-------------------------------+
               |       LocalLLMExtractor       |
               |   (agents/extractor.py)       |
               +---------------+---------------+
                               |
                               | POST http://localhost:8000/v1
                               v
               +-------------------------------+
               |    Local NVIDIA LLM Server    |
               |       (localhost:8000)        |
               +---------------+---------------+
                               |
                               | JSON ChatCompletion
                               v
               +-------------------------------+
               |   Pydantic Validation         |
               |  (PropertyExtraction model)   |
               +---------------+---------------+
                               |
                               v
               +-------------------------------+
               |     SQLite Database           |
               |    (db/database.py)           |
               +---------------+---------------+
```

### Recommended Concrete Changes

1. **Refactor `agents/extractor.py`**:
   - Remove `langchain_google_genai` import.
   - Implement `LocalLLMExtractor` using `openai.OpenAI(base_url=LOCAL_INFERENCE_URL, api_key="not-needed")` or `requests`/`httpx`.
   - Implement JSON block extraction and `PropertyExtraction.model_validate_json()`.
   - Add HTML DOM sanitizer to strip scripts/styles and compress token size.

2. **Implement Scraping Modules**:
   - `agents/zillow_agent.py`: Discovery agent subclassing `BaseAgent`.
   - `agents/county_agent.py`: Assessor & Permit agent querying SF PIM and DBI tracking.

3. **Update `requirements.txt`**:
   - Remove `langchain-google-genai` and `google-genai`.
   - Add `openai` (if explicit pinning desired) and `httpx`.

4. **Integrate Pipeline in `main.py`**:
   - Replace mock print logs with live calls to `DiscoveryAgent`, `LocalLLMExtractor`, and `CountyAgent`.
   - Update `Lead` records in `leads.db` through real pipeline execution.
