(**
   osint_scraper.mli - Zero-cost open-source intelligence (OSINT) skip tracing module.
   Attempts to find homeowner phone numbers by scraping public search engines.
*)

val url_encode : string -> string

val build_search_url : Types.raw_lead -> string

val extract_phones_from_html : string -> string list

val extract_phone_number : ?search_url:string -> Types.raw_lead -> (Types.raw_lead, string) result
