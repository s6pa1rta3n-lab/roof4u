# Architectural Investigation: Roo4u Lead Generation Pipeline & San Francisco District Support

## Executive Summary
This report presents the architectural analysis of the Roo4u pure OCaml engine, its lead generation and municipal public records pipeline, and the concrete implementation strategy for the four target San Francisco neighborhoods: **Sunset**, **Richmond**, **Excelsior**, and **Pacific Heights**.

Roo4u operates as a 100% offline, deterministic lead discovery, mathematical qualification, and cryptographic proof engine. The pipeline enforces four formal invariants (INV1–INV4), calculates multi-component actionability scores $S(L) \in [0.0, 100.0]$, generates RFC 6234 / FIPS 180-4 SHA-256 cryptographic proofs, records self-healing telemetry, and exports leads in an RFC 4180 CSV schema with DDE formula injection protection.

---

## 1. Codebase Architecture & Repository Layout

The codebase is organized in pure OCaml 5 using Dune 3.0. It contains zero external runtime dependencies outside the OCaml standard libraries (`unix`, `str`, `threads`).

### 1.1 Directory Layout
```
ocaml/
├── dune-project                  # Dune project declaration (roof_engine v2.0.0)
├── roof_engine.opam              # Opam packaging metadata
├── bin/
│   ├── dune                      # Executable configuration (roof_pipeline)
│   └── main.ml                   # CLI entrypoint with public records microservices
├── lib/
│   ├── dune                      # Library configuration (roof_engine)
│   ├── types.ml                  # Formal algebraic data types and JSON AST codecs
│   ├── types.mli                 # Interface definitions for core types
│   ├── crypto.ml                 # RFC 6234 / FIPS 180-4 SHA-256 implementation
│   ├── crypto.mli                # SHA-256 interface
│   ├── json.ml                   # Recursive descent JSON AST parser & serializer
│   ├── json.mli                  # JSON parser interface
│   ├── invariants.ml             # Formal algebraic invariants INV1, INV2, INV3, INV4
│   ├── invariants.mli            # Invariant checker interface
│   ├── scorer.ml                 # Deterministic 0.0-100.0 actionability scorer & proof generator
│   ├── embeddings.ml             # Deterministic 256-D feature hashing embedder (CRC32 + MD5)
│   ├── embeddings.mli            # Embeddings interface
│   ├── lesson_store.ml           # POSIX atomic JSON lesson store with Unix.lockf
│   ├── lesson_store.mli          # Lesson store interface
│   ├── vector_store.ml           # Embedded 256-D vector database & cosine similarity search
│   ├── vector_store.mli          # Vector store interface
│   ├── db.ml                     # SQLite lead persistence and state machine layer
│   ├── db.mli                    # Database interface
│   ├── http_client.ml            # Pure OCaml HTTP 1.1 client over Unix sockets
│   ├── http_client.mli           # HTTP client interface
│   ├── datasf.ml                 # DataSF SODA API connector (i98e-djp9 & tyz3-vt28)
│   ├── datasf.mli                # DataSF connector interface
│   ├── municipal.ml              # SF Planning PIM and DBI scraping & date normalizer
│   ├── municipal.mli             # Municipal parser interface
│   ├── homeowner_names.ml        # Microservice: SF Assessor-Recorder Secured Roll names
│   ├── homeowner_names.mli       # Homeowner names interface
│   ├── homeowner_addresses.ml    # Microservice: Enterprise Addressing System addresses
│   ├── homeowner_addresses.mli   # Homeowner addresses interface
│   ├── gis_roofs.ml              # Microservice: SF Building Footprints & GIS roof geometry
│   ├── gis_roofs.mli             # GIS roofs interface
│   ├── roof_permits.ml           # Microservice: SF DBI roofing permits & permit history
│   ├── roof_permits.mli          # Roof permits interface
│   ├── property_tax_records.ml   # Microservice: County Property & Tax assessment records
│   ├── property_tax_records.mli  # Property tax records interface
│   ├── public_records_orchestrator.ml  # Coordinator for 5 public records microservices
│   ├── public_records_orchestrator.mli # Orchestrator interface
│   ├── llm_client.ml             # Local LLM client (localhost:8000) & JSON cleaner
│   ├── llm_client.mli            # LLM client interface
│   ├── telemetry.ml              # ScrapingFailureEvent logger & GitHub issue transport
│   ├── telemetry.mli             # Telemetry interface
│   ├── csv_exporter.ml           # RFC 4180 CSV exporter with DDE injection protection
│   ├── csv_exporter.mli          # CSV exporter interface
│   ├── pipeline.ml               # Autonomous lead acquisition & qualification pipeline
│   └── pipeline.mli              # Pipeline orchestrator interface
└── test/
    ├── dune                      # Test build definitions
    ├── test_crypto.ml            # RFC 6234 standard test vectors
    ├── test_json.ml              # JSON AST parser edge cases and fuzzing
    ├── test_invariants.ml        # INV1-INV4 formal mathematical boundary checks
    ├── test_memory.ml            # Lock concurrency, embeddings & vector search
    ├── test_connectors.ml        # DataSF SoQL query builder injection tests
    ├── test_security.ml          # Adversarial vulnerability closing tests
    ├── test_e2e_pipeline.ml      # Tier 4 real-world multi-agent pipeline tests
    ├── test_adversarial_m1.ml    # M1 challenger adversarial suite
    ├── test_m1_challenger.ml     # M1 invariant challenger tests
    ├── test_tier5_adversarial.ml # Tier 5 white-box stress testing suite
    └── test_public_records_microservices.ml # Automated tests for public records microservices
```

---

## 2. Pipeline Execution Stages & Data Flow

The lead qualification process consists of eight distinct sequential stages:

```
+-----------------------------------------------------------------------------------------+
|                                    Roo4u Pipeline Flow                                  |
+-----------------------------------------------------------------------------------------+
|                                                                                         |
|  [Stage 1: Public Records & Municipal Harvesting]                                       |
|   - DataSF SODA Building Permits (i98e-djp9)                                            |
|   - DataSF SODA PermitSF (tyz3-vt28)                                                    |
|   - 5 Public Records Microservices (Names, Addresses, GIS, Permits, Tax)                |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 2: Lead Synthesis & SQLite Persistence]                                         |
|   - Raw lead synthesis into `raw_lead` records                                          |
|   - Insert into SQLite (`leads.db`) with status `DISCOVERED`                            |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 3: Enrichment & Normalization]                                                  |
|   - Attribute alignment (APN, year built, square footage, owner trust status)           |
|   - Update SQLite status to `ENRICHED`                                                  |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 4: Mathematical Invariant Qualification (INV1-4)]                               |
|   - INV1: Physical Eligibility (Victorian / Flat / Mansard; SFR / MultiUnit2To4)        |
|   - INV2: Temporal Degradation (RoofAge >= 15.0 yrs OR YearBuilt <= 1996)              |
|   - INV3: Economic Viability (AssessedValue >= $1.0M, non-HOA, non-Rental)              |
|   - INV4: Permit Recency Non-Conflict (No roof replacement in preceding 15 yrs)         |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 5: Actionability Scoring & Cryptographic Digest]                                |
|   - S(L) = S_age (0-40) + S_value (0-35) + S_type (10-25) in [0.0, 100.0]               |
|   - Canonical payload construction & RFC 6234 SHA-256 calculation                       |
|   - Proof ID generation: PROOF-OCAML-<SHA256[:16]>                                      |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 6: SQLite State Machine Finalization]                                           |
|   - Qualified leads -> `VALIDATED`                                                      |
|   - Disqualified leads -> `DISQUALIFIED`                                                |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 7: Closed-Loop Telemetry & Memory Learning]                                     |
|   - ScrapingFailureEvent capture & SHA-256 fingerprinting                               |
|   - Persistence in `lessons_learned.json` via Unix.lockf advisory locking               |
|   - 256-D feature hashing vector indexing in `vector_store.sqlite`                      |
|                                     |                                                   |
|                                     v                                                   |
|  [Stage 8: RFC 4180 CSV Lead Export]                                                    |
|   - Filtering by minimum actionability score (default >= 60.0)                          |
|   - Neutralization of DDE formula injection prefixes (=, +, -, @, \t, \r)              |
|   - 10-column export to `validated_leads.csv`                                           |
|                                                                                         |
+-----------------------------------------------------------------------------------------+
```

---

## 3. Data Structures & Schema Specification

### 3.1 Core Pipeline Data Types (`types.ml`)

#### `roof_type`
```ocaml
type roof_type =
  | Victorian
  | Flat
  | Mansard
  | Gable
  | Hip
  | Metal
  | Unknown
  | Other of string
```

#### `property_type`
```ocaml
type property_type =
  | SingleFamily
  | MultiUnit2To4
  | MultiUnit5Plus
  | Commercial
  | MixedUse
  | Condo
  | Unknown
  | Other of string
```

#### `permit_record`
```ocaml
type permit_record = {
  permit_number : string;
  permit_type : string option;
  description : string;
  date_filed : string option;
  date_issued : string option;
  status : string option;
  year : int option;
  is_roof_replacement : bool;
  cost : float option;
}
```

#### `raw_lead`
```ocaml
type raw_lead = {
  address : string;
  zip_code : string;
  property_type : property_type;
  roof_type : roof_type;
  property_type_raw : string option;
  roof_type_raw : string option;
  estimated_value : float option;
  owner_name : string option;
  is_hoa : bool;
  is_rental : bool;
  apn : string option;
  last_roof_permit_date : string option;
  roof_age_years : float option;
  year_built : int option;
  phone_number : string option;
  permits : permit_record list;
}
```

#### `scoring_components` & `qualification_verdict`
```ocaml
type scoring_components = {
  age_score : float;     (* 0.0 to 40.0 *)
  value_score : float;   (* 0.0 to 35.0 *)
  type_score : float;    (* 10.0 to 25.0 *)
  total_score : float;   (* 0.0 to 100.0 *)
}

type invariant_id =
  | INV1_Physical
  | INV2_Temporal
  | INV3_Economic
  | INV4_Permits

type invariant_violation = {
  code : invariant_id;
  name : string;
  message : string;
}

type qualification_verdict =
  | Qualified of {
      score : scoring_components;
      invariants_passed : string list;
      proof_id : string;
    }
  | Disqualified of {
      failed_invariants : invariant_violation list;
      partial_score : float;
      score_components : scoring_components;
    }

type verified_lead = {
  lead : raw_lead;
  verdict : qualification_verdict;
  proof_id : string;
  sha256_proof : string;
  timestamp : string;
}
```

### 3.2 Public Records Microservice Types (`types.ml`)

| Data Type | Primary Fields | Municipal Data Source |
|---|---|---|
| `homeowner_name_record` | `parcel_number`, `property_location`, `owner_name`, `ownership_type`, `has_homeowner_exemption`, `exemption_value`, `assessor_neighborhood`, `closed_roll_year` | SF Assessor-Recorder Secured Roll (`wv5m-vpq2`) |
| `homeowner_address_record` | `parcel_number`, `property_location`, `street_number`, `street_name`, `unit_number`, `zip_code`, `neighborhood`, `property_class_code`, `is_residential`, `units_count` | SF Enterprise Addressing System / Assessor Roll (`wv5m-vpq2`) |
| `gis_roof_record` | `parcel_number`, `property_location`, `roof_size_sqft`, `roof_type_classified`, `ground_elevation_ft`, `roof_height_ft`, `coordinates_latitude`, `coordinates_longitude`, `polygon_points_count`, `is_green_roof_or_solar` | SF Building Footprints / Green Roofs GIS (`sfnk-6tdn`) & SF Planning PIM |
| `roof_permit_record` | `permit_number`, `block`, `lot`, `parcel_number`, `street_number`, `street_name`, `zip_code`, `description`, `filed_date`, `issued_date`, `completed_date`, `status`, `estimated_cost`, `roof_age_years`, `is_roof_replacement` | SF DBI Building Permits (`i98e-djp9`) & PermitSF (`tyz3-vt28`) |
| `property_tax_record` | `parcel_number`, `property_location`, `closed_roll_year`, `assessed_land_value`, `assessed_improvement_value`, `total_assessed_value`, `improvement_to_land_ratio`, `zoning_code`, `use_code`, `year_built`, `number_of_units`, `number_of_bedrooms`, `supervisor_district` | SF Assessor-Recorder Roll & Tax Collector (`wv5m-vpq2`) |

### 3.3 Output CSV Export Schema (`csv_exporter.ml`)

The exported `validated_leads.csv` matches the RFC 4180 10-column schema:

| Column # | Column Name | Formatting & Sanitization Rules |
|---|---|---|
| 1 | `Address` | DDE sanitization, RFC 4180 quotes |
| 2 | `Zip Code` | 5-digit string |
| 3 | `Property Type` | Formatted enum string (`Single-Family`, `Multi-Unit (2-4 Units)`) |
| 4 | `Roof Type` | Formatted enum string (`Victorian`, `Flat`, `Mansard`) |
| 5 | `Assessed Value` | Numeric float without decimals or 2 decimal places |
| 6 | `Owner Name` | DDE sanitization (prefixed with `'` if starting with `=`, `+`, `-`, `@`, `\t`, `\r`) |
| 7 | `APN` | Block/lot identifier string |
| 8 | `Roof Age (Years)` | Numeric float |
| 9 | `Phone Number` | Phone string or empty string |
| 10 | `Status` | `VALIDATED` |

---

## 4. Invariant Verification & Scoring Equations

### 4.1 Invariant Rules (`invariants.ml`)

1. **INV1 (Physical Eligibility)**:
   $$\text{Valid Roof} \in \{\text{Victorian}, \text{Flat}, \text{Mansard}\} \quad \land \quad \text{Valid Property} \in \{\text{SingleFamily}, \text{MultiUnit2To4}\}$$

2. **INV2 (Temporal Degradation)**:
   $$\text{RoofAge} \ge 15.0 \quad \lor \quad (\text{RoofAge is None} \land (\text{CurrentYear} - \text{YearBuilt} \ge 30))$$

3. **INV3 (Economic Viability)**:
   $$\text{AssessedValue} \ge \$1,000,000.00 \quad \land \quad \text{is\_hoa} = \text{false} \quad \land \quad \text{is\_rental} = \text{false}$$

4. **INV4 (Permit Recency Non-Conflict)**:
   $$\forall p \in \text{Permits}, \quad \text{IsRoofReplacement}(p) \implies (\text{CurrentYear} - \text{Year}(p) \ge 15)$$

### 4.2 Actionability Scoring Engine (`scorer.ml`)

The total score $S(L) = S_{\text{age}} + S_{\text{value}} + S_{\text{type}}$ is calculated deterministically:

- **Age Score ($S_{\text{age}} \in [0.0, 40.0]$)**:
  $$S_{\text{age}} = \min\left(1.0, \max\left(0.0, \frac{\text{EffectiveAge}}{30.0}\right)\right) \times 40.0$$

- **Value Score ($S_{\text{value}} \in [0.0, 35.0]$)**:
  $$S_{\text{value}} = \begin{cases} 15.0 + \min\left(1.0, \max\left(0.0, \frac{V - 1,000,000}{4,000,000}\right)\right) \times 20.0 & \text{if } V \ge 1,000,000 \\ 0.0 & \text{otherwise} \end{cases}$$

- **Type Score ($S_{\text{type}} \in [10.0, 25.0]$)**:
  - Victorian SFR: $25.0$
  - Mansard SFR: $24.0$
  - Flat SFR: $22.0$
  - Victorian 2-4 Units: $20.0$
  - Mansard 2-4 Units: $19.0$
  - Flat 2-4 Units: $18.0$
  - Other SFR: $12.0$
  - Default: $10.0$

### 4.3 Cryptographic Proof Generation (`scorer.ml`)

For each qualified lead, a canonical verification payload is constructed:
$$\text{Payload} = \text{"ROO4U-PROOF-V1|" } || \text{ Address } || \text{ "|" } || \text{ ZipCode } || \text{ "|" } || \text{ PropType } || \text{ "|" } || \text{ RoofType } || \text{ "|" } || \text{ Status } || \text{ "|" } || \text{ Score } || \text{ "|" } || \text{ Timestamp}$$

The 64-character SHA-256 digest is generated via pure RFC 6234 implementation (`Crypto.sha256_string`), and the Proof ID is formatted as:
$$\text{Proof ID} = \text{"PROOF-OCAML-" } || \text{ Uppercase}(\text{SHA256}[0..15])$$

---

## 5. San Francisco Target Neighborhood Qualification Analysis

The four target neighborhoods have distinct municipal identifiers, architectural profiles, and valuation ranges.

| Neighborhood | SF Zip Codes | Supervisor District | Assessor Neighborhood Keywords | Dominant Architecture & Roof Types | Valuation Baseline (INV3) | Typical Actionability Score Range |
|---|---|---|---|---|---|---|
| **Sunset** | `94122` (Inner Sunset)<br>`94116` (Outer Sunset/Parkside) | District 4 & 7 | `"Sunset"`, `"Inner Sunset"`, `"Outer Sunset"`, `"Parkside"` | 1920–1940s single-family & 2-unit flats; Flat built-up tar/gravel & Victorian/Pitched tile front | $1.2M – $2.3M | **70.0 – 86.0** |
| **Richmond** | `94118` (Inner Richmond)<br>`94121` (Outer Richmond) | District 1 | `"Richmond"`, `"Inner Richmond"`, `"Outer Richmond"`, `"Central Richmond"` | 1900–1930s Victorian & Edwardian 2-4 unit flats; Victorian pitch & Flat modified bitumen | $1.8M – $3.8M | **78.0 – 94.0** |
| **Excelsior** | `94112` (Excelsior / Outer Mission) | District 11 | `"Excelsior"`, `"Outer Mission"`, `"Crocker Amazon"` | 1900–1940s single-family residential & duplexes; Victorian pitch, Flat built-up, Mansard front | $1.05M – $1.6M | **68.0 – 82.0** |
| **Pacific Heights** | `94115` (Pacific Heights) | District 2 | `"Pacific Heights"` | 1890–1920s historic grand Victorians, Queen Annes, Mansard estates & luxury 2-4 unit flats | $2.8M – $8.5M+ | **88.0 – 98.5** |

---

## 6. Identified Gaps & Implementation Recommendations

Based on the inspection of `ocaml/lib/` and `ocaml/test/`, the following areas require alignment to support all four target neighborhoods:

### 6.1 Configuration Alignment (`pipeline.ml` & `main.ml`)
- **Current State**: `Pipeline.default_config` defines `target_zips = ["94115"; "94123"; "94118"; "94109"]`.
- **Recommendation**: Update `target_zips` to represent the four target corridors:
  $$\text{target\_zips} = [\text{"94115"}; \text{"94122"}; \text{"94118"}; \text{"94112"}]$$
  (Pacific Heights: 94115, Sunset: 94122, Richmond: 94118, Excelsior: 94112).

### 6.2 Municipal Seed Corridors (`pipeline.ml`)
- **Current State**: `default_seed_leads_for_zip` defines properties for `94115`, `94123`, `94118`, and `94109`.
- **Recommendation**: Add dedicated municipal seed properties for:
  - `94122` (Sunset: e.g. 1420 20th Ave, 1845 Irving St, 2130 Judah St)
  - `94112` (Excelsior: e.g. 450 Excelsior Ave, 780 Russia Ave, 1200 Geneva Ave)

### 6.3 Public Records Microservice Handlers (`ocaml/lib/`)
- **`homeowner_addresses.ml`**:
  - Update `zip_code` inference in `parse_homeowner_address_record` to map `"sun"` prefix to `"94122"`, `"ex"` to `"94112"`.
  - Add explicit branches for `"sunset"`, `"richmond"`, and `"excelsior"` in `fallback_addresses_for_neighborhood`.
- **`homeowner_names.ml`**, **`gis_roofs.ml`**, **`property_tax_records.ml`**:
  - Add explicit neighborhood entries for `"sunset"`, `"richmond"`, `"excelsior"`, and `"pacific heights"`.
- **`roof_permits.ml`**:
  - Add zip entries for `"94122"`, `"94116"`, `"94118"`, `"94121"`, `"94112"`, `"94115"` in `fallback_permits_for_zip`.

### 6.4 Automated Test Suite Coverage (`ocaml/test/`)
- **`test_public_records_microservices.ml`**: Add test assertions querying and verifying all four target districts through `Public_records_orchestrator.acquire_neighborhood_public_records`.
- **`test_e2e_pipeline.ml`**: Expand end-to-end scenario execution across Sunset (`94122`), Richmond (`94118`), Excelsior (`94112`), and Pacific Heights (`94115`).
