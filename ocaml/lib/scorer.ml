(**
   scorer.ml - Pure deterministic mathematical actionability scoring engine.
   Implements continuous and discrete multi-component score S(L) in [0.0, 100.0].
   Produces genuine RFC 6234 / FIPS 180-4 cryptographic proof digests.
*)

open Types

let current_year_default = 2026

let compute_age_score ?(current_year = current_year_default) (roof_age : float option) (year_built : int option) : float =
  let effective_age =
    match roof_age with
    | Some a -> max 0.0 a
    | None ->
        match year_built with
        | Some y -> float_of_int (max 0 (current_year - y))
        | None -> 15.0
  in
  let age_ratio = min 1.0 (max 0.0 (effective_age /. 30.0)) in
  age_ratio *. 40.0

let compute_value_score (est_val : float option) : float =
  match est_val with
  | Some v when v >= 1000000.0 ->
      let scaled = min 1.0 (max 0.0 ((v -. 1000000.0) /. 4000000.0)) in
      15.0 +. (scaled *. 20.0)
  | _ -> 0.0

let compute_type_score (r_type : roof_type) (p_type : property_type) : float =
  match (r_type, p_type) with
  | (Victorian, SingleFamily) -> 25.0
  | (Mansard, SingleFamily) -> 24.0
  | (Flat, SingleFamily) -> 22.0
  | (Victorian, MultiUnit2To4) -> 20.0
  | (Mansard, MultiUnit2To4) -> 19.0
  | (Flat, MultiUnit2To4) -> 18.0
  | (Other _, SingleFamily) -> 12.0
  | _ -> 10.0

let compute_actionability_score
    ?(current_year = current_year_default)
    (roof_age : float option)
    (year_built : int option)
    (est_val : float option)
    (r_type : roof_type)
    (p_type : property_type) : scoring_components =
  let age_comp = compute_age_score ~current_year roof_age year_built in
  let val_comp = compute_value_score est_val in
  let type_comp = compute_type_score r_type p_type in
  let total = min 100.0 (max 0.0 (age_comp +. val_comp +. type_comp)) in
  {
    age_score = age_comp;
    value_score = val_comp;
    type_score = type_comp;
    total_score = total;
  }

let calculate_score ?(current_year = current_year_default) (lead : raw_lead) : scoring_components =
  compute_actionability_score
    ~current_year
    lead.roof_age_years
    lead.year_built
    lead.estimated_value
    lead.roof_type
    lead.property_type

let verify_lead
    ?(current_year = current_year_default)
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

  let scores = calculate_score ~current_year lead in

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
