open Roof_engine
open Types
open Invariants
open Gis_roofs

let test_counter = ref 0
let pass_counter = ref 0
let fail_counter = ref 0

(** [record_assertion test_name condition] updates test counters and prints result *)
let record_assertion (test_name : string) (condition : bool) : unit =
  incr test_counter;
  if condition then (
    incr pass_counter;
    Printf.printf "  [PASS] %s\n%!" test_name
  ) else (
    incr fail_counter;
    Printf.printf "  [FAIL] %s\n%!" test_name
  )

(** [all_roof_types] enumerates all 8 constructors of type roof_type *)
let all_roof_types : roof_type list = [
  Victorian;
  Flat;
  Mansard;
  Gable;
  Hip;
  Metal;
  Unknown;
  Other "CustomMembrane";
]

(** [all_property_types] enumerates all 8 constructors of type property_type *)
let all_property_types : property_type list = [
  SingleFamily;
  MultiUnit2To4;
  MultiUnit5Plus;
  Commercial;
  MixedUse;
  Condo;
  Unknown;
  Other "IndustrialWarehouse";
]

(** [make_lead_stub r_type p_type] constructs a minimal raw_lead for invariant testing *)
let make_lead_stub (r_type : roof_type) (p_type : property_type) : raw_lead = {
  address = "2223 Pacific Ave";
  zip_code = "94115";
  property_type = p_type;
  roof_type = r_type;
  property_type_raw = Some (string_of_property_type p_type);
  roof_type_raw = Some (string_of_roof_type r_type);
  estimated_value = Some 3500000.0;
  owner_name = Some "Benchmark Owner";
  is_hoa = false;
  is_rental = false;
  apn = Some "0576-010";
  last_roof_permit_date = None;
  roof_age_years = Some 22.0;
  year_built = Some 1900;
  phone_number = Some "415-555-0199";
  permits = [];
}

(** [test_pitch_boundaries ()] tests boundary pitch values and edge conditions *)
let test_pitch_boundaries () : unit =
  Printf.printf "\n[CHALLENGE SECTION 1: Boundary Pitch Values]\n%!";

  let flat_0 = classify_roof_morphology {
    pitch_deg = Some 0.0;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.0_DEG: Pitch 0.0 deg classifies as Flat" (flat_0 = Flat);

  let flat_5_0 = classify_roof_morphology {
    pitch_deg = Some 5.0;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.5_0_DEG: Pitch 5.0 deg boundary classifies as Flat" (flat_5_0 = Flat);

  let gable_5_00001 = classify_roof_morphology {
    pitch_deg = Some 5.00001;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.5_00001_DEG: Pitch 5.00001 deg classifies as Gable" (gable_5_00001 = Gable);

  let gable_5_1 = classify_roof_morphology {
    pitch_deg = Some 5.1;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.5_1_DEG: Pitch 5.1 deg classifies as Gable" (gable_5_1 = Gable);

  let gable_30_0_historic = classify_roof_morphology {
    pitch_deg = Some 30.0;
    height_delta_ft = Some 8.0;
    year_built = Some 1900;
    style_tag = None;
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.30_0_HISTORIC: Pitch exactly 30.0 deg on 1900 build falls to Gable" (gable_30_0_historic = Gable);

  let vic_30_00001_historic = classify_roof_morphology {
    pitch_deg = Some 30.00001;
    height_delta_ft = Some 8.0;
    year_built = Some 1900;
    style_tag = None;
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.30_00001_HISTORIC: Pitch 30.00001 deg on 1900 build classifies as Victorian" (vic_30_00001_historic = Victorian);

  let vic_30_1_historic = classify_roof_morphology {
    pitch_deg = Some 30.1;
    height_delta_ft = Some 8.0;
    year_built = Some 1915;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.30_1_HISTORIC: Pitch 30.1 deg on 1915 build classifies as Victorian" (vic_30_1_historic = Victorian);

  let gable_30_1_modern = classify_roof_morphology {
    pitch_deg = Some 30.1;
    height_delta_ft = Some 8.0;
    year_built = Some 1916;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.30_1_MODERN: Pitch 30.1 deg on 1916 build classifies as Gable" (gable_30_1_modern = Gable);

  let vic_45_historic = classify_roof_morphology {
    pitch_deg = Some 45.0;
    height_delta_ft = Some 12.0;
    year_built = Some 1895;
    style_tag = None;
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.45_HISTORIC: Pitch 45.0 deg on 1895 build classifies as Victorian" (vic_45_historic = Victorian);

  let gable_45_modern = classify_roof_morphology {
    pitch_deg = Some 45.0;
    height_delta_ft = Some 12.0;
    year_built = Some 1965;
    style_tag = None;
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.45_MODERN: Pitch 45.0 deg on 1965 build classifies as Gable" (gable_45_modern = Gable);

  let vic_75_historic = classify_roof_morphology {
    pitch_deg = Some 75.0;
    height_delta_ft = Some 18.0;
    year_built = Some 1890;
    style_tag = None;
    material_desc = None;
    polygon_points = 10;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.75_HISTORIC: Pitch 75.0 deg on 1890 build classifies as Victorian" (vic_75_historic = Victorian);

  let mansard_75 = classify_roof_morphology {
    pitch_deg = Some 75.0;
    height_delta_ft = Some 14.0;
    year_built = Some 1920;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = Some "mansard";
  } in
  record_assertion "PITCH.BVA.75_MANSARD_SHAPE: Pitch 75.0 deg with mansard shape classifies as Mansard" (mansard_75 = Mansard);

  let gable_89_9 = classify_roof_morphology {
    pitch_deg = Some 89.9;
    height_delta_ft = None;
    year_built = Some 1950;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.89_9_DEG: Pitch 89.9 deg classifies as Gable" (gable_89_9 = Gable);

  let unknown_90_0 = classify_roof_morphology {
    pitch_deg = Some 90.0;
    height_delta_ft = None;
    year_built = Some 1900;
    style_tag = None;
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.90_0_WALL: Pitch 90.0 deg vertical surface classifies as Unknown" (unknown_90_0 = Unknown);

  let unknown_95_0 = classify_roof_morphology {
    pitch_deg = Some 95.0;
    height_delta_ft = None;
    year_built = Some 1900;
    style_tag = None;
    material_desc = None;
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.95_0_OVERHANG: Pitch 95.0 deg overhang classifies as Unknown" (unknown_95_0 = Unknown);

  let flat_negative_pitch = classify_roof_morphology {
    pitch_deg = Some (-2.5);
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.NEGATIVE: Negative pitch <= 5.0 deg classifies as Flat" (flat_negative_pitch = Flat);

  let unknown_nan_pitch = classify_roof_morphology {
    pitch_deg = Some nan;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.NAN: NaN pitch safely resolves to Unknown" (unknown_nan_pitch = Unknown);

  let unknown_infinity_pitch = classify_roof_morphology {
    pitch_deg = Some infinity;
    height_delta_ft = None;
    year_built = None;
    style_tag = None;
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "PITCH.BVA.INFINITY: Infinity pitch safely resolves to Unknown" (unknown_infinity_pitch = Unknown)

(** [test_historic_era_boundaries ()] tests 1915 vs 1916 boundary and geometric thresholds *)
let test_historic_era_boundaries () : unit =
  Printf.printf "\n[CHALLENGE SECTION 2: Historic Era Boundaries (1915 vs 1916)]\n%!";

  let vic_1914 = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1914;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.BVA.1914: Pre-1915 construction classifies as Victorian" (vic_1914 = Victorian);

  let vic_1915 = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1915;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.BVA.1915: Exactly 1915 construction classifies as Victorian" (vic_1915 = Victorian);

  let gable_1916 = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1916;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.BVA.1916: Post-1915 (1916) construction disqualifies Victorian into Gable" (gable_1916 = Gable);

  let gable_1917 = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1917;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.BVA.1917: 1917 construction classifies as Gable" (gable_1917 = Gable);

  let vic_height_delta_8_0 = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = Some 8.0;
    year_built = Some 1910;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.HEIGHT.8_0_FT: Height delta 8.0 ft without pitch classifies as Victorian" (vic_height_delta_8_0 = Victorian);

  let unknown_height_delta_7_9 = classify_roof_morphology {
    pitch_deg = None;
    height_delta_ft = Some 7.9;
    year_built = Some 1910;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.HEIGHT.7_9_FT: Height delta 7.9 ft fails Victorian threshold and yields Unknown" (unknown_height_delta_7_9 = Unknown);

  let gable_points_5 = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1912;
    style_tag = None;
    material_desc = None;
    polygon_points = 5;
    osm_shape = None;
  } in
  record_assertion "ERA.POINTS.5_PTS: 5 polygon vertices fails Victorian threshold (>= 6) and yields Gable" (gable_points_5 = Gable);

  let vic_points_6 = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1912;
    style_tag = None;
    material_desc = None;
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "ERA.POINTS.6_PTS: Exactly 6 polygon vertices satisfies Victorian threshold" (vic_points_6 = Victorian);

  let vic_points_12 = classify_roof_morphology {
    pitch_deg = Some 40.0;
    height_delta_ft = Some 15.0;
    year_built = Some 1888;
    style_tag = None;
    material_desc = None;
    polygon_points = 12;
    osm_shape = None;
  } in
  record_assertion "ERA.POINTS.12_PTS: Complex 12-vertex footprint classifies as Victorian" (vic_points_12 = Victorian);

  let vic_style_tag_bypasses_year = classify_roof_morphology {
    pitch_deg = Some 25.0;
    height_delta_ft = Some 6.0;
    year_built = Some 1928;
    style_tag = Some "Queen Anne Victorian";
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "ERA.STYLE_BYPASS: Explicit Victorian style tag classifies as Victorian regardless of year" (vic_style_tag_bypasses_year = Victorian)

(** [test_styles_and_materials ()] tests architectural styles, material strings, and conflict resolutions *)
let test_styles_and_materials () : unit =
  Printf.printf "\n[CHALLENGE SECTION 3: Complex Architectural Styles & Materials]\n%!";

  let style_cases = [
    ("Victorian uppercase", Some "VICTORIAN", Victorian);
    ("Queen Anne mixed case", Some "qUeEn aNnE", Victorian);
    ("Italianate title case", Some "Italianate", Victorian);
    ("Edwardian lowercase", Some "edwardian", Victorian);
    ("Stick-Eastlake variant", Some "San Francisco Stick Style", Victorian);
    ("Second Empire style", Some "Second Empire", Mansard);
    ("Beaux-Arts style", Some "Beaux-Arts classic", Mansard);
    ("Mansard explicit style", Some "Mansard Villa", Mansard);
    ("Spanish Revival (non-target)", Some "Spanish Colonial Revival", Gable);
    ("Craftsman (non-target)", Some "Craftsman Bungalow", Gable);
    ("Tudor Revival (non-target)", Some "Tudor Revival", Gable);
  ] in
  List.iter (fun (label, tag, expected) ->
    let res = classify_roof_morphology {
      pitch_deg = Some 20.0;
      height_delta_ft = Some 5.0;
      year_built = Some 1940;
      style_tag = tag;
      material_desc = None;
      polygon_points = 4;
      osm_shape = None;
    } in
    record_assertion (Printf.sprintf "STYLE.%s" label) (res = expected)
  ) style_cases;

  let mat_cases = [
    ("Tar and gravel standard", Some "Tar and Gravel multi-layer", Flat);
    ("TAR AND GRAVEL uppercase", Some "TAR AND GRAVEL", Flat);
    ("Built-Up Roof hyphenated", Some "Built-Up Roof (BUR)", Flat);
    ("Built up roof spaced", Some "built up roofing system", Flat);
    ("Modified bitumen", Some "Modified Bitumen APP membrane", Flat);
    ("Torch-down application", Some "Torch applied cap sheet", Flat);
    ("TPO single-ply", Some "White reflective TPO membrane", Flat);
    ("EPDM synthetic rubber", Some "0.060 black EPDM sheet", Flat);
    ("Standing seam metal", Some "Standing seam coated steel", Metal);
    ("Corrugated metal", Some "Galvanized corrugated metal roof", Metal);
    ("Architectural composition shingle", Some "CertainTeed asphalt composition shingle", Gable);
    ("Clay barrel tile", Some "Spanish red clay barrel tile", Gable);
    ("Natural slate", Some "Vermont natural slate tiles", Gable);
  ] in
  List.iter (fun (label, mat, expected) ->
    let res = classify_roof_morphology {
      pitch_deg = Some 15.0;
      height_delta_ft = Some 4.0;
      year_built = Some 1960;
      style_tag = None;
      material_desc = mat;
      polygon_points = 4;
      osm_shape = None;
    } in
    record_assertion (Printf.sprintf "MAT.%s" label) (res = expected)
  ) mat_cases;

  let conflict_mansard_vs_tar = classify_roof_morphology {
    pitch_deg = Some 10.0;
    height_delta_ft = Some 3.0;
    year_built = Some 1900;
    style_tag = Some "Second Empire Mansard";
    material_desc = Some "Tar and gravel flat deck";
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "CONFLICT.MANSARD_PRECEDENCE: Mansard style takes precedence over tar material" (conflict_mansard_vs_tar = Mansard);

  let conflict_flat_vs_victorian = classify_roof_morphology {
    pitch_deg = Some 3.0;
    height_delta_ft = Some 1.0;
    year_built = Some 1895;
    style_tag = Some "Italianate Victorian";
    material_desc = Some "Tar and gravel flat roof behind parapet";
    polygon_points = 6;
    osm_shape = None;
  } in
  record_assertion "CONFLICT.FLAT_PRECEDENCE: Pitch <= 5 deg takes precedence over Victorian style" (conflict_flat_vs_victorian = Flat);

  let conflict_tpo_vs_metal_trim = classify_roof_morphology {
    pitch_deg = Some 12.0;
    height_delta_ft = Some 2.0;
    year_built = Some 2015;
    style_tag = None;
    material_desc = Some "TPO membrane with standing seam metal edge trim";
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "CONFLICT.TPO_PRECEDENCE: TPO membrane takes precedence over metal edge trim" (conflict_tpo_vs_metal_trim = Flat);

  let conflict_victorian_vs_metal = classify_roof_morphology {
    pitch_deg = Some 35.0;
    height_delta_ft = Some 10.0;
    year_built = Some 1900;
    style_tag = Some "Queen Anne";
    material_desc = Some "Standing seam metal decorative roof turret";
    polygon_points = 8;
    osm_shape = None;
  } in
  record_assertion "CONFLICT.VIC_VS_METAL: Victorian style takes precedence over metal material" (conflict_victorian_vs_metal = Victorian);

  let collision_mortar = classify_roof_morphology {
    pitch_deg = Some 20.0;
    height_delta_ft = Some 5.0;
    year_built = Some 1980;
    style_tag = None;
    material_desc = Some "Clay tile embedded in mortar bed";
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "COLLISION.MORTAR_TAR: Substring 'tar' inside 'mortar' triggers Flat classification" (collision_mortar = Flat);

  let collision_shiplap = classify_roof_morphology {
    pitch_deg = Some 20.0;
    height_delta_ft = Some 5.0;
    year_built = Some 1980;
    style_tag = Some "Shiplap siding exterior";
    material_desc = None;
    polygon_points = 4;
    osm_shape = None;
  } in
  record_assertion "COLLISION.SHIPLAP_HIP: Substring 'hip' inside 'shiplap' triggers Hip classification" (collision_shiplap = Hip)

(** [test_inv1_cartesian_product ()] tests all 64 combinations of roof_type x property_type *)
let test_inv1_cartesian_product () : unit =
  Printf.printf "\n[CHALLENGE SECTION 4: Full 64-Combination Matrix against INV-1]\n%!";

  let satisfied_cells = ref 0 in
  let violated_cells = ref 0 in

  List.iter (fun r_type ->
    List.iter (fun p_type ->
      let status = check_inv1_physical r_type p_type in
      let lead_stub = make_lead_stub r_type p_type in
      let helper_res = check_inv1 lead_stub in

      let expected_satisfied =
        (r_type = Victorian || r_type = Flat || r_type = Mansard) &&
        (p_type = SingleFamily || p_type = MultiUnit2To4)
      in

      let status_ok =
        if expected_satisfied then (
          incr satisfied_cells;
          match status with
          | Satisfied msg -> String.length msg > 0 && helper_res = Ok ()
          | Violated _ -> false
        ) else (
          incr violated_cells;
          match status with
          | Violated v ->
              v.code = INV1_Physical &&
              String.length v.message > 0 &&
              (match helper_res with Error m -> m = v.message | Ok () -> false)
          | Satisfied _ -> false
        )
      in
      record_assertion (Printf.sprintf "INV1.MATRIX.%s_x_%s" (string_of_roof_type r_type) (string_of_property_type p_type)) status_ok
    ) all_property_types
  ) all_roof_types;

  record_assertion "INV1.MATRIX.TOTAL_CELLS: Exactly 64 cells evaluated" (!satisfied_cells + !violated_cells = 64);
  record_assertion "INV1.MATRIX.SATISFIED_COUNT: Exactly 6 cells satisfy INV-1 (3 roofs x 2 props)" (!satisfied_cells = 6);
  record_assertion "INV1.MATRIX.VIOLATED_COUNT: Exactly 58 cells violate INV-1 (64 - 6)" (!violated_cells = 58)

(** [test_synthetic_stress_harness ()] stress-tests classify_roof_morphology with 1000 pseudo-random inputs *)
let test_synthetic_stress_harness () : unit =
  Printf.printf "\n[CHALLENGE SECTION 5: Synthetic Stress Harness (1000 Iterations)]\n%!";

  let pitch_candidates = [None; Some 0.0; Some 2.5; Some 5.0; Some 5.1; Some 15.0; Some 30.0; Some 30.1; Some 45.0; Some 75.0; Some 90.0; Some 120.0; Some (-5.0)] in
  let year_candidates = [None; Some 1850; Some 1900; Some 1906; Some 1915; Some 1916; Some 1930; Some 1975; Some 2024] in
  let style_candidates = [None; Some "Victorian"; Some "queen anne"; Some "Italianate"; Some "Second Empire"; Some "Ranch"; Some "Spanish"; Some ""] in
  let mat_candidates = [None; Some "tar and gravel"; Some "TPO membrane"; Some "Modified Bitumen"; Some "standing seam metal"; Some "asphalt shingle"; Some "clay tile"] in
  let shape_candidates = [None; Some "flat"; Some "mansard"; Some "hip"; Some "gable"; Some "metal"; Some "unknown"] in
  let point_candidates = [0; 3; 4; 5; 6; 8; 12; 25] in

  let exception_caught = ref false in
  let non_empty_classifications = ref 0 in

  for i = 1 to 1000 do
    let pitch = List.nth pitch_candidates (i mod List.length pitch_candidates) in
    let year = List.nth year_candidates ((i * 3) mod List.length year_candidates) in
    let style = List.nth style_candidates ((i * 7) mod List.length style_candidates) in
    let mat = List.nth mat_candidates ((i * 11) mod List.length mat_candidates) in
    let shape = List.nth shape_candidates ((i * 13) mod List.length shape_candidates) in
    let points = List.nth point_candidates ((i * 17) mod List.length point_candidates) in

    try
      let res = classify_roof_morphology {
        pitch_deg = pitch;
        height_delta_ft = Some 10.0;
        year_built = year;
        style_tag = style;
        material_desc = mat;
        polygon_points = points;
        osm_shape = shape;
      } in
      let _str = string_of_roof_type res in
      incr non_empty_classifications
    with _ ->
      exception_caught := true
  done;

  record_assertion "STRESS.NO_EXCEPTIONS: 1000 iterations completed without unhandled exceptions" (not !exception_caught);
  record_assertion "STRESS.ALL_RESOLVED: 1000 iterations returned valid typed classifications" (!non_empty_classifications = 1000)

let () =
  Printf.printf "\n==================================================================\n";
  Printf.printf "=== Roo4u Morphology & Invariants Empirical Challenger Harness ===\n";
  Printf.printf "==================================================================\n";

  test_pitch_boundaries ();
  test_historic_era_boundaries ();
  test_styles_and_materials ();
  test_inv1_cartesian_product ();
  test_synthetic_stress_harness ();

  Printf.printf "\n==================================================================\n";
  Printf.printf "=== CHALLENGER SUMMARY: %d Total, %d Passed, %d Failed ===\n"
    !test_counter !pass_counter !fail_counter;
  Printf.printf "==================================================================\n\n%!";

  if !fail_counter > 0 then exit 1
  else exit 0
