# Roo4u - Agentic Lead Generation

Roo4u is an automated, agentic lead generation pipeline specifically designed for roofing contractors targeting **Victorian** and **Flat** roofs in wealthy neighborhoods.

## Architecture: The "Local Swarm" (Zero-Cost Cloud Alternative)
Until we scale to paid cloud infrastructure with API keys, Roo4u leverages a brilliant "Local Compute Arbitrage" architecture. Instead of deploying to AWS or GCP, this system runs entirely within the **Antigravity Desktop Agent Environment** using **Global Scheduled Tasks**.

We operate on an **Hourly Micro-Batch Schedule**. Every hour, a cron job triggers and spawns a master "Orchestrator" sidecar agent that delegates work to a swarm of subagents:

1. **GitHub Issue Polling:** The master invokes a `github_db_manager` subagent equipped with the native `github-mcp-server`. It reads this repository's issues to grab your latest commands (e.g., changing the target zip code).
2. **Database Maintenance:** The same subagent connects to the local SQLite database (`leads.db`) and queues up exactly 3-5 leads to process. Keeping the batch size micro allows us to fly completely under the radar of anti-bot systems.
3. **Pure AI Browsing:** The master then invokes a specialized `pure_ai_browser` subagent. Rather than relying on static, breakable Python scripts, this subagent acts exactly like the `/browser` command—using its own AI logic to search the web, read HTML, and navigate county sites dynamically from scratch to validate the leads.
4. **Execution & Export:** The master records the findings back into the database and spits out a `validated_leads.csv` for human review.

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
