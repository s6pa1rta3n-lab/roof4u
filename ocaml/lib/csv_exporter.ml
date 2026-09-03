(**
   csv_exporter.ml - RFC 4180 Compliant CSV Lead Exporter with DDE Formula Injection Protection.
   Exports qualified and enriched leads to CSV with exact 10-column schema.
*)

open Types

let headers = [
  "Address";
  "Zip Code";
  "Property Type";
  "Roof Type";
  "Assessed Value";
  "Owner Name";
  "APN";
  "Roof Age (Years)";
  "Phone Number";
  "Status";
]

let header_string = String.concat "," headers ^ "\n"

(** Formula injection neutralization: prepends ' if starting with =, +, -, @, \t, or \r *)
let sanitize_csv_field (s : string) : string =
  if String.length s = 0 then s
  else
    let c0 = s.[0] in
    if c0 = '=' || c0 = '+' || c0 = '-' || c0 = '@' || c0 = '\t' || c0 = '\r' then
      "'" ^ s
    else
      let trimmed = String.trim s in
      if String.length trimmed > 0 then
        let tc0 = trimmed.[0] in
        if tc0 = '=' || tc0 = '+' || tc0 = '-' || tc0 = '@' || tc0 = '\t' || tc0 = '\r' then
          "'" ^ s
        else
          s
      else
        s

(** RFC 4180 CSV value escaping *)
let escape_csv_field (s : string) : string =
  let needs_quoting =
    String.contains s ',' ||
    String.contains s '"' ||
    String.contains s '\n' ||
    String.contains s '\r' ||
    (String.length s > 0 && (s.[0] = ' ' || s.[String.length s - 1] = ' '))
  in
  if needs_quoting then
    let buf = Buffer.create (String.length s + 8) in
    Buffer.add_char buf '"';
    String.iter (fun c ->
      if c = '"' then Buffer.add_string buf "\"\""
      else Buffer.add_char buf c
    ) s;
    Buffer.add_char buf '"';
    Buffer.contents buf
  else
    s

let format_csv_cell (s : string) : string =
  let sanitized = sanitize_csv_field s in
  escape_csv_field sanitized

let format_float_opt (opt : float option) : string =
  match opt with
  | None -> ""
  | Some f ->
      if Float.is_nan f || Float.is_infinite f then ""
      else if f = floor f then Printf.sprintf "%.0f" f
      else Printf.sprintf "%.2f" f

let row_of_raw_lead ?(status = "VALIDATED") (lead : raw_lead) : string list =
  [
    format_csv_cell lead.address;
    format_csv_cell lead.zip_code;
    format_csv_cell (string_of_property_type lead.property_type);
    format_csv_cell (string_of_roof_type lead.roof_type);
    format_csv_cell (format_float_opt lead.estimated_value);
    format_csv_cell (Option.value ~default:"" lead.owner_name);
    format_csv_cell (Option.value ~default:"" lead.apn);
    format_csv_cell (format_float_opt lead.roof_age_years);
    format_csv_cell (Option.value ~default:"" lead.phone_number);
    format_csv_cell status;
  ]

let row_of_verified_lead (v : verified_lead) : string list =
  let status =
    match v.verdict with
    | Qualified _ -> "VALIDATED"
    | Disqualified _ -> "DISQUALIFIED"
  in
  row_of_raw_lead ~status v.lead

let row_of_db_row (row : Db.lead_row) : string list =
  let prop_type = Option.value ~default:"Single-Family" row.property_type in
  let roof_type = Option.value ~default:"Victorian" row.roof_type in
  let status_display =
    match String.uppercase_ascii (String.trim row.status) with
    | "VALIDATED" | "QUALIFIED" | "EXPORTED" | "ENRICHED" -> "VALIDATED"
    | "DISQUALIFIED" -> "DISQUALIFIED"
    | "DISCARDED" -> "DISCARDED"
    | other -> other
  in
  [
    format_csv_cell row.address;
    format_csv_cell row.zip_code;
    format_csv_cell prop_type;
    format_csv_cell roof_type;
    format_csv_cell (format_float_opt row.estimated_value);
    format_csv_cell (Option.value ~default:"" row.owner_name);
    format_csv_cell (Option.value ~default:"" row.apn);
    format_csv_cell (format_float_opt row.roof_age_years);
    format_csv_cell (Option.value ~default:"" row.phone_number);
    format_csv_cell status_display;
  ]

let write_csv_rows ?(crlf = false) (filepath : string) (rows : string list list) : unit =
  let term = if crlf then "\r\n" else "\n" in
  let header = String.concat "," headers ^ term in
  let oc = open_out filepath in
  try
    output_string oc header;
    List.iter (fun row ->
      let line = String.concat "," row ^ term in
      output_string oc line
    ) rows;
    close_out oc
  with exn ->
    close_out_noerr oc;
    raise exn

let export_validated_leads_csv (filepath : string) (leads : verified_lead list) : unit =
  let qualified_leads =
    List.filter (fun v ->
      match v.verdict with
      | Qualified { score; _ } when score.total_score >= 60.0 -> true
      | _ -> false
    ) leads
  in
  let rows = List.map row_of_verified_lead qualified_leads in
  write_csv_rows filepath rows

let export_from_db
    ?(min_score = 60.0)
    (db : Db.t)
    ~(output_file : string) : int =
  let validated = Db.list_leads ~status:Db.Validated db in
  let enriched = Db.list_leads ~status:Db.Enriched db in
  let all_candidates = validated @ enriched in
  let qualified_rows =
    List.filter (fun row ->
      let raw = Db.raw_lead_of_row row in
      let score = Scorer.calculate_score raw in
      score.total_score >= min_score
    ) all_candidates
  in
  let csv_rows = List.map row_of_db_row qualified_rows in
  write_csv_rows output_file csv_rows;
  List.length qualified_rows

let export_to_csv
    ?(min_score = 60.0)
    ?(db_path = "leads.db")
    ?(output_file = "validated_leads.csv")
    () : int =
  let db = Db.create ~db_path () in
  Db.init_db db;
  export_from_db ~min_score db ~output_file
