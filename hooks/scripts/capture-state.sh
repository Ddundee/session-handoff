#!/usr/bin/env bash
set -euo pipefail

# Discover active processes, ports, and git state relevant to the current project.
# Outputs structured Markdown to stdout.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo ""
echo "<!-- AUTO-CAPTURED: process snapshot at $TIMESTAMP -->"
echo "### Process Snapshot ($TIMESTAMP)"
echo ""

# --- Listening Ports ---
echo "**Listening Ports:**"
found_ports=false
if command -v ss &>/dev/null; then
  while IFS= read -r line; do
    [ -n "$line" ] && echo "- \`$line\`" && found_ports=true
  done < <(ss -tlnp 2>/dev/null | grep -E ':(3000|3001|4000|5000|5173|8000|8080|8443|9000) ' || true)
elif command -v lsof &>/dev/null; then
  while IFS= read -r line; do
    [ -n "$line" ] && echo "- \`$line\`" && found_ports=true
  done < <(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -E ':(3000|3001|4000|5000|5173|8000|8080|8443|9000) ' || true)
fi
$found_ports || echo "- None detected"

# --- Active Monitors ---
echo ""
echo "**Active Monitors:**"
found_monitors=false
while IFS= read -r line; do
  [ -n "$line" ] && echo "- \`$line\`" && found_monitors=true
done < <(ps aux 2>/dev/null | grep -E '(tail -[fF]|inotifywait|fswatch|entr )' | grep -v grep || true)
$found_monitors || echo "- None detected"

# --- Background Node/Python/Dev Processes ---
echo ""
echo "**Dev Processes:**"
found_dev=false
while IFS= read -r line; do
  [ -n "$line" ] && echo "- \`$line\`" && found_dev=true
done < <(ps aux 2>/dev/null | grep -E '(node |python3? |ruby |go run |cargo run |npm |npx |yarn |pnpm |vite|webpack|next dev|flask|uvicorn|gunicorn)' | grep -v grep | head -20 || true)
$found_dev || echo "- None detected"

# --- Git State ---
echo ""
echo "**Git State:**"
if [ -d "$PROJECT_DIR/.git" ] || git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  branch=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "detached")
  modified=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last_commit=$(git -C "$PROJECT_DIR" log --oneline -1 2>/dev/null || echo "no commits")
  echo "- Branch: \`$branch\`"
  echo "- Modified files: $modified"
  echo "- Last commit: \`$last_commit\`"

  # Worktrees
  worktree_count=$(git -C "$PROJECT_DIR" worktree list 2>/dev/null | wc -l | tr -d ' ')
  if [ "$worktree_count" -gt 1 ]; then
    echo "- Active worktrees:"
    git -C "$PROJECT_DIR" worktree list 2>/dev/null | while IFS= read -r wt; do
      echo "  - \`$wt\`"
    done
  fi
else
  echo "- Not a git repository"
fi
