(**
   http_client.ml - Pure OCaml HTTP 1.1 Client using standard Unix sockets.
   Zero external dependencies. Full chunked transfer decoding, content-length decoding,
   case-insensitive header handling, and socket timeouts.
*)

type response = {
  status_code : int;
  status_message : string;
  headers : (string * string) list;
  body : string;
}

let parse_url (url : string) : (string * int * string, string) result =
  let s = String.trim url in
  if s = "" then Error "Empty URL"
  else
    let without_proto, default_port =
      if String.starts_with ~prefix:"http://" s then
        (String.sub s 7 (String.length s - 7), 80)
      else if String.starts_with ~prefix:"https://" s then
        (String.sub s 8 (String.length s - 8), 443)
      else (s, 80)
    in
    let slash_idx =
      try Some (String.index without_proto '/')
      with Not_found -> None
    in
    let host_port_part, path_query =
      match slash_idx with
      | Some idx ->
          let h = String.sub without_proto 0 idx in
          let pq = String.sub without_proto idx (String.length without_proto - idx) in
          (h, if pq = "" then "/" else pq)
      | None ->
          (without_proto, "/")
    in
    if host_port_part = "" then Error ("Invalid host in URL: " ^ url)
    else
      match String.split_on_char ':' host_port_part with
      | [h] -> Ok (h, default_port, path_query)
      | [h; p_str] ->
          (try
             let p = int_of_string p_str in
             if p > 0 && p <= 65535 then Ok (h, p, path_query)
             else Error ("Port out of range: " ^ p_str)
           with _ -> Error ("Invalid port in URL: " ^ p_str))
      | _ -> Error ("Malformed host:port in URL: " ^ url)

let get_header (name : string) (headers : (string * string) list) : string option =
  let target = String.lowercase_ascii (String.trim name) in
  let rec find = function
    | [] -> None
    | (k, v) :: rest ->
        if String.lowercase_ascii (String.trim k) = target then Some (String.trim v)
        else find rest
  in
  find headers

let decode_chunked (chunked_str : string) : (string, string) result =
  let len = String.length chunked_str in
  let buf = Buffer.create (max 64 len) in
  let rec parse_chunks pos =
    if pos >= len then Ok (Buffer.contents buf)
    else
      let rec find_eol i =
        if i >= len then None
        else if chunked_str.[i] = '\n' then
          let line_end = if i > pos && chunked_str.[i - 1] = '\r' then i - 1 else i in
          Some (line_end, i + 1)
        else find_eol (i + 1)
      in
      match find_eol pos with
      | None -> Ok (Buffer.contents buf)
      | Some (line_end, next_pos) ->
          let size_line = String.trim (String.sub chunked_str pos (line_end - pos)) in
          if size_line = "" then parse_chunks next_pos
          else
            let hex_str =
              match String.split_on_char ';' size_line with
              | h :: _ -> String.trim h
              | [] -> ""
            in
            (try
               let chunk_size = int_of_string ("0x" ^ hex_str) in
               if chunk_size < 0 then Error ("Negative chunk size: " ^ hex_str)
               else if chunk_size = 0 then Ok (Buffer.contents buf)
               else if next_pos + chunk_size > len then
                 let avail = len - next_pos in
                 Buffer.add_substring buf chunked_str next_pos avail;
                 Ok (Buffer.contents buf)
               else
                 begin
                   Buffer.add_substring buf chunked_str next_pos chunk_size;
                   let after_chunk = next_pos + chunk_size in
                   let skip_crlf =
                     if after_chunk + 1 < len && chunked_str.[after_chunk] = '\r' && chunked_str.[after_chunk + 1] = '\n' then
                       after_chunk + 2
                     else if after_chunk < len && chunked_str.[after_chunk] = '\n' then
                       after_chunk + 1
                     else after_chunk
                   in
                   parse_chunks skip_crlf
                 end
             with e ->
               Error ("Failed to parse chunk size hex '" ^ hex_str ^ "': " ^ Printexc.to_string e))
  in
  parse_chunks 0

let parse_response_string (raw : string) : (response, string) result =
  let len = String.length raw in
  if len = 0 then Error "Empty HTTP response"
  else
    let header_end_opt =
      let rec find i =
        if i + 3 < len && raw.[i] = '\r' && raw.[i+1] = '\n' && raw.[i+2] = '\r' && raw.[i+3] = '\n' then
          Some (i, i + 4)
        else if i + 1 < len && raw.[i] = '\n' && raw.[i+1] = '\n' then
          Some (i, i + 2)
        else if i + 1 < len then find (i + 1)
        else None
      in
      find 0
    in
    match header_end_opt with
    | None -> Error "Malformed HTTP response: missing header delimiter"
    | Some (header_end, body_start) ->
        let header_section = String.sub raw 0 header_end in
        let raw_body = String.sub raw body_start (len - body_start) in
        let header_lines = String.split_on_char '\n' header_section in
        let header_lines = List.map (fun l ->
          let l_len = String.length l in
          if l_len > 0 && l.[l_len - 1] = '\r' then String.sub l 0 (l_len - 1) else l
        ) header_lines in
        let header_lines = List.filter (fun l -> String.trim l <> "") header_lines in
        match header_lines with
        | [] -> Error "Empty header section in HTTP response"
        | status_line :: header_pairs ->
            let parts = String.split_on_char ' ' (String.trim status_line) in
            let parts = List.filter (fun p -> p <> "") parts in
            let status_code, status_message =
              match parts with
              | _version :: code_str :: rest ->
                  let code = try int_of_string code_str with _ -> 0 in
                  let msg = String.concat " " rest in
                  (code, msg)
              | [code_str] ->
                  let code = try int_of_string code_str with _ -> 0 in
                  (code, "")
              | [] -> (0, "")
            in
            let headers =
              List.filter_map (fun line ->
                match String.index_opt line ':' with
                | Some idx ->
                    let k = String.trim (String.sub line 0 idx) in
                    let v = String.trim (String.sub line (idx + 1) (String.length line - idx - 1)) in
                    Some (k, v)
                | None -> None
              ) header_pairs
            in
            let is_chunked =
              match get_header "transfer-encoding" headers with
              | Some v -> String.lowercase_ascii v = "chunked"
              | None -> false
            in
            let body_res =
              if is_chunked then decode_chunked raw_body
              else
                match get_header "content-length" headers with
                | Some cl_str ->
                    (try
                       let cl = int_of_string cl_str in
                       if cl >= 0 && cl <= String.length raw_body then
                         Ok (String.sub raw_body 0 cl)
                       else Ok raw_body
                     with _ -> Ok raw_body)
                | None -> Ok raw_body
            in
            match body_res with
            | Ok body ->
                Ok {
                  status_code;
                  status_message;
                  headers;
                  body;
                }
            | Error e -> Error ("Body decoding error: " ^ e)

let request
    ?(headers = [])
    ?(body = "")
    ?(timeout = 10.0)
    ~(method_str : string)
    ~(url : string)
    () : (response, string) result =
  match parse_url url with
  | Error e -> Error e
  | Ok (host, port, path_and_query) ->
      let sock =
        try
          let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
          Unix.setsockopt_float s Unix.SO_RCVTIMEO timeout;
          Unix.setsockopt_float s Unix.SO_SNDTIMEO timeout;
          s
        with Unix.Unix_error (err, fn, _) ->
          failwith (Printf.sprintf "Socket error in %s: %s" fn (Unix.error_message err))
      in
      Fun.protect
        ~finally:(fun () ->
          try Unix.close sock with _ -> ())
        (fun () ->
          try
            let inet_addr =
              if host = "localhost" || host = "127.0.0.1" then
                Unix.inet_addr_loopback
              else
                try Unix.inet_addr_of_string host
                with _ ->
                  let host_entry = Unix.gethostbyname host in
                  host_entry.Unix.h_addr_list.(0)
            in
            Unix.connect sock (Unix.ADDR_INET (inet_addr, port));

            let has_header name =
              let target = String.lowercase_ascii name in
              List.exists (fun (k, _) -> String.lowercase_ascii k = target) headers
            in
            let buf = Buffer.create 512 in
            Buffer.add_string buf (Printf.sprintf "%s %s HTTP/1.1\r\n" method_str path_and_query);
            Buffer.add_string buf (Printf.sprintf "Host: %s\r\n" host);
            if not (has_header "user-agent") then
              Buffer.add_string buf "User-Agent: Roo4u-PureOCaml-Engine/1.0\r\n";
            if not (has_header "connection") then
              Buffer.add_string buf "Connection: close\r\n";
            if body <> "" && not (has_header "content-length") then
              Buffer.add_string buf (Printf.sprintf "Content-Length: %d\r\n" (String.length body));
            if body <> "" && not (has_header "content-type") && method_str = "POST" then
              Buffer.add_string buf "Content-Type: application/json\r\n";
            List.iter (fun (k, v) ->
              Buffer.add_string buf (Printf.sprintf "%s: %s\r\n" k v)
            ) headers;
            Buffer.add_string buf "\r\n";
            if body <> "" then Buffer.add_string buf body;

            let req_bytes = Bytes.of_string (Buffer.contents buf) in
            let req_len = Bytes.length req_bytes in
            let rec send_all written =
              if written < req_len then
                let n = Unix.write sock req_bytes written (req_len - written) in
                if n = 0 then failwith "Connection closed while sending request"
                else send_all (written + n)
            in
            send_all 0;

            let resp_buf = Buffer.create 4096 in
            let chunk = Bytes.create 4096 in
            let rec read_all () =
              let n =
                try Unix.read sock chunk 0 4096
                with Unix.Unix_error (Unix.EAGAIN, _, _) | Unix.Unix_error (Unix.EWOULDBLOCK, _, _) -> 0
              in
              if n > 0 then begin
                Buffer.add_subbytes resp_buf chunk 0 n;
                read_all ()
              end
            in
            read_all ();
            let raw_response = Buffer.contents resp_buf in
            parse_response_string raw_response
          with
          | Unix.Unix_error (err, fn, _) ->
              Error (Printf.sprintf "HTTP network error in %s to %s:%d: %s" fn host port (Unix.error_message err))
          | Failure msg -> Error ("HTTP request failure: " ^ msg)
          | exn -> Error ("HTTP exception: " ^ Printexc.to_string exn))

let get ?headers ?timeout url =
  request ?headers ?timeout ~method_str:"GET" ~url ()

let post ?headers ?body ?timeout url =
  request ?headers ?body ?timeout ~method_str:"POST" ~url ()
