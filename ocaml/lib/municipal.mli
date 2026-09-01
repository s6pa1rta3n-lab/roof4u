(**
   municipal.mli - Scrapers and Table Extractors for SF Planning PIM and SF DBI Permit Tracking.
   Features:
     - Comprehensive multi-format date parser and normalizer (ISO 8601, US MM/DD/YYYY, YYYY-MM-DD, 4-digit years).
     - Roofing permit classification heuristics (reroof, tear-off, roof replace vs non-roof alterations).
     - DOM/HTML text cleaner and table extractor for municipal portal responses.
*)

val normalize_date : string -> string option
(** [normalize_date raw_str] normalizes dates into ISO "YYYY-MM-DD" format.
    Supports ISO timestamps, MM/DD/YYYY, MM/DD/YY, YYYY-MM-DD, Month DD YYYY, DD-Mon-YYYY, and 4-digit years.
    Returns [None] for empty, null, or invalid date strings (e.g. "N/A", "Unknown", "pending"). *)

val parse_date_year : string -> int option
(** [parse_date_year raw_str] extracts the 4-digit year from a normalized or raw date string. *)

val is_roof_replacement : string -> bool
(** [is_roof_replacement description] evaluates whether a permit description refers
    to a full roof replacement (reroof, tear-off, shingle replacement, new roof, tar and gravel). *)

val is_non_roof_alteration : string -> bool
(** [is_non_roof_alteration description] evaluates if a permit is exclusively non-roof work
    (e.g., solar electrical, kitchen/bathroom remodel, seismic, windows). *)

val clean_dom_text : ?extra_selectors:string list -> ?max_chars:int -> string -> string
(** [clean_dom_text ?extra_selectors ?max_chars html]
    Strips scripts, styles, and tags, extracting text from tables, property summaries,
    and permit grids, collapsed and truncated to [max_chars] (default 12000). *)

val extract_pim_details : string -> (string * string option * float option * bool option * bool option)
(** [extract_pim_details text_or_html]
    Extracts [(address, apn_opt, assessed_value_opt, is_hoa_opt, is_rental_opt)]
    from SF Planning Information Map text. *)

val extract_dbi_permits : string -> Types.permit_record list
(** [extract_dbi_permits text_or_html]
    Extracts structured permit records from SF DBI Permit Tracking table text. *)
