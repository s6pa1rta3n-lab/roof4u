---
name: handoff
description: >-
  Use this skill when the user types the slash command `/handoff`. This command instructs the agent to programmatically spawn a new conversation chat using the agentapi CLI, passing the current context and requirements to the new chat.
---

# /handoff Slash Command

When the user types `/handoff` (followed optionally by a prompt or instructions), you must execute the `agentapi new-conversation` command to spawn a new chat in the UI.

## Execution Steps:
1. Gather the necessary context, constraints, and the user's provided prompt (if any).
2. Formulate a comprehensive string that summarizes the handover state.
3. Run the following command in the terminal:
   `~/.gemini/antigravity/bin/agentapi new-conversation "<your_formulated_prompt_here>"`
4. Confirm to the user that the new chat has been spawned.
