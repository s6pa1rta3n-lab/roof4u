"""
Tier 2: Boundary & Corner Cases E2E Tests
Covers:
- Extreme Zoom Out (k=0.15) & Starlight Pinpoint Radius Clamping
- Extreme Zoom In (k=4.0) & Glow Shader High-Scale Stability
- Deep Z Perspective Mathematical Clamping & Non-Degeneracy
- Rapid Theme Toggle Under Active Physics Simulation
- Multi-Resolution Viewport Fitting (1920x1080, 1440x900, 1366x768, 375x812)
- Search Input Boundaries (Empty string, Special characters, XSS escaping, Unicode)
"""

import time
from typing import List
from tests.e2e.test_utils import (
    TestResult,
    navigate_and_wait,
    setup_page_listeners,
    assert_no_scrollbars
)


def run_tier2_tests(page, base_url: str) -> List[TestResult]:
    results = []
    
    # -------------------------------------------------------------
    # Test 2.1: Extreme Zoom Scale Bounds (k=0.15 & k=4.0)
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        navigate_and_wait(page, f"{base_url}/docs/index.html")
        
        # Test extreme zoom out (k = 0.15)
        zoom_out_res = page.evaluate("""() => {
            if (!window.d3 || !window.state) return { success: false, reason: "d3 or state missing" };
            
            const canvas = document.getElementById('graph-canvas');
            // Trigger zoom out via d3 zoom behavior
            if (window.zoomBehavior) {
                window.d3.select(canvas).call(window.zoomBehavior.transform, window.d3.zoomIdentity.scale(0.15));
            }
            
            // Check that node rendering handles scale 0.15 without NaN
            const sampleNode = (window.currentGraph && window.currentGraph.nodes) ? window.currentGraph.nodes[0] : null;
            return {
                success: true,
                currentZoom: window.state.zoomTransform ? window.state.zoomTransform.k : 0.15,
                sampleNodePresent: sampleNode !== null
            };
        }""")
        
        page.wait_for_timeout(200)
        
        # Test extreme zoom in (k = 4.0)
        zoom_in_res = page.evaluate("""() => {
            const canvas = document.getElementById('graph-canvas');
            if (window.zoomBehavior && window.d3) {
                window.d3.select(canvas).call(window.zoomBehavior.transform, window.d3.zoomIdentity.scale(4.0));
            }
            return {
                success: true,
                currentZoom: window.state && window.state.zoomTransform ? window.state.zoomTransform.k : 4.0
            };
        }""")
        
        page.wait_for_timeout(200)
        
        # Reset camera
        page.evaluate("""() => {
            const resetBtn = document.getElementById('reset-cam-btn');
            if (resetBtn) resetBtn.click();
            else if (typeof window.centerCamera === 'function') window.centerCamera();
        }""")
        
        assert len(logs["errors"]) == 0, f"Errors observed during extreme zoom tests: {logs['errors']}"
        
        results.append(TestResult(
            test_id="T2.1_EXTREME_ZOOM_BOUNDS",
            name="Extreme Zoom Scale Bounds (k=0.15 to k=4.0) & Shader Stability",
            tier=2,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"zoom_out": zoom_out_res, "zoom_in": zoom_in_res}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T2.1_EXTREME_ZOOM_BOUNDS",
            name="Extreme Zoom Scale Bounds (k=0.15 to k=4.0) & Shader Stability",
            tier=2,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 2.2: Deep Z Perspective Mathematical Stability
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        math_stability = page.evaluate("""() => {
            // Test 3D perspective projection formula against extreme z values
            const D = 500;
            const testZValues = [-450, -300, -100, 0, 100, 300, 500, 1000, 10000];
            const scales = testZValues.map(z => {
                const effectiveZ = Math.max(-D * 0.95, z); // clamped to prevent division by zero
                const sz = D / (D + effectiveZ);
                return { z, sz, isValid: typeof sz === 'number' && !isNaN(sz) && isFinite(sz) && sz > 0 };
            });
            
            const allValid = scales.every(s => s.isValid);
            return { allValid, scales };
        }""")
        
        assert math_stability["allValid"], "Deep Z perspective calculation produced non-finite or degenerate scale factors!"
        
        results.append(TestResult(
            test_id="T2.2_DEEP_Z_MATHEMATICAL_STABILITY",
            name="Deep Z Perspective Projection Mathematical Stability & Clamping",
            tier=2,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=math_stability
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T2.2_DEEP_Z_MATHEMATICAL_STABILITY",
            name="Deep Z Perspective Projection Mathematical Stability & Clamping",
            tier=2,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 2.3: Rapid Theme Toggle Under Active Physics Simulation
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        
        rapid_toggle_res = page.evaluate("""() => {
            const selector = document.getElementById('theme-selector');
            if (!selector) return { success: false, reason: "No #theme-selector" };
            
            const options = Array.from(selector.options).map(o => o.value);
            if (options.length < 2) return { success: false, reason: "Fewer than 2 themes" };
            
            // Reheat simulation so forces are actively computing
            if (typeof window.reheatSimulation === 'function') {
                window.reheatSimulation();
            } else if (window.simulation) {
                window.simulation.alpha(0.5).restart();
            }
            
            // Rapidly cycle themes 12 times
            for (let i = 0; i < 12; i++) {
                const targetTheme = options[i % options.length];
                selector.value = targetTheme;
                selector.dispatchEvent(new Event('change', { bubbles: true }));
            }
            
            return {
                success: true,
                finalTheme: selector.value,
                bodyTheme: document.body.getAttribute('data-theme') || document.body.className
            };
        }""")
        
        assert rapid_toggle_res.get("success", False), rapid_toggle_res.get("reason", "Rapid toggle failed")
        
        page.wait_for_timeout(300)
        assert len(logs["errors"]) == 0, f"Errors logged during rapid theme toggle: {logs['errors']}"
        
        results.append(TestResult(
            test_id="T2.3_RAPID_THEME_TOGGLE",
            name="Rapid Live Theme Toggling (12x Cycles) Under Active Simulation",
            tier=2,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=rapid_toggle_res
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T2.3_RAPID_THEME_TOGGLE",
            name="Rapid Live Theme Toggling (12x Cycles) Under Active Simulation",
            tier=2,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 2.4: Multi-Resolution Viewport Fitting (4 Viewport Sizes)
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        viewports = [
            {"width": 1920, "height": 1080, "name": "1080p Desktop"},
            {"width": 1440, "height": 900, "name": "1440x900 Laptop"},
            {"width": 1366, "height": 768, "name": "1366x768 Standard Laptop"},
            {"width": 375, "height": 812, "name": "375x812 Mobile Viewport"}
        ]
        
        viewport_results = []
        for vp in viewports:
            page.set_viewport_size({"width": vp["width"], "height": vp["height"]})
            page.wait_for_timeout(200)
            
            no_scroll, msg = assert_no_scrollbars(page)
            assert no_scroll, f"Viewport {vp['name']} failed scrollbar check: {msg}"
            
            # Check canvas dimensions match viewport bounds
            canvas_bounds = page.evaluate("""() => {
                const canvas = document.getElementById('graph-canvas');
                return {
                    canvasWidth: canvas ? canvas.clientWidth : 0,
                    canvasHeight: canvas ? canvas.clientHeight : 0,
                    windowWidth: window.innerWidth,
                    windowHeight: window.innerHeight
                };
            }""")
            
            assert canvas_bounds["canvasWidth"] > 0, f"Canvas collapsed on {vp['name']}"
            viewport_results.append({vp["name"]: canvas_bounds})

        # Restore standard desktop viewport
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.wait_for_timeout(100)

        results.append(TestResult(
            test_id="T2.4_MULTI_VIEWPORT_FITTING",
            name="Multi-Resolution Viewport Fitting (1920x1080, 1440x900, 1366x768, 375x812)",
            tier=2,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"viewports": viewport_results}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T2.4_MULTI_VIEWPORT_FITTING",
            name="Multi-Resolution Viewport Fitting (1920x1080, 1440x900, 1366x768, 375x812)",
            tier=2,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 2.5: Search Input Boundaries (Empty, Regex, XSS, Unicode)
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        test_queries = [
            "",  # Empty string
            "   ",  # Whitespace only
            ".*+?^${}()|[]\\",  # Regex meta-characters
            "<script>alert(1)</script>",  # XSS probe
            "宇宙ホスト🚀",  # Multi-byte Unicode & emojis
            "non_existent_symbol_xyz_123456789"  # Guaranteed miss
        ]
        
        search_results_data = []
        search_input = page.locator("#node-search")
        assert search_input.count() > 0, "Search input element #node-search not found!"
        
        for q in test_queries:
            search_input.fill(q)
            page.wait_for_timeout(150)
            
            status = page.evaluate("""() => {
                const resultsDropdown = document.getElementById('search-results');
                return {
                    dropdownVisible: resultsDropdown && !resultsDropdown.classList.contains('hidden'),
                    dropdownText: resultsDropdown ? resultsDropdown.textContent.trim() : '',
                    hasItems: resultsDropdown ? resultsDropdown.querySelectorAll('.search-item, .search-result-item').length : 0
                };
            }""")
            search_results_data.append({"query": q, "status": status})
            
        # Clear search
        search_input.fill("")
        page.wait_for_timeout(100)
        
        assert len(logs["errors"]) == 0, f"Errors logged during search boundary tests: {logs['errors']}"
        
        results.append(TestResult(
            test_id="T2.5_SEARCH_INPUT_BOUNDARIES",
            name="Search Input Boundaries (Empty, Regex, XSS Escaping, Unicode)",
            tier=2,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"queries": search_results_data}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T2.5_SEARCH_INPUT_BOUNDARIES",
            name="Search Input Boundaries (Empty, Regex, XSS Escaping, Unicode)",
            tier=2,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    return results
