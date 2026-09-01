(**
   db.ml - Native SQLite Lead Persistence & State Machine Layer.
   Manages the 'leads' table in leads.db for DISCOVERED, ENRICHED, VALIDATED,
   and DISCARDED states.
*)

type lead_status =
  | Discovered
  | Enriched
  | Validated
  | Discarded
  | Disqualified
  | Custom of string

let string_of_status = function
  | Discovered -> "DISCOVERED"
  | Enriched -> "ENRICHED"
  | Validated -> "VALIDATED"
  | Discarded -> "DISCARDED"
  | Disqualified -> "DISQUALIFIED"
  | Custom s -> String.uppercase_ascii (String.trim s)

let status_of_string s =
  match String.uppercase_ascii (String.trim s) with
  | "DISCOVERED" -> Discovered
  | "ENRICHED" -> Enriched
  | "VALIDATED" -> Validated
  | "DISCARDED" -> Discarded
  | "DISQUALIFIED" -> Disqualified
  | other -> Custom other

type lead_row = {
  id : int;
  address : string;
  zip_code : string;
  property_type : string option;
  roof_type : string option;
  estimated_value : float option;
  owner_name : string option;
  is_hoa : bool;
  is_rental : bool;
  apn : string option;
  last_roof_permit_date : string option;
  roof_age_years : float option;
  phone_number : string option;
  created_at : string;
  status : string;
}

type t = {
  db_path : string;
  leads_by_address : (string, lead_row) Hashtbl.t;
  leads_by_id : (int, lead_row) Hashtbl.t;
  next_id : int ref;
  mutex : Mutex.t;
}

let iso8601_now () : string =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
    (tm.Unix.tm_year + 1900)
    (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday
    tm.Unix.tm_hour
    tm.Unix.tm_min
    tm.Unix.tm_sec

let row_to_json (r : lead_row) : Json.t =
  let opt_str k v = match v with Some s -> [(k, Json.String s)] | None -> [(k, Json.Null)] in
  let opt_float k v = match v with Some f -> [(k, Json.Number f)] | None -> [(k, Json.Null)] in
  let fields =
    [
      ("id", Json.Number (float_of_int r.id));
      ("address", Json.String r.address);
      ("zip_code", Json.String r.zip_code);
    ] @
    (opt_str "property_type" r.property_type) @
    (opt_str "roof_type" r.roof_type) @
    (opt_float "estimated_value" r.estimated_value) @
    (opt_str "owner_name" r.owner_name) @
    [
      ("is_hoa", Json.Bool r.is_hoa);
      ("is_rental", Json.Bool r.is_rental);
    ] @
    (opt_str "apn" r.apn) @
    (opt_str "last_roof_permit_date" r.last_roof_permit_date) @
    (opt_float "roof_age_years" r.roof_age_years) @
    (opt_str "phone_number" r.phone_number) @
    [
      ("created_at", Json.String r.created_at);
      ("status", Json.String r.status);
    ]
  in
  Json.Object fields

let row_of_json (j : Json.t) : lead_row =
  let id = Json.get_int "id" j |> Option.value ~default:0 in
  let address = Json.get_string "address" j |> Option.value ~default:"" in
  let zip_code = Json.get_string "zip_code" j |> Option.value ~default:"94115" in
  let property_type = Json.get_string "property_type" j in
  let roof_type = Json.get_string "roof_type" j in
  let estimated_value = Json.get_float "estimated_value" j in
  let owner_name = Json.get_string "owner_name" j in
  let is_hoa =
    match Json.get_bool "is_hoa" j with
    | Some b -> b
    | None -> (match Json.get_int "is_hoa" j with Some i -> i <> 0 | None -> false)
  in
  let is_rental =
    match Json.get_bool "is_rental" j with
    | Some b -> b
    | None -> (match Json.get_int "is_rental" j with Some i -> i <> 0 | None -> false)
  in
  let apn = Json.get_string "apn" j in
  let last_roof_permit_date = Json.get_string "last_roof_permit_date" j in
  let roof_age_years = Json.get_float "roof_age_years" j in
  let phone_number = Json.get_string "phone_number" j in
  let created_at = Json.get_string "created_at" j |> Option.value ~default:(iso8601_now ()) in
  let status = Json.get_string "status" j |> Option.value ~default:"DISCOVERED" in
  {
    id;
    address;
    zip_code;
    property_type;
    roof_type;
    estimated_value;
    owner_name;
    is_hoa;
    is_rental;
    apn;
    last_roof_permit_date;
    roof_age_years;
    phone_number;
    created_at;
    status;
  }

let raw_lead_of_row (r : lead_row) : Types.raw_lead =
  let property_type =
    match r.property_type with
    | Some s -> Types.parse_property_type s
    | None -> Types.SingleFamily
  in
  let roof_type =
    match r.roof_type with
    | Some s -> Types.parse_roof_type s
    | None -> Types.Victorian
  in
  {
    address = r.address;
    zip_code = r.zip_code;
    property_type;
    roof_type;
    property_type_raw = r.property_type;
    roof_type_raw = r.roof_type;
    estimated_value = r.estimated_value;
    owner_name = r.owner_name;
    is_hoa = r.is_hoa;
    is_rental = r.is_rental;
    apn = r.apn;
    last_roof_permit_date = r.last_roof_permit_date;
    roof_age_years = r.roof_age_years;
    year_built = None;
    phone_number = r.phone_number;
    permits = [];
  }

let row_of_raw_lead ?(id = 0) ?(status = Discovered) (l : Types.raw_lead) : lead_row =
  {
    id;
    address = l.address;
    zip_code = l.zip_code;
    property_type = Some (Types.string_of_property_type l.property_type);
    roof_type = Some (Types.string_of_roof_type l.roof_type);
    estimated_value = l.estimated_value;
    owner_name = l.owner_name;
    is_hoa = l.is_hoa;
    is_rental = l.is_rental;
    apn = l.apn;
    last_roof_permit_date = l.last_roof_permit_date;
    roof_age_years = l.roof_age_years;
    phone_number = l.phone_number;
    created_at = iso8601_now ();
    status = string_of_status status;
  }

let sql_escape (s : string) : string =
  let buf = Buffer.create (String.length s + 8) in
  for i = 0 to String.length s - 1 do
    let c = s.[i] in
    if c = '\'' then Buffer.add_string buf "''"
    else if c = '\000' then ()
    else Buffer.add_char buf c
  done;
  Buffer.contents buf

let sql_opt_str = function
  | Some s -> "'" ^ sql_escape s ^ "'"
  | None -> "NULL"

let sql_opt_float = function
  | Some f -> Printf.sprintf "%.6f" f
  | None -> "NULL"

let run_sqlite_cmd (db_path : string) (sql : string) : (string, string) result =
  if db_path = ":memory:" then Ok ""
  else
    try
      let cmd = Printf.sprintf "sqlite3 %s %s" (Filename.quote db_path) (Filename.quote sql) in
      let ic = Unix.open_process_in cmd in
      let buf = Buffer.create 1024 in
      let chunk = Bytes.create 1024 in
      let rec read () =
        let n = input ic chunk 0 1024 in
        if n > 0 then (
          Buffer.add_subbytes buf chunk 0 n;
          read ()
        )
      in
      read ();
      let status = Unix.close_process_in ic in
      match status with
      | Unix.WEXITED 0 -> Ok (Buffer.contents buf)
      | Unix.WEXITED code -> Error (Printf.sprintf "sqlite3 exited %d: %s" code (Buffer.contents buf))
      | _ -> Error "sqlite3 process failed"
    with exn ->
      Error (Printexc.to_string exn)

let init_db (t : t) : unit =
  Mutex.protect t.mutex (fun () ->
    if t.db_path <> ":memory:" then
      let dir = Filename.dirname t.db_path in
      if not (Sys.file_exists dir) then
        (try Unix.mkdir dir 0o755 with _ -> ());
      let sql =
        "CREATE TABLE IF NOT EXISTS leads (" ^
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " ^
        "address TEXT NOT NULL UNIQUE, " ^
        "zip_code TEXT NOT NULL, " ^
        "property_type TEXT, " ^
        "roof_type TEXT, " ^
        "estimated_value REAL, " ^
        "owner_name TEXT, " ^
        "is_hoa BOOLEAN DEFAULT 0, " ^
        "is_rental BOOLEAN DEFAULT 0, " ^
        "apn TEXT, " ^
        "last_roof_permit_date DATE, " ^
        "roof_age_years REAL, " ^
        "phone_number TEXT, " ^
        "created_at DATE DEFAULT CURRENT_TIMESTAMP, " ^
        "status TEXT DEFAULT 'DISCOVERED'" ^
        ");" ^
        "CREATE INDEX IF NOT EXISTS idx_leads_zip ON leads(zip_code);" ^
        "CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);"
      in
      ignore (run_sqlite_cmd t.db_path sql)
  )

let load_existing_rows (t : t) : unit =
  if t.db_path <> ":memory:" && Sys.file_exists t.db_path then
    match run_sqlite_cmd t.db_path "SELECT json_group_array(json_object('id', id, 'address', address, 'zip_code', zip_code, 'property_type', property_type, 'roof_type', roof_type, 'estimated_value', estimated_value, 'owner_name', owner_name, 'is_hoa', is_hoa, 'is_rental', is_rental, 'apn', apn, 'last_roof_permit_date', last_roof_permit_date, 'roof_age_years', roof_age_years, 'phone_number', phone_number, 'created_at', created_at, 'status', status)) FROM leads;" with
    | Ok json_str ->
        let trimmed = String.trim json_str in
        if String.length trimmed > 0 then
          (match Json.parse trimmed with
           | Ok (Json.Array rows) ->
               List.iter (fun row_json ->
                 try
                   let r = row_of_json row_json in
                   Hashtbl.replace t.leads_by_address (String.lowercase_ascii r.address) r;
                   Hashtbl.replace t.leads_by_id r.id r;
                   if r.id >= !(t.next_id) then t.next_id := r.id + 1
                 with _ -> ()
               ) rows
           | _ -> ())
    | Error _ -> ()

let create ?(db_path = "leads.db") () : t =
  let full_path =
    if db_path = ":memory:" then ":memory:"
    else if Filename.is_relative db_path then
      Filename.concat (Sys.getcwd ()) db_path
    else db_path
  in
  let db = {
    db_path = full_path;
    leads_by_address = Hashtbl.create 64;
    leads_by_id = Hashtbl.create 64;
    next_id = ref 1;
    mutex = Mutex.create ();
  } in
  init_db db;
  load_existing_rows db;
  db

let db_path (t : t) : string = t.db_path

let insert_lead (t : t) ?(status = Discovered) (l : Types.raw_lead) : (int, string) result =
  Mutex.protect t.mutex (fun () ->
    let addr_key = String.lowercase_ascii (String.trim l.address) in
    if addr_key = "" then Error "Lead address cannot be empty"
    else if Hashtbl.mem t.leads_by_address addr_key then
      Error ("Lead address already exists: " ^ l.address)
    else
      let id = !(t.next_id) in
      incr t.next_id;
      let row = row_of_raw_lead ~id ~status l in
      Hashtbl.replace t.leads_by_address addr_key row;
      Hashtbl.replace t.leads_by_id id row;
      if t.db_path <> ":memory:" then (
        let sql = Printf.sprintf
          "INSERT INTO leads (id, address, zip_code, property_type, roof_type, estimated_value, owner_name, is_hoa, is_rental, apn, last_roof_permit_date, roof_age_years, phone_number, created_at, status) VALUES (%d, '%s', '%s', %s, %s, %s, %s, %d, %d, %s, %s, %s, %s, '%s', '%s');"
          id
          (sql_escape row.address)
          (sql_escape row.zip_code)
          (sql_opt_str row.property_type)
          (sql_opt_str row.roof_type)
          (sql_opt_float row.estimated_value)
          (sql_opt_str row.owner_name)
          (if row.is_hoa then 1 else 0)
          (if row.is_rental then 1 else 0)
          (sql_opt_str row.apn)
          (sql_opt_str row.last_roof_permit_date)
          (sql_opt_float row.roof_age_years)
          (sql_opt_str row.phone_number)
          (sql_escape row.created_at)
          (sql_escape row.status)
        in
        ignore (run_sqlite_cmd t.db_path sql)
      );
      Ok id
  )

let upsert_lead (t : t) ?(status = Discovered) (l : Types.raw_lead) : (int, string) result =
  Mutex.protect t.mutex (fun () ->
    let addr_key = String.lowercase_ascii (String.trim l.address) in
    if addr_key = "" then Error "Lead address cannot be empty"
    else
      match Hashtbl.find_opt t.leads_by_address addr_key with
      | Some existing ->
          let updated = {
            existing with
            zip_code = l.zip_code;
            property_type = Some (Types.string_of_property_type l.property_type);
            roof_type = Some (Types.string_of_roof_type l.roof_type);
            estimated_value = (match l.estimated_value with Some _ as v -> v | None -> existing.estimated_value);
            owner_name = (match l.owner_name with Some _ as v -> v | None -> existing.owner_name);
            is_hoa = l.is_hoa;
            is_rental = l.is_rental;
            apn = (match l.apn with Some _ as v -> v | None -> existing.apn);
            last_roof_permit_date = (match l.last_roof_permit_date with Some _ as v -> v | None -> existing.last_roof_permit_date);
            roof_age_years = (match l.roof_age_years with Some _ as v -> v | None -> existing.roof_age_years);
            phone_number = (match l.phone_number with Some _ as v -> v | None -> existing.phone_number);
            status = string_of_status status;
          } in
          Hashtbl.replace t.leads_by_address addr_key updated;
          Hashtbl.replace t.leads_by_id existing.id updated;
          if t.db_path <> ":memory:" then (
            let sql = Printf.sprintf
              "UPDATE leads SET zip_code='%s', property_type=%s, roof_type=%s, estimated_value=%s, owner_name=%s, is_hoa=%d, is_rental=%d, apn=%s, last_roof_permit_date=%s, roof_age_years=%s, phone_number=%s, status='%s' WHERE id=%d;"
              (sql_escape updated.zip_code)
              (sql_opt_str updated.property_type)
              (sql_opt_str updated.roof_type)
              (sql_opt_float updated.estimated_value)
              (sql_opt_str updated.owner_name)
              (if updated.is_hoa then 1 else 0)
              (if updated.is_rental then 1 else 0)
              (sql_opt_str updated.apn)
              (sql_opt_str updated.last_roof_permit_date)
              (sql_opt_float updated.roof_age_years)
              (sql_opt_str updated.phone_number)
              (sql_escape updated.status)
              existing.id
            in
            ignore (run_sqlite_cmd t.db_path sql)
          );
          Ok existing.id
      | None ->
          let id = !(t.next_id) in
          incr t.next_id;
          let row = row_of_raw_lead ~id ~status l in
          Hashtbl.replace t.leads_by_address addr_key row;
          Hashtbl.replace t.leads_by_id id row;
          if t.db_path <> ":memory:" then (
            let sql = Printf.sprintf
              "INSERT INTO leads (id, address, zip_code, property_type, roof_type, estimated_value, owner_name, is_hoa, is_rental, apn, last_roof_permit_date, roof_age_years, phone_number, created_at, status) VALUES (%d, '%s', '%s', %s, %s, %s, %s, %d, %d, %s, %s, %s, %s, '%s', '%s');"
              id
              (sql_escape row.address)
              (sql_escape row.zip_code)
              (sql_opt_str row.property_type)
              (sql_opt_str row.roof_type)
              (sql_opt_float row.estimated_value)
              (sql_opt_str row.owner_name)
              (if row.is_hoa then 1 else 0)
              (if row.is_rental then 1 else 0)
              (sql_opt_str row.apn)
              (sql_opt_str row.last_roof_permit_date)
              (sql_opt_float row.roof_age_years)
              (sql_opt_str row.phone_number)
              (sql_escape row.created_at)
              (sql_escape row.status)
            in
            ignore (run_sqlite_cmd t.db_path sql)
          );
          Ok id
  )

let update_status (t : t) (address : string) (status : lead_status) : (unit, string) result =
  Mutex.protect t.mutex (fun () ->
    let addr_key = String.lowercase_ascii (String.trim address) in
    match Hashtbl.find_opt t.leads_by_address addr_key with
    | Some existing ->
        let new_status_str = string_of_status status in
        let updated = { existing with status = new_status_str } in
        Hashtbl.replace t.leads_by_address addr_key updated;
        Hashtbl.replace t.leads_by_id existing.id updated;
        if t.db_path <> ":memory:" then (
          let sql = Printf.sprintf "UPDATE leads SET status='%s' WHERE id=%d;" (sql_escape new_status_str) existing.id in
          ignore (run_sqlite_cmd t.db_path sql)
        );
        Ok ()
    | None -> Error ("Lead not found: " ^ address)
  )

let update_enriched
    (t : t)
    (address : string)
    ?apn
    ?owner_name
    ?estimated_value
    ?last_roof_permit_date
    ?roof_age_years
    ?is_hoa
    ?is_rental
    ?property_type
    ?roof_type
    ?phone_number
    () : (unit, string) result =
  Mutex.protect t.mutex (fun () ->
    let addr_key = String.lowercase_ascii (String.trim address) in
    match Hashtbl.find_opt t.leads_by_address addr_key with
    | Some existing ->
        let updated = {
          existing with
          apn = (match apn with Some _ as v -> v | None -> existing.apn);
          owner_name = (match owner_name with Some _ as v -> v | None -> existing.owner_name);
          estimated_value = (match estimated_value with Some _ as v -> v | None -> existing.estimated_value);
          last_roof_permit_date = (match last_roof_permit_date with Some _ as v -> v | None -> existing.last_roof_permit_date);
          roof_age_years = (match roof_age_years with Some _ as v -> v | None -> existing.roof_age_years);
          is_hoa = (match is_hoa with Some b -> b | None -> existing.is_hoa);
          is_rental = (match is_rental with Some b -> b | None -> existing.is_rental);
          property_type = (match property_type with Some _ as v -> v | None -> existing.property_type);
          roof_type = (match roof_type with Some _ as v -> v | None -> existing.roof_type);
          phone_number = (match phone_number with Some _ as v -> v | None -> existing.phone_number);
          status = "ENRICHED";
        } in
        Hashtbl.replace t.leads_by_address addr_key updated;
        Hashtbl.replace t.leads_by_id existing.id updated;
        if t.db_path <> ":memory:" then (
          let sql = Printf.sprintf
            "UPDATE leads SET apn=%s, owner_name=%s, estimated_value=%s, last_roof_permit_date=%s, roof_age_years=%s, is_hoa=%d, is_rental=%d, property_type=%s, roof_type=%s, phone_number=%s, status='ENRICHED' WHERE id=%d;"
            (sql_opt_str updated.apn)
            (sql_opt_str updated.owner_name)
            (sql_opt_float updated.estimated_value)
            (sql_opt_str updated.last_roof_permit_date)
            (sql_opt_float updated.roof_age_years)
            (if updated.is_hoa then 1 else 0)
            (if updated.is_rental then 1 else 0)
            (sql_opt_str updated.property_type)
            (sql_opt_str updated.roof_type)
            (sql_opt_str updated.phone_number)
            existing.id
          in
          ignore (run_sqlite_cmd t.db_path sql)
        );
        Ok ()
    | None -> Error ("Lead not found: " ^ address)
  )

let get_lead_by_address (t : t) (address : string) : lead_row option =
  Mutex.protect t.mutex (fun () ->
    let addr_key = String.lowercase_ascii (String.trim address) in
    Hashtbl.find_opt t.leads_by_address addr_key
  )

let get_lead_by_id (t : t) (id : int) : lead_row option =
  Mutex.protect t.mutex (fun () ->
    Hashtbl.find_opt t.leads_by_id id
  )

let list_leads
    ?(status : lead_status option)
    ?(zip_code : string option)
    ?(limit : int option)
    (t : t) : lead_row list =
  Mutex.protect t.mutex (fun () ->
    let rows = Hashtbl.fold (fun _ r acc -> r :: acc) t.leads_by_address [] in
    let filtered =
      List.filter (fun r ->
        let match_status =
          match status with
          | Some st -> String.uppercase_ascii r.status = string_of_status st
          | None -> true
        in
        let match_zip =
          match zip_code with
          | Some z -> r.zip_code = z
          | None -> true
        in
        match_status && match_zip
      ) rows
    in
    let sorted = List.sort (fun r1 r2 -> compare r1.id r2.id) filtered in
    match limit with
    | Some n when n > 0 ->
        let rec take n = function
          | [] -> []
          | _ when n <= 0 -> []
          | x :: xs -> x :: take (n - 1) xs
        in
        take n sorted
    | _ -> sorted
  )

let count_leads ?(status : lead_status option) (t : t) : int =
  List.length (list_leads ?status t)

let delete_lead_by_address (t : t) (address : string) : bool =
  Mutex.protect t.mutex (fun () ->
    let addr_key = String.lowercase_ascii (String.trim address) in
    match Hashtbl.find_opt t.leads_by_address addr_key with
    | Some existing ->
        Hashtbl.remove t.leads_by_address addr_key;
        Hashtbl.remove t.leads_by_id existing.id;
        if t.db_path <> ":memory:" then (
          let sql = Printf.sprintf "DELETE FROM leads WHERE id=%d;" existing.id in
          ignore (run_sqlite_cmd t.db_path sql)
        );
        true
    | None -> false
  )

let delete_lead_by_id (t : t) (id : int) : bool =
  Mutex.protect t.mutex (fun () ->
    match Hashtbl.find_opt t.leads_by_id id with
    | Some existing ->
        let addr_key = String.lowercase_ascii existing.address in
        Hashtbl.remove t.leads_by_address addr_key;
        Hashtbl.remove t.leads_by_id id;
        if t.db_path <> ":memory:" then (
          let sql = Printf.sprintf "DELETE FROM leads WHERE id=%d;" id in
          ignore (run_sqlite_cmd t.db_path sql)
        );
        true
    | None -> false
  )

let clear (t : t) : unit =
  Mutex.protect t.mutex (fun () ->
    Hashtbl.clear t.leads_by_address;
    Hashtbl.clear t.leads_by_id;
    t.next_id := 1;
    if t.db_path <> ":memory:" then (
      let sql = "DELETE FROM leads;" in
      ignore (run_sqlite_cmd t.db_path sql)
    )
  )
