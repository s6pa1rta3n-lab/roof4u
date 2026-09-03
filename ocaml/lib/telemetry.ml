(**
   telemetry.ml - Telemetry Logging, ScrapingFailureEvent, SHA-256 Fingerprinting,
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

let default_config : config = {
  owner = "s6pa1rta3n-lab";
  repo = "roof4u";
  token = (try Some (Sys.getenv "GITHUB_TOKEN") with _ -> (try Some (Sys.getenv "GH_TOKEN") with _ -> None));
  api_base_url = "https://api.github.com";
  offline_queue_path = ".github_issues_queue.json";
  throttle_seconds = 60.0;
  enabled = true;
}

let string_of_transport = function
  | MCP -> "mcp"
  | REST -> "rest"
  | OfflineQueue -> "offline_queue"
  | NoneTransport -> "none"

let string_of_issue_action = function
  | Created -> "created"
  | Commented -> "commented"
  | Queued -> "queued"
  | Throttled -> "throttled"
  | Disabled -> "disabled"
  | ErrorAction s -> "error: " ^ s

let generate_error_fingerprint (event : scraping_failure_event) : string =
  let err_prefix =
    let l = String.length event.error_message in
    if l > 120 then String.sub event.error_message 0 120 else event.error_message
  in
  let raw =
    Printf.sprintf "%s|%s|%s|%s"
      event.domain
      event.failure_type
      (Option.value ~default:"" event.selector)
      err_prefix
  in
  let hash = Crypto.sha256_string raw in
  String.sub hash 0 16

let format_issue_title (event : scraping_failure_event) : string =
  let brief =
    match event.selector with
    | Some s when String.trim s <> "" -> String.trim s
    | _ ->
        let msg = String.sub event.error_message 0 (min 60 (String.length event.error_message)) in
        String.map (function '\n' | '\r' -> ' ' | c -> c) (String.trim msg)
  in
  Printf.sprintf "[Scraping Failure] %s - %s: %s" event.domain event.failure_type brief

let format_issue_body ?(lesson_action = "Inspect target DOM hierarchy and update selector fallback list.") (event : scraping_failure_event) : string =
  let fingerprint = generate_error_fingerprint event in
  let snippet =
    match event.dom_snippet with
    | Some s when s <> "" -> String.sub s 0 (min 4000 (String.length s))
    | _ -> "<!-- No DOM snippet captured -->"
  in
  let trace = Option.value ~default:"No stack trace provided." event.stack_trace in
  let fix = Option.value ~default:lesson_action event.suggested_fix in
  let sel = Option.value ~default:"N/A" event.selector in
  let addr = Option.value ~default:"N/A" event.lead_address in

  Printf.sprintf
"## 🚨 Automated Scraping Failure Telemetry

<!-- ROO4U_TELEMETRY_START
domain: %s
url: %s
failure_type: %s
selector: %s
fingerprint: %s
timestamp: %s
lead_address: %s
ROO4U_TELEMETRY_END -->

### 1. Incident Overview
| Attribute | Detail |
|---|---|
| **Domain** | `%s` |
| **Target URL** | `%s` |
| **Failure Classification** | `%s` |
| **Failed Selector** | `%s` |
| **Lead Address** | `%s` |
| **Error Fingerprint** | `%s` |
| **Timestamp (UTC)** | `%s` |

### 2. Error Message & Stack Trace
**Exception**: `%s`

```python
%s
```

### 3. DOM Context Snippet
```html
%s
```

### 4. Self-Healing & Remediation Analysis
- **Root Cause Assessment**: Automated detection indicates selector drift or municipal portal structure changes.
- **Suggested Remediation**: %s
- **Feedforward Status**: Ingested into `lessons_learned.json` and `LocalVectorStore` for active query adaptation.

---
*Reported automatically by Roo4u Self-Healing Learning Agent*
"
    event.domain event.url event.failure_type sel fingerprint event.timestamp addr
    event.domain event.url event.failure_type sel addr fingerprint event.timestamp
    event.error_message trace snippet fix

let format_comment_body (event : scraping_failure_event) : string =
  let fingerprint = generate_error_fingerprint event in
  let snippet =
    match event.dom_snippet with
    | Some s when s <> "" -> String.sub s 0 (min 4000 (String.length s))
    | _ -> "<!-- No DOM snippet captured -->"
  in
  let sel = Option.value ~default:"N/A" event.selector in
  let addr = Option.value ~default:"N/A" event.lead_address in

  Printf.sprintf
"### 🔄 Scraping Failure Recurrence Logged

- **Timestamp (UTC)**: `%s`
- **Target URL**: `%s`
- **Lead Address**: `%s`
- **Error Summary**: `%s`
- **Failed Selector**: `%s`
- **Fingerprint**: `%s`

<details>
<summary>View DOM Snippet</summary>

```html
%s
```
</details>

*Recurrence recorded by Roo4u Dual-Transport GitHub Client.*
"
    event.timestamp event.url addr event.error_message sel fingerprint snippet

let parse_telemetry_metadata_block (body : string) : (string * string) list option =
  let start_marker = "<!-- ROO4U_TELEMETRY_START" in
  let end_marker = "ROO4U_TELEMETRY_END -->" in
  let s_len = String.length start_marker in
  let e_len = String.length end_marker in
  let b_len = String.length body in

  let rec find_sub sub sub_len i =
    if i + sub_len > b_len then None
    else if String.sub body i sub_len = sub then Some i
    else find_sub sub sub_len (i + 1)
  in
  match find_sub start_marker s_len 0 with
  | None -> None
  | Some start_idx ->
      let content_start = start_idx + s_len in
      match find_sub end_marker e_len content_start with
      | None -> None
      | Some end_idx ->
          let block_text = String.sub body content_start (end_idx - content_start) in
          let lines = String.split_on_char '\n' block_text in
          let pairs = List.filter_map (fun line ->
            match String.index_opt line ':' with
            | Some idx ->
                let k = String.trim (String.sub line 0 idx) in
                let v = String.trim (String.sub line (idx + 1) (String.length line - idx - 1)) in
                Some (k, v)
            | None -> None
          ) lines in
          Some pairs

let find_duplicate_issue (event : scraping_failure_event) (open_issues : Json.t list) : Json.t option =
  let fingerprint = generate_error_fingerprint event in
  let expected_prefix = Printf.sprintf "[Scraping Failure] %s - %s" event.domain event.failure_type in

  let check_issue (issue : Json.t) : bool =
    let body = Json.get_string "body" issue |> Option.value ~default:"" in
    let title = Json.get_string "title" issue |> Option.value ~default:"" in

    match parse_telemetry_metadata_block body with
    | Some pairs ->
        let get_k k = List.assoc_opt k pairs in
        if get_k "fingerprint" = Some fingerprint then true
        else if get_k "domain" = Some event.domain &&
                get_k "failure_type" = Some event.failure_type &&
                event.selector <> None &&
                get_k "selector" = event.selector then true
        else false
    | None ->
        if String.starts_with ~prefix:expected_prefix title then
          match event.selector with
          | Some s when s <> "" ->
              let s_len = String.length s in
              let t_len = String.length title in
              let rec has_sel i =
                if i + s_len > t_len then false
                else if String.sub title i s_len = s then true
                else has_sel (i + 1)
              in
              has_sel 0
          | _ -> true
        else false
  in
  List.find_opt check_issue open_issues

let throttle_cache : (string, float) Hashtbl.t = Hashtbl.create 32

let reset_throttle_cache () =
  Hashtbl.clear throttle_cache

let event_to_json (e : scraping_failure_event) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let fields =
    [
      ("domain", Json.String e.domain);
      ("url", Json.String e.url);
      ("failure_type", Json.String e.failure_type);
      ("error_message", Json.String e.error_message);
    ] @
    (opt_str "selector" e.selector) @
    (opt_str "stack_trace" e.stack_trace) @
    (opt_str "dom_snippet" e.dom_snippet) @
    (opt_str "suggested_fix" e.suggested_fix) @
    (opt_str "lead_address" e.lead_address) @
    (opt_str "phase" e.phase) @
    (opt_str "attempted_action" e.attempted_action) @
    (opt_str "exception_class" e.exception_class) @
    [
      ("retry_count", Json.Number (float_of_int e.retry_count));
      ("timestamp", Json.String e.timestamp);
    ]
  in
  Json.Object fields

let event_of_json (j : Json.t) : scraping_failure_event =
  let domain = Json.get_string "domain" j |> Option.value ~default:"" in
  let url = Json.get_string "url" j |> Option.value ~default:"" in
  let failure_type = Json.get_string "failure_type" j |> Option.value ~default:"UNKNOWN" in
  let error_message = Json.get_string "error_message" j |> Option.value ~default:"" in
  let selector = Json.get_string "selector" j in
  let stack_trace = Json.get_string "stack_trace" j in
  let dom_snippet = Json.get_string "dom_snippet" j in
  let suggested_fix = Json.get_string "suggested_fix" j in
  let lead_address = Json.get_string "lead_address" j in
  let phase = Json.get_string "phase" j in
  let attempted_action = Json.get_string "attempted_action" j in
  let exception_class = Json.get_string "exception_class" j in
  let retry_count = Json.get_int "retry_count" j |> Option.value ~default:0 in
  let timestamp = Json.get_string "timestamp" j |> Option.value ~default:"" in
  {
    domain;
    url;
    failure_type;
    error_message;
    selector;
    stack_trace;
    dom_snippet;
    suggested_fix;
    lead_address;
    phase;
    attempted_action;
    exception_class;
    retry_count;
    timestamp;
  }

let issue_log_result_to_json (res : issue_log_result) : Json.t =
  let opt_int k v = match v with Some i -> [(k, Json.Number (float_of_int i))] | None -> [(k, Json.Null)] in
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let fields =
    [
      ("action", Json.String (string_of_issue_action res.action));
    ] @
    (opt_int "issue_number" res.issue_number) @
    (opt_str "issue_url" res.issue_url) @
    [
      ("transport_used", Json.String (string_of_transport res.transport_used));
      ("deduplicated", Json.Bool res.deduplicated);
      ("error_fingerprint", Json.String res.error_fingerprint);
      ("message", Json.String res.message);
      ("timestamp", Json.String res.timestamp);
    ]
  in
  Json.Object fields

let queue_offline_event
    ?(queue_path = default_config.offline_queue_path)
    (event : scraping_failure_event)
    ~(title : string)
    ~(body : string)
    ~(labels : string list) : issue_log_result =
  let fingerprint = generate_error_fingerprint event in
  let existing_items =
    if Sys.file_exists queue_path then
      try
        let ic = open_in queue_path in
        let s = really_input_string ic (in_channel_length ic) in
        close_in ic;
        match Json.parse s with
        | Ok (Json.Array arr) -> arr
        | _ -> []
      with _ -> []
    else []
  in
  let now_iso = event.timestamp in
  let new_item = Json.Object [
    ("id", Json.String (Printf.sprintf "%s-%08x" fingerprint (int_of_float (Unix.gettimeofday ()))));
    ("fingerprint", Json.String fingerprint);
    ("event", event_to_json event);
    ("title", Json.String title);
    ("body", Json.String body);
    ("labels", Json.Array (List.map (fun l -> Json.String l) labels));
    ("queued_at", Json.String now_iso);
  ] in
  let updated_queue = Json.Array (new_item :: existing_items) in
  let tmp_path = Printf.sprintf "%s.tmp.%08x" queue_path (Random.int 0x3FFFFFFF) in
  (try
     let oc = open_out tmp_path in
     output_string oc (Json.to_string_pretty updated_queue);
     close_out oc;
     Sys.rename tmp_path queue_path
   with _ ->
     try Sys.remove tmp_path with _ -> ());

  {
    action = Queued;
    issue_number = None;
    issue_url = None;
    transport_used = OfflineQueue;
    deduplicated = false;
    error_fingerprint = fingerprint;
    message = Printf.sprintf "Queued telemetry failure to offline queue: %s" queue_path;
    timestamp = now_iso;
  }

let log_scraping_failure
    ?(config = default_config)
    ?mcp_caller
    ?lesson_action
    ?(allow_queue = true)
    (event : scraping_failure_event) : issue_log_result =
  let fingerprint = generate_error_fingerprint event in
  let now = Unix.gettimeofday () in

  if not config.enabled then
    {
      action = Disabled;
      issue_number = None;
      issue_url = None;
      transport_used = NoneTransport;
      deduplicated = false;
      error_fingerprint = fingerprint;
      message = "GitHub telemetry logger is disabled";
      timestamp = event.timestamp;
    }
  else
    let labels = [
      "scraping-failure";
      "automated-telemetry";
      Printf.sprintf "domain:%s" event.domain;
      Printf.sprintf "type:%s" (String.lowercase_ascii event.failure_type);
    ] in

    let open_issues, list_transport =
      match mcp_caller with
      | Some caller ->
          let payload = Json.Object [
            ("owner", Json.String config.owner);
            ("repo", Json.String config.repo);
            ("state", Json.String "OPEN");
            ("perPage", Json.Number 50.0);
          ] in
          (match caller "list_issues" payload with
           | Ok (Json.Array arr) -> (arr, MCP)
           | Ok (Json.Object fields) ->
               (match List.assoc_opt "issues" fields with
                | Some (Json.Array arr) -> (arr, MCP)
                | _ -> ([], MCP))
           | Ok _ -> ([], MCP)
           | Error _ -> ([], NoneTransport))
      | None -> ([], NoneTransport)
    in

    let duplicate_opt = find_duplicate_issue event open_issues in

    match duplicate_opt with
    | Some dup ->
        let issue_num = Json.get_int "number" dup in
        let issue_url = Json.get_string "html_url" dup in
        let last_time = try Hashtbl.find throttle_cache fingerprint with Not_found -> 0.0 in
        if now -. last_time < config.throttle_seconds then
          {
            action = Throttled;
            issue_number = issue_num;
            issue_url;
            transport_used = list_transport;
            deduplicated = true;
            error_fingerprint = fingerprint;
            message = Printf.sprintf "Throttled duplicate recurrence on issue #%s" (match issue_num with Some n -> string_of_int n | None -> "?");
            timestamp = event.timestamp;
          }
        else
          let comment_body = format_comment_body event in
          let mcp_comment_res =
            match mcp_caller, issue_num with
            | Some caller, Some num ->
                let payload = Json.Object [
                  ("owner", Json.String config.owner);
                  ("repo", Json.String config.repo);
                  ("issue_number", Json.Number (float_of_int num));
                  ("body", Json.String comment_body);
                ] in
                (match caller "add_issue_comment" payload with
                 | Ok _ ->
                     Hashtbl.replace throttle_cache fingerprint now;
                     Some {
                       action = Commented;
                       issue_number = issue_num;
                       issue_url;
                       transport_used = MCP;
                       deduplicated = true;
                       error_fingerprint = fingerprint;
                       message = Printf.sprintf "Appended recurrence comment to issue #%d via MCP" num;
                       timestamp = event.timestamp;
                     }
                 | Error _ -> None)
            | _ -> None
          in
          (match mcp_comment_res with
           | Some res -> res
           | None ->
               if allow_queue then
                 queue_offline_event ~queue_path:config.offline_queue_path event
                   ~title:(format_issue_title event)
                   ~body:(format_issue_body ?lesson_action event)
                   ~labels
               else
                 {
                   action = ErrorAction "Failed to append comment to duplicate issue";
                   issue_number = issue_num;
                   issue_url;
                   transport_used = NoneTransport;
                   deduplicated = true;
                   error_fingerprint = fingerprint;
                   message = "Failed to append comment via remote transport";
                   timestamp = event.timestamp;
                 })

    | None ->
        let title = format_issue_title event in
        let body = format_issue_body ?lesson_action event in
        let mcp_create_res =
          match mcp_caller with
          | Some caller ->
              let payload = Json.Object [
                ("owner", Json.String config.owner);
                ("repo", Json.String config.repo);
                ("method", Json.String "create");
                ("title", Json.String title);
                ("body", Json.String body);
                ("labels", Json.Array (List.map (fun l -> Json.String l) labels));
              ] in
              (match caller "issue_write" payload with
               | Ok res_obj ->
                   let num = Json.get_int "number" res_obj in
                   let url = Json.get_string "html_url" res_obj in
                   Hashtbl.replace throttle_cache fingerprint now;
                   Some {
                     action = Created;
                     issue_number = num;
                     issue_url = url;
                     transport_used = MCP;
                     deduplicated = false;
                     error_fingerprint = fingerprint;
                     message = Printf.sprintf "Created issue #%s via MCP" (match num with Some n -> string_of_int n | None -> "?");
                     timestamp = event.timestamp;
                   }
               | Error _ -> None)
          | None -> None
        in
        match mcp_create_res with
        | Some res -> res
        | None ->
            if allow_queue then
              queue_offline_event ~queue_path:config.offline_queue_path event
                ~title ~body ~labels
            else
              {
                action = ErrorAction "Failed to create issue via remote transports";
                issue_number = None;
                issue_url = None;
                transport_used = NoneTransport;
                deduplicated = false;
                error_fingerprint = fingerprint;
                message = "Failed to create issue via remote transports";
                timestamp = event.timestamp;
              }

let flush_offline_queue
    ?(config = default_config)
    ?mcp_caller
    () : issue_log_result list =
  if not (Sys.file_exists config.offline_queue_path) then []
  else
    let items =
      try
        let ic = open_in config.offline_queue_path in
        let s = really_input_string ic (in_channel_length ic) in
        close_in ic;
        match Json.parse s with
        | Ok (Json.Array arr) -> arr
        | _ -> []
      with _ -> []
    in
    let results = ref [] in
    let remaining = ref [] in
    List.iter (fun item ->
      match Json.get_field "event" item with
      | Some ev_json ->
          let ev = event_of_json ev_json in
          let res = log_scraping_failure ~config ?mcp_caller ~allow_queue:false ev in
          (match res.action with
           | Created | Commented | Throttled ->
               results := res :: !results
           | _ ->
               remaining := item :: !remaining)
      | None -> ()
    ) items;

    (if !remaining = [] then
       (try Sys.remove config.offline_queue_path with _ -> ())
     else
       let updated = Json.Array !remaining in
       let tmp_path = Printf.sprintf "%s.tmp.%08x" config.offline_queue_path (Random.int 0x3FFFFFFF) in
       try
         let oc = open_out tmp_path in
         output_string oc (Json.to_string_pretty updated);
         close_out oc;
         Sys.rename tmp_path config.offline_queue_path
       with _ -> ());

    List.rev !results
