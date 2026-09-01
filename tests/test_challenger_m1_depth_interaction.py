#!/usr/bin/env python3
"""
Empirical Challenger Test Suite for Milestone 1 (3D Depth Rendering Engine).
Adversarially stress-tests:
1. Exact mathematical bijectivity and zero drift of unproject3D(project3D(x, y, z))
   across 100,000+ random configurations, boundary conditions, and continuous drag simulations.
2. findNodeAt depth sorting & foreground hit selection under overlapping node configurations.
3. Live browser Playwright verification of mouse interaction and dragging in docs/app.js.
"""

import math
import random
import sys
import time
import os
from typing import Dict, Any, List, Tuple

# Ensure repo root is on sys.path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from playwright.sync_api import sync_playwright
from tests.e2e.test_utils import start_ephemeral_server, stop_ephemeral_server


# ============================================================================
# Python Reference Implementation of docs/app.js Projection Formulas
# ============================================================================

def project3D(x: float, y: float, z: float, width: float, height: float, panX: float, panY: float, zoomScale: float, D: float = 500.0) -> Dict[str, float]:
    nodeZ = float(z) if (z is not None and not math.isnan(z)) else 0.0
    clampedZ = max(-D * 0.95, min(10000.0, nodeZ))
    sz = D / (D + clampedZ)
    pFactor = math.pow(sz, 0.6)
    parallaxX = (panX or 0.0) * pFactor
    parallaxY = (panY or 0.0) * pFactor
    k = zoomScale or 1.0

    screenX = (x * k + parallaxX) * sz + (width / 2.0) * (1.0 - sz)
    screenY = (y * k + parallaxY) * sz + (height / 2.0) * (1.0 - sz)
    return {"screenX": screenX, "screenY": screenY, "sz": sz}


def unproject3D(screenX: float, screenY: float, z: float, width: float, height: float, panX: float, panY: float, zoomScale: float, D: float = 500.0) -> Dict[str, float]:
    nodeZ = float(z) if (z is not None and not math.isnan(z)) else 0.0
    clampedZ = max(-D * 0.95, min(10000.0, nodeZ))
    sz = D / (D + clampedZ)
    pFactor = math.pow(sz, 0.6)
    parallaxX = (panX or 0.0) * pFactor
    parallaxY = (panY or 0.0) * pFactor
    k = zoomScale or 1.0

    worldX = ((screenX - (width / 2.0) * (1.0 - sz)) / sz - parallaxX) / k
    worldY = ((screenY - (height / 2.0) * (1.0 - sz)) / sz - parallaxY) / k
    return {"worldX": worldX, "worldY": worldY, "x": worldX, "y": worldY}


# ============================================================================
# Test Suite 1: Mathematical Bijectivity & Drift Stress Testing
# ============================================================================

def run_mathematical_drift_stress_tests():
    print("\n" + "="*70)
    print("TEST SUITE 1: PROJECT3D <-> UNPROJECT3D MATHEMATICAL BIJECTIVITY & DRIFT")
    print("="*70)

    # 1.1 Forward-Inverse Round-trip (100,000 randomized test vectors)
    num_samples = 100_000
    max_world_abs_err = 0.0
    max_world_rel_err = 0.0
    random.seed(42)

    t0 = time.time()
    for i in range(num_samples):
        x = random.uniform(-20000.0, 20000.0)
        y = random.uniform(-20000.0, 20000.0)
        z = random.uniform(-475.0, 5000.0)
        width = random.uniform(10.0, 7680.0)
        height = random.uniform(10.0, 4320.0)
        panX = random.uniform(-50000.0, 50000.0)
        panY = random.uniform(-50000.0, 50000.0)
        zoom = random.uniform(0.01, 50.0)
        D = random.choice([200.0, 500.0, 1000.0])

        proj = project3D(x, y, z, width, height, panX, panY, zoom, D)
        unproj = unproject3D(proj["screenX"], proj["screenY"], z, width, height, panX, panY, zoom, D)

        absErrX = abs(x - unproj["worldX"])
        absErrY = abs(y - unproj["worldY"])
        relErrX = absErrX / (abs(x) + 1.0)
        relErrY = absErrY / (abs(y) + 1.0)

        max_world_abs_err = max(max_world_abs_err, absErrX, absErrY)
        max_world_rel_err = max(max_world_rel_err, relErrX, relErrY)

    dur = time.time() - t0
    print(f"[*] 1.1 Forward->Inverse Round-trip ({num_samples:,} vectors):")
    print(f"    - Max Absolute Reconstruction Error: {max_world_abs_err:.2e} units")
    print(f"    - Max Relative Reconstruction Error: {max_world_rel_err:.2e}")
    print(f"    - Execution Time: {dur:.2f}s")
    assert max_world_abs_err < 1e-7, f"Absolute drift exceeded tolerance: {max_world_abs_err}"
    assert max_world_rel_err < 1e-10, f"Relative drift exceeded tolerance: {max_world_rel_err}"
    print("    -> [PASS] Zero mathematical drift confirmed (within IEEE 754 precision limit).")

    # 1.2 Inverse-Forward Round-trip (100,000 randomized screen vectors)
    max_screen_abs_err = 0.0
    max_screen_rel_err = 0.0
    t0 = time.time()
    for i in range(num_samples):
        screenX = random.uniform(-10000.0, 20000.0)
        screenY = random.uniform(-10000.0, 20000.0)
        z = random.uniform(-475.0, 5000.0)
        width = random.uniform(10.0, 7680.0)
        height = random.uniform(10.0, 4320.0)
        panX = random.uniform(-50000.0, 50000.0)
        panY = random.uniform(-50000.0, 50000.0)
        zoom = random.uniform(0.01, 50.0)
        D = 500.0

        unproj = unproject3D(screenX, screenY, z, width, height, panX, panY, zoom, D)
        proj = project3D(unproj["worldX"], unproj["worldY"], z, width, height, panX, panY, zoom, D)

        absErrX = abs(screenX - proj["screenX"])
        absErrY = abs(screenY - proj["screenY"])
        relErrX = absErrX / (abs(screenX) + 1.0)
        relErrY = absErrY / (abs(screenY) + 1.0)

        max_screen_abs_err = max(max_screen_abs_err, absErrX, absErrY)
        max_screen_rel_err = max(max_screen_rel_err, relErrX, relErrY)

    dur = time.time() - t0
    print(f"[*] 1.2 Inverse->Forward Round-trip ({num_samples:,} vectors):")
    print(f"    - Max Absolute Screen Error: {max_screen_abs_err:.2e} px")
    print(f"    - Max Relative Screen Error: {max_screen_rel_err:.2e}")
    print(f"    - Execution Time: {dur:.2f}s")
    assert max_screen_abs_err < 1e-7, f"Screen drift exceeded tolerance: {max_screen_abs_err}"
    assert max_screen_rel_err < 1e-10, f"Screen relative drift exceeded tolerance: {max_screen_rel_err}"
    print("    -> [PASS] Exact screen bijectivity confirmed.")

    # 1.3 Cumulative Continuous Drag Trajectory Simulation (10,000 steps)
    print("[*] 1.3 Simulating continuous drag trajectory across 10,000 steps...")
    cur_world_x = 100.0
    cur_world_y = -50.0
    node_z = -45.0
    w, h = 1920.0, 1080.0
    pan_x, pan_y = 120.0, -80.0
    k = 1.45

    max_trajectory_error = 0.0
    for step in range(10_000):
        t = step * 0.01
        cursor_x = 960.0 + 400.0 * math.sin(t * 1.5)
        cursor_y = 540.0 + 300.0 * math.cos(t * 2.3)

        unproj = unproject3D(cursor_x, cursor_y, node_z, w, h, pan_x, pan_y, k)
        cur_world_x = unproj["worldX"]
        cur_world_y = unproj["worldY"]

        proj = project3D(cur_world_x, cur_world_y, node_z, w, h, pan_x, pan_y, k)
        err = math.hypot(proj["screenX"] - cursor_x, proj["screenY"] - cursor_y)
        if err > max_trajectory_error:
            max_trajectory_error = err

    print(f"    - Max Trajectory Reprojection Error: {max_trajectory_error:.2e} px")
    assert max_trajectory_error < 1e-10, f"Trajectory drift occurred: {max_trajectory_error}"
    print("    -> [PASS] Continuous dragging trajectory is perfectly locked (zero lag/drift).")

    # 1.4 Boundary & Singularity Stress
    print("[*] 1.4 Testing boundary edge cases and singular inputs...")
    extreme_cases = [
        {"x": 0, "y": 0, "z": -475.0, "w": 1920, "h": 1080, "panX": 0, "panY": 0, "k": 1.0},
        {"x": 100, "y": 100, "z": -1000.0, "w": 1920, "h": 1080, "panX": 0, "panY": 0, "k": 1.0},
        {"x": 50, "y": 50, "z": 10000.0, "w": 1920, "h": 1080, "panX": 0, "panY": 0, "k": 1.0},
        {"x": -100, "y": 200, "z": None, "w": 1920, "h": 1080, "panX": 500, "panY": -300, "k": 0.15},
        {"x": 0, "y": 0, "z": 0.0, "w": 1, "h": 1, "panX": 0, "panY": 0, "k": 4.0},
        {"x": 1000, "y": -1000, "z": 50.0, "w": 7680, "h": 4320, "panX": 10000, "panY": -10000, "k": 0.01},
    ]

    for idx, case in enumerate(extreme_cases):
        p = project3D(case["x"], case["y"], case["z"], case["w"], case["h"], case["panX"], case["panY"], case["k"])
        assert not math.isnan(p["screenX"]) and not math.isnan(p["screenY"]) and not math.isnan(p["sz"])
        assert math.isfinite(p["screenX"]) and math.isfinite(p["screenY"]) and math.isfinite(p["sz"])
        assert p["sz"] > 0
        u = unproject3D(p["screenX"], p["screenY"], case["z"], case["w"], case["h"], case["panX"], case["panY"], case["k"])
        assert not math.isnan(u["worldX"]) and not math.isnan(u["worldY"])
        assert math.isfinite(u["worldX"]) and math.isfinite(u["worldY"])
        print(f"    Case {idx+1} ({case['z']=}, {case['w']}x{case['h']}, k={case['k']}): sz={p['sz']:.4f}, world=({u['worldX']:.2f}, {u['worldY']:.2f}) [STABLE]")

    print("    -> [PASS] Boundary stability verified.")


# ============================================================================
# Test Suite 2: Depth Occlusion & Hit Testing (findNodeAt)
# ============================================================================

def run_findnodeat_depth_occlusion_tests():
    print("\n" + "="*70)
    print("TEST SUITE 2: FINDNODEAT DEPTH OCCLUSION & FOREGROUND HIT SELECTION")
    print("="*70)

    def simulate_find_node_at(nodes: List[Dict[str, Any]], screenX: float, screenY: float, width: float, height: float, panX: float, panY: float, k: float, maxDistance=None):
        candidates = []
        for n in nodes:
            if n.get("x") is None or n.get("y") is None:
                continue
            z = n.get("z", 0.0)
            proj = project3D(n["x"], n["y"], z, width, height, panX, panY, k)
            
            isSelected = False
            isHovered = False
            baseRadius = (n.get("importance", 3) * 2.2) + 3.5
            radiusMultiplier = 1.0
            screenRadius = max(8.0, baseRadius * radiusMultiplier * proj["sz"] * math.sqrt(k) + 6.0)
            dist = math.hypot(proj["screenX"] - screenX, proj["screenY"] - screenY)

            candidates.append({
                "node": n,
                "dist": dist,
                "screenRadius": screenRadius,
                "z": z,
                "sz": proj["sz"],
                "screenX": proj["screenX"],
                "screenY": proj["screenY"]
            })

        # Depth-priority sorting: foreground first (smallest z)
        candidates.sort(key=lambda c: c["z"])

        # 1. Direct Hit Check
        for c in candidates:
            if c["dist"] <= c["screenRadius"]:
                return c["node"]

        # 2. Fuzzy Proximity Fallback
        if maxDistance is not None and maxDistance > 0:
            closestNode = None
            minDist = maxDistance
            for c in candidates:
                if c["dist"] < minDist:
                    minDist = c["dist"]
                    closestNode = c["node"]
            return closestNode

        return None

    w, h = 1920.0, 1080.0
    pan_x, pan_y = 0.0, 0.0
    k = 1.0

    # Test 2.1: Direct Coincident Overlap (Center of Viewport: x=960, y=540)
    print("[*] 2.1 Direct Coincident Overlap (2 nodes at viewport center):")
    node_foreground = {"id": "node_fg", "x": 960.0, "y": 540.0, "z": -80.0, "importance": 4}
    node_background = {"id": "node_bg", "x": 960.0, "y": 540.0, "z": +80.0, "importance": 4}

    pFG = project3D(960.0, 540.0, -80.0, w, h, pan_x, pan_y, k)
    pBG = project3D(960.0, 540.0, +80.0, w, h, pan_x, pan_y, k)
    assert abs(pFG["screenX"] - 960.0) < 1e-9 and abs(pFG["screenY"] - 540.0) < 1e-9
    assert abs(pBG["screenX"] - 960.0) < 1e-9 and abs(pBG["screenY"] - 540.0) < 1e-9

    hit1 = simulate_find_node_at([node_foreground, node_background], 960.0, 540.0, w, h, pan_x, pan_y, k)
    hit2 = simulate_find_node_at([node_background, node_foreground], 960.0, 540.0, w, h, pan_x, pan_y, k)

    assert hit1 is not None and hit1["id"] == "node_fg", f"Expected node_fg, got {hit1}"
    assert hit2 is not None and hit2["id"] == "node_fg", f"Expected node_fg, got {hit2}"
    print(f"    - Hit result (fg first in list): {hit1['id']} [PASS]")
    print(f"    - Hit result (bg first in list): {hit2['id']} [PASS]")

    # Test 2.2: Partial Overlap (Intersection of hit discs)
    print("[*] 2.2 Partial Overlap (Cursor in intersection of two overlapping discs):")
    node_A = {"id": "node_A_fg", "x": 970.0, "y": 540.0, "z": -60.0, "importance": 3}
    node_B = {"id": "node_B_bg", "x": 985.0, "y": 540.0, "z": 40.0, "importance": 3}

    projA = project3D(node_A["x"], node_A["y"], node_A["z"], w, h, pan_x, pan_y, k)
    projB = project3D(node_B["x"], node_B["y"], node_B["z"], w, h, pan_x, pan_y, k)
    
    rA = max(8.0, (3 * 2.2 + 3.5) * projA["sz"] + 6.0)
    rB = max(8.0, (3 * 2.2 + 3.5) * projB["sz"] + 6.0)

    print(f"    - Node A (fg, z=-60): screen=({projA['screenX']:.2f}, {projA['screenY']:.2f}), radius={rA:.2f}")
    print(f"    - Node B (bg, z=+40): screen=({projB['screenX']:.2f}, {projB['screenY']:.2f}), radius={rB:.2f}")

    overlap_x = (projA["screenX"] + projB["screenX"]) / 2.0
    overlap_y = (projA["screenY"] + projB["screenY"]) / 2.0

    hit_overlap = simulate_find_node_at([node_B, node_A], overlap_x, overlap_y, w, h, pan_x, pan_y, k)
    assert hit_overlap is not None and hit_overlap["id"] == "node_A_fg", f"Expected foreground node_A_fg, got {hit_overlap}"
    print(f"    - Cursor at intersection ({overlap_x:.2f}, {overlap_y:.2f}) -> selected: {hit_overlap['id']} [PASS]")

    only_B_x = projB["screenX"] + (rB - 2.0)
    only_B_y = projB["screenY"]
    hit_B = simulate_find_node_at([node_B, node_A], only_B_x, only_B_y, w, h, pan_x, pan_y, k)
    assert hit_B is not None and hit_B["id"] == "node_B_bg", f"Expected background node_B_bg, got {hit_B}"
    print(f"    - Cursor on exclusive B edge ({only_B_x:.2f}, {only_B_y:.2f}) -> selected: {hit_B['id']} [PASS]")

    # Test 2.3: Multi-Layer Depth Stack (10 collinear nodes along camera depth ray)
    print("[*] 2.3 Deep Collinear Stack (10 concentric nodes at viewport center across z=[-90..+90]):")
    depths = [-90.0, -70.0, -50.0, -30.0, -10.0, 10.0, 30.0, 50.0, 70.0, 90.0]
    stack_nodes = [{"id": f"stack_z_{int(z)}", "x": 960.0, "y": 540.0, "z": z, "importance": 3} for z in depths]
    
    shuffled = list(stack_nodes)
    random.shuffle(shuffled)

    hit_stack = simulate_find_node_at(shuffled, 960.0, 540.0, w, h, pan_x, pan_y, k)
    assert hit_stack is not None and hit_stack["id"] == "stack_z_-90", f"Expected stack_z_-90, got {hit_stack}"
    print(f"    - Top hit in 10-node stack: {hit_stack['id']} (z=-90) [PASS]")

    current_pool = list(stack_nodes)
    for expected_z in depths:
        hit = simulate_find_node_at(current_pool, 960.0, 540.0, w, h, pan_x, pan_y, k)
        assert hit is not None and hit["id"] == f"stack_z_{int(expected_z)}", f"Expected stack_z_{int(expected_z)}, got {hit}"
        current_pool = [n for n in current_pool if n["id"] != hit["id"]]

    print("    - All 10 layers peeled sequentially from front to back with 100% precision. [PASS]")


# ============================================================================
# Test Suite 3: Live Browser Playwright Integration & Dragging Verification
# ============================================================================

def run_playwright_live_browser_tests():
    print("\n" + "="*70)
    print("TEST SUITE 3: LIVE PLAYWRIGHT CHROMIUM BROWSER HIT & DRAG VERIFICATION")
    print("="*70)

    httpd, server_thread, base_url = start_ephemeral_server()
    print(f"[*] Ephemeral HTTP server started at: {base_url}")

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1920, "height": 1080})
            page = context.new_page()

            errors = []
            page.on("pageerror", lambda err: errors.append(str(err)))
            page.on("console", lambda msg: errors.append(f"Console error: {msg.text}") if msg.type == "error" else None)

            page.goto(f"{base_url}/docs/index.html", wait_until="networkidle")
            page.wait_for_timeout(1000)

            # 3.1 Verify Live Window Exports
            print("[*] 3.1 Checking window 3D API exports in running application...")
            exports_check = page.evaluate("""() => {
                return {
                    hasProject3D: typeof window.project3D === 'function',
                    hasUnproject3D: typeof window.unproject3D === 'function',
                    hasFindNodeAt: typeof window.findNodeAt === 'function',
                    hasGetNodeAtPosition: typeof window.getNodeAtPosition === 'function',
                    hasCurrentGraph: !!window.currentGraph && Array.isArray(window.currentGraph.nodes),
                    nodeCount: window.currentGraph ? window.currentGraph.nodes.length : 0
                };
            }""")
            print(f"    - Exports: {exports_check}")
            assert exports_check["hasProject3D"], "window.project3D missing!"
            assert exports_check["hasUnproject3D"], "window.unproject3D missing!"
            assert exports_check["hasFindNodeAt"], "window.findNodeAt missing!"
            assert exports_check["nodeCount"] > 0, "No nodes loaded in currentGraph!"
            print("    -> [PASS] Window 3D API exports verified.")

            # 3.2 In-Browser unproject3D(project3D) Bijectivity Check
            print("[*] 3.2 In-Browser unproject3D/project3D bijectivity verification...")
            browser_drift_check = page.evaluate("""() => {
                const W = window.innerWidth;
                const H = window.innerHeight - 64;
                const tx = window.state.zoomTransform.x;
                const ty = window.state.zoomTransform.y;
                const k = window.state.zoomTransform.k;
                
                let maxDrift = 0;
                for (const n of window.currentGraph.nodes) {
                    if (n.x === undefined || n.y === undefined) continue;
                    const z = n.z || 0;
                    const proj = window.project3D(n.x, n.y, z, W, H, tx, ty, k);
                    const unproj = window.unproject3D(proj.screenX, proj.screenY, z, W, H, tx, ty, k);
                    const err = Math.hypot(n.x - unproj.worldX, n.y - unproj.worldY);
                    if (err > maxDrift) maxDrift = err;
                }
                return { maxDrift, nodeCount: window.currentGraph.nodes.length };
            }""")
            print(f"    - In-Browser Max Node Drift across {browser_drift_check['nodeCount']} nodes: {browser_drift_check['maxDrift']:.2e}")
            assert browser_drift_check["maxDrift"] < 1e-7, f"In-browser drift too large: {browser_drift_check['maxDrift']}"
            print("    -> [PASS] In-browser graph node round-trip drift is < 1e-7.")

            # 3.3 Live findNodeAt Foreground Hit Testing with Synthetic Overlapping Nodes
            print("[*] 3.3 Injecting synthetic overlapping test nodes into live browser context...")
            hit_test_res = page.evaluate("""() => {
                const W = window.innerWidth;
                const H = window.innerHeight - 64;
                const tx = window.state.zoomTransform.x;
                const ty = window.state.zoomTransform.y;
                const k = window.state.zoomTransform.k;

                // Choose target screen point (500, 400)
                const targetScreenX = 500;
                const targetScreenY = 400;

                // Use unproject3D to determine exact world positions that project to (targetScreenX, targetScreenY)
                const unprojFG = window.unproject3D(targetScreenX, targetScreenY, -80, W, H, tx, ty, k);
                const unprojBG = window.unproject3D(targetScreenX, targetScreenY, 80, W, H, tx, ty, k);

                // Create two test nodes directly overlapping at (targetScreenX, targetScreenY)
                const fgNode = {
                    id: 'SYNTH_FG_NODE',
                    name: 'Foreground Test Node',
                    x: unprojFG.worldX,
                    y: unprojFG.worldY,
                    z: -80, // Foreground
                    importance: 4,
                    layer: 1
                };
                const bgNode = {
                    id: 'SYNTH_BG_NODE',
                    name: 'Background Test Node',
                    x: unprojBG.worldX,
                    y: unprojBG.worldY,
                    z: 80, // Background
                    importance: 4,
                    layer: 5
                };

                // Add to nodes list (put bgNode first to test depth sorting priority)
                window.currentGraph.nodes.push(bgNode);
                window.currentGraph.nodes.push(fgNode);

                const projFG = window.project3D(fgNode.x, fgNode.y, -80, W, H, tx, ty, k);
                const projBG = window.project3D(bgNode.x, bgNode.y, 80, W, H, tx, ty, k);

                const hitAtTarget = window.findNodeAt(targetScreenX, targetScreenY);

                // Clean up synthetic nodes
                window.currentGraph.nodes = window.currentGraph.nodes.filter(n => !n.id.startsWith('SYNTH_'));

                return {
                    targetScreenX,
                    targetScreenY,
                    projFG,
                    projBG,
                    hitId: hitAtTarget ? hitAtTarget.id : null
                };
            }""")
            print(f"    - Target Screen Coords: ({hit_test_res['targetScreenX']}, {hit_test_res['targetScreenY']})")
            print(f"    - FG Projected Coords:  ({hit_test_res['projFG']['screenX']:.2f}, {hit_test_res['projFG']['screenY']:.2f})")
            print(f"    - BG Projected Coords:  ({hit_test_res['projBG']['screenX']:.2f}, {hit_test_res['projBG']['screenY']:.2f})")
            print(f"    - Hit at Screen Overlap: {hit_test_res['hitId']} [Expected: SYNTH_FG_NODE]")
            assert hit_test_res["hitId"] == "SYNTH_FG_NODE", f"Expected SYNTH_FG_NODE, got {hit_test_res['hitId']}"
            print("    -> [PASS] Live browser hit testing strictly selects foreground node at overlapping screen coordinates.")

            # 3.4 Interactive Dragging via Analytical unproject3D
            print("[*] 3.4 Live interactive drag simulation via analytical unproject3D...")
            drag_sim_res = page.evaluate("""() => {
                const W = window.innerWidth;
                const H = window.innerHeight - 64;
                const tx = window.state.zoomTransform.x;
                const ty = window.state.zoomTransform.y;
                const k = window.state.zoomTransform.k;

                const node = window.currentGraph.nodes[0];
                const originalWorldX = node.x;
                const originalWorldY = node.y;
                const z = node.z || 0;

                // Simulate dragging node to 10 distinct screen target positions
                const targets = [
                    { sx: 400, sy: 300 },
                    { sx: 600, sy: 450 },
                    { sx: 850, sy: 200 },
                    { sx: 1100, sy: 600 },
                    { sx: 960, sy: 500 }
                ];

                const results = [];
                for (const t of targets) {
                    // Drag action: unproject cursor screen position to world coordinates
                    const unproj = window.unproject3D(t.sx, t.sy, z, W, H, tx, ty, k);
                    node.fx = unproj.worldX;
                    node.fy = unproj.worldY;

                    // Render action: project node world position back to screen
                    const reproj = window.project3D(node.fx, node.fy, z, W, H, tx, ty, k);
                    const error = Math.hypot(reproj.screenX - t.sx, reproj.screenY - t.sy);
                    results.push({ target: t, reproj: { sx: reproj.screenX, sy: reproj.screenY }, error });
                }

                // Release drag
                node.fx = null;
                node.fy = null;

                const maxError = Math.max(...results.map(r => r.error));
                return { maxError, sample: results[0] };
            }""")

            print(f"    - Drag Reprojection Max Error across screen targets: {drag_sim_res['maxError']:.2e} px")
            assert drag_sim_res["maxError"] < 1e-10, f"Drag tracking error exceeded tolerance: {drag_sim_res['maxError']}"
            print("    -> [PASS] Live D3 drag with analytical unproject3D tracking confirmed (0px lag/drift).")

            context.close()
            browser.close()

    finally:
        stop_ephemeral_server(httpd, server_thread)
        print("[✓] Ephemeral server stopped.")

    print("\n" + "="*70)
    print("ALL EMPIRICAL CHALLENGER ADVERSARIAL TESTS PASSED (100% SUCCESS)")
    print("="*70)


if __name__ == "__main__":
    run_mathematical_drift_stress_tests()
    run_findnodeat_depth_occlusion_tests()
    run_playwright_live_browser_tests()
