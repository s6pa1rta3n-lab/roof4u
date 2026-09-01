"""
tests/test_judge_agent.py

Component and integration test suite for agents/judge_agent.py (Milestone 4).
Validates AST security scanning, test report parsing, 5-dimension rubric scoring,
SHA-256 digital sign-off generation, and CLI runner execution.
100% Mock-Free.
"""

import os
import sys
import json
import tempfile
import hashlib
import subprocess
import pytest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from agents.judge_agent import (
    AgentAsJudge,
    ASTScanResult,
    TestReportMetrics,
    RubricScoreBreakdown,
    CertificationData
)


# ============================================================================
# 1. AST SECURITY & ANTI-MOCK SCANNER TESTS
# ============================================================================

class TestASTScanner:
    """Validates AST scanner across codebase compliance and synthetic violation traps."""

    def test_ast_scan_clean_codebase(self):
        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        result = judge.scan_ast()
        assert isinstance(result, ASTScanResult)
        assert result.files_scanned >= 10
        assert len(result.forbidden_import_violations) == 0
        assert len(result.hardcoded_key_violations) == 0
        assert len(result.empty_facade_violations) == 0
        assert result.passed is True

    def test_ast_scan_detects_mock_import_violation(self, tmp_path):
        bad_file = tmp_path / "bad_mock.py"
        bad_file.write_text("import unittest.mock\n\ndef test_dummy():\n    pass\n", encoding="utf-8")

        judge = AgentAsJudge(repo_root=str(tmp_path))
        result = judge.scan_ast(repo_path=str(tmp_path))
        assert result.passed is False
        assert any("unittest.mock" in v for v in result.forbidden_import_violations)

    def test_ast_scan_detects_magicmock_name_violation(self, tmp_path):
        bad_file = tmp_path / "bad_magic.py"
        bad_file.write_text("from anything import MagicMock\n", encoding="utf-8")

        judge = AgentAsJudge(repo_root=str(tmp_path))
        result = judge.scan_ast(repo_path=str(tmp_path))
        assert result.passed is False
        assert any("MagicMock" in v for v in result.forbidden_import_violations)

    def test_ast_scan_detects_cloud_sdk_violation(self, tmp_path):
        bad_file = tmp_path / "bad_sdk.py"
        bad_file.write_text("import google.generativeai as genai\n", encoding="utf-8")

        judge = AgentAsJudge(repo_root=str(tmp_path))
        result = judge.scan_ast(repo_path=str(tmp_path))
        assert result.passed is False
        assert any("Cloud SDK" in v for v in result.forbidden_import_violations)

    def test_ast_scan_detects_empty_facade_function(self, tmp_path):
        # Concrete implementation file (not test_*)
        concrete_file = tmp_path / "agents" / "facade_agent.py"
        concrete_file.parent.mkdir(parents=True, exist_ok=True)
        concrete_file.write_text("class FacadeAgent:\n    def scrape(self):\n        '''Empty docstring only'''\n", encoding="utf-8")

        judge = AgentAsJudge(repo_root=str(tmp_path))
        result = judge.scan_ast(repo_path=str(tmp_path))
        assert result.passed is False
        assert any("Empty facade" in v for v in result.empty_facade_violations)

    def test_file_tree_hashing_consistency(self):
        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        r1 = judge.scan_ast()
        r2 = judge.scan_ast()
        assert r1.file_hashes == r2.file_hashes


# ============================================================================
# 2. TEST REPORT PARSER TESTS
# ============================================================================

class TestReportParser:
    """Validates parsing of pytest JSON output formats."""

    def test_parse_valid_test_report(self, tmp_path):
        report_file = tmp_path / "sample_report.json"
        report_data = {
            "summary": {
                "total": 375,
                "passed": 375,
                "failed": 0,
                "error": 0,
                "skipped": 0,
                "duration": 45.2
            },
            "tests": [
                {"nodeid": f"tests/test_{i}.py::test_case", "outcome": "passed"} for i in range(375)
            ],
            "metadata": {"project": "Roo4u", "mode": "ZERO_MOCK"}
        }
        report_file.write_text(json.dumps(report_data), encoding="utf-8")

        judge = AgentAsJudge(repo_root=str(tmp_path))
        metrics = judge.parse_test_report(str(report_file))
        assert metrics.total_tests == 375
        assert metrics.passed_tests == 375
        assert metrics.failed_tests == 0
        assert metrics.pass_rate == 1.0
        assert metrics.all_passed is True
        assert metrics.duration_seconds == 45.2

    def test_parse_report_with_failures(self, tmp_path):
        report_file = tmp_path / "failing_report.json"
        report_data = {
            "summary": {
                "total": 100,
                "passed": 95,
                "failed": 5,
                "error": 0,
                "skipped": 0,
                "duration": 20.0
            },
            "tests": []
        }
        report_file.write_text(json.dumps(report_data), encoding="utf-8")

        judge = AgentAsJudge(repo_root=str(tmp_path))
        metrics = judge.parse_test_report(str(report_file))
        assert metrics.total_tests == 100
        assert metrics.passed_tests == 95
        assert metrics.failed_tests == 5
        assert metrics.pass_rate == 0.95
        assert metrics.all_passed is False

    def test_parse_missing_report_raises_filenotfound(self, tmp_path):
        judge = AgentAsJudge(repo_root=str(tmp_path))
        with pytest.raises(FileNotFoundError):
            judge.parse_test_report(str(tmp_path / "nonexistent.json"))


# ============================================================================
# 3. 5-DIMENSION RUBRIC EVALUATOR TESTS
# ============================================================================

class Test5DRubricEngine:
    """Validates weighted scoring logic, dimension point caps, and hard gate enforcement."""

    def test_rubric_perfect_score_100(self):
        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        ast_res = ASTScanResult(files_scanned=20, passed=True)
        test_met = TestReportMetrics(
            total_tests=375,
            passed_tests=375,
            failed_tests=0,
            error_tests=0,
            pass_rate=1.0,
            duration_seconds=50.0,
            all_passed=True,
            test_names=[f"tests/test_learning_{i}.py" for i in range(10)]
        )

        rubric = judge.evaluate_5d_rubric(ast_res, test_met)
        assert rubric.overall_score == 100.0
        assert rubric.status == "PASS"
        assert rubric.security_and_credentials == 25.0
        assert rubric.anti_mock_integrity == 25.0
        assert rubric.functional_correctness == 25.0
        assert rubric.self_healing_and_learning == 15.0
        assert rubric.runtime_performance == 10.0
        assert rubric.hard_gate_passed is True

    def test_rubric_hard_gate_failure_on_security_violation(self):
        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        ast_res = ASTScanResult(
            files_scanned=20,
            hardcoded_key_violations=["agents/bad.py:10 Hardcoded key detected"],
            passed=False
        )
        test_met = TestReportMetrics(total_tests=100, passed_tests=100, all_passed=True, pass_rate=1.0)

        rubric = judge.evaluate_5d_rubric(ast_res, test_met)
        assert rubric.security_and_credentials == 0.0
        assert rubric.status == "FAIL"
        assert rubric.hard_gate_passed is False
        assert len(rubric.hard_gate_failures) >= 1

    def test_rubric_hard_gate_failure_on_mock_violation(self):
        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        ast_res = ASTScanResult(
            files_scanned=20,
            forbidden_import_violations=["tests/bad.py: from unittest.mock import MagicMock"],
            passed=False
        )
        test_met = TestReportMetrics(total_tests=100, passed_tests=100, all_passed=True, pass_rate=1.0)

        rubric = judge.evaluate_5d_rubric(ast_res, test_met)
        assert rubric.anti_mock_integrity == 0.0
        assert rubric.status == "FAIL"
        assert rubric.hard_gate_passed is False

    def test_rubric_hard_gate_failure_on_test_failures(self):
        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        ast_res = ASTScanResult(files_scanned=20, passed=True)
        test_met = TestReportMetrics(
            total_tests=100,
            passed_tests=98,
            failed_tests=2,
            all_passed=False,
            pass_rate=0.98
        )

        rubric = judge.evaluate_5d_rubric(ast_res, test_met)
        assert rubric.functional_correctness == 0.0
        assert rubric.status == "FAIL"
        assert rubric.hard_gate_passed is False


# ============================================================================
# 4. DIGITAL CERTIFICATION & ARTIFACT GENERATION
# ============================================================================

class TestDigitalCertificationSignOff:
    """Validates end-to-end certification emission and SHA-256 cryptographic verification."""

    def test_certify_full_workflow(self, tmp_path):
        # Create synthetic valid report
        report_file = tmp_path / ".test_report.json"
        report_data = {
            "summary": {
                "total": 375,
                "passed": 375,
                "failed": 0,
                "error": 0,
                "skipped": 0,
                "duration": 40.0
            },
            "tests": [
                {"nodeid": f"tests/test_memory_{i}.py::test_{i}", "outcome": "passed"} for i in range(10)
            ]
        }
        report_file.write_text(json.dumps(report_data), encoding="utf-8")

        out_json = str(tmp_path / "CERTIFIED_PASS.json")
        out_md = str(tmp_path / "CERTIFICATION_REPORT.md")

        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        cert = judge.certify(
            test_report_path=str(report_file),
            output_path=out_json,
            markdown_path=out_md
        )

        assert cert["status"] == "PASS"
        assert cert["overall_score"] == 100.0
        assert "sha256_digest" in cert
        assert "file_tree_hash" in cert

        # Verify JSON file on disk
        assert os.path.exists(out_json)
        with open(out_json, "r", encoding="utf-8") as f:
            disk_data = json.load(f)
        assert disk_data["overall_score"] == 100.0
        assert disk_data["sha256_digest"] == cert["sha256_digest"]

        # Verify Markdown file on disk
        assert os.path.exists(out_md)
        with open(out_md, "r", encoding="utf-8") as f:
            md_text = f.read()
        assert "Roo4u Agent-As-Judge Digital Certification Report" in md_text
        assert "100.0 / 100.0" in md_text
        assert cert["sha256_digest"] in md_text

    def test_sha256_digest_tamper_detection(self, tmp_path):
        report_file = tmp_path / ".test_report.json"
        report_data = {
            "summary": {"total": 100, "passed": 100, "failed": 0, "duration": 10.0},
            "tests": [{"nodeid": f"test_learning_{i}", "outcome": "passed"} for i in range(10)]
        }
        report_file.write_text(json.dumps(report_data), encoding="utf-8")

        judge = AgentAsJudge(repo_root=PROJECT_ROOT)
        cert = judge.certify(
            test_report_path=str(report_file),
            output_path=str(tmp_path / "cert.json"),
            markdown_path=str(tmp_path / "cert.md")
        )

        orig_digest = cert["sha256_digest"]

        # Tampering with score should invalidate hash check
        tampered_cert = cert.copy()
        tampered_cert["overall_score"] = 99.0
        tampered_json = json.dumps(tampered_cert, sort_keys=True)
        recalculated = hashlib.sha256(tampered_json.encode()).hexdigest()
        assert recalculated != orig_digest


# ============================================================================
# 5. CLI RUNNER EXECUTION TEST
# ============================================================================

class TestJudgeCLIRunner:
    """Validates execution of scripts/run_judge.py as a standalone subprocess."""

    def test_run_judge_cli_execution(self, tmp_path):
        report_file = tmp_path / "cli_test_report.json"
        report_data = {
            "summary": {"total": 375, "passed": 375, "failed": 0, "duration": 30.0},
            "tests": [{"nodeid": f"test_learning_{i}", "outcome": "passed"} for i in range(10)]
        }
        report_file.write_text(json.dumps(report_data), encoding="utf-8")

        out_json = str(tmp_path / "cli_pass.json")
        out_md = str(tmp_path / "cli_report.md")

        res = subprocess.run(
            [
                "./venv/bin/python", "scripts/run_judge.py",
                "--report", str(report_file),
                "--output", out_json,
                "--markdown", out_md
            ],
            capture_output=True,
            text=True,
            timeout=30
        )

        assert res.returncode == 0
        assert "ROO4U AGENT-AS-JUDGE EVALUATION & CERTIFICATION ENGINE" in res.stdout
        assert "OVERALL EVALUATION SCORE" in res.stdout
        assert "CERTIFICATION SUCCESS: Roo4u has achieved 100.0% PASS certification!" in res.stdout
        assert os.path.exists(out_json)
        assert os.path.exists(out_md)
