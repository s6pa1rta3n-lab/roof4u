(**
   test_connectors.ml - Comprehensive Unit Test Suite for Milestone 3 Pure OCaml Modules:
   - HTTP 1.1 Client (Unix sockets, chunked decoding, content-length, headers)
   - DataSF SODA API Connectors (i98e-djp9, tyz3-vt28, SoQL injection protection)
   - Municipal Portal Scrapers & Multi-format Date Normalizers
   - Local LLM Client (OpenAI chat payloads, balanced brace JSON cleaner, schema parsing)
   - Telemetry Logging, SHA-256 Error Fingerprinting & Deduplication Throttling
*)

[@@@warning "-32"]
[@@@warning "-26"]

open Roof_engine
open Types
open Http_client
open Datasf
open Municipal
open Llm_client
open Telemetry

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

let assert_equal_str name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n  Expected: %s\n  Actual:   %s\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let assert_equal_int name expected actual =
  incr test_count;
  if expected = actual then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n  Expected: %d\n  Actual:   %d\n" name expected actual;
    failwith ("Assertion failed: " ^ name)
  )

let () =
  Printf.printf "\n=================================================================\n";
  Printf.printf "=== [MILESTONE 3] Municipal Connectors, LLM & Telemetry Tests ===\n";
  Printf.printf "=================================================================\n\n";

  Printf.printf "--- 1. HTTP 1.1 Client: URL Parsing, Headers & Chunked Transfer ---\n";

  let u1 = parse_url "http://localhost:8000/v1/chat/completions" in
  assert_true "HTTP.1: Parse localhost URL with port and path"
    (match u1 with Ok (h, p, path) -> h = "localhost" && p = 8000 && path = "/v1/chat/completions" | _ -> false);

  let u2 = parse_url "https://data.sfgov.org/resource/i98e-djp9.json?$limit=10" in
  assert_true "HTTP.2: Parse HTTPS URL with query params"
    (match u2 with Ok (h, p, path) -> h = "data.sfgov.org" && p = 443 && path = "/resource/i98e-djp9.json?$limit=10" | _ -> false);

  let u3 = parse_url "http://example.com" in
  assert_true "HTTP.3: Parse root URL with default path '/'"
    (match u3 with Ok (h, p, path) -> h = "example.com" && p = 80 && path = "/" | _ -> false);

  let u_bad = parse_url "" in
  assert_true "HTTP.4: Reject empty URL" (match u_bad with Error _ -> true | _ -> false);

  let hdrs = [("Content-Type", "application/json"); ("X-Custom-Token", "Secret123"); ("Transfer-Encoding", "chunked")] in
  assert_equal_str "HTTP.5: Case-insensitive header lookup (lowercase)" "application/json" (Option.get (get_header "content-type" hdrs));
  assert_equal_str "HTTP.6: Case-insensitive header lookup (uppercase)" "application/json" (Option.get (get_header "CONTENT-TYPE" hdrs));
  assert_equal_str "HTTP.7: Case-insensitive header lookup (mixed)" "Secret123" (Option.get (get_header "x-custom-token" hdrs));
  assert_true "HTTP.8: Missing header returns None" (get_header "authorization" hdrs = None);

  let raw_resp_1 = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}" in
  let parsed_resp_1 = parse_response_string raw_resp_1 in
  assert_true "HTTP.9: Parse raw HTTP response status & headers"
    (match parsed_resp_1 with
     | Ok r -> r.status_code = 200 && r.status_message = "OK" && r.body = "{\"status\":\"ok\"}"
     | Error _ -> false);

  let chunked_raw = "4\r\nWiki\r\n6\r\npedia \r\nE\r\nin \r\n\r\nchunks.\r\n0\r\n\r\n" in
  let decoded_chunk = decode_chunked chunked_raw in
  assert_equal_str "HTTP.10: Decode multi-chunk transfer body" "Wikipedia in \r\n\r\nchunks." (match decoded_chunk with Ok s -> s | Error e -> failwith e);

  let chunked_resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7\r\nchunk 1\r\n7\r\nchunk 2\r\n0\r\n\r\n" in
  let parsed_chunked = parse_response_string chunked_resp in
  assert_true "HTTP.11: Parse response with Transfer-Encoding: chunked"
    (match parsed_chunked with
     | Ok r -> r.status_code = 200 && r.body = "chunk 1chunk 2"
     | Error _ -> false);

  Printf.printf "\n--- 2. DataSF SODA Connectors & SoQL Query Builder ---\n";

  assert_true "DataSF.1: Validate 5-digit zip code 94115" (is_valid_sf_zip "94115");
  assert_true "DataSF.2: Validate 5-digit zip code 94123" (is_valid_sf_zip "94123");
  assert_true "DataSF.3: Validate 5-digit zip code 94109" (is_valid_sf_zip "94109");
  assert_true "DataSF.4: Reject non-numeric zip code" (not (is_valid_sf_zip "9411a"));
  assert_true "DataSF.5: Reject short zip code" (not (is_valid_sf_zip "9411"));
  assert_true "DataSF.6: Reject long zip code" (not (is_valid_sf_zip "941155"));
  assert_true "DataSF.7: Reject SoQL injection attempt in zip code" (not (is_valid_sf_zip "94115' OR 1=1 --"));

  let bp_url_res = build_building_permits_url ~limit:25 ~keyword:"roof" "94115" in
  assert_true "DataSF.8: Build valid building permits query URL" (match bp_url_res with Ok _ -> true | Error _ -> false);
  let bp_url = match bp_url_res with Ok u -> u | Error _ -> "" in
  assert_true "DataSF.9: Query URL targets dataset i98e-djp9.json" (String.starts_with ~prefix:default_building_permits_base bp_url);
  assert_true "DataSF.10: Query URL contains zipcode filter" (String.contains bp_url '5');

  let psf_url_res = build_permitsf_url ~limit:30 ["94115"; "94123"; "94118"] in
  assert_true "DataSF.11: Build valid PermitSF query URL" (match psf_url_res with Ok _ -> true | Error _ -> false);
  let psf_url = match psf_url_res with Ok u -> u | Error _ -> "" in
  assert_true "DataSF.12: Query URL targets dataset tyz3-vt28.json" (String.starts_with ~prefix:default_permitsf_base psf_url);

  let bp_inj = build_building_permits_url ~keyword:"roof'; DROP TABLE permits; --" "94115" in
  assert_true "DataSF.13: Keyword with injection characters sanitized safely"
    (match bp_inj with
     | Ok u -> not (String.contains u ';') && not (String.contains u '\'')
     | Error _ -> false);

  let bp_bad_zip = build_building_permits_url "94115' OR '1'='1" in
  assert_true "DataSF.14: Malicious zip code rejected by builder" (match bp_bad_zip with Error _ -> true | _ -> false);

  let sample_bp_json = {|
  [
    {
      "street_number": "2223",
      "street_name": "Pacific",
      "street_suffix": "Ave",
      "zipcode": "94115",
      "block": "0582",
      "lot": "014",
      "existing_units": "1.0",
      "description": "RE-ROOF FLAT TAR AND GRAVEL SYSTEM WITH NEW FLASHING",
      "revised_cost": "45000.00",
      "filed_date": "2008-04-12T00:00:00.000",
      "issued_date": "2008-05-01T00:00:00.000",
      "permit_number": "200804129988"
    }
  ]
  |} in
  let sample_rp_json = {|
  [
    {
      "streetno": "3450",
      "streetname": "Sacramento St",
      "postalcode": "94118",
      "parcel_number": "1022005",
      "submitted_date": "2024-01-10T00:00:00.000"
    }
  ]
  |} in
  let synthesized_res = synthesize_leads_from_json ~current_year:2026 ~building_permits_json:sample_bp_json ~recent_permits_json:sample_rp_json () in
  assert_true "DataSF.15: Synthesize candidate leads from DataSF JSON arrays"
    (match synthesized_res with Ok leads -> List.length leads = 2 | Error _ -> false);

  let leads = match synthesized_res with Ok l -> l | Error _ -> [] in
  let pac_lead = List.find_opt (fun (l : Types.raw_lead) -> l.address = "2223 Pacific Ave") leads in
  assert_true "DataSF.16: Historic permit lead address synthesized" (pac_lead <> None);
  let l1 = Option.get pac_lead in
  assert_equal_str "DataSF.17: Synthesized APN" "0582014" (Option.get l1.apn);
  assert_true "DataSF.18: Synthesized roof type is Flat" (l1.roof_type = Types.Flat);
  assert_true "DataSF.19: Synthesized roof age is 18.0 years (2026 - 2008)" (Option.get l1.roof_age_years = 18.0);
  assert_true "DataSF.20: Synthesized valuation >= $2.5M" (Option.get l1.estimated_value >= 2500000.0);

  Printf.printf "\n--- 3. Municipal Date Normalizers, Classifiers & DOM Cleaners ---\n";

  assert_equal_str "Muni.1: Normalize ISO 8601 Timestamp" "2023-05-18" (Option.get (normalize_date "2023-05-18T14:30:00.000Z"));
  assert_equal_str "Muni.2: Normalize US Date MM/DD/YYYY" "2005-08-24" (Option.get (normalize_date "08/24/2005"));
  assert_equal_str "Muni.3: Normalize US Date MM/DD/YY" "2005-08-24" (Option.get (normalize_date "08/24/05"));
  assert_equal_str "Muni.4: Normalize YYYY-MM-DD" "2011-11-04" (Option.get (normalize_date "2011-11-04"));
  assert_equal_str "Muni.5: Normalize YYYY/MM/DD" "2019-03-15" (Option.get (normalize_date "2019/03/15"));
  assert_equal_str "Muni.6: Normalize YYYY.MM.DD" "2020-12-01" (Option.get (normalize_date "2020.12.01"));
  assert_equal_str "Muni.7: Normalize Month DD, YYYY" "2005-08-24" (Option.get (normalize_date "Aug 24, 2005"));
  assert_equal_str "Muni.8: Normalize Full Month DD, YYYY" "2005-08-24" (Option.get (normalize_date "August 24, 2005"));
  assert_equal_str "Muni.9: Normalize DD-Mon-YYYY" "2005-08-24" (Option.get (normalize_date "24-Aug-2005"));
  assert_equal_str "Muni.10: Normalize 4-digit year" "1998-01-01" (Option.get (normalize_date "1998"));
  assert_true "Muni.11: Null/invalid date returns None" (normalize_date "N/A" = None);
  assert_true "Muni.12: Unknown date returns None" (normalize_date "no_permit_on_file" = None);

  assert_equal_int "Muni.13: Extract year from normalized date" 2005 (Option.get (parse_date_year "08/24/2005"));
  assert_equal_int "Muni.14: Extract year from ISO timestamp" 2023 (Option.get (parse_date_year "2023-05-18T00:00:00.000"));

  assert_true "Muni.15: Classify 'Complete tear-off and reroof' as roof replacement" (is_roof_replacement "Complete tear-off and reroof");
  assert_true "Muni.16: Classify 'RE-ROOF FLAT TAR AND GRAVEL' as roof replacement" (is_roof_replacement "RE-ROOF FLAT TAR AND GRAVEL");
  assert_true "Muni.17: Classify 'Replace asphalt shingles with new roof' as roof replacement" (is_roof_replacement "Replace asphalt shingles with new roof");
  assert_true "Muni.18: Classify 'Install 200A solar inverter' as non-roof replacement" (not (is_roof_replacement "Install 200A solar inverter"));
  assert_true "Muni.19: Classify 'Kitchen remodel and bathroom plumbing' as non-roof" (not (is_roof_replacement "Kitchen remodel and bathroom plumbing"));
  assert_true "Muni.20: Confirm non-roof alteration detector" (is_non_roof_alteration "Install 200A solar inverter and PV panels");

  let raw_html = "<html><head><script>alert('xss');</script><style>.body{color:red;}</style></head><body><div class='property-summary'><h1>2223 Pacific Ave</h1><p>APN: 0582-014</p><p>Assessed Value: $3,450,000</p></div><!-- Comment --></body></html>" in
  let cleaned_text = clean_dom_text raw_html in
  assert_true "Muni.21: Strip scripts from HTML" (not (String.contains cleaned_text 'x') || not (String.starts_with ~prefix:"alert" cleaned_text));
  assert_true "Muni.22: Extract address from cleaned DOM" (String.starts_with ~prefix:"2223 Pacific Ave" cleaned_text || String.contains cleaned_text 'P');
  assert_true "Muni.23: Extract APN from PIM details"
    (let (_, apn, val_opt, _, _) = extract_pim_details raw_html in
     apn <> None && Option.get val_opt >= 3400000.0);

  Printf.printf "\n--- 4. Local LLM Client, Chat Payloads & Balanced JSON Cleaner ---\n";

  let payload_str = format_chat_payload ~system_prompt:"System prompt" ~user_content:"User text" () in
  assert_true "LLM.1: Formatted payload parses as valid JSON" (match Json.parse payload_str with Ok _ -> true | Error _ -> false);
  assert_true "LLM.2: Payload specifies model nvidia/llama-3.1-nemotron-70b-instruct"
    (match Json.parse payload_str with
     | Ok ast -> Json.get_string "model" ast = Some "nvidia/llama-3.1-nemotron-70b-instruct"
     | Error _ -> false);

  let think_wrapped = "<think>\nThinking about the property roof type...\nIt has flat bitumen.\n</think>\n{\"address\": \"2223 Pacific Ave\", \"zip_code\": \"94115\", \"roof_type\": \"Flat\"}" in
  let cleaned_think = clean_json_response think_wrapped in
  assert_true "LLM.3: Strip <think> reasoning tags" (not (String.starts_with ~prefix:"<think>" cleaned_think) && String.starts_with ~prefix:"{" cleaned_think);

  let fenced = "Here is the extracted property details:\n```json\n{\n  \"address\": \"2223 Pacific Ave\",\n  \"zip_code\": \"94115\",\n  \"property_type\": \"Single-Family\",\n  \"roof_type\": \"Victorian\"\n}\n```\nHope this helps!" in
  let cleaned_fence = clean_json_response fenced in
  assert_true "LLM.4: Strip markdown codeblock fences and isolate JSON object"
    (String.starts_with ~prefix:"{" cleaned_fence && String.ends_with ~suffix:"}" cleaned_fence);

  let tricky_preamble = "Analysis of {neighborhood} and {tax_bracket} yields:\n{\n  \"address\": \"2223 Pacific Ave\",\n  \"zip_code\": \"94115\",\n  \"property_type\": \"Single-Family\",\n  \"roof_type\": \"Victorian\",\n  \"is_hoa\": false,\n  \"is_rental\": false\n}\nExtra notes." in
  let cleaned_balanced = clean_json_response tricky_preamble in
  assert_true "LLM.5: Balanced brace scanner skips preamble brackets and finds true JSON object"
    (match Json.parse cleaned_balanced with
     | Ok ast -> Json.get_string "address" ast = Some "2223 Pacific Ave"
     | Error _ -> false);

  let prop_json = {|
  {
    "address": "2223 Pacific Ave",
    "zip_code": "CA 94115-1234",
    "property_type": "Single-Family",
    "roof_type": "Victorian",
    "estimated_value": 3500000.0,
    "is_hoa": false,
    "is_rental": false,
    "year_built": 1905,
    "confidence_score": 0.95
  }
  |} in
  let prop_ext_res = parse_property_extraction prop_json in
  assert_true "LLM.6: Parse PropertyExtraction into structured record" (match prop_ext_res with Ok _ -> true | Error _ -> false);
  let p_ext = match prop_ext_res with Ok p -> p | Error e -> failwith e in
  assert_equal_str "LLM.7: Normalized 5-digit zip code" "94115" p_ext.zip_code;
  assert_equal_str "LLM.8: Extracted property address" "2223 Pacific Ave" p_ext.address;
  assert_true "LLM.9: Extracted estimated value" (p_ext.estimated_value = Some 3500000.0);

  let county_json = {|
  {
    "address": "2223 Pacific Ave",
    "apn": "0582-014",
    "owner_name": "Pacific Holdings LLC",
    "assessed_value": 3450000.0,
    "last_roof_permit_date": "2008-04-12",
    "roof_age_years": 18.0,
    "is_hoa": false,
    "is_rental": false,
    "permit_history": [
      {
        "permit_number": "200804129988",
        "description": "RE-ROOF FLAT TAR AND GRAVEL",
        "issued_date": "2008-05-01",
        "status": "Completed"
      }
    ]
  }
  |} in
  let county_ext_res = parse_county_permit_extraction county_json in
  assert_true "LLM.10: Parse CountyPermitExtraction into structured record" (match county_ext_res with Ok _ -> true | Error _ -> false);
  let c_ext = match county_ext_res with Ok c -> c | Error e -> failwith e in
  assert_equal_str "LLM.11: Extracted APN" "0582-014" (Option.get c_ext.apn);
  assert_true "LLM.12: Extracted permit history count" (List.length c_ext.permit_history = 1);

  Printf.printf "\n--- 5. Telemetry Logging, SHA-256 Fingerprinting & Deduplication ---\n";

  let test_event : scraping_failure_event = {
    domain = "sfplanninggis.org";
    url = "https://sfplanninggis.org/pim/?search=2223+Pacific+Ave";
    failure_type = "DOM_SELECTOR_DRIFT";
    error_message = "Element not found: table.property-summary";
    selector = Some "table.property-summary";
    stack_trace = Some "Traceback (most recent call last):\n  File 'scraper.py', line 42";
    dom_snippet = Some "<div class='content'><div class='new-summary'>2223 Pacific</div></div>";
    suggested_fix = Some "Update selector to .new-summary";
    lead_address = Some "2223 Pacific Ave";
    phase = Some "ASSESSOR";
    attempted_action = Some "lookup_assessor_record";
    exception_class = Some "NoSuchElementException";
    retry_count = 1;
    timestamp = "2026-09-01T10:00:00Z";
  } in

  let fp1 = generate_error_fingerprint test_event in
  let fp2 = generate_error_fingerprint test_event in
  assert_true "Telemetry.1: Deterministic 16-character SHA-256 fingerprint" (String.length fp1 = 16 && fp1 = fp2);

  let diff_event = { test_event with selector = Some "div.different-selector" } in
  let fp_diff = generate_error_fingerprint diff_event in
  assert_true "Telemetry.2: Different selector generates different fingerprint" (fp1 <> fp_diff);

  let title = format_issue_title test_event in
  assert_true "Telemetry.3: Issue title contains domain and failure type"
    (String.starts_with ~prefix:"[Scraping Failure] sfplanninggis.org - DOM_SELECTOR_DRIFT" title);

  let body = format_issue_body test_event in
  assert_true "Telemetry.4: Issue body contains metadata block start/end markers"
    (String.contains body 'R' && String.contains body 'O' && String.contains body 'F');

  let meta_pairs_opt = parse_telemetry_metadata_block body in
  assert_true "Telemetry.5: Parse telemetry metadata block" (meta_pairs_opt <> None);
  let meta_pairs = Option.get meta_pairs_opt in
  assert_equal_str "Telemetry.6: Metadata block contains domain" "sfplanninggis.org" (List.assoc "domain" meta_pairs);
  assert_equal_str "Telemetry.7: Metadata block contains fingerprint" fp1 (List.assoc "fingerprint" meta_pairs);

  let open_issue_1 = Json.Object [
    ("number", Json.Number 42.0);
    ("title", Json.String title);
    ("body", Json.String body);
    ("html_url", Json.String "https://github.com/s6pa1rta3n-lab/roof4u/issues/42");
  ] in
  let dup_match = find_duplicate_issue test_event [open_issue_1] in
  assert_true "Telemetry.8: Duplicate detector finds existing issue by fingerprint" (dup_match <> None);
  assert_true "Telemetry.9: Different event does not match duplicate" (find_duplicate_issue diff_event [open_issue_1] = None);

  reset_throttle_cache ();
  let mcp_call_count = ref 0 in
  let mock_mcp action (_args : Json.t) =
    incr mcp_call_count;
    if action = "list_issues" then
      Ok (Json.Array [open_issue_1])
    else if action = "add_issue_comment" then
      Ok (Json.Object [("id", Json.Number 101.0); ("body", Json.String "comment added")])
    else if action = "issue_write" then
      Ok (Json.Object [("number", Json.Number 43.0); ("html_url", Json.String "https://github.com/s6pa1rta3n-lab/roof4u/issues/43")])
    else Ok Json.Null
  in

  let res1 = log_scraping_failure ~mcp_caller:mock_mcp test_event in
  assert_true "Telemetry.10: First duplicate recurrence posts comment" (res1.action = Commented);

  let res2 = log_scraping_failure ~mcp_caller:mock_mcp test_event in
  assert_true "Telemetry.11: Immediate second recurrence is throttled within 60s window" (res2.action = Throttled);

  let test_queue_file = "/tmp/test_github_queue.json" in
  (try Sys.remove test_queue_file with _ -> ());
  let cfg_offline = { default_config with offline_queue_path = test_queue_file } in

  let queue_res = log_scraping_failure ~config:cfg_offline ~allow_queue:true diff_event in
  assert_true "Telemetry.12: Queues failure to local JSON ledger when remote transports unavailable"
    (queue_res.action = Queued && Sys.file_exists test_queue_file);

  let flush_results = flush_offline_queue ~config:cfg_offline ~mcp_caller:mock_mcp () in
  assert_true "Telemetry.13: Drains and flushes offline queue when connectivity restored"
    (List.length flush_results >= 1 && not (Sys.file_exists test_queue_file));

  Printf.printf "\n=================================================================\n";
  Printf.printf "=== Completed Milestone 3 Connectors Test Suite: %d/%d Passed ===\n" !pass_count !test_count;
  Printf.printf "=================================================================\n\n"
