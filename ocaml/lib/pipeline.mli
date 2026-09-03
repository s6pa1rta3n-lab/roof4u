(**
   pipeline.mli - Autonomous Real Estate Lead Acquisition & Verification Pipeline.
   Orchestrates discovery via DataSF SODA connectors and municipal scrapers,
   enrichment, mathematical invariant qualification (INV1-4), SQLite persistence,
   closed-loop learning / telemetry, and RFC 4180 CSV export.
*)

type config = {
  target_zips : string list;
  limit_per_zip : int;
  db_path : string;
  csv_path : string;
  lessons_path : string;
  vector_db_path : string;
  enable_learning : bool;
  enable_telemetry : bool;
  min_score : float;
  current_year : int;
}

val default_config : config

val target_neighborhoods : string list ref
val max_leads_limit : int option ref

type pipeline_summary = {
  candidates_discovered : int;
  leads_enriched : int;
  leads_qualified : int;
  leads_disqualified : int;
  leads_exported : int;
  lessons_count : int;
  vectors_count : int;
}

val run_pipeline :
  ?config:config ->
  ?target_neighborhoods:string list ->
  ?max_leads:int ->
  unit ->
  pipeline_summary
(** [run_pipeline ?config ?target_neighborhoods ?max_leads ()] executes the end-to-end Roo4u autonomous pipeline:
    1. Phase 1: GIS Discovery (gods-eye-view polygons, spatial ray-casting, roof morphology).
    2. Phase 2: Contact Enrichment (BatchSkipTracing API -> OSINT scraper -> fallback).
    3. Phase 3: Public Records & Tax Validation (Assessor roll, DBI permits, HOA & rental filters).
    4. Phase 4: Invariant Qualification & Actionability Scoring (INV-1..4 & 0..100 score).
    5. Phase 5: SQLite Persistence & RFC 4180 CSV Export. *)

val default_seed_leads_for_zip : string -> Types.raw_lead list
(** [default_seed_leads_for_zip zip] returns authentic municipal seed leads for the specified postal code. *)

val verify_single_lead_json : ?current_year:int -> string -> (Types.verified_lead, string) result
(** [verify_single_lead_json ?current_year json_str]
    Parses a single JSON lead string, executes mathematical verification,
    and returns the verified lead with cryptographic SHA-256 proof. *)
