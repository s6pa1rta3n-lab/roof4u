(**
   lesson_store.ml - POSIX Atomic JSON Lesson Store with Advisory Locking.
   Provides persistent memory for scraping failures, workarounds, and self-healing
   resolutions with Unix.lockf advisory locking and corruption recovery.
*)

type lesson_status =
  | Active
  | Resolved
  | Probation
  | Deprecated

let string_of_status = function
  | Active -> "ACTIVE"
  | Resolved -> "RESOLVED"
  | Probation -> "PROBATION"
  | Deprecated -> "DEPRECATED"

let status_of_string s =
  match String.uppercase_ascii (String.trim s) with
  | "RESOLVED" -> Resolved
  | "PROBATION" -> Probation
  | "DEPRECATED" -> Deprecated
  | _ -> Active

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
  status : string;
  occurrence_count : int;
  success_count_after_workaround : int;
  target_entity : string option;
  phase : string option;
  tags : string list;
}

type t = {
  file_path : string;
  mutex : Mutex.t;
}

let iso8601_now () : string =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  let frac = int_of_float ((t -. floor t) *. 1000.0) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"
    (tm.Unix.tm_year + 1900)
    (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday
    tm.Unix.tm_hour
    tm.Unix.tm_min
    tm.Unix.tm_sec
    frac

let generate_id () : string =
  let t = Unix.gettimeofday () in
  let r1 = Random.bits () in
  let r2 = Random.bits () in
  let str = Printf.sprintf "lesson-%f-%d-%d" t r1 r2 in
  let hash = Crypto.sha256_string str in
  String.sub hash 0 16

let make_lesson
    ?(id = generate_id ())
    ?(url = "")
    ?source_url
    ?(failure_type = "UNKNOWN")
    ?error_category
    ?(error_message = "")
    ?(lesson_learned = "")
    ?(recommended_action = "")
    ?root_cause_analysis
    ?strategy_attempted
    ?recommended_workaround
    ?(suggested_selectors = [])
    ?(suggested_delay_seconds = 0.0)
    ?(suggested_headers = [])
    ?code_patch_suggestion
    ?github_issue_number
    ?github_issue_url
    ?(timestamp = iso8601_now ())
    ?dom_snippet
    ?(resolved = false)
    ?(status = "ACTIVE")
    ?(occurrence_count = 1)
    ?(success_count_after_workaround = 0)
    ?target_entity
    ?phase
    ?(tags = [])
    ~domain
    () : lesson =
  let url = if url = "" then Option.value source_url ~default:"" else url in
  let source_url = match source_url with Some s -> Some s | None -> if url <> "" then Some url else None in
  let failure_type =
    if failure_type = "UNKNOWN" || failure_type = "" then
      Option.value error_category ~default:"UNKNOWN"
    else failure_type
  in
  let error_category = match error_category with Some s -> Some s | None -> Some failure_type in
  let lesson_learned =
    if lesson_learned = "" then Option.value root_cause_analysis ~default:""
    else lesson_learned
  in
  let root_cause_analysis = match root_cause_analysis with Some s -> Some s | None -> if lesson_learned <> "" then Some lesson_learned else None in
  let recommended_action =
    if recommended_action = "" then Option.value recommended_workaround ~default:""
    else recommended_action
  in
  let recommended_workaround = match recommended_workaround with Some s -> Some s | None -> if recommended_action <> "" then Some recommended_action else None in
  let status =
    if resolved && String.uppercase_ascii status = "ACTIVE" then "RESOLVED"
    else status
  in
  {
    id;
    domain;
    url;
    source_url;
    failure_type;
    error_category;
    error_message;
    lesson_learned;
    recommended_action;
    root_cause_analysis;
    strategy_attempted;
    recommended_workaround;
    suggested_selectors;
    suggested_delay_seconds;
    suggested_headers;
    code_patch_suggestion;
    github_issue_number;
    github_issue_url;
    timestamp;
    dom_snippet;
    resolved;
    status;
    occurrence_count;
    success_count_after_workaround;
    target_entity;
    phase;
    tags;
  }

let lesson_to_json (l : lesson) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let opt_int k v = match v with Some i -> [(k, Json.Number (float_of_int i))] | None -> [(k, Json.Null)] in
  let selectors_json = Json.Array (List.map (fun s -> Json.String s) l.suggested_selectors) in
  let headers_json = Json.Object (List.map (fun (k, v) -> (k, Json.String v)) l.suggested_headers) in
  let tags_json = Json.Array (List.map (fun s -> Json.String s) l.tags) in
  let fields =
    [
      ("id", Json.String l.id);
      ("domain", Json.String l.domain);
      ("url", Json.String l.url);
    ] @
    (opt_str "source_url" l.source_url) @
    [
      ("failure_type", Json.String l.failure_type);
    ] @
    (opt_str "error_category" l.error_category) @
    [
      ("error_message", Json.String l.error_message);
      ("lesson_learned", Json.String l.lesson_learned);
      ("recommended_action", Json.String l.recommended_action);
    ] @
    (opt_str "root_cause_analysis" l.root_cause_analysis) @
    (opt_str "strategy_attempted" l.strategy_attempted) @
    (opt_str "recommended_workaround" l.recommended_workaround) @
    [
      ("suggested_selectors", selectors_json);
      ("suggested_delay_seconds", Json.Number l.suggested_delay_seconds);
      ("suggested_headers", headers_json);
    ] @
    (opt_str "code_patch_suggestion" l.code_patch_suggestion) @
    (opt_int "github_issue_number" l.github_issue_number) @
    (opt_str "github_issue_url" l.github_issue_url) @
    [
      ("timestamp", Json.String l.timestamp);
    ] @
    (opt_str "dom_snippet" l.dom_snippet) @
    [
      ("resolved", Json.Bool l.resolved);
      ("status", Json.String l.status);
      ("occurrence_count", Json.Number (float_of_int l.occurrence_count));
      ("success_count_after_workaround", Json.Number (float_of_int l.success_count_after_workaround));
    ] @
    (opt_str "target_entity" l.target_entity) @
    (opt_str "phase" l.phase) @
    [ ("tags", tags_json) ]
  in
  Json.Object fields

let lesson_of_json (j : Json.t) : lesson =
  let id = Json.get_string "id" j |> Option.value ~default:(generate_id ()) in
  let domain = Json.get_string "domain" j |> Option.value ~default:"unknown" in
  let url = Json.get_string "url" j |> Option.value ~default:"" in
  let source_url = Json.get_string "source_url" j in
  let failure_type = Json.get_string "failure_type" j |> Option.value ~default:"UNKNOWN" in
  let error_category = Json.get_string "error_category" j in
  let error_message = Json.get_string "error_message" j |> Option.value ~default:"" in
  let lesson_learned = Json.get_string "lesson_learned" j |> Option.value ~default:"" in
  let lesson_field =
    if lesson_learned = "" then Json.get_string "lesson" j |> Option.value ~default:""
    else lesson_learned
  in
  let recommended_action = Json.get_string "recommended_action" j |> Option.value ~default:"" in
  let root_cause_analysis = Json.get_string "root_cause_analysis" j in
  let strategy_attempted = Json.get_string "strategy_attempted" j in
  let recommended_workaround = Json.get_string "recommended_workaround" j in

  let suggested_selectors =
    match Json.get_array "suggested_selectors" j with
    | Some arr -> List.filter_map Json.as_string arr
    | None -> []
  in

  let suggested_delay_seconds = Json.get_float "suggested_delay_seconds" j |> Option.value ~default:0.0 in

  let suggested_headers =
    match Json.get_object "suggested_headers" j with
    | Some kvs ->
        List.filter_map (fun (k, v) ->
          match Json.as_string v with
          | Some s -> Some (k, s)
          | None -> None
        ) kvs
    | None -> []
  in

  let code_patch_suggestion = Json.get_string "code_patch_suggestion" j in
  let github_issue_number = Json.get_int "github_issue_number" j in
  let github_issue_url = Json.get_string "github_issue_url" j in
  let timestamp = Json.get_string "timestamp" j |> Option.value ~default:(iso8601_now ()) in
  let dom_snippet = Json.get_string "dom_snippet" j in
  let resolved = Json.get_bool "resolved" j |> Option.value ~default:false in
  let status = Json.get_string "status" j |> Option.value ~default:(if resolved then "RESOLVED" else "ACTIVE") in
  let occurrence_count =
    match Json.get_int "occurrence_count" j with
    | Some c -> c
    | None -> (match Json.get_int "count" j with Some c -> c | None -> 1)
  in
  let success_count_after_workaround =
    Json.get_int "success_count_after_workaround" j |> Option.value ~default:0
  in
  let target_entity = Json.get_string "target_entity" j in
  let phase = Json.get_string "phase" j in
  let tags =
    match Json.get_array "tags" j with
    | Some arr -> List.filter_map Json.as_string arr
    | None -> []
  in

  make_lesson
    ~id
    ~url
    ?source_url
    ~failure_type
    ?error_category
    ~error_message
    ~lesson_learned:lesson_field
    ~recommended_action
    ?root_cause_analysis
    ?strategy_attempted
    ?recommended_workaround
    ~suggested_selectors
    ~suggested_delay_seconds
    ~suggested_headers
    ?code_patch_suggestion
    ?github_issue_number
    ?github_issue_url
    ~timestamp
    ?dom_snippet
    ~resolved
    ~status
    ~occurrence_count
    ~success_count_after_workaround
    ?target_entity
    ?phase
    ~tags
    ~domain
    ()

let create ?(file_path = "lessons_learned.json") () : t =
  let full_path =
    if Filename.is_relative file_path then
      Filename.concat (Sys.getcwd ()) file_path
    else file_path
  in
  {
    file_path = full_path;
    mutex = Mutex.create ();
  }

let file_path (t : t) : string = t.file_path

let with_file_lock (t : t) (f : unit -> 'a) : 'a =
  Mutex.protect t.mutex (fun () ->
    let dir = Filename.dirname t.file_path in
    if not (Sys.file_exists dir) then
      (try Unix.mkdir dir 0o755 with _ -> ());
    let lock_path = t.file_path ^ ".lock" in
    let lock_fd = Unix.openfile lock_path [Unix.O_CREAT; Unix.O_RDWR] 0o644 in
    try
      Unix.lockf lock_fd Unix.F_LOCK 0;
      let res =
        try f ()
        with exn ->
          (try Unix.lockf lock_fd Unix.F_ULOCK 0 with _ -> ());
          (try Unix.close lock_fd with _ -> ());
          raise exn
      in
      (try Unix.lockf lock_fd Unix.F_ULOCK 0 with _ -> ());
      (try Unix.close lock_fd with _ -> ());
      res
    with exn ->
      (try Unix.close lock_fd with _ -> ());
      raise exn
  )

let atomic_write_internal (t : t) (lessons : lesson list) : unit =
  let dir = Filename.dirname t.file_path in
  if not (Sys.file_exists dir) then
    (try Unix.mkdir dir 0o755 with _ -> ());
  let rand_suffix = Printf.sprintf "%06x_%d" (Random.bits () land 0xFFFFFF) (Unix.getpid ()) in
  let tmp_path = Printf.sprintf "%s.tmp.%s" t.file_path rand_suffix in
  let oc = open_out_bin tmp_path in
  let fd = Unix.descr_of_out_channel oc in
  let json_ast = Json.Array (List.map lesson_to_json lessons) in
  let json_str = Json.to_string_pretty ~indent:2 json_ast in
  output_string oc json_str;
  output_string oc "\n";
  flush oc;
  Unix.fsync fd;
  close_out oc;
  Sys.rename tmp_path t.file_path

let trigger_corruption_recovery (t : t) : lesson list =
  let ts = Printf.sprintf "%.6f" (Unix.gettimeofday ()) in
  let rand = Printf.sprintf "%06x" (Random.bits () land 0xFFFFFF) in
  let backup_path = Printf.sprintf "%s.corrupt.%s_%s" t.file_path ts rand in
  (try Sys.rename t.file_path backup_path with _ -> ());
  atomic_write_internal t [];
  []

let load_lessons (t : t) : lesson list =
  with_file_lock t (fun () ->
    if not (Sys.file_exists t.file_path) then []
    else
      let ic = open_in_bin t.file_path in
      let len = in_channel_length ic in
      let content = really_input_string ic len in
      close_in ic;
      let trimmed = String.trim content in
      if String.length trimmed = 0 then []
      else
        match Json.parse trimmed with
        | Ok (Json.Array items) ->
            (try List.map lesson_of_json items
             with _ -> trigger_corruption_recovery t)
        | _ -> trigger_corruption_recovery t
  )

let save_lessons_atomic (t : t) (lessons : lesson list) : unit =
  with_file_lock t (fun () ->
    atomic_write_internal t lessons
  )

let upsert_lesson (t : t) (lesson : lesson) : lesson =
  with_file_lock t (fun () ->
    let current =
      if not (Sys.file_exists t.file_path) then []
      else
        let ic = open_in_bin t.file_path in
        let len = in_channel_length ic in
        let content = really_input_string ic len in
        close_in ic;
        let trimmed = String.trim content in
        if String.length trimmed = 0 then []
        else
          match Json.parse trimmed with
          | Ok (Json.Array items) -> (try List.map lesson_of_json items with _ -> trigger_corruption_recovery t)
          | _ -> trigger_corruption_recovery t
    in
    let rec replace = function
      | [] -> [lesson], false
      | x :: xs when x.id = lesson.id -> lesson :: xs, true
      | x :: xs ->
          let updated_xs, found = replace xs in
          x :: updated_xs, found
    in
    let updated_list, found = replace current in
    let final_list = if found then updated_list else current @ [lesson] in
    atomic_write_internal t final_list;
    lesson
  )

let add_lesson (t : t) (lesson : lesson) : lesson =
  upsert_lesson t lesson

let get_lesson (t : t) (lesson_id : string) : lesson option =
  let lessons = load_lessons t in
  List.find_opt (fun l -> l.id = lesson_id) lessons

let list_lessons
    ?(domain : string option)
    ?(failure_type : string option)
    ?(limit : int option)
    (t : t) : lesson list =
  let all = load_lessons t in
  let filtered =
    List.filter (fun l ->
      let match_domain =
        match domain with
        | Some d -> String.lowercase_ascii l.domain = String.lowercase_ascii d
        | None -> true
      in
      let match_failure =
        match failure_type with
        | Some f ->
            String.uppercase_ascii l.failure_type = String.uppercase_ascii f ||
            (match l.error_category with
             | Some cat -> String.uppercase_ascii cat = String.uppercase_ascii f
             | None -> false)
        | None -> true
      in
      match_domain && match_failure
    ) all
  in
  match limit with
  | Some n when n > 0 ->
      let rec take n = function
        | [] -> []
        | _ when n <= 0 -> []
        | x :: xs -> x :: take (n - 1) xs
      in
      take n filtered
  | _ -> filtered

let filter_by_domain (d : string) (t : t) : lesson list =
  list_lessons ~domain:d t

let update_lesson (t : t) (lesson_id : string) (updater : lesson -> lesson) : lesson option =
  with_file_lock t (fun () ->
    let all =
      if not (Sys.file_exists t.file_path) then []
      else
        let ic = open_in_bin t.file_path in
        let len = in_channel_length ic in
        let content = really_input_string ic len in
        close_in ic;
        let trimmed = String.trim content in
        if String.length trimmed = 0 then []
        else
          match Json.parse trimmed with
          | Ok (Json.Array items) -> (try List.map lesson_of_json items with _ -> trigger_corruption_recovery t)
          | _ -> trigger_corruption_recovery t
    in
    let found_target = ref None in
    let updated_list =
      List.map (fun l ->
        if l.id = lesson_id then
          let updated = updater l in
          found_target := Some updated;
          updated
        else l
      ) all
    in
    match !found_target with
    | Some target ->
        atomic_write_internal t updated_list;
        Some target
    | None -> None
  )

let increment_success (t : t) (lesson_id : string) : lesson option =
  update_lesson t lesson_id (fun l ->
    let new_count = l.success_count_after_workaround + 1 in
    let should_resolve = new_count >= 5 && String.uppercase_ascii l.status = "ACTIVE" in
    let new_status = if should_resolve then "RESOLVED" else l.status in
    let new_resolved = if should_resolve then true else l.resolved in
    { l with
      success_count_after_workaround = new_count;
      status = new_status;
      resolved = new_resolved;
    }
  )

let delete_lesson (t : t) (lesson_id : string) : bool =
  with_file_lock t (fun () ->
    let all =
      if not (Sys.file_exists t.file_path) then []
      else
        let ic = open_in_bin t.file_path in
        let len = in_channel_length ic in
        let content = really_input_string ic len in
        close_in ic;
        let trimmed = String.trim content in
        if String.length trimmed = 0 then []
        else
          match Json.parse trimmed with
          | Ok (Json.Array items) -> (try List.map lesson_of_json items with _ -> trigger_corruption_recovery t)
          | _ -> trigger_corruption_recovery t
    in
    let initial_len = List.length all in
    let filtered = List.filter (fun l -> l.id <> lesson_id) all in
    if List.length filtered < initial_len then (
      atomic_write_internal t filtered;
      true
    ) else false
  )

let count ?(domain : string option) (t : t) : int =
  List.length (list_lessons ?domain t)

let clear (t : t) : unit =
  with_file_lock t (fun () ->
    atomic_write_internal t []
  )

let load_lessons_from_file (path : string) : lesson list =
  let store = create ~file_path:path () in
  load_lessons store

let save_lessons_to_file_atomic (path : string) (lessons : lesson list) : unit =
  let store = create ~file_path:path () in
  save_lessons_atomic store lessons

let upsert_lesson_to_file (path : string) (lesson : lesson) : lesson =
  let store = create ~file_path:path () in
  upsert_lesson store lesson

let increment_success_in_file (path : string) (lesson_id : string) : bool =
  let store = create ~file_path:path () in
  match increment_success store lesson_id with
  | Some _ -> true
  | None -> false
