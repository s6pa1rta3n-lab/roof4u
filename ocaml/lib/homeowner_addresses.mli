(**
   homeowner_addresses.mli - Microservice for discovering homeowner addresses in a neighborhood.
   Data Sources:
     - San Francisco Assessor-Recorder Secured Property Roll (DataSF wv5m-vpq2)
     - City and County of San Francisco Enterprise Addressing System (EAS)
*)

open Types

val default_addresses_endpoint : string

val sanitize_neighborhood : string -> string
(** [sanitize_neighborhood name] removes invalid characters from neighborhood name inputs. *)

val build_addresses_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?zip_code:string ->
  ?residential_only:bool ->
  neighborhood:string ->
  unit ->
  (string, string) result
(** [build_addresses_query_url ?base_url ?limit ?zip_code ?residential_only ~neighborhood ()]
    constructs a valid SODA SoQL URL to query homeowner addresses in the specified neighborhood. *)

val parse_homeowner_address_record : Json.t -> (homeowner_address_record, string) result
(** [parse_homeowner_address_record json] parses an Assessor Roll JSON object into a typed [homeowner_address_record]. *)

val parse_homeowner_addresses_response : string -> (homeowner_address_record list, string) result
(** [parse_homeowner_addresses_response body] parses a SODA JSON array response into a list of [homeowner_address_record]. *)

val fetch_homeowner_addresses :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?zip_code:string ->
  ?residential_only:bool ->
  neighborhood:string ->
  unit ->
  (homeowner_address_record list, string) result
(** [fetch_homeowner_addresses ?base_url ?limit ?timeout ?zip_code ?residential_only ~neighborhood ()]
    queries live municipal records to acquire homeowner addresses in a target neighborhood. *)

val answer_source_description : string
(** [answer_source_description] returns a direct explanation of where homeowner addresses are located in public records. *)
