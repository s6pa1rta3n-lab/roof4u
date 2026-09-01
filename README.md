# Roo4u - Agentic Lead Generation

Roo4u is an automated, agentic lead generation pipeline specifically designed for roofing contractors targeting **Victorian** and **Flat** roofs in wealthy neighborhoods.

## Architecture: The "Local Swarm" (Zero-Cost Cloud Alternative)
Until we scale to paid cloud infrastructure with API keys, Roo4u leverages a brilliant "Local Compute Arbitrage" architecture. Instead of deploying to AWS or GCP, this system runs entirely within the **Antigravity Desktop Agent Environment** using **Global Scheduled Tasks**.

Every time the scheduled cron job triggers, it spawns a fresh **sidecar agent** that executes our pipeline in the following priority order:

1. **GitHub Issue Polling:** The agent acts as an autonomous worker, checking this GitHub repository's issues for new commands (e.g., a new zip code to target or a bug to fix) before beginning its run.
2. **Database Maintenance:** It connects to the local SQLite database (`leads.db`) to clean up old data, enforce uniqueness, and prep the environment.
3. **Agentic Web Browsing:** It invokes a browser subagent (via `/browser` concepts) to scrape Zillow, County GIS, Permit Tracking, and PeopleSearch platforms autonomously to validate leads without paying for commercial API data.
4. **Execution & Export:** It records its findings back into the database and spits out a `validated_leads.csv` for human review.

## Tech Stack
- **Environment:** Antigravity Global Scheduled Tasks (Cron)
- **Orchestration:** Multi-Agent Swarm (Sidecar spawn via CLI / UI)
- **Scraping:** Headless Browser Agents 
- **Storage Foundation:** SQLite3 -> CSV

## Setup Instructions
1. Clone the repository.
2. Ensure you have the Antigravity Desktop App installed.
3. Set a Global Scheduled Task to run the orchestrator script on a recurring basis. The agent will handle the rest autonomously in sidecar chats!

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
