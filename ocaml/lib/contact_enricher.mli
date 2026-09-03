(**
   contact_enricher.mli - Multi-tier phone number extraction, validation,
   and fallback orchestration engine.
*)

type enrichment_source =
  | SkipTracingApi
  | OsintScraper
  | MunicipalDirectory
  | NoneSource

type enrichment_result = {
  phone : string option;
  source : enrichment_source;
}

val enrich_lead_custom :
  ?skip_tracing_fn:(Types.raw_lead -> (Types.raw_lead, string) result) ->
  ?osint_fn:(Types.raw_lead -> (Types.raw_lead, string) result) ->
  ?seed_directory_fn:(Types.raw_lead -> string option) ->
  Types.raw_lead ->
  Types.raw_lead * string

val enrich_lead_with_status : Types.raw_lead -> Types.raw_lead * string

val enrich_lead : Types.raw_lead -> Types.raw_lead

val enrich_phone : Types.raw_lead -> Types.raw_lead
