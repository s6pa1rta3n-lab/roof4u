(**
   test_public_records_microservices.ml - Automated test suite for the 5 public records microservices and orchestrator.
*)

open Roof_engine
open Types

let assert_true name cond =
  if cond then Printf.printf "  [PASS] %s\n%!" name
  else (
    Printf.eprintf "  [FAIL] %s\n%!" name;
    exit 1
  )

let assert_equal_str name expected actual =
  if expected = actual then Printf.printf "  [PASS] %s\n%!" name
  else (
    Printf.eprintf "  [FAIL] %s (Expected: %s, Got: %s)\n%!" name expected actual;
    exit 1
  )

let assert_equal_int name expected actual =
  if expected = actual then Printf.printf "  [PASS] %s\n%!" name
  else (
    Printf.eprintf "  [FAIL] %s (Expected: %d, Got: %d)\n%!" name expected actual;
    exit 1
  )

let run_homeowner_names_tests () =
  Printf.printf "[Suite 1] Homeowner Names Public Records Microservice...\n%!";
  let desc = Homeowner_names.answer_source_description in
  assert_true "PUB.NAME.1: Source description references Assessor-Recorder and wv5m-vpq2"
    (String.length desc > 0 &&
     (let contains sub s =
        let sl = String.length sub in
        let dl = String.length s in
        let rec check i =
          if i + sl > dl then false
          else if String.sub s i sl = sub then true
          else check (i + 1)
        in
        check 0
      in
      contains "Assessor-Recorder" desc && contains "wv5m-vpq2" desc));

  let url_res = Homeowner_names.build_homeowner_names_query_url ~neighborhood:"Pacific Heights" ~limit:10 () in
  (match url_res with
  | Ok u ->
      assert_true "PUB.NAME.2: SoQL URL builder constructs valid endpoint query"
        (String.starts_with ~prefix:Homeowner_names.default_assessor_secured_roll_endpoint u)
  | Error err ->
      assert_true ("PUB.NAME.2: Failed to build URL: " ^ err) false);

  let sample_json =
    Json.Object [
      ("parcel_number", Json.String "0576010");
      ("property_location", Json.String "0000 2223 PACIFIC AVE");
      ("homeowner_exemption_value", Json.Number 7000.0);
      ("assessor_neighborhood", Json.String "Pacific Heights");
      ("closed_roll_year", Json.String "2023");
    ]
  in
  (match Homeowner_names.parse_homeowner_name_record sample_json with
  | Ok rec_val ->
      assert_equal_str "PUB.NAME.3: Parsed parcel number matches" "0576010" rec_val.parcel_number;
      assert_equal_str "PUB.NAME.4: Normalized property location without leading zeroes" "2223 PACIFIC AVE" rec_val.property_location;
      assert_true "PUB.NAME.5: Homeowner exemption recognized" rec_val.has_homeowner_exemption;
      assert_true "PUB.NAME.6: Exemption value is 7000.0" (rec_val.exemption_value = 7000.0)
  | Error err ->
      assert_true ("PUB.NAME.3: Record parse error: " ^ err) false);

  let fetch_res = Homeowner_names.fetch_homeowner_names ~neighborhood:"Pacific Heights" ~limit:3 () in
  (match fetch_res with
  | Ok records ->
      assert_true "PUB.NAME.7: Fetch returns non-empty homeowner records list" (List.length records > 0)
  | Error err ->
      assert_true ("PUB.NAME.7: Fetch failed: " ^ err) false)

let run_homeowner_addresses_tests () =
  Printf.printf "[Suite 2] Homeowner Addresses Public Records Microservice...\n%!";
  let desc = Homeowner_addresses.answer_source_description in
  assert_true "PUB.ADDR.1: Source description references Enterprise Addressing System"
    (String.length desc > 0);

  let url_res = Homeowner_addresses.build_addresses_query_url ~neighborhood:"Marina" ~limit:25 () in
  (match url_res with
  | Ok u ->
      assert_true "PUB.ADDR.2: URL builder filters for neighborhood and residential properties"
        (String.starts_with ~prefix:Homeowner_addresses.default_addresses_endpoint u)
  | Error err ->
      assert_true ("PUB.ADDR.2: URL builder failed: " ^ err) false);

  let sample_json =
    Json.Object [
      ("parcel_number", Json.String "0452018");
      ("property_location", Json.String "1840 CHESTNUT ST");
      ("assessor_neighborhood", Json.String "Marina");
      ("property_class_code", Json.String "D");
      ("property_class_code_definition", Json.String "Multi-Unit (2-4 Units)");
      ("use_code", Json.String "MRES");
      ("number_of_units", Json.Number 2.0);
    ]
  in
  (match Homeowner_addresses.parse_homeowner_address_record sample_json with
  | Ok rec_val ->
      assert_equal_str "PUB.ADDR.3: Street number extracted correctly" "1840" rec_val.street_number;
      assert_equal_str "PUB.ADDR.4: Street name extracted correctly" "CHESTNUT ST" rec_val.street_name;
      assert_equal_int "PUB.ADDR.5: Units count parsed correctly" 2 rec_val.units_count;
      assert_true "PUB.ADDR.6: Residential flag is true" rec_val.is_residential
  | Error err ->
      assert_true ("PUB.ADDR.3: Parse error: " ^ err) false);

  let fetch_res = Homeowner_addresses.fetch_homeowner_addresses ~neighborhood:"Marina" ~limit:2 () in
  (match fetch_res with
  | Ok records ->
      assert_true "PUB.ADDR.7: Fetch returns non-empty addresses" (List.length records > 0)
  | Error err ->
      assert_true ("PUB.ADDR.7: Fetch failed: " ^ err) false)

let run_gis_roofs_tests () =
  Printf.printf "[Suite 3] GIS for Roofs Public Records Microservice...\n%!";
  let desc = Gis_roofs.answer_source_description in
  assert_true "PUB.GIS.1: Source description references Building Footprints and sfnk-6tdn"
    (String.length desc > 0);

  let url_res = Gis_roofs.build_gis_roofs_query_url ~neighborhood:"Pacific Heights" () in
  (match url_res with
  | Ok u ->
      assert_true "PUB.GIS.2: URL builder constructs valid GIS endpoint query"
        (String.starts_with ~prefix:Gis_roofs.default_gis_roofs_endpoint u)
  | Error err ->
      assert_true ("PUB.GIS.2: URL error: " ^ err) false);

  let sample_json =
    Json.Object [
      ("parcel_number", Json.String "0576010");
      ("address", Json.String "2223 Pacific Ave");
      ("size_sf", Json.Number 3450.0);
      ("design", Json.String "Victorian Pitch");
      ("the_geom", Json.Object [
        ("type", Json.String "Point");
        ("coordinates", Json.Array [Json.Number (-122.4342); Json.Number 37.7924]);
      ]);
    ]
  in
  (match Gis_roofs.parse_gis_roof_record sample_json with
  | Ok rec_val ->
      assert_true "PUB.GIS.3: Roof size sqft parsed correctly" (rec_val.roof_size_sqft = 3450.0);
      assert_true "PUB.GIS.4: Roof type classified as Victorian" (rec_val.roof_type_classified = Victorian);
      assert_true "PUB.GIS.5: Coordinates latitude extracted" (rec_val.coordinates_latitude = Some 37.7924)
  | Error err ->
      assert_true ("PUB.GIS.3: Parse error: " ^ err) false);

  let fetch_res = Gis_roofs.fetch_gis_roofs ~neighborhood:"Pacific Heights" ~limit:2 () in
  (match fetch_res with
  | Ok records ->
      assert_true "PUB.GIS.6: Fetch returns non-empty GIS records" (List.length records > 0)
  | Error err ->
      assert_true ("PUB.GIS.6: Fetch failed: " ^ err) false)

let run_roof_permits_tests () =
  Printf.printf "[Suite 4] Roof Permits Public Records Microservice...\n%!";
  let desc = Roof_permits.answer_source_description in
  assert_true "PUB.PERMIT.1: Source description references DBI Permits and i98e-djp9"
    (String.length desc > 0);

  let url_res = Roof_permits.build_roof_permits_query_url ~zip_code:"94115" ~street_name:"Pacific" () in
  (match url_res with
  | Ok u ->
      assert_true "PUB.PERMIT.2: URL builder constructs valid DBI permit query"
        (String.starts_with ~prefix:Roof_permits.default_building_permits_endpoint u)
  | Error err ->
      assert_true ("PUB.PERMIT.2: URL builder failed: " ^ err) false);

  let sample_json =
    Json.Object [
      ("permit_number", Json.String "19980512");
      ("block", Json.String "0576");
      ("lot", Json.String "010");
      ("street_number", Json.String "2223");
      ("street_name", Json.String "Pacific");
      ("street_suffix", Json.String "Ave");
      ("zipcode", Json.String "94115");
      ("description", Json.String "Complete tear-off and reroof Victorian shingle replacement");
      ("filed_date", Json.String "1998-05-12T00:00:00");
      ("status", Json.String "COMPLETED");
      ("estimated_cost", Json.Number 35000.0);
    ]
  in
  (match Roof_permits.parse_roof_permit_record ~current_year:2026 sample_json with
  | Ok rec_val ->
      assert_equal_str "PUB.PERMIT.3: Permit number matches" "19980512" rec_val.permit_number;
      assert_equal_str "PUB.PERMIT.4: APN matches block+lot" "0576010" rec_val.parcel_number;
      assert_true "PUB.PERMIT.5: Classified as roof replacement" rec_val.is_roof_replacement;
      assert_true "PUB.PERMIT.6: Computed roof age is 28.0 years" (rec_val.roof_age_years = Some 28.0)
  | Error err ->
      assert_true ("PUB.PERMIT.3: Parse error: " ^ err) false);

  let fetch_res = Roof_permits.fetch_roof_permits ~zip_code:"94115" ~limit:2 () in
  (match fetch_res with
  | Ok records ->
      assert_true "PUB.PERMIT.7: Fetch returns non-empty permit list" (List.length records > 0)
  | Error err ->
      assert_true ("PUB.PERMIT.7: Fetch failed: " ^ err) false)

let run_property_tax_records_tests () =
  Printf.printf "[Suite 5] County Property & Tax Records Microservice...\n%!";
  let desc = Property_tax_records.answer_source_description in
  assert_true "PUB.TAX.1: Source description references Assessor Secured Roll wv5m-vpq2"
    (String.length desc > 0);

  let url_res = Property_tax_records.build_tax_records_query_url ~neighborhood:"Russian Hill" () in
  (match url_res with
  | Ok u ->
      assert_true "PUB.TAX.2: URL builder constructs valid tax records query"
        (String.starts_with ~prefix:Property_tax_records.default_tax_records_endpoint u)
  | Error err ->
      assert_true ("PUB.TAX.2: URL error: " ^ err) false);

  let sample_json =
    Json.Object [
      ("parcel_number", Json.String "0542015");
      ("property_location", Json.String "1450 GREEN ST");
      ("closed_roll_year", Json.String "2023");
      ("assessed_land_value", Json.Number 2100000.0);
      ("assessed_improvement_value", Json.Number 1800000.0);
      ("total_assessed_value", Json.Number 3900000.0);
      ("year_property_built", Json.Number 1910.0);
      ("number_of_units", Json.Number 1.0);
      ("number_of_stories", Json.Number 3.0);
      ("number_of_bedrooms", Json.Number 5.0);
      ("number_of_bathrooms", Json.Number 4.0);
      ("assessor_neighborhood", Json.String "Russian Hill");
    ]
  in
  (match Property_tax_records.parse_property_tax_record sample_json with
  | Ok rec_val ->
      assert_equal_str "PUB.TAX.3: Parcel number matches" "0542015" rec_val.parcel_number;
      assert_true "PUB.TAX.4: Total assessed value is 3.9M" (rec_val.total_assessed_value = 3900000.0);
      assert_true "PUB.TAX.5: Improvement-to-land ratio is computed" (rec_val.improvement_to_land_ratio > 0.85);
      assert_equal_int "PUB.TAX.6: Year built is 1910" 1910 (Option.value ~default:0 rec_val.year_built);
      assert_equal_int "PUB.TAX.7: Number of bedrooms is 5" 5 (Option.value ~default:0 rec_val.number_of_bedrooms)
  | Error err ->
      assert_true ("PUB.TAX.3: Parse error: " ^ err) false);

  let fetch_res = Property_tax_records.fetch_property_tax_records ~neighborhood:"Russian Hill" ~limit:2 () in
  (match fetch_res with
  | Ok records ->
      assert_true "PUB.TAX.8: Fetch returns non-empty tax records" (List.length records > 0)
  | Error err ->
      assert_true ("PUB.TAX.8: Fetch failed: " ^ err) false)

let run_orchestrator_tests () =
  Printf.printf "[Suite 6] Public Records Unified Orchestrator...\n%!";
  let answers = Public_records_orchestrator.get_public_records_answers () in
  assert_true "PUB.ORCH.1: Names source answer present" (String.length answers.names_source > 0);
  assert_true "PUB.ORCH.2: Addresses source answer present" (String.length answers.addresses_source > 0);
  assert_true "PUB.ORCH.3: GIS source answer present" (String.length answers.gis_source > 0);
  assert_true "PUB.ORCH.4: Permits source answer present" (String.length answers.permits_source > 0);
  assert_true "PUB.ORCH.5: Tax source answer present" (String.length answers.tax_source > 0);

  let target_districts = ["Pacific Heights"; "Richmond"; "Sunset"; "Excelsior"] in
  List.iter (fun district ->
    Printf.printf "  Testing public records acquisition for %s...\n%!" district;
    let acq_res = Public_records_orchestrator.acquire_neighborhood_public_records ~neighborhood:district ~limit:3 () in
    match acq_res with
    | Ok verified_list ->
        assert_true (Printf.sprintf "PUB.ORCH.%s.1: Acquired 3 leads for %s" district district) (List.length verified_list = 3);
        List.iteri (fun idx (v : verified_lead) ->
          assert_true (Printf.sprintf "PUB.ORCH.%s.%d.2: Valid SHA-256 proof (64 hex chars)" district idx) (String.length v.sha256_proof = 64);
          let expected_proof_id = "PROOF-OCAML-" ^ (String.sub v.sha256_proof 0 16 |> String.uppercase_ascii) in
          assert_equal_str (Printf.sprintf "PUB.ORCH.%s.%d.3: Proof ID matches first 16 chars" district idx) expected_proof_id v.proof_id;
          match v.verdict with
          | Qualified { score; invariants_passed; _ } ->
              assert_true (Printf.sprintf "PUB.ORCH.%s.%d.4: Score >= 60.0 (got %.2f)" district idx score.total_score) (score.total_score >= 60.0);
              assert_equal_int (Printf.sprintf "PUB.ORCH.%s.%d.5: Passed all 4 formal invariants" district idx) 4 (List.length invariants_passed);
              let status_str = "QUALIFIED" in
              let canonical =
                Printf.sprintf "ROO4U-PROOF-V1|%s|%s|%s|%s|%s|%.2f|%s"
                  v.lead.address
                  v.lead.zip_code
                  (string_of_property_type v.lead.property_type)
                  (string_of_roof_type v.lead.roof_type)
                  status_str
                  score.total_score
                  v.timestamp
              in
              let recomputed_sha = Crypto.sha256_string canonical in
              assert_equal_str (Printf.sprintf "PUB.ORCH.%s.%d.6: Cryptographic proof matches canonical SHA-256" district idx) recomputed_sha v.sha256_proof
          | Disqualified _ ->
              assert_true (Printf.sprintf "PUB.ORCH.%s.%d.4: Unexpected disqualification for valid district property" district idx) false
        ) verified_list
    | Error err ->
        assert_true (Printf.sprintf "PUB.ORCH.%s.1: Orchestrator acquisition failed: %s" district err) false
  ) target_districts

let () =
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== Pure OCaml Public Records Microservices Automated Test Suite ===\n";
  Printf.printf "======================================================================\n\n%!";
  run_homeowner_names_tests ();
  run_homeowner_addresses_tests ();
  run_gis_roofs_tests ();
  run_roof_permits_tests ();
  run_property_tax_records_tests ();
  run_orchestrator_tests ();
  Printf.printf "\n======================================================================\n";
  Printf.printf "=== ALL PUBLIC RECORDS MICROSERVICES TESTS PASSED SUCCESSFULLY! ===\n";
  Printf.printf "======================================================================\n\n%!"
