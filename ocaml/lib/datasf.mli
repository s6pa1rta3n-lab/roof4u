(**
   datasf.mli - Connectors and Query Builders for San Francisco DataSF SODA APIs.
   Datasets:
     - Building Permits: i98e-djp9.json
     - PermitSF: tyz3-vt28.json
   Features:
     - Parameter-validated SoQL query builder enforcing strict regex whitelisting
       on zip codes (^[0-9]{5}$) and alphanumeric keyword sanitization (anti-SoQL injection).
     - JSON response deserialization into structured candidate lead and permit records.
*)

val default_building_permits_base : string
val default_permitsf_base : string

val is_valid_sf_zip : string -> bool
(** [is_valid_sf_zip z] checks if [z] strictly matches 5 digits ^[0-9]{5}$. *)

val sanitize_soql_string : string -> string
(** [sanitize_soql_string s] sanitizes user input by escaping single quotes and removing
    dangerous SQL/SoQL punctuation characters. *)

val sanitize_keyword : string -> string
(** [sanitize_keyword k] sanitizes search keyword, allowing only alphanumeric chars, spaces, and hyphens. *)

val build_building_permits_url :
  ?base_url:string ->
  ?limit:int ->
  ?keyword:string ->
  string ->
  (string, string) result
(** [build_building_permits_url ?base_url ?limit ?keyword zip_code]
    Constructs a validated DataSF SODA query URL for dataset i98e-djp9.
    Returns [Error] if [zip_code] fails 5-digit validation. *)

val build_permitsf_url :
  ?base_url:string ->
  ?limit:int ->
  string list ->
  (string, string) result
(** [build_permitsf_url ?base_url ?limit zip_codes]
    Constructs a validated DataSF SODA query URL for dataset tyz3-vt28.
    Returns [Error] if [zip_codes] is empty or any zip code is invalid. *)

val parse_building_permit_record :
  Json.t ->
  (Types.permit_record * string * string * string * float option, string) result
(** Parses a single building permit JSON object into [(permit_record, address, zip_code, apn, cost_opt)]. *)

val synthesize_candidate_leads :
  ?current_year:int ->
  building_permits:Json.t ->
  recent_permits:Json.t ->
  unit ->
  Types.raw_lead list
(** [synthesize_candidate_leads ?current_year ~building_permits ~recent_permits ()]
    Synthesizes raw DataSF permit arrays into deduplicated candidate raw_lead records. *)

val synthesize_leads_from_json :
  ?current_year:int ->
  building_permits_json:string ->
  recent_permits_json:string ->
  unit ->
  (Types.raw_lead list, string) result
(** High-level helper parsing JSON strings and returning synthesized raw_leads. *)
