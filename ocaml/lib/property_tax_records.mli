(**
   property_tax_records.mli - Microservice for querying County Property and Tax records.
   Data Sources:
     - San Francisco Office of the Assessor-Recorder Secured Property Tax Roll (DataSF wv5m-vpq2)
     - SF Treasurer & Tax Collector Property Tax Records
*)

open Types

val default_tax_records_endpoint : string

val sanitize_param : string -> string
(** [sanitize_param str] sanitizes query parameters against SoQL injection. *)

val build_tax_records_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?neighborhood:string ->
  ?address:string ->
  ?parcel_number:string ->
  unit ->
  (string, string) result
(** [build_tax_records_query_url ?base_url ?limit ?neighborhood ?address ?parcel_number ()]
    constructs a SODA SoQL URL to query County Property and Tax Roll records. *)

val parse_property_tax_record : Json.t -> (property_tax_record, string) result
(** [parse_property_tax_record json] parses an Assessor Tax Roll JSON record into a typed [property_tax_record]. *)

val parse_property_tax_records_response : string -> (property_tax_record list, string) result
(** [parse_property_tax_records_response body] parses a SODA JSON array into a list of [property_tax_record]. *)

val fetch_property_tax_records :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?neighborhood:string ->
  ?address:string ->
  ?parcel_number:string ->
  unit ->
  (property_tax_record list, string) result
(** [fetch_property_tax_records ?base_url ?limit ?timeout ?neighborhood ?address ?parcel_number ()]
    queries live municipal records to fetch assessed land values, improvement values, and tax details. *)

val answer_source_description : string
(** [answer_source_description] returns a direct explanation of where County Property & Tax records are located. *)
