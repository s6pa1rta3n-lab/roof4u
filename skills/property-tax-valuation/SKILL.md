---
name: property-tax-valuation
description: Extracts and analyzes county property tax assessments, land valuations, and physical structure attributes from public tax rolls.
---

# Property Tax Valuation Skill

## Purpose
This skill answers: **"Where can I find County Property & Tax records for addresses in a neighborhood?"**
It queries official county assessor property rolls and treasurer tax records to extract itemized valuations (assessed land, improvements, fixtures), calculate the improvement-to-land ratio ($V_{imp} / V_{land}$), and retrieve building structural metadata (year built, stories, units, bedrooms, bathrooms).

## Public Record Sources
1. **San Francisco Assessor-Recorder Secured Property Tax Roll**:
   - SODA Endpoint: `https://data.sfgov.org/resource/wv5m-vpq2.json`
   - Valuation Fields: `assessed_land_value`, `assessed_improvement_value`, `assessed_fixtures_value`, `assessed_personal_property_value`, `total_assessed_value`.
   - Structural Fields: `year_property_built`, `number_of_units`, `number_of_stories`, `number_of_bedrooms`, `number_of_bathrooms`, `number_of_rooms`, `zoning_code`, `tax_rate_area_code`.
2. **City and County of San Francisco Office of the Treasurer & Tax Collector**:
   - Portal: `https://sf-treasurer.org/property-tax`
   - Property Tax Installments, Delinquency Tracking, and Supplemental Tax Rolls.

## OCaml Programmatic Interface

```ocaml
open Roof_engine
open Types

val Property_tax_records.build_tax_records_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?neighborhood:string ->
  ?address:string ->
  ?parcel_number:string ->
  unit -> (string, string) result

val Property_tax_records.fetch_property_tax_records :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?neighborhood:string ->
  ?address:string ->
  ?parcel_number:string ->
  unit -> (property_tax_record list, string) result
```

## CLI Execution

```bash
roof_pipeline --property-tax-records "Pacific Heights" --limit 10
```

## Output Schema (`property_tax_record`)

| Field | Type | Description |
|---|---|---|
| `parcel_number` | `string` | County Assessor Parcel Number |
| `property_location` | `string` | Standardized property address |
| `closed_roll_year` | `string` | Tax roll assessment year |
| `assessed_land_value` | `float` | County assessed land value ($) |
| `assessed_improvement_value` | `float` | Assessed building/structure value ($) |
| `total_assessed_value` | `float` | Total statutory assessed roll value ($) |
| `improvement_to_land_ratio` | `float` | $V_{improvement} / V_{land}$ ratio |
| `year_built` | `int option` | Original construction year |
| `number_of_units` | `int option` | Total residential units |
| `number_of_stories` | `int option` | Building vertical story count |
| `number_of_bedrooms` | `int option` | Total bedroom count |
| `number_of_bathrooms` | `int option` | Total bathroom count |
| `zoning_code` | `string option` | Planning zoning classification (e.g. `RH-2`, `RH-3`) |
