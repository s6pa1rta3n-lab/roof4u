---
name: permit-history-audit
description: Audits municipal building and reroofing permit history to compute empirical roof age and verify formal temporal non-replacement invariants.
---

# Permit History Audit Skill

## Purpose
This skill answers: **"Where can I find the permits for roofs in a neighborhood?"**
It audits historical and active municipal building permits to identify reroofing, tear-off, and roof repair filings, extracting permit dates, scopes of work, and project valuations to determine empirical roof age relative to current calendar year ($A_{roof} = Y_{current} - Y_{permit}$).

## Public Record Sources
1. **San Francisco Department of Building Inspection (DBI) Building Permits**:
   - SODA Endpoint: `https://data.sfgov.org/resource/i98e-djp9.json`
   - Fields: `permit_number`, `block`, `lot`, `street_number`, `street_name`, `description`, `filed_date`, `issued_date`, `completed_date`, `status`, `estimated_cost`, `revised_cost`.
2. **PermitSF Integrated DBI & Planning Dataset**:
   - SODA Endpoint: `https://data.sfgov.org/resource/tyz3-vt28.json`
3. **SF DBI Permit Tracking System (PTS)**:
   - Portal: `https://dbiweb02.sfgov.org/dbipts/`
   - Real-time permit filing status, routing, and inspection sign-offs.

## OCaml Programmatic Interface

```ocaml
open Roof_engine
open Types

val Roof_permits.build_roof_permits_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?zip_code:string ->
  ?street_name:string ->
  ?keyword:string ->
  unit -> (string, string) result

val Roof_permits.fetch_roof_permits :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?current_year:int ->
  ?zip_code:string ->
  ?street_name:string ->
  ?keyword:string ->
  unit -> (roof_permit_record list, string) result
```

## CLI Execution

```bash
roof_pipeline --roof-permits "94115" --limit 15
```

## Output Schema (`roof_permit_record`)

| Field | Type | Description |
|---|---|---|
| `permit_number` | `string` | Official DBI permit application number |
| `parcel_number` | `string` | APN (Block + Lot) |
| `street_number` | `string` | Street address number |
| `street_name` | `string` | Full street name with suffix |
| `zip_code` | `string` | 5-digit postal zip code |
| `description` | `string` | Full scope of work description |
| `filed_date` | `string option` | ISO-8601 permit application filing date |
| `issued_date` | `string option` | Date permit was approved and issued |
| `completed_date` | `string option` | Final inspection sign-off date |
| `status` | `string option` | Permit status (`COMPLETED`, `ISSUED`, `FILED`) |
| `estimated_cost` | `float option` | Declared job valuation cost in USD |
| `roof_age_years` | `float option` | Empirical roof age ($Y_{current} - Y_{permit}$) |
| `is_roof_replacement` | `bool` | True if classified as reroof/tear-off work |
