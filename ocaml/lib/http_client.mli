(**
   http_client.mli - Pure OCaml HTTP 1.1 Client using standard Unix sockets.
   Zero external dependencies. Supports GET, POST, custom headers,
   chunked transfer decoding, Content-Length decoding, and socket timeouts.
*)

type response = {
  status_code : int;
  status_message : string;
  headers : (string * string) list;
  body : string;
}

val parse_url : string -> (string * int * string, string) result
(** [parse_url url] parses [url] into [(host, port, path_and_query)].
    Supports http:// and https:// URLs with optional port and path/query. *)

val get_header : string -> (string * string) list -> string option
(** [get_header name headers] looks up a header key case-insensitively. *)

val decode_chunked : string -> (string, string) result
(** [decode_chunked chunked_str] decodes an HTTP/1.1 chunked transfer body. *)

val parse_response_string : string -> (response, string) result
(** [parse_response_string raw] parses a complete raw HTTP response text into [response]. *)

val request :
  ?headers:(string * string) list ->
  ?body:string ->
  ?timeout:float ->
  method_str:string ->
  url:string ->
  unit ->
  (response, string) result
(** [request ~method_str ~url ?headers ?body ?timeout ()] executes an HTTP request
    over Unix sockets. Returns [Ok response] or [Error msg]. *)

val get :
  ?headers:(string * string) list ->
  ?timeout:float ->
  string ->
  (response, string) result
(** [get url ?headers ?timeout] executes a GET request. *)

val post :
  ?headers:(string * string) list ->
  ?body:string ->
  ?timeout:float ->
  string ->
  (response, string) result
(** [post url ?headers ?body ?timeout] executes a POST request. *)
