(**
   vector_store.mli - Embedded Vector Store & Cosine Similarity Search Engine.
   Stores high-dimensional float embeddings with metadata, domain filtering,
   failure_type filtering, and top-k ranking.
*)

type vector_record = {
  id : string;
  domain : string;
  failure_type : string option;
  text : string;
  metadata : (string * Json.t) list;
  embedding : float array;
  created_at : string;
}

type search_result = {
  record : vector_record;
  score : float;
  rank : int;
}

type t

(** Creates a vector store instance (default db_path is ":memory:", dimension is 256). *)
val create : ?db_path:string -> ?dimension:int -> unit -> t

val db_path : t -> string
val dimension : t -> int

(** JSON AST conversions *)
val record_to_json : vector_record -> Json.t
val record_of_json : Json.t -> vector_record

(** Helper to construct a vector_record *)
val make_record :
  ?domain:string ->
  ?failure_type:string ->
  ?metadata:(string * Json.t) list ->
  ?embedding:float array ->
  ?created_at:string ->
  id:string ->
  text:string ->
  unit ->
  vector_record

(** Upserts a single text document, computing its embedding if omitted. *)
val upsert :
  ?domain:string ->
  ?failure_type:string ->
  ?metadata:(string * Json.t) list ->
  ?embedding:float array ->
  ?created_at:string ->
  t ->
  string ->
  string ->
  vector_record

(** Upserts a preconstructed vector_record. *)
val upsert_record : t -> vector_record -> vector_record

(** Batch upserts multiple vector records. Returns number of inserted/updated items. *)
val upsert_batch : t -> vector_record list -> int

(** Retrieves a record by ID. *)
val get : t -> string -> vector_record option

(** Deletes a record by ID. Returns true if removed. *)
val delete : t -> string -> bool

(** Updates metadata dictionary for an existing record. *)
val update_metadata : t -> string -> (string * Json.t) list -> bool

(** Semantic cosine similarity search engine with top-k ranking and filters. *)
val search :
  ?query_embedding:float array ->
  ?top_k:int ->
  ?domain:string ->
  ?failure_type:string ->
  ?min_similarity:float ->
  t ->
  string option ->
  search_result list

(** Counts stored records, optionally filtered by domain. *)
val count : ?domain:string -> t -> int

(** Clears all records from the store. *)
val clear : t -> unit

(** Synchronizes all lessons from a LessonStore into the VectorStore. *)
val sync_lessons : Lesson_store.t -> t -> int
