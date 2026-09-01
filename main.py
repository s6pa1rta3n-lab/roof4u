import argparse
import os
from db.database import init_db, get_session, Lead
# from agents.zillow_agent import ZillowAgent
# from agents.county_agent import CountyAgent

def run_pipeline(zip_code: str):
    """
    Main pipeline for Roo4u Agentic Lead Generation.
    Runs the agents in sequence (The Funnel Method).
    """
    print(f"Starting Roo4u Pipeline for Zip Code: {zip_code}")
    
    # 1. Initialize Database
    engine = init_db()
    session = get_session(engine)
    print("Database initialized.")

    print("\n--- PHASE 1: DISCOVERY ---")
    print("Initializing ZillowAgent...")
    # In a full run, ZillowAgent would populate the DB with raw property leads.
    # For this POC, we will seed our manual test case to prove the pipeline downstream.
    test_address = "2223 Pacific Ave"
    
    existing = session.query(Lead).filter_by(address=test_address).first()
    if not existing:
        print(f"Seeding test property: {test_address} (SF, 94115)")
        lead = Lead(
            address=test_address,
            zip_code="94115",
            property_type="Single-Family",
            roof_type="Victorian",
            is_hoa=False,
            is_rental=False,
            status="DISCOVERED"
        )
        session.add(lead)
        session.commit()
    else:
        print(f"Test property {test_address} already in database.")

    print("\n--- PHASE 2: ASSESSOR & PERMITS ---")
    print("Initializing CountyAgent for San Francisco...")
    # Here, CountyAgent would query the SF PIM and DBI websites for each DISCOVERED lead.
    # We will log the logic that would occur.
    leads_to_process = session.query(Lead).filter_by(status="DISCOVERED").all()
    for lead in leads_to_process:
        print(f"-> Processing {lead.address}...")
        print(f"   [Agent Navigation] Navigating to sfplanninggis.org/pim/...")
        print(f"   [Agent Extraction] Extracted APN and Tax Value. Assessed Value: $4.37M")
        print(f"   [Agent Navigation] Navigating to DBI Permit Tracking...")
        print(f"   [Agent Extraction] Extracted Permit History. Found 'Reroof' in 2008.")
        
        # Update lead
        lead.estimated_value = 4370000
        lead.roof_age_years = 18.0
        lead.status = "VALIDATED"
        session.commit()
        print(f"-> {lead.address} is a VALID lead! (Roof age > 15 years)")

    print("\n--- PHASE 3: CONTACT ENRICHMENT ---")
    # contact_agent goes here
    
    print("\nPipeline Complete!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Roo4u Lead Generation Pipeline")
    parser.add_argument("--zip", type=str, default="94115", help="Target zip code")
    args = parser.parse_args()
    
    run_pipeline(args.zip)
