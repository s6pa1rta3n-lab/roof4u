(**
   csv_exporter.mli - RFC 4180 Compliant CSV Lead Exporter with DDE Formula Injection Protection.
   Exports qualified and enriched leads to CSV with exact 10-column schema:
   Address, Zip Code, Property Type, Roof Type, Assessed Value, Owner Name, APN, Roof Age (Years), Phone Number, Status
*)

val headers : string list
(** Standard 10-column headers list:
    ["Address"; "Zip Code"; "Property Type"; "Roof Type"; "Assessed Value";
     "Owner Name"; "APN"; "Roof Age (Years)"; "Phone Number"; "Status"] *)

val header_string : string
(** Comma-separated RFC 4180 header row. *)

val sanitize_csv_field : string -> string
(** Neutralizes CSV / DDE formula injection characters:
    Prepends ['] if the field begins with '=', '+', '-', '@', '\t', or '\r'. *)

val escape_csv_field : string -> string
(** Escapes a single string field according to RFC 4180 rules:
    Wraps in double quotes if it contains commas, quotes, newlines, or carriage returns.
    Doubles any internal quotes (["""] for ["]). *)

val format_csv_cell : string -> string
(** Applies formula injection sanitization followed by RFC 4180 escaping. *)

val row_of_raw_lead : ?status:string -> Types.raw_lead -> string list
(** Converts a [Types.raw_lead] to a 10-element list of formatted CSV cells. *)

val row_of_verified_lead : Types.verified_lead -> string list
(** Converts a [Types.verified_lead] to a 10-element list of formatted CSV cells. *)

val row_of_db_row : Db.lead_row -> string list
(** Converts a [Db.lead_row] to a 10-element list of formatted CSV cells. *)

val export_validated_leads_csv : string -> Types.verified_lead list -> unit
(** [export_validated_leads_csv filepath leads]
    Exports a list of [Types.verified_lead] records meeting qualification criteria
    (score >= 60.0) to [filepath]. *)

val export_from_db :
  ?min_score:float ->
  Db.t ->
  output_file:string ->
  int
(** [export_from_db ?min_score db ~output_file]
    Queries VALIDATED and ENRICHED leads from the SQLite database [db],
    scores each lead to ensure total_score >= [min_score] (default 60.0),
    and exports them to [output_file]. Returns the count of exported rows. *)

val export_to_csv :
  ?min_score:float ->
  ?db_path:string ->
  ?output_file:string ->
  unit ->
  int
(** [export_to_csv ?min_score ?db_path ?output_file ()]
    High-level exporter opening [db_path] (default "leads.db") and writing to
    [output_file] (default "validated_leads.csv"). Returns the count of exported rows. *)
