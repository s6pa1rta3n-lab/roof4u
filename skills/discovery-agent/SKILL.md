---
name: property-discovery-agent
description: Autonomous browsing and real estate listing discovery agent specialized in Victorian and Flat roof candidate extraction.
---

# Property Discovery Agent Skill

## 1. Overview
The Property Discovery Agent navigates real estate portals and municipal parcel maps to identify candidate residential properties within specified target zip codes (e.g., `94115`, `94123`, `94118`, `94109`).

## 2. Input Contract
- **`zip_code`** (string): 5-digit United States postal code.
- **`target_address`** (optional string): Direct street address for targeted property evaluation.
- **`max_results`** (integer, default `10`): Maximum candidate URLs to extract per search page.
- **`feedforward_strategy`** (optional object): Dynamic selectors and request delays retrieved from the Learning Agent.

## 3. Execution Protocol
1. **Feedforward Check**: Query the Learning Agent for domain `zillow.com` to retrieve active failure workarounds and selector overrides.
2. **Page Navigation**: Navigate to the search endpoint (`/homes/<zip_code>_rb/`) using Playwright browser context with randomized human-like viewport and headers.
3. **DOM Pruning (`clean_dom`)**:
   - Strip non-semantic tags (`<script>`, `<style>`, `<svg>`, `<noscript>`, `<iframe>`, `<nav>`, `<footer>`).
   - Extract semantic property cards (`article[data-test="property-card"]`, `.list-card`).
   - Collapse excessive whitespace and enforce 12,000 character prompt budget.
4. **Local LLM Extraction**: Dispatch pruned text to `http://localhost:8000/v1/chat/completions` with JSON schema validation.
5. **Telemetry Hook**: If 0 cards are matched or DOM anomalies occur, emit a `DOM_SELECTOR_DRIFT` failure event to the Learning Agent.

## 4. Output Contract
Returns structured `Lead` objects containing:
- `address`: Normalized street address.
- `zip_code`: Postal code.
- `property_type`: Extracted structure classification (e.g. Single-Family).
- `roof_type`: Preliminary architectural style (e.g. Victorian, Flat).
- `estimated_value`: Price or valuation in USD.
- `status`: Set to `DISCOVERED`.
