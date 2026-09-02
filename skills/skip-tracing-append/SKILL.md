---
name: skip-tracing-append
description: >-
  Provides capabilities for appending real homeowner phone numbers to qualified 
  real estate leads using a third-party skip tracing API (e.g., BatchSkipTracing).
---

# Skip Tracing Append Module

## Overview
This skill interfaces with credit-header skip tracing APIs to resolve a homeowner's name and property address into a verified, actionable phone number. This module replaces the mock `555` testing numbers with production-ready outreach data.

## API Integration
The `Skip_tracer` OCaml module uses `Http_client.post` to execute REST API calls. 
It requires the `SKIP_TRACING_API_KEY` environment variable.

## Safe Credentials
When invoking this skill, agents **MUST** use the safe credentials protocol to verify that the `SKIP_TRACING_API_KEY` is present in the local `.env` file before executing pipeline commands.
