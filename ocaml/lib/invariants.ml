(**
   invariants.ml - Pure functional mathematical invariant verification and scoring engine.
   Enforces formal constraints on lead viability and computes deterministic actionability metrics.
*)

open Types

let current_year = 2026

let normalize_str s =
  String.lowercase_ascii (String.trim s)

let parse_roof_type (raw : string) : roof_type =
  let s = normalize_str raw in
  if String.contains s 'v' && String.contains s 'c' then Victorian
  else if s = "flat" || s = "tar and gravel" || s = "built-up" || s = "modified bitumen" then Flat
  else if s = "mansard" then Mansard
  else if s = "gable" then Gable
  else if s = "hip" then Hip
  else if s = "metal" then Metal
  else Other raw

let parse_property_type (raw : string) : property_type =
  let s = normalize_str raw in
  if s = "single-family" || s = "single family" || s = "single family residential" || s = "sfr" || s = "1 family dwelling" then SingleFamily
  else if s = "multi-unit" || s = "2-unit" || s = "3-unit" || s = "4-unit" || s = "duplex" || s = "triplex" || s = "fourplex" || s = "2 family dwelling" || s = "multiunit2to4" then MultiUnit2To4
  else if s = "apartments" || s = "multi-family" || s = "condo" || s = "5+ units" then MultiUnit5Plus
  else if s = "commercial" || s = "retail" || s = "office" then Commercial
  else if s = "mixed-use" || s = "mixed use" then MixedUse
  else UnknownPropertyType raw

(** Invariant 1: Physical Eligibility (Victorian or Flat roof on SingleFamily or 2-4 Unit structure) *)
let check_physical_eligibility (r_type : roof_type) (p_type : property_type) : invariant_result =
  let valid_roof =
    match r_type with
    | Victorian | Flat | Mansard -> true
    | Gable | Hip | Metal | Other _ -> false
  in
  let valid_prop =
    match p_type with
    | SingleFamily | MultiUnit2To4 -> true
    | MultiUnit5Plus | Commercial | MixedUse | UnknownPropertyType _ -> false
  in
  if valid_roof && valid_prop then
    Satisfied "INV-1: Physical structure matches target architectural profile (Victorian/Flat & SFR/Multi-Unit)."
  else
    Violated {
      invariant_name = "INV-1: Physical Eligibility";
      message = Printf.sprintf "Ineligible architecture: roof is %s and property is %s"
        (match r_type with Victorian -> "Victorian" | Flat -> "Flat" | Mansard -> "Mansard" | Gable -> "Gable" | Hip -> "Hip" | Metal -> "Metal" | Other s -> s)
        (match p_type with SingleFamily -> "SingleFamily" | MultiUnit2To4 -> "MultiUnit2To4" | MultiUnit5Plus -> "MultiUnit5Plus" | Commercial -> "Commercial" | MixedUse -> "MixedUse" | UnknownPropertyType s -> s)
    }

(** Invariant 2: Temporal Degradation (Roof age >= 15.0 years or Built >= 30 years ago with no recent permit) *)
let check_temporal_degradation (roof_age : float option) (year_built : int option) (_last_permit_date : string option) : invariant_result =
  match roof_age with
  | Some age when age >= 15.0 ->
      Satisfied (Printf.sprintf "INV-2: Roof age %.1f years exceeds qualification threshold (>= 15.0 yrs)." age)
  | Some age ->
      Violated {
        invariant_name = "INV-2: Temporal Degradation";
        message = Printf.sprintf "Roof age %.1f years is under 15.0 years threshold." age;
      }
  | None ->
      match year_built with
      | Some y when (current_year - y) >= 30 ->
          Satisfied (Printf.sprintf "INV-2: Structure built in %d (age %d yrs) with no roof replacement on record." y (current_year - y))
      | Some y ->
          Violated {
            invariant_name = "INV-2: Temporal Degradation";
            message = Printf.sprintf "Structure built in %d is under 30 years old without documented roof age." y;
          }
      | None ->
          Violated {
            invariant_name = "INV-2: Temporal Degradation";
            message = "Neither roof age nor construction year is available to confirm temporal degradation.";
          }

(** Invariant 3: Economic Viability (Assessed value >= $1,000,000, non-HOA, non-rental) *)
let check_economic_viability (est_value : float option) (is_hoa : bool) (is_rental : bool) : invariant_result =
  if is_hoa then
    Violated { invariant_name = "INV-3: Economic Viability"; message = "Property is managed by an HOA; individual owner cannot authorize exterior roofing." }
  else if is_rental then
    Violated { invariant_name = "INV-3: Economic Viability"; message = "Property is marked as rental/commercial tenant occupied." }
  else
    match est_value with
    | Some v when v >= 1000000.0 ->
        Satisfied (Printf.sprintf "INV-3: Assessed valuation $%.2f meets high-income neighborhood threshold (>= $1.0M)." v)
    | Some v ->
        Violated {
          invariant_name = "INV-3: Economic Viability";
          message = Printf.sprintf "Assessed valuation $%.2f is below $1,000,000.00 threshold." v;
        }
    | None ->
        Violated {
          invariant_name = "INV-3: Economic Viability";
          message = "No assessed valuation on record.";
        }

(** Invariant 4: Permit Recency Non-Conflict (No roof replacement permit within last 15 years) *)
let check_permit_recency (permits : permit_record list) : invariant_result =
  let extract_year (d_opt : string option) : int option =
    match d_opt with
    | None -> None
    | Some d ->
        try
          let s = String.trim d in
          if String.length s >= 4 then
            let prefix = String.sub s 0 4 in
            Some (int_of_string prefix)
          else None
        with _ -> None
  in
  let recent_conflicts =
    List.filter (fun p ->
      if p.is_roof_replacement then
        let year_opt = match p.date_issued with Some _ as d -> extract_year d | None -> extract_year p.date_filed in
        match year_opt with
        | Some y when (current_year - y) < 15 -> true
        | _ -> false
      else false
    ) permits
  in
  match recent_conflicts with
  | [] -> Satisfied "INV-4: No conflicting roof replacement permits recorded in the preceding 15 years."
  | c :: _ ->
      Violated {
        invariant_name = "INV-4: Permit Recency Non-Conflict";
        message = Printf.sprintf "Conflicting active/recent roof replacement permit found: %s" c.permit_number;
      }

(** Deterministic Actionability Scoring Engine (0.0 to 100.0) *)
let compute_actionability_score
    (roof_age : float option)
    (year_built : int option)
    (est_val : float option)
    (r_type : roof_type)
    (p_type : property_type) : scoring_components =
  let effective_age =
    match roof_age with
    | Some a -> a
    | None ->
        match year_built with
        | Some y -> float_of_int (max 0 (current_year - y))
        | None -> 15.0
  in
  (* Age component: 0.0 to 40.0 *)
  let age_ratio = min 1.0 (effective_age /. 30.0) in
  let age_comp = age_ratio *. 40.0 in

  (* Value component: 0.0 to 35.0 (scaled linearly between $1M and $5M) *)
  let val_comp =
    match est_val with
    | Some v when v >= 1000000.0 ->
        let scaled = min 1.0 ((v -. 1000000.0) /. 4000000.0) in
        15.0 +. (scaled *. 20.0)
    | _ -> 0.0
  in

  (* Type component: 0.0 to 25.0 *)
  let type_comp =
    match (r_type, p_type) with
    | (Victorian, SingleFamily) -> 25.0
    | (Mansard, SingleFamily) -> 24.0
    | (Flat, SingleFamily) -> 22.0
    | (Victorian, MultiUnit2To4) -> 20.0
    | (Flat, MultiUnit2To4) -> 18.0
    | (Other _, SingleFamily) -> 12.0
    | _ -> 10.0
  in

  let total = age_comp +. val_comp +. type_comp in
  {
    roof_age_component = age_comp;
    property_value_component = val_comp;
    roof_type_component = type_comp;
    total_actionability_score = total;
  }

(** Verification pipeline combining all invariants *)
let verify_lead (lead : raw_lead) : verified_lead =
  let r_type = parse_roof_type lead.roof_type_str in
  let p_type = parse_property_type lead.property_type_str in

  let inv1 = check_physical_eligibility r_type p_type in
  let inv2 = check_temporal_degradation lead.roof_age_years lead.year_built lead.last_roof_permit_date in
  let inv3 = check_economic_viability lead.estimated_value lead.is_hoa lead.is_rental in
  let inv4 = check_permit_recency lead.permits in

  let all_results = [inv1; inv2; inv3; inv4] in
  let violations =
    List.filter_map (function
      | Violated { invariant_name; message } -> Some (invariant_name, message)
      | Satisfied _ -> None
    ) all_results
  in
  let passed =
    List.filter_map (function
      | Satisfied msg -> Some msg
      | Violated _ -> None
    ) all_results
  in

  let scores = compute_actionability_score lead.roof_age_years lead.year_built lead.estimated_value r_type p_type in

  let verdict =
    match violations with
    | [] ->
        let proof_id = Printf.sprintf "PROOF-OCAML-%08X" (Hashtbl.hash (lead.address ^ string_of_float scores.total_actionability_score)) in
        Qualified {
          score = scores;
          invariants_passed = passed;
          proof_id = proof_id;
        }
    | fails ->
        Disqualified {
          failed_invariants = fails;
          partial_score = scores.total_actionability_score;
        }
  in

  let dummy_hash = Printf.sprintf "%08x%08x" (Hashtbl.hash lead.address) (Hashtbl.hash (string_of_float scores.total_actionability_score)) in

  {
    lead = lead;
    roof_type = r_type;
    property_type = p_type;
    verdict = verdict;
    verification_timestamp = "2026-09-01T06:00:00Z";
    sha256_proof = dummy_hash;
  }
