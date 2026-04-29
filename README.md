# Session Handoff

A Claude Code plugin for seamless session continuity when switching accounts or recovering from session limits.

## The Problem

When you hit Claude Code session limits mid-task, you lose ephemeral state:

- **Running monitors** (`tail -f`, log watchers, dev servers)
- **Background processes** (builds, test runners, watchers)
- **Cron jobs** created with `CronCreate` (in-memory only)
- **Work context** (what you were doing, why, and what's next)
- **Key decisions** made during the session

Memory, plans, tasks, and git state persist to disk automatically — but operational context does not. Switching to another account means spending significant time reconstructing what you were doing and restarting services.

## How It Works

Session Handoff uses two layers to track and restore state:

### Layer 1: Automatic Hooks (Safety Net)

Hooks fire on session events to capture process-level data without relying on manual saves:

| Hook | Event | What It Does |
|------|-------|-------------|
| `on-session-start.sh` | `SessionStart` | Detects an existing handoff file and suggests `/handoff resume` |
| `on-post-tool-use.sh` | `PostToolUse` (Bash) | Auto-logs background processes as they're started |
| `on-stop.sh` | `Stop` | Captures a final process snapshot before the session ends |

### Layer 2: The `/handoff` Skill (Semantic Context)

The skill provides explicit commands that capture not just process data, but the *meaning* behind your work — goals, decisions, progress, and next steps.

State is stored in `.claude/handoff/session-state.md` in your **project directory** (not `~/.claude/`), so it survives account switches on the same machine.

## Usage

### Save session state

```
/handoff save
```

Creates a comprehensive snapshot including:
- Current work context and progress
- Active monitors and background processes (with purpose)
- Cron jobs (schedule and prompt)
- Key architectural decisions with rationale
- Git state and environment
- Ordered next steps for the resuming session

### Resume in a new session

```
/handoff resume
```

Reads the saved state and:
1. Presents a briefing of the previous session
2. Identifies which services need restarting
3. Offers to recreate cron jobs
4. Loads the referenced plan file
5. Confirms next steps, then picks up where you left off

### Check tracking status

```
/handoff status
```

Shows the delta between tracked state and live processes — what's running vs. what the handoff file expects.

## Installation

### From GitHub

```bash
# Clone the plugin
git clone https://github.com/arunr8/session-handoff.git ~/.claude/plugins/local/session-handoff

# Make hook scripts executable
chmod +x ~/.claude/plugins/local/session-handoff/hooks/scripts/*.sh
```

### Register the Plugin

Add to `~/.claude/plugins/installed_plugins.json` under the `"plugins"` key:

```json
"session-handoff": [
  {
    "scope": "user",
    "installPath": "~/.claude/plugins/local/session-handoff",
    "version": "0.1.0",
    "installedAt": "2026-04-29T00:00:00.000Z",
    "lastUpdated": "2026-04-29T00:00:00.000Z"
  }
]
```

Add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "session-handoff": true
  }
}
```

Restart Claude Code. The `/handoff` command should appear in available skills.

## Typical Workflow

```
Session 1 (Account A):
  ├── Working on feature implementation...
  ├── Started dev server, monitoring logs
  ├── Made key design decisions
  ├── Approaching session limit
  └── /handoff save  ← captures everything

  [Session ends — switch to Account B]

Session 2 (Account B):
  ├── SessionStart hook: "Handoff file found (5m ago)..."
  ├── /handoff resume
  ├── Briefing: "Working on feature X, 3/7 steps done,
  │   dev server needs restart, next: implement Y"
  ├── Restarts services, continues work
  └── /handoff save  ← before switching back

  [Repeat as needed]
```

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
│       ├── on-session-start.sh     # Resume detection on new session
│       ├── on-post-tool-use.sh     # Background process auto-capture
│       └── on-stop.sh              # Final state save on session end
└── README.md
```

## How the State File Works

The handoff file at `.claude/handoff/session-state.md` is a structured Markdown document with sections for work context, progress, monitors, processes, cron jobs, decisions, environment, and next steps.

**Hooks append raw data** (marked with `<!-- AUTO-CAPTURED -->` comments) as events happen during the session. When you run `/handoff save`, Claude integrates this raw data into the structured format, enriches it with semantic context (purpose, rationale), and writes a clean document.

This means even if you hit a sudden session limit without running `/handoff save`, the `Stop` hook captures a final process snapshot, and any background processes started during the session were already auto-logged by the `PostToolUse` hook.

## Requirements

- Claude Code CLI (v2.1+)
- `bash`, `ps`, `git` (standard on Linux/macOS)
- Optional: `ss` or `lsof` (for port discovery)
- Optional: `python3` (for JSON parsing in the PostToolUse hook)

## License

MIT
