# Roo4u - Automated Lead Generation Pipeline

Roo4u is an automated lead generation pipeline for roofing contractors targeting Victorian and flat roofs in high-income neighborhoods.

## Overview

Roo4u finds high-value roofing leads. It identifies specific roof types in affluent San Francisco corridors, extracts the property owner's name and mailing address, calculates the age of the roof using building permits, filters out condos and commercial rentals, and finds the owner's phone number. The final output is a verified list of actionable leads ready for contact.

### Technical Architecture

The system is a fully autonomous pipeline built entirely in OCaml. It processes data locally.

1. **GIS Integration (`gods-eye-view`)**: The pipeline ingests San Francisco neighborhood polygon boundaries. It uses a custom ray-casting algorithm with AABB pre-filtering to identify properties in target corridors (Pacific Heights, Marina, Seacliff). It applies morphological classifiers to target Victorian, flat, and Mansard roofs.
2. **Public Record Connectors**: The system extracts property ownership from the San Francisco Assessor-Recorder Secured Roll. It normalizes addresses to USPS Publication 28 standards.
3. **Roof Age Validation**: The pipeline parses Department of Building Inspection (DBI) permit datasets. It analyzes roofing keywords to calculate the elapsed roof age. It queries county tax and property records to filter out Homeowner Associations (HOAs) and commercial rentals.
4. **Contact Enrichment**: The system uses a 4-tier waterfall enrichment process (Commercial Skip Tracer -> OSINT Scraper -> Municipal Directory) to append phone numbers. A strict North American Numbering Plan (NANP) validator rejects fake numbers and toll-free lines.
5. **Production Infrastructure**: The system executes via a CLI runner (`bin/main.ml`). It stores state in a resilient SQLite database running in WAL mode to guarantee transactional idempotency. It exports leads to a 10-column RFC 4180 CSV file, protects against formula injection, and validates every lead with a cryptographic SHA-256 proof.

## Agentic Development and GitHub Integration

We built Roo4u using multi-agent swarms. We delegated complex engineering milestones to autonomous agent teams that executed the entire software development lifecycle.

### Multi-Agent Orchestration
We used the `teamwork_preview` system to spawn parallel agents (explorers, workers, reviewers, challengers, and auditors). These agents independently researched requirements, wrote OCaml code, patched vulnerabilities, and audited the final deliverables. 

### Zero-Mock Verification
The agent teams enforced absolute integrity. They wrote and passed over 1,500 test assertions across 29 test suites using real data invariants. They refused all test mocks. Independent post-victory auditors verified the cryptographic proofs and enforced a coding style with zero inline comments.

### GitHub as a Second Brain
We integrated GitHub directly into the agent workflow to track state and manage the build process.
- **Mandatory Documentation**: Agents filed unexpected errors, blockers, and architecture shifts as sub-issues under parent epics in real time.
- **Automated Issue Management**: We implemented a strict issue hygiene framework. The agents cross-reference the OCaml codebase against open GitHub issues. They automatically close resolved issues using explicit code citations and test run evidence. A scheduled GitHub Actions workflow and local reconciliation scripts guarantee issues transition deterministically from `TRIAGED` to `CLOSED`.

## Setup Instructions

1. Clone the repository.
2. Install OCaml (5.1.0) and Dune.
3. Run the complete test suite:
   ```bash
   cd ocaml && dune runtest
   ```
4. Execute the CLI pipeline to generate leads:
   ```bash
   dune exec roo4u -- --run --neighborhood "Pacific Heights" --csv validated_leads.csv
   ```

## License

MIT License.
