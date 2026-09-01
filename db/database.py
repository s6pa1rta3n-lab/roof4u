from sqlalchemy import create_engine, Column, Integer, String, Boolean, Date, Float
from sqlalchemy.orm import declarative_base, sessionmaker
from datetime import datetime
import os

Base = declarative_base()

class Lead(Base):
    __tablename__ = 'leads'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    # Discovery Phase
    address = Column(String, unique=True, nullable=False)
    zip_code = Column(String, nullable=False)
    property_type = Column(String)  # e.g., Single-Family
    roof_type = Column(String)      # Victorian, Flat
    estimated_value = Column(Float)
    
    # County & Assessor Phase
    owner_name = Column(String)
    is_hoa = Column(Boolean, default=False)
    is_rental = Column(Boolean, default=False)
    apn = Column(String)            # Assessor Parcel Number
    
    # Permit Phase
    last_roof_permit_date = Column(Date)
    roof_age_years = Column(Float)
    
    # Contact Phase
    phone_number = Column(String)
    
    # Tracking
    created_at = Column(Date, default=datetime.utcnow)
    status = Column(String, default="DISCOVERED") # DISCOVERED, VALIDATED, ENRICHED, DISCARDED

def get_engine(db_path="sqlite:///leads.db"):
    return create_engine(db_path)

def init_db(db_path="sqlite:///leads.db"):
    engine = get_engine(db_path)
    Base.metadata.create_all(engine)
    return engine

def get_session(engine):
    Session = sessionmaker(bind=engine)
    return Session()

if __name__ == "__main__":
    print("Initializing database...")
    init_db()
    print("Database initialized successfully.")
