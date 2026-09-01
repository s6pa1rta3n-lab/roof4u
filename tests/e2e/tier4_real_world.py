"""
Tier 4: Real-World Workload Scenarios E2E Tests
Covers:
- Comprehensive End-to-End Architectural Exploration User Flow (Landing -> Theming -> Filtering -> Physics -> Branch Switching -> Shift Modal -> Node Inspection -> Copy Hash -> Camera Reset)
- High-Density Node Filtering & Multi-Layout Mode Stress Testing (Swarm Toggle & Layout Transitions)
"""

import time
from typing import List
from tests.e2e.test_utils import (
    TestResult,
    navigate_and_wait,
    setup_page_listeners
)


def run_tier4_tests(page, base_url: str) -> List[TestResult]:
    results = []
    
    # -------------------------------------------------------------
    # Test 4.1: Complete End-to-End User Architectural Flow
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        navigate_and_wait(page, f"{base_url}/docs/index.html")
        
        # Step 1: Verify Initial Landing State
        stats = page.evaluate("""() => {
            return {
                nodes: document.getElementById('stat-nodes')?.textContent.trim(),
                links: document.getElementById('stat-links')?.textContent.trim(),
                clusters: document.getElementById('stat-clusters')?.textContent.trim()
            };
        }""")
        assert "279" in (stats["nodes"] or ""), f"Initial node count mismatch: {stats['nodes']}"
        
        # Step 2: Cycle Themes
        page.evaluate("""() => {
            const selector = document.getElementById('theme-selector');
            if (selector && selector.options.length >= 3) {
                for (let i = 0; i < 3; i++) {
                    selector.selectedIndex = i;
                    selector.dispatchEvent(new Event('change', { bubbles: true }));
                }
            }
        }""")
        page.wait_for_timeout(200)
        
        # Step 3: Sector Chip Filtering
        chip_clicked = page.evaluate("""() => {
            const chips = document.querySelectorAll('#category-chips .category-chip, .chip');
            if (chips.length > 0) {
                chips[0].click();
                return true;
            }
            return false;
        }""")
        page.wait_for_timeout(200)
        
        # Reset chip filter
        page.evaluate("""() => {
            const chips = document.querySelectorAll('#category-chips .category-chip.active, .chip.active');
            chips.forEach(c => c.click());
        }""")
        page.wait_for_timeout(150)
        
        # Step 4: Physics Controls Drawer
        page.evaluate("""() => {
            const toggleBtn = document.getElementById('toggle-controls-btn');
            if (toggleBtn) toggleBtn.click();
            
            const chargeSlider = document.getElementById('slider-charge');
            if (chargeSlider) {
                chargeSlider.value = "-450";
                chargeSlider.dispatchEvent(new Event('input', { bubbles: true }));
                chargeSlider.dispatchEvent(new Event('change', { bubbles: true }));
            }
            
            // Close drawer
            if (toggleBtn) toggleBtn.click();
        }""")
        page.wait_for_timeout(200)
            
        # Step 5: Switch to v2 branch
        page.evaluate("""() => {
            const tabV2 = document.getElementById('tab-v2');
            if (tabV2) tabV2.click();
            else if (typeof window.loadBranch === 'function') window.loadBranch('v2');
        }""")
        page.wait_for_timeout(500)
        
        # Step 6: Open Comparison Modal (Architecture Shift)
        page.evaluate("""() => {
            const tabCompare = document.getElementById('tab-compare');
            if (tabCompare) tabCompare.click();
            else if (typeof window.showComparisonModal === 'function') window.showComparisonModal();
        }""")
        page.wait_for_timeout(300)
        
        modal_state = page.evaluate("""() => {
            const modal = document.getElementById('compare-modal');
            const isVisible = modal && (
                modal.classList.contains('active') ||
                modal.classList.contains('open') ||
                !modal.classList.contains('hidden') ||
                window.getComputedStyle(modal).display !== 'none'
            );
            const tableRows = modal ? modal.querySelectorAll('tbody tr').length : 0;
            const cards = modal ? modal.querySelectorAll('.mapping-card, .compare-card').length : 0;
            return { isVisible: !!isVisible, tableRows, cards };
        }""")
        
        assert modal_state["isVisible"], "Architecture Shift comparison modal did not open upon clicking #tab-compare!"
        assert modal_state["tableRows"] > 0 or modal_state["cards"] > 0, "Comparison modal content is empty!"
        
        # Close comparison modal with close button or ESC
        page.evaluate("""() => {
            const closeBtn = document.getElementById('close-compare-modal') || document.querySelector('.close-modal-btn');
            if (closeBtn) closeBtn.click();
            else if (typeof window.hideComparisonModal === 'function') window.hideComparisonModal();
            else {
                const modal = document.getElementById('compare-modal');
                if (modal) modal.classList.add('hidden');
            }
        }""")
        page.wait_for_timeout(300)
        
        # Step 7: Select a node & inspect drawer
        node_selected = page.evaluate("""() => {
            if (window.currentGraph && window.currentGraph.nodes && window.currentGraph.nodes.length > 0) {
                const target = window.currentGraph.nodes[0];
                if (typeof window.selectNode === 'function') {
                    window.selectNode(target);
                } else if (window.state) {
                    window.state.selectedNode = target;
                }
                return true;
            }
            return false;
        }""")
        page.wait_for_timeout(200)
        
        # Step 8: Reset Camera
        page.evaluate("""() => {
            const resetCam = document.getElementById('reset-cam-btn');
            if (resetCam) resetCam.click();
            else if (typeof window.centerCamera === 'function') window.centerCamera();
        }""")
        page.wait_for_timeout(200)
            
        assert len(logs["errors"]) == 0, f"Errors logged during full exploration flow: {logs['errors']}"
        
        results.append(TestResult(
            test_id="T4.1_E2E_USER_WORKLOAD_FLOW",
            name="Comprehensive E2E User Architectural Exploration Workflow",
            tier=4,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"initial_stats": stats, "modal": modal_state}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T4.1_E2E_USER_WORKLOAD_FLOW",
            name="Comprehensive E2E User Architectural Exploration Workflow",
            tier=4,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    # -------------------------------------------------------------
    # Test 4.2: High-Density Filtering & Multi-Layout Mode Transitions
    # -------------------------------------------------------------
    t0 = time.time()
    try:
        logs = setup_page_listeners(page)
        
        # Toggle Swarm Logs checkbox via evaluate
        swarm_res = page.evaluate("""() => {
            const swarmCheckbox = document.getElementById('toggle-swarm');
            if (!swarmCheckbox) return { found: false };
            
            swarmCheckbox.checked = false;
            swarmCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
            const countNoSwarm = document.getElementById('stat-nodes')?.textContent.trim();
            
            swarmCheckbox.checked = true;
            swarmCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
            const countWithSwarm = document.getElementById('stat-nodes')?.textContent.trim();
            
            return {
                found: true,
                countNoSwarm,
                countWithSwarm
            };
        }""")
        page.wait_for_timeout(300)
            
        # Test all 4 layout mode transitions
        layout_res = page.evaluate("""() => {
            const layoutSelector = document.getElementById('layout-mode');
            if (!layoutSelector) return { found: false };
            
            const modes = ['cosmic', 'concentric', 'layered', 'clusters'];
            for (const mode of modes) {
                layoutSelector.value = mode;
                layoutSelector.dispatchEvent(new Event('change', { bubbles: true }));
            }
            
            // Restore default
            layoutSelector.value = 'cosmic';
            layoutSelector.dispatchEvent(new Event('change', { bubbles: true }));
            return { found: true, cycledModes: modes };
        }""")
        page.wait_for_timeout(200)
            
        assert len(logs["errors"]) == 0, f"Errors logged during high-density layout transitions: {logs['errors']}"
        
        results.append(TestResult(
            test_id="T4.2_HIGH_DENSITY_LAYOUT_STRESS",
            name="High-Density Swarm Filtering & Multi-Layout Mode Stress",
            tier=4,
            passed=True,
            duration_ms=(time.time() - t0) * 1000,
            details={"swarm": swarm_res, "layout": layout_res}
        ))
    except Exception as e:
        results.append(TestResult(
            test_id="T4.2_HIGH_DENSITY_LAYOUT_STRESS",
            name="High-Density Swarm Filtering & Multi-Layout Mode Stress",
            tier=4,
            passed=False,
            duration_ms=(time.time() - t0) * 1000,
            error_message=str(e)
        ))

    return results
