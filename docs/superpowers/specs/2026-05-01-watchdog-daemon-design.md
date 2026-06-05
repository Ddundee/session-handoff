# Watchdog Daemon Design Spec

**Date:** 2026-05-01
**Status:** Approved

## Problem

Claude Code sessions can cut off unexpectedly due to session limits, crashes, or network issues. The existing session-handoff plugin captures state on exit but requires manual `/handoff resume` to restore. Users want zero-intervention recovery.

## Solution

A PID-polling watchdog daemon that:
1. Launches Claude as a child process
2. Detects when Claude exits (any reason)
3. Automatically restarts Claude with `/handoff resume`
4. Protects against crash loops with backoff and alerting
5. Auto-bootstraps via the SessionStart hook — no manual setup beyond plugin install

## Architecture

```
SessionStart Hook
  → Is watchdog running? (check PID file)
    → YES: do nothing
    → NO:  spawn watchdog in background

Watchdog Main Loop:
  1. Launch `claude` as child process
  2. Wait for exit
  3. Stop hook captures state automatically
  4. Check restart budget
     - OK → backoff delay → restart with resume
     - Exhausted → alert user, stop
  5. Go to 1
```

### Files

| File | Purpose |
|------|---------|
| `daemon/claude-watchdog.sh` | Main watchdog script |
| `daemon/claude-watchdog.service` | Optional systemd user unit |
| `daemon/setup-systemd.sh` | Helper to install systemd unit |
| `hooks/scripts/on-session-start.sh` | Modified to auto-bootstrap watchdog |

### State Files (per-project, runtime)

| File | Purpose |
|------|---------|
| `.claude/handoff/watchdog.pid` | Watchdog PID (prevents duplicates) |
| `.claude/handoff/watchdog.log` | Daemon log output |
| `.claude/handoff/session-state.md` | Existing handoff state file |

## Watchdog Behavior

### Startup
- Takes project directory as argument (defaults to `$PWD`)
- Checks for existing watchdog via PID file — exits if one is alive
- Writes own PID to `.claude/handoff/watchdog.pid`
- Logs startup to `.claude/handoff/watchdog.log`

### Main Loop
- Launches `claude` in the project directory
- Waits for child process to exit
- On exit code 0 (clean): restart after 2s delay
- On non-zero exit (crash): increment crash counter, apply backoff

### Backoff Schedule
- Restart delays: 2s → 5s → 10s → 30s → 60s
- After 5 crashes within 10 minutes: alert and stop
- Crash counter resets after 10 minutes of stable operation

### Crash Alerting
- Always: append alert to `watchdog.log`
- If available: `notify-send` desktop notification
- Log message includes instructions for manual save

### Clean Shutdown
- `SIGTERM`/`SIGINT` to watchdog → forward signal to Claude child
- Exit without restart (user intentionally stopped the watchdog)
- Clean up PID file on exit

### Resume Mechanism
- Restart Claude with: `claude -p "run /handoff resume"`
- The existing Stop hook ensures state is captured before exit
- The existing SessionStart hook detects the handoff file

## Hook Integration

### Modified `on-session-start.sh`
After existing handoff detection logic:
1. Resolve path to `claude-watchdog.sh` (relative to hook script location)
2. Check if `.claude/handoff/watchdog.pid` exists and process is alive
3. If no watchdog running: spawn with `nohup` in background, redirect to log

### Unchanged Hooks
- `on-stop.sh`: Still captures final state — watchdog depends on this
- `on-post-tool-use.sh`: Still logs background processes

## Systemd Unit (Optional)

User-level service at `~/.config/systemd/user/claude-watchdog@.service` (template unit, instance = project path hash). `setup-systemd.sh` installs it.

## Installation

```bash
# Plugin install — everything works automatically
claude plugin marketplace add Ddundee/session-handoff
claude plugin install session-handoff

# Optional: systemd for reboot persistence
./daemon/setup-systemd.sh /path/to/project
```

## Success Criteria
- Session cut-off → Claude restarts within 5s with full context
- Crash loop → user alerted after 5 failures, daemon stops
- Zero manual intervention required after plugin install
- Watchdog survives terminal close (when run via systemd)
