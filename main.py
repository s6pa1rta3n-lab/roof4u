"""
===============================================================================
DEPRECATION NOTICE:
main.py is DEPRECATED as part of the pure OCaml rewrite (Milestone 4).
The entire autonomous pipeline orchestration, invariant verification,
and lead acquisition engine is now natively implemented in pure OCaml:
  - ocaml/lib/pipeline.mli / ocaml/lib/pipeline.ml
  - ocaml/lib/datasf.ml
  - ocaml/lib/invariants.ml
  - ocaml/lib/scorer.ml
  - ocaml/lib/csv_exporter.ml
  - CLI binary: ./ocaml/_build/default/bin/main.exe --run
===============================================================================
"""

import argparse
import os
import subprocess
import sys
import warnings
from typing import Optional

warnings.warn(
    "main.py is deprecated in favor of pure OCaml binary (roof_pipeline --run).",
    DeprecationWarning,
    stacklevel=2
)

from db.database import init_db, get_session, Lead
from agents.zillow_agent import ZillowAgent
from agents.county_agent import CountyAgent
from agents.extractor import LocalLLMExtractor
from agents.learning_agent import LearningAgent
from memory.lesson_store import LessonStore
from memory.vector_store import LocalVectorStore
from integrations.github_client import GitHubIssueLogger


def run_pipeline(
    zip_code: str = "94115",
    target_address: Optional[str] = None,
    headless: bool = True,
    db_path: str = "sqlite:///leads.db",
    enable_learning: bool = True,
    enable_github_logging: bool = True,
    lessons_path: str = "lessons_learned.json",
    vector_db_path: str = "memory/vector_store.sqlite"
):
    """
    Main pipeline for Roo4u Agentic Lead Generation.
    Executes the Browsing Agents in sequence (Discovery -> Assessor/Permits -> Qualification)
    with feedforward self-healing rules and failure telemetry logging.
    """
    print(f"Starting Roo4u Pipeline for Zip Code: {zip_code}")
    print(f"==================================================")
    print(f" Roo4u Autonomous Lead Pipeline (Milestone 2)    ")
    print(f" Target Zip: {zip_code} | Mode: Offline First    ")
    print(f"==================================================")

    # 1. Initialize Database
    engine = init_db(db_path)
    session = get_session(engine)
    print("Database initialized.")

    # 2. Initialize Dual Memory & GitHub Issue Logger
    lesson_store = LessonStore(file_path=lessons_path)
    vector_store = LocalVectorStore(db_path=vector_db_path)
    github_logger = GitHubIssueLogger(
        owner="s6pa1rta3n-lab",
        repo="roof4u",
        enabled=enable_github_logging
    )

    # 3. Instantiate Learning Agent & Extractor
    extractor = LocalLLMExtractor()
    learning_agent = LearningAgent(
        lesson_store=lesson_store,
        vector_store=vector_store,
        github_logger=github_logger,
        extractor=extractor
    ) if enable_learning else None

    # 4. Instantiate Browsing Agents with Learning Agent Injected
    zillow_agent = ZillowAgent(headless=headless, extractor=extractor, learning_agent=learning_agent)
    county_agent = CountyAgent(headless=headless, extractor=extractor, learning_agent=learning_agent)

    try:
        # -------------------------------------------------------------
        # PHASE 1: DISCOVERY (ZillowAgent)
        # -------------------------------------------------------------
        print("\n--- PHASE 1: DISCOVERY ---")
        print(f"Executing ZillowAgent discovery for zip code: {zip_code}...")

        discovered_leads = []
        if target_address:
            print(f"Processing targeted property address: {target_address}")
            existing = session.query(Lead).filter_by(address=target_address).first()
            if not existing:
                lead = Lead(
                    address=target_address,
                    zip_code=zip_code,
                    property_type="Single-Family",
                    roof_type="Victorian",
                    status="DISCOVERED"
                )
                session.add(lead)
                session.commit()
                discovered_leads.append(lead)
            else:
                discovered_leads.append(existing)
        else:
            # Discover candidates via web scraping
            candidates = zillow_agent.discover_properties(zip_code, max_results=5)
            if candidates:
                for item in candidates:
                    url = item.get("url")
                    try:
                        lead = zillow_agent.scrape_and_create_lead(url, target_zip=zip_code)
                        existing = session.query(Lead).filter_by(address=lead.address).first()
                        if not existing:
                            session.add(lead)
                            session.commit()
                            discovered_leads.append(lead)
                            print(f"-> Discovered and saved lead: {lead.address}")
                        else:
                            discovered_leads.append(existing)
                    except Exception as e:
                        session.rollback()
                        print(f"Warning: Failed to scrape listing {url}: {e}")
            else:
                # If no live listings returned (offline mode/bot block), seed sample property for pipeline continuity
                default_address = "2223 Pacific Ave"
                existing = session.query(Lead).filter_by(address=default_address).first()
                if not existing:
                    print(f"Seeding default property lead: {default_address} (SF, {zip_code})")
                    lead = Lead(
                        address=default_address,
                        zip_code=zip_code,
                        property_type="Single-Family",
                        roof_type="Victorian",
                        is_hoa=False,
                        is_rental=False,
                        status="DISCOVERED"
                    )
                    session.add(lead)
                    session.commit()
                    discovered_leads.append(lead)
                else:
                    discovered_leads.append(existing)

        # -------------------------------------------------------------
        # PHASE 2: ASSESSOR & PERMITS (CountyAgent)
        # -------------------------------------------------------------
        print("\n--- PHASE 2: ASSESSOR & PERMITS ---")
        print("Executing CountyAgent for San Francisco Assessor & DBI Permit records...")

        leads_to_process = session.query(Lead).filter_by(status="DISCOVERED").all()
        for lead in leads_to_process:
            print(f"\n-> Processing Lead: {lead.address}...")
            try:
                county_agent.enrich_lead(lead)
                session.commit()
                val_str = f", Assessed Value: ${lead.estimated_value:,.2f}" if lead.estimated_value else ""
                print(f"   [Assessor] APN: {lead.apn or 'N/A'}{val_str}")
                print(f"   [Permits] Last Roof Permit: {lead.last_roof_permit_date or 'N/A'}, Roof Age: {lead.roof_age_years or 'N/A'} yrs")
                print(f"   [Status] Lead status updated to: {lead.status}")
            except Exception as e:
                session.rollback()
                print(f"   Warning: Failed to enrich lead {lead.address} via CountyAgent: {e}")

        # -------------------------------------------------------------
        # PHASE 3: SUMMARY & LEARNING TELEMETRY
        # -------------------------------------------------------------
        total_discovered = session.query(Lead).filter_by(status="DISCOVERED").count()
        total_validated = session.query(Lead).filter_by(status="VALIDATED").count()
        total_enriched = session.query(Lead).filter_by(status="ENRICHED").count()

        print("\n--- PIPELINE EXECUTION SUMMARY ---")
        print(f"Total Discovered Leads: {total_discovered}")
        print(f"Total Validated Leads:  {total_validated}")
        print(f"Total Enriched Leads:   {total_enriched}")

        if learning_agent:
            all_lessons = lesson_store.load_all()
            active_lessons = [l for l in all_lessons if l.status == "ACTIVE"]
            vector_count = vector_store.count()
            print(f"\n--- LEARNING & TELEMETRY SUMMARY ---")
            print(f"Total Lessons in Memory:      {len(all_lessons)}")
            print(f"Active Self-Healing Rules:    {len(active_lessons)}")
            print(f"Indexed Vectors in Local DB:  {vector_count}")
            for l in active_lessons[-3:]:
                action = l.recommended_action or l.recommended_workaround
                print(f"  * [{l.failure_type}] {l.domain}: {action} (Occurrences: {l.occurrence_count})")

        print("\nPipeline Complete!\n")
    finally:
        zillow_agent.close_browser()
        county_agent.close_browser()
        session.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Roo4u Lead Generation Pipeline (DEPRECATED -> Pure OCaml)")
    parser.add_argument("--zip", type=str, default="94115", help="Target zip code (default: 94115)")
    parser.add_argument("--address", type=str, default=None, help="Target specific property address")
    parser.add_argument("--headless", action="store_true", default=True, help="Run browser in headless mode")
    parser.add_argument("--db", type=str, default="sqlite:///leads.db", help="SQLite database path")
    parser.add_argument("--disable-learning", action="store_true", help="Disable learning agent")
    parser.add_argument("--disable-github", action="store_true", help="Disable github issue logging")
    parser.add_argument("--ocaml", action="store_true", help="Execute native pure OCaml binary instead")
    args = parser.parse_args()

    print("=" * 70)
    print(" [DEPRECATION NOTICE] main.py is DEPRECATED in favor of pure OCaml.")
    print(" Please use pure OCaml engine: ./ocaml/_build/default/bin/main.exe --run")
    print("=" * 70)

    if args.ocaml:
        base_dir = os.path.dirname(os.path.abspath(__file__))
        ocaml_bin = os.path.join(base_dir, "ocaml", "_build", "default", "bin", "main.exe")
        db_clean = args.db.replace("sqlite:///", "")
        cmd = [ocaml_bin, "--run", "--zips", args.zip, "--db", db_clean]
        res = subprocess.run(cmd)
        sys.exit(res.returncode)

    run_pipeline(
        zip_code=args.zip,
        target_address=args.address,
        headless=args.headless,
        db_path=args.db,
        enable_learning=not args.disable_learning,
        enable_github_logging=not args.disable_github
    )
