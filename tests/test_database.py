"""
tests/test_database.py

Component test suite for db/database.py.
Validates SQLite schema creation, full CRUD operations, ORM field serialization,
column constraints, default values, state transitions, filtering, and transaction integrity.
100% Mock-Free.
"""

import os
import tempfile
from datetime import datetime, date
import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

from db.database import Base, Lead, get_engine, init_db, get_session


# ============================================================================
# 1. DATABASE INITIALIZATION & SESSION LIFECYCLE
# ============================================================================

class TestDatabaseInitialization:
    """Validates engine instantiation, schema creation, and session lifecycle."""

    def test_init_db_in_memory(self):
        engine = init_db("sqlite:///:memory:")
        assert engine is not None
        # Verify table exists in metadata
        assert "leads" in Base.metadata.tables
        session = get_session(engine)
        count = session.query(Lead).count()
        assert count == 0
        session.close()
        engine.dispose()

    def test_init_db_file_path(self, tmp_path):
        db_file = tmp_path / "custom_leads.db"
        db_uri = f"sqlite:///{db_file}"
        engine = init_db(db_uri)
        assert os.path.exists(db_file)
        session = get_session(engine)
        lead = Lead(address="100 Test St", zip_code="94115")
        session.add(lead)
        session.commit()
        assert session.query(Lead).count() == 1
        session.close()
        engine.dispose()

    def test_get_session_lifecycle(self):
        engine = init_db("sqlite:///:memory:")
        session = get_session(engine)
        assert session.is_active
        session.close()
        engine.dispose()

    def test_get_engine_helper(self):
        engine = get_engine("sqlite:///:memory:")
        assert engine is not None
        engine.dispose()


# ============================================================================
# 2. LEAD CRUD OPERATIONS
# ============================================================================

class TestLeadCRUDOperations:
    """Validates full Create, Read, Update, Delete operations and field mappings."""

    def test_create_and_read_lead(self, db_session):
        lead = Lead(
            address="2223 Pacific Ave, San Francisco, CA 94115",
            zip_code="94115",
            property_type="Single-Family",
            roof_type="Victorian",
            estimated_value=4370000.0,
            owner_name="PACIFIC HERITAGE TRUST",
            is_hoa=False,
            is_rental=False,
            apn="0582-014",
            last_roof_permit_date=date(2008, 5, 14),
            roof_age_years=18.0,
            phone_number="415-555-0199",
            status="VALIDATED"
        )
        db_session.add(lead)
        db_session.commit()
        assert lead.id is not None

        retrieved = db_session.query(Lead).filter_by(address="2223 Pacific Ave, San Francisco, CA 94115").first()
        assert retrieved is not None
        assert retrieved.zip_code == "94115"
        assert retrieved.property_type == "Single-Family"
        assert retrieved.roof_type == "Victorian"
        assert retrieved.estimated_value == 4370000.0
        assert retrieved.owner_name == "PACIFIC HERITAGE TRUST"
        assert retrieved.is_hoa is False
        assert retrieved.is_rental is False
        assert retrieved.apn == "0582-014"
        assert retrieved.last_roof_permit_date == date(2008, 5, 14)
        assert retrieved.roof_age_years == 18.0
        assert retrieved.phone_number == "415-555-0199"
        assert retrieved.status == "VALIDATED"

    def test_update_lead_fields(self, db_session):
        lead = Lead(address="100 Broadway", zip_code="94115", status="DISCOVERED")
        db_session.add(lead)
        db_session.commit()

        lead.apn = "1234-567"
        lead.owner_name = "BROADWAY HOLDINGS LLC"
        lead.roof_age_years = 22.5
        lead.status = "VALIDATED"
        db_session.commit()

        updated = db_session.query(Lead).filter_by(id=lead.id).first()
        assert updated.apn == "1234-567"
        assert updated.owner_name == "BROADWAY HOLDINGS LLC"
        assert updated.roof_age_years == 22.5
        assert updated.status == "VALIDATED"

    def test_delete_lead(self, db_session):
        lead = Lead(address="200 Delete Me Way", zip_code="94115")
        db_session.add(lead)
        db_session.commit()
        lead_id = lead.id

        db_session.delete(lead)
        db_session.commit()

        assert db_session.query(Lead).filter_by(id=lead_id).first() is None

    def test_lead_float_precision(self, db_session):
        lead = Lead(
            address="300 Precision Blvd",
            zip_code="94115",
            estimated_value=14250000.75,
            roof_age_years=18.5
        )
        db_session.add(lead)
        db_session.commit()

        retrieved = db_session.query(Lead).filter_by(address="300 Precision Blvd").first()
        assert retrieved.estimated_value == 14250000.75
        assert retrieved.roof_age_years == 18.5

    def test_lead_date_storage(self, db_session):
        permit_d = date(2012, 4, 15)
        lead = Lead(
            address="400 Date St",
            zip_code="94115",
            last_roof_permit_date=permit_d
        )
        db_session.add(lead)
        db_session.commit()

        retrieved = db_session.query(Lead).filter_by(address="400 Date St").first()
        assert retrieved.last_roof_permit_date == permit_d
        assert isinstance(retrieved.last_roof_permit_date, date)


# ============================================================================
# 3. DATABASE CONSTRAINTS & DEFAULTS
# ============================================================================

class TestDatabaseConstraintsAndDefaults:
    """Validates column constraints (NOT NULL, UNIQUE) and default value population."""

    def test_unique_address_constraint(self, db_session):
        lead1 = Lead(address="500 Unique Ave", zip_code="94115")
        db_session.add(lead1)
        db_session.commit()

        lead2 = Lead(address="500 Unique Ave", zip_code="94115")
        db_session.add(lead2)
        with pytest.raises(IntegrityError):
            db_session.commit()
        db_session.rollback()

    def test_nullable_address_constraint(self, db_session):
        lead = Lead(address=None, zip_code="94115")
        db_session.add(lead)
        with pytest.raises(IntegrityError):
            db_session.commit()
        db_session.rollback()

    def test_nullable_zip_constraint(self, db_session):
        lead = Lead(address="600 No Zip Way", zip_code=None)
        db_session.add(lead)
        with pytest.raises(IntegrityError):
            db_session.commit()
        db_session.rollback()

    def test_default_status_discovered(self, db_session):
        lead = Lead(address="700 Default Status Ln", zip_code="94115")
        db_session.add(lead)
        db_session.commit()
        assert lead.status == "DISCOVERED"

    def test_default_boolean_flags(self, db_session):
        lead = Lead(address="800 Default Flags Ct", zip_code="94115")
        db_session.add(lead)
        db_session.commit()
        assert lead.is_hoa is False
        assert lead.is_rental is False

    def test_default_created_at_timestamp(self, db_session):
        lead = Lead(address="900 Timestamp Pl", zip_code="94115")
        db_session.add(lead)
        db_session.commit()
        assert lead.created_at is not None


# ============================================================================
# 4. STATE MACHINE & FILTERING
# ============================================================================

class TestLeadStateMachineAndFiltering:
    """Validates state transitions and status query filtering."""

    def test_state_transition_lifecycle(self, db_session):
        lead = Lead(address="1000 Transition St", zip_code="94115", status="DISCOVERED")
        db_session.add(lead)
        db_session.commit()
        assert lead.status == "DISCOVERED"

        lead.status = "VALIDATED"
        db_session.commit()
        assert db_session.query(Lead).filter_by(id=lead.id).first().status == "VALIDATED"

        lead.status = "ENRICHED"
        db_session.commit()
        assert db_session.query(Lead).filter_by(id=lead.id).first().status == "ENRICHED"

        lead.status = "DISCARDED"
        db_session.commit()
        assert db_session.query(Lead).filter_by(id=lead.id).first().status == "DISCARDED"

    def test_query_filter_by_status(self, db_session):
        leads = [
            Lead(address="1001 A St", zip_code="94115", status="DISCOVERED"),
            Lead(address="1002 B St", zip_code="94115", status="DISCOVERED"),
            Lead(address="1003 C St", zip_code="94115", status="VALIDATED"),
            Lead(address="1004 D St", zip_code="94115", status="VALIDATED"),
            Lead(address="1005 E St", zip_code="94115", status="VALIDATED"),
            Lead(address="1006 F St", zip_code="94115", status="ENRICHED"),
            Lead(address="1007 G St", zip_code="94115", status="DISCARDED"),
        ]
        db_session.add_all(leads)
        db_session.commit()

        assert db_session.query(Lead).filter_by(status="DISCOVERED").count() == 2
        assert db_session.query(Lead).filter_by(status="VALIDATED").count() == 3
        assert db_session.query(Lead).filter_by(status="ENRICHED").count() == 1
        assert db_session.query(Lead).filter_by(status="DISCARDED").count() == 1

    def test_filter_validated_and_enriched(self, db_session):
        leads = [
            Lead(address="2001 Disc St", zip_code="94115", status="DISCOVERED"),
            Lead(address="2002 Val St", zip_code="94115", status="VALIDATED"),
            Lead(address="2003 Enr St", zip_code="94115", status="ENRICHED"),
            Lead(address="2004 Disc2 St", zip_code="94115", status="DISCARDED"),
        ]
        db_session.add_all(leads)
        db_session.commit()

        qualified = db_session.query(Lead).filter(Lead.status.in_(["VALIDATED", "ENRICHED"])).all()
        assert len(qualified) == 2
        addrs = [q.address for q in qualified]
        assert "2002 Val St" in addrs
        assert "2003 Enr St" in addrs


# ============================================================================
# 5. TRANSACTIONS & EDGE CASES
# ============================================================================

class TestDatabaseTransactionsAndEdgeCases:
    """Validates transactional rollbacks, edge cases, SQL injection resistance, and bulk data."""

    def test_transaction_rollback(self, db_session):
        lead1 = Lead(address="3001 Good St", zip_code="94115")
        db_session.add(lead1)
        db_session.flush()

        lead2 = Lead(address="3001 Good St", zip_code="94115")  # Duplicate
        db_session.add(lead2)
        with pytest.raises(IntegrityError):
            db_session.flush()

        db_session.rollback()
        assert db_session.query(Lead).filter_by(address="3001 Good St").first() is None

    def test_special_characters_address(self, db_session):
        special_addrs = [
            "123 O'Connor St #4-B, San Francisco, CA",
            '456 "Quote" Way, Suite 100',
            "789 <script>alert(1)</script> Ave",
            "1011 Normal St; DROP TABLE leads; --",
        ]
        for addr in special_addrs:
            lead = Lead(address=addr, zip_code="94115")
            db_session.add(lead)
        db_session.commit()

        for addr in special_addrs:
            found = db_session.query(Lead).filter_by(address=addr).first()
            assert found is not None
            assert found.address == addr

    def test_unicode_owner_names(self, db_session):
        unicode_names = [
            "José Ramón Peña & Sons LLC",
            "München Real Estate GmbH",
            "株式会社 東京リアルティ",
            "Александр Смирнов",
        ]
        for idx, name in enumerate(unicode_names):
            lead = Lead(address=f"400{idx} Unicode Way", zip_code="94115", owner_name=name)
            db_session.add(lead)
        db_session.commit()

        for idx, name in enumerate(unicode_names):
            found = db_session.query(Lead).filter_by(address=f"400{idx} Unicode Way").first()
            assert found.owner_name == name

    def test_large_number_of_leads(self, db_session):
        bulk_leads = [
            Lead(address=f"{i} Bulk Lane, San Francisco, CA", zip_code="94115", estimated_value=100000.0 + i)
            for i in range(150)
        ]
        db_session.add_all(bulk_leads)
        db_session.commit()

        count = db_session.query(Lead).count()
        assert count == 150
