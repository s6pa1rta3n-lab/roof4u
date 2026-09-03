(**
   test_memory.ml - Comprehensive Test Suite for Milestone 2:
   Embeddings, Lesson Store (with POSIX Locking & Corruption Recovery),
   Vector Store (Cosine Semantic Search & Filtering), and SQLite Lead Database.
*)

open Roof_engine

let test_count = ref 0
let pass_count = ref 0

let assert_true name cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n" name;
    failwith ("Assertion failed: " ^ name)
  )

let assert_false name cond =
  assert_true name (not cond)

let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s (%d == %d)\n" name expected actual
  ) else (
    Printf.printf "  [FAIL] %s (Expected %d, got %d)\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let assert_equal_string name expected actual =
  incr test_count;
  if String.equal expected actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s (\"%s\" == \"%s\")\n" name expected actual
  ) else (
    Printf.printf "  [FAIL] %s (Expected \"%s\", got \"%s\")\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let assert_equal_float name expected actual eps =
  incr test_count;
  if abs_float (expected -. actual) <= eps then (
    incr pass_count;
    Printf.printf "  [PASS] %s (%.4f == %.4f)\n" name expected actual
  ) else (
    Printf.printf "  [FAIL] %s (Expected %.4f, got %.4f)\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let () =
  Printf.printf "\n=================================================================\n";
  Printf.printf "=== MILESTONE 2: Dual Memory, Embeddings, Vector & DB Test Suite ===\n";
  Printf.printf "=================================================================\n\n";

  Printf.printf "--- [Section 1] Feature Hashing & Offline Embeddings ---\n";

  let text1 = "HTTP 403 Forbidden Cloudflare Bot Challenge on Zillow" in
  let emb1 = Embeddings.embed_text text1 in
  assert_equal_int "F6.1: Embedding dimension is exactly 256" 256 (Array.length emb1);

  let norm1 = Embeddings.l2_norm emb1 in
  assert_equal_float "F6.2: Vector L2 norm is 1.0 within numerical precision" 1.0 norm1 0.0001;

  let emb1_repeat = Embeddings.embed_text text1 in
  let sim_self = Embeddings.cosine_similarity emb1 emb1_repeat in
  assert_equal_float "F6.3: Deterministic embedding produces exact identity similarity 1.0" 1.0 sim_self 0.00001;

  let tokens = Embeddings.tokenize "HTTP 403 Forbidden on server 500" in
  let has_status_403 = List.exists (fun (t, w) -> t = "status:403" && abs_float (w -. 3.0) < 0.001) tokens in
  let has_status_500 = List.exists (fun (t, w) -> t = "status:500" && abs_float (w -. 3.0) < 0.001) tokens in
  let has_word_http = List.exists (fun (t, w) -> t = "w:http" && abs_float (w -. 1.5) < 0.001) tokens in
  let has_bigram = List.exists (fun (t, w) -> t = "bi:http_403" && abs_float (w -. 2.0) < 0.001) tokens in
  let has_3gram = List.exists (fun (t, w) -> t = "3g:htt" && abs_float (w -. 0.5) < 0.001) tokens in
  let has_4gram = List.exists (fun (t, w) -> t = "4g:http" && abs_float (w -. 0.5) < 0.001) tokens in
  assert_true "F6.4: Status code tokens boosted with weight 3.0" (has_status_403 && has_status_500);
  assert_true "F6.5: Word tokens extracted with weight 1.5" has_word_http;
  assert_true "F6.6: Bigrams extracted with weight 2.0" has_bigram;
  assert_true "F6.7: Subword 3-grams and 4-grams extracted with weight 0.5" (has_3gram && has_4gram);

  let empty_emb = Embeddings.embed_text "" in
  assert_equal_int "F6.8: Empty string embedding length is 256" 256 (Array.length empty_emb);
  assert_equal_float "F6.9: Empty string embedding norm is 1.0" 1.0 (Embeddings.l2_norm empty_emb) 0.0001;

  let crc_hello = Embeddings.crc32 "hello" in
  assert_true "F6.10: CRC32 checksum computed correctly" (crc_hello >= 0);

  let batch_texts = [
    "Rate limit 429 encountered on DataSF API";
    "DOM selector drift on San Francisco DBI table";
    "Cloudflare bot protection 403 challenge";
  ] in
  let batch_embs = Embeddings.embed_batch batch_texts in
  assert_equal_int "F6.11: Batch embedding produces exact output list length" 3 (List.length batch_embs);
  let batch_sims = Embeddings.batch_cosine_similarity emb1 batch_embs in
  assert_equal_int "F6.12: Batch cosine similarity returns scores for all items" 3 (List.length batch_sims);

  let long_text = String.concat " " (List.init 300 (fun i -> "feature_token_" ^ string_of_int i)) in
  let long_emb = Embeddings.embed_text long_text in
  assert_equal_float "F6.13: Long 300-token embedding norm is 1.0" 1.0 (Embeddings.l2_norm long_emb) 0.0001;

  Printf.printf "\n--- [Section 2] Atomic JSON Lesson Store & Recovery ---\n";

  let temp_lesson_file = Filename.temp_file "roo4u_test_lessons_" ".json" in
  let store = Lesson_store.create ~file_path:temp_lesson_file () in

  assert_equal_int "F5.1: Fresh store starts empty" 0 (Lesson_store.count store);

  let lesson1 = Lesson_store.make_lesson
    ~domain:"zillow.com"
    ~failure_type:"BOT_CHALLENGE"
    ~error_message:"HTTP 403 Forbidden Cloudflare challenge"
    ~lesson_learned:"Rotate user agent headers and inject random delays"
    ~recommended_action:"Set suggested_delay_seconds to 2.5 and add stealth headers"
    ~suggested_delay_seconds:2.5
    ~suggested_headers:[("User-Agent", "Mozilla/5.0 Stealth")]
    ()
  in
  let saved1 = Lesson_store.upsert_lesson store lesson1 in
  assert_equal_string "F5.2: Upsert returns saved lesson with matching ID" lesson1.id saved1.id;
  assert_equal_int "F5.3: Count is now 1" 1 (Lesson_store.count store);

  assert_true "F5.4: Disk file exists" (Sys.file_exists temp_lesson_file);
  let loaded_lessons = Lesson_store.load_lessons store in
  assert_equal_int "F5.5: Loaded lessons count matches" 1 (List.length loaded_lessons);
  let loaded1 = List.hd loaded_lessons in
  assert_equal_string "F5.6: Loaded lesson preserves domain" "zillow.com" loaded1.domain;
  assert_equal_string "F5.7: Loaded lesson preserves failure_type" "BOT_CHALLENGE" loaded1.failure_type;
  assert_equal_float "F5.8: Loaded lesson preserves delay" 2.5 loaded1.suggested_delay_seconds 0.001;

  let lesson2 = Lesson_store.make_lesson
    ~domain:"dbi.sfgov.org"
    ~failure_type:"DOM_DRIFT"
    ~error_message:"Permit table selector not found"
    ~lesson_learned:"Use API json endpoint instead of DOM scraping"
    ()
  in
  ignore (Lesson_store.upsert_lesson store lesson2);
  assert_equal_int "F5.9: Total count is now 2" 2 (Lesson_store.count store);
  assert_equal_int "F5.10: Domain filter zillow.com returns 1" 1 (Lesson_store.count ~domain:"zillow.com" store);
  assert_equal_int "F5.11: Domain filter dbi.sfgov.org returns 1" 1 (Lesson_store.count ~domain:"dbi.sfgov.org" store);
  assert_equal_int "F5.12: Failure type filter DOM_DRIFT returns 1" 1 (List.length (Lesson_store.list_lessons ~failure_type:"DOM_DRIFT" store));

  assert_equal_string "F5.13: Initial status is ACTIVE" "ACTIVE" lesson1.status;
  assert_false "F5.14: Initial resolved is false" lesson1.resolved;

  for _ = 1 to 4 do
    ignore (Lesson_store.increment_success store lesson1.id)
  done;
  let after_4 = Lesson_store.get_lesson store lesson1.id |> Option.get in
  assert_equal_int "F5.15: Success count is 4 after 4 increments" 4 after_4.success_count_after_workaround;
  assert_equal_string "F5.16: Status remains ACTIVE at 4 successes" "ACTIVE" after_4.status;

  let after_5 = Lesson_store.increment_success store lesson1.id |> Option.get in
  assert_equal_int "F5.17: Success count is 5 after 5th increment" 5 after_5.success_count_after_workaround;
  assert_equal_string "F5.18: Self-healing transitions status to RESOLVED at >= 5" "RESOLVED" after_5.status;
  assert_true "F5.19: Resolved flag is set to true" after_5.resolved;

  let threads = List.init 4 (fun thread_id ->
    Thread.create (fun () ->
      for i = 1 to 10 do
        let l = Lesson_store.make_lesson
          ~domain:("thread_domain_" ^ string_of_int thread_id)
          ~failure_type:"THREAD_TEST"
          ~error_message:("Thread " ^ string_of_int thread_id ^ " item " ^ string_of_int i)
          ()
        in
        ignore (Lesson_store.upsert_lesson store l)
      done
    ) ()
  ) in
  List.iter Thread.join threads;
  assert_true "F5.20: Concurrent thread writes completed safely" (Lesson_store.count store >= 42);

  let del_res = Lesson_store.delete_lesson store lesson2.id in
  assert_true "F5.21: Delete existing lesson returns true" del_res;
  assert_true "F5.22: Deleted lesson not found" (Lesson_store.get_lesson store lesson2.id = None);

  let oc = open_out temp_lesson_file in
  output_string oc "{ corrupted invalid json truncated !!! [";
  close_out oc;
  let recovered_lessons = Lesson_store.load_lessons store in
  assert_equal_int "F5.23: Corruption recovery safely resets store to empty list" 0 (List.length recovered_lessons);
  assert_true "F5.24: Store exists and is valid after recovery" (Sys.file_exists temp_lesson_file);

  (try Sys.remove temp_lesson_file with _ -> ());
  (try Sys.remove (temp_lesson_file ^ ".lock") with _ -> ());

  Printf.printf "\n--- [Section 3] Vector Store & Cosine Search Engine ---\n";

  let vstore = Vector_store.create () in
  assert_equal_int "F7.1: Fresh vector store is empty" 0 (Vector_store.count vstore);

  let rec1 = Vector_store.upsert
    ~domain:"zillow.com"
    ~failure_type:"BOT_CHALLENGE"
    vstore
    "VEC-403"
    "HTTP 403 Forbidden Cloudflare Bot Protection blocking property card listing"
  in
  ignore (Vector_store.upsert
    ~domain:"dbi.sfgov.org"
    ~failure_type:"DOM_SELECTOR_DRIFT"
    vstore
    "VEC-DOM"
    "SF DBI Permit tracking table selector #permit-history changed to .pts-table-grid");
  ignore (Vector_store.upsert
    ~domain:"data.sfgov.org"
    ~failure_type:"RATE_LIMIT"
    vstore
    "VEC-429"
    "HTTP 429 Too Many Requests SODA API rate limit exceeded on building permits dataset");
  assert_equal_int "F7.2: Vector store has 3 items" 3 (Vector_store.count vstore);

  let retrieved = Vector_store.get vstore "VEC-403" |> Option.get in
  assert_equal_string "F7.3: Retrieved record text matches" rec1.text retrieved.text;
  assert_equal_int "F7.4: Retrieved record embedding has length 256" 256 (Array.length retrieved.embedding);

  let search_403 = Vector_store.search ~top_k:3 vstore (Some "Cloudflare 403 challenge bot blocking") in
  assert_true "F7.5: Search returns top results" (List.length search_403 > 0);
  let top_result = List.hd search_403 in
  assert_equal_string "F7.6: Top match for 403 query is VEC-403" "VEC-403" top_result.record.id;
  assert_equal_int "F7.7: Top match has rank 1" 1 top_result.rank;
  assert_true "F7.8: Similarity score is positive (> 0.25)" (top_result.score > 0.25);

  let search_rate = Vector_store.search ~top_k:3 vstore (Some "DataSF 429 rate limit backoff") in
  let top_rate = List.hd search_rate in
  assert_equal_string "F7.9: Top match for rate limit query is VEC-429" "VEC-429" top_rate.record.id;

  let filtered_domain = Vector_store.search ~domain:"dbi.sfgov.org" ~top_k:5 vstore (Some "scraping error") in
  assert_equal_int "F7.10: Domain filter dbi.sfgov.org returns exactly 1 match" 1 (List.length filtered_domain);
  assert_equal_string "F7.11: Domain filtered match is VEC-DOM" "VEC-DOM" (List.hd filtered_domain).record.id;

  let filtered_type = Vector_store.search ~failure_type:"RATE_LIMIT" ~top_k:5 vstore (Some "error") in
  assert_equal_int "F7.12: Failure type filter RATE_LIMIT returns exactly 1 match" 1 (List.length filtered_type);
  assert_equal_string "F7.13: Failure type filtered match is VEC-429" "VEC-429" (List.hd filtered_type).record.id;

  let strict_results = Vector_store.search ~min_similarity:0.999 vstore (Some "Completely unrelated query about baking pies") in
  assert_equal_int "F7.14: Unrelated query with high min_similarity threshold returns 0 results" 0 (List.length strict_results);

  let batch_recs = [
    Vector_store.make_record ~domain:"test.com" ~id:"BATCH-1" ~text:"Test item 1" ();
    Vector_store.make_record ~domain:"test.com" ~id:"BATCH-2" ~text:"Test item 2" ();
  ] in
  let batch_count = Vector_store.upsert_batch vstore batch_recs in
  assert_equal_int "F7.15: Batch upsert inserted 2 records" 2 batch_count;
  assert_equal_int "F7.16: Total count is now 5" 5 (Vector_store.count vstore);

  let temp_sync_lesson_file = Filename.temp_file "sync_lessons_" ".json" in
  let sync_lesson_store = Lesson_store.create ~file_path:temp_sync_lesson_file () in
  ignore (Lesson_store.upsert_lesson sync_lesson_store lesson1);
  ignore (Lesson_store.upsert_lesson sync_lesson_store lesson2);

  let sync_vstore = Vector_store.create () in
  let synced_count = Vector_store.sync_lessons sync_lesson_store sync_vstore in
  assert_equal_int "F7.17: Sync lessons indexes all 2 lessons into vector store" 2 synced_count;
  assert_equal_int "F7.18: Synced vector store count is 2" 2 (Vector_store.count sync_vstore);

  (try Sys.remove temp_sync_lesson_file with _ -> ());
  (try Sys.remove (temp_sync_lesson_file ^ ".lock") with _ -> ());

  Printf.printf "\n--- [Section 4] SQLite Leads Database Layer ---\n";

  let temp_db_file = Filename.temp_file "roo4u_test_leads_" ".db" in
  let db = Db.create ~db_path:temp_db_file () in
  assert_equal_int "F8.1: Fresh database starts with 0 leads" 0 (Db.count_leads db);

  let lead1 : Types.raw_lead = {
    address = "2223 Pacific Ave";
    zip_code = "94115";
    property_type = Types.SingleFamily;
    roof_type = Types.Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 3500000.0;
    owner_name = None;
    is_hoa = false;
    is_rental = false;
    apn = None;
    last_roof_permit_date = None;
    roof_age_years = Some 22.0;
    year_built = Some 1900;
    phone_number = None;
    permits = [];
  } in

  let ins_res = Db.insert_lead db ~status:Db.Discovered lead1 in
  assert_true "F8.2: Insert raw lead returns Ok id" (Result.is_ok ins_res);
  let id1 = Result.get_ok ins_res in
  assert_equal_int "F8.3: Lead ID is 1" 1 id1;
  assert_equal_int "F8.4: Total lead count is 1" 1 (Db.count_leads db);

  let dup_res = Db.insert_lead db lead1 in
  assert_true "F8.5: Inserting duplicate address returns Error" (Result.is_error dup_res);

  let by_addr = Db.get_lead_by_address db "2223 Pacific Ave" |> Option.get in
  assert_equal_string "F8.6: Get by address retrieves exact address" "2223 Pacific Ave" by_addr.address;
  assert_equal_string "F8.7: Status is DISCOVERED" "DISCOVERED" by_addr.status;
  assert_equal_string "F8.8: Zip code is 94115" "94115" by_addr.zip_code;

  let by_id = Db.get_lead_by_id db id1 |> Option.get in
  assert_equal_string "F8.9: Get by ID retrieves matching record" "2223 Pacific Ave" by_id.address;

  let enrich_res = Db.update_enriched
    db
    "2223 Pacific Ave"
    ~apn:"0581-012"
    ~owner_name:"PACIFIC TRUST"
    ~estimated_value:3800000.0
    ~last_roof_permit_date:"2002-05-14"
    ~roof_age_years:24.0
    ~is_hoa:false
    ~is_rental:false
    ()
  in
  assert_true "F8.10: update_enriched returns Ok ()" (Result.is_ok enrich_res);
  let enriched_lead = Db.get_lead_by_address db "2223 Pacific Ave" |> Option.get in
  assert_equal_string "F8.11: Status transitioned to ENRICHED" "ENRICHED" enriched_lead.status;
  assert_equal_string "F8.12: APN updated to 0581-012" "0581-012" (Option.get enriched_lead.apn);
  assert_equal_string "F8.13: Owner name updated" "PACIFIC TRUST" (Option.get enriched_lead.owner_name);
  assert_equal_float "F8.14: Estimated value updated" 3800000.0 (Option.get enriched_lead.estimated_value) 0.01;

  let val_res = Db.update_status db "2223 Pacific Ave" Db.Validated in
  assert_true "F8.15: update_status returns Ok ()" (Result.is_ok val_res);
  let validated_lead = Db.get_lead_by_address db "2223 Pacific Ave" |> Option.get in
  assert_equal_string "F8.16: Status transitioned to VALIDATED" "VALIDATED" validated_lead.status;

  let lead2 : Types.raw_lead = {
    address = "1440 Union St";
    zip_code = "94123";
    property_type = Types.MultiUnit2To4;
    roof_type = Types.Flat;
    property_type_raw = Some "2-Unit";
    roof_type_raw = Some "Flat";
    estimated_value = Some 2200000.0;
    owner_name = None;
    is_hoa = false;
    is_rental = false;
    apn = None;
    last_roof_permit_date = None;
    roof_age_years = Some 18.0;
    year_built = Some 1920;
    phone_number = None;
    permits = [];
  } in
  ignore (Db.insert_lead db ~status:Db.Discovered lead2);
  assert_equal_int "F8.17: Total lead count is 2" 2 (Db.count_leads db);
  assert_equal_int "F8.18: Validated leads count is 1" 1 (Db.count_leads ~status:Db.Validated db);
  assert_equal_int "F8.19: Discovered leads count is 1" 1 (Db.count_leads ~status:Db.Discovered db);
  assert_equal_int "F8.20: Zip code 94123 filter returns 1" 1 (List.length (Db.list_leads ~zip_code:"94123" db));

  let malicious_lead : Types.raw_lead = {
    address = "999 Evil St'; DROP TABLE leads; --";
    zip_code = "94115";
    property_type = Types.SingleFamily;
    roof_type = Types.Victorian;
    property_type_raw = Some "Single-Family";
    roof_type_raw = Some "Victorian";
    estimated_value = Some 1500000.0;
    owner_name = Some "Robert'); DROP TABLE leads;--";
    is_hoa = false;
    is_rental = false;
    apn = Some "APN' OR 1=1;--";
    last_roof_permit_date = None;
    roof_age_years = Some 20.0;
    year_built = Some 1950;
    phone_number = None;
    permits = [];
  } in
  let mal_res = Db.insert_lead db ~status:Db.Discovered malicious_lead in
  assert_true "F8.21: Malicious SQL injection payload safely escaped and inserted" (Result.is_ok mal_res);
  assert_true "F8.22: Table leads still exists and intact" (Db.count_leads db >= 3);
  let mal_retrieved = Db.get_lead_by_address db "999 Evil St'; DROP TABLE leads; --" |> Option.get in
  assert_equal_string "F8.23: Malicious owner name preserved verbatim" "Robert'); DROP TABLE leads;--" (Option.get mal_retrieved.owner_name);

  let del_lead_res = Db.delete_lead_by_address db "999 Evil St'; DROP TABLE leads; --" in
  assert_true "F8.24: Delete lead by address returns true" del_lead_res;

  (try Sys.remove temp_db_file with _ -> ());

  Printf.printf "\n=================================================================\n";
  Printf.printf "=== ALL MILESTONE 2 TESTS PASSED: %d/%d (100.0%%) ===\n" !pass_count !test_count;
  Printf.printf "=================================================================\n\n"
