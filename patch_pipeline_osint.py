import re

with open('ocaml/lib/pipeline.ml', 'r') as f:
    content = f.read()

replacement = """  (* PHASE 2: ENRICHMENT & PROPERTY DETAILS *)
  Printf.printf "\\n--- PHASE 2: ENRICHMENT & PROPERTY DETAILS ---\\n";
  let discovered_rows = Db.list_leads ~status:Db.Discovered db in
  let enriched_count = ref 0 in
  List.iter (fun row ->
    let raw = Db.raw_lead_of_row row in
    (* Append real phone number using zero-cost OSINT scraper module *)
    let raw = match Osint_scraper.extract_phone_number raw with
      | Ok raw_with_phone -> raw_with_phone
      | Error msg -> 
          Printf.eprintf "[!] OSINT scraping failed for %s: %s\\n" raw.address msg;
          raw
    in
    (* Transition status to ENRICHED and persist appended phone number *)
    (match Db.update_enriched db raw.address ?phone_number:raw.phone_number () with
    | Ok () -> incr enriched_count
    | Error e -> Printf.eprintf "[!] Error transitioning %s to ENRICHED: %s\\n" raw.address e)
  ) discovered_rows;"""

content = re.sub(
    r"\(\* PHASE 2: ENRICHMENT & PROPERTY DETAILS \*\).*?\) discovered_rows;",
    replacement,
    content,
    flags=re.DOTALL
)

with open('ocaml/lib/pipeline.ml', 'w') as f:
    f.write(content)
