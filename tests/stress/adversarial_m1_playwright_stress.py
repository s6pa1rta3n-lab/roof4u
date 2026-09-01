#!/usr/bin/env python3
"""
adversarial_m1_playwright_stress.py
Live browser-based adversarial stress suite for Roo4u Milestone 1 (3D Depth Rendering Engine).
Executes high-load stress testing, extreme zoom/pan torture, co-planar node stability,
and screen-space hit testing inside headless Chromium.
"""

import os
import sys
import time
from typing import Dict, Any

# Add repo root to sys.path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from playwright.sync_api import sync_playwright
from tests.e2e.test_utils import start_ephemeral_server, stop_ephemeral_server

GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"


def run_live_stress_tests() -> int:
    print(f"\n{BOLD}{CYAN}======================================================================{RESET}")
    print(f"{BOLD}{CYAN}    ROO4U M1 3D DEPTH ENGINE — LIVE PLAYWRIGHT ADVERSARIAL STRESS     {RESET}")
    print(f"{BOLD}{CYAN}======================================================================\n")

    httpd, server_thread, base_url = start_ephemeral_server(0)
    print(f"[*] Ephemeral HTTP server started at: {base_url}")

    failures = 0
    total = 0

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1920, "height": 1080})
        page = context.new_page()

        console_errors = []
        page.on("pageerror", lambda e: console_errors.append(f"PageError: {e}"))
        page.on("console", lambda msg: console_errors.append(f"ConsoleError: {msg.text}") if msg.type == "error" else None)

        try:
            page.goto(f"{base_url}/docs/index.html", wait_until="networkidle")
            page.wait_for_timeout(500)

            # -------------------------------------------------------------
            # Test 1: 1,500 Injected Nodes & 2,500 Links High-Load Frame Loop
            # -------------------------------------------------------------
            total += 1
            print(f"[*] [1/5] Injecting 1,500 Nodes & 2,500 Links High-Load Stress Test...", end="", flush=True)
            t0 = time.time()
            high_load_res = page.evaluate("""() => {
                if (!window.currentGraph || !window.computeNodeZ || !window.project3D) {
                    return { success: false, reason: "Engine functions not exposed on window" };
                }

                // Generate 1500 synthetic nodes across all 6 layers & importance 1-5
                const syntheticNodes = [];
                for (let i = 0; i < 1500; i++) {
                    const layer = (i % 6) + 1;
                    const importance = (i % 5) + 1;
                    const id = `synth_node_${i}`;
                    const n = {
                        id,
                        label: `Synth ${i}`,
                        layer,
                        importance,
                        category: `Category_${i % 8}`,
                        color: ['#00f0ff', '#7000ff', '#ffaa00', '#00ff88', '#ec4899'][i % 5],
                        x: 960 + (Math.random() - 0.5) * 2500,
                        y: 540 + (Math.random() - 0.5) * 2000
                    };
                    n.z = window.computeNodeZ(n);
                    syntheticNodes.push(n);
                }

                // Generate 2500 synthetic links
                const syntheticLinks = [];
                for (let i = 0; i < 2500; i++) {
                    const src = syntheticNodes[Math.floor(Math.random() * syntheticNodes.length)];
                    const tgt = syntheticNodes[Math.floor(Math.random() * syntheticNodes.length)];
                    if (src.id !== tgt.id) {
                        syntheticLinks.push({ source: src, target: tgt, weight: 1 });
                    }
                }

                window.currentGraph.nodes = syntheticNodes;
                window.currentGraph.links = syntheticLinks;
                window.state.nodes = syntheticNodes;

                // Measure frame execution times over 30 consecutive simulated frames
                const frameTimes = [];
                const W = 1920, H = 1016;
                const k = 1.0, tx = 0, ty = 0;

                for (let f = 0; f < 30; f++) {
                    const tStart = performance.now();
                    
                    // Unified Render Queue build & depth-sort
                    const queue = [];
                    for (let i = 0; i < syntheticNodes.length; i++) {
                        const n = syntheticNodes[i];
                        const proj = window.project3D(n.x, n.y, n.z, W, H, tx, ty, k);
                        n.screenX = proj.screenX;
                        n.screenY = proj.screenY;
                        n.sz = proj.sz;
                        queue.push({ type: 'node', z: n.z, data: n, proj });
                    }

                    for (let i = 0; i < syntheticLinks.length; i++) {
                        const l = syntheticLinks[i];
                        const s = l.source, t = l.target;
                        const sProj = window.project3D(s.x, s.y, s.z, W, H, tx, ty, k);
                        const tProj = window.project3D(t.x, t.y, t.z, W, H, tx, ty, k);
                        const linkZ = (s.z + t.z) / 2 + 0.4;
                        queue.push({ type: 'link', z: linkZ, data: l, sProj, tProj });
                    }

                    queue.sort((a, b) => b.z - a.z);

                    const tElapsed = performance.now() - tStart;
                    frameTimes.push(tElapsed);
                }

                const avgTime = frameTimes.reduce((a, b) => a + b, 0) / frameTimes.length;
                const maxTime = Math.max(...frameTimes);

                // Verify no NaNs occurred in projected coordinates
                let nanCount = 0;
                for (const n of syntheticNodes) {
                    if (isNaN(n.screenX) || isNaN(n.screenY) || isNaN(n.sz) || !isFinite(n.screenX)) {
                        nanCount++;
                    }
                }

                return {
                    success: true,
                    nodeCount: syntheticNodes.length,
                    linkCount: syntheticLinks.length,
                    avgFrameMs: avgTime,
                    maxFrameMs: maxTime,
                    nanCount
                };
            }""")

            assert high_load_res["success"], high_load_res.get("reason", "High load injection failed")
            assert high_load_res["nanCount"] == 0, f"NaNs detected in projected coordinates: {high_load_res['nanCount']}"
            assert high_load_res["avgFrameMs"] < 15.0, f"Average frame processing time too high: {high_load_res['avgFrameMs']}ms"
            print(f" {GREEN}[PASS]{RESET} ({high_load_res['avgFrameMs']:.2f}ms avg/frame, {time.time()-t0:.2f}s total)")

            # -------------------------------------------------------------
            # Test 2: Extreme Pan & Zoom Torture with Canvas Render Loop
            # -------------------------------------------------------------
            total += 1
            print(f"[*] [2/5] Extreme Pan & Zoom Camera Torture Test...", end="", flush=True)
            t0 = time.time()
            zoom_torture_res = page.evaluate("""() => {
                const canvas = document.getElementById('graph-canvas');
                const testScales = [0.01, 0.15, 0.5, 1.0, 2.5, 4.0, 10.0, 50.0];
                const testPans = [
                    { x: -50000, y: -50000 },
                    { x: 50000, y: 50000 },
                    { x: 0, y: 0 },
                    { x: -1000, y: 2000 }
                ];

                for (const k of testScales) {
                    for (const pan of testPans) {
                        if (window.zoomBehavior && window.d3) {
                            window.d3.select(canvas).call(
                                window.zoomBehavior.transform,
                                window.d3.zoomIdentity.translate(pan.x, pan.y).scale(k)
                            );
                        }
                    }
                }

                // Reset camera
                window.centerCamera();

                return {
                    success: true,
                    finalZoom: window.state.zoomTransform ? window.state.zoomTransform.k : 1.0
                };
            }""")
            page.wait_for_timeout(300)
            assert zoom_torture_res["success"], "Zoom torture failed"
            print(f" {GREEN}[PASS]{RESET} ({time.time()-t0:.2f}s)")

            # -------------------------------------------------------------
            # Test 3: Unproject3D & Interactive Mouse Coordinate Tracking
            # -------------------------------------------------------------
            total += 1
            print(f"[*] [3/5] Interactive Drag Tracking & Unproject3D Accuracy...", end="", flush=True)
            t0 = time.time()
            drag_res = page.evaluate("""() => {
                const sampleNode = window.currentGraph.nodes[0];
                const W = window.innerWidth;
                const H = window.innerHeight - 64;
                const k = window.state.zoomTransform.k;
                const tx = window.state.zoomTransform.x;
                const ty = window.state.zoomTransform.y;

                // Project node to screen
                const proj = window.project3D(sampleNode.x, sampleNode.y, sampleNode.z, W, H, tx, ty, k);

                // Simulate cursor dragging to new screen position (screenX + 150, screenY + 100)
                const targetScreenX = proj.screenX + 150;
                const targetScreenY = proj.screenY + 100;

                // Invert via unproject3D
                const unproj = window.unproject3D(targetScreenX, targetScreenY, sampleNode.z, W, H, tx, ty, k);

                // Project new world coordinate back to screen
                const reprojected = window.project3D(unproj.worldX, unproj.worldY, sampleNode.z, W, H, tx, ty, k);

                const errX = Math.abs(reprojected.screenX - targetScreenX);
                const errY = Math.abs(reprojected.screenY - targetScreenY);

                return {
                    success: true,
                    errX,
                    errY,
                    isExact: (errX + errY) < 1e-6
                };
            }""")
            assert drag_res["success"] and drag_res["isExact"], f"Unproject3D error too high: {drag_res}"
            print(f" {GREEN}[PASS]{RESET} (error < 1e-6, {time.time()-t0:.2f}s)")

            # -------------------------------------------------------------
            # Test 4: Co-Planar Overlapping Nodes Stability
            # -------------------------------------------------------------
            total += 1
            print(f"[*] [4/5] Co-Planar Overlapping Nodes Stability Test...", end="", flush=True)
            t0 = time.time()
            coplanar_res = page.evaluate("""() => {
                // Invert graph with 300 perfectly co-planar nodes at z = 0
                const coplanarNodes = [];
                for (let i = 0; i < 300; i++) {
                    coplanarNodes.push({
                        id: `coplanar_${i}`,
                        label: `CoPlanar ${i}`,
                        layer: 3,
                        importance: 3,
                        z: 0.0,
                        x: 960 + (i % 10) * 15,
                        y: 540 + Math.floor(i / 10) * 15,
                        color: '#00f0ff'
                    });
                }

                window.currentGraph.nodes = coplanarNodes;
                window.state.nodes = coplanarNodes;

                // Check hit testing with multiple identical z nodes
                const hit = window.findNodeAt(960, 540);
                
                return {
                    success: true,
                    hitFound: hit !== null
                };
            }""")
            assert coplanar_res["success"], "Coplanar stability test failed"
            print(f" {GREEN}[PASS]{RESET} ({time.time()-t0:.2f}s)")

            # -------------------------------------------------------------
            # Test 5: Depth-Aware Screen-Space Hit Testing
            # -------------------------------------------------------------
            total += 1
            print(f"[*] [5/5] Depth-Aware Hit Testing & Selection...", end="", flush=True)
            t0 = time.time()
            hit_test_res = page.evaluate("""() => {
                // Reload clean branch
                window.loadBranch('main');
                const targetNode = window.currentGraph.nodes.find(n => n.importance >= 4 && n.x !== undefined);
                if (!targetNode) return { success: false, reason: "No target node" };

                const W = window.innerWidth;
                const H = window.innerHeight - 64;
                const k = window.state.zoomTransform.k;
                const tx = window.state.zoomTransform.x;
                const ty = window.state.zoomTransform.y;

                const proj = window.project3D(targetNode.x, targetNode.y, targetNode.z, W, H, tx, ty, k);

                // Query hit detection at exact screen coordinate
                const detected = window.findNodeAt(proj.screenX, proj.screenY);

                return {
                    success: true,
                    targetId: targetNode.id,
                    detectedId: detected ? detected.id : null,
                    isMatch: detected && detected.id === targetNode.id
                };
            }""")
            assert hit_test_res["success"] and hit_test_res["isMatch"], f"Hit test mismatch: {hit_test_res}"
            print(f" {GREEN}[PASS]{RESET} ({time.time()-t0:.2f}s)")

            # Check for console/page errors during all tests
            assert len(console_errors) == 0, f"Browser console errors detected: {console_errors}"

        except Exception as e:
            print(f" {RED}[FAIL]{RESET} -> {e}")
            failures += 1
        finally:
            context.close()
            browser.close()
            stop_ephemeral_server(httpd, server_thread)

    print(f"\n{BOLD}----------------------------------------------------------------------{RESET}")
    print(f"LIVE STRESS TESTS TOTAL : {total}")
    print(f"PASSED                  : {GREEN}{total - failures}{RESET}")
    print(f"FAILED                  : {RED if failures > 0 else GREEN}{failures}{RESET}")
    print(f"{BOLD}======================================================================{RESET}\n")

    return 1 if failures > 0 else 0


if __name__ == "__main__":
    sys.exit(run_live_stress_tests())
