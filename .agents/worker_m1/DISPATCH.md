## 2026-09-01T08:10:00Z
You are the Implementation Worker for Milestone 1 (M1: Browsing Agent & Local Model Integration) of the Roo4u project.
Your working directory is: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/worker_m1
The project workspace is: /Users/solveetcoagula/Desktop/activeProjects/Roo4u

Inputs to read:
- /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ORIGINAL_REQUEST.md
- /Users/solveetcoagula/Desktop/activeProjects/Roo4u/PROJECT.md
- /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_survey_1/survey_browsing.md
- /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_survey_1/handoff.md

Your exclusive write ownership:
- `requirements.txt`
- `agents/extractor.py`
- `agents/zillow_agent.py`
- `agents/county_agent.py`
- `main.py`

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Detailed Tasks:
1. Update `requirements.txt`: Purge `langchain-google-genai` and `google-genai`. Ensure all required dependencies are present (e.g. `playwright`, `pydantic`, `openai`, `beautifulsoup4`, `requests`, `httpx`, `sqlalchemy`, `pytest`, `pytest-json-report`, `starlette`, `uvicorn`). Install missing packages into `venv` if needed using `venv/bin/pip`.
2. Refactor `agents/extractor.py`:
   - Completely remove all Gemini/Google GenAI imports and references.
   - Implement `LocalLLMExtractor` (or update `LLMExtractor`) using `openai.OpenAI` client targeting `base_url` configured from `LOCAL_INFERENCE_URL` environment variable (default: `http://localhost:8000/v1`) with a dummy api_key (e.g. `"not-needed"` or `"local"`).
   - Define comprehensive Pydantic models for extraction: `PropertyExtraction`, `CountyPermitExtraction`.
   - Implement extraction methods that accept preprocessed HTML/text, send structured JSON prompts to the local model endpoint, parse and validate the response into the Pydantic schema, with graceful error handling.
3. Implement `agents/zillow_agent.py`:
   - Subclass `BaseAgent`.
   - Implement property page navigation and DOM retrieval.
   - Implement DOM preprocessing with `beautifulsoup4` to strip script tags, styles, SVG, and noisy DOM nodes, extracting key sections (price, home facts, roof, features, description) to minimize token load.
   - Integrate with `LLMExtractor` to extract property details.
   - Return structured lead data or dictionary compatible with DB `Lead` model.
4. Implement `agents/county_agent.py`:
   - Subclass `BaseAgent`.
   - Implement permit / assessor portal navigation and DOM retrieval.
   - Implement DOM preprocessing and integration with `LLMExtractor` to extract permit history, roof permit dates, property records.
5. Wire `main.py`:
   - Un-comment and wire `ZillowAgent` and `CountyAgent` into the processing pipeline, replacing the hardcoded simulated print statements.
6. Verify and test your changes:
   - Run python verification commands using `./venv/bin/python` to verify module imports and behavior.
   - Ensure zero mentions of Google Gemini / `GEMINI_API_KEY` across the codebase.
7. Write your detailed handoff report to `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/worker_m1/handoff.md` and progress to `progress.md`. Send a message when done.
