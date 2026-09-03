open Types

type enrichment_source =
  | SkipTracingApi
  | OsintScraper
  | MunicipalDirectory
  | NoneSource

type enrichment_result = {
  phone : string option;
  source : enrichment_source;
}

let default_seed_directory (lead : raw_lead) : string option =
  match lead.phone_number with
  | Some p ->
      (match Phone_validator.sanitize_and_normalize p with
       | Ok vp -> Some vp.canonical
       | Error _ -> None)
  | None -> None

let default_skip_tracing_fn (lead : raw_lead) : (raw_lead, string) result =
  Skip_tracer.append_phone_number lead

let default_osint_fn (lead : raw_lead) : (raw_lead, string) result =
  Osint_scraper.extract_phone_number lead

let enrich_lead_custom
    ?(skip_tracing_fn = default_skip_tracing_fn)
    ?(osint_fn = default_osint_fn)
    ?(seed_directory_fn = default_seed_directory)
    (lead : raw_lead) : raw_lead * string =
  let tier1_outcome =
    try
      match skip_tracing_fn lead with
      | Ok res ->
          (match res.phone_number with
           | Some p ->
               (match Phone_validator.sanitize_and_normalize p with
                | Ok vp -> Some vp.canonical
                | Error _ -> None)
           | None -> None)
      | Error _ -> None
    with _ -> None
  in
  match tier1_outcome with
  | Some phone ->
      ({ lead with phone_number = Some phone }, "TIER1_SKIP_TRACER")
  | None ->
      let tier2_outcome =
        try
          match osint_fn lead with
          | Ok res ->
              (match res.phone_number with
               | Some p ->
                   (match Phone_validator.sanitize_and_normalize p with
                    | Ok vp -> Some vp.canonical
                    | Error _ -> None)
               | None -> None)
          | Error _ -> None
        with _ -> None
      in
      match tier2_outcome with
      | Some phone ->
          ({ lead with phone_number = Some phone }, "TIER2_OSINT_SCRAPER")
      | None ->
          let tier3_outcome =
            try
              match seed_directory_fn lead with
              | Some p ->
                  (match Phone_validator.sanitize_and_normalize p with
                   | Ok vp -> Some vp.canonical
                   | Error _ -> None)
              | None -> None
            with _ -> None
          in
          match tier3_outcome with
          | Some phone ->
              ({ lead with phone_number = Some phone }, "TIER3_MUNICIPAL_DIRECTORY")
          | None ->
              ({ lead with phone_number = None }, "NONE")

let enrich_lead_with_status (lead : raw_lead) : raw_lead * string =
  enrich_lead_custom lead

let enrich_lead (lead : raw_lead) : raw_lead =
  let (enriched, _) = enrich_lead_with_status lead in
  enriched

let enrich_phone (lead : raw_lead) : raw_lead =
  enrich_lead lead
