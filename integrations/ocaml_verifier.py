"""
integrations/ocaml_verifier.py

Bridge interface executing the OCaml Mathematical Lead Verification Engine (roof_verif_cli).
Provides type-safe execution, JSON serialization, and proof parsing for Python pipeline agents.
"""

import json
import os
import subprocess
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any


@dataclass
class OCamlVerificationResult:
    is_qualified: bool
    status: str
    actionability_score: float
    score_components: Dict[str, float] = field(default_factory=dict)
    invariants_passed: List[str] = field(default_factory=list)
    failed_invariants: List[Dict[str, str]] = field(default_factory=list)
    proof_id: Optional[str] = None
    proof_digest: Optional[str] = None
    verification_timestamp: Optional[str] = None
    raw_output: str = ""


class OCamlLeadVerifier:
    """
    Executes the statically compiled OCaml mathematical verification engine
    to enforce algebraic invariants and calculate deterministic lead scores.
    """

    def __init__(self, binary_path: Optional[str] = None):
        if binary_path:
            self.binary_path = binary_path
        else:
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            self.binary_path = os.path.join(base_dir, "ocaml", "_build", "default", "bin", "main.exe")

    def is_binary_available(self) -> bool:
        """Checks if the compiled OCaml verification binary exists and is executable."""
        return os.path.isfile(self.binary_path) and os.access(self.binary_path, os.X_OK)

    def verify_lead_dict(self, lead_data: Dict[str, Any]) -> OCamlVerificationResult:
        """
        Executes mathematical verification on a dictionary representation of a lead.
        """
        json_payload = json.dumps(lead_data)
        return self.verify_json_string(json_payload)

    def verify_json_string(self, json_payload: str) -> OCamlVerificationResult:
        """
        Passes JSON payload to roof_verif_cli and parses the returned proof certificate.
        """
        if not self.is_binary_available():
            raise FileNotFoundError(f"OCaml verification binary not found at: {self.binary_path}")

        proc = subprocess.run(
            [self.binary_path, "--stdin"],
            input=json_payload,
            text=True,
            capture_output=True
        )

        stdout = proc.stdout.strip()
        stderr = proc.stderr.strip()

        if not stdout and stderr:
            raise RuntimeError(f"OCaml verification error: {stderr}")

        try:
            parsed = json.loads(stdout)
            verdict = parsed.get("verdict", {})
            status = verdict.get("status", "DISQUALIFIED")
            is_qualified = (status == "QUALIFIED")
            score = verdict.get("actionability_score", verdict.get("partial_score", 0.0))
            score_comp = verdict.get("score_components", {})
            invariants_passed = verdict.get("invariants_passed", [])
            failed_invariants = verdict.get("failed_invariants", [])
            proof_id = verdict.get("proof_id")
            proof_digest = parsed.get("proof_digest")
            ts = parsed.get("verification_timestamp")

            return OCamlVerificationResult(
                is_qualified=is_qualified,
                status=status,
                actionability_score=float(score),
                score_components=score_comp,
                invariants_passed=invariants_passed,
                failed_invariants=failed_invariants,
                proof_id=proof_id,
                proof_digest=proof_digest,
                verification_timestamp=ts,
                raw_output=stdout
            )
        except Exception as e:
            raise ValueError(f"Failed to parse OCaml verification output: {e}\nRaw output: {stdout}")
