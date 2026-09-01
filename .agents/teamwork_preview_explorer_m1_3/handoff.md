# Milestone 1 Exploration Report: Formal Types, Mathematical Invariants & Deterministic Scorer

## 1. Observation

### 1.1 Legacy Vulnerabilities & Violations in Existing Codebase
Direct inspection of `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml/lib/invariants.ml` and `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/ocaml/lib/parser.ml` revealed critical design flaws and red-team integrity violations:

1. **Mock Cryptographic Digest Generation**:
   In `ocaml/lib/invariants.ml` (lines 209, 222-230):
   ```ocaml
   let proof_id = Printf.sprintf "PROOF-OCAML-%08X" (Hashtbl.hash (lead.address ^ string_of_float scores.total_actionability_score)) in
   ...
   let dummy_hash = Printf.sprintf "%08x%08x" (Hashtbl.hash lead.address) (Hashtbl.hash (string_of_float scores.total_actionability_score)) in
   ```
   *Observation*: `Hashtbl.hash` produces non-cryptographic, architecture-dependent 30-bit integers formatted as a pseudo-hex string. This violates the mandatory Victory Audit protocol ("Agents must use actual cryptographic primitives and are explicitly forbidden from substituting hashes or mocks to force tests to pass").

2. **Ad-Hoc Regex Parsing without True AST**:
   In `ocaml/lib/parser.ml` (lines 20-31, 65-96):
   ```ocaml
   let extract_string_field (key : string) (json_str : string) : string option =
     let pattern = "\"" ^ key ^ "\"" in
     try
       let k_pos = Str.search_forward (Str.regexp_string pattern) json_str 0 in
   ```
   *Observation*: The legacy parser used regular expression slicing via the `Str` library rather than constructing a syntax tree. Nested JSON, escaped characters, unicode code points, and formatted JSON broke field extraction.

3. **Monolithic Module Coupling**:
   *Observation*: Invariant verification, scoring arithmetic, proof generation, string parsing, and string formatting were tangled across `invariants.ml` and `parser.ml`, making modular verification and testing difficult.

### 1.2 Requirements from `PROJECT.md` and `ORIGINAL_REQUEST.md`
- **INV1 (Physical Eligibility)**: Roof type $\in \{\text{Victorian}, \text{Flat}, \text{Mansard}\}$ AND Property type $\in \{\text{SingleFamily}, \text{MultiUnit2To4}\}$.
- **INV2 (Temporal Degradation)**: Documented $\text{RoofAge} \ge 15.0\text{ years}$ OR $\text{YearBuilt} \le 1996$ ($\ge 30\text{ years old}$ relative to current year 2026).
- **INV3 (Economic Viability)**: $\text{EstimatedValue} \ge \$1,000,000.00$ AND $\text{is\_hoa} = \text{false}$ AND $\text{is\_rental} = \text{false}$.
- **INV4 (Permit Recency Non-Conflict)**: No roof replacement permits issued or filed within the preceding 15 years ($(2026 - y) < 15 \implies y \ge 2012$).
- **Deterministic Actionability Scoring**:
  $$S(L) = \text{AgeScore}(L) + \text{ValueScore}(L) + \text{TypeScore}(L) \in [0.0, 100.0]$$
  - $\text{AgeScore} \in [0.0, 40.0]$: $\min(1.0, A_{eff} / 30.0) \times 40.0$
  - $\text{ValueScore} \in [0.0, 35.0]$: $15.0 + (\min(1.0, (V - 10^6) / 4\cdot 10^6) \times 20.0)$ if $V \ge 10^6$, else $0.0$.
  - $\text{TypeScore} \in [10.0, 25.0]$: Victorian SFR (25.0), Mansard SFR (24.0), Flat SFR (22.0), Victorian 2-4 (20.0), Mansard 2-4 (19.0), Flat 2-4 (18.0), Other SFR (12.0), default (10.0).
- **Genuine SHA-256 Proofs**: Cryptographic proof digest generated via `Roof_crypto.sha256_string` over canonical representation.

---

## 2. Logic Chain

### 2.1 Module Separation Architecture
To achieve clean separation of concerns and pure functional purity:
1. `types.ml`: Algebraic data types (`roof_type`, `property_type`, `permit_record`, `raw_lead`, `scoring_components`, `invariant_violation`, `invariant_status`, `qualification_verdict`, `verified_lead`). Zero dependency on other modules.
2. `invariants.ml`: Pure mathematical predicate checks for INV1, INV2, INV3, INV4. Depends only on `Types`.
3. `scorer.ml`: Pure mathematical calculation of continuous and discrete score components $S(L) \in [0.0, 100.0]$. Depends only on `Types`.
4. Integration with `crypto.ml` & `json.ml`: Verification coordinator creates canonical payload strings, hashes them via `Crypto.sha256_string`, and serializes to `Json.t` AST without using `Str` or external C bindings.

### 2.2 Formal Invariant State Machine
Each invariant check evaluates to `invariant_status`:
- `Satisfied of string` (informative pass summary)
- `Violated of invariant_violation` (`{ code; name; message }`)

A lead is `Qualified` if and only if $\forall i \in \{1, 2, 3, 4\}, \text{INV}_i(L) = \text{Satisfied}(\dots)$. If any invariant evaluates to `Violated`, the lead is classified as `Disqualified` with all violated invariants collected in `failed_invariants`.

### 2.3 Cryptographic Integrity and Canonical Proof Encoding
To ensure that proofs are immutable and tamper-evident:
1. Canonical payload format:
   `"ROO4U-PROOF-V1|" ^ address ^ "|" ^ zip_code ^ "|" ^ prop_type ^ "|" ^ roof_type ^ "|" ^ Printf.sprintf "%.2f" total_score ^ "|" ^ timestamp`
2. Digest: `sha256_proof = Crypto.sha256_string canonical_payload` (64 lowercase hex characters).
3. Proof Identifier: `proof_id = "PROOF-OCAML-" ^ (String.sub sha256_proof 0 16 |> String.uppercase_ascii)`.

---

## 3. Implementation Blueprint & Code Designs

### 3.1 `ocaml/lib/types.ml` Blueprint
```ocaml
(**
   types.ml - Formal algebraic data types for Roo4u lead verification and scoring.
   Statically typed representations for municipal properties, permits, invariants, and proofs.
*)

type roof_type =
  | Victorian
  | Flat
  | Mansard
  | Gable
  | Hip
  | Metal
  | Unknown
  | Other of string

type property_type =
  | SingleFamily
  | MultiUnit2To4
  | MultiUnit5Plus
  | Commercial
  | MixedUse
  | Condo
  | Unknown
  | Other of string

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

type invariant_status =
  | Satisfied of string
  | Violated of invariant_violation

type scoring_components = {
  age_score : float;     (** 0.0 to 40.0 *)
  value_score : float;   (** 0.0 to 35.0 *)
  type_score : float;    (** 10.0 to 25.0 *)
  total_score : float;   (** 0.0 to 100.0 *)
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

(** Helper string converters *)
let string_of_roof_type = function
  | Victorian -> "Victorian"
  | Flat -> "Flat"
  | Mansard -> "Mansard"
  | Gable -> "Gable"
  | Hip -> "Hip"
  | Metal -> "Metal"
  | Unknown -> "Unknown"
  | Other s -> s

let parse_roof_type (raw : string) : roof_type =
  let s = String.lowercase_ascii (String.trim raw) in
  let contains_sub sub =
    let sub_len = String.length sub in
    let s_len = String.length s in
    let rec check i =
      if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else check (i + 1)
    in
    check 0
  in
  if contains_sub "vic" then Victorian
  else if s = "flat" || contains_sub "tar" || contains_sub "built-up" || contains_sub "bitumen" || contains_sub "torch" || s = "tpo" || s = "epdm" then Flat
  else if contains_sub "mansard" then Mansard
  else if contains_sub "gable" || contains_sub "pitch" then Gable
  else if contains_sub "hip" then Hip
  else if contains_sub "metal" || contains_sub "seam" then Metal
  else if s = "unknown" || s = "" then Unknown
  else Other raw

let string_of_property_type = function
  | SingleFamily -> "Single-Family"
  | MultiUnit2To4 -> "Multi-Unit (2-4 Units)"
  | MultiUnit5Plus -> "Multi-Family (5+ Units)"
  | Commercial -> "Commercial"
  | MixedUse -> "Mixed-Use"
  | Condo -> "Condominium"
  | Unknown -> "Unknown"
  | Other s -> s

let parse_property_type (raw : string) : property_type =
  let s = String.lowercase_ascii (String.trim raw) in
  let contains_sub sub =
    let sub_len = String.length sub in
    let s_len = String.length s in
    let rec check i =
      if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else check (i + 1)
    in
    check 0
  in
  if s = "single-family" || s = "single family" || s = "sfr" || s = "single family residential" || s = "1 family dwelling" || s = "townhouse" then SingleFamily
  else if s = "multi-unit" || s = "2-unit" || s = "3-unit" || s = "4-unit" || s = "duplex" || s = "triplex" || s = "fourplex" || s = "2 family dwelling" || s = "multiunit2to4" || contains_sub "2-4 unit" then MultiUnit2To4
  else if contains_sub "apartment" || contains_sub "5+ unit" || s = "multi-family" || s = "multiunit5plus" then MultiUnit5Plus
  else if contains_sub "commercial" || contains_sub "retail" || contains_sub "office" || contains_sub "industrial" then Commercial
  else if contains_sub "mixed" then MixedUse
  else if contains_sub "condo" || contains_sub "co-op" then Condo
  else if s = "unknown" || s = "" then Unknown
  else Other raw
```

---

### 3.2 `ocaml/lib/invariants.ml` Blueprint
```ocaml
(**
   invariants.ml - Pure functional mathematical invariant verification engine.
   Formally evaluates INV1, INV2, INV3, and INV4 against raw lead records.
*)

open Types

let current_year_default = 2026

(** Helper: extracts 4-digit integer year (1800-2099) from date strings without Str regex *)
let extract_year_from_string (s : string) : int option =
  let len = String.length s in
  let rec find_digit idx =
    if idx + 3 >= len then None
    else
      let c0 = s.[idx] in
      let c1 = s.[idx + 1] in
      let c2 = s.[idx + 2] in
      let c3 = s.[idx + 3] in
      if c0 >= '0' && c0 <= '9' &&
         c1 >= '0' && c1 <= '9' &&
         c2 >= '0' && c2 <= '9' &&
         c3 >= '0' && c3 <= '9' then
        let yr = ((Char.code c0 - 48) * 1000) +
                 ((Char.code c1 - 48) * 100) +
                 ((Char.code c2 - 48) * 10) +
                 (Char.code c3 - 48) in
        if yr >= 1800 && yr <= 2099 then Some yr
        else find_digit (idx + 1)
      else find_digit (idx + 1)
  in
  find_digit 0

(** Invariant 1: Physical Eligibility *)
let check_inv1_physical (r_type : roof_type) (p_type : property_type) : invariant_status =
  let valid_roof =
    match r_type with
    | Victorian | Flat | Mansard -> true
    | Gable | Hip | Metal | Unknown | Other _ -> false
  in
  let valid_prop =
    match p_type with
    | SingleFamily | MultiUnit2To4 -> true
    | MultiUnit5Plus | Commercial | MixedUse | Condo | Unknown | Other _ -> false
  in
  if valid_roof && valid_prop then
    Satisfied "INV-1: Physical structure matches target architectural profile (Victorian/Flat/Mansard & SFR/Multi-Unit 2-4)."
  else
    Violated {
      code = INV1_Physical;
      name = "INV-1: Physical Eligibility";
      message = Printf.sprintf "Ineligible architecture: roof is %s and property is %s"
        (string_of_roof_type r_type)
        (string_of_property_type p_type);
    }

(** Invariant 2: Temporal Degradation *)
let check_inv2_temporal ?(current_year = current_year_default) (roof_age : float option) (year_built : int option) : invariant_status =
  match roof_age with
  | Some age when age >= 15.0 ->
      Satisfied (Printf.sprintf "INV-2: Roof age %.1f years exceeds qualification threshold (>= 15.0 yrs)." age)
  | Some age ->
      Violated {
        code = INV2_Temporal;
        name = "INV-2: Temporal Degradation";
        message = Printf.sprintf "Roof age %.1f years is under 15.0 years threshold." age;
      }
  | None ->
      match year_built with
      | Some y when (current_year - y) >= 30 ->
          Satisfied (Printf.sprintf "INV-2: Structure built in %d (age %d yrs) with no roof replacement on record (>= 30 yrs)." y (current_year - y))
      | Some y ->
          Violated {
            code = INV2_Temporal;
            name = "INV-2: Temporal Degradation";
            message = Printf.sprintf "Structure built in %d is under 30 years old without documented roof age." y;
          }
      | None ->
          Violated {
            code = INV2_Temporal;
            name = "INV-2: Temporal Degradation";
            message = "Neither roof age nor construction year is available to confirm temporal degradation.";
          }

(** Invariant 3: Economic Viability *)
let check_inv3_economic (est_value : float option) (is_hoa : bool) (is_rental : bool) : invariant_status =
  if is_hoa then
    Violated {
      code = INV3_Economic;
      name = "INV-3: Economic Viability";
      message = "Property is managed by an HOA; individual owner cannot authorize exterior roofing.";
    }
  else if is_rental then
    Violated {
      code = INV3_Economic;
      name = "INV-3: Economic Viability";
      message = "Property is marked as rental/commercial tenant occupied.";
    }
  else
    match est_value with
    | Some v when v >= 1000000.0 ->
        Satisfied (Printf.sprintf "INV-3: Assessed valuation $%.2f meets high-income neighborhood threshold (>= $1.0M)." v)
    | Some v ->
        Violated {
          code = INV3_Economic;
          name = "INV-3: Economic Viability";
          message = Printf.sprintf "Assessed valuation $%.2f is below $1,000,000.00 threshold." v;
        }
    | None ->
        Violated {
          code = INV3_Economic;
          name = "INV-3: Economic Viability";
          message = "No assessed valuation on record.";
        }

(** Helper: checks if permit relates to roofing replacement *)
let is_roof_replacement_permit (p : permit_record) : bool =
  if p.is_roof_replacement then true
  else
    let desc = String.lowercase_ascii p.description in
    let ptype = match p.permit_type with Some t -> String.lowercase_ascii t | None -> "" in
    let combined = desc ^ " " ^ ptype in
    let contains_sub sub =
      let sub_len = String.length sub in
      let s_len = String.length combined in
      let rec check i =
        if i + sub_len > s_len then false
        else if String.sub combined i sub_len = sub then true
        else check (i + 1)
      in
      check 0
    in
    contains_sub "reroof" || contains_sub "re-roof" || contains_sub "roof replace" || contains_sub "tear off" || contains_sub "tear-off"

let get_permit_year (p : permit_record) : int option =
  match p.year with
  | Some y -> Some y
  | None ->
      match p.date_issued with
      | Some d -> (match extract_year_from_string d with Some y -> Some y | None -> (match p.date_filed with Some f -> extract_year_from_string f | None -> None))
      | None -> (match p.date_filed with Some f -> extract_year_from_string f | None -> None)

(** Invariant 4: Permit Recency Non-Conflict *)
let check_inv4_permits ?(current_year = current_year_default) (permits : permit_record list) : invariant_status =
  let recent_conflicts =
    List.filter (fun p ->
      if is_roof_replacement_permit p then
        match get_permit_year p with
        | Some y when (current_year - y) < 15 -> true
        | _ -> false
      else false
    ) permits
  in
  match recent_conflicts with
  | [] -> Satisfied "INV-4: No conflicting roof replacement permits recorded in the preceding 15 years."
  | c :: _ ->
      let yr_info = match get_permit_year c with Some y -> Printf.sprintf " in %d" y | None -> "" in
      Violated {
        code = INV4_Permits;
        name = "INV-4: Permit Recency Non-Conflict";
        message = Printf.sprintf "Conflicting active/recent roof replacement permit found: %s%s" c.permit_number yr_info;
      }
```

---

### 3.3 `ocaml/lib/scorer.ml` Blueprint
```ocaml
(**
   scorer.ml - Pure deterministic mathematical actionability scoring engine.
   Implements continuous and discrete multi-component score S(L) in [0.0, 100.0].
*)

open Types

let current_year_default = 2026

let compute_actionability_score
    ?(current_year = current_year_default)
    (roof_age : float option)
    (year_built : int option)
    (est_val : float option)
    (r_type : roof_type)
    (p_type : property_type) : scoring_components =
  let effective_age =
    match roof_age with
    | Some a -> max 0.0 a
    | None ->
        match year_built with
        | Some y -> float_of_int (max 0 (current_year - y))
        | None -> 15.0
  in
  (* 1. Age Component: 0.0 to 40.0 pts *)
  let age_ratio = min 1.0 (max 0.0 (effective_age /. 30.0)) in
  let age_comp = age_ratio *. 40.0 in

  (* 2. Value Component: 0.0 to 35.0 pts (scaled linearly between $1.0M and $5.0M) *)
  let val_comp =
    match est_val with
    | Some v when v >= 1000000.0 ->
        let scaled = min 1.0 (max 0.0 ((v -. 1000000.0) /. 4000000.0)) in
        15.0 +. (scaled *. 20.0)
    | _ -> 0.0
  in

  (* 3. Architectural Type Component: 10.0 to 25.0 pts *)
  let type_comp =
    match (r_type, p_type) with
    | (Victorian, SingleFamily) -> 25.0
    | (Mansard, SingleFamily) -> 24.0
    | (Flat, SingleFamily) -> 22.0
    | (Victorian, MultiUnit2To4) -> 20.0
    | (Mansard, MultiUnit2To4) -> 19.0
    | (Flat, MultiUnit2To4) -> 18.0
    | (Other _, SingleFamily) -> 12.0
    | _ -> 10.0
  in

  let total = min 100.0 (max 0.0 (age_comp +. val_comp +. type_comp)) in
  {
    age_score = age_comp;
    value_score = val_comp;
    type_score = type_comp;
    total_score = total;
  }
```

---

### 3.4 Verification Coordinator & Genuine Cryptographic Proof Generation
```ocaml
(**
   Lead verification orchestrator producing genuine RFC 6234 / FIPS 180-4 proofs.
*)

let verify_lead
    ?(current_year = 2026)
    ?(timestamp = "2026-09-01T06:00:00Z")
    (lead : raw_lead) : verified_lead =
  let inv1 = Invariants.check_inv1_physical lead.roof_type lead.property_type in
  let inv2 = Invariants.check_inv2_temporal ~current_year lead.roof_age_years lead.year_built in
  let inv3 = Invariants.check_inv3_economic lead.estimated_value lead.is_hoa lead.is_rental in
  let inv4 = Invariants.check_inv4_permits ~current_year lead.permits in

  let all_results = [inv1; inv2; inv3; inv4] in
  let violations =
    List.filter_map (function
      | Violated v -> Some v
      | Satisfied _ -> None
    ) all_results
  in
  let passed =
    List.filter_map (function
      | Satisfied msg -> Some msg
      | Violated _ -> None
    ) all_results
  in

  let scores =
    Scorer.compute_actionability_score
      ~current_year
      lead.roof_age_years
      lead.year_built
      lead.estimated_value
      lead.roof_type
      lead.property_type
  in

  (* Canonical string representation for cryptographic digest *)
  let status_str = if violations = [] then "QUALIFIED" else "DISQUALIFIED" in
  let canonical_payload =
    Printf.sprintf "ROO4U-PROOF-V1|%s|%s|%s|%s|%s|%.2f|%s"
      lead.address
      lead.zip_code
      (string_of_property_type lead.property_type)
      (string_of_roof_type lead.roof_type)
      status_str
      scores.total_score
      timestamp
  in

  (* Genuine SHA-256 computation via pure OCaml Crypto module *)
  let sha256_proof = Crypto.sha256_string canonical_payload in
  let proof_id = "PROOF-OCAML-" ^ (String.sub sha256_proof 0 16 |> String.uppercase_ascii) in

  let verdict =
    match violations with
    | [] ->
        Qualified {
          score = scores;
          invariants_passed = passed;
          proof_id = proof_id;
        }
    | fails ->
        Disqualified {
          failed_invariants = fails;
          partial_score = scores.total_score;
          score_components = scores;
        }
  in

  {
    lead;
    verdict;
    proof_id;
    sha256_proof;
    timestamp;
  }
```

---

## 4. Caveats

1. **Date Extraction Scope**:
   The date extraction function `extract_year_from_string` scans for 4-digit years between 1800 and 2099. Two-digit years in arbitrary text strings are mapped to standard date conventions during earlier parsing in `datasf.ml`/`municipal.ml`.
2. **Scoring Bounds**:
   When a lead is disqualified, its `partial_score` is still computed deterministically and preserved in `Disqualified.partial_score` for learning agent telemetry ranking and vector similarity features.

---

## 5. Conclusion

The updated design for `types.ml`, `invariants.ml`, and `scorer.ml`:
1. **Completely Eliminates Fake Hashes**: Replaces `Hashtbl.hash` and `dummy_hash` with genuine 64-character SHA-256 cryptographic digests generated via pure RFC 6234 OCaml (`crypto.ml`).
2. **Implements Pure Functional Invariant Verification**: Formally encodes INV1, INV2, INV3, and INV4 with rich, structured violation diagnostics (`invariant_violation`).
3. **Guarantees Deterministic Mathematical Scoring**: Computes $S(L) = \text{Age} (0\text{--}40) + \text{Value} (0\text{--}35) + \text{Type} (10\text{--}25)$ strictly bounded in $[0.0, 100.0]$.
4. **Seamlessly Interfaces with AST JSON**: Direct algebraic conversion to and from `Roof_json.t` AST without using `Str` regex hacks.

---

## 6. Verification Method

### 6.1 Programmatic Unit Tests (`ocaml/test/test_invariants.ml`)
Run the Dune test suite:
```bash
dune runtest
```

### 6.2 Test Assertions Matrix
| Test Case | Inputs | Expected Verdict | Expected Score |
|---|---|---|---|
| **Prime Victorian SFR** | Victorian, SFR, RoofAge 25.0y, Val $4.5M, Non-HOA, Non-Rental, No recent permits | `Qualified` | $\approx 90.83$ ($\ge 80.0$) |
| **Flat Roof 2-4 Unit** | Flat, MultiUnit2To4, RoofAge 18.0y, Val $2.8M, Non-HOA | `Qualified` | $\approx 66.00$ ($\ge 60.0$) |
| **Gable Roof Ineligible** | Gable, SFR, RoofAge 20.0y, Val $2.0M | `Disqualified` (INV1) | Partial score computed |
| **HOA Managed Ineligible** | Victorian, SFR, RoofAge 20.0y, Val $3.0M, `is_hoa = true` | `Disqualified` (INV3) | Partial score computed |
| **Recent Permit Conflict** | Victorian, SFR, RoofAge 20.0y, Val $3.0M, Permit in 2023 | `Disqualified` (INV4) | Partial score computed |
| **Construction Fallback** | RoofAge None, Built 1980 (46 yrs), Val $2.0M | `Qualified` (INV2 fallback) | Age score 40.0 pts |
| **Exact $1M Threshold** | Victorian, SFR, RoofAge 15.0y, Val $1,000,000.00 | `Qualified` (INV3 edge) | Val score 15.0 pts |
| **$999,999.00 Threshold** | Victorian, SFR, RoofAge 15.0y, Val $999,999.00 | `Disqualified` (INV3) | Val score 0.0 pts |

### 6.3 Invalidation Conditions
- Any occurrence of `Hashtbl.hash` or non-standard hash functions in `invariants.ml` or `scorer.ml`.
- Any non-deterministic score output for identical property attributes.
- Failure of `sha256_proof` to match NIST SHA-256 hash output of the canonical string.
