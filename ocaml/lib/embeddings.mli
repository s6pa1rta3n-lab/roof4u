(**
   embeddings.mli - Deterministic 256-D Offline Feature Hashing Embedder.
   Uses multi-scale signed feature hashing with subword n-grams and domain token boosting.
   100% offline, zero external models, zero cloud APIs, zero mock dependencies.
*)

val default_dimension : int

(** Multi-scale tokenization producing (token_string, importance_weight) pairs. *)
val tokenize : string -> (string * float) list

(** IEEE 802.3 CRC32 checksum for bucket indexing. *)
val crc32 : string -> int

(** MD5 sign hash returning +1.0 or -1.0. *)
val sign_of_token : string -> float

(** Computes L2 norm of a vector. *)
val l2_norm : float array -> float

(** Generates a unit-normalized (L2 norm = 1.0) float array of length [dimension]. *)
val embed_text : ?dimension:int -> string -> float array

(** Generates a batch of unit-normalized embeddings. *)
val embed_batch : ?dimension:int -> string list -> float array list

(** Computes scalar cosine similarity between two embedding vectors. *)
val cosine_similarity : float array -> float array -> float

(** Computes cosine similarity between a query vector and a list of document vectors. *)
val batch_cosine_similarity : float array -> float array list -> float list
