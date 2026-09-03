(**
   crypto.mli - Pure OCaml RFC 6234 / FIPS 180-4 compliant SHA-256 implementation.
   Zero external dependencies (no C bindings, no OpenSSL, no mock hashes).
*)

type ctx

val init : unit -> ctx
val update_bytes : ctx -> bytes -> int -> int -> unit
val update_string : ctx -> string -> unit
val finalize_bytes : ctx -> bytes
val finalize_hex : ctx -> string

val sha256_bytes : bytes -> bytes
val sha256_string : string -> string
val sha256_digest : string -> string
val sha256_channel : in_channel -> string
val sha256_file : string -> string
