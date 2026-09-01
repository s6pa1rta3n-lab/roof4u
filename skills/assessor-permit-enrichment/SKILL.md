---
name: municipal-assessor-permit-enrichment
description: Municipal public records agent querying San Francisco Planning Assessor (PIM) and DBI Building/Reroofing Permit tracking systems.
---

# Municipal Assessor & Permit Enrichment Skill

## 1. Overview
Enriches discovered real estate leads with authoritative municipal tax, ownership, parcel (APN), and historical building permit records from the City and County of San Francisco.

## 2. Target Data Endpoints
- **SF Planning Information Map (PIM)**: `https://sfplanninggis.org/pim/` (Assessor valuation, APN, owner name, zoning).
- **SF Department of Building Inspection (DBI)**: `https://dbiweb02.sfgov.org/dbipts/` (Building, alterations, and reroofing permit history).
- **DataSF Open Data Permitting API**: `https://data.sfgov.org/resource/i98e-djp9.json` and `https://data.sfgov.org/resource/tyz3-vt28.json` (Live municipal permits).

## 3. Execution Protocol
1. **Assessor Resolution**:
   - Query PIM using normalized address to extract Assessor Parcel Number (`APN`), Owner Name, and Tax Assessed Value.
   - Verify non-HOA ownership and single-owner deed status.
2. **Permit History Synthesis**:
   - Query DBI PTS or DataSF API for all historical permits associated with the address and parcel.
   - Filter records for roofing-specific keywords (`reroof`, `tear off`, `roof replacement`, `new roof`, `modified bitumen`, `shingle`).
   - Identify the most recent roofing permit date (`last_roof_permit_date`).
3. **Roof Age Calculation**:
   - If a roofing permit exists: $\text{Roof Age} = \text{Current Year} - \text{Permit Year}$.
   - If no roofing permit exists: $\text{Roof Age} = \text{Current Year} - \text{Year Built}$.
4. **State Transition**:
   - Updates lead record fields in `leads.db`.
   - Transitions lead status to `ENRICHED`.

## 4. Error Mitigation & Invariants
- Handles multi-format date strings (`YYYY-MM-DD`, `MM/DD/YYYY`, 2-digit years).
- Normalizes "None on File", "Pending", and historic exemptions to explicit `null` values.
- Intercepts municipal portal timeout and redirects to fallback Socrata OpenData JSON endpoints.
