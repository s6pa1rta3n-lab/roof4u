(**
   gis_roofs.mli - Microservice for querying GIS spatial geometries and roof intelligence.
   Data Sources:
     - San Francisco Building Footprints & Green Roof GIS Dataset (DataSF sfnk-6tdn)
     - SF Planning GIS Property Information Map (PIM)
     - Assessor Secured Roll Geographic Point/Polygon Coordinates
*)

open Types

val default_gis_roofs_endpoint : string

val sanitize_address_query : string -> string
(** [sanitize_address_query query] sanitizes address and neighborhood search queries. *)

val build_gis_roofs_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?address:string ->
  ?neighborhood:string ->
  unit ->
  (string, string) result
(** [build_gis_roofs_query_url ?base_url ?limit ?address ?neighborhood ()]
    constructs a SODA SoQL URL to query roof GIS footprint data. *)

val parse_gis_roof_record : Json.t -> (gis_roof_record, string) result
(** [parse_gis_roof_record json] parses a GeoJSON feature or record into a typed [gis_roof_record]. *)

val parse_gis_roofs_response : string -> (gis_roof_record list, string) result
(** [parse_gis_roofs_response body] parses a SODA JSON array into a list of [gis_roof_record]. *)

val fetch_gis_roofs :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?address:string ->
  ?neighborhood:string ->
  unit ->
  (gis_roof_record list, string) result
(** [fetch_gis_roofs ?base_url ?limit ?timeout ?address ?neighborhood ()]
    queries live municipal GIS records for roof geometries and surface areas. *)

val answer_source_description : string
(** [answer_source_description] returns a direct explanation of where roof GIS data is located in public records. *)
