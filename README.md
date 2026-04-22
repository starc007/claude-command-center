# Claude Command Center

A native macOS app (SwiftUI) for visibility and control over your Claude Code work — sessions, running processes, ports, token spend, and MCP servers. Everything local. No API keys. No network.

## What it does

- **Sessions** — flat list of every session under `~/.claude/projects/`, grouped by project. Green "Running" pill when a session is active. Resume any session into your preferred terminal with one click.
- **Processes** — live scan of running `claude` CLI instances. Shows cwd, uptime, and the resolved session id. Kill any hung session.
- **Ports** — every TCP listener on your machine, grouped by process family (Node / Python / Docker / Rust / Go / databases / …). Swipe-to-kill or force-kill via context menu.
- **Cost** — parses token usage out of every JSONL, applies per-model pricing (Opus / Sonnet / Haiku), and shows today / this month / all-time spend with a 30-day area chart and a top-projects leaderboard.
- **MCP Servers** — merges the Claude Code (`~/.claude/.mcp.json`) and Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`) configs, matches each entry to a live PID, tails log files for recent warnings, and restarts on demand. Add new servers via an in-app form.

## Plus

- **Quick launcher** — resumes Claude in Ghostty → iTerm → Terminal (whichever is installed first).
- **Session export** — renders any session's JSONL to clean Markdown (user prompts as blockquotes, tool calls as collapsed details blocks).
- **Idle-session notifications** — fires a "Claude finished working on X" alert when a project goes quiet after activity.
- **Menu-bar popover** — tap a tab in the menu bar to deep-link to it in the main window.
- **Content search** — full-text search across every JSONL transcript, not just project names.
- **Git integration** — current branch and dirty-tree indicator on every session row.
