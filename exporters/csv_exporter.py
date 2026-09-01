import csv
from db.database import init_db, get_session, Lead
import os

def export_to_csv(db_path="sqlite:///leads.db", output_file="validated_leads.csv"):
    engine = init_db(db_path)
    session = get_session(engine)
    
    # We only want to export VALIDATED and ENRICHED leads
    leads = session.query(Lead).filter(Lead.status.in_(["VALIDATED", "ENRICHED"])).all()
    
    if not leads:
        print("No validated leads found to export.")
        return

    headers = [
        "Address", "Zip Code", "Property Type", "Roof Type", 
        "Assessed Value", "Owner Name", "APN", "Roof Age (Years)", 
        "Phone Number", "Status"
    ]
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        
        for lead in leads:
            writer.writerow([
                lead.address, lead.zip_code, lead.property_type, lead.roof_type,
                lead.estimated_value, lead.owner_name, lead.apn, lead.roof_age_years,
                lead.phone_number, lead.status
            ])
            
    print(f"Exported {len(leads)} leads to {output_file}")

if __name__ == "__main__":
    export_to_csv()
