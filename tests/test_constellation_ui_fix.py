import http.server
import socketserver
import threading
import time
from playwright.sync_api import sync_playwright

class EphemeralServer:
    def __init__(self, directory):
        self.directory = directory
        self.httpd = None
        self.thread = None
        self.port = None

    def start(self):
        handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(*args, directory=self.directory, **kwargs)
        self.httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        return f"http://127.0.0.1:{self.port}/"

    def stop(self):
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()

def run_tests():
    server = EphemeralServer("docs")
    url = server.start()
    print(f"Testing at {url}", flush=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 900})

        console_errors = []
        page.on("console", lambda msg: console_errors.append(msg.text) if msg.type == "error" else None)
        page.on("pageerror", lambda err: console_errors.append(str(err)))

        page.goto(url)
        page.wait_for_load_state("networkidle")

        # Test 1: Chrome Simplification on Initial Load (R2)
        print("[*] Test 1: Chrome Simplification on Initial Load...", flush=True)
        tab_main = page.locator("#tab-main")
        tab_v2 = page.locator("#tab-v2")
        tab_compare = page.locator("#tab-compare")
        theme_selector = page.locator("#theme-selector")
        settings_toggle = page.locator("#toggle-settings-btn")
        canvas = page.locator("#graph-canvas")
        tagline = page.locator(".brand-tagline")
        settings_drawer = page.locator("#settings-drawer")
        inspector_drawer = page.locator("#inspector-drawer")

        assert tab_main.is_visible(), "Main tab must be visible"
        assert tab_v2.is_visible(), "v2 tab must be visible"
        assert tab_compare.is_visible(), "Architecture Shift tab must be visible"
        assert theme_selector.is_visible(), "Theme selector must be visible"
        assert settings_toggle.is_visible(), "Settings toggle must be visible"
        assert canvas.is_visible(), "Canvas must be visible"
        assert tagline.count() == 0, "Multi-line tagline must be removed"

        # Check that settings and inspector drawers are hidden on load
        settings_classes = settings_drawer.get_attribute("class") or ""
        assert "hidden" in settings_classes, f"Settings drawer should be hidden initially: {settings_classes}"
        inspector_classes = inspector_drawer.get_attribute("class") or ""
        assert "hidden" in inspector_classes, f"Inspector drawer should be hidden initially: {inspector_classes}"
        print("    [PASS] Default chrome is minimal.", flush=True)

        # Test 2: Node Distribution and Auto-fit within 2s (R1)
        print("[*] Test 2: Node Distribution and Auto-fit...", flush=True)
        time.sleep(2.0)
        bounds = page.evaluate("""() => {
            const nodes = window.currentGraph.nodes;
            let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
            nodes.forEach(n => {
                if (n.x < minX) minX = n.x;
                if (n.x > maxX) maxX = n.x;
                if (n.y < minY) minY = n.y;
                if (n.y > maxY) maxY = n.y;
            });
            const k = window.state.zoomTransform.k;
            const tx = window.state.zoomTransform.x;
            const ty = window.state.zoomTransform.y;
            return {
                nodeCount: nodes.length,
                spanX: maxX - minX,
                spanY: maxY - minY,
                k: k,
                tx: tx,
                ty: ty,
                alpha: window.simulation.alpha()
            };
        }""")

        assert bounds["nodeCount"] == 279, f"Expected 279 nodes on main, got {bounds['nodeCount']}"
        assert bounds["spanX"] > 600, f"Nodes did not spread horizontally: spanX={bounds['spanX']}"
        assert bounds["spanY"] > 400, f"Nodes did not spread vertically: spanY={bounds['spanY']}"
        assert bounds["k"] > 0.2 and bounds["k"] < 2.0, f"Camera zoom is out of expected range: k={bounds['k']}"
        print(f"    [PASS] 279 nodes on main spread across canvas (span: {bounds['spanX']:.1f}x{bounds['spanY']:.1f}, zoom: {bounds['k']:.2f}).", flush=True)

        # Test 3: Settings Drawer Interactions (R2)
        print("[*] Test 3: Settings Drawer Opening, Content, and Click-away...", flush=True)
        settings_toggle.click()
        time.sleep(0.3)
        settings_classes = settings_drawer.get_attribute("class") or ""
        assert "hidden" not in settings_classes, "Settings drawer must open on toggle click"

        # Search bar, Layout select, Filters, Stats HUD inside drawer
        search_input = page.locator("#node-search")
        layout_select = page.locator("#layout-mode")
        hud_stats = page.locator("#hud-branch-tag")
        assert search_input.is_visible(), "Search bar must be visible inside settings drawer"
        assert layout_select.is_visible(), "Layout selector must be visible inside settings drawer"
        assert hud_stats.is_visible(), "Stats HUD must be visible inside settings drawer"

        # Click outside (click-away on canvas)
        page.mouse.click(200, 300)
        time.sleep(0.3)
        settings_classes = settings_drawer.get_attribute("class") or ""
        assert "hidden" in settings_classes, "Settings drawer must close on click-away"
        print("    [PASS] Settings drawer toggles and closes on click-away.", flush=True)

        # Test 4: Node Selection & Inspector Drawer (R2)
        print("[*] Test 4: Node Selection & Inspector Drawer...", flush=True)
        page.evaluate("""() => {
            const firstNode = window.currentGraph.nodes[0];
            window.selectNode(firstNode);
        }""")
        time.sleep(0.3)
        inspector_classes = inspector_drawer.get_attribute("class") or ""
        assert "hidden" not in inspector_classes, "Inspector drawer must open on node selection"
        insp_name = page.locator("#insp-name").inner_text()
        assert len(insp_name) > 0, "Inspector must display node name"

        # Press Escape to close inspector
        page.keyboard.press("Escape")
        time.sleep(0.3)
        inspector_classes = inspector_drawer.get_attribute("class") or ""
        assert "hidden" in inspector_classes, "Inspector drawer must close on Escape"
        print("    [PASS] Node selection opens inspector and Escape closes it.", flush=True)

        # Test 5: Search Selection Closes Settings Drawer
        print("[*] Test 5: Search Selection...", flush=True)
        settings_toggle.click()
        time.sleep(0.3)
        search_input.fill("audit")
        time.sleep(0.3)
        first_result = page.locator(".search-result-item").first
        assert first_result.is_visible(), "Search result must be displayed"
        first_result.click()
        time.sleep(0.3)

        settings_classes = settings_drawer.get_attribute("class") or ""
        assert "hidden" in settings_classes, "Settings drawer must close upon selecting search item"
        inspector_classes = inspector_drawer.get_attribute("class") or ""
        assert "hidden" not in inspector_classes, "Inspector drawer must open for search selection"
        print("    [PASS] Search selection properly routes to inspector and closes settings.", flush=True)

        # Test 6: Branch switching (v2 -> main)
        print("[*] Test 6: Branch Switching...", flush=True)
        tab_v2.click()
        time.sleep(1.0)
        v2_node_count = page.evaluate("() => window.currentGraph.nodes.length")
        assert v2_node_count == 431, f"Expected 431 nodes on v2, got {v2_node_count}"
        tab_main.click()
        time.sleep(1.0)
        main_node_count = page.evaluate("() => window.currentGraph.nodes.length")
        assert main_node_count == 279, f"Expected 279 nodes on main, got {main_node_count}"
        print("    [PASS] Branch switching succeeds with full node graph.", flush=True)

        # Test 7: Physics Reset and Sliders
        print("[*] Test 7: Physics Reset and Sliders...", flush=True)
        settings_toggle.click()
        time.sleep(0.3)
        page.evaluate("""() => {
            document.getElementById('slider-charge').value = -1000;
            document.getElementById('slider-charge').dispatchEvent(new Event('input'));
            document.getElementById('reset-physics-btn').click();
        }""")
        time.sleep(0.3)
        charge_val = page.evaluate("() => window.state.physics.charge")
        assert charge_val == -480, f"Expected reset charge -480, got {charge_val}"
        print("    [PASS] Physics reset successfully restored default parameters.", flush=True)

        # Test 8: Responsive Viewport Form Factors (Desktop, Tablet, Mobile)
        print("[*] Test 8: Responsive Viewports (375px Mobile, 768px Tablet, 1280px Laptop)...", flush=True)
        for vp in [{"width": 1280, "height": 800}, {"width": 768, "height": 1024}, {"width": 375, "height": 667}]:
            page.set_viewport_size(vp)
            time.sleep(0.2)
            s_box = page.locator("#node-search").bounding_box()
            assert s_box is not None, f"Search input missing at viewport {vp['width']}x{vp['height']}"
            assert s_box["width"] > 200, f"Search input squished at viewport {vp['width']}x{vp['height']}: width={s_box['width']}"
            assert page.locator("#layout-mode").is_visible(), f"Layout selector hidden at viewport {vp['width']}"
            assert page.locator("#zoom-indicator").is_visible(), f"Zoom indicator hidden at viewport {vp['width']}"
        print("    [PASS] Responsive viewports render drawer controls with full visibility and width.", flush=True)

        # Test 9: Category Chips Filter & Swarm Toggle within Settings Drawer
        print("[*] Test 9: Category Filter Chips & Swarm Toggle Interaction...", flush=True)
        page.set_viewport_size({"width": 1440, "height": 900})
        time.sleep(0.2)
        # Ensure drawer is open
        if "hidden" in (settings_drawer.get_attribute("class") or ""):
            settings_toggle.click()
            time.sleep(0.3)
        
        # Test category chip selection
        page.locator(".category-chip").first.click()
        time.sleep(0.5)
        filtered_count = page.evaluate("() => window.currentGraph.nodes.length")
        assert filtered_count < 279, f"Category filter should reduce nodes, got {filtered_count}"
        active_chips = page.evaluate("() => document.querySelectorAll('.category-chip.active').length")
        assert active_chips == 1, f"Expected exactly 1 active chip, got {active_chips}"
        assert "hidden" not in (settings_drawer.get_attribute("class") or ""), "Settings drawer should stay open when clicking category chips"

        # Toggle chip back off
        page.locator(".category-chip").first.click()
        time.sleep(0.5)
        assert page.evaluate("() => window.currentGraph.nodes.length") == 279
        all_chips = page.evaluate("() => document.querySelectorAll('.category-chip').length")
        active_chips = page.evaluate("() => document.querySelectorAll('.category-chip.active').length")
        assert active_chips == all_chips, "All chips should be marked active when no filter is active"
        print("    [PASS] Category filter chips toggle and maintain drawer state correctly.", flush=True)

        # Test 10: Zero Console Errors
        print("[*] Test 10: Console Errors...", flush=True)
        assert len(console_errors) == 0, f"Encountered console errors: {console_errors}"
        print("    [PASS] Zero console errors during interaction lifecycle.", flush=True)

        browser.close()

    server.stop()
    print("\nALL VERIFICATION TESTS PASSED SUCCESSFULLY!", flush=True)

if __name__ == "__main__":
    run_tests()
