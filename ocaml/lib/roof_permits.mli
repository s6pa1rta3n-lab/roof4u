(**
   roof_permits.mli - Microservice for querying DBI roofing permits and permit histories.
   Data Sources:
     - San Francisco Department of Building Inspection (DBI) Building Permits (DataSF i98e-djp9)
     - SF Planning & DBI PermitSF Dataset (DataSF tyz3-vt28)
     - SF DBI Permit Tracking System (PTS)
*)

open Types

val default_building_permits_endpoint : string

val default_permitsf_endpoint : string


val sanitize_keyword : string -> string
(** [sanitize_keyword kw] sanitizes permit search keywords. *)

val build_roof_permits_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?zip_code:string ->
  ?street_name:string ->
  ?keyword:string ->
  unit ->
  (string, string) result
(** [build_roof_permits_query_url ?base_url ?limit ?zip_code ?street_name ?keyword ()]
    constructs a SODA SoQL query for DBI building permits filtered by roofing work. *)

val parse_roof_permit_record :
  ?current_year:int ->
  Json.t ->
  (roof_permit_record, string) result
(** [parse_roof_permit_record ?current_year json] parses a DBI permit JSON object into a typed [roof_permit_record]. *)

val parse_roof_permits_response :
  ?current_year:int ->
  string ->
  (roof_permit_record list, string) result
(** [parse_roof_permits_response ?current_year body] parses a SODA JSON array into a list of [roof_permit_record]. *)

val fetch_roof_permits :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?current_year:int ->
  ?zip_code:string ->
  ?street_name:string ->
  ?keyword:string ->
  unit ->
  (roof_permit_record list, string) result
(** [fetch_roof_permits ?base_url ?limit ?timeout ?current_year ?zip_code ?street_name ?keyword ()]
    executes an HTTP query to fetch live DBI roofing permits. *)

val answer_source_description : string
(** [answer_source_description] returns a direct explanation of where roofing permits are located in public records. *)
