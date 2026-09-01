(**
   db.mli - Native SQLite Lead Persistence & State Machine Layer.
   Manages the 'leads' table in leads.db for DISCOVERED, ENRICHED, VALIDATED,
   and DISCARDED states.
*)

type lead_status =
  | Discovered
  | Enriched
  | Validated
  | Discarded
  | Disqualified
  | Custom of string

val string_of_status : lead_status -> string
val status_of_string : string -> lead_status

type lead_row = {
  id : int;
  address : string;
  zip_code : string;
  property_type : string option;
  roof_type : string option;
  estimated_value : float option;
  owner_name : string option;
  is_hoa : bool;
  is_rental : bool;
  apn : string option;
  last_roof_permit_date : string option;
  roof_age_years : float option;
  phone_number : string option;
  created_at : string;
  status : string;
}

type t

(** Creates a database handle for a SQLite database path (default "leads.db"). *)
val create : ?db_path:string -> unit -> t

val db_path : t -> string

(** Initializes the SQLite leads table and indexes. *)
val init_db : t -> unit

(** JSON AST conversions *)
val row_to_json : lead_row -> Json.t
val row_of_json : Json.t -> lead_row

(** Converts a lead_row to Types.raw_lead *)
val raw_lead_of_row : lead_row -> Types.raw_lead

(** Converts a Types.raw_lead to a new lead_row *)
val row_of_raw_lead : ?id:int -> ?status:lead_status -> Types.raw_lead -> lead_row

(** Inserts a new lead into the database. Returns (Ok id) or (Error msg). *)
val insert_lead : t -> ?status:lead_status -> Types.raw_lead -> (int, string) result

(** Inserts or updates an existing lead by unique address. Returns (Ok id) or (Error msg). *)
val upsert_lead : t -> ?status:lead_status -> Types.raw_lead -> (int, string) result

(** Updates the status of a lead by address. *)
val update_status : t -> string -> lead_status -> (unit, string) result

(** Updates enriched fields for a lead by address. *)
val update_enriched :
  t ->
  string -> (* address *)
  ?apn:string ->
  ?owner_name:string ->
  ?estimated_value:float ->
  ?last_roof_permit_date:string ->
  ?roof_age_years:float ->
  ?is_hoa:bool ->
  ?is_rental:bool ->
  ?property_type:string ->
  ?roof_type:string ->
  ?phone_number:string ->
  unit ->
  (unit, string) result

(** Retrieves a lead record by address. *)
val get_lead_by_address : t -> string -> lead_row option

(** Retrieves a lead record by ID. *)
val get_lead_by_id : t -> int -> lead_row option

(** Lists leads matching optional status and zip code filters. *)
val list_leads :
  ?status:lead_status ->
  ?zip_code:string ->
  ?limit:int ->
  t ->
  lead_row list

(** Counts leads matching an optional status filter. *)
val count_leads : ?status:lead_status -> t -> int

(** Deletes a lead by address. *)
val delete_lead_by_address : t -> string -> bool

(** Deletes a lead by ID. *)
val delete_lead_by_id : t -> int -> bool

(** Clears all leads from the table. *)
val clear : t -> unit
