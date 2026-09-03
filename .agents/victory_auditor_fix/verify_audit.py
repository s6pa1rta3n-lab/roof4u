import http.server
import socketserver
import threading
import time
import hashlib
from playwright.sync_api import sync_playwright

def verify_dataset_hash():
    with open("docs/data.js", "rb") as f:
        data = f.read()
    digest = hashlib.sha256(data).hexdigest()
    expected = "b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e"
    assert digest == expected, f"docs/data.js hash mismatch: {digest} != {expected}"
    print(f"[AUDIT] Dataset byte-identity confirmed: {digest}")

def run_independent_audit():
    verify_dataset_hash()
    
    # Start server
    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(*args, directory="docs", **kwargs)
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    port = httpd.server_address[1]
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{port}/"
    print(f"[AUDIT] Server running at {url}")

    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page.on("console", lambda msg: errors.append(msg.text) if msg.type == "error" else None)
        page.on("pageerror", lambda err: errors.append(str(err)))

        page.goto(url)
        page.wait_for_load_state("networkidle")

        # 1. UI Simplification checks
        # Only branch tabs, theme selector, settings toggle, canvas visible
        assert page.locator("#tab-main").is_visible(), "tab-main visible"
        assert page.locator("#tab-v2").is_visible(), "tab-v2 visible"
        assert page.locator("#tab-compare").is_visible(), "tab-compare visible"
        assert page.locator("#theme-selector").is_visible(), "theme selector visible"
        assert page.locator("#toggle-settings-btn").is_visible(), "settings toggle visible"
        assert page.locator("#graph-canvas").is_visible(), "canvas visible"

        # Secondary controls hidden behind settings drawer
        settings_classes = page.locator("#settings-drawer").get_attribute("class") or ""
        assert "hidden" in settings_classes, "Settings drawer must be hidden on first load"
        
        # Inspector drawer hidden on first load
        inspector_classes = page.locator("#inspector-drawer").get_attribute("class") or ""
        assert "hidden" in inspector_classes, "Inspector drawer must be hidden on first load"

        # Header tagline removed / minimal
        assert page.locator(".brand-tagline").count() == 0, "No multi-line brand tagline"

        # Header height check
        header_height = page.locator(".app-header").bounding_box()["height"]
        assert header_height < 60, f"Header should be compact (<60px), got {header_height}px"

        # 2. Node Distribution and Auto-fit checks
        time.sleep(2.0)
        metrics = page.evaluate("""() => {
            const nodes = window.currentGraph.nodes;
            let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
            nodes.forEach(n => {
                if (n.x < minX) minX = n.x;
                if (n.x > maxX) maxX = n.x;
                if (n.y < minY) minY = n.y;
                if (n.y > maxY) maxY = n.y;
            });
            return {
                nodeCount: nodes.length,
                spanX: maxX - minX,
                spanY: maxY - minY,
                zoomK: window.state.zoomTransform.k,
                panX: window.state.zoomTransform.x,
                panY: window.state.zoomTransform.y
            };
        }""")
        print(f"[AUDIT] Main graph metrics: {metrics}")
        assert metrics["nodeCount"] == 279, f"Main node count expected 279, got {metrics['nodeCount']}"
        assert metrics["spanX"] > 1000, f"Nodes spread horizontally: {metrics['spanX']}"
        assert metrics["spanY"] > 800, f"Nodes spread vertically: {metrics['spanY']}"
        assert 0.15 <= metrics["zoomK"] <= 1.0, f"Zoom within auto-fitted framing range: {metrics['zoomK']}"

        # 3. Settings Drawer interaction & click-away
        page.locator("#toggle-settings-btn").click()
        time.sleep(0.3)
        assert "hidden" not in (page.locator("#settings-drawer").get_attribute("class") or "")
        
        # Click outside to close
        page.mouse.click(100, 300)
        time.sleep(0.3)
        assert "hidden" in (page.locator("#settings-drawer").get_attribute("class") or "")

        # 4. v2 Branch Switching and Node Distribution
        page.locator("#tab-v2").click()
        time.sleep(2.0)
        v2_metrics = page.evaluate("""() => {
            const nodes = window.currentGraph.nodes;
            let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
            nodes.forEach(n => {
                if (n.x < minX) minX = n.x;
                if (n.x > maxX) maxX = n.x;
                if (n.y < minY) minY = n.y;
                if (n.y > maxY) maxY = n.y;
            });
            return {
                nodeCount: nodes.length,
                spanX: maxX - minX,
                spanY: maxY - minY,
                zoomK: window.state.zoomTransform.k
            };
        }""")
        print(f"[AUDIT] v2 graph metrics: {v2_metrics}")
        assert v2_metrics["nodeCount"] == 431, f"v2 node count expected 431, got {v2_metrics['nodeCount']}"
        assert v2_metrics["spanX"] > 1000, f"v2 spanX {v2_metrics['spanX']}"
        assert v2_metrics["spanY"] > 800, f"v2 spanY {v2_metrics['spanY']}"

        # 5. Console errors check
        assert len(errors) == 0, f"Found console errors: {errors}"
        print("[AUDIT] Zero JS/Console errors detected during entire audit.")

        browser.close()

    httpd.shutdown()
    httpd.server_close()
    print("[AUDIT] ALL INDEPENDENT VERIFICATION CHECKS PASSED.")

if __name__ == "__main__":
    run_independent_audit()
