(**
   test_spatial_pip_challenger.ml - Empirical Stress Testing Harness for Spatial Point-in-Polygon
   and Affluent Neighborhood Boundary Targeting in gis_roofs.ml.
*)

open Roof_engine
open Gis_roofs

let test_count = ref 0
let pass_count = ref 0
let fail_count = ref 0

(** [check_assert name condition] records pass or fail and increments counters. *)
let check_assert (name : string) (condition : bool) : unit =
  incr test_count;
  if condition then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" name
  ) else (
    incr fail_count;
    Printf.printf "  [FAIL] %s\n%!" name
  )

(** [find_target_boundary name boundaries] extracts a specific neighborhood boundary by name. *)
let find_target_boundary (name : string) (boundaries : neighborhood_boundary list) : neighborhood_boundary option =
  let norm_target = canonicalize_neighborhood_alias (normalize_neighborhood_name name) in
  List.find_opt (fun nb ->
    let norm_nb = canonicalize_neighborhood_alias (normalize_neighborhood_name nb.name) in
    norm_nb = norm_target
  ) boundaries

let () =
  Printf.printf "\n===================================================================\n";
  Printf.printf "=== EMPIRICAL CHALLENGER: SPATIAL PIP & NEIGHBORHOOD TARGETING ===\n";
  Printf.printf "===================================================================\n\n";

  let boundaries = get_sf_neighborhoods () in
  check_assert "CHALLENGER.PREFLIGHT: Loaded 41 Analysis Neighborhoods" (List.length boundaries = 41);

  let target_corridors = [
    "Pacific Heights";
    "Presidio Heights";
    "Marina";
    "Russian Hill";
    "Seacliff";
  ] in

  Printf.printf "\n[Challenge 1] Vertex Containment Across Target Affluent Corridors...\n%!";
  List.iter (fun nb_name ->
    match find_target_boundary nb_name boundaries with
    | None ->
        check_assert (Printf.sprintf "VERTEX.FIND.%s: Target corridor exists in boundaries" nb_name) false
    | Some nb ->
        let vertex_count = ref 0 in
        let vertex_pass = ref true in
        let vertex_trans_pass = ref true in
        List.iter (fun poly ->
          List.iter (fun ring ->
            List.iter (fun (v_lon, v_lat) ->
              incr vertex_count;
              let in_direct = point_in_neighborhood_boundary v_lon v_lat nb in
              let in_trans = point_in_neighborhood_boundary v_lat v_lon nb in
              if not in_direct then vertex_pass := false;
              if not in_trans then vertex_trans_pass := false
            ) ring
          ) poly
        ) nb.polygons;
        check_assert
          (Printf.sprintf "VERTEX.CONTAIN.%s: All %d polygon vertices contained (lon,lat)" nb_name !vertex_count)
          (!vertex_count > 0 && !vertex_pass);
        check_assert
          (Printf.sprintf "VERTEX.TRANS.%s: All %d polygon vertices contained (lat,lon transposed)" nb_name !vertex_count)
          (!vertex_count > 0 && !vertex_trans_pass)
  ) target_corridors;

  Printf.printf "\n[Challenge 2] Polygon Edge Midpoints and Quarter-Points Stress Testing...\n%!";
  List.iter (fun nb_name ->
    match find_target_boundary nb_name boundaries with
    | None -> ()
    | Some nb ->
        let edges_tested = ref 0 in
        let midpoints_pass = ref true in
        let quarters_pass = ref true in
        List.iter (fun poly ->
          List.iter (fun ring ->
            let pts = Array.of_list ring in
            let n = Array.length pts in
            if n >= 3 then
              let j = ref (n - 1) in
              for i = 0 to n - 1 do
                incr edges_tested;
                let (x1, y1) = pts.(i) in
                let (x2, y2) = pts.(!j) in
                let mx = (x1 +. x2) /. 2.0 in
                let my = (y1 +. y2) /. 2.0 in
                let q1x = (3.0 *. x1 +. x2) /. 4.0 in
                let q1y = (3.0 *. y1 +. y2) /. 4.0 in
                let q3x = (x1 +. 3.0 *. x2) /. 4.0 in
                let q3y = (y1 +. 3.0 *. y2) /. 4.0 in
                if not (point_in_ring mx my ring) then midpoints_pass := false;
                if not (point_in_ring q1x q1y ring) || not (point_in_ring q3x q3y ring) then quarters_pass := false;
                j := i
              done
          ) poly
        ) nb.polygons;
        check_assert
          (Printf.sprintf "EDGE.MIDPOINTS.%s: All %d edge midpoints contained on boundary" nb_name !edges_tested)
          (!edges_tested > 0 && !midpoints_pass);
        check_assert
          (Printf.sprintf "EDGE.QUARTERS.%s: All %d edge quarter-points contained on boundary" nb_name !edges_tested)
          (!edges_tested > 0 && !quarters_pass)
  ) target_corridors;

  Printf.printf "\n[Challenge 3] Axis-Aligned Bounding Box (AABB) Rejection & Global Limits...\n%!";
  List.iter (fun nb_name ->
    match find_target_boundary nb_name boundaries with
    | None -> ()
    | Some nb ->
        let (min_lon, min_lat, max_lon, max_lat) = nb.bbox in
        let mid_lon = (min_lon +. max_lon) /. 2.0 in
        let mid_lat = (min_lat +. max_lat) /. 2.0 in
        let deltas = [1e-7; 1e-5; 1e-3; 0.01; 0.1; 1.0] in
        List.iter (fun delta ->
          let west_pt = (min_lon -. delta, mid_lat) in
          let east_pt = (max_lon +. delta, mid_lat) in
          let south_pt = (mid_lon, min_lat -. delta) in
          let north_pt = (mid_lon, max_lat +. delta) in
          let outside_west = not (point_in_neighborhood_boundary (fst west_pt) (snd west_pt) nb) in
          let outside_east = not (point_in_neighborhood_boundary (fst east_pt) (snd east_pt) nb) in
          let outside_south = not (point_in_neighborhood_boundary (fst south_pt) (snd south_pt) nb) in
          let outside_north = not (point_in_neighborhood_boundary (fst north_pt) (snd north_pt) nb) in
          check_assert
            (Printf.sprintf "AABB.REJECT.%s.delta_%.1e: West/East/South/North outside rejected" nb_name delta)
            (outside_west && outside_east && outside_south && outside_north)
        ) deltas
  ) target_corridors;

  let global_extremes = [
    ("Null Island", 0.0, 0.0);
    ("North Pole", 0.0, 90.0);
    ("South Pole", 0.0, -90.0);
    ("Equator East", 100.0, 0.0);
    ("Prime Meridian North", 0.0, 45.0);
    ("Large Positive Coordinates", 1e6, 1e6);
    ("Large Negative Coordinates", -1e6, -1e6);
  ] in
  List.iter (fun (label, lon, lat) ->
    let resolved = find_neighborhood lon lat in
    let in_corridor = is_point_in_affluent_corridor lon lat in
    check_assert (Printf.sprintf "EXTREME.REJECT.%s: Safely returns None and outside corridor" label)
      (resolved = None && not in_corridor)
  ) global_extremes;

  Printf.printf "\n[Challenge 4] Coordinate Transposition Invariance Across Benchmarks & Grid...\n%!";
  let benchmark_addresses = [
    ("2223 Pacific Ave", 37.7924, -122.4342, "Pacific Heights");
    ("3645 Washington St", 37.7890, -122.4540, "Presidio Heights");
    ("1840 Chestnut St", 37.8005, -122.4348, "Marina");
    ("1450 Green St", 37.7985, -122.4225, "Russian Hill");
    ("300 Sea Cliff Ave", 37.7885, -122.4880, "Seacliff");
  ] in
  List.iter (fun (addr, lat, lon, expected_nb) ->
    let match_direct = point_in_neighborhood lat lon expected_nb in
    let match_transposed = point_in_neighborhood lon lat expected_nb in
    let resolve_direct = find_neighborhood lat lon in
    let resolve_transposed = find_neighborhood lon lat in
    let corridor_direct = is_point_in_affluent_corridor lat lon in
    let corridor_transposed = is_point_in_affluent_corridor lon lat in
    check_assert (Printf.sprintf "TRANS.SYMMETRY.%s: Exact match under (lat,lon) and (lon,lat)" addr)
      (match_direct && match_transposed &&
       resolve_direct = Some expected_nb && resolve_transposed = Some expected_nb &&
       corridor_direct && corridor_transposed)
  ) benchmark_addresses;

  let grid_steps = 10 in
  let pac_bbox =
    match find_target_boundary "Pacific Heights" boundaries with
    | Some nb -> nb.bbox
    | None -> (-122.446, 37.784, -122.422, 37.796)
  in
  let (p_min_x, p_min_y, p_max_x, p_max_y) = pac_bbox in
  let grid_symmetric = ref true in
  for ix = 0 to grid_steps do
    for iy = 0 to grid_steps do
      let lon = p_min_x +. (float_of_int ix /. float_of_int grid_steps) *. (p_max_x -. p_min_x) in
      let lat = p_min_y +. (float_of_int iy /. float_of_int grid_steps) *. (p_max_y -. p_min_y) in
      let in_dir = point_in_neighborhood lat lon "Pacific Heights" in
      let in_tra = point_in_neighborhood lon lat "Pacific Heights" in
      if in_dir <> in_tra then grid_symmetric := false
    done
  done;
  check_assert "TRANS.GRID.PACIFIC_HEIGHTS: Perfect symmetry across all grid sample points" !grid_symmetric;

  Printf.printf "\n[Challenge 5] Benchmark Properties Verification & Target Exclusivity...\n%!";
  List.iter (fun (addr, lat, lon, expected_nb) ->
    let in_expected = point_in_neighborhood lat lon expected_nb in
    check_assert (Printf.sprintf "BENCHMARK.CONTAIN.%s: Resolves in %s" addr expected_nb) in_expected;

    let other_corridors = List.filter (fun c -> c <> expected_nb) target_corridors in
    let in_other = List.exists (fun other -> point_in_neighborhood lat lon other) other_corridors in
    check_assert (Printf.sprintf "BENCHMARK.EXCLUSIVE.%s: Not present in other 4 corridors" addr) (not in_other);

    let resolved = find_neighborhood lat lon in
    check_assert (Printf.sprintf "BENCHMARK.RESOLVE.%s: find_neighborhood matches %s" addr expected_nb)
      (resolved = Some expected_nb);

    let in_affluent = is_point_in_affluent_corridor lat lon in
    check_assert (Printf.sprintf "BENCHMARK.CORRIDOR.%s: is_point_in_affluent_corridor is true" addr) in_affluent
  ) benchmark_addresses;

  let all_catalog = candidate_properties_catalog in
  check_assert "CATALOG.COUNT: All 16 candidate catalog properties verified" (List.length all_catalog = 16);
  List.iter (fun (c : candidate_roof) ->
    match (c.latitude, c.longitude) with
    | (Some lat, Some lon) ->
        let in_nb = point_in_neighborhood lat lon c.neighborhood in
        check_assert (Printf.sprintf "CATALOG.CONTAIN.%s: %s inside %s" c.address c.address c.neighborhood) in_nb;
        let in_corridor = is_point_in_affluent_corridor lat lon in
        check_assert (Printf.sprintf "CATALOG.AFFLUENT.%s: in affluent corridor" c.address) in_corridor
    | _ ->
        check_assert (Printf.sprintf "CATALOG.COORDS.%s: Coordinates present" c.address) false
  ) all_catalog;

  Printf.printf "\n[Challenge 6] Negative Control Points Adversarial Verification...\n%!";
  let negative_controls = [
    ("Excelsior", 37.7265, -122.4330, Some "Excelsior");
    ("Sunset (Parkside)", 37.7612, -122.4785, Some "Sunset/Parkside");
    ("Bay Bridge (Mid-Span)", 37.7983, -122.3778, None);
    ("Pacific Ocean (Offshore)", 37.7800, -122.6000, None);
    ("Marin Headlands (North of Bridge)", 37.8300, -122.5000, None);
    ("Oakland (East Bay)", 37.8044, -122.2712, None);
    ("San Francisco Airport (SFO)", 37.6213, -122.3790, None);
    ("Mission District", 37.7599, -122.4148, Some "Mission");
    ("Tenderloin", 37.7847, -122.4145, Some "Tenderloin");
    ("Bayview Hunters Point", 37.7300, -122.3800, Some "Bayview Hunters Point");
    ("Visitacion Valley", 37.7120, -122.4080, Some "Visitacion Valley");
  ] in
  List.iter (fun (name, lat, lon, expected_res) ->
    let in_affluent = is_point_in_affluent_corridor lat lon in
    check_assert (Printf.sprintf "NEG.AFFLUENT_REJECT.%s: Excluded from affluent corridors" name) (not in_affluent);

    List.iter (fun target ->
      let in_target = point_in_neighborhood lat lon target in
      check_assert (Printf.sprintf "NEG.TARGET_REJECT.%s.%s: Excluded from %s" name target target) (not in_target)
    ) target_corridors;

    let actual_res = find_neighborhood lat lon in
    check_assert (Printf.sprintf "NEG.RESOLVE.%s: Correctly resolves to %s" name
      (match expected_res with Some s -> s | None -> "None"))
      (actual_res = expected_res)
  ) negative_controls;

  Printf.printf "\n[Challenge 7] Ray-Casting Singularity & Boundary Collinearity Stress...\n%!";
  match find_target_boundary "Pacific Heights" boundaries with
  | None -> ()
  | Some pac_nb ->
      let pac_ring = List.hd (List.hd pac_nb.polygons) in
      let vertices = Array.of_list pac_ring in
      let singularity_pass = ref true in
      for i = 0 to Array.length vertices - 2 do
        let (vx, vy) = vertices.(i) in
        let ray_west_outside = (vx -. 0.05, vy) in
        let in_pac = point_in_neighborhood_boundary (fst ray_west_outside) (snd ray_west_outside) pac_nb in
        if in_pac then singularity_pass := false
      done;
      check_assert "SINGULARITY.RAY_THROUGH_VERTEX: Horizontal rays through vertices correctly evaluate"
        !singularity_pass;

      let square_ring : ring = [
        (0.0, 0.0);
        (2.0, 0.0);
        (2.0, 2.0);
        (0.0, 2.0);
        (0.0, 0.0);
      ] in
      check_assert "SYNTHETIC.ON_VERTEX_ORIGIN: Point (0,0) contained on vertex"
        (point_in_ring 0.0 0.0 square_ring);
      check_assert "SYNTHETIC.ON_VERTEX_CORNER: Point (2,2) contained on vertex"
        (point_in_ring 2.0 2.0 square_ring);
      check_assert "SYNTHETIC.ON_EDGE_BOTTOM: Point (1,0) contained on horizontal bottom edge"
        (point_in_ring 1.0 0.0 square_ring);
      check_assert "SYNTHETIC.ON_EDGE_TOP: Point (1,2) contained on horizontal top edge"
        (point_in_ring 1.0 2.0 square_ring);
      check_assert "SYNTHETIC.ON_EDGE_LEFT: Point (0,1) contained on vertical left edge"
        (point_in_ring 0.0 1.0 square_ring);
      check_assert "SYNTHETIC.ON_EDGE_RIGHT: Point (2,1) contained on vertical right edge"
        (point_in_ring 2.0 1.0 square_ring);
      check_assert "SYNTHETIC.INTERIOR: Point (1,1) contained in interior"
        (point_in_ring 1.0 1.0 square_ring);
      check_assert "SYNTHETIC.OUTSIDE_LEFT: Point (-0.5, 1.0) outside square"
        (not (point_in_ring (-0.5) 1.0 square_ring));
      check_assert "SYNTHETIC.OUTSIDE_RAY_ALONG_BOTTOM: Point (-1.0, 0.0) ray along bottom edge"
        (not (point_in_ring (-1.0) 0.0 square_ring));
      check_assert "SYNTHETIC.OUTSIDE_RAY_ALONG_TOP: Point (-1.0, 2.0) ray along top edge"
        (not (point_in_ring (-1.0) 2.0 square_ring));
      check_assert "SYNTHETIC.OUTSIDE_TOP: Point (1.0, 2.5) outside square"
        (not (point_in_ring 1.0 2.5 square_ring));

      let poly_with_hole : polygon = [
        [(0.0, 0.0); (6.0, 0.0); (6.0, 6.0); (0.0, 6.0); (0.0, 0.0)];
        [(2.0, 2.0); (4.0, 2.0); (4.0, 4.0); (2.0, 4.0); (2.0, 2.0)];
      ] in
      check_assert "HOLE.OUTSIDE_OUTER: Point (-1, 3) outside outer ring"
        (not (point_in_polygon (-1.0) 3.0 poly_with_hole));
      check_assert "HOLE.SOLID_BODY: Point (1, 1) in solid polygon ring"
        (point_in_polygon 1.0 1.0 poly_with_hole);
      check_assert "HOLE.INTERIOR_HOLE: Point (3, 3) inside hole rejected"
        (not (point_in_polygon 3.0 3.0 poly_with_hole));
      check_assert "HOLE.HOLE_BOUNDARY: Point (2, 3) on hole boundary excluded"
        (not (point_in_polygon 2.0 3.0 poly_with_hole));

  Printf.printf "\n[Challenge 8] Performance Latency & High-Throughput Stress...\n%!";
  let iterations = 100000 in
  let test_points = [|
    (37.7924, -122.4342);
    (37.7890, -122.4540);
    (37.8005, -122.4348);
    (37.7985, -122.4225);
    (37.7885, -122.4880);
    (37.7265, -122.4330);
    (37.7612, -122.4785);
    (37.7983, -122.3778);
    (37.7800, -122.6000);
    (37.8044, -122.2712);
  |] in
  let num_pts = Array.length test_points in
  let t_start = Unix.gettimeofday () in
  let accum_hits = ref 0 in
  for i = 0 to iterations - 1 do
    let (lat, lon) = test_points.(i mod num_pts) in
    if is_point_in_affluent_corridor lat lon then
      incr accum_hits
  done;
  let t_end = Unix.gettimeofday () in
  let total_duration_sec = t_end -. t_start in
  let avg_latency_us = (total_duration_sec *. 1000000.0) /. float_of_int iterations in
  let throughput_qps = float_of_int iterations /. total_duration_sec in

  Printf.printf "  Executed %d spatial PIP containment queries in %.4f s\n"
    iterations total_duration_sec;
  Printf.printf "  Average Latency: %.3f microseconds/query\n" avg_latency_us;
  Printf.printf "  Throughput:      %.1f queries/sec\n" throughput_qps;
  Printf.printf "  Affluent Hits:   %d / %d (expected %d)\n"
    !accum_hits iterations (iterations / 2);

  check_assert "PERF.THROUGHPUT: Throughput exceeds 20,000 queries/sec"
    (throughput_qps > 20000.0);
  check_assert "PERF.LATENCY: Average latency below 50.0 microseconds/query"
    (avg_latency_us < 50.0);
  check_assert "PERF.ACCURACY: Hit count matches expected ratio"
    (!accum_hits = iterations / 2);

  Printf.printf "\n===================================================================\n";
  Printf.printf "=== CHALLENGER SUMMARY: %d Total, %d Passed, %d Failed ===\n"
    !test_count !pass_count !fail_count;
  Printf.printf "===================================================================\n\n%!";

  if !fail_count > 0 then exit 1
  else exit 0
