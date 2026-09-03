(**
   gis_roofs.mli - Microservice for querying GIS spatial geometries,
   San Francisco Analysis Neighborhood boundaries, and roof intelligence.
   Integrates gods-eye-view offline GeoJSON boundaries, ray-casting point-in-polygon
   containment, affluent corridor targeting, and roof morphology classification.
*)

open Types

(** Candidate roof record discovered via gods_eye_view GIS footprint and municipal layer. *)
type candidate_roof = {
  address : string;
  zip_code : string;
  neighborhood : string;
  roof_type : Types.roof_type;
  property_type : Types.property_type;
  footprint_sqft : float;
  latitude : float option;
  longitude : float option;
  estimated_value : float option;
}

(** 2D coordinate point representation (longitude, latitude). *)
type point = float * float

(** Linear ring representation consisting of an ordered list of points. *)
type ring = point list

(** Polygon representation consisting of an exterior ring followed by optional interior hole rings. *)
type polygon = ring list

(** MultiPolygon representation consisting of a list of polygons. *)
type multi_polygon = polygon list

(** Bounding box and polygonal geometry representation of an administrative neighborhood. *)
type neighborhood_boundary = {
  name : string;
  polygons : polygon list;
  bbox : float * float * float * float;
}

(** Wealth and affluence tier of a San Francisco municipal neighborhood. *)
type affluence_tier =
  | Tier1_UltraAffluent
  | Tier2_Affluent
  | Tier3_Moderate

(** Morphological and architectural inputs for structural roof classification. *)
type morphology_inputs = {
  pitch_deg : float option;
  height_delta_ft : float option;
  year_built : int option;
  style_tag : string option;
  material_desc : string option;
  polygon_points : int;
  osm_shape : string option;
}

val default_gis_roofs_endpoint : string
(** Default DataSF SODA endpoint for building footprints and green roofs. *)

val default_sf_neighborhoods_geojson_path : string
(** Canonical filesystem path to bundled san-francisco.json Analysis Neighborhood dataset. *)

val candidate_geojson_paths : string list
(** Search paths inspected when loading the San Francisco GeoJSON boundary file. *)

val target_affluent_neighborhoods : string list
(** The 5 primary affluent target corridors for high-ticket roofing lead generation. *)

val is_affluent_neighborhood : string -> bool
(** [is_affluent_neighborhood name] determines if the named neighborhood falls in the target wealth corridors. *)

val affluence_tier_of_neighborhood : string -> affluence_tier
(** [affluence_tier_of_neighborhood name] categorizes a neighborhood into its affluence tier. *)

val to_lon_lat : float -> float -> float * float
(** [to_lon_lat a b] normalizes coordinate arguments into (longitude, latitude). *)

val to_lat_lon : float -> float -> float * float
(** [to_lat_lon a b] normalizes coordinate arguments into (latitude, longitude). *)

val normalize_neighborhood_name : string -> string
(** [normalize_neighborhood_name name] converts a neighborhood name into lowercase alphanumeric tokens. *)

val canonicalize_neighborhood_alias : string -> string
(** [canonicalize_neighborhood_alias norm] resolves common neighborhood aliases to canonical DataSF names. *)

val compute_bbox : polygon list -> float * float * float * float
(** [compute_bbox polys] computes the axis-aligned bounding box (min_lon, min_lat, max_lon, max_lat). *)

val parse_neighborhood_geojson : string -> (neighborhood_boundary list, string) result
(** [parse_neighborhood_geojson raw_json] parses a GeoJSON FeatureCollection string into typed boundaries. *)

val load_sf_neighborhoods : ?path:string -> unit -> (neighborhood_boundary list, string) result
(** [load_sf_neighborhoods ?path ()] loads and parses neighborhood boundaries from disk. *)

val get_sf_neighborhoods : unit -> neighborhood_boundary list
(** [get_sf_neighborhoods ()] returns memoized neighborhood boundaries, loading on initial invocation. *)

val point_in_ring : float -> float -> ring -> bool
(** [point_in_ring a b ring] evaluates whether point (lon, lat) or (lat, lon) falls inside the ring. *)

val point_in_polygon : float -> float -> polygon -> bool
(** [point_in_polygon a b poly] evaluates whether point falls inside outer ring and outside all holes. *)

val point_in_neighborhood_boundary : float -> float -> neighborhood_boundary -> bool
(** [point_in_neighborhood_boundary a b boundary] evaluates point containment using AABB pre-filtering and ray-casting. *)

val point_in_neighborhood : float -> float -> string -> bool
(** [point_in_neighborhood a b name] evaluates if coordinates fall within the named neighborhood. *)

val find_neighborhood : float -> float -> string option
(** [find_neighborhood a b] returns the name of the SF Analysis Neighborhood containing the coordinates. *)

val is_point_in_affluent_corridor : float -> float -> bool
(** [is_point_in_affluent_corridor a b] returns true if coordinates fall within any target affluent corridor. *)

val classify_roof_morphology : morphology_inputs -> Types.roof_type
(** [classify_roof_morphology inputs] classifies structural attributes into a typed roof morphology. *)

val candidate_properties_catalog : candidate_roof list
(** Seed catalog of verified physical candidate properties in target affluent corridors. *)

val fetch_gods_eye_candidates :
  ?neighborhood:string ->
  ?zip:string ->
  unit ->
  candidate_roof list
(** [fetch_gods_eye_candidates ?neighborhood ?zip ()] returns candidate roofs matching neighborhood or zip. *)

val candidate_to_raw_lead : candidate_roof -> Types.raw_lead
(** [candidate_to_raw_lead candidate] converts a candidate roof into a pipeline raw lead record. *)

val candidate_to_gis_record : candidate_roof -> Types.gis_roof_record
(** [candidate_to_gis_record candidate] converts a candidate roof into a GIS footprint record. *)

val candidate_roof_to_json : candidate_roof -> Json.t
(** [candidate_roof_to_json candidate] serializes a candidate roof into a JSON AST. *)

val sanitize_address_query : string -> string
(** [sanitize_address_query query] sanitizes address and neighborhood search queries. *)

val build_gis_roofs_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?address:string ->
  ?neighborhood:string ->
  unit ->
  (string, string) result
(** [build_gis_roofs_query_url ?base_url ?limit ?address ?neighborhood ()] constructs a SODA SoQL URL. *)

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
(** [fetch_gis_roofs ?base_url ?limit ?timeout ?address ?neighborhood ()] queries live municipal GIS records. *)

val answer_source_description : string
(** [answer_source_description] returns an explanation of public records data sources. *)
