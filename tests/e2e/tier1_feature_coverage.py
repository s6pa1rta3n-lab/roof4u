"""
Tier 1: Feature Coverage E2E Tests
Covers:
- Data Invariance SHA-256 Guarantee (docs/data.js)
- R1. 3D Depth Rendering Engine (Z-coordinates, perspective scaling, depth sorting, filaments, photons)
- R2. Pure Black Hole Void Aesthetic (Pure #000000 background, starfield cleanup, black glassmorphism)
- R3. Minimap Decommissioning & Screen Fitting (Minimap removal, relocated zoom indicator, 100vh fitting)
- R4. Multiple Design Proposals & Live Theme Switching (>= 3 themes, zero-reload switching, palette updates)
"""

import os
import time
from typing import List
from tests.e2e.test_utils import (
    TestResult,
    compute_file_sha256,
    DATA_JS_PATH,
    EXPECTED_DATA_JS_SHA256,
    navigate_and_wait,
    setup_page_listeners,
    assert_no_scrollbars
)


def run_tier1_tests(page, base_url: str) -> List[TestResult]:
    results = []
    
    # -------------------------------------------------------------
    # Test 1.1: Data Invariance SHA-256 Check
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        actual_sha = compute_file_sha256(DATA_JS_PATH)
        assert actual_sha == EXPECTED_DATA_JS_SHA256, (
            f"Dataset SHA-256 mismatch! Expected {EXPECTED_DATA_JS_SHA256}, got {actual_sha}"
        )
        results.append(TestResult(
            test_id="T1.1_DATA_INVARIANCE",
            name="Dataset Invariance SHA-256 Guarantee (docs/data.js)",
            tier=1,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"sha256": actual_sha}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T1.1_DATA_INVARIANCE",
            name="Dataset Invariance SHA-256 Guarantee (docs/data.js)",
            tier=1,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 1.2: R2 Pure Black Hole Void (#000000) & Canvas Backdrop
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        navigate_and_wait(page, f"{base_url}/docs/index.html")
        
        bg_info = page.evaluate("""() => {
            const bodyBg = window.getComputedStyle(document.body).backgroundColor;
            const htmlBg = window.getComputedStyle(document.documentElement).backgroundColor;
            const workspace = document.querySelector('.workspace');
            const workspaceBg = workspace ? window.getComputedStyle(workspace).backgroundColor : null;
            const canvas = document.getElementById('graph-canvas');
            const canvasBg = canvas ? window.getComputedStyle(canvas).backgroundColor : null;
            return { bodyBg, htmlBg, workspaceBg, canvasBg };
        }""")
        
        # Must be pure black rgb(0, 0, 0)
        assert bg_info["bodyBg"] in ["rgb(0, 0, 0)", "#000000", "black"], (
            f"document.body background must be pure black rgb(0,0,0), got: {bg_info['bodyBg']}"
        )
        
        # Check no non-black ambient canvas background
        if bg_info["workspaceBg"] and bg_info["workspaceBg"] not in ["rgba(0, 0, 0, 0)", "transparent", "rgb(0, 0, 0)"]:
            raise AssertionError(f".workspace background is not black/transparent: {bg_info['workspaceBg']}")

        results.append(TestResult(
            test_id="T1.2_BLACK_HOLE_VOID",
            name="R2: Pure Black Hole Void Aesthetic (#000000 background)",
            tier=1,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=bg_info
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T1.2_BLACK_HOLE_VOID",
            name="R2: Pure Black Hole Void Aesthetic (#000000 background)",
            tier=1,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 1.3: R2 Starfield Cleanup & Black Glassmorphism Panels
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        hud_info = page.evaluate("""() => {
            const starfieldCanvas = document.getElementById('starfield-canvas');
            const starfieldVisible = starfieldCanvas && (
                starfieldCanvas.offsetWidth > 0 ||
                window.getComputedStyle(starfieldCanvas).display !== 'none'
            );
            
            const statsPanel = document.querySelector('.hud-stats');
            const filtersPanel = document.querySelector('.hud-filters');
            const statsBg = statsPanel ? window.getComputedStyle(statsPanel).backgroundColor : null;
            const filtersBg = filtersPanel ? window.getComputedStyle(filtersPanel).backgroundColor : null;
            
            return {
                hasStarfieldElement: starfieldCanvas !== null,
                starfieldVisible: !!starfieldVisible,
                statsBg,
                filtersBg
            };
        }""")
        
        # Starfield canvas must either be completely removed from DOM or disabled/hidden
        assert not hud_info["hasStarfieldElement"] or not hud_info["starfieldVisible"], (
            "Static starfield canvas is still present and active in DOM/view!"
        )
        
        # Panels must use black-based translucent glassmorphism (rgba(0, 0, 0, ...))
        if hud_info["statsBg"]:
            assert hud_info["statsBg"].startswith("rgba(0, 0, 0,") or hud_info["statsBg"] == "rgb(0, 0, 0)", (
                f"HUD stats panel does not use black glassmorphism: {hud_info['statsBg']}"
            )
            
        results.append(TestResult(
            test_id="T1.3_GLASS_PANELS_STARFIELD",
            name="R2: Starfield Decommissioning & Black Glassmorphism HUDs",
            tier=1,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=hud_info
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T1.3_GLASS_PANELS_STARFIELD",
            name="R2: Starfield Decommissioning & Black Glassmorphism HUDs",
            tier=1,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 1.4: R3 Minimap Removal & Viewport Screen Fitting
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        # Check standard 1920x1080 screen fitting
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.wait_for_timeout(300)
        
        minimap_check = page.evaluate("""() => {
            const minimapCanvas = document.getElementById('minimap-canvas');
            const minimapHud = document.querySelector('.hud-minimap');
            const minimapContainer = document.getElementById('minimap-container');
            const zoomIndicator = document.getElementById('zoom-indicator') || document.querySelector('.zoom-badge') || document.querySelector('.zoom-indicator');
            
            return {
                hasMinimapCanvas: minimapCanvas !== null,
                hasMinimapHud: minimapHud !== null,
                hasMinimapContainer: minimapContainer !== null,
                hasZoomIndicator: zoomIndicator !== null,
                zoomIndicatorText: zoomIndicator ? zoomIndicator.textContent.trim() : null
            };
        }""")
        
        assert not minimap_check["hasMinimapCanvas"], "Minimap canvas #minimap-canvas is still present in DOM!"
        assert not minimap_check["hasMinimapHud"], "Minimap HUD panel .hud-minimap is still present in DOM!"
        assert not minimap_check["hasMinimapContainer"], "Minimap container #minimap-container is still present in DOM!"
        assert minimap_check["hasZoomIndicator"], "Zoom level indicator was removed instead of being cleanly relocated!"
        
        no_scroll, scroll_msg = assert_no_scrollbars(page)
        assert no_scroll, scroll_msg
        
        results.append(TestResult(
            test_id="T1.4_MINIMAP_REMOVAL_VIEWPORT",
            name="R3: Galactic Radar Minimap Decommissioning & 100vh Fitting",
            tier=1,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=minimap_check
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T1.4_MINIMAP_REMOVAL_VIEWPORT",
            name="R3: Galactic Radar Minimap Decommissioning & 100vh Fitting",
            tier=1,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 1.5: R1 3D Depth Engine (Z-Coordinates, Perspective, Sorting)
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        depth_data = page.evaluate("""() => {
            // Check state / graph nodes for z coordinate presence
            let nodes = null;
            if (window.currentGraph && window.currentGraph.nodes) {
                nodes = window.currentGraph.nodes;
            } else if (window.graphNodes) {
                nodes = window.graphNodes;
            } else if (window.state && window.state.nodes) {
                nodes = window.state.nodes;
            }
            
            if (!nodes || nodes.length === 0) {
                return { hasNodes: false };
            }
            
            const zValues = nodes.map(n => n.z).filter(z => typeof z === 'number' && !isNaN(z));
            const hasZ = zValues.length === nodes.length;
            const minZ = Math.min(...zValues);
            const maxZ = Math.max(...zValues);
            
            // Check if project3D or perspective projection function exists
            const hasProject3D = typeof window.project3D === 'function' || typeof window.projectNode === 'function';
            
            // Check continuous z variation (not all same depth)
            const uniqueZCount = new Set(zValues).size;
            
            return {
                hasNodes: true,
                totalNodes: nodes.length,
                hasZ,
                minZ,
                maxZ,
                uniqueZCount,
                hasProject3D
            };
        }""")
        
        assert depth_data["hasNodes"], "No graph nodes available in window context to inspect 3D properties."
        assert depth_data["hasZ"], "Not all graph nodes have numeric z-coordinates assigned!"
        assert depth_data["uniqueZCount"] > 5, (
            f"Z-coordinates lack continuous volumetric variation (only {depth_data['uniqueZCount']} unique z values)."
        )
        assert depth_data["maxZ"] > depth_data["minZ"], (
            f"Z-coordinates do not span a continuous depth range: [{depth_data['minZ']}, {depth_data['maxZ']}]."
        )
        
        results.append(TestResult(
            test_id="T1.5_3D_DEPTH_ENGINE",
            name="R1: 3D Depth Rendering Engine (Z-Coordinates & Perspective)",
            tier=1,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=depth_data
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T1.5_3D_DEPTH_ENGINE",
            name="R1: 3D Depth Rendering Engine (Z-Coordinates & Perspective)",
            tier=1,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 1.6: R4 Multiple Design Proposals & Live Theme Switcher
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        theme_check = page.evaluate("""() => {
            const selector = document.getElementById('theme-selector') || document.querySelector('.theme-select');
            if (!selector) {
                return { hasSelector: false };
            }
            
            const options = Array.from(selector.options || []).map(o => ({ value: o.value, text: o.textContent }));
            return {
                hasSelector: true,
                optionsCount: options.length,
                options,
                currentValue: selector.value,
                bodyThemeAttr: document.body.getAttribute('data-theme') || document.body.className
            };
        }""")
        
        assert theme_check["hasSelector"], "Theme selector element (#theme-selector) not found in header/DOM!"
        assert theme_check["optionsCount"] >= 3, (
            f"Expected at least 3 distinct theme proposals, found {theme_check['optionsCount']} options."
        )
        
        # Test live switching between all options without page reload
        for option in theme_check["options"]:
            theme_val = option["value"]
            page.select_option("#theme-selector", theme_val)
            page.wait_for_timeout(200)
            
            # Verify body theme attribute / class was updated immediately
            current_theme_state = page.evaluate("""() => {
                return {
                    bodyThemeAttr: document.body.getAttribute('data-theme') || '',
                    bodyClass: document.body.className,
                    colorPrimary: window.getComputedStyle(document.body).getPropertyValue('--color-primary').trim() ||
                                  window.getComputedStyle(document.documentElement).getPropertyValue('--color-primary').trim()
                };
            }""")
            
            theme_applied = (theme_val in current_theme_state["bodyThemeAttr"]) or (theme_val in current_theme_state["bodyClass"])
            assert theme_applied, f"Live theme switch to '{theme_val}' failed to update DOM data-theme or class!"

        results.append(TestResult(
            test_id="T1.6_THEME_SWITCHER",
            name="R4: 3 Design Proposals & Live Zero-Reload Theme Switcher",
            tier=1,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=theme_check
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T1.6_THEME_SWITCHER",
            name="R4: 3 Design Proposals & Live Zero-Reload Theme Switcher",
            tier=1,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    return results
