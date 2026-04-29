#!/usr/bin/env bash
set -euo pipefail

# Stop hook: final state capture before session ends.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HANDOFF_FILE="$PROJECT_DIR/.claude/handoff/session-state.md"

# Only act if handoff tracking is active
if [ ! -f "$HANDOFF_FILE" ]; then
  echo "{}"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Run capture-state for a final process snapshot
if [ -x "$SCRIPT_DIR/capture-state.sh" ]; then
  {
    echo ""
    echo "---"
    echo "## Session End ($TIMESTAMP)"
    echo ""
    bash "$SCRIPT_DIR/capture-state.sh" 2>/dev/null || true
  } >> "$HANDOFF_FILE"
fi

printf '{"systemMessage": "Session state captured to handoff file before exit."}\n'
