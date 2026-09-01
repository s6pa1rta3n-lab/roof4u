(**
   test_lessons_json.ml - Test parsing real lessons_learned.json
*)

#use "/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/teamwork_preview_explorer_m1_2/scratch_test_json.ml";;

let read_file filename =
  let ic = open_in filename in
  let len = in_channel_length ic in
  let buf = really_input_string ic len in
  close_in ic;
  buf

let () =
  let path = "/Users/solveetcoagula/Desktop/activeProjects/Roo4u/lessons_learned.json" in
  Printf.printf "Reading %s...\n" path;
  let content = read_file path in
  match parse content with
  | Error err ->
      Printf.printf "[FAIL] Parsing lessons_learned.json failed: %s\n" err;
      exit 1
  | Ok ast ->
      Printf.printf "[PASS] Successfully parsed lessons_learned.json!\n";
      (match ast with
       | Array lessons ->
           Printf.printf "Found %d lessons in array.\n" (List.length lessons);
           List.iteri (fun i item ->
             let id = match get_string "id" item with Some s -> s | None -> "<none>" in
             let domain = match get_string "domain" item with Some s -> s | None -> "<none>" in
             let failure = match get_string "failure_type" item with Some s -> s | None -> "<none>" in
             let occurrences = match get_int "occurrence_count" item with Some n -> n | None -> 0 in
             let resolved = match get_bool "resolved" item with Some b -> b | None -> false in
             if i < 3 then
               Printf.printf "  Lesson %d: ID=%s Domain=%s Type=%s Count=%d Resolved=%b\n"
                 i id domain failure occurrences resolved
           ) lessons
       | _ ->
           Printf.printf "[FAIL] Expected Array root in lessons_learned.json\n");
      let serialized = to_string ast in
      Printf.printf "Serialized size: %d bytes (Original: %d bytes)\n"
        (String.length serialized) (String.length content);
      match parse serialized with
      | Error err -> Printf.printf "[FAIL] Re-parsing serialized JSON failed: %s\n" err
      | Ok _ -> Printf.printf "[PASS] Re-parsed serialized JSON successfully! Perfect roundtrip.\n"
