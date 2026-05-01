#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: detect an existing handoff file and notify Claude.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HANDOFF_FILE="$PROJECT_DIR/.claude/handoff/session-state.md"

if [ -f "$HANDOFF_FILE" ]; then
  # Calculate age of handoff file
  if stat -c %Y "$HANDOFF_FILE" &>/dev/null; then
    last_modified=$(stat -c %Y "$HANDOFF_FILE")
  elif stat -f %m "$HANDOFF_FILE" &>/dev/null; then
    last_modified=$(stat -f %m "$HANDOFF_FILE")
  else
    last_modified=0
  fi

  now=$(date +%s)
  age_seconds=$(( now - last_modified ))
  age_hours=$(( age_seconds / 3600 ))
  age_minutes=$(( (age_seconds % 3600) / 60 ))

  if [ "$age_hours" -gt 0 ]; then
    age_display="${age_hours}h ${age_minutes}m ago"
  else
    age_display="${age_minutes}m ago"
  fi

  # Extract the work context line if available
  work_context=$(grep -A1 "## Work Context" "$HANDOFF_FILE" 2>/dev/null | tail -1 | sed 's/^- //' | head -c 200 || echo "")

  msg="A session handoff file exists at .claude/handoff/session-state.md (last updated $age_display)."
  if [ -n "$work_context" ]; then
    msg="$msg Previous work: $work_context."
  fi
  msg="$msg Run /handoff resume to continue where the previous session left off."

  printf '{"systemMessage": "%s"}\n' "$(echo "$msg" | sed 's/"/\\"/g')"
else
  echo "{}"
fi

# ── Watchdog auto-bootstrap ──────────────────────────────────────
# Ensure the watchdog daemon is running for this project.
# If no watchdog is alive, spawn one in the background.

HANDOFF_DIR="$PROJECT_DIR/.claude/handoff"
PID_FILE="$HANDOFF_DIR/watchdog.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG_SCRIPT="$SCRIPT_DIR/../../daemon/claude-watchdog.sh"

if [[ -x "$WATCHDOG_SCRIPT" ]]; then
  watchdog_running=false

  if [[ -f "$PID_FILE" ]]; then
    existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      watchdog_running=true
    fi
  fi

  if [[ "$watchdog_running" == false ]]; then
    mkdir -p "$HANDOFF_DIR"
    # Find the Claude process to attach to (walk up from hook's parent)
    claude_pid=""
    candidate="$PPID"
    while [[ -n "$candidate" ]] && (( candidate > 1 )); do
      if ps -p "$candidate" -o comm= 2>/dev/null | grep -q "claude"; then
        claude_pid="$candidate"
        break
      fi
      candidate="$(ps -p "$candidate" -o ppid= 2>/dev/null | tr -d ' ' || true)"
    done
    nohup "$WATCHDOG_SCRIPT" "$PROJECT_DIR" "$claude_pid" >> "$HANDOFF_DIR/watchdog.log" 2>&1 &
  fi
fi
