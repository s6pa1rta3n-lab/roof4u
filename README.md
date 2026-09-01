# Roo4u - Agentic Lead Generation

Roo4u is an automated, agentic lead generation pipeline specifically designed for roofing contractors targeting **Victorian** and **Flat** roofs in wealthy neighborhoods. 

## Overview
This system uses a funnel-based methodology to extract, validate, and enrich leads autonomously using a series of specialized AI agents:

1. **Discovery (Zillow/Redfin Agent):** Locates Victorian and Flat roof properties in targeted wealthy zip codes while explicitly filtering out HOAs and rental properties.
2. **Owner & Property Agent (County GIS/Assessor):** Navigates complex county assessor websites to extract property tax data and owner entity information.
3. **Permit Agent (Building Inspection):** Queries county/city permit databases to determine the age of the roof by parsing historical roofing permits (e.g., "tear off", "reroof").
4. **Enrichment Agent (PeopleSearch):** Matches the owner name and address across public directories to retrieve valid phone numbers.

## Tech Stack
- **Language:** Python 3.10+
- **Browser Automation:** Playwright
- **Agent Orchestration:** LangChain / PydanticAI
- **LLM Integration:** Google Gemini API (for parsing messy DOM/HTML into structured data)
- **Storage Foundation:** SQLite3
- **Exports:** CSV and Google Sheets API

## Setup Instructions
1. Clone the repository.
2. Create a virtual environment: `python -m venv venv` and activate it.
3. Install dependencies: `pip install -r requirements.txt`
4. Install Playwright browsers: `playwright install`
5. Set your `GEMINI_API_KEY` in a `.env` file.

## Development Status
- [x] Phase 1: Manual POC Validation
- [x] Phase 2: Project Initialization & Database Setup
- [ ] Phase 3: Agent Implementation
- [ ] Phase 4: Pipeline Orchestration & Export

## Database
Leads are stored in a local SQLite database (`db/leads.db`). The schema strictly enforces uniqueness on the property address to prevent duplicate scraping.
