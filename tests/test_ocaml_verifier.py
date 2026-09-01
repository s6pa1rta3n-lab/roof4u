"""
tests/test_ocaml_verifier.py

Zero-mock automated unit and integration tests for OCaml mathematical lead verification.
Validates end-to-end IPC execution, invariant enforcement, scoring monotonicity, and proof generation.
"""

import pytest
from integrations.ocaml_verifier import OCamlLeadVerifier, OCamlVerificationResult


@pytest.fixture
def verifier():
    return OCamlLeadVerifier()


def test_ocaml_binary_availability(verifier):
    assert verifier.is_binary_available() is True


def test_ocaml_verification_prime_victorian(verifier):
    lead = {
        "address": "2828 Vallejo St",
        "zip_code": "94123",
        "property_type": "Single-Family",
        "roof_type": "Victorian",
        "estimated_value": 4500000.0,
        "is_hoa": False,
        "is_rental": False,
        "roof_age_years": 25.0
    }
    result = verifier.verify_lead_dict(lead)
    assert result.is_qualified is True
    assert result.status == "QUALIFIED"
    assert result.actionability_score >= 80.0
    assert result.proof_id is not None
    assert result.proof_id.startswith("PROOF-OCAML-")
    assert len(result.invariants_passed) == 4
    assert len(result.failed_invariants) == 0


def test_ocaml_verification_flat_roof_multi_unit(verifier):
    lead = {
        "address": "1520 California St",
        "zip_code": "94109",
        "property_type": "Multi-Unit",
        "roof_type": "Flat",
        "estimated_value": 2800000.0,
        "is_hoa": False,
        "is_rental": False,
        "roof_age_years": 18.0
    }
    result = verifier.verify_lead_dict(lead)
    assert result.is_qualified is True
    assert result.status == "QUALIFIED"
    assert result.actionability_score >= 60.0
    assert any("Flat" in inv or "Physical" in inv for inv in result.invariants_passed)


def test_ocaml_disqualification_hoa_violation(verifier):
    lead = {
        "address": "100 Van Ness Ave #1204",
        "zip_code": "94102",
        "property_type": "Single-Family",
        "roof_type": "Victorian",
        "estimated_value": 3000000.0,
        "is_hoa": True,
        "is_rental": False,
        "roof_age_years": 20.0
    }
    result = verifier.verify_lead_dict(lead)
    assert result.is_qualified is False
    assert result.status == "DISQUALIFIED"
    assert any("Economic Viability" in f.get("invariant", "") for f in result.failed_invariants)


def test_ocaml_disqualification_young_roof(verifier):
    lead = {
        "address": "3344 Clay St",
        "zip_code": "94118",
        "property_type": "Single-Family",
        "roof_type": "Victorian",
        "estimated_value": 3500000.0,
        "is_hoa": False,
        "is_rental": False,
        "roof_age_years": 8.0
    }
    result = verifier.verify_lead_dict(lead)
    assert result.is_qualified is False
    assert result.status == "DISQUALIFIED"
    assert any("Temporal Degradation" in f.get("invariant", "") for f in result.failed_invariants)


def test_ocaml_disqualification_ineligible_roof_type(verifier):
    lead = {
        "address": "555 Sunset Blvd",
        "zip_code": "94122",
        "property_type": "Single-Family",
        "roof_type": "Gable",
        "estimated_value": 2000000.0,
        "is_hoa": False,
        "is_rental": False,
        "roof_age_years": 22.0
    }
    result = verifier.verify_lead_dict(lead)
    assert result.is_qualified is False
    assert result.status == "DISQUALIFIED"
    assert any("Physical Eligibility" in f.get("invariant", "") for f in result.failed_invariants)


def test_ocaml_disqualification_recent_permit_conflict(verifier):
    lead = {
        "address": "777 Presidio Ave",
        "zip_code": "94115",
        "property_type": "Single-Family",
        "roof_type": "Victorian",
        "estimated_value": 3000000.0,
        "is_hoa": False,
        "is_rental": False,
        "roof_age_years": 20.0,
        "permits": [
            {
                "permit_number": "PERMIT-2023-099",
                "date_filed": "2023-04-10",
                "date_issued": "2023-05-12",
                "description": "Full roof replacement and tear-off",
                "is_roof_replacement": True,
                "cost": 45000.0
            }
        ]
    }
    result = verifier.verify_lead_dict(lead)
    assert result.is_qualified is False
    assert result.status == "DISQUALIFIED"
    assert any("Permit Recency Non-Conflict" in f.get("invariant", "") for f in result.failed_invariants)
