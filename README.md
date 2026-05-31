<p align="center">
  <h1 align="center">Session Handoff</h1>
  <p align="center">
    <strong>Seamless session continuity for Claude Code</strong>
  </p>
  <p align="center">
    Automatically restarts Claude Code sessions when they cut off — zero manual intervention after install.
  </p>
  <p align="center">
    <a href="https://github.com/Ddundee/session-handoff/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
    <a href="https://github.com/Ddundee/session-handoff/releases"><img src="https://img.shields.io/badge/version-0.2.0-green.svg" alt="Version 0.2.0"></a>
    <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg" alt="Platform: Linux | macOS">
    <img src="https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2.svg" alt="Claude Code Plugin">
  </p>
</p>

---

## Quick Start

```bash
claude plugin marketplace add github:Ddundee/session-handoff
claude plugin install session-handoff
```

That's it. Start Claude, and the watchdog daemon auto-bootstraps in the background. If your session ever cuts off, it restarts automatically with full context.

---

## The Problem

When Claude Code sessions hit their limit mid-task, you lose everything that isn't written to disk:

| Lost on session end | Persists natively |
|---|---|
| Running monitors (`tail -f`, dev servers) | Git state |
| Background processes (builds, watchers) | Files on disk |
| Cron jobs (`CronCreate`) | Memory & plans |
| Work context (what, why, what's next) | Tasks |
| Key decisions & rationale | |

**Session Handoff captures what Claude Code doesn't** — and the watchdog daemon ensures you never have to manually recover.

---

## How It Works

```
                          ┌──────────────────────────┐
                          │     Session Running       │
                          │                          │
                          │  Hooks auto-capture:     │
                          │  - Background processes  │
                          │  - Running monitors      │
                          │  - Work context          │
                          └──────────┬───────────────┘
                                     │
                              Session exits
                           (limit, crash, etc.)
                                     │
                          ┌──────────▼───────────────┐
                          │     Stop Hook Fires       │
                          │  Captures final snapshot  │
                          └──────────┬───────────────┘
                                     │
                          ┌──────────▼───────────────┐
                          │   Watchdog Detects Exit   │
                          │  Checks restart budget   │
                          └──────────┬───────────────┘
                                     │
                          ┌──────────▼───────────────┐
                          │   Restarts Claude with    │
                          │   /handoff resume         │
                          │                          │
                          │   Session continues with  │
                          │   full context restored   │
                          └──────────────────────────┘
```

### Three Layers of Protection

**Layer 1 — Automatic Hooks** capture process-level data as you work, without any manual action:

| Hook | Trigger | Action |
|------|---------|--------|
| `on-session-start.sh` | Session starts | Detects handoff file, bootstraps watchdog |
| `on-post-tool-use.sh` | After Bash calls | Auto-logs background processes |
| `on-stop.sh` | Session ends | Captures final process snapshot |

**Layer 2 — `/handoff` Skill** adds semantic context on top of raw process data:

```
/handoff save      # Capture goals, decisions, progress, next steps
/handoff resume    # Restore full context and restart services
/handoff status    # Compare tracked state vs. live processes
```

**Layer 3 — Watchdog Daemon** monitors Claude and auto-restarts on exit:

| Scenario | Action |
|----------|--------|
| Clean exit (code 0) | Restart after 2s |
| Crash (non-zero) | Backoff: 2s → 5s → 10s → 30s → 60s |
| 5 crashes in 10 min | Alert user, stop daemon |
| 10 min stable | Reset crash counter |

---

## Installation

### Plugin Install (Recommended)

```bash
claude plugin marketplace add github:Ddundee/session-handoff
claude plugin install session-handoff
```

Everything works automatically after this. The watchdog daemon spawns on your next session start.

### Optional: Systemd Service

For the watchdog to survive terminal closes and reboots:

```bash
cd ~/.claude/plugins/local/session-handoff
./daemon/setup-systemd.sh /path/to/your/project
```

<details>
<summary>Systemd management commands</summary>

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

</details>

---

## Usage

### Automatic Mode (Default)

After installing, everything is hands-free:

1. **Start Claude** in your project directory
2. **Work normally** — hooks silently capture state as you go
3. **Session cuts off** — watchdog detects the exit
4. **Auto-restart** — Claude relaunches with `/handoff resume`
5. **Continue working** — full context restored, services restarted

### Manual Commands

You can still use the skill commands directly when you want explicit control:

```bash
/handoff save      # Snapshot current session state
/handoff resume    # Restore from a saved snapshot
/handoff status    # Show tracked vs. live process delta
```

---

## What Gets Tracked

| State | Without Plugin | With Session Handoff |
|-------|---------------|---------------------|
| Running monitors | Lost | Logged with command + purpose |
| Background processes | Lost | Auto-captured by hooks |
| Cron jobs | Lost (in-memory only) | Saved with schedule + prompt |
| Work context & decisions | Lost (in conversation) | Structured summary |
| Shell environment | Lost | Key variables captured |
| Plans, tasks, git, memory | Already persists | Referenced for quick reload |

State is saved to `.claude/handoff/session-state.md` in your **project directory**, so it survives account switches on the same machine.

---

## Crash Loop Protection

If Claude keeps crashing (5 times within 10 minutes), the watchdog:

1. Sends a **desktop notification** via `notify-send`
2. Logs details to `.claude/handoff/watchdog.log`
3. **Stops restarting** — manual intervention required

<details>
<summary>Recovering from a crash loop</summary>

```bash
# Check what went wrong
cat .claude/handoff/watchdog.log

# Manually start Claude and save state if needed
claude
/handoff save

# Remove the stale PID file
rm .claude/handoff/watchdog.pid

# Watchdog auto-bootstraps on next Claude session
```

</details>

---

## Architecture

```
session-handoff/
├── .claude-plugin/
│   └── plugin.json                 # Plugin metadata
├── skills/
│   └── handoff/
│       ├── SKILL.md                # /handoff [save|resume|status]
│       └── references/
│           ├── state-format.md     # State file template
│           └── resume-checklist.md # Resume procedure
├── hooks/
│   ├── hooks.json                  # Hook registrations
│   └── scripts/
│       ├── capture-state.sh        # Process/port/git discovery
│       ├── on-session-start.sh     # Resume detection + watchdog bootstrap
│       ├── on-post-tool-use.sh     # Background process auto-capture
│       └── on-stop.sh              # Final state snapshot
├── daemon/
│   ├── claude-watchdog.sh          # Watchdog daemon
│   ├── claude-watchdog.service     # Systemd unit template
│   └── setup-systemd.sh           # Systemd install helper
└── README.md
```

---

## Troubleshooting

<details>
<summary>Watchdog not starting</summary>

```bash
# Check for stale PID file
cat .claude/handoff/watchdog.pid
ps -p $(cat .claude/handoff/watchdog.pid)

# Remove stale PID and restart Claude
rm .claude/handoff/watchdog.pid
```

</details>

<details>
<summary>Claude keeps restarting when I don't want it to</summary>

```bash
# Kill the watchdog cleanly
kill $(cat .claude/handoff/watchdog.pid)
```

Sending `SIGTERM` or `SIGINT` forwards the signal to Claude and exits without restarting.

</details>

<details>
<summary>Checking watchdog logs</summary>

```bash
tail -f .claude/handoff/watchdog.log
```

</details>

---

## Requirements

| Required | Optional |
|----------|----------|
| Claude Code CLI (v2.1+) | `notify-send` (desktop alerts) |
| `bash`, `ps`, `git` | `systemd` (reboot persistence) |
| | `ss` or `lsof` (port discovery) |
| | `python3` (JSON parsing in hooks) |

---

## License

[MIT](LICENSE)

---

<p align="center">
  Built by <a href="https://github.com/Ddundee">Ddundee</a>
</p>
