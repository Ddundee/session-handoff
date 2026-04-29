#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook (Bash matcher): log background processes to the handoff file.
# Reads tool input JSON from stdin. Exits fast if not a background process.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HANDOFF_FILE="$PROJECT_DIR/.claude/handoff/session-state.md"

# Only act if handoff tracking is active
if [ ! -f "$HANDOFF_FILE" ]; then
  echo "{}"
  exit 0
fi

# Read tool input from stdin
input=$(cat)

# Check if this was a background process
run_bg=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('run_in_background','false'))" 2>/dev/null || echo "false")

if [ "$run_bg" != "true" ] && [ "$run_bg" != "True" ]; then
  echo "{}"
  exit 0
fi

# Extract command
command_str=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command','unknown'))" 2>/dev/null || echo "unknown")

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append to handoff file
{
  echo ""
  echo "<!-- AUTO-CAPTURED: background process at $timestamp -->"
  echo "- \`$command_str\` (background, started $timestamp)"
} >> "$HANDOFF_FILE"

printf '{"systemMessage": "Background process logged to handoff file: %s"}\n' "$(echo "$command_str" | head -c 100 | sed 's/"/\\"/g')"
