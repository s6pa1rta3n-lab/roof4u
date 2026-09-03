---
name: actionable-lead-exporter
description: Exporter agent formatting mathematically verified roofing leads into SQLite storage and validated CSV files for contractor outreach.
---

# Actionable Lead Exporter Skill

## 1. Overview
Persists and formats mathematically verified, qualified leads into production SQLite database tables (`leads.db`) and exports actionable CRM-ready CSV files (`validated_leads.csv`).

## 2. Lead Qualification Criteria
Only leads satisfying all formal mathematical invariants and receiving a status of `VALIDATED` or `QUALIFIED` with an OCaml actionability score $\ge 60.0$ are written to the export destination.

## 3. CSV Export Schema (`validated_leads.csv`)
The generated CSV file contains the following standardized columns:
1. `address`: Normalized street address.
2. `zip_code`: 5-digit postal code.
3. `property_type`: Building classification (e.g., `Single-Family`).
4. `roof_type`: Architectural roof style (e.g., `Victorian`, `Flat`).
5. `estimated_value`: Assessed property valuation in USD.
6. `apn`: San Francisco Assessor Parcel Number.
7. `owner_name`: Registered legal owner.
8. `roof_age_years`: Calculated roof age in years.
9. `last_roof_permit_date`: Date of most recent roofing permit.
10. `actionability_score`: Deterministic OCaml score ($0.0 - 100.0$).
11. `status`: Qualification state (`VALIDATED`).
12. `proof_id`: Unique mathematical verification proof hash.

## 4. Execution Invariants
- Enforces unique address constraints in `leads.db`.
- Atomic CSV export with header validation and quoted string escaping.
- Re-export triggered automatically upon pipeline completion or on demand via `CsvExporter.export_to_csv()`.
