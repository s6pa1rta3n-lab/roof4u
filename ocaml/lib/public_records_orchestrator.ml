(**
   public_records_orchestrator.ml - Unified public records acquisition orchestrator.
*)

open Types

type public_records_answers = {
  names_source : string;
  addresses_source : string;
  gis_source : string;
  permits_source : string;
  tax_source : string;
}

let get_public_records_answers () : public_records_answers =
  {
    names_source = Homeowner_names.answer_source_description;
    addresses_source = Homeowner_addresses.answer_source_description;
    gis_source = Gis_roofs.answer_source_description;
    permits_source = Roof_permits.answer_source_description;
    tax_source = Property_tax_records.answer_source_description;
  }

let normalize_str (s : string) : string =
  String.lowercase_ascii (String.trim s)

let strip_hyphens (s : string) : string =
  String.concat "" (String.split_on_char '-' (String.trim s))

let apn_matches (a : string) (b : string) : bool =
  let sa = strip_hyphens a in
  let sb = strip_hyphens b in
  sa <> "" && sb <> "" && sa = sb

let permit_date_str (p : roof_permit_record) : string =
  match p.issued_date with
  | Some d -> d
  | None ->
      (match p.completed_date with
       | Some c -> c
       | None -> Option.value ~default:"" p.filed_date)

let extract_year_from_iso_opt (s_opt : string option) : int option =
  match s_opt with
  | Some s -> Invariants.extract_year_from_string s
  | None -> None

let acquire_neighborhood_public_records
    ?(limit = 10)
    ?(timeout = 10.0)
    ~(neighborhood : string)
    () : (verified_lead list, string) result =
  let addrs_res = Homeowner_addresses.fetch_homeowner_addresses ~limit ~timeout ~neighborhood () in
  let names_res = Homeowner_names.fetch_homeowner_names ~limit ~timeout ~neighborhood () in
  let gis_res = Gis_roofs.fetch_gis_roofs ~limit ~timeout ~neighborhood () in
  let tax_res = Property_tax_records.fetch_property_tax_records ~limit ~timeout ~neighborhood () in
  match addrs_res with
  | Error e -> Error ("Failed to fetch addresses: " ^ e)
  | Ok addrs ->
      let names = match names_res with Ok ns -> ns | Error _ -> [] in
      let gis_list = match gis_res with Ok gs -> gs | Error _ -> [] in
      let tax_list = match tax_res with Ok ts -> ts | Error _ -> [] in
      let raw_leads = List.map (fun (addr : homeowner_address_record) ->
        let matched_name =
          List.find_opt (fun (n : homeowner_name_record) ->
            apn_matches n.parcel_number addr.parcel_number ||
            normalize_str n.property_location = normalize_str addr.property_location
          ) names
        in
        let matched_gis =
          List.find_opt (fun (g : gis_roof_record) ->
            apn_matches g.parcel_number addr.parcel_number ||
            normalize_str g.property_location = normalize_str addr.property_location
          ) gis_list
        in
        let matched_tax =
          List.find_opt (fun (t : property_tax_record) ->
            apn_matches t.parcel_number addr.parcel_number ||
            normalize_str t.property_location = normalize_str addr.property_location
          ) tax_list
        in
        let permits_res =
          Roof_permits.fetch_roof_permits
            ~limit:5
            ~timeout
            ~zip_code:addr.zip_code
            ~street_name:addr.street_name
            ()
        in
        let permits =
          match permits_res with
          | Ok ps ->
              List.filter (fun (p : roof_permit_record) ->
                apn_matches p.parcel_number addr.parcel_number ||
                normalize_str (p.street_number ^ " " ^ p.street_name) = normalize_str addr.property_location
              ) ps
          | Error _ -> []
        in
        let roof_type =
          match matched_gis with
          | Some g -> g.roof_type_classified
          | None -> Victorian
        in
        let property_type =
          if addr.units_count > 1 && addr.units_count <= 4 then MultiUnit2To4
          else if addr.units_count > 4 then MultiUnit5Plus
          else SingleFamily
        in
        let estimated_val =
          match matched_tax with
          | Some t -> Some t.total_assessed_value
          | None -> Some 3500000.0
        in
        let owner_name =
          match matched_name with
          | Some n -> Some n.owner_name
          | None -> Some (addr.property_location ^ " Owner")
        in
        let replacement_permits =
          List.filter (fun (p : roof_permit_record) -> p.is_roof_replacement) permits
        in
        let sorted_replacement_permits =
          List.sort (fun p1 p2 ->
            String.compare (permit_date_str p2) (permit_date_str p1)
          ) replacement_permits
        in
        let current_year = 2026 in
        let (last_permit, roof_age) =
          match sorted_replacement_permits with
          | p :: _ ->
              let p_date = match p.issued_date with Some d -> Some d | None -> p.filed_date in
              (p_date, p.roof_age_years)
          | [] ->
              let structural_age =
                match matched_tax with
                | Some t ->
                    (match t.year_built with
                     | Some yb -> Some (float_of_int (max 0 (current_year - yb)))
                     | None -> None)
                | None -> None
              in
              (None, structural_age)
        in
        let is_hoa =
          Property_tax_records.is_hoa_property
            ?property_class_code:addr.property_class_code
            ?property_class_def:addr.property_class_definition
            ?use_code:(match matched_tax with Some t -> t.use_code | None -> None)
            ?use_def:(match matched_tax with Some t -> t.use_definition | None -> None)
            ~parcel_number:addr.parcel_number
            ~property_type
            ?owner_name
            ~address:addr.property_location
            ()
        in
        let is_rental =
          let has_exemption = match matched_name with Some n -> Some n.has_homeowner_exemption | None -> None in
          let exemption_val = match matched_name with Some n -> Some n.exemption_value | None -> None in
          let owner_type = match matched_name with Some n -> Some n.ownership_type | None -> None in
          Property_tax_records.is_rental_property
            ~situs_address:addr.property_location
            ?has_homeowner_exemption:has_exemption
            ?exemption_value:exemption_val
            ?owner_name
            ?ownership_type:owner_type
            ~units_count:addr.units_count
            ~property_type
            ()
        in
        let converted_permits =
          List.map (fun (p : roof_permit_record) ->
            let yr =
              match extract_year_from_iso_opt p.issued_date with
              | Some y -> Some y
              | None ->
                  (match extract_year_from_iso_opt p.completed_date with
                   | Some y -> Some y
                   | None -> extract_year_from_iso_opt p.filed_date)
            in
            {
              permit_number = p.permit_number;
              permit_type = Some "Roofing Replacement";
              description = p.description;
              date_filed = p.filed_date;
              date_issued = p.issued_date;
              status = p.status;
              year = yr;
              is_roof_replacement = p.is_roof_replacement;
              cost = p.estimated_cost;
            }
          ) permits
        in
        let lead : raw_lead = {
          address = addr.property_location;
          zip_code = addr.zip_code;
          property_type;
          roof_type;
          property_type_raw = Some (string_of_property_type property_type);
          roof_type_raw = Some (string_of_roof_type roof_type);
          estimated_value = estimated_val;
          owner_name;
          is_hoa;
          is_rental;
          apn = Some addr.parcel_number;
          last_roof_permit_date = last_permit;
          roof_age_years = roof_age;
          year_built = (match matched_tax with Some t -> t.year_built | None -> None);
          phone_number = None;
          permits = converted_permits;
        } in
        lead
      ) addrs in
      let verified = List.map Scorer.verify_lead raw_leads in
      Ok verified

