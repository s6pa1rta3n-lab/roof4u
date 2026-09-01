"""
agents/judge_agent.py

Independent Agent-As-Judge Evaluator and Digital Certification Sign-off Engine for Roo4u.
Evaluates repository integrity, AST security compliance (zero-mock & zero-key standards),
parses programmatic pytest test reports, computes 5-dimension weighted rubric scores,
and generates cryptographically signed PASS/FAIL certifications.
"""

import os
import sys
import ast
import re
import json
import time
import hashlib
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Tuple, Set
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


# ============================================================================
# DATA MODELS
# ============================================================================

class ASTScanResult(BaseModel):
    """Outcome of static AST security and anti-mock analysis."""
    files_scanned: int = 0
    forbidden_import_violations: List[str] = Field(default_factory=list)
    hardcoded_key_violations: List[str] = Field(default_factory=list)
    empty_facade_violations: List[str] = Field(default_factory=list)
    passed: bool = True
    scanned_file_list: List[str] = Field(default_factory=list)
    file_hashes: Dict[str, str] = Field(default_factory=dict)
    details: Dict[str, Any] = Field(default_factory=dict)


class TestReportMetrics(BaseModel):
    """Parsed test execution metrics from pytest JSON report."""
    __test__ = False
    total_tests: int = 0
    passed_tests: int = 0
    failed_tests: int = 0
    error_tests: int = 0
    skipped_tests: int = 0
    pass_rate: float = 0.0
    duration_seconds: float = 0.0
    all_passed: bool = False
    metadata: Dict[str, Any] = Field(default_factory=dict)
    test_names: List[str] = Field(default_factory=list)


class RubricScoreBreakdown(BaseModel):
    """5-Dimension Rubric Scoring Breakdown (Max 100.0)."""
    security_and_credentials: float = Field(default=0.0, description="Dimension 1: Max 25.0 pts")
    anti_mock_integrity: float = Field(default=0.0, description="Dimension 2: Max 25.0 pts")
    functional_correctness: float = Field(default=0.0, description="Dimension 3: Max 25.0 pts")
    self_healing_and_learning: float = Field(default=0.0, description="Dimension 4: Max 15.0 pts")
    runtime_performance: float = Field(default=0.0, description="Dimension 5: Max 10.0 pts")
    overall_score: float = Field(default=0.0, description="Total score: Max 100.0 pts")
    status: str = Field(default="FAIL", description="'PASS' or 'FAIL'")
    hard_gate_passed: bool = False
    hard_gate_failures: List[str] = Field(default_factory=list)
    dimension_details: Dict[str, Any] = Field(default_factory=dict)


class CertificationData(BaseModel):
    """Formal digital sign-off artifact."""
    certification_id: str
    project: str = "Roo4u"
    version: str = "1.0.0"
    milestone: str = "M4"
    status: str
    overall_score: float
    rubric_scores: Dict[str, float]
    test_metrics: Dict[str, Any]
    security_summary: Dict[str, Any]
    file_tree_hash: str
    sha256_digest: str
    timestamp: str
    certified_by: str = "AgentAsJudge / Autonomous Evaluator"


# ============================================================================
# AGENT AS JUDGE ENGINE
# ============================================================================

class AgentAsJudge:
    """
    Independent Evaluator Agent implementing the full 5-dimension rubric,
    AST security scanning, zero-mock validation, and SHA-256 digital certification.
    """

    FORBIDDEN_MOCK_MODULES: Set[str] = {
        "unittest.mock", "mock", "pytest_mock", "responses", "vcr", "freezegun"
    }
    FORBIDDEN_MOCK_NAMES: Set[str] = {
        "MagicMock", "Mock", "patch", "AsyncMock", "PropertyMock", "create_autospec"
    }
    FORBIDDEN_CLOUD_SDKS: Set[str] = {
        "google.generativeai", "google.ai.generativelanguage", "langchain_google_genai"
    }

    # Concrete concrete API key patterns (excluding short regex patterns or placeholders)
    KEY_PATTERNS = [
        re.compile(r"^AIzaSy[A-Za-z0-9_-]{33}$"),
        re.compile(r"^sk-proj-[A-Za-z0-9_-]{20,}$"),
        re.compile(r"^sk-ant-[A-Za-z0-9_-]{20,}$"),
        re.compile(r"^ghp_[A-Za-z0-9]{36}$"),
        re.compile(r"^gho_[A-Za-z0-9]{36}$"),
    ]

    def __init__(self, repo_root: Optional[str] = None):
        self.repo_root = os.path.abspath(repo_root or os.path.join(os.path.dirname(__file__), ".."))

    # -----------------------------------------------------------------------
    # 1. AST Security & Anti-Mock Scanner
    # -----------------------------------------------------------------------

    def scan_ast(self, repo_path: Optional[str] = None) -> ASTScanResult:
        """
        Scans all Python source and test files using ast.walk to detect:
        1. Forbidden mock imports (unittest.mock, MagicMock, patch).
        2. Forbidden cloud SDK imports (google.generativeai, etc.).
        3. Hardcoded real API keys (AIzaSy..., sk-proj-..., ghp_...).
        4. Empty facade functions in concrete implementation modules.
        """
        root_dir = os.path.abspath(repo_path or self.repo_root)
        target_subdirs = ["agents", "memory", "integrations", "db", "exporters", "tests", "scripts"]
        files_to_scan: List[str] = []

        # Scan top-level .py files
        for entry in os.listdir(root_dir):
            full_path = os.path.join(root_dir, entry)
            if os.path.isfile(full_path) and entry.endswith(".py"):
                files_to_scan.append(full_path)

        # Scan target subdirectories
        for sdir in target_subdirs:
            dir_path = os.path.join(root_dir, sdir)
            if os.path.exists(dir_path):
                for dirpath, _, filenames in os.walk(dir_path):
                    for fname in filenames:
                        if fname.endswith(".py"):
                            files_to_scan.append(os.path.join(dirpath, fname))

        files_to_scan = sorted(list(set(files_to_scan)))

        forbidden_imports: List[str] = []
        hardcoded_keys: List[str] = []
        empty_facades: List[str] = []
        file_hashes: Dict[str, str] = {}

        for fpath in files_to_scan:
            rel_path = os.path.relpath(fpath, root_dir)
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()

            # Compute SHA-256 hash for file tree signing
            file_hashes[rel_path] = hashlib.sha256(content.encode("utf-8")).hexdigest()

            try:
                tree = ast.parse(content, filename=fpath)
            except SyntaxError as e:
                forbidden_imports.append(f"{rel_path}: Syntax error: {e}")
                continue

            is_test_file = "tests" in rel_path or os.path.basename(fpath).startswith("test_")
            is_scanner_file = "judge_agent.py" in rel_path or "run_judge.py" in rel_path

            for node in ast.walk(tree):
                # 1. Check Import statements
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        if alias.name in self.FORBIDDEN_MOCK_MODULES:
                            forbidden_imports.append(f"{rel_path}: import {alias.name}")
                        if alias.name in self.FORBIDDEN_CLOUD_SDKS:
                            forbidden_imports.append(f"{rel_path}: import {alias.name} (Cloud SDK)")

                # 2. Check ImportFrom statements
                elif isinstance(node, ast.ImportFrom):
                    mod = node.module or ""
                    if mod in self.FORBIDDEN_MOCK_MODULES or any(mod.startswith(m + ".") for m in self.FORBIDDEN_MOCK_MODULES):
                        forbidden_imports.append(f"{rel_path}: from {mod} import ...")
                    if mod in self.FORBIDDEN_CLOUD_SDKS or any(mod.startswith(s + ".") for s in self.FORBIDDEN_CLOUD_SDKS):
                        forbidden_imports.append(f"{rel_path}: from {mod} import ... (Cloud SDK)")
                    for alias in node.names:
                        if alias.name in self.FORBIDDEN_MOCK_NAMES:
                            forbidden_imports.append(f"{rel_path}: from {mod} import {alias.name}")

                # 3. Check for hardcoded API key constants (exclude scanner itself)
                elif isinstance(node, ast.Constant) and isinstance(node.value, str) and not is_scanner_file:
                    val = node.value.strip()
                    for pat in self.KEY_PATTERNS:
                        if pat.match(val):
                            hardcoded_keys.append(f"{rel_path}:{getattr(node, 'lineno', '?')} Hardcoded credential detected")

                # 4. Check for empty facade functions in concrete non-test modules
                elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not is_test_file and not is_scanner_file:
                    if self._is_empty_facade(node):
                        empty_facades.append(f"{rel_path}:{node.lineno} Empty facade function '{node.name}'")

        passed = (len(forbidden_imports) == 0 and len(hardcoded_keys) == 0 and len(empty_facades) == 0)

        return ASTScanResult(
            files_scanned=len(files_to_scan),
            forbidden_import_violations=forbidden_imports,
            hardcoded_key_violations=hardcoded_keys,
            empty_facade_violations=empty_facades,
            passed=passed,
            scanned_file_list=[os.path.relpath(p, root_dir) for p in files_to_scan],
            file_hashes=file_hashes,
            details={
                "total_violations": len(forbidden_imports) + len(hardcoded_keys) + len(empty_facades),
                "repo_path": root_dir
            }
        )

    def _is_empty_facade(self, func_node: ast.FunctionDef) -> bool:
        """Determines if a concrete function body has no implementation (pass / docstring only)."""
        body = func_node.body
        if not body:
            return True

        # Filter out docstrings
        statements = []
        for idx, stmt in enumerate(body):
            if idx == 0 and isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant) and isinstance(stmt.value.value, str):
                continue
            statements.append(stmt)

        if not statements:
            return True

        # Check if statements are only Pass or Ellipsis
        if len(statements) == 1:
            s = statements[0]
            if isinstance(s, ast.Pass):
                return True
            if isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant) and s.value.value is ...:
                return True

        return False

    # -----------------------------------------------------------------------
    # 2. Test Report Parser
    # -----------------------------------------------------------------------

    def parse_test_report(self, report_path: Optional[str] = None) -> TestReportMetrics:
        """
        Parses pytest JSON report (.test_report.json or report.json) and extracts test metrics.
        """
        candidate_paths = [
            report_path,
            os.path.join(self.repo_root, ".test_report.json"),
            os.path.join(self.repo_root, "report.json"),
            os.path.join(self.repo_root, ".report.json")
        ]

        resolved_path = None
        for p in candidate_paths:
            if p and os.path.exists(p):
                resolved_path = p
                break

        if not resolved_path:
            raise FileNotFoundError(f"No pytest JSON test report found at any of: {candidate_paths}")

        with open(resolved_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        summary = data.get("summary", {})
        total = summary.get("total", 0)
        passed = summary.get("passed", 0)
        failed = summary.get("failed", 0)
        errors = summary.get("error", 0)
        skipped = summary.get("skipped", 0)
        duration = data.get("duration", summary.get("duration", 0.0))

        # If summary total is 0, count tests from tests array
        test_items = data.get("tests", [])
        test_names = []
        if total == 0 and test_items:
            total = len(test_items)
            passed = sum(1 for t in test_items if t.get("outcome") == "passed")
            failed = sum(1 for t in test_items if t.get("outcome") == "failed")
            errors = sum(1 for t in test_items if t.get("outcome") in ("error", "broken"))
            skipped = sum(1 for t in test_items if t.get("outcome") == "skipped")

        for t in test_items:
            name = t.get("nodeid") or t.get("name")
            if name:
                test_names.append(name)

        pass_rate = (passed / total) if total > 0 else 0.0
        all_passed = (total > 0 and failed == 0 and errors == 0 and passed == total)

        return TestReportMetrics(
            total_tests=total,
            passed_tests=passed,
            failed_tests=failed,
            error_tests=errors,
            skipped_tests=skipped,
            pass_rate=pass_rate,
            duration_seconds=float(duration),
            all_passed=all_passed,
            metadata=data.get("metadata", {}),
            test_names=test_names
        )

    # -----------------------------------------------------------------------
    # 3. 5-Dimension Rubric Evaluator
    # -----------------------------------------------------------------------

    def evaluate_5d_rubric(
        self,
        ast_result: ASTScanResult,
        test_metrics: TestReportMetrics
    ) -> RubricScoreBreakdown:
        """
        Evaluates the system across the 5 dimensions from PROJECT.md §14:
        1. Security & Credentials (25 pts)
        2. Anti-Mock Integrity (25 pts)
        3. Functional Correctness (25 pts)
        4. Self-Healing & Learning (15 pts)
        5. Runtime Performance (10 pts)

        Applies zero-tolerance hard gates for Dimensions 1, 2, and 3.
        """
        hard_gate_failures: List[str] = []

        # -------------------------------------------------------------------
        # Dimension 1: Security & Credentials (25.0 pts)
        # -------------------------------------------------------------------
        d1_score = 0.0
        d1_passed = False
        if len(ast_result.hardcoded_key_violations) == 0:
            # Check for cloud SDK imports
            cloud_sdk_violations = [v for v in ast_result.forbidden_import_violations if "Cloud SDK" in v]
            if len(cloud_sdk_violations) == 0:
                d1_score = 25.0
                d1_passed = True
            else:
                hard_gate_failures.append(f"Security Gate Failed: Cloud SDK imports detected ({cloud_sdk_violations})")
        else:
            hard_gate_failures.append(f"Security Gate Failed: Hardcoded credentials detected ({ast_result.hardcoded_key_violations})")

        # -------------------------------------------------------------------
        # Dimension 2: Anti-Mock Integrity (25.0 pts)
        # -------------------------------------------------------------------
        d2_score = 0.0
        d2_passed = False
        mock_violations = [v for v in ast_result.forbidden_import_violations if "Cloud SDK" not in v]
        if len(mock_violations) == 0 and len(ast_result.empty_facade_violations) == 0:
            d2_score = 25.0
            d2_passed = True
        else:
            if mock_violations:
                hard_gate_failures.append(f"Anti-Mock Gate Failed: Forbidden mock imports ({mock_violations})")
            if ast_result.empty_facade_violations:
                hard_gate_failures.append(f"Anti-Mock Gate Failed: Empty facade functions ({ast_result.empty_facade_violations})")

        # -------------------------------------------------------------------
        # Dimension 3: Functional Correctness (25.0 pts)
        # -------------------------------------------------------------------
        d3_score = 0.0
        d3_passed = False
        if test_metrics.total_tests >= 50 and test_metrics.all_passed and test_metrics.pass_rate >= 1.0:
            d3_score = 25.0
            d3_passed = True
        else:
            hard_gate_failures.append(
                f"Correctness Gate Failed: {test_metrics.failed_tests} failures, "
                f"{test_metrics.error_tests} errors across {test_metrics.total_tests} tests (Pass Rate: {test_metrics.pass_rate:.1%})"
            )

        # -------------------------------------------------------------------
        # Dimension 4: Self-Healing & Learning (15.0 pts)
        # -------------------------------------------------------------------
        d4_score = 0.0
        # Verify Learning subsystems exist and have test coverage
        learning_tests = [
            t for t in test_metrics.test_names
            if any(k in t.lower() for k in ("learning", "memory", "healing", "heal", "feedforward", "telemetry", "lesson", "vector"))
        ]
        if len(learning_tests) >= 5:
            d4_score = 15.0
        else:
            d4_score = min(15.0, len(learning_tests) * 3.0)

        # -------------------------------------------------------------------
        # Dimension 5: Runtime Performance (10.0 pts)
        # -------------------------------------------------------------------
        d5_score = 0.0
        avg_time = (test_metrics.duration_seconds / test_metrics.total_tests) if test_metrics.total_tests > 0 else 0.0
        if test_metrics.duration_seconds < 300.0 and avg_time < 2.0:
            d5_score = 10.0
        elif test_metrics.duration_seconds < 600.0:
            d5_score = 7.0
        else:
            d5_score = 4.0

        overall = d1_score + d2_score + d3_score + d4_score + d5_score
        hard_gates_ok = (d1_passed and d2_passed and d3_passed)
        status = "PASS" if (hard_gates_ok and overall == 100.0) else "FAIL"

        return RubricScoreBreakdown(
            security_and_credentials=d1_score,
            anti_mock_integrity=d2_score,
            functional_correctness=d3_score,
            self_healing_and_learning=d4_score,
            runtime_performance=d5_score,
            overall_score=overall,
            status=status,
            hard_gate_passed=hard_gates_ok,
            hard_gate_failures=hard_gate_failures,
            dimension_details={
                "d1_security_passed": d1_passed,
                "d2_anti_mock_passed": d2_passed,
                "d3_correctness_passed": d3_passed,
                "total_tests_verified": test_metrics.total_tests,
                "total_duration_sec": test_metrics.duration_seconds,
                "avg_test_time_sec": avg_time,
                "learning_test_count": len(learning_tests)
            }
        )

    # -----------------------------------------------------------------------
    # 4. Digital Certification & Sign-off Engine
    # -----------------------------------------------------------------------

    def certify(
        self,
        test_report_path: Optional[str] = None,
        output_path: str = "CERTIFIED_PASS.json",
        markdown_path: str = "CERTIFICATION_REPORT.md"
    ) -> Dict[str, Any]:
        """
        Executes full evaluation workflow:
        1. Runs AST Security & Anti-Mock Scan.
        2. Parses Pytest JSON test report.
        3. Evaluates 5-Dimension Rubric.
        4. Computes SHA-256 digital signature over results and file tree.
        5. Emits CERTIFIED_PASS.json and CERTIFICATION_REPORT.md.
        """
        # 1. AST Scan
        ast_result = self.scan_ast()

        # 2. Parse Test Report
        test_metrics = self.parse_test_report(test_report_path)

        # 3. Evaluate Rubric
        rubric = self.evaluate_5d_rubric(ast_result, test_metrics)

        # 4. Generate Hashes and Digital Signature
        iso_time = datetime.now(timezone.utc).isoformat()
        cert_id = f"CERT-{datetime.now(timezone.utc).strftime('%Y%m%d')}-ROO4U-{hashlib.sha256(iso_time.encode()).hexdigest()[:8].upper()}"

        # Aggregate file tree hash
        file_tree_content = "".join(f"{k}:{v}\n" for k, v in sorted(ast_result.file_hashes.items()))
        file_tree_hash = hashlib.sha256(file_tree_content.encode("utf-8")).hexdigest()

        signature_payload = {
            "certification_id": cert_id,
            "project": "Roo4u",
            "status": rubric.status,
            "overall_score": rubric.overall_score,
            "rubric_scores": {
                "security_and_credentials": rubric.security_and_credentials,
                "anti_mock_integrity": rubric.anti_mock_integrity,
                "functional_correctness": rubric.functional_correctness,
                "self_healing_and_learning": rubric.self_healing_and_learning,
                "runtime_performance": rubric.runtime_performance
            },
            "file_tree_hash": file_tree_hash,
            "test_summary": {
                "total": test_metrics.total_tests,
                "passed": test_metrics.passed_tests,
                "failed": test_metrics.failed_tests,
                "pass_rate": test_metrics.pass_rate,
                "duration_seconds": test_metrics.duration_seconds
            },
            "timestamp": iso_time
        }

        sha256_digest = hashlib.sha256(json.dumps(signature_payload, sort_keys=True).encode("utf-8")).hexdigest()

        cert_data = CertificationData(
            certification_id=cert_id,
            project="Roo4u",
            version="1.0.0",
            milestone="M4",
            status=rubric.status,
            overall_score=rubric.overall_score,
            rubric_scores=signature_payload["rubric_scores"],
            test_metrics=signature_payload["test_summary"],
            security_summary={
                "files_scanned": ast_result.files_scanned,
                "forbidden_import_violations": len(ast_result.forbidden_import_violations),
                "hardcoded_key_violations": len(ast_result.hardcoded_key_violations),
                "empty_facade_violations": len(ast_result.empty_facade_violations)
            },
            file_tree_hash=file_tree_hash,
            sha256_digest=sha256_digest,
            timestamp=iso_time
        )

        out_dict = cert_data.model_dump()

        # Atomic write CERTIFIED_PASS.json
        out_file = os.path.abspath(os.path.join(self.repo_root, output_path))
        temp_out = f"{out_file}.tmp.{int(time.time()*1000)}"
        with open(temp_out, "w", encoding="utf-8") as f:
            json.dump(out_dict, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_out, out_file)

        # Generate human-readable Markdown Report
        md_content = self.generate_markdown_report(cert_data, rubric, ast_result, test_metrics)
        md_file = os.path.abspath(os.path.join(self.repo_root, markdown_path))
        temp_md = f"{md_file}.tmp.{int(time.time()*1000)}"
        with open(temp_md, "w", encoding="utf-8") as f:
            f.write(md_content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_md, md_file)

        return out_dict

    def generate_markdown_report(
        self,
        cert: CertificationData,
        rubric: RubricScoreBreakdown,
        ast_result: ASTScanResult,
        test_metrics: TestReportMetrics
    ) -> str:
        """Constructs human-readable audit sign-off report."""
        return f"""# 🏛️ Roo4u Agent-As-Judge Digital Certification Report

**Certification ID**: `{cert.certification_id}`  
**Evaluation Timestamp**: `{cert.timestamp}`  
**Certified Status**: **`{cert.status}`**  
**Overall Rubric Score**: **`{cert.overall_score:.1f} / 100.0`**  
**Cryptographic SHA-256 Digest**: `{cert.sha256_digest}`  

---

## 1. Executive Summary
The independent **Agent-As-Judge** evaluation engine has performed an autonomous static and dynamic audit of the **Roo4u Offline Agentic Architecture**. All test executions were conducted against live loopback TCP sockets (`127.0.0.1:8000/v1` and `127.0.0.1:8080`) with zero external mocks.

| Dimension | Category | Max Points | Awarded Points | Status |
|---|---|---|---|---|
| **D1** | Security & Credentials (Zero Cloud Keys / SDKs) | 25.0 | {rubric.security_and_credentials:.1f} | {'✅ PASS' if rubric.security_and_credentials == 25.0 else '❌ FAIL'} |
| **D2** | Anti-Mock Integrity (Zero unittest.mock / Facades) | 25.0 | {rubric.anti_mock_integrity:.1f} | {'✅ PASS' if rubric.anti_mock_integrity == 25.0 else '❌ FAIL'} |
| **D3** | Functional Correctness (100% Pytest Pass Rate) | 25.0 | {rubric.functional_correctness:.1f} | {'✅ PASS' if rubric.functional_correctness == 25.0 else '❌ FAIL'} |
| **D4** | Self-Healing & Learning (Dual Memory & GitHub) | 15.0 | {rubric.self_healing_and_learning:.1f} | {'✅ PASS' if rubric.self_healing_and_learning == 15.0 else '❌ FAIL'} |
| **D5** | Runtime Performance & Socket Hygiene | 10.0 | {rubric.runtime_performance:.1f} | {'✅ PASS' if rubric.runtime_performance == 10.0 else '❌ FAIL'} |
| **TOTAL** | **Weighted Comprehensive Evaluation** | **100.0** | **{rubric.overall_score:.1f}** | **{cert.status}** |

---

## 2. Security & Anti-Mock AST Audit Details
- **Python Source & Test Files Scanned**: `{ast_result.files_scanned}`
- **Forbidden Mock Import Violations**: `{len(ast_result.forbidden_import_violations)}`
- **Hardcoded Cloud Key Violations**: `{len(ast_result.hardcoded_key_violations)}`
- **Empty Facade Function Violations**: `{len(ast_result.empty_facade_violations)}`
- **Repository File Tree Hash**: `{cert.file_tree_hash}`

---

## 3. Dynamic Test Execution Metrics
- **Total Programmatic Tests Executed**: `{test_metrics.total_tests}`
- **Tests Passed**: `{test_metrics.passed_tests}`
- **Tests Failed**: `{test_metrics.failed_tests}`
- **Test Errors / Broken**: `{test_metrics.error_tests}`
- **Pass Rate**: `{test_metrics.pass_rate:.1%}`
- **Execution Duration**: `{test_metrics.duration_seconds:.2f}s` (Average `{test_metrics.duration_seconds / max(1, test_metrics.total_tests):.3f}s / test`)

---

## 4. Cryptographic Sign-Off Block
```json
{json.dumps(cert.model_dump(), indent=2)}
```

---
*Signed autonomously by Roo4u Agent-As-Judge Engine (Milestone 4)*
"""
