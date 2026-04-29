# Resume Checklist

Follow these steps when resuming from a handoff state file. Execute them in order.

## 1. Load Context
- Read `.claude/handoff/session-state.md` completely.
- Read the plan file referenced in the Work Context section (if any).
- Scan the project's memory directory for relevant memories.

## 2. Assess Live State
- Run `capture-state.sh` to discover what processes are currently running.
- Compare live state against the handoff file's Active Monitors and Background Processes sections.
- Check git branch and working tree status — confirm they match what the handoff file expects.

## 3. Present Summary to User
Format a concise briefing:
```
Resuming from handoff (saved <timestamp>):
- Goal: <work context goal>
- Progress: <X of Y steps complete>
- Services down: <list of processes that need restarting>
- Git: on branch <branch>, <N> uncommitted changes
- Next step: <first item from Next Steps>
```

## 4. Restart Services
For each service listed in Active Monitors and Background Processes that is not currently running:
- Ask the user if they want it restarted.
- If yes, start it using the same command from the handoff file.
- Log the new PID to the handoff file.

## 5. Recreate Cron Jobs
For each entry in the Cron Jobs section:
- Recreate using CronCreate with the same schedule and prompt.

## 6. Verify Environment
- Confirm key environment variables are set.
- Confirm working directory matches.
- If the handoff notes mention required setup (API keys, config), flag those to the user.

## 7. Confirm and Begin
- Present the Next Steps list to the user.
- Ask if priorities have changed or if anything needs updating.
- Begin executing from the first Next Step.

## 8. Update Handoff File
- Update the `last_updated` timestamp and `previous_session_id`.
- Clear the `## Session End` section if present — the session is now active.
- Continue maintaining the file throughout the new session.
