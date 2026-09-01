(**
   json.mli - Pure OCaml RFC 8259 Recursive-Descent JSON AST Parser & Serializer.
   Zero external dependencies. Full Unicode escape and surrogate pair support.
*)

type t =
  | Null
  | Bool of bool
  | Number of float
  | String of string
  | Array of t list
  | Object of (string * t) list

(** Parse a JSON string into an AST. Returns Error with line/col on syntax error. *)
val parse : ?max_depth:int -> string -> (t, string) result

(** Parse a JSON string, raising Failure on error. *)
val parse_exn : ?max_depth:int -> string -> t

(** Serialize a JSON AST into a compact RFC 8259 string. *)
val to_string : t -> string

(** Serialize a JSON AST into an indented pretty-printed string. *)
val to_string_pretty : ?indent:int -> t -> string

(** Serialize a JSON AST into a Buffer. *)
val to_buffer : Buffer.t -> t -> unit

(** Serialize a JSON AST into an out_channel. *)
val to_channel : out_channel -> t -> unit

(** {1 Safe Typed Field Accessors} *)

val get_field : string -> t -> t option
val get_string : string -> t -> string option
val get_float : string -> t -> float option
val get_int : string -> t -> int option
val get_bool : string -> t -> bool option
val get_array : string -> t -> t list option
val get_object : string -> t -> (string * t) list option

(** {1 Direct Value Unwrappers} *)

val as_string : t -> string option
val as_float : t -> float option
val as_int : t -> int option
val as_bool : t -> bool option
val as_array : t -> t list option
val as_object : t -> (string * t) list option

(** {1 Combinators & Navigation} *)

val member : string -> t -> t
val index : int -> t -> t option
val path : string list -> t -> t option

(** {1 AST Constructors} *)

val null : t
val bool : bool -> t
val string : string -> t
val float : float -> t
val int : int -> t
val array : t list -> t
val obj : (string * t) list -> t
