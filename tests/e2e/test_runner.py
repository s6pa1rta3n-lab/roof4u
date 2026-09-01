#!/usr/bin/env python3
"""
Roo4u Constellation Overhaul E2E Test Suite Runner.
Standalone executable test runner that starts an ephemeral HTTP server,
launches headless Playwright Chromium, and runs all test tiers.

Usage:
    python3 tests/e2e/test_runner.py [--tier 1|2|3|4] [--port PORT] [--verbose]
"""

import os
import sys
import time
import argparse
from typing import List

# Force unbuffered stdout/stderr
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(line_buffering=True)
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(line_buffering=True)

# Ensure repo root is on sys.path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from playwright.sync_api import sync_playwright
from tests.e2e.test_utils import (
    TestResult,
    start_ephemeral_server,
    stop_ephemeral_server
)
from tests.e2e.tier1_feature_coverage import run_tier1_tests
from tests.e2e.tier2_boundary_corner import run_tier2_tests
from tests.e2e.tier3_cross_feature import run_tier3_tests
from tests.e2e.tier4_real_world import run_tier4_tests
from tests.e2e.tier5_adversarial_stress import run_tier5_tests

# ANSI Color codes for clean reporting
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"


def print_banner():
    print(f"\n{BOLD}{CYAN}======================================================================{RESET}", flush=True)
    print(f"{BOLD}{CYAN}      ROO4U CONSTELLATION OVERHAUL — E2E TEST RUNNER                 {RESET}", flush=True)
    print(f"{BOLD}{CYAN}======================================================================{RESET}\n", flush=True)


def print_results_summary(results: List[TestResult], total_duration_s: float):
    total = len(results)
    passed = sum(1 for r in results if r.passed)
    failed = total - passed
    
    print(f"\n{BOLD}----------------------------------------------------------------------{RESET}", flush=True)
    print(f"{BOLD}                           TEST SUMMARY MATRIX                        {RESET}", flush=True)
    print(f"{BOLD}----------------------------------------------------------------------{RESET}", flush=True)
    
    for r in results:
        status_tag = f"{GREEN}[PASS]{RESET}" if r.passed else f"{RED}[FAIL]{RESET}"
        tier_tag = f"{CYAN}Tier {r.tier}{RESET}"
        print(f" {status_tag} {tier_tag:8} | {r.test_id:32} | {r.name[:38]:38} ({r.duration_ms:.1f}ms)", flush=True)
        if not r.passed and r.error_message:
            print(f"        {RED}Error: {r.error_message}{RESET}", flush=True)
            
    print(f"{BOLD}----------------------------------------------------------------------{RESET}", flush=True)
    pass_rate = (passed / total * 100) if total > 0 else 0
    print(f"Total Tests : {BOLD}{total}{RESET}", flush=True)
    print(f"Passed      : {GREEN}{passed}{RESET}", flush=True)
    print(f"Failed      : {RED if failed > 0 else GREEN}{failed}{RESET}", flush=True)
    print(f"Pass Rate   : {GREEN if failed == 0 else YELLOW}{pass_rate:.1f}%{RESET}", flush=True)
    print(f"Duration    : {total_duration_s:.2f}s", flush=True)
    print(f"{BOLD}======================================================================{RESET}\n", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Roo4u Constellation E2E Test Runner")
    parser.add_argument("--tier", type=int, choices=[1, 2, 3, 4, 5], help="Run only a specific tier (1-5)")
    parser.add_argument("--port", type=int, default=0, help="Custom port for local HTTP server (default: random free port)")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    parser.add_argument("--headed", action="store_true", help="Run browser in headed mode (default: headless)")
    args = parser.parse_args()

    if args.verbose:
        os.environ["ROO4U_TEST_VERBOSE"] = "1"

    print_banner()

    # Step 1: Spin up ephemeral local HTTP server
    print(f"[*] Starting ephemeral HTTP server on repo root: {REPO_ROOT}", flush=True)
    httpd, server_thread, base_url = start_ephemeral_server(args.port)
    print(f"[✓] Local server active at: {BOLD}{base_url}{RESET}", flush=True)

    all_results: List[TestResult] = []
    start_time = time.time()

    # Step 2: Initialize Playwright and execute test tiers
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=not args.headed)
            context = browser.new_context(
                viewport={"width": 1920, "height": 1080},
                device_scale_factor=1
            )
            page = context.new_page()

            print(f"[*] Chromium initialized. Executing test suites...\n", flush=True)

            # Tier 1
            if args.tier is None or args.tier == 1:
                print(f"{BOLD}>>> Running Tier 1: Feature Coverage Tests...{RESET}", flush=True)
                t1_results = run_tier1_tests(page, base_url)
                all_results.extend(t1_results)
                for r in t1_results:
                    tag = f"{GREEN}PASS{RESET}" if r.passed else f"{RED}FAIL{RESET}"
                    print(f"  [{tag}] {r.test_id}: {r.name}", flush=True)

            # Tier 2
            if args.tier is None or args.tier == 2:
                print(f"\n{BOLD}>>> Running Tier 2: Boundary & Corner Cases...{RESET}", flush=True)
                t2_results = run_tier2_tests(page, base_url)
                all_results.extend(t2_results)
                for r in t2_results:
                    tag = f"{GREEN}PASS{RESET}" if r.passed else f"{RED}FAIL{RESET}"
                    print(f"  [{tag}] {r.test_id}: {r.name}", flush=True)

            # Tier 3
            if args.tier is None or args.tier == 3:
                print(f"\n{BOLD}>>> Running Tier 3: Cross-Feature Interactions...{RESET}", flush=True)
                t3_results = run_tier3_tests(page, base_url)
                all_results.extend(t3_results)
                for r in t3_results:
                    tag = f"{GREEN}PASS{RESET}" if r.passed else f"{RED}FAIL{RESET}"
                    print(f"  [{tag}] {r.test_id}: {r.name}", flush=True)

            # Tier 4
            if args.tier is None or args.tier == 4:
                print(f"\n{BOLD}>>> Running Tier 4: Real-World Workload Scenarios...{RESET}", flush=True)
                t4_results = run_tier4_tests(page, base_url)
                all_results.extend(t4_results)
                for r in t4_results:
                    tag = f"{GREEN}PASS{RESET}" if r.passed else f"{RED}FAIL{RESET}"
                    print(f"  [{tag}] {r.test_id}: {r.name}", flush=True)

            # Tier 5
            if args.tier is None or args.tier == 5:
                print(f"\n{BOLD}>>> Running Tier 5: Adversarial Coverage Hardening...{RESET}", flush=True)
                t5_results = run_tier5_tests(page, base_url)
                all_results.extend(t5_results)
                for r in t5_results:
                    tag = f"{GREEN}PASS{RESET}" if r.passed else f"{RED}FAIL{RESET}"
                    print(f"  [{tag}] {r.test_id}: {r.name}", flush=True)

            context.close()
            browser.close()

    except Exception as e:
        print(f"\n{RED}[!] Unhandled test runner exception: {e}{RESET}", flush=True)
        all_results.append(TestResult(
            test_id="RUNNER_FATAL_ERROR",
            name="Playwright Test Runner Execution",
            tier=0,
            passed=False,
            duration_ms=0,
            error_message=str(e)
        ))
    finally:
        # Step 3: Cleanly terminate HTTP server
        print(f"\n[*] Shutting down ephemeral server...", flush=True)
        stop_ephemeral_server(httpd, server_thread)
        print(f"[✓] Ephemeral server terminated.", flush=True)

    total_duration = time.time() - start_time
    print_results_summary(all_results, total_duration)

    # Return exit code: 0 if all pass, 1 if any failed
    has_failures = any(not r.passed for r in all_results)
    return 1 if has_failures else 0


if __name__ == "__main__":
    sys.exit(main())
