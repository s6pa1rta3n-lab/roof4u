# Empirical Challenge Report: Milestone 1 (M1) - Browsing Agent & Local Model Integration

**Target**: Roo4u Milestone 1 Codebase (`agents/base_agent.py`, `agents/extractor.py`, `agents/zillow_agent.py`, `agents/county_agent.py`, `db/database.py`, `main.py`)  
**Challenger**: Challenger 1 (Archetype: challenger, Roles: critic, specialist)  
**Integrity Mode**: Development  
**Execution Environment**: macOS / Python 3.14 / pytest 9.1.1  
**Overall Risk Assessment**: **MEDIUM**  
**Verdict**: **REQUEST_CHANGES**  

---

## 1. Challenge Summary

An empirical, adversarial challenge campaign was conducted against Milestone 1 deliverables to stress-test core assumptions, edge cases, lifecycle hazards, and parser boundaries. A total of **118 empirical tests** were executed across three test suites (`tests/test_challenger_m1_1.py`, `tests/test_challenger_m1_2.py`, and `tests/test_challenger_m1_deep_stress.py`).

While the core architecture successfully decoupled from external cloud APIs, implemented robust Pydantic schemas, and built fast DOM pruning capabilities, **two concrete defects** and one minor limitation were uncovered through empirical reproduction:
1. **[HIGH] Non-Idempotent Playwright Browser Teardown (`BaseAgent.close_browser`)**: Calling `close_browser()` multiple times (e.g. in `finally` blocks or during chained error recovery) crashes with `playwright._impl._errors.Error: Event loop is closed! Is Playwright already stopped?`.
2. **[MEDIUM] Greedy Outer-Brace Slicing Corrupts JSON in `LocalLLMExtractor._clean_json_response`**: When local reasoning models output curly braces in preamble, chain-of-thought, or markdown explanations before the JSON object, `_clean_json_response` slices from the first preamble brace to the final brace, corrupting the payload and failing `json.loads`.
3. **[LOW / INFORMATIONAL] 2-Digit Year Parsing in `CountyAgent.parse_permit_date`**: Dates in `MM/DD/YY` or `YY-MM-DD` formats evaluate to `None`.

---

## 2. Identified Vulnerabilities & Challenges

### [High] Challenge 1: `BaseAgent.close_browser()` Non-Idempotent Teardown Crash

- **Assumption Challenged**: Calling `close_browser()` is safe to invoke repeatedly during cleanup, context exit, or exception handlers.
- **Attack Scenario**: An exception occurs during scraping inside a `try...finally` block where both the inner block and an outer lifecycle manager attempt to close the agent's browser, or `close_browser()` is called after the browser was stopped.
- **Verbatim Code (`agents/base_agent.py:29-39`)**:
  ```python
  def close_browser(self):
      """Cleans up the Playwright instance."""
      if self.page:
          self.page.close()
      if self.context:
          self.context.close()
      if self.browser:
          self.browser.close()
      if self.playwright:
          self.playwright.stop()
  ```
- **Blast Radius**: `self.page`, `self.context`, `self.browser`, and `self.playwright` remain truthy objects rather than being reset to `None`. On a subsequent close call, `self.page.close()` is executed against an already stopped Playwright event loop, throwing `playwright._impl._errors.Error: Event loop is closed! Is Playwright already stopped?` and masking the original application exception.
- **Empirical Reproduction**:
  ```bash
  ./venv/bin/pytest tests/test_challenger_m1_deep_stress.py::TestPlaywrightLifecycleSafety::test_browser_idempotent_double_close -v
  ```
  *Output*:
  ```text
  FAILED: Double close_browser raised unexpected exception: Event loop is closed! Is Playwright already stopped?
  playwright._impl._errors.Error: Event loop is closed! Is Playwright already stopped?
  ```
- **Suggested Mitigation**:
  Wrap each step in `try...except` and reset internal references to `None`:
  ```python
  def close_browser(self):
      """Cleans up the Playwright instance idempotently."""
      try:
          if self.page and not self.page.is_closed():
              self.page.close()
      except Exception:
          pass
      finally:
          self.page = None

      try:
          if self.context:
              self.context.close()
      except Exception:
          pass
      finally:
          self.context = None

      try:
          if self.browser:
              self.browser.close()
      except Exception:
          pass
      finally:
          self.browser = None

      try:
          if self.playwright:
              self.playwright.stop()
      except Exception:
          pass
      finally:
          self.playwright = None
  ```

---

### [Medium] Challenge 2: Greedy Outer-Brace Slicing Corrupts JSON in `LocalLLMExtractor._clean_json_response`

- **Assumption Challenged**: The first `{` in the local LLM output is always the root of the JSON payload.
- **Attack Scenario**: A local reasoning model (e.g. DeepSeek-R1, Qwen 2.5, Nemotron) includes mathematical expressions, placeholders, or preamble containing `{` before the JSON object (e.g. `"Considering criteria {budget} and {zip_code}:\n{\"address\": \"123 Main St\", \"zip_code\": \"94115\"}"`).
- **Verbatim Code (`agents/extractor.py:104-109`)**:
  ```python
  start = text.find("{")
  end = text.rfind("}")
  if start != -1 and end != -1 and end > start:
      return text[start:end+1]
  return text
  ```
- **Blast Radius**: `start` points to the brace in `{budget}`, so `text[start:end+1]` extracts:
  `"{budget} and {zip_code}:\n{\"address\": \"123 Main St\", \"zip_code\": \"94115\"}"`
  This causes `PropertyExtraction.model_validate_json` and `json.loads` to crash with `JSONDecodeError`.
- **Empirical Reproduction**:
  ```python
  from agents.extractor import LocalLLMExtractor
  import json

  ext = LocalLLMExtractor()
  output = "I evaluated {condition_a} and decided on:\n{\"address\": \"123 Main St\", \"zip_code\": \"94115\"}"
  cleaned = ext._clean_json_response(output)
  # Result: '{condition_a} and decided on:\n{"address": "123 Main St", "zip_code": "94115"}'
  # json.loads(cleaned) -> json.decoder.JSONDecodeError: Expecting property name enclosed in double quotes
  ```
- **Suggested Mitigation**:
  Prioritize regex extraction of fenced code blocks (```json ... ```), strip reasoning tags (like `<think>...</think>`), or use a bracket balancing scanner to isolate genuine JSON objects.

---

### [Low] Challenge 3: 2-Digit Year Parsing in `CountyAgent.parse_permit_date`

- **Assumption Challenged**: All municipal permit dates use 4-digit years.
- **Attack Scenario**: Older county archives record permit dates in short form such as `"05/15/98"` or `"12-01-04"`.
- **Empirical Observation**:
  `CountyAgent.parse_permit_date("05/15/98")` returns `None` because `strptime` formats only specify `%Y` and the regex fallback `\b(19\d\d|20\d\d)\b` requires 4 digits.
- **Blast Radius**: Roof age is not computed from short-form date strings, defaulting `roof_age_years` to `None`.
- **Suggested Mitigation**:
  Add `"%m/%d/%y"` and `"%m-%d-%y"` to the strptime format tuple.

---

## 3. Stress Test Results Matrix

| Stress Dimension | Test Description | Target Module | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|---|---|
| **DOM Cleaning** | Malformed HTML with unclosed tags | `ZillowAgent.clean_dom` | Parse clean text without crashing | Clean text extracted, scripts stripped | **PASS** |
| **DOM Cleaning** | 50-level nested tags & SVGs | `ZillowAgent.clean_dom` | Strip scripts/svgs without recursion error | Scripts/svgs decomposed cleanly | **PASS** |
| **DOM Cleaning** | 50,000 token (250KB+) payload | `ZillowAgent.clean_dom` | Execute in < 5s, limit to 12,000 chars | Finished in 0.05s, len <= 12,000 chars | **PASS** |
| **DOM Cleaning** | Non-standard tags, CDATA, MathML | `ZillowAgent.clean_dom` | Extract text cleanly | Text extracted without error | **PASS** |
| **DOM Cleaning** | Null bytes `\x00` and unicode `\xa0` | `ZillowAgent.clean_dom` | Clean text without crashing | Successfully cleaned | **PASS** |
| **DOM Cleaning** | Municipal multi-column permit tables | `CountyAgent.clean_dom` | Retain parcel info, strip forms/nav | Tables isolated, nav removed | **PASS** |
| **DOM Cleaning** | Empty and None inputs | `BaseAgent` subclasses | Return empty string safely | Returned `""` | **PASS** |
| **Schema Validation** | Full `PropertyExtraction` payload | `PropertyExtraction` | Validate fields and types | All fields valid | **PASS** |
| **Schema Validation** | 9-digit, messy, int zip codes | `PropertyExtraction` | Normalize to 5-digit zip | Normalized via regex validator | **PASS** |
| **Schema Validation** | Missing required `address` | `PropertyExtraction` | Raise `ValidationError` | `ValidationError` raised | **PASS** |
| **Schema Validation** | String-to-number type coercions | `PropertyExtraction` | Coerce to float/int | Coerced accurately | **PASS** |
| **Schema Validation** | Mixed items in `permit_history` | `CountyPermitExtraction` | Accept `PermitRecord`, dict, str | Coerced matching dicts to `PermitRecord` | **PASS** |
| **Date Parsing** | ISO, US slash, dash, textual dates | `CountyAgent.parse_permit_date` | Return `datetime.date` | Accurately parsed | **PASS** |
| **Date Parsing** | Embedded year in free text | `CountyAgent.parse_permit_date` | Fallback to year regex (`date(Y, 1, 1)`) | Accurately parsed | **PASS** |
| **Date Parsing** | Leap day (`2024-02-29`) vs invalid | `CountyAgent.parse_permit_date` | Parse leap day; fallback on invalid | Accurately parsed | **PASS** |
| **Date Parsing** | 2-digit years (`"05/15/98"`) | `CountyAgent.parse_permit_date` | Return `date(1998, 5, 15)` | Returned `None` | **FAIL (Low)** |
| **Extractor JSON** | Markdown codeblock fences (```json) | `LocalLLMExtractor` | Strip fences and return clean JSON | JSON isolated cleanly | **PASS** |
| **Extractor JSON** | Thinking tokens (`<think>...</think>`) | `LocalLLMExtractor` | Extract JSON payload | JSON isolated cleanly | **PASS** |
| **Extractor JSON** | Preamble text with curly braces | `LocalLLMExtractor` | Extract genuine JSON object | Outer brace slice corrupts JSON | **FAIL (Medium)** |
| **Extractor JSON** | Braces inside string values | `LocalLLMExtractor` | Preserve internal braces | JSON parsed cleanly | **PASS** |
| **Lifecycle Safety** | Idempotent double `close_browser()` | `BaseAgent` | Close cleanly without exception | Event loop closed error raised | **FAIL (High)** |
| **Lifecycle Safety** | Context manager clean exit & error safety | `BaseAgent` | Browser closed on normal/error exit | Browser closed properly | **PASS** |
| **Lifecycle Safety** | Concurrent browser isolation | `BaseAgent` | Multi-threaded agents run independently | 3 threads completed cleanly | **PASS** |
| **Database** | Unique address constraint | `Lead` (SQLAlchemy) | Reject duplicate address insertion | `IntegrityError` raised | **PASS** |
| **Database** | SQL injection strings in address | `Lead` (SQLAlchemy) | Store safely without SQL execution | Stored safely via parameterized queries | **PASS** |
| **Database** | Transaction rollback on failure | `get_session` | Session healthy after rollback | Clean rollback verified | **PASS** |
| **Pipeline CLI** | Multiple runs idempotency | `main.py` | No duplicate leads created | Counts constant across runs | **PASS** |
| **Pipeline CLI** | Targeted address mode | `main.py` | Enrich specific property | Processed and persisted | **PASS** |

---

## 4. Unchallenged Areas

- **Live Dynamic Bot-Protection**: Live execution against active anti-bot systems (Cloudflare turnstiles, DataDome) was not tested against production servers to prevent external IP blacklisting and adhere to offline zero-cloud test standards.

---

## 5. Explicit Recommendation

**Verdict**: **REQUEST_CHANGES**

The worker should apply the following targeted fixes:
1. **Fix `BaseAgent.close_browser()`**: Ensure browser cleanup is idempotent by setting `self.page`, `self.context`, `self.browser`, `self.playwright` to `None` and wrapping teardown calls in `try...except`.
2. **Harden `LocalLLMExtractor._clean_json_response()`**: Improve JSON extraction to ignore curly braces inside non-JSON preambles or reasoning blocks.
3. **Extend `CountyAgent.parse_permit_date()`**: Add `%m/%d/%y` and `%m-%d-%y` to strptime format tuples to support 2-digit years.
