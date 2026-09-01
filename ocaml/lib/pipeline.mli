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

type pipeline_summary = {
  candidates_discovered : int;
  leads_enriched : int;
  leads_qualified : int;
  leads_disqualified : int;
  leads_exported : int;
  lessons_count : int;
  vectors_count : int;
}

val run_pipeline : ?config:config -> unit -> pipeline_summary
(** [run_pipeline ?config ()] executes the end-to-end Roo4u autonomous pipeline:
    1. Phase 1: Discovers candidate leads for target SF zip codes.
    2. Phase 2: Enriches candidate properties with municipal details.
    3. Phase 3: Executes invariant qualification (INV1-INV4) and actionability scoring.
    4. Phase 4: Persists status transitions to SQLite database.
    5. Phase 5: Updates lesson store & vector store and exports qualified leads to CSV. *)

val verify_single_lead_json : ?current_year:int -> string -> (Types.verified_lead, string) result
(** [verify_single_lead_json ?current_year json_str]
    Parses a single JSON lead string, executes mathematical verification,
    and returns the verified lead with cryptographic SHA-256 proof. *)
