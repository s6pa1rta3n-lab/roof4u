(**
   telemetry.mli - Telemetry Logging, ScrapingFailureEvent, SHA-256 Fingerprinting,
   and Dual-Transport GitHub Issue Logger with Deduplication and Throttling.
*)

type scraping_failure_event = {
  domain : string;
  url : string;
  failure_type : string;
  error_message : string;
  selector : string option;
  stack_trace : string option;
  dom_snippet : string option;
  suggested_fix : string option;
  lead_address : string option;
  phase : string option;
  attempted_action : string option;
  exception_class : string option;
  retry_count : int;
  timestamp : string;
}

type transport =
  | MCP
  | REST
  | OfflineQueue
  | NoneTransport

type issue_action =
  | Created
  | Commented
  | Queued
  | Throttled
  | Disabled
  | ErrorAction of string

type issue_log_result = {
  action : issue_action;
  issue_number : int option;
  issue_url : string option;
  transport_used : transport;
  deduplicated : bool;
  error_fingerprint : string;
  message : string;
  timestamp : string;
}

type config = {
  owner : string;
  repo : string;
  token : string option;
  api_base_url : string;
  offline_queue_path : string;
  throttle_seconds : float;
  enabled : bool;
}

val default_config : config

val string_of_transport : transport -> string
val string_of_issue_action : issue_action -> string

val generate_error_fingerprint : scraping_failure_event -> string
(** [generate_error_fingerprint event] computes a deterministic 16-character hex SHA-256
    fingerprint over domain|failure_type|selector|error_message[:120]. *)

val format_issue_title : scraping_failure_event -> string
val format_issue_body : ?lesson_action:string -> scraping_failure_event -> string
val format_comment_body : scraping_failure_event -> string

val parse_telemetry_metadata_block : string -> (string * string) list option
(** [parse_telemetry_metadata_block body] extracts key-value pairs from
    <!-- ROO4U_TELEMETRY_START ... ROO4U_TELEMETRY_END --> block. *)

val find_duplicate_issue :
  scraping_failure_event ->
  Json.t list ->
  Json.t option
(** [find_duplicate_issue event open_issues] searches list of open issue objects
    for a duplicate matching fingerprint or domain+failure_type+selector. *)

val event_to_json : scraping_failure_event -> Json.t
val event_of_json : Json.t -> scraping_failure_event

val issue_log_result_to_json : issue_log_result -> Json.t

val queue_offline_event :
  ?queue_path:string ->
  scraping_failure_event ->
  title:string ->
  body:string ->
  labels:string list ->
  issue_log_result

val flush_offline_queue :
  ?config:config ->
  ?mcp_caller:(string -> Json.t -> (Json.t, string) result) ->
  unit ->
  issue_log_result list

val log_scraping_failure :
  ?config:config ->
  ?mcp_caller:(string -> Json.t -> (Json.t, string) result) ->
  ?lesson_action:string ->
  ?allow_queue:bool ->
  scraping_failure_event ->
  issue_log_result

val reset_throttle_cache : unit -> unit
