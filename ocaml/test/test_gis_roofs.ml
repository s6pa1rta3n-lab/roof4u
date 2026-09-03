open Roof_engine
open Types
open Invariants
open Gis_roofs

let test_count = ref 0
let pass_count = ref 0
let fail_count = ref 0

let check_assert name condition =
  incr test_count;
  if condition then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n%!" name
  )

let () =
  Printf.printf "\n======================================================\n";
  Printf.printf "=== Roo4u GIS Component Integration (gods-eye-view) ===\n";
  Printf.printf "======================================================\n\n";

  Printf.printf "[Section 1] GeoJSON Parsing & Boundary Ingestion...\n%!";

  let load_res = load_sf_neighborhoods () in
  check_assert "GEOJSON.LOAD: Successfully loads san-francisco.json"
    (match load_res with Ok _ -> true | Error _ -> false);

  let boundaries = get_sf_neighborhoods () in
  check_assert "GEOJSON.COUNT: Exactly 41 Analysis Neighborhoods loaded"
    (List.length boundaries = 41);

  let target_names = [
    "Pacific Heights";
    "Presidio Heights";
    "Marina";
    "Russian Hill";
    "Seacliff";
  ] in
  List.iter (fun target ->
    let found = List.exists (fun nb -> nb.name = target) boundaries in
    check_assert (Printf.sprintf "GEOJSON.TARGET_EXISTS: '%s' present in dataset" target) found
  ) target_names;

  List.iter (fun nb ->
    let (min_lon, min_lat, max_lon, max_lat) = nb.bbox in
    let valid_bbox = min_lon < max_lon && min_lat < max_lat in
    check_assert (Printf.sprintf "GEOJSON.BBOX.VALID: '%s' bounding box strictly ordered" nb.name) valid_bbox
  ) boundaries;

  let malformed_res = parse_neighborhood_geojson "{ invalid json" in
  check_assert "GEOJSON.ERR.SYNTAX: Syntax error returns Error result"
    (match malformed_res with Error _ -> true | Ok _ -> false);

  let missing_feats_res = parse_neighborhood_geojson "{\"type\":\"FeatureCollection\"}" in
  check_assert "GEOJSON.ERR.SCHEMA: Missing 'features' array returns Error result"
    (match missing_feats_res with Error _ -> true | Ok _ -> false);

  Printf.printf "\n[Section 2] Ray-Casting Containment on Benchmark Properties...\n%!";

  let benchmark_cases = [
    ("2223 Pacific Ave", 37.7924, -122.4342, "Pacific Heights");
    ("1940 Webster St", 37.7895, -122.4320, "Pacific Heights");
    ("2500 Broadway", 37.7940, -122.4385, "Pacific Heights");
    ("2820 Scott St", 37.7938, -122.4410, "Pacific Heights");
    ("3645 Washington St", 37.7890, -122.4540, "Presidio Heights");
    ("3800 Clay St", 37.7882, -122.4560, "Presidio Heights");
    ("3450 Sacramento St", 37.7875, -122.4505, "Presidio Heights");
    ("1840 Chestnut St", 37.8005, -122.4348, "Marina");
    ("2340 Union St", 37.7972, -122.4395, "Marina");
    ("2845 Fillmore St", 37.7961, -122.4361, "Marina");
    ("1450 Green St", 37.7985, -122.4225, "Russian Hill");
    ("2150 Hyde St", 37.8012, -122.4180, "Russian Hill");
    ("1000 Lombard St", 37.8020, -122.4190, "Russian Hill");
    ("300 Sea Cliff Ave", 37.7885, -122.4880, "Seacliff");
    ("254 El Camino Del Mar", 37.7862, -122.4845, "Seacliff");
    ("130 26th Ave", 37.7870, -122.4865, "Seacliff");
  ] in
  List.iter (fun (addr, lat, lon, expected_nb) ->
    let in_nb = point_in_neighborhood lat lon expected_nb in
    check_assert (Printf.sprintf "PIP.CONTAIN: %s in %s (lat,lon)" addr expected_nb) in_nb;
    let in_nb_trans = point_in_neighborhood lon lat expected_nb in
    check_assert (Printf.sprintf "PIP.CONTAIN.TRANS: %s in %s (lon,lat auto-normal)" addr expected_nb) in_nb_trans;
    let found_opt = find_neighborhood lat lon in
    check_assert (Printf.sprintf "PIP.RESOLVE: %s resolves to %s" addr expected_nb)
      (found_opt = Some expected_nb);
    let in_affluent = is_point_in_affluent_corridor lat lon in
    check_assert (Printf.sprintf "PIP.AFFLUENT: %s is in affluent corridor" addr) in_affluent
  ) benchmark_cases;

  Printf.printf "\n[Section 3] Negative Boundary Controls & Excluded Neighborhoods...\n%!";

  let negative_cases = [
    ("2223 Pacific Ave NOT in Marina", 37.7924, -122.4342, "Marina");
    ("1840 Chestnut St NOT in Pacific Heights", 37.8005, -122.4348, "Pacific Heights");
    ("3645 Washington St NOT in Seacliff", 37.7890, -122.4540, "Seacliff");
    ("Sunset point NOT in Pacific Heights", 37.7612, -122.4785, "Pacific Heights");
    ("Financial District point NOT in Seacliff", 37.7900, -122.4000, "Seacliff");
    ("San Jose coordinate NOT in Pacific Heights", 37.3382, -121.8863, "Pacific Heights");
  ] in
  List.iter (fun (desc, lat, lon, target_nb) ->
    let inside = point_in_neighborhood lat lon target_nb in
    check_assert (Printf.sprintf "PIP.NEG: %s" desc) (not inside)
  ) negative_cases;

  let non_affluent_coords = [
    ("Sunset", 37.7612, -122.4785);
    ("Excelsior", 37.7265, -122.4330);
    ("Bayview", 37.7300, -122.3800);
  ] in
  List.iter (fun (name, lat, lon) ->
    let in_corridor = is_point_in_affluent_corridor lat lon in
    check_assert (Printf.sprintf "PIP.NON_AFFLUENT: %s coordinate not in affluent corridor" name) (not in_corridor)
  ) non_affluent_coords;

  Printf.printf "\n[Section 4] Neighborhood Targeting, Aliasing & Affluence Tiers...\n%!";

  let affluent_names = [
    "Pacific Heights";
    "pacific heights";
    "PACIFIC HEIGHTS";
    "Pac Heights";
    "Presidio Heights";
    "presidio hts";
    "Marina";
    "marina";
    "Cow Hollow";
    "cow hollow";
    "Seacliff";
    "Sea Cliff";
    "Russian Hill";
  ] in
  List.iter (fun name ->
    check_assert (Printf.sprintf "ALIAS.AFFLUENT: '%s' recognized as affluent" name)
      (is_affluent_neighborhood name)
  ) affluent_names;

  let non_affluent_names = [
    "Sunset";
    "Excelsior";
    "Mission";
    "Bayview Hunters Point";
    "Tenderloin";
    "Visitacion Valley";
  ] in
  List.iter (fun name ->
    check_assert (Printf.sprintf "ALIAS.NON_AFFLUENT: '%s' rejected" name)
      (not (is_affluent_neighborhood name))
  ) non_affluent_names;

  check_assert "TIER.ULTRA: Pacific Heights is Tier 1"
    (affluence_tier_of_neighborhood "Pacific Heights" = Tier1_UltraAffluent);
  check_assert "TIER.ULTRA.ALIAS: Cow Hollow is Tier 1 (Marina)"
    (affluence_tier_of_neighborhood "Cow Hollow" = Tier1_UltraAffluent);
  check_assert "TIER.AFFLUENT: Noe Valley is Tier 2"
    (affluence_tier_of_neighborhood "Noe Valley" = Tier2_Affluent);
  check_assert "TIER.MODERATE: Sunset is Tier 3"
    (affluence_tier_of_neighborhood "Sunset" = Tier3_Moderate);

  check_assert "COW_HOLLOW.CONTAIN: 2340 Union St resolves in 'Cow Hollow' query"
    (point_in_neighborhood 37.7972 (-122.4395) "Cow Hollow");
  check_assert "SEA_CLIFF.CONTAIN: 300 Sea Cliff Ave resolves in 'Sea Cliff' query"
    (point_in_neighborhood 37.7885 (-122.4880) "Sea Cliff");

  Printf.printf "\n[Section 5] Candidate Roofs Catalog & Pipeline Mapping...\n%!";

  let all_candidates = fetch_gods_eye_candidates () in
  check_assert "CANDIDATES.TOTAL: Complete catalog has 16 candidate roofs"
    (List.length all_candidates = 16);

  let pac_candidates = fetch_gods_eye_candidates ~neighborhood:"Pacific Heights" () in
  check_assert "CANDIDATES.PAC: Exactly 4 candidates in Pacific Heights"
    (List.length pac_candidates = 4);

  let cow_candidates = fetch_gods_eye_candidates ~neighborhood:"Cow Hollow" () in
  check_assert "CANDIDATES.COW_HOLLOW: Cow Hollow returns Marina candidates"
    (List.length cow_candidates = 3);

  let zip_candidates = fetch_gods_eye_candidates ~zip:"94123" () in
  check_assert "CANDIDATES.ZIP_94123: Marina zip code filters 3 candidates"
    (List.length zip_candidates = 3);

  List.iter (fun (c : candidate_roof) ->
    let raw = candidate_to_raw_lead c in
    check_assert (Printf.sprintf "MAP.RAW_LEAD.ADDR: %s preserved" c.address)
      (raw.address = c.address && raw.zip_code = c.zip_code);
    check_assert (Printf.sprintf "MAP.RAW_LEAD.ROOF: %s roof type matches" c.address)
      (raw.roof_type = c.roof_type);
    check_assert (Printf.sprintf "MAP.RAW_LEAD.DEFAULTS: %s non-HOA & non-rental" c.address)
      (raw.is_hoa = false && raw.is_rental = false);

    let gis = candidate_to_gis_record c in
    check_assert (Printf.sprintf "MAP.GIS.SIZE: %s square footage matches" c.address)
      (gis.roof_size_sqft = c.footprint_sqft);
    check_assert (Printf.sprintf "MAP.GIS.TYPE: %s roof type classified" c.address)
      (gis.roof_type_classified = c.roof_type);

    let json_ast = candidate_roof_to_json c in
    check_assert (Printf.sprintf "MAP.JSON: %s serializes to JSON Object" c.address)
      (match json_ast with Json.Object _ -> true | _ -> false)
  ) all_candidates;

  Printf.printf "\n[Section 6] Roof Morphology Classification Rules & Boundary Value Analysis...\n%!";

  let flat_0 = classify_roof_morphology {
    pitch_deg = Some 0.0;
    height_delta_ft = Some 0.0;
    year_built = Some 1930;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.FLAT.0_DEG: 0.0 deg pitch classified as Flat" (flat_0 = Flat);

  let flat_5 = classify_roof_morphology {
    pitch_deg = Some 5.0;
    height_delta_ft = Some 1.5;
    year_built = Some 1925;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.FLAT.5_DEG: 5.0 deg boundary pitch classified as Flat" (flat_5 = Flat);

  let flat_shape = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = Some 1940;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = Some "flat";
  } in
  check_assert "MORPH.FLAT.SHAPE: 'flat' shape classified as Flat" (flat_shape = Flat);

  let flat_mat_tar = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = Some 1960;
    style_tag = None;
    material_desc = Some "Built-up tar and gravel";
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.FLAT.MAT_TAR: Tar and gravel classified as Flat" (flat_mat_tar = Flat);

  let flat_mat_tpo = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = Some 2010;
    style_tag = None;
    material_desc = Some "TPO membrane single-ply";
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.FLAT.MAT_TPO: TPO membrane classified as Flat" (flat_mat_tpo = Flat);

  let flat_mat_bitumen = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = Some 1985;
    style_tag = None;
    material_desc = Some "Modified Bitumen torch-applied";
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.FLAT.MAT_BITUMEN: Modified Bitumen classified as Flat" (flat_mat_bitumen = Flat);

  let vic_queen_anne = classify_roof_morphology {
    pitch_deg = Some 45.0;
    height_delta_ft = Some 14.0;
    year_built = Some 1892;
    style_tag = Some "Queen Anne";
    material_desc = Some "Cedar shake shingles";
    polygon_points = 10;
    osm_shape = None;
  } in
  check_assert "MORPH.VIC.QUEEN_ANNE: Queen Anne style classified as Victorian" (vic_queen_anne = Victorian);

  let vic_italianate = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 9.0;
    year_built = Some 1878;
    style_tag = Some "Italianate";
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  check_assert "MORPH.VIC.ITALIANATE: Italianate style classified as Victorian" (vic_italianate = Victorian);

  let vic_edwardian = classify_roof_morphology {
    pitch_deg = Some 32.0;
    height_delta_ft = Some 8.5;
    year_built = Some 1908;
    style_tag = Some "Edwardian";
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  check_assert "MORPH.VIC.EDWARDIAN: Edwardian style classified as Victorian" (vic_edwardian = Victorian);

  let vic_bva_30_1 = classify_roof_morphology {
    pitch_deg = Some 30.1;
    height_delta_ft = Some 8.5;
    year_built = Some 1915;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  check_assert "MORPH.VIC.BVA_30_1: 30.1 deg pitch & 1915 year classified as Victorian" (vic_bva_30_1 = Victorian);

  let mansard_shape = classify_roof_morphology {
    pitch_deg = Some 70.0;
    height_delta_ft = Some 12.0;
    year_built = Some 1885;
    style_tag = None;
    material_desc = Some "Slate shingles";
    polygon_points = 8;
    osm_shape = Some "mansard";
  } in
  check_assert "MORPH.MANSARD.SHAPE: Mansard shape classified as Mansard" (mansard_shape = Mansard);

  let mansard_style = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = Some 1890;
    style_tag = Some "Second Empire Beaux-Arts";
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  check_assert "MORPH.MANSARD.STYLE: Second Empire style classified as Mansard" (mansard_style = Mansard);

  let gable_bva_5_1 = classify_roof_morphology {
    pitch_deg = Some 5.1;
    height_delta_ft = Some 2.0;
    year_built = Some 1960;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.INELIGIBLE.GABLE_5_1: 5.1 deg low pitch classified as Gable" (gable_bva_5_1 = Gable);

  let gable_tract = classify_roof_morphology {
    pitch_deg = Some 18.0;
    height_delta_ft = Some 5.0;
    year_built = Some 1955;
    style_tag = Some "Ranch Tract";
    material_desc = Some "Asphalt 3-tab shingle";
    polygon_points = 4;
    osm_shape = Some "gable";
  } in
  check_assert "MORPH.INELIGIBLE.GABLE_TRACT: 1955 tract gable classified as Gable" (gable_tract = Gable);

  let gable_bva_30 = classify_roof_morphology {
    pitch_deg = Some 30.0;
    height_delta_ft = Some 7.0;
    year_built = Some 1920;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.INELIGIBLE.GABLE_30: 30.0 deg boundary pitch classified as Gable" (gable_bva_30 = Gable);

  let gable_post1915 = classify_roof_morphology {
    pitch_deg = Some 32.0;
    height_delta_ft = Some 8.5;
    year_built = Some 1925;
    style_tag = Some "Craftsman";
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  check_assert "MORPH.INELIGIBLE.POST_1915: 1925 Craftsman with 32 deg pitch classified as Gable" (gable_post1915 = Gable);

  let hip_shape = classify_roof_morphology {
    pitch_deg = Some 20.0;
    height_delta_ft = Some 5.5;
    year_built = Some 1950;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = Some "hip";
  } in
  check_assert "MORPH.INELIGIBLE.HIP: Hip roof classified as Hip" (hip_shape = Hip);

  let metal_util = classify_roof_morphology {
    pitch_deg = Some 12.0;
    height_delta_ft = Some 4.0;
    year_built = Some 1970;
    style_tag = None;
    material_desc = Some "Standing seam corrugated metal";
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.INELIGIBLE.METAL: Metal roof classified as Metal" (metal_util = Metal);

  let wall_90 = classify_roof_morphology {
    pitch_deg = Some 90.0;
    height_delta_ft = Some 30.0;
    year_built = Some 1900;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.INELIGIBLE.90_DEG: 90.0 deg vertical surface classified as Unknown" (wall_90 = Unknown);

  let unknown_empty = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  check_assert "MORPH.UNKNOWN: Empty inputs classified as Unknown" (unknown_empty = Unknown);

  Printf.printf "\n[Section 7] Formal Invariant INV-1 Verification on Classified Roofs...\n%!";

  let inv1_vic_sfr = check_inv1_physical Victorian SingleFamily in
  check_assert "INV1.VIC.SFR: Victorian SFR satisfies INV-1"
    (match inv1_vic_sfr with Satisfied _ -> true | Violated _ -> false);

  let inv1_vic_multi = check_inv1_physical Victorian MultiUnit2To4 in
  check_assert "INV1.VIC.MULTI: Victorian MultiUnit2To4 satisfies INV-1"
    (match inv1_vic_multi with Satisfied _ -> true | Violated _ -> false);

  let inv1_flat_sfr = check_inv1_physical Flat SingleFamily in
  check_assert "INV1.FLAT.SFR: Flat SFR satisfies INV-1"
    (match inv1_flat_sfr with Satisfied _ -> true | Violated _ -> false);

  let inv1_flat_multi = check_inv1_physical Flat MultiUnit2To4 in
  check_assert "INV1.FLAT.MULTI: Flat MultiUnit2To4 satisfies INV-1"
    (match inv1_flat_multi with Satisfied _ -> true | Violated _ -> false);

  let inv1_man_sfr = check_inv1_physical Mansard SingleFamily in
  check_assert "INV1.MANSARD.SFR: Mansard SFR satisfies INV-1"
    (match inv1_man_sfr with Satisfied _ -> true | Violated _ -> false);

  let inv1_man_multi = check_inv1_physical Mansard MultiUnit2To4 in
  check_assert "INV1.MANSARD.MULTI: Mansard MultiUnit2To4 satisfies INV-1"
    (match inv1_man_multi with Satisfied _ -> true | Violated _ -> false);

  let inv1_gable_fail = check_inv1_physical Gable SingleFamily in
  check_assert "INV1.GABLE.DISQ: Gable SFR violates INV-1"
    (match inv1_gable_fail with Violated v -> v.code = INV1_Physical | Satisfied _ -> false);

  let inv1_hip_fail = check_inv1_physical Hip SingleFamily in
  check_assert "INV1.HIP.DISQ: Hip SFR violates INV-1"
    (match inv1_hip_fail with Violated v -> v.code = INV1_Physical | Satisfied _ -> false);

  let inv1_metal_fail = check_inv1_physical Metal SingleFamily in
  check_assert "INV1.METAL.DISQ: Metal SFR violates INV-1"
    (match inv1_metal_fail with Violated v -> v.code = INV1_Physical | Satisfied _ -> false);

  let inv1_condo_fail = check_inv1_physical Victorian Condo in
  check_assert "INV1.CONDO.DISQ: Victorian Condo violates INV-1"
    (match inv1_condo_fail with Violated v -> v.code = INV1_Physical | Satisfied _ -> false);

  let inv1_comm_fail = check_inv1_physical Flat Commercial in
  check_assert "INV1.COMM.DISQ: Flat Commercial violates INV-1"
    (match inv1_comm_fail with Violated v -> v.code = INV1_Physical | Satisfied _ -> false);

  let inv1_multi5_fail = check_inv1_physical Mansard MultiUnit5Plus in
  check_assert "INV1.MULTI5.DISQ: Mansard MultiUnit5Plus violates INV-1"
    (match inv1_multi5_fail with Violated v -> v.code = INV1_Physical | Satisfied _ -> false);

  List.iter (fun (c : candidate_roof) ->
    let status = check_inv1_physical c.roof_type c.property_type in
    check_assert (Printf.sprintf "INV1.CATALOG.%s: Physical invariant satisfied" c.address)
      (match status with Satisfied _ -> true | Violated _ -> false)
  ) all_candidates;

  Printf.printf "\n[Section 8] Preserved SODA Functions Verification...\n%!";

  let clean_addr = sanitize_address_query "123 Main St; DROP TABLE; 'test'" in
  check_assert "SODA.SANITIZE: Sanitizes malicious characters"
    (not (String.contains clean_addr ';') && not (String.contains clean_addr '='));

  let url_res = build_gis_roofs_query_url ~neighborhood:"Pacific Heights" ~limit:10 () in
  check_assert "SODA.URL: Builds valid SODA query URL"
    (match url_res with
     | Ok u -> String.starts_with ~prefix:default_gis_roofs_endpoint u && String.contains u '?'
     | Error _ -> false);

  let sample_json = Json.Object [
    ("address", Json.String "2223 Pacific Ave");
    ("parcel_number", Json.String "0576010");
    ("size_sf", Json.Number 3450.0);
    ("design", Json.String "Victorian");
  ] in
  let parse_rec_res = parse_gis_roof_record sample_json in
  check_assert "SODA.PARSE: Parses SODA JSON record"
    (match parse_rec_res with
     | Ok r -> r.property_location = "2223 Pacific Ave" && r.roof_type_classified = Victorian
     | Error _ -> false);

  check_assert "SODA.DESC: Public records source description non-empty"
    (String.length answer_source_description > 50);

  Printf.printf "\n======================================================\n";
  Printf.printf "=== TEST SUMMARY: %d Total, %d Passed, %d Failed ===\n"
    !test_count !pass_count !fail_count;
  Printf.printf "======================================================\n\n%!";

  if !fail_count > 0 then exit 1
  else exit 0
