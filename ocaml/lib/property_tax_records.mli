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

val is_condo_lot_series : string -> bool
(** [is_condo_lot_series parcel_or_lot] returns true if the parcel lot portion
    falls in the San Francisco condominium unit series 0500 to 0999. *)

val is_hoa_property :
  ?property_class_code:string ->
  ?property_class_def:string ->
  ?use_code:string ->
  ?use_def:string ->
  ?parcel_number:string ->
  ?property_type:Types.property_type ->
  ?owner_name:string ->
  ?address:string ->
  unit ->
  bool
(** [is_hoa_property ?property_class_code ?property_class_def ?use_code ?use_def ?parcel_number ?property_type ?owner_name ?address ()]
    evaluates condominium class codes ('D', 'Z'), condo lot numbering (0500-0999),
    use codes ('CONDO', 'COOP', 'TIC'), definition descriptions, master deed tokens,
    and unit identifiers. *)

val is_rental_property :
  ?situs_address:string ->
  ?tax_mailing_address:string ->
  ?has_homeowner_exemption:bool ->
  ?exemption_value:float ->
  ?owner_name:string ->
  ?ownership_type:Types.ownership_type ->
  ?units_count:int ->
  ?property_type:Types.property_type ->
  unit ->
  bool
(** [is_rental_property ?situs_address ?tax_mailing_address ?has_homeowner_exemption ?exemption_value ?owner_name ?ownership_type ?units_count ?property_type ()]
    evaluates tax mailing address mismatches, absence of California Prop 13 $7,000 homeowner exemption,
    corporate/LLC ownership entities, and commercial multi-unit densities (>4 units). *)

