"""
tests/test_exporter.py

Component test suite for exporters/csv_exporter.py.
Validates CSV export filtering (only VALIDATED and ENRICHED leads), header compliance,
column mappings, NULL/None handling, RFC 4180 escaping, and Unicode support.
100% Mock-Free.
"""

import os
import csv
import tempfile
import pytest

from exporters.csv_exporter import export_to_csv
from db.database import init_db, get_session, Lead


# ============================================================================
# 1. CSV EXPORTER FILTERING & SCHEMA COMPLIANCE
# ============================================================================

class TestCSVExporterFilteringAndSchema:
    """Validates export filtering rules and exact CSV column schema."""

    def test_export_only_validated_enriched(self, tmp_path):
        db_file = tmp_path / "export_filter.db"
        csv_file = tmp_path / "output.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        leads = [
            Lead(address="101 Validated St", zip_code="94115", status="VALIDATED", estimated_value=1500000.0, roof_age_years=20.0),
            Lead(address="102 Enriched Ave", zip_code="94115", status="ENRICHED", estimated_value=2000000.0, roof_age_years=16.0),
            Lead(address="103 Discovered Rd", zip_code="94115", status="DISCOVERED", estimated_value=800000.0),
            Lead(address="104 Discarded Blvd", zip_code="94115", status="DISCARDED", estimated_value=300000.0),
        ]
        session.add_all(leads)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = list(csv.reader(f))

        # Header + 2 data rows
        assert len(reader) == 3
        headers = reader[0]
        assert "Address" in headers
        assert "Status" in headers

        addresses = [row[0] for row in reader[1:]]
        assert "101 Validated St" in addresses
        assert "102 Enriched Ave" in addresses
        assert "103 Discovered Rd" not in addresses
        assert "104 Discarded Blvd" not in addresses

    def test_csv_exact_headers(self, tmp_path):
        db_file = tmp_path / "headers.db"
        csv_file = tmp_path / "headers.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        session.add(Lead(address="100 Header St", zip_code="94115", status="VALIDATED"))
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = list(csv.reader(f))

        expected_headers = [
            "Address", "Zip Code", "Property Type", "Roof Type",
            "Assessed Value", "Owner Name", "APN", "Roof Age (Years)",
            "Phone Number", "Status"
        ]
        assert reader[0] == expected_headers

    def test_csv_column_mapping(self, tmp_path):
        db_file = tmp_path / "mapping.db"
        csv_file = tmp_path / "mapping.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        lead = Lead(
            address="2223 Pacific Ave, San Francisco, CA 94115",
            zip_code="94115",
            property_type="Single-Family",
            roof_type="Victorian",
            estimated_value=4370000.0,
            owner_name="PACIFIC HERITAGE TRUST",
            apn="0582-014",
            roof_age_years=18.0,
            phone_number="415-555-0199",
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            row = next(reader)

        assert row["Address"] == "2223 Pacific Ave, San Francisco, CA 94115"
        assert row["Zip Code"] == "94115"
        assert row["Property Type"] == "Single-Family"
        assert row["Roof Type"] == "Victorian"
        assert float(row["Assessed Value"]) == 4370000.0
        assert row["Owner Name"] == "PACIFIC HERITAGE TRUST"
        assert row["APN"] == "0582-014"
        assert float(row["Roof Age (Years)"]) == 18.0
        assert row["Phone Number"] == "415-555-0199"
        assert row["Status"] == "VALIDATED"

    def test_csv_empty_database(self, tmp_path):
        db_file = tmp_path / "empty.db"
        csv_file = tmp_path / "empty.csv"
        db_uri = f"sqlite:///{db_file}"

        init_db(db_uri)
        # Should not crash on empty database
        export_to_csv(db_path=db_uri, output_file=str(csv_file))

    def test_csv_no_qualified_leads(self, tmp_path):
        db_file = tmp_path / "unqualified.db"
        csv_file = tmp_path / "unqualified.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        session.add(Lead(address="100 Unqualified St", zip_code="94115", status="DISCOVERED"))
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))


# ============================================================================
# 2. DATA INTEGRITY & FORMATTING
# ============================================================================

class TestCSVDataIntegrityAndFormatting:
    """Validates escaping of special characters, Unicode encoding, and NULL handling."""

    def test_csv_special_characters_quotes(self, tmp_path):
        db_file = tmp_path / "special.db"
        csv_file = tmp_path / "special.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        lead = Lead(
            address='100 O\'Farrell St, Suite "A", San Francisco, CA',
            zip_code="94115",
            owner_name="Smith, Jones & Co., LLC",
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            row = next(reader)

        assert row["Address"] == '100 O\'Farrell St, Suite "A", San Francisco, CA'
        assert row["Owner Name"] == "Smith, Jones & Co., LLC"

    def test_csv_unicode_encoding(self, tmp_path):
        db_file = tmp_path / "unicode.db"
        csv_file = tmp_path / "unicode.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        lead = Lead(
            address="500 España Blvd",
            zip_code="94115",
            owner_name="José María González & Hijos",
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            row = next(reader)

        assert row["Address"] == "500 España Blvd"
        assert row["Owner Name"] == "José María González & Hijos"

    def test_csv_null_field_handling(self, tmp_path):
        db_file = tmp_path / "nulls.db"
        csv_file = tmp_path / "nulls.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        lead = Lead(
            address="600 Bare Lead Way",
            zip_code="94115",
            owner_name=None,
            apn=None,
            phone_number=None,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            row = next(reader)

        assert row["Owner Name"] == ""
        assert row["APN"] == ""
        assert row["Phone Number"] == ""

    def test_csv_float_values(self, tmp_path):
        db_file = tmp_path / "floats.db"
        csv_file = tmp_path / "floats.csv"
        db_uri = f"sqlite:///{db_file}"

        engine = init_db(db_uri)
        session = get_session(engine)
        lead = Lead(
            address="700 Exact Float Ave",
            zip_code="94115",
            estimated_value=1850000.50,
            roof_age_years=19.5,
            status="VALIDATED"
        )
        session.add(lead)
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            row = next(reader)

        assert float(row["Assessed Value"]) == 1850000.50
        assert float(row["Roof Age (Years)"]) == 19.5

    def test_csv_overwrite_existing_file(self, tmp_path):
        db_file = tmp_path / "overwrite.db"
        csv_file = tmp_path / "overwrite.csv"
        db_uri = f"sqlite:///{db_file}"

        # Write dummy content first
        with open(csv_file, "w", encoding="utf-8") as f:
            f.write("OLD_CONTENT_THAT_SHOULD_BE_OVERWRITTEN\n")

        engine = init_db(db_uri)
        session = get_session(engine)
        session.add(Lead(address="800 Fresh Lead St", zip_code="94115", status="VALIDATED"))
        session.commit()
        session.close()

        export_to_csv(db_path=db_uri, output_file=str(csv_file))

        with open(csv_file, "r", encoding="utf-8") as f:
            content = f.read()

        assert "OLD_CONTENT" not in content
        assert "800 Fresh Lead St" in content
