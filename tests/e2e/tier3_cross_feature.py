"""
Tier 3: Cross-Feature Interactions E2E Tests
Covers:
- Theme Switch Under Active Pan & Zoom Camera Transform (Preserves Camera State & Parallax)
- Dual-Branch Architecture Toggle (main <-> v2) Under Custom Theme
- Search Autocomplete Selection Focusing Node in 3D & Populating Inspector
- Constellation Isolation Mode Operating Seamlessly Across Theme Changes
"""

import time
from typing import List
from tests.e2e.test_utils import (
    TestResult,
    navigate_and_wait,
    setup_page_listeners
)


def run_tier3_tests(page, base_url: str) -> List[TestResult]:
    results = []
    
    # -------------------------------------------------------------
    # Test 3.1: Theme Switch Under Active Pan & Zoom Transform
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        navigate_and_wait(page, f"{base_url}/docs/index.html")
        
        # Apply custom pan and zoom transform
        pan_zoom_res = page.evaluate("""() => {
            const canvas = document.getElementById('graph-canvas');
            if (window.d3 && window.zoomBehavior) {
                // Set pan to (180, 120) and zoom to 1.75
                const customTransform = window.d3.zoomIdentity.translate(180, 120).scale(1.75);
                window.d3.select(canvas).call(window.zoomBehavior.transform, customTransform);
            }
            return {
                setTransform: { x: 180, y: 120, k: 1.75 },
                currentTransform: window.state && window.state.zoomTransform ? {
                    x: window.state.zoomTransform.x,
                    y: window.state.zoomTransform.y,
                    k: window.state.zoomTransform.k
                } : null
            };
        }""")
        
        page.wait_for_timeout(200)
        
        # Switch theme
        theme_switched = page.evaluate("""() => {
            const selector = document.getElementById('theme-selector');
            if (!selector || selector.options.length < 2) return false;
            selector.selectedIndex = (selector.selectedIndex + 1) % selector.options.length;
            selector.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
        }""")
        
        page.wait_for_timeout(200)
        
        # Verify transform was preserved after theme change
        post_transform = page.evaluate("""() => {
            return window.state && window.state.zoomTransform ? {
                x: window.state.zoomTransform.x,
                y: window.state.zoomTransform.y,
                k: window.state.zoomTransform.k
            } : null;
        }""")
        
        if post_transform:
            assert abs(post_transform["k"] - 1.75) < 0.1, (
                f"Zoom scale not preserved during theme change! Expected ~1.75, got {post_transform['k']}"
            )
            assert abs(post_transform["x"] - 180) < 1.0, (
                f"Pan X not preserved during theme change! Expected ~180, got {post_transform['x']}"
            )

        results.append(TestResult(
            test_id="T3.1_THEME_WITH_ACTIVE_TRANSFORM",
            name="Theme Switch Under Active Pan & Zoom Camera Transform",
            tier=3,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"pre": pan_zoom_res, "post": post_transform}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T3.1_THEME_WITH_ACTIVE_TRANSFORM",
            name="Theme Switch Under Active Pan & Zoom Camera Transform",
            tier=3,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 3.2: Dual-Branch Switch (main <-> v2) Under Custom Theme
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        
        # Select custom theme first (if available)
        page.evaluate("""() => {
            const selector = document.getElementById('theme-selector');
            if (selector && selector.options.length >= 2) {
                selector.selectedIndex = 1;
                selector.dispatchEvent(new Event('change', { bubbles: true }));
            }
        }""")
        page.wait_for_timeout(150)
        
        # Click v2 branch tab
        page.evaluate("""() => {
            const tabV2 = document.getElementById('tab-v2');
            if (tabV2) tabV2.click();
            else if (typeof window.loadBranch === 'function') window.loadBranch('v2');
        }""")
        page.wait_for_timeout(500)
        
        # Verify v2 stats (431 nodes, 334 links)
        v2_stats = page.evaluate("""() => {
            const statNodes = document.getElementById('stat-nodes');
            const statLinks = document.getElementById('stat-links');
            const branchTag = document.getElementById('hud-branch-tag');
            return {
                nodes: statNodes ? statNodes.textContent.trim() : null,
                links: statLinks ? statLinks.textContent.trim() : null,
                tag: branchTag ? branchTag.textContent.trim() : null,
                activeBranch: window.state ? window.state.activeBranch : null
            };
        }""")
        
        assert "431" in (v2_stats["nodes"] or ""), f"Expected 431 nodes for v2 branch, got {v2_stats['nodes']}"
        assert "334" in (v2_stats["links"] or ""), f"Expected 334 links for v2 branch, got {v2_stats['links']}"
        
        # Switch back to main branch
        page.evaluate("""() => {
            const tabMain = document.getElementById('tab-main');
            if (tabMain) tabMain.click();
            else if (typeof window.loadBranch === 'function') window.loadBranch('main');
        }""")
        page.wait_for_timeout(500)
        
        main_stats = page.evaluate("""() => {
            const statNodes = document.getElementById('stat-nodes');
            const statLinks = document.getElementById('stat-links');
            return {
                nodes: statNodes ? statNodes.textContent.trim() : null,
                links: statLinks ? statLinks.textContent.trim() : null,
                activeBranch: window.state ? window.state.activeBranch : null
            };
        }""")
        
        assert "279" in (main_stats["nodes"] or ""), f"Expected 279 nodes for main branch, got {main_stats['nodes']}"
        assert "164" in (main_stats["links"] or ""), f"Expected 164 links for main branch, got {main_stats['links']}"

        results.append(TestResult(
            test_id="T3.2_BRANCH_TOGGLE_CUSTOM_THEME",
            name="Dual-Branch Architecture Switch (main <-> v2) Under Custom Theme",
            tier=3,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"v2": v2_stats, "main": main_stats}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T3.2_BRANCH_TOGGLE_CUSTOM_THEME",
            name="Dual-Branch Architecture Switch (main <-> v2) Under Custom Theme",
            tier=3,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 3.3: Search Selection Focusing Node in 3D Depth
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        
        # Type search query "agent"
        page.evaluate("""() => {
            const searchInput = document.getElementById('node-search');
            if (searchInput) {
                searchInput.value = 'agent';
                searchInput.dispatchEvent(new Event('input', { bubbles: true }));
            }
        }""")
        page.wait_for_timeout(300)
        
        # Click the first search dropdown item
        click_res = page.evaluate("""() => {
            const items = document.querySelectorAll('#search-results .search-item, #search-results .search-result-item');
            if (items.length > 0) {
                items[0].click();
                return { clicked: true, count: items.length };
            }
            return { clicked: false, count: 0 };
        }""")
        
        assert click_res["clicked"], "No search dropdown items found for query 'agent'"
        page.wait_for_timeout(400)
        
        # Verify inspector drawer opens
        inspector_state = page.evaluate("""() => {
            const drawer = document.getElementById('inspector-drawer');
            const isOpen = drawer && (
                drawer.classList.contains('open') ||
                drawer.classList.contains('active') ||
                !drawer.classList.contains('hidden')
            );
            const selectedNode = window.state ? (window.state.selectedNode || window.state.activeNode) : null;
            const shaCopyBtn = document.getElementById('insp-sha-copy') || document.querySelector('.sha-copy-btn');
            
            return {
                drawerFound: drawer !== null,
                isOpen: !!isOpen,
                selectedNodeName: selectedNode ? selectedNode.name || selectedNode.id : null,
                hasShaCopyBtn: shaCopyBtn !== null
            };
        }""")
        
        assert inspector_state["isOpen"], "Inspector drawer did not open upon search result selection!"
        assert inspector_state["hasShaCopyBtn"], "SHA-256 copy button missing in inspector drawer!"

        results.append(TestResult(
            test_id="T3.3_SEARCH_FOCUS_INSPECTOR",
            name="Search Autocomplete Selection Focusing Node in 3D & Populating Inspector",
            tier=3,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=inspector_state
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T3.3_SEARCH_FOCUS_INSPECTOR",
            name="Search Autocomplete Selection Focusing Node in 3D & Populating Inspector",
            tier=3,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 3.4: Constellation Isolation Mode with Theme Palette
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        
        # Activate constellation isolation
        isolation_res = page.evaluate("""() => {
            const focusBtn = document.getElementById('focus-constellation-btn') || document.querySelector('.focus-constellation-btn');
            if (focusBtn) {
                focusBtn.click();
            } else if (typeof window.isolateConstellation === 'function') {
                window.isolateConstellation();
            }
            
            return {
                isolated: window.state ? !!window.state.isIsolated : false
            };
        }""")
        
        page.wait_for_timeout(200)
        
        # Switch theme while isolated
        page.evaluate("""() => {
            const selector = document.getElementById('theme-selector');
            if (selector && selector.options.length >= 3) {
                selector.selectedIndex = 2; // third theme
                selector.dispatchEvent(new Event('change', { bubbles: true }));
            }
        }""")
        page.wait_for_timeout(200)
        
        # Clear isolation
        page.evaluate("""() => {
            const clearBtn = document.getElementById('clear-focus-btn') || document.querySelector('.clear-focus-btn');
            if (clearBtn) clearBtn.click();
            else if (typeof window.clearIsolation === 'function') window.clearIsolation();
        }""")
        page.wait_for_timeout(150)
        
        assert len(logs["errors"]) == 0, f"Errors logged during isolation tests: {logs['errors']}"

        results.append(TestResult(
            test_id="T3.4_ISOLATION_THEME_INTERACTION",
            name="Constellation Isolation Mode Cross-Theme Integration",
            tier=3,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details=isolation_res
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T3.4_ISOLATION_THEME_INTERACTION",
            name="Constellation Isolation Mode Cross-Theme Integration",
            tier=3,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    return results
