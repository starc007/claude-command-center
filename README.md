# Claude Command Center

A native macOS app (SwiftUI) for visibility and control over your Claude Code work — sessions, running processes, ports, token spend, and MCP servers. Everything local. No API keys. No network.

## What it does

- **Sessions** — flat list of every session under `~/.claude/projects/`, grouped by project. Green "Running" pill when a session is active. Resume any session into your preferred terminal with one click.
- **Processes** — live scan of running `claude` CLI instances. Shows cwd, uptime, and the resolved session id. Kill any hung session.
- **Ports** — every TCP listener on your machine, grouped by process family (Node / Python / Docker / Rust / Go / databases / …). Swipe-to-kill or force-kill via context menu.
- **Cost** — parses token usage out of every JSONL, applies per-model pricing (Opus / Sonnet / Haiku), and shows today / this month / all-time spend with a 30-day area chart and a top-projects leaderboard.
- **MCP Servers** — merges the Claude Code (`~/.claude/.mcp.json`) and Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`) configs, matches each entry to a live PID, tails log files for recent warnings, and restarts on demand. Add new servers via an in-app form.

Plus:
- **Quick launcher** — resumes Claude in Ghostty → iTerm → Terminal (whichever is installed first).
- **Session export** — renders any session's JSONL to clean Markdown (user prompts as blockquotes, tool calls as collapsed details blocks).
- **Idle-session notifications** — fires a "Claude finished working on X" alert when a project goes quiet after activity (requires bundled `.app`; see limitations).
- **Menu-bar popover** — tap a tab in the menu bar to deep-link to it in the main window.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 15+ (Swift 5.9+ toolchain)
- Optional: Ghostty or iTerm installed; otherwise falls back to Terminal.app

## Build + run

```bash
swift build
./.build/debug/ClaudeCommandCenter
```

For a release binary:

```bash
swift build -c release
./.build/release/ClaudeCommandCenter
```

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘R | Refresh the current tab |
| ⌘N | Add MCP server (MCP tab) |
| ⌘Q | Quit |

## Data sources

Everything the app reads is on your local disk:

- `~/.claude/projects/<folder>/*.jsonl` — session transcripts + token usage
- `~/.claude/.mcp.json` — Claude Code MCP config
- `~/Library/Application Support/Claude/claude_desktop_config.json` — Claude Desktop MCP config
- `~/Library/Logs/Claude/mcp-server-<name>.log` — per-server stderr logs
- `lsof -nP -iTCP -sTCP:LISTEN` — active TCP listeners
- `ps -axww` — running processes

No credentials, no telemetry, no network calls.

## Project layout

```
Sources/ClaudeCommandCenter/
  App/                      # @main entry + AppState + AppDelegate
  Models/                   # Session, PortInfo, MCPServer, …
  Services/                 # SessionReader, PortManager, CostTracker, MCPManager, GitService, TerminalLauncher, …
  Views/                    # SessionListView, PortManagerView, CostTrackerView, MCPManagerView, ClaudeProcessesView, AddMCPServerSheet
  Components/               # GlassCard, StatusDot, AnimatedCounter
  MenuBar/                  # MenuBarView
  Theme/                    # Colors, Typography, Animations
```

## Known limitations

- **Notifications require a signed `.app` bundle.** Running via `swift run` the idle watcher still runs, but `UNUserNotificationCenter` asserts on a nil `bundleProxy` unless the binary is inside a proper bundle. Migrate to an Xcode app target to light this up.
- **Terminal automation permission** — the first time the app launches a session in Terminal / iTerm / Ghostty, macOS prompts for Automation permission. Grant it from *System Settings → Privacy & Security → Automation*.
- **Path decoding is best-effort** — the session folder name encoding (`-` → `/`) is lossy for project paths with real hyphens. The app resolves the real path from the `cwd` field in the JSONL, which is always correct; only the fallback path is approximate.

## Roadmap

- Package into a real `.app` bundle with entitlements + code signing
- Per-session detail view with inline preview of user + assistant turns
- Manual session-idle timer override for custom "finished" notifications
- File-system watch instead of polling for the idle detector

## License

MIT.
