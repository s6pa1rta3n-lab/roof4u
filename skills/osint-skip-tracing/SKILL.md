---
name: osint-skip-tracing
description: >-
  Provides capabilities for appending phone numbers to real estate leads using 
  zero-cost Open Source Intelligence (OSINT) scraping.
---

# OSINT Skip Tracing Module

## Overview
This skill interfaces with public search engines (e.g., DuckDuckGo) to search for a homeowner's name and address. It scrapes the HTML response and uses regex to extract potential phone numbers.

This is a zero-cost, best-effort alternative to paid credit-header skip tracing APIs.

## Limitations
- **Low Match Rate**: Most mobile numbers are not publicly listed alongside residential addresses.
- **False Positives**: Search results often contain unrelated phone numbers (e.g., local businesses, real estate agents) which the regex will blindly extract.
- **Rate Limiting**: Search engines may block automated requests resulting in timeouts.
