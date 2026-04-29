# Session State File Format

The handoff state file lives at `.claude/handoff/session-state.md` in the project directory. Follow this format exactly when writing or updating the file.

## Template

```markdown
---
last_updated: <ISO 8601 timestamp>
previous_session_id: <session uuid if known>
project: <absolute project path>
---

# Session Handoff State

## Work Context
- **Current goal**: <one-line description of the overall objective>
- **Current task**: <what is actively being worked on right now>
- **Phase**: <current phase/step in the plan, if executing a plan>
- **Plan file**: <path to .claude/plans/xxx.md, or "none">

## Progress
- [x] Completed step with brief description
- [x] Another completed step
- [ ] **Current step** (IN PROGRESS — describe where it stands)
- [ ] Upcoming step
- [ ] Another upcoming step

## Active Monitors
| Command | Purpose | Started |
|---------|---------|---------|
| `tail -f /path/to/log` | Watching for deploy errors | 2026-04-29T10:00:00Z |
| `npm run dev` | Dev server on :3000 | 2026-04-29T09:30:00Z |

## Background Processes
| Command | PID | Port | Purpose | Started |
|---------|-----|------|---------|---------|
| `npm run build -- --watch` | 45678 | — | Incremental build watcher | 2026-04-29T10:15:00Z |
| `python server.py` | 45690 | 8000 | API server for testing | 2026-04-29T10:20:00Z |

## Cron Jobs
| Schedule | Command/Prompt | Purpose |
|----------|---------------|---------|
| Every 5m | `curl localhost:3000/health` | Health check during testing |
| Every 10m | "Check build status and report" | CI monitoring loop |

## Key Decisions
- **<Decision>**: <Rationale>. Example: "Chose SQLite over Postgres for local dev because the test suite needs to be self-contained."
- **<Decision>**: <Rationale>.

## Environment
- **Working directory**: /path/to/project
- **Git branch**: `feature/branch-name`
- **Uncommitted changes**: <count> files (<brief summary>)
- **Key env vars**: `VAR1=value1`, `VAR2=value2`
- **Active worktrees**: <path and branch, or "none">

## Next Steps
1. <Immediate next action — the first thing the resuming session should do>
2. <Following action>
3. <Following action>

## Notes
<Any critical context, gotchas, or warnings the next session needs. Include things like:
- Partial implementations that compile but aren't complete
- Known issues discovered but not yet fixed
- External dependencies or blockers
- Credentials or API keys that need to be set up>
```

## Guidelines

- Keep each section concise. The goal is fast orientation, not a novel.
- Omit empty sections rather than writing "None" repeatedly — but always include Work Context, Progress, and Next Steps.
- The Progress section should mirror the task list or plan steps. Use checkboxes for scanability.
- For Key Decisions, only record choices that would surprise someone picking up the work cold. Skip obvious ones.
- Next Steps should be actionable and ordered. The first item is what the resuming session does immediately.
- Auto-captured data from hooks (marked with `<!-- AUTO-CAPTURED -->`) should be integrated into the proper sections during a `/handoff save` and the raw markers removed.
