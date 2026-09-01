"""
Test Utilities and Fixtures for Roo4u Constellation E2E Test Suite.
Provides ephemeral HTTP server management, Playwright page lifecycle helpers,
canvas inspection, and assertion utilities.
"""

import os
import sys
import time
import socket
import hashlib
import threading
from http.server import HTTPServer, SimpleHTTPRequestHandler
from typing import Tuple, List, Dict, Any, Optional
from dataclasses import dataclass, field

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
DATA_JS_PATH = os.path.join(DOCS_DIR, "data.js")
EXPECTED_DATA_JS_SHA256 = "b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e"


@dataclass
class TestResult:
    test_id: str
    name: str
    tier: int
    passed: bool
    duration_ms: float
    error_message: Optional[str] = None
    details: Dict[str, Any] = field(default_factory=dict)


class QuietHTTPRequestHandler(SimpleHTTPRequestHandler):
    """HTTP Request Handler serving from repo root with suppressed access logs."""
    def __init__(self, *args, directory=None, **kwargs):
        if directory is None:
            directory = REPO_ROOT
        super().__init__(*args, directory=directory, **kwargs)

    def log_message(self, format, *args):
        # Suppress standard access logs unless verbose
        if os.environ.get("ROO4U_TEST_VERBOSE", "0") == "1":
            super().log_message(format, *args)

    def end_headers(self):
        # Disable caching for reliable E2E testing
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()


def find_free_port() -> int:
    """Find a free TCP port on localhost."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('127.0.0.1', 0))
        s.listen(1)
        return s.getsockname()[1]


def start_ephemeral_server(port: Optional[int] = None) -> Tuple[HTTPServer, threading.Thread, str]:
    """Start an ephemeral background HTTP server serving REPO_ROOT."""
    if port is None or port == 0:
        port = find_free_port()
    
    server_address = ('127.0.0.1', port)
    httpd = HTTPServer(server_address, QuietHTTPRequestHandler)
    
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    
    # Wait for server to become responsive
    base_url = f"http://127.0.0.1:{port}"
    max_wait = 5.0
    start_time = time.time()
    while time.time() - start_time < max_wait:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.5):
                break
        except (ConnectionRefusedError, socket.timeout, OSError):
            time.sleep(0.05)
            
    return httpd, thread, base_url


def stop_ephemeral_server(httpd: HTTPServer, thread: threading.Thread) -> None:
    """Shutdown the ephemeral HTTP server."""
    try:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=2.0)
    except Exception:
        pass


def compute_file_sha256(file_path: str) -> str:
    """Compute SHA-256 hex digest of a local file."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def setup_page_listeners(page) -> Dict[str, List[str]]:
    """Attach console and error listeners to Playwright page."""
    logs = {
        "errors": [],
        "warnings": [],
        "logs": []
    }
    
    def on_console(msg):
        text = msg.text
        if msg.type == "error":
            logs["errors"].append(text)
        elif msg.type == "warning":
            logs["warnings"].append(text)
        else:
            logs["logs"].append(text)
            
    def on_page_error(exc):
        logs["errors"].append(f"Uncaught Exception: {exc}")
        
    page.on("console", on_console)
    page.on("pageerror", on_page_error)
    return logs


def navigate_and_wait(page, url: str, wait_for_sim: bool = True, timeout_ms: int = 10000):
    """Navigate to visualizer and wait for canvas and data to be fully loaded."""
    page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
    
    # Wait for graph canvas to be present in DOM
    page.wait_for_selector("#graph-canvas", timeout=timeout_ms)
    
    # Wait for graph data and d3 to be loaded in window context
    page.wait_for_function(
        """() => {
            return (typeof window.ROO4U_GRAPH_DATA !== 'undefined') &&
                   (document.getElementById('graph-canvas') !== null);
        }""",
        timeout=timeout_ms
    )
    
    if wait_for_sim:
        # Give simulation a brief moment to run initial ticks
        page.wait_for_timeout(300)


def assert_no_scrollbars(page) -> Tuple[bool, str]:
    """Check if the document has zero horizontal or vertical scrollbars."""
    metrics = page.evaluate("""() => {
        const doc = document.documentElement;
        const body = document.body;
        return {
            windowWidth: window.innerWidth,
            windowHeight: window.innerHeight,
            docScrollWidth: doc.scrollWidth,
            docScrollHeight: doc.scrollHeight,
            docClientWidth: doc.clientWidth,
            docClientHeight: doc.clientHeight,
            bodyScrollWidth: body.scrollWidth,
            bodyScrollHeight: body.scrollHeight,
            overflowX: window.getComputedStyle(doc).overflowX,
            overflowY: window.getComputedStyle(doc).overflowY
        };
    }""")
    
    # Allow 1px tolerance for sub-pixel anti-aliasing on certain viewports
    has_h_scrollbar = metrics["docScrollWidth"] > (metrics["windowWidth"] + 1)
    has_v_scrollbar = metrics["docScrollHeight"] > (metrics["windowHeight"] + 1)
    
    if has_h_scrollbar or has_v_scrollbar:
        msg = (f"Scrollbar detected: docScroll=({metrics['docScrollWidth']}x{metrics['docScrollHeight']}) "
               f"vs window=({metrics['windowWidth']}x{metrics['windowHeight']})")
        return False, msg
    return True, "No scrollbars detected"
