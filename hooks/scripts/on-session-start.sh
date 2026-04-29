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
