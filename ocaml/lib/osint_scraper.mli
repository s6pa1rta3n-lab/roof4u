(**
   osint_scraper.mli - Zero-cost open-source intelligence (OSINT) skip tracing module.
   Attempts to find homeowner phone numbers by scraping public search engines.
*)

(** 
   Performs a web search using the homeowner's name and address.
   Extracts potential phone numbers from the search results using regex.
   Returns the most likely phone number, or None if no match is found.
*)
val extract_phone_number : Types.raw_lead -> (Types.raw_lead, string) result
