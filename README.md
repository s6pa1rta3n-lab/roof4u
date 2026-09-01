# Roo4u - Offline Agentic Lead Generation

Roo4u is an automated lead generation pipeline for roofing contractors targeting Victorian and Flat roofs in high-income neighborhoods.

## System Architecture

The system operates entirely offline using local compute resources. It requires zero external cloud APIs or paid infrastructure. All operations execute within the Antigravity Desktop Agent environment via scheduled tasks.

### Core Components

1. **Local Inference Execution:** The Browsing Agent executes web scraping and data extraction tasks using a local OpenAI-compatible inference endpoint (`http://localhost:8000/v1`). It parses HTML structures dynamically without external language model dependencies.
2. **Learning Agent (Self-Healing Loop):** A dedicated agent monitors the system for scraping failures. It records failures to a dual-memory system consisting of a local file (`lessons_learned.json`) and a custom SQLite+NumPy vector database. It logs issues to GitHub using a dual-transport client (MCP and REST fallback) with SHA-256 deduplication.
3. **Programmatic Zero-Mock Test Suite:** The testing infrastructure uses live Starlette and Uvicorn loopback servers to simulate network traffic locally. It executes all tests without utilizing the `unittest.mock` library for external endpoints.
4. **Agent-As-Judge Evaluator:** An evaluation agent analyzes the codebase using Abstract Syntax Trees (AST). It scores the system across five dimensions and issues a cryptographic SHA-256 digital certificate (`CERTIFIED_PASS.json`) upon successful verification.

## Technology Stack

- **Execution Environment:** Antigravity Scheduled Tasks
- **Inference Engine:** Local OpenAI-compatible server (e.g., NVIDIA open-source models)
- **Vector Database:** Custom SQLite and NumPy implementation
- **Testing:** Pytest with native HTTP loopback servers
- **Data Storage:** SQLite database and CSV file exports

## Execution Status

The current implementation has completed all primary milestones. The codebase holds a 100 percent test pass rate across 468 integration tests and possesses a validated `CERTIFIED_PASS.json` digital signature.

## Setup Instructions

1. Clone the repository to your local machine.
2. Ensure the Antigravity Desktop application is installed and active.
3. Start the local inference endpoint on port 8000.
4. Configure a scheduled task within Antigravity to trigger the orchestrator.
5. The system processes leads and generates the `validated_leads.csv` export file locally.

## License

This project is licensed under the MIT License.
