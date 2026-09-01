# Dispatch for Explorer M2-2 (GitHub Issue Logger)

## 2026-09-01T08:21:07Z

You are Explorer M2-2.
Working directory: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m2_2
Project root: /Users/solveetcoagula/Desktop/activeProjects/Roo4u

Authoritative User Request: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/ORIGINAL_REQUEST.md
Project Blueprint: /Users/solveetcoagula/Desktop/activeProjects/Roo4u/PROJECT.md

Task:
Investigate and design the GitHub Issue Logger for Milestone 2:
1. `integrations/github_client.py`: Dual-transport GitHub issue manager.
   - Primary: MCP tools via `github-mcp-server` (`issue_write`, `list_issues`, `add_issue_comment`).
   - Fallback: GitHub REST API (`https://api.github.com/repos/s6pa1rta3n-lab/roof4u/issues`) using `requests`/`httpx` with `GITHUB_TOKEN` if present or graceful offline queuing/logging.
   - Target repository: `s6pa1rta3n-lab/roof4u`.
   - Deduplication: Search existing open issues by domain/failure title before creating a new issue; append comment if already exists.
   - Formatting: Structured markdown issue body with reproduction steps, stack trace, DOM snippet, and proposed self-healing patch.

Deliverables:
- Detailed technical design and interface specification in `.agents/explorer_m2_2/github_logger_design.md`
- 5-component handoff report in `.agents/explorer_m2_2/handoff.md`
- Notify parent when complete via `send_message`.
