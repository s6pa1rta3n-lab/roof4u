"""
Tier 5: Adversarial Coverage Hardening E2E Tests
White-box adversarial stress testing for Roo4u Constellation Overhaul.

Covers:
- T5.1: Rapid Theme Cycling (50+ toggles) during active force simulation and camera pan/zoom
- T5.2: Extreme Viewport Resizing Matrix (320x480 up to 4K 3840x2160) with Zero Scrollbars
- T5.3: Dual-Branch Toggling (main <-> v2) under Multiple Search Filter States
- T5.4: Memory Leak & Continuous Animation Profiling (100 interaction cycles + Heap inspection)
- T5.5: High-Concurrency Chaos & Fuzzing Resilience (disordered multi-action barrage)
"""

import time
from typing import List
from tests.e2e.test_utils import (
    TestResult,
    navigate_and_wait,
    setup_page_listeners,
    assert_no_scrollbars
)


def run_tier5_tests(page, base_url: str) -> List[TestResult]:
    results = []

    # -------------------------------------------------------------
    # Test 5.1: Rapid Theme Cycling (50+ toggles) Under Active Simulation & Pan/Zoom
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        navigate_and_wait(page, f"{base_url}/docs/index.html")

        theme_stress_res = page.evaluate("""() => {
            const selector = document.getElementById('theme-selector');
            if (!selector) return { success: false, reason: "No #theme-selector" };

            const themeKeys = ['event-horizon', 'accretion-disk', 'quantum-void'];
            const cycles = 60; // 60 rapid cycles (exceeds 50 requirement)
            const transitions = [];

            // Ensure simulation is active and reheating
            if (window.simulation) {
                window.simulation.alpha(1.0).restart();
            }

            for (let i = 0; i < cycles; i++) {
                const theme = themeKeys[i % themeKeys.length];
                
                // Switch theme via API and DOM event
                if (typeof window.setTheme === 'function') {
                    window.setTheme(theme);
                } else {
                    selector.value = theme;
                    selector.dispatchEvent(new Event('change', { bubbles: true }));
                }

                // Simultaneously perform camera pan/zoom transformations
                if (window.zoomBehavior && window.d3) {
                    const canvas = document.getElementById('graph-canvas');
                    const k = 0.5 + (i % 10) * 0.3; // scale from 0.5 to 3.2
                    const tx = (i % 5 - 2) * 50;
                    const ty = (i % 5 - 2) * 40;
                    window.d3.select(canvas).call(
                        window.zoomBehavior.transform,
                        window.d3.zoomIdentity.translate(tx, ty).scale(k)
                    );
                }

                // Verify DOM synchronization
                const currentDataTheme = document.body.getAttribute('data-theme');
                const hasClass = document.body.classList.contains(`theme-${theme}`);
                const selectorVal = selector.value;

                if (currentDataTheme !== theme || !hasClass || selectorVal !== theme) {
                    return {
                        success: false,
                        reason: `Theme desync at cycle ${i}: expected ${theme}, got data-theme=${currentDataTheme}, class=${document.body.className}, selector=${selectorVal}`
                    };
                }

                // Check canvas rendering integrity (no NaN or corrupt coordinates)
                if (window.currentGraph && window.currentGraph.nodes && window.currentGraph.nodes.length > 0) {
                    const sample = window.currentGraph.nodes[0];
                    if (sample.screenX !== undefined && isNaN(sample.screenX)) {
                        return { success: false, reason: `NaN screenX encountered on node ${sample.id} at cycle ${i}` };
                    }
                }
            }

            // Restore default theme and center camera
            window.setTheme('event-horizon');
            if (typeof window.centerCamera === 'function') {
                window.centerCamera();
            }

            return {
                success: true,
                totalCycles: cycles,
                finalTheme: document.body.getAttribute('data-theme')
            };
        }""")

        page.wait_for_timeout(400)
        assert theme_stress_res.get("success", False), theme_stress_res.get("reason", "Theme stress test failed")
        assert len(logs["errors"]) == 0, f"Console/page errors during rapid theme cycling: {logs['errors']}"

        results.append(TestResult(
            test_id="T5.1_EXTREME_THEME_CYCLING_STRESS",
            name="Rapid Theme Cycling (60x Toggles) Under Active Simulation & Pan/Zoom",
            tier=5,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=theme_stress_res
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T5.1_EXTREME_THEME_CYCLING_STRESS",
            name="Rapid Theme Cycling (60x Toggles) Under Active Simulation & Pan/Zoom",
            tier=5,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 5.2: Extreme Viewport Resizing Matrix (320x480 up to 4K 3840x2160)
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        test_resolutions = [
            {"width": 320, "height": 480, "name": "320x480 Ultra-Compact Mobile (iPhone SE 1st Gen)"},
            {"width": 360, "height": 640, "name": "360x640 Standard Mobile (Android Small)"},
            {"width": 375, "height": 667, "name": "375x667 Mobile (iPhone 8/SE2)"},
            {"width": 375, "height": 812, "name": "375x812 Mobile (iPhone X/11/12)"},
            {"width": 414, "height": 896, "name": "414x896 Phablet (iPhone XR/11 Pro Max)"},
            {"width": 768, "height": 1024, "name": "768x1024 Tablet Portrait (iPad)"},
            {"width": 1024, "height": 768, "name": "1024x768 Tablet Landscape (iPad)"},
            {"width": 1280, "height": 720, "name": "1280x720 720p HD Display"},
            {"width": 1366, "height": 768, "name": "1366x768 Standard Laptop Display"},
            {"width": 1440, "height": 900, "name": "1440x900 MacBook Standard"},
            {"width": 1920, "height": 1080, "name": "1920x1080 1080p FHD Desktop"},
            {"width": 2560, "height": 1440, "name": "2560x1440 2K QHD Display"},
            {"width": 3840, "height": 2160, "name": "3840x2160 4K UHD Ultra-High-Res"}
        ]

        resolution_audit = []
        for res in test_resolutions:
            page.set_viewport_size({"width": res["width"], "height": res["height"]})
            page.wait_for_timeout(150)

            # 1. Assert zero scrollbars
            no_scroll, msg = assert_no_scrollbars(page)
            assert no_scroll, f"Viewport {res['name']} failed scrollbar check: {msg}"

            # 2. Assert canvas fits workspace cleanly without overflowing
            canvas_metrics = page.evaluate("""() => {
                const canvas = document.getElementById('graph-canvas');
                const header = document.querySelector('.app-header');
                const body = document.body;
                const doc = document.documentElement;

                return {
                    windowW: window.innerWidth,
                    windowH: window.innerHeight,
                    canvasW: canvas ? canvas.clientWidth : 0,
                    canvasH: canvas ? canvas.clientHeight : 0,
                    headerH: header ? header.offsetHeight : 0,
                    headerOverflow: header ? header.scrollWidth > window.innerWidth : false,
                    bodyOverflowX: window.getComputedStyle(body).overflowX,
                    bodyOverflowY: window.getComputedStyle(body).overflowY
                };
            }""")

            assert canvas_metrics["canvasW"] == res["width"], (
                f"Canvas width {canvas_metrics['canvasW']} does not match viewport {res['width']} on {res['name']}"
            )
            assert canvas_metrics["canvasH"] == (res["height"] - 64), (
                f"Canvas height {canvas_metrics['canvasH']} does not match viewport height minus header on {res['name']}"
            )
            assert not canvas_metrics["headerOverflow"], f"Header overflowed viewport on {res['name']}"

            resolution_audit.append({"resolution": res["name"], "status": "PASS", "metrics": canvas_metrics})

        # Restore standard 1080p desktop
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.wait_for_timeout(150)
        assert len(logs["errors"]) == 0, f"Errors logged during extreme viewport resizing: {logs['errors']}"

        results.append(TestResult(
            test_id="T5.2_EXTREME_VIEWPORT_RESIZING_MATRIX",
            name="Extreme Responsive Viewport Resizing Matrix (320x480 to 4K 3840x2160)",
            tier=5,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"resolutions_tested": len(test_resolutions), "audit": resolution_audit}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T5.2_EXTREME_VIEWPORT_RESIZING_MATRIX",
            name="Extreme Responsive Viewport Resizing Matrix (320x480 to 4K 3840x2160)",
            tier=5,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 5.3: Dual-Branch Toggling (main <-> v2) Under Multiple Search Filter States
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        test_queries = [
            "agent",       # Common keyword
            "ocaml",       # v2-specific keyword
            "base_agent",  # main-specific keyword
            "AST",         # Certification keyword
            "NonExistentQuery_999XYZ",  # Zero-result query
            ".*",          # Regex pattern query
            "<tag>"        # Escaped characters
        ]

        branch_search_res = page.evaluate("""(queries) => {
            const auditLog = [];
            const searchInput = document.getElementById('node-search');
            const tabMain = document.getElementById('tab-main');
            const tabV2 = document.getElementById('tab-v2');

            if (!searchInput || !tabMain || !tabV2) {
                return { success: false, reason: "Search input or branch tabs missing" };
            }

            for (let i = 0; i < queries.length; i++) {
                const q = queries[i];
                
                // 1. Enter search query on main branch
                tabMain.click();
                searchInput.value = q;
                searchInput.dispatchEvent(new Event('input', { bubbles: true }));

                const mainCount = window.currentGraph ? window.currentGraph.nodes.length : 0;
                const mainBranch = window.state ? window.state.currentBranch : '';

                if (mainBranch !== 'main') {
                    return { success: false, reason: `Branch switch to main failed for query '${q}'` };
                }

                // 2. Switch to v2 branch while search query is active
                tabV2.click();
                const v2Count = window.currentGraph ? window.currentGraph.nodes.length : 0;
                const v2Branch = window.state ? window.state.currentBranch : '';

                if (v2Branch !== 'v2') {
                    return { success: false, reason: `Branch switch to v2 failed for query '${q}'` };
                }

                // 3. Trigger category chip filter on v2
                const chips = document.querySelectorAll('.category-chip');
                if (chips.length > 0) {
                    chips[0].click(); // Toggle off first cluster
                }

                // 4. Switch back to main
                tabMain.click();
                const returnMainCount = window.currentGraph ? window.currentGraph.nodes.length : 0;

                // Re-enable category chip
                if (chips.length > 0) {
                    chips[0].click();
                }

                auditLog.push({
                    query: q,
                    mainCount,
                    v2Count,
                    returnMainCount
                });
            }

            // Clear search
            searchInput.value = '';
            searchInput.dispatchEvent(new Event('input', { bubbles: true }));
            tabMain.click();

            return {
                success: true,
                auditLog
            };
        }""", test_queries)

        page.wait_for_timeout(300)
        assert branch_search_res.get("success", False), branch_search_res.get("reason", "Branch search test failed")
        assert len(logs["errors"]) == 0, f"Errors logged during dual-branch search filtering: {logs['errors']}"

        results.append(TestResult(
            test_id="T5.3_DUAL_BRANCH_SEARCH_FILTER_STRESS",
            name="Dual-Branch Architecture Switching (main <-> v2) Under Search & Filter States",
            tier=5,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=branch_search_res
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T5.3_DUAL_BRANCH_SEARCH_FILTER_STRESS",
            name="Dual-Branch Architecture Switching (main <-> v2) Under Search & Filter States",
            tier=5,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 5.4: Memory Leak & Continuous Animation Profiling
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        
        mem_profile_res = page.evaluate("""() => {
            const initialMem = window.performance && window.performance.memory
                ? {
                    usedJSHeapSize: window.performance.memory.usedJSHeapSize,
                    totalJSHeapSize: window.performance.memory.totalJSHeapSize
                }
                : null;

            // Execute 100 intense interaction cycles of rapid UI mutations
            const themeKeys = ['event-horizon', 'accretion-disk', 'quantum-void'];
            const layouts = ['cosmic', 'concentric', 'layered', 'clusters'];
            const branches = ['main', 'v2'];

            for (let i = 0; i < 100; i++) {
                // Theme mutation
                window.setTheme(themeKeys[i % themeKeys.length]);

                // Branch mutation every 10 cycles
                if (i % 10 === 0) {
                    window.loadBranch(branches[(i / 10) % branches.length]);
                }

                // Layout mutation every 5 cycles
                if (i % 5 === 0) {
                    const sel = document.getElementById('layout-mode');
                    if (sel) {
                        sel.value = layouts[(i / 5) % layouts.length];
                        sel.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                }

                // Camera transform mutation
                if (window.zoomBehavior && window.d3) {
                    const canvas = document.getElementById('graph-canvas');
                    const k = 0.8 + (i % 20) * 0.1;
                    window.d3.select(canvas).call(
                        window.zoomBehavior.transform,
                        window.d3.zoomIdentity.scale(k)
                    );
                }

                // Physics reheat
                if (window.simulation && i % 25 === 0) {
                    window.simulation.alpha(0.6).restart();
                }
            }

            // Return to stable state
            window.loadBranch('main');
            window.setTheme('event-horizon');
            if (typeof window.centerCamera === 'function') {
                window.centerCamera();
            }

            const finalMem = window.performance && window.performance.memory
                ? {
                    usedJSHeapSize: window.performance.memory.usedJSHeapSize,
                    totalJSHeapSize: window.performance.memory.totalJSHeapSize
                }
                : null;

            return {
                success: true,
                cyclesCompleted: 100,
                initialMem,
                finalMem
            };
        }""")

        page.wait_for_timeout(500)
        assert mem_profile_res.get("success", False), mem_profile_res.get("reason", "Memory profiling failed")
        assert len(logs["errors"]) == 0, f"Errors logged during continuous memory profiling: {logs['errors']}"

        # If performance.memory is available (Chromium), verify heap growth is bounded
        initial_m = mem_profile_res.get("initialMem")
        final_m = mem_profile_res.get("finalMem")
        if initial_m and final_m and initial_m.get("usedJSHeapSize", 0) > 0:
            growth_ratio = final_m["usedJSHeapSize"] / initial_m["usedJSHeapSize"]
            assert growth_ratio < 4.0, f"Potential memory leak detected: Heap grew {growth_ratio:.2f}x"

        results.append(TestResult(
            test_id="T5.4_MEMORY_LEAK_ANIMATION_PROFILING",
            name="Memory Leak & Continuous 100-Cycle Animation Profiling",
            tier=5,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=mem_profile_res
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T5.4_MEMORY_LEAK_ANIMATION_PROFILING",
            name="Memory Leak & Continuous 100-Cycle Animation Profiling",
            tier=5,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 5.5: High-Concurrency Chaos Fuzzing
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)

        chaos_res = page.evaluate("""() => {
            // Chaotic interleaving of UI button clicks, slider inputs, and drawer toggles
            const buttons = [
                document.getElementById('toggle-controls-btn'),
                document.getElementById('reset-cam-btn'),
                document.getElementById('reheat-sim-btn'),
                document.getElementById('reset-physics-btn'),
                document.getElementById('tab-compare'),
                document.getElementById('close-compare-btn'),
                document.getElementById('tab-main'),
                document.getElementById('tab-v2')
            ].filter(Boolean);

            for (let i = 0; i < 40; i++) {
                const btn = buttons[i % buttons.length];
                btn.click();
            }

            // Close comparison modal if left open
            if (typeof window.hideComparisonModal === 'function') {
                window.hideComparisonModal();
            }

            // Restore stable main state
            window.loadBranch('main');
            window.setTheme('event-horizon');
            if (typeof window.centerCamera === 'function') {
                window.centerCamera();
            }

            return {
                success: true,
                actionsDispatched: 40,
                currentState: {
                    branch: window.state ? window.state.currentBranch : 'main',
                    theme: window.state ? window.state.theme : 'event-horizon'
                }
            };
        }""")

        page.wait_for_timeout(300)
        assert chaos_res.get("success", False), chaos_res.get("reason", "Chaos fuzzing failed")
        assert len(logs["errors"]) == 0, f"Errors logged during chaos fuzzing: {logs['errors']}"

        results.append(TestResult(
            test_id="T5.5_HIGH_CONCURRENCY_CHAOS_FUZZING",
            name="High-Concurrency Chaos & Disordered Input Fuzzing",
            tier=5,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=chaos_res
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T5.5_HIGH_CONCURRENCY_CHAOS_FUZZING",
            name="High-Concurrency Chaos & Disordered Input Fuzzing",
            tier=5,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    return results
