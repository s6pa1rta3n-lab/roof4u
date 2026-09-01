"""
===============================================================================
DEPRECATION NOTICE:
This Python CSV exporter is DEPRECATED as part of the pure OCaml rewrite (Milestone 4).
All lead export and DDE sanitization logic is now natively implemented in:
  - ocaml/lib/csv_exporter.mli
  - ocaml/lib/csv_exporter.ml
Please use the OCaml CLI binary:
  ./ocaml/_build/default/bin/main.exe --run --csv <path>
===============================================================================
"""

import csv
import os
import sys
import warnings
from db.database import init_db, get_session, Lead

# Issue deprecation warning on import
warnings.warn(
    "exporters/csv_exporter.py is deprecated in favor of pure OCaml implementation (ocaml/lib/csv_exporter.ml).",
    DeprecationWarning,
    stacklevel=2
)


def export_to_csv(db_path="sqlite:///leads.db", output_file="validated_leads.csv"):
    """
    Deprecated Python export wrapper.
    Exports VALIDATED and ENRICHED leads to RFC 4180 CSV.
    """
    print("[DEPRECATED] exporters.csv_exporter.export_to_csv() is deprecated. Use ocaml/lib/csv_exporter.ml instead.")
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
    print("=" * 70)
    print(" DEPRECATION WARNING: exporters/csv_exporter.py is deprecated.")
    print(" Please use pure OCaml binary: ./ocaml/_build/default/bin/main.exe")
    print("=" * 70)
    export_to_csv()
