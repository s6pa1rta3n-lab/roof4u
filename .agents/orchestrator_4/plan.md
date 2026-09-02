# Plan — Lead Generation Pipeline Verification for 4 SF Districts

## Objective
Execute and validate the Roo4u end-to-end lead generation pipeline across four target San Francisco neighborhoods: Sunset, Richmond, Excelsior, and Pacific Heights.

## Plan Steps
1. **Exploration Phase**:
   - Dispatch 3 parallel Explorers (`teamwork_preview_explorer`) to inspect Roo4u codebase, existing OCaml test setup, Dune configuration, lead generation pipeline modules, cryptographic proof generation, and existing test suites.
   - Synthesize findings into a consolidated implementation strategy.
2. **Implementation Phase**:
   - Dispatch Worker (`teamwork_preview_worker`) to implement OCaml automated test suite extensions for Sunset, Richmond, Excelsior, and Pacific Heights districts.
   - Ensure genuine end-to-end execution, lead qualification, and cryptographic proof verification with zero mocks/bypasses.
   - Ensure real-time build process documentation for any blockers/errors encountered as GitHub sub-issues on `s6pa1rta3n-lab/roof4u` issue #30.
3. **Review & Verification Phase**:
   - Dispatch 2 Reviewers (`teamwork_preview_reviewer`) to verify correctness, test passing (`dune runtest`), code layout, and absence of inline comments or mocked logic.
   - Dispatch 2 Challengers (`teamwork_preview_challenger`) to independently execute stress tests and edge cases.
   - Dispatch Forensic Auditor (`teamwork_preview_auditor`) to verify anti-cheating, cryptographic validity, and zero mocked logic.
4. **Gate Evaluation & Delivery**:
   - Check all verdicts in `GATE_STATUS.md`.
   - Ensure all acceptance criteria are met.
   - Produce final `handoff.md` and report to Sentinel.
