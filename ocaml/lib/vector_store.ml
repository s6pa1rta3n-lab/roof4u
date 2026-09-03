(**
   vector_store.ml - Embedded Vector Store & Cosine Similarity Search Engine.
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

type t = {
  db_path : string;
  dimension : int;
  records : (string, vector_record) Hashtbl.t;
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

let record_to_json (r : vector_record) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let emb_json = Json.Array (Array.to_list (Array.map (fun f -> Json.Number f) r.embedding)) in
  let meta_json = Json.Object r.metadata in
  let fields =
    [
      ("id", Json.String r.id);
      ("domain", Json.String r.domain);
    ] @
    (opt_str "failure_type" r.failure_type) @
    [
      ("text", Json.String r.text);
      ("metadata", meta_json);
      ("embedding", emb_json);
      ("created_at", Json.String r.created_at);
    ]
  in
  Json.Object fields

let record_of_json (j : Json.t) : vector_record =
  let id = Json.get_string "id" j |> Option.value ~default:"" in
  let domain = Json.get_string "domain" j |> Option.value ~default:"general" in
  let failure_type = Json.get_string "failure_type" j in
  let text = Json.get_string "text" j |> Option.value ~default:"" in
  let metadata = Json.get_object "metadata" j |> Option.value ~default:[] in
  let embedding =
    match Json.get_array "embedding" j with
    | Some arr ->
        let floats = List.filter_map Json.as_float arr in
        Array.of_list floats
    | None -> Array.make Embeddings.default_dimension 0.0
  in
  let created_at = Json.get_string "created_at" j |> Option.value ~default:(iso8601_now ()) in
  {
    id;
    domain;
    failure_type;
    text;
    metadata;
    embedding;
    created_at;
  }

let make_record
    ?(domain = "general")
    ?failure_type
    ?(metadata = [])
    ?embedding
    ?(created_at = iso8601_now ())
    ~id
    ~text
    () : vector_record =
  let emb =
    match embedding with
    | Some e -> e
    | None -> Embeddings.embed_text text
  in
  {
    id;
    domain;
    failure_type;
    text;
    metadata;
    embedding = emb;
    created_at;
  }

let persist_to_disk (t : t) : unit =
  if t.db_path <> ":memory:" then
    let dir = Filename.dirname t.db_path in
    if not (Sys.file_exists dir) then
      (try Unix.mkdir dir 0o755 with _ -> ());
    let rand_suffix = Printf.sprintf "%06x_%d" (Random.bits () land 0xFFFFFF) (Unix.getpid ()) in
    let tmp_path = Printf.sprintf "%s.tmp.%s" t.db_path rand_suffix in
    let oc = open_out_bin tmp_path in
    let fd = Unix.descr_of_out_channel oc in
    let all_records = Hashtbl.fold (fun _ r acc -> r :: acc) t.records [] in
    let json_ast = Json.Array (List.map record_to_json all_records) in
    let json_str = Json.to_string_pretty ~indent:2 json_ast in
    output_string oc json_str;
    output_string oc "\n";
    flush oc;
    Unix.fsync fd;
    close_out oc;
    Sys.rename tmp_path t.db_path

let load_from_disk (t : t) : unit =
  if t.db_path <> ":memory:" && Sys.file_exists t.db_path then
    try
      let ic = open_in_bin t.db_path in
      let len = in_channel_length ic in
      let content = really_input_string ic len in
      close_in ic;
      let trimmed = String.trim content in
      if String.length trimmed > 0 then
        match Json.parse trimmed with
        | Ok (Json.Array items) ->
            List.iter (fun item ->
              try
                let rec_obj = record_of_json item in
                Hashtbl.replace t.records rec_obj.id rec_obj
              with _ -> ()
            ) items
        | _ -> ()
    with _ -> ()

let create ?(db_path = ":memory:") ?(dimension = Embeddings.default_dimension) () : t =
  let full_path =
    if db_path = ":memory:" then ":memory:"
    else if Filename.is_relative db_path then
      Filename.concat (Sys.getcwd ()) db_path
    else db_path
  in
  let store = {
    db_path = full_path;
    dimension;
    records = Hashtbl.create 64;
    mutex = Mutex.create ();
  } in
  load_from_disk store;
  store

let db_path (t : t) : string = t.db_path
let dimension (t : t) : int = t.dimension

let upsert_record (t : t) (r : vector_record) : vector_record =
  Mutex.protect t.mutex (fun () ->
    let emb =
      if Array.length r.embedding = 0 || (Array.for_all (fun x -> x = 0.0) r.embedding) then
        Embeddings.embed_text ~dimension:t.dimension r.text
      else r.embedding
    in
    let final_record = { r with embedding = emb } in
    Hashtbl.replace t.records final_record.id final_record;
    persist_to_disk t;
    final_record
  )

let upsert
    ?(domain = "general")
    ?failure_type
    ?(metadata = [])
    ?embedding
    ?(created_at = iso8601_now ())
    (t : t)
    (id : string)
    (text : string) : vector_record =
  let rec_obj = make_record ~domain ?failure_type ~metadata ?embedding ~created_at ~id ~text () in
  upsert_record t rec_obj

let upsert_batch (t : t) (records : vector_record list) : int =
  Mutex.protect t.mutex (fun () ->
    let count = ref 0 in
    List.iter (fun r ->
      let emb =
        if Array.length r.embedding = 0 || (Array.for_all (fun x -> x = 0.0) r.embedding) then
          Embeddings.embed_text ~dimension:t.dimension r.text
        else r.embedding
      in
      let final_record = { r with embedding = emb } in
      Hashtbl.replace t.records final_record.id final_record;
      incr count
    ) records;
    if !count > 0 then persist_to_disk t;
    !count
  )

let get (t : t) (record_id : string) : vector_record option =
  Mutex.protect t.mutex (fun () ->
    Hashtbl.find_opt t.records record_id
  )

let delete (t : t) (record_id : string) : bool =
  Mutex.protect t.mutex (fun () ->
    if Hashtbl.mem t.records record_id then (
      Hashtbl.remove t.records record_id;
      persist_to_disk t;
      true
    ) else false
  )

let update_metadata (t : t) (record_id : string) (metadata_updates : (string * Json.t) list) : bool =
  Mutex.protect t.mutex (fun () ->
    match Hashtbl.find_opt t.records record_id with
    | Some existing ->
        let new_meta_tbl = Hashtbl.create 16 in
        List.iter (fun (k, v) -> Hashtbl.replace new_meta_tbl k v) existing.metadata;
        List.iter (fun (k, v) -> Hashtbl.replace new_meta_tbl k v) metadata_updates;
        let merged_meta = Hashtbl.fold (fun k v acc -> (k, v) :: acc) new_meta_tbl [] in
        let updated = { existing with metadata = merged_meta } in
        Hashtbl.replace t.records record_id updated;
        persist_to_disk t;
        true
    | None -> false
  )

let search
    ?(query_embedding : float array option)
    ?(top_k = 5)
    ?(domain : string option)
    ?(failure_type : string option)
    ?(min_similarity = -1.0)
    (t : t)
    (query_text : string option) : search_result list =
  Mutex.protect t.mutex (fun () ->
    let q_emb =
      match query_embedding with
      | Some emb -> emb
      | None ->
          (match query_text with
           | Some q -> Embeddings.embed_text ~dimension:t.dimension q
           | None -> invalid_arg "search: Must provide either query_text or query_embedding")
    in

    let candidates = ref [] in
    Hashtbl.iter (fun _ rec_obj ->
      let match_domain =
        match domain with
        | Some d -> String.lowercase_ascii rec_obj.domain = String.lowercase_ascii d
        | None -> true
      in
      let match_failure =
        match failure_type with
        | Some f ->
            (match rec_obj.failure_type with
             | Some ft -> String.uppercase_ascii ft = String.uppercase_ascii f
             | None -> false)
        | None -> true
      in
      if match_domain && match_failure then
        let score = Embeddings.cosine_similarity q_emb rec_obj.embedding in
        if score >= min_similarity then
          candidates := (rec_obj, score) :: !candidates
    ) t.records;

    let sorted = List.sort (fun (_, s1) (_, s2) -> Float.compare s2 s1) !candidates in
    let rec take n = function
      | [] -> []
      | _ when n <= 0 -> []
      | x :: xs -> x :: take (n - 1) xs
    in
    let top_list = take top_k sorted in
    List.mapi (fun idx (rec_obj, score) ->
      {
        record = rec_obj;
        score;
        rank = idx + 1;
      }
    ) top_list
  )

let count ?(domain : string option) (t : t) : int =
  Mutex.protect t.mutex (fun () ->
    match domain with
    | None -> Hashtbl.length t.records
    | Some d ->
        let cnt = ref 0 in
        Hashtbl.iter (fun _ r ->
          if String.lowercase_ascii r.domain = String.lowercase_ascii d then
            incr cnt
        ) t.records;
        !cnt
  )

let clear (t : t) : unit =
  Mutex.protect t.mutex (fun () ->
    Hashtbl.clear t.records;
    persist_to_disk t
  )

let sync_lessons (lesson_store : Lesson_store.t) (vector_store : t) : int =
  let lessons = Lesson_store.load_lessons lesson_store in
  let count = ref 0 in
  List.iter (fun (l : Lesson_store.lesson) ->
    let rca = match l.root_cause_analysis with Some s -> s | None -> l.lesson_learned in
    let action = match l.recommended_workaround with Some s -> s | None -> l.recommended_action in
    let doc_text = Printf.sprintf "[%s] [%s] %s | %s | Action: %s"
      l.domain l.failure_type l.error_message rca action in
    let metadata = [
      ("status", Json.String l.status);
      ("resolved", Json.Bool l.resolved);
      ("occurrence_count", Json.Number (float_of_int l.occurrence_count));
      ("timestamp", Json.String l.timestamp);
    ] in
    ignore (upsert
      ~domain:l.domain
      ~failure_type:l.failure_type
      ~metadata
      vector_store
      l.id
      doc_text);
    incr count
  ) lessons;
  !count
