(**
   types.ml - Formal algebraic data types for Roo4u lead generation verification.
   Statically typed representation of property metadata, permits, and verification proofs.
*)

type roof_type =
  | Victorian
  | Flat
  | Mansard
  | Gable
  | Hip
  | Metal
  | Other of string

type property_type =
  | SingleFamily
  | MultiUnit2To4
  | MultiUnit5Plus
  | Commercial
  | MixedUse
  | UnknownPropertyType of string

type permit_record = {
  permit_number : string;
  date_filed : string option;
  date_issued : string option;
  description : string;
  is_roof_replacement : bool;
  cost : float option;
}

type raw_lead = {
  address : string;
  zip_code : string;
  property_type_str : string;
  roof_type_str : string;
  estimated_value : float option;
  apn : string option;
  owner_name : string option;
  is_hoa : bool;
  is_rental : bool;
  year_built : int option;
  roof_age_years : float option;
  last_roof_permit_date : string option;
  permits : permit_record list;
}

type invariant_result =
  | Satisfied of string
  | Violated of { invariant_name : string; message : string }

type scoring_components = {
  roof_age_component : float;       (** 0.0 to 40.0 *)
  property_value_component : float; (** 0.0 to 35.0 *)
  roof_type_component : float;      (** 0.0 to 25.0 *)
  total_actionability_score : float; (** 0.0 to 100.0 *)
}

type qualification_verdict =
  | Qualified of {
      score : scoring_components;
      invariants_passed : string list;
      proof_id : string;
    }
  | Disqualified of {
      failed_invariants : (string * string) list;
      partial_score : float;
    }

type verified_lead = {
  lead : raw_lead;
  roof_type : roof_type;
  property_type : property_type;
  verdict : qualification_verdict;
  verification_timestamp : string;
  sha256_proof : string;
}
