#!/usr/bin/env python3
"""
scripts/run_judge.py

Authoritative CLI runner for Roo4u Agent-As-Judge Evaluator & Certification (Milestone 4).
Runs AST security scanning, test report parsing, 5-dimension rubric scoring,
and generates cryptographically signed CERTIFIED_PASS.json and CERTIFICATION_REPORT.md.
"""

import os
import sys
import argparse
import subprocess
import json

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from agents.judge_agent import AgentAsJudge


def print_banner():
    print("=" * 72)
    print(" 🏛️  ROO4U AGENT-AS-JUDGE EVALUATION & CERTIFICATION ENGINE")
    print(" Milestone 4: Zero-Mock Verification & Digital Sign-Off")
    print("=" * 72)


def print_rubric_table(cert_data: dict):
    scores = cert_data.get("rubric_scores", {})
    overall = cert_data.get("overall_score", 0.0)
    status = cert_data.get("status", "FAIL")

    print("\n" + "-" * 72)
    print(f" {'DIMENSION':<42} | {'MAX':<6} | {'SCORE':<6} | {'STATUS':<8}")
    print("-" * 72)

    dimensions = [
        ("D1. Security & Credentials (Zero Keys/SDKs)", 25.0, scores.get("security_and_credentials", 0.0)),
        ("D2. Anti-Mock Integrity (Zero Mocks/Facades)", 25.0, scores.get("anti_mock_integrity", 0.0)),
        ("D3. Functional Correctness (100% Tests Pass)", 25.0, scores.get("functional_correctness", 0.0)),
        ("D4. Self-Healing & Learning (Dual Memory/GH)", 15.0, scores.get("self_healing_and_learning", 0.0)),
        ("D5. Runtime Performance & Socket Hygiene", 10.0, scores.get("runtime_performance", 0.0)),
    ]

    for name, max_pts, score in dimensions:
        dim_status = "PASS" if score == max_pts else "FAIL"
        print(f" {name:<42} | {max_pts:<6.1f} | {score:<6.1f} | {dim_status:<8}")

    print("-" * 72)
    print(f" {'OVERALL EVALUATION SCORE':<42} | 100.0  | {overall:<6.1f} | {status:<8}")
    print("-" * 72)

    print(f"\n[+] Certification ID : {cert_data.get('certification_id')}")
    print(f"[+] File Tree Hash   : {cert_data.get('file_tree_hash')}")
    print(f"[+] SHA-256 Digest   : {cert_data.get('sha256_digest')}")
    print(f"[+] Evaluation Status: {status}")
    print("-" * 72)


def main():
    parser = argparse.ArgumentParser(description="Roo4u Agent-As-Judge CLI Evaluator")
    parser.add_argument("--run-pytest", action="store_true", help="Execute full pytest suite before evaluation")
    parser.add_argument("--report", type=str, default=".test_report.json", help="Path to pytest JSON report")
    parser.add_argument("--output", type=str, default="CERTIFIED_PASS.json", help="Output path for certification JSON")
    parser.add_argument("--markdown", type=str, default="CERTIFICATION_REPORT.md", help="Output path for markdown report")
    args = parser.parse_args()

    print_banner()

    report_file = os.path.abspath(args.report)

    # 1. Optionally run pytest if requested or if report is missing
    if args.run_pytest or not os.path.exists(report_file):
        print(f"\n[*] Executing Pytest suite with JSON report emission ({report_file})...")
        pytest_cmd = [
            "./venv/bin/pytest",
            "-v",
            "--json-report",
            f"--json-report-file={report_file}"
        ]
        res = subprocess.run(pytest_cmd, cwd=PROJECT_ROOT)
        if res.returncode != 0 and not os.path.exists(report_file):
            print(f"\n[-] Pytest execution failed without producing report file: {report_file}")
            sys.exit(1)

    # 2. Run AgentAsJudge evaluation
    print(f"\n[*] Running AgentAsJudge AST security audit and rubric evaluation...")
    judge = AgentAsJudge(repo_root=PROJECT_ROOT)

    try:
        cert_data = judge.certify(
            test_report_path=report_file,
            output_path=args.output,
            markdown_path=args.markdown
        )
    except Exception as e:
        print(f"\n[-] Certification failed with error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # 3. Print evaluation table
    print_rubric_table(cert_data)

    status = cert_data.get("status", "FAIL")
    overall = cert_data.get("overall_score", 0.0)

    if status == "PASS" and overall == 100.0:
        print(f"\n🏆 CERTIFICATION SUCCESS: Roo4u has achieved 100.0% PASS certification!")
        print(f"Artifacts created: {args.output}, {args.markdown}\n")
        sys.exit(0)
    else:
        print(f"\n❌ CERTIFICATION FAILED: Overall score {overall}/100.0. Status: {status}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
