(**
   homeowner_names.mli - Microservice for discovering homeowner names from public records.
   Data Sources:
     - San Francisco Office of the Assessor-Recorder Secured Property Roll (DataSF wv5m-vpq2)
     - County Clerk-Recorder Grantor/Grantee Deeds Registry
*)

open Types

val default_assessor_secured_roll_endpoint : string

val sanitize_param : string -> string
(** [sanitize_param str] sanitizes query parameters against SoQL injection. *)

val build_homeowner_names_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?neighborhood:string ->
  ?street_address:string ->
  ?parcel_number:string ->
  unit ->
  (string, string) result
(** [build_homeowner_names_query_url ?base_url ?limit ?neighborhood ?street_address ?parcel_number ()]
    constructs a valid SODA SoQL URL to query the Assessor Secured Property Roll for homeowner names. *)

val parse_homeowner_name_record : Json.t -> (homeowner_name_record, string) result
(** [parse_homeowner_name_record json] parses a single Assessor Roll record into a typed [homeowner_name_record]. *)

val parse_homeowner_names_response : string -> (homeowner_name_record list, string) result
(** [parse_homeowner_names_response body] parses a SODA JSON response string into a list of [homeowner_name_record]. *)

val fetch_homeowner_names :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?neighborhood:string ->
  ?street_address:string ->
  ?parcel_number:string ->
  unit ->
  (homeowner_name_record list, string) result
(** [fetch_homeowner_names ?base_url ?limit ?timeout ?neighborhood ?street_address ?parcel_number ()]
    executes an HTTP query to fetch live homeowner records from the Assessor Secured Property Roll. *)

val answer_source_description : string
(** [answer_source_description] returns a direct explanation of where homeowner names are located in public records. *)
