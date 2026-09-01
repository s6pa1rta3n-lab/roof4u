## 2026-09-01T10:41:00Z
You are an implementation worker agent for Milestone 4 of the Roo4u pure OCaml rewrite.
Working directory: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/teamwork_preview_worker_m4
Project root: /Users/solveetcoagula/Desktop/activeProjects/Roo4u
Original user request: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ORIGINAL_REQUEST.md
Project specification: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/PROJECT.md

You MUST read ORIGINAL_REQUEST.md and PROJECT.md first.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Task:
Implement Milestone 4 deliverables in pure OCaml:
1. ocaml/lib/csv_exporter.mli and ocaml/lib/csv_exporter.ml:
   - Exact 10-column RFC 4180 CSV export: `Address,Zip Code,Property Type,Roof Type,Assessed Value,Owner Name,APN,Roof Age (Years),Phone Number,Status`.
   - CSV formula injection protection: sanitize fields starting with `=`, `+`, `-`, `@`, `\t`, `\r` by prepending `'` and RFC 4180 double-quote escaping.
   - Filter and export VALIDATED and ENRICHED leads with actionability score >= 60.0 to `validated_leads.csv`.
2. ocaml/lib/pipeline.mli and ocaml/lib/pipeline.ml:
   - Core autonomous orchestration workflow:
     * Discovers candidate leads via DataSF SODA connectors (datasf.ml) or municipal PIM/DBI scrapers (municipal.ml) for target SF zip codes (94115, 94123, 94118, 94109).
     * Enriches with property details and permit histories (municipal.ml / llm_client.ml).
     * Executes mathematical invariant checks (INV1-4) and actionability scoring (invariants.ml & scorer.ml).
     * Stores leads and status transitions in SQLite database leads.db (db.ml).
     * On error: logs telemetry (telemetry.ml), updates lessons_learned.json (lesson_store.ml), updates vector store (vector_store.ml), and applies feedforward workarounds.
     * Exports qualified leads to validated_leads.csv (csv_exporter.ml).
3. ocaml/bin/main.ml and ocaml/bin/dune:
   - Main CLI binary (`roof_pipeline`) supporting full live run options:
     * `--run`: Executes the end-to-end live pipeline.
     * `--zips <string>`: Target zip codes (default "94115,94123,94118,94109").
     * `--limit <int>`: Record limit per zip code.
     * `--csv <path>`: Output CSV file (default: "validated_leads.csv").
     * `--db <path>`: SQLite database file (default: "leads.db").
     * `--json <string>` / `--verify-lead <string>`: Single lead verification mode.
     * `--help`: Usage documentation.
4. Update ocaml/test/test_e2e_pipeline.ml to exercise all 5 real-world scenarios and verify CSV output format and scores.
5. Execute live pipeline run to generate `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/validated_leads.csv`.
6. Safely deprecate legacy Python pipeline execution files (main.py, scripts/acquire_live_data.py, exporters/csv_exporter.py) by adding clear OCaml deprecation wrappers/banners pointing to the pure OCaml binary.
7. Verification: Run `dune clean && dune build && dune runtest --force` and verify 100% pass rate with 0 errors/warnings.

Write full handoff report to /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/teamwork_preview_worker_m4/handoff.md documenting all implemented files, exact diffs, test outputs, and validated_leads.csv verification.
Send a message to your caller when done.
