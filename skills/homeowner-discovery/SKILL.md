---
name: homeowner-discovery
description: Discovers and resolves homeowner identities, ownership structures, and property tax exemption filings via public municipal real estate records.
---

# Homeowner Discovery Skill

## Purpose
This skill answers: **"Where can I find the names of homeowners in a neighborhood (via public records)?"**
It orchestrates queries against municipal property rolls and county deed registries to resolve ownership identities, classify ownership structure (Individual, Trust, Corporate/LLC, Estate), and identify owner-occupancy via statutory homeowner tax exemptions.

## Public Record Sources
1. **San Francisco Office of the Assessor-Recorder Secured Property Roll**:
   - SODA Endpoint: `https://data.sfgov.org/resource/wv5m-vpq2.json`
   - Primary Identifiers: Assessor's Parcel Number (APN: Block and Lot), Property Location.
   - Ownership Fields: `homeowner_exemption_value` ($7,000 exemption indicates owner-occupied status; $0 indicates absentee/investor), `closed_roll_year`, `current_sales_date`, `percent_of_ownership`.
2. **County Clerk-Recorder Grantor / Grantee Official Records Index**:
   - Source: Office of the Assessor-Recorder Official Records (`sfassessor.org`).
   - Identifiers: Recorded Deeds, Transfer Deeds, Deeds of Trust, Reconveyances.

## OCaml Programmatic Interface

```ocaml
open Roof_engine
open Types

val Homeowner_names.build_homeowner_names_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?neighborhood:string ->
  ?street_address:string ->
  ?parcel_number:string ->
  unit -> (string, string) result

val Homeowner_names.fetch_homeowner_names :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?neighborhood:string ->
  ?street_address:string ->
  ?parcel_number:string ->
  unit -> (homeowner_name_record list, string) result
```

## CLI Execution

```bash
roof_pipeline --homeowner-names "Pacific Heights" --limit 10
```

## Output Schema (`homeowner_name_record`)

| Field | Type | Description |
|---|---|---|
| `parcel_number` | `string` | County Assessor Parcel Number (Block/Lot) |
| `property_location` | `string` | Cleaned municipal street address |
| `owner_name` | `string` | Resolved owner or trust entity name |
| `ownership_type` | `ownership_type` | `Individual`, `Trust`, `CorporateLLC`, `Estate`, `PublicEntity` |
| `has_homeowner_exemption` | `bool` | True if statutory $7,000 exemption is recorded (owner-occupied) |
| `exemption_value` | `float` | Dollar value of homeowner exemption |
| `assessor_neighborhood` | `string option` | Formal assessor neighborhood name |
| `closed_roll_year` | `string option` | Tax assessment tax roll year |
