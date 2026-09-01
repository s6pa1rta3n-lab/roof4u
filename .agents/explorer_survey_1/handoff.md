# Handoff Report: Codebase Survey - Browsing Agent Integration & Local Model Inference (R1)

## 1. Observation

Direct observations from codebase inspection and execution tests:

1. **Cloud API Coupling in `agents/extractor.py`**:
   - `agents/extractor.py:4`: `from langchain_google_genai import ChatGoogleGenerativeAI`
   - `agents/extractor.py:20-25`:
     ```python
     # Requires GEMINI_API_KEY to be set in environment variables
     self.llm = ChatGoogleGenerativeAI(
         model="gemini-3.1-pro", # Using the high-tier model for complex HTML parsing
         temperature=0
     )
     ```
   - Running `source venv/bin/activate && python -c "from agents.extractor import LLMExtractor; extractor = LLMExtractor()"` yielded:
     ```
     pydantic_core._pydantic_core.ValidationError: 1 validation error for ChatGoogleGenerativeAI
       Value error, API key required for Gemini Developer API. Provide api_key parameter or set GOOGLE_API_KEY/GEMINI_API_KEY environment variable.
     ```

2. **Dependencies in `requirements.txt`**:
   - `requirements.txt:5-6`: Contains `langchain-google-genai` and `google-genai`.
   - `pip list` in virtual environment confirms `openai 3.6.0`, `httpx 0.28.1`, `requests 2.34.2`, `pydantic 2.13.5`, `pydantic-ai 2.37.0`, `playwright 1.62.0`, `sqlalchemy 2.0.52` are installed.

3. **Browser Automation Foundation in `agents/base_agent.py`**:
   - Uses `playwright.sync_api.sync_playwright` to launch headless Chromium with standard User-Agent and 1080p viewport.
   - Provides `get_html(url: str)` and context manager support (`__enter__`, `__exit__`).

4. **Pipeline & Agent Gaps in `main.py`**:
   - `main.py:4-5`: `# from agents.zillow_agent import ZillowAgent` and `# from agents.county_agent import CountyAgent` are commented out.
   - `main.py:20-64`: Pipeline currently seeds a hardcoded property (`2223 Pacific Ave`) and prints mock progress strings rather than invoking live agents.

5. **Local Port & Server Status**:
   - Executing `curl -I http://localhost:8000` returned:
     ```
     curl: (7) Failed to connect to localhost port 8000 after 0 ms: Couldn't connect to server
     ```
   - Shows no active server is running on `localhost:8000` yet, requiring either a real local inference server (NVIDIA NIM / vLLM) or a lightweight local HTTP mock service during standalone test execution.

---

## 2. Logic Chain

1. **Premise 1 (from Observation 1 & 2)**: `agents/extractor.py` hard-imports `ChatGoogleGenerativeAI` and crashes on initialization without `GEMINI_API_KEY`.
2. **Premise 2 (from ORIGINAL_REQUEST.md)**: Requirement R1 and Acceptance Criterion 3 dictate that no external cloud API keys (e.g., Google Gemini, OpenAI) may be utilized anywhere in the execution path, and inference must route to a local endpoint (e.g., `localhost:8000`).
3. **Inference 1**: To satisfy R1, `agents/extractor.py` must be refactored to remove all Google Gemini imports and replaced with a local LLM client using an OpenAI-compatible interface targeting `LOCAL_INFERENCE_URL` (default `http://localhost:8000/v1`).
4. **Premise 3 (from Observation 3 & 4)**: `BaseAgent` provides working Playwright browser mechanics, but `ZillowAgent` and `CountyAgent` are absent, leaving `main.py` dependent on hardcoded print simulations.
5. **Inference 2**: Full R1 implementation requires creating the concrete scraping agents (`ZillowAgent` and `CountyAgent`) inheriting from `BaseAgent`, equipped with DOM preprocessing to feed concise HTML/text to the local model.
6. **Inference 3**: Since `openai 3.6.0` and `httpx 0.28.1` are already available in `venv`, the local client can directly use `openai.OpenAI(base_url="http://localhost:8000/v1", api_key="not-needed")` and validate the JSON output using `PropertyExtraction.model_validate_json()`.

---

## 3. Caveats

- **Active Model Server**: No local server was running on `localhost:8000` during the survey. The test suite (R4) and development runs will require a running local inference service or a live local endpoint.
- **Dynamic Site Layouts**: Real estate and county assessor websites (e.g., SF PIM) often update DOM selectors or employ bot-mitigation techniques (Cloudflare/CAPTCHA). Playwright configurations should anticipate timeouts and feed failures into the R2 learning loop.

---

## 4. Conclusion

The existing codebase contains a functional SQLite schema and Playwright foundation, but is blocked by a critical cloud API violation in `agents/extractor.py` and missing concrete scraping modules in `agents/`. 

To complete R1:
1. Refactor `agents/extractor.py` to route extraction inference exclusively to the local OpenAI-compatible endpoint at `http://localhost:8000/v1`.
2. Remove `langchain-google-genai` and `google-genai` from `requirements.txt`.
3. Implement `agents/zillow_agent.py` and `agents/county_agent.py` using `BaseAgent`.
4. Add DOM preprocessing (`beautifulsoup4`) to reduce token load on local models.
5. Wire real agent execution into `main.py`.

---

## 5. Verification Method

To independently verify the survey findings and ensure decoupling:

1. **Verify Cloud API Removal**:
   ```bash
   git grep -inE "gemini|ChatGoogleGenerativeAI|google-genai|GOOGLE_API_KEY|GEMINI_API_KEY" agents/ requirements.txt
   ```
   *Expected result after fix:* Zero occurrences.

2. **Verify Local Extractor Initialization (No API Key Required)**:
   ```bash
   source venv/bin/activate && python -c "from agents.extractor import PropertyExtraction, LocalLLMExtractor; print('Extractor loaded without cloud keys')"
   ```
   *Expected result:* Exits with code 0 without raising any `ValidationError` or missing key errors.

3. **Verify Local Inference Execution**:
   With a local server or mock running on port 8000:
   ```bash
   pytest -v tests/
   ```
   *Expected result:* 100% pass rate without importing `unittest.mock` on external endpoints.
