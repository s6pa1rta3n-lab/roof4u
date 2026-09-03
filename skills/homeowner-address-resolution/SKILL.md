---
name: homeowner-address-resolution
description: Discovers and normalizes homeowner residential addresses within targeted municipal neighborhoods from public property databases.
---

# Homeowner Address Resolution Skill

## Purpose
This skill answers: **"Where can I find the addresses of homeowners in a neighborhood?"**
It queries municipal property rolls and enterprise addressing databases to extract, filter, and normalize residential property addresses within specified neighborhoods, enforcing zoning and building use constraints (Single Family Residential, 2-4 Units).

## Public Record Sources
1. **San Francisco Assessor-Recorder Secured Property Roll**:
   - SODA Endpoint: `https://data.sfgov.org/resource/wv5m-vpq2.json`
   - Geographic Dimensions: `assessor_neighborhood` (e.g., Pacific Heights, Marina, Russian Hill, Presidio Heights), `analysis_neighborhood`, `supervisor_district`.
   - Classification Fields: `use_code` (`SRES` = Single Family, `MRES` = Multi-Family), `property_class_code` (`D` = Dwellings, `Z` = Condominiums), `number_of_units`.
2. **City and County of San Francisco Enterprise Addressing System (EAS)**:
   - SODA Endpoint: `https://data.sfgov.org/resource/ramy-di5b.json`
   - Fields: Base street number, street name, street type suffix, standardized postal zip code.

## OCaml Programmatic Interface

```ocaml
open Roof_engine
open Types

val Homeowner_addresses.build_addresses_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?zip_code:string ->
  ?residential_only:bool ->
  neighborhood:string ->
  unit -> (string, string) result

val Homeowner_addresses.fetch_homeowner_addresses :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?zip_code:string ->
  ?residential_only:bool ->
  neighborhood:string ->
  unit -> (homeowner_address_record list, string) result
```

## CLI Execution

```bash
roof_pipeline --homeowner-addresses "Pacific Heights" --limit 20
```

## Output Schema (`homeowner_address_record`)

| Field | Type | Description |
|---|---|---|
| `parcel_number` | `string` | Assessor Parcel Number (APN) |
| `property_location` | `string` | Full normalized address |
| `street_number` | `string` | Base building street number |
| `street_name` | `string` | Normalized street name with suffix |
| `zip_code` | `string` | 5-digit postal code |
| `neighborhood` | `string` | Target neighborhood corridor |
| `property_class_code` | `string option` | Assessor classification code |
| `is_residential` | `bool` | True if verified residential dwelling |
| `units_count` | `int` | Number of residential living units |
