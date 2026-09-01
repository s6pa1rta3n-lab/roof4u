(**
   lesson_store.mli - POSIX Atomic JSON Lesson Store with Advisory Locking.
   Provides persistent memory for scraping failures, workarounds, and self-healing
   resolutions with Unix.lockf advisory locking and corruption recovery.
*)

type lesson_status =
  | Active
  | Resolved
  | Probation
  | Deprecated

val string_of_status : lesson_status -> string
val status_of_string : string -> lesson_status

type lesson = {
  id : string;
  domain : string;
  url : string;
  source_url : string option;
  failure_type : string;
  error_category : string option;
  error_message : string;
  lesson_learned : string;
  recommended_action : string;
  root_cause_analysis : string option;
  strategy_attempted : string option;
  recommended_workaround : string option;
  suggested_selectors : string list;
  suggested_delay_seconds : float;
  suggested_headers : (string * string) list;
  code_patch_suggestion : string option;
  github_issue_number : int option;
  github_issue_url : string option;
  timestamp : string;
  dom_snippet : string option;
  resolved : bool;
  status : string; (* ACTIVE | RESOLVED | PROBATION | DEPRECATED *)
  occurrence_count : int;
  success_count_after_workaround : int;
  target_entity : string option;
  phase : string option;
  tags : string list;
}

type t

(** Create a lesson store handle for a given file path (default "lessons_learned.json"). *)
val create : ?file_path:string -> unit -> t

(** Returns the target file path of the store. *)
val file_path : t -> string

(** JSON AST conversions *)
val lesson_to_json : lesson -> Json.t
val lesson_of_json : Json.t -> lesson

(** Creates a new lesson record with sensible defaults. *)
val make_lesson :
  ?id:string ->
  ?url:string ->
  ?source_url:string ->
  ?failure_type:string ->
  ?error_category:string ->
  ?error_message:string ->
  ?lesson_learned:string ->
  ?recommended_action:string ->
  ?root_cause_analysis:string ->
  ?strategy_attempted:string ->
  ?recommended_workaround:string ->
  ?suggested_selectors:string list ->
  ?suggested_delay_seconds:float ->
  ?suggested_headers:(string * string) list ->
  ?code_patch_suggestion:string ->
  ?github_issue_number:int ->
  ?github_issue_url:string ->
  ?timestamp:string ->
  ?dom_snippet:string ->
  ?resolved:bool ->
  ?status:string ->
  ?occurrence_count:int ->
  ?success_count_after_workaround:int ->
  ?target_entity:string ->
  ?phase:string ->
  ?tags:string list ->
  domain:string ->
  unit ->
  lesson

(** Loads all lessons from the JSON ledger with automatic corruption recovery. *)
val load_lessons : t -> lesson list

(** Atomically writes the entire lesson list using tmp file, fsync, and rename under lockf. *)
val save_lessons_atomic : t -> lesson list -> unit

(** Adds or updates a lesson atomically. *)
val upsert_lesson : t -> lesson -> lesson

(** Alias for upsert_lesson. *)
val add_lesson : t -> lesson -> lesson

(** Retrieves a lesson by ID. *)
val get_lesson : t -> string -> lesson option

(** Lists lessons matching optional domain and failure_type filters. *)
val list_lessons :
  ?domain:string ->
  ?failure_type:string ->
  ?limit:int ->
  t ->
  lesson list

(** Retrieves all lessons for a specific domain. *)
val filter_by_domain : string -> t -> lesson list

(** Updates fields of an existing lesson atomically. *)
val update_lesson : t -> string -> (lesson -> lesson) -> lesson option

(** Increments success count and triggers self-healing transition to RESOLVED at >= 5 successes. *)
val increment_success : t -> string -> lesson option

(** Deletes a lesson by ID atomically. *)
val delete_lesson : t -> string -> bool

(** Returns total count of stored lessons. *)
val count : ?domain:string -> t -> int

(** Clears the store atomically to an empty list. *)
val clear : t -> unit

(** {1 Direct path-based helper functions} *)

val load_lessons_from_file : string -> lesson list
val save_lessons_to_file_atomic : string -> lesson list -> unit
val upsert_lesson_to_file : string -> lesson -> lesson
val increment_success_in_file : string -> string -> bool
