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

(** Helper: substring search without regex *)
let contains_substring (needle : string) (haystack : string) : bool =
  let n_len = String.length needle in
  let h_len = String.length haystack in
  if n_len = 0 then true
  else if n_len > h_len then false
  else
    let rec check i =
      if i + n_len > h_len then false
      else if String.sub haystack i n_len = needle then true
      else check (i + 1)
    in
    check 0

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
    contains_substring "reroof" combined ||
    contains_substring "re-roof" combined ||
    contains_substring "roof replace" combined ||
    contains_substring "tear off" combined ||
    contains_substring "tear-off" combined ||
    contains_substring "shingle replace" combined ||
    contains_substring "tar and gravel" combined

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

(** Result-based lead verification helpers *)
let check_inv1 (lead : raw_lead) : (unit, string) result =
  match check_inv1_physical lead.roof_type lead.property_type with
  | Satisfied _ -> Ok ()
  | Violated v -> Error v.message

let check_inv2 ?(current_year = current_year_default) (lead : raw_lead) : (unit, string) result =
  match check_inv2_temporal ~current_year lead.roof_age_years lead.year_built with
  | Satisfied _ -> Ok ()
  | Violated v -> Error v.message

let check_inv3 (lead : raw_lead) : (unit, string) result =
  match check_inv3_economic lead.estimated_value lead.is_hoa lead.is_rental with
  | Satisfied _ -> Ok ()
  | Violated v -> Error v.message

let check_inv4 ?(current_year = current_year_default) (lead : raw_lead) : (unit, string) result =
  match check_inv4_permits ~current_year lead.permits with
  | Satisfied _ -> Ok ()
  | Violated v -> Error v.message
