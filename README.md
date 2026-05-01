# Session Handoff

A Claude Code plugin for seamless session continuity. Automatically restarts Claude Code sessions when they cut off — zero manual intervention after install.

## The Problem

When you hit Claude Code session limits mid-task, you lose ephemeral state:

- **Running monitors** (`tail -f`, log watchers, dev servers)
- **Background processes** (builds, test runners, watchers)
- **Cron jobs** created with `CronCreate` (in-memory only)
- **Work context** (what you were doing, why, and what's next)
- **Key decisions** made during the session

Memory, plans, tasks, and git state persist to disk automatically — but operational context does not. Previously, recovering required manually running `/handoff resume`. Now the watchdog daemon handles it automatically.

## How It Works

Session Handoff uses three layers:

### Layer 1: Automatic Hooks (Safety Net)

Hooks fire on session events to capture process-level data without manual saves:

| Hook | Event | What It Does |
|------|-------|-------------|
| `on-session-start.sh` | `SessionStart` | Detects handoff file, auto-bootstraps watchdog daemon |
| `on-post-tool-use.sh` | `PostToolUse` (Bash) | Auto-logs background processes as they're started |
| `on-stop.sh` | `Stop` | Captures a final process snapshot before session ends |

### Layer 2: The `/handoff` Skill (Semantic Context)

Explicit commands that capture not just process data, but the *meaning* behind your work — goals, decisions, progress, and next steps.

State is stored in `.claude/handoff/session-state.md` in your **project directory** (not `~/.claude/`), so it survives account switches on the same machine.

### Layer 3: Watchdog Daemon (Auto-Restart)

A background daemon that monitors the Claude process and automatically restarts it when sessions cut off:

```
Claude exits (session limit, crash, network issue)
  → Stop hook captures state
  → Watchdog detects exit
  → Backoff delay (if crash)
  → Watchdog restarts Claude with /handoff resume
  → Session continues with full context
```

The watchdog starts automatically — no configuration needed. On the first `SessionStart`, the hook spawns the watchdog in the background if it isn't already running.

## Installation

```bash
# Install the plugin (everything works automatically after this)
claude plugin install github:themoddedcube/session-handoff
```

That's it. The next time Claude starts, the watchdog daemon will auto-bootstrap and begin guarding your session.

### Optional: Systemd Service

For the watchdog to survive terminal closes and system reboots:

```bash
# Navigate to the plugin directory
cd ~/.claude/plugins/local/session-handoff

# Install systemd user service for your project
./daemon/setup-systemd.sh /path/to/your/project
```

Manage the service:

```bash
# Check status
systemctl --user status claude-watchdog@<instance>.service

# View logs
journalctl --user -u claude-watchdog@<instance>.service

# Stop
systemctl --user stop claude-watchdog@<instance>.service

# Disable (remove from boot)
systemctl --user disable claude-watchdog@<instance>.service
```

## Usage

### Automatic (Default)

After installing the plugin, everything is automatic:

1. Start Claude in your project directory
2. The `SessionStart` hook spawns the watchdog daemon in the background
3. Work normally — hooks capture state as you go
4. If Claude exits for any reason, the watchdog restarts it with full context
5. The resumed session picks up where you left off

### Manual Commands

You can still use the skill commands directly:

```bash
# Save session state explicitly (hooks do this automatically)
/handoff save

# Resume from a saved state
/handoff resume

# Check what's tracked vs. what's running
/handoff status
```

## Watchdog Behavior

### Restart Logic

| Scenario | Watchdog Action |
|----------|----------------|
| Clean exit (code 0) | Restart after 2s delay |
| Crash (non-zero exit) | Backoff: 2s → 5s → 10s → 30s → 60s |
| 5 crashes in 10 minutes | Alert user, stop watchdog |
| 10 minutes stable | Reset crash counter |

### Crash Loop Protection

If Claude keeps crashing (5 times within 10 minutes), the watchdog:

1. Sends a desktop notification (via `notify-send`)
2. Logs details to `.claude/handoff/watchdog.log`
3. Stops restarting — manual intervention required

To recover from a crash loop:

```bash
# Check what went wrong
cat .claude/handoff/watchdog.log

# Manually start Claude and save state if needed
claude
/handoff save

# Remove the stale PID file and restart
rm .claude/handoff/watchdog.pid

# The watchdog will auto-bootstrap on next Claude session start
```

### Clean Shutdown

To stop the watchdog intentionally (without it restarting Claude):

```bash
# Find and kill the watchdog
kill $(cat .claude/handoff/watchdog.pid)
```

Sending `SIGTERM` or `SIGINT` to the watchdog forwards the signal to Claude and exits cleanly without restarting.

## What Gets Tracked

| State | Native Persistence | How Handoff Helps |
|-------|-------------------|-------------------|
| Monitors (`tail -f`, watchers) | Ephemeral | Logged with command + purpose |
| Background processes | Ephemeral | Auto-captured by hook, enriched on save |
| Cron jobs (`CronCreate`) | In-memory only | Saved with schedule + prompt |
| Work context and decisions | In conversation only | Saved as structured summary |
| Shell environment | Ephemeral | Key variables captured |
| Plans and tasks | Already persistent | Referenced by path for quick reload |
| Memory | Already persistent | Works across accounts automatically |
| Git state | Already persistent | Branch and status captured for verification |

## Plugin Structure

```
session-handoff/
├── .claude-plugin/
│   └── plugin.json                 # Plugin metadata
├── skills/
│   └── handoff/
│       ├── SKILL.md                # Core skill: /handoff [save|resume|status]
│       └── references/
│           ├── state-format.md     # Canonical handoff file template
│           └── resume-checklist.md # Step-by-step resume procedure
├── hooks/
│   ├── hooks.json                  # Hook event registrations
│   └── scripts/
│       ├── capture-state.sh        # Process/port/git discovery utility
│       ├── on-session-start.sh     # Resume detection + watchdog bootstrap
│       ├── on-post-tool-use.sh     # Background process auto-capture
│       └── on-stop.sh              # Final state save on session end
├── daemon/
│   ├── claude-watchdog.sh          # Watchdog daemon script
│   ├── claude-watchdog.service     # Systemd user unit template
│   └── setup-systemd.sh           # Systemd install helper
├── docs/
│   └── superpowers/specs/
│       └── 2026-05-01-watchdog-daemon-design.md
└── README.md
```

## How the State File Works

The handoff file at `.claude/handoff/session-state.md` is a structured Markdown document with sections for work context, progress, monitors, processes, cron jobs, decisions, environment, and next steps.

**Hooks append raw data** (marked with `<!-- AUTO-CAPTURED -->` comments) as events happen during the session. When you run `/handoff save`, Claude integrates this raw data into the structured format, enriches it with semantic context (purpose, rationale), and writes a clean document.

Even without running `/handoff save`, the `Stop` hook captures a final process snapshot, and background processes are auto-logged by the `PostToolUse` hook. The watchdog daemon uses this auto-captured state to resume.

## How the Watchdog Works

The watchdog is a simple bash script that:

1. Launches Claude as a child process
2. Waits for Claude to exit
3. Checks the exit code and restart budget
4. Restarts Claude with a `/handoff resume` prompt
5. Repeats until intentionally stopped or crash loop detected

**PID file** at `.claude/handoff/watchdog.pid` prevents duplicate watchdogs. The `SessionStart` hook checks this file — if the watchdog isn't running, it spawns one automatically.

**Log file** at `.claude/handoff/watchdog.log` records all watchdog activity for debugging.

## Requirements

- Claude Code CLI (v2.1+)
- `bash`, `ps`, `git` (standard on Linux/macOS)
- Optional: `ss` or `lsof` (for port discovery)
- Optional: `python3` (for JSON parsing in the PostToolUse hook)
- Optional: `notify-send` (for desktop crash notifications on Linux)
- Optional: `systemd` (for reboot-persistent watchdog)

## Troubleshooting

### Watchdog not starting

```bash
# Check if the PID file exists with a stale PID
cat .claude/handoff/watchdog.pid
ps -p $(cat .claude/handoff/watchdog.pid)

# Remove stale PID file
rm .claude/handoff/watchdog.pid

# Watchdog will auto-start on next Claude session
```

### Claude keeps restarting when I don't want it to

```bash
# Kill the watchdog cleanly
kill $(cat .claude/handoff/watchdog.pid)
```

### Checking watchdog logs

```bash
tail -f .claude/handoff/watchdog.log
```

## License

MIT
