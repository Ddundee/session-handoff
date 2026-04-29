---
name: handoff
description: "This skill should be used when the user says 'handoff', 'save session', 'resume session', 'continue where I left off', 'switching accounts', 'session limit', 'pick up where I left off', 'save my progress', or 'handoff status'. Captures and restores ephemeral session state (monitors, background processes, cron jobs, work context, decisions) so work can continue seamlessly after switching Claude Code accounts or starting a new session."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(bash *)
  - Bash(ps *)
  - Bash(ss *)
  - Bash(lsof *)
  - Bash(git *)
  - Bash(mkdir *)
---

# Session Handoff

Capture and restore session state for seamless continuity across Claude Code sessions and account switches.

## Modes

Parse `$ARGUMENTS` to determine the mode:
- **No arguments, `save`, or empty**: Run **Save** mode
- **`resume`**: Run **Resume** mode
- **`status`**: Run **Status** mode

---

## Save Mode

Save mode creates a comprehensive snapshot of the current session's ephemeral state. Run this before switching accounts, or when approaching session limits.

### Procedure

1. **Discover live processes.** Execute the capture script:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/capture-state.sh"
   ```
   Parse the output to identify running monitors, dev servers, background processes, and git state.

2. **Read existing handoff file** at `.claude/handoff/session-state.md` if it exists. Look for `<!-- AUTO-CAPTURED -->` entries added by hooks during the session — these contain raw background process data that needs to be integrated into the structured format.

3. **Gather work context.** From the current conversation, identify:
   - The overall goal and current task
   - Which plan file is being executed (check `.claude/plans/` for recent files)
   - Task progress (use the TaskList and TaskGet tools if tasks are active)
   - Key decisions made during this session and their rationale
   - Any critical context a fresh session would need

4. **Write the handoff file.** Create or overwrite `.claude/handoff/session-state.md` following the template in `references/state-format.md`. Ensure the directory exists:
   ```bash
   mkdir -p .claude/handoff
   ```

   Critical sections to populate:
   - **Work Context**: Current goal, active task, plan phase
   - **Progress**: Checklist reflecting completed and pending work
   - **Active Monitors / Background Processes**: From capture script output, enriched with purpose from conversation context
   - **Cron Jobs**: Any CronCreate jobs active in this session (these are in-memory only and will be lost)
   - **Key Decisions**: Non-obvious choices with rationale
   - **Next Steps**: Ordered, actionable list — the first item is what the next session does immediately

5. **Confirm to the user.** Display a brief summary of what was saved:
   - Number of processes/monitors tracked
   - Current progress snapshot
   - The first Next Step (so they know what to expect on resume)
   - The file path

### Important Notes for Save

- Cron jobs created with CronCreate exist only in memory. Always capture their schedule and purpose in the handoff file — they cannot be recovered otherwise.
- Monitor tool sessions are ephemeral. Record the command, what is being watched, and why.
- If the user has not explicitly asked to save, still write a complete file. Partial saves create confusion on resume.
- Integrate any `<!-- AUTO-CAPTURED -->` hook data into the proper structured sections, then remove the raw markers.

---

## Resume Mode

Resume mode reads the handoff file and reconstructs the session context. Run this in a new session after switching accounts.

### Procedure

Follow the checklist in `references/resume-checklist.md`. The key steps:

1. **Read the handoff file** at `.claude/handoff/session-state.md`. If it does not exist, inform the user that no handoff state was found and suggest running `/handoff save` in their next session before switching.

2. **Assess live state.** Run the capture script to discover what is currently running:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/capture-state.sh"
   ```
   Compare against the handoff file to identify which services are down.

3. **Present a briefing.** Summarize for the user:
   - What was being worked on (goal and current task)
   - Progress (X of Y steps complete)
   - Which services need restarting
   - Git state (branch, uncommitted changes)
   - The immediate next step

4. **Offer to restart services.** For each dead monitor or background process listed in the handoff file, ask the user if it should be restarted using the original command.

5. **Recreate cron jobs.** For each cron job in the handoff file, offer to recreate it with CronCreate using the same schedule and prompt.

6. **Load plan context.** If a plan file is referenced, read it to understand the full implementation strategy, not just the next step.

7. **Confirm and begin.** Present the Next Steps list, ask the user if priorities have changed, then start executing.

8. **Update the handoff file.** Refresh the timestamp and session ID. Clear the Session End marker. The file is now being actively maintained again.

---

## Status Mode

Display the current tracking state without modifying anything.

### Procedure

1. **Read the handoff file** if it exists. Display its contents in a readable format.

2. **Run the capture script** to show live process state.

3. **Show the delta.** Highlight differences between what the handoff file tracks and what is actually running:
   - Processes listed in the file but not running (died or were stopped)
   - Processes running but not tracked in the file (started since last save)

---

## Continuous Tracking Guidance

During any session where handoff tracking is active (a `.claude/handoff/session-state.md` file exists), maintain it:

- **After starting a monitor or background process**: Update the corresponding table in the handoff file with the command, purpose, and PID/port.
- **After creating a cron job**: Add it to the Cron Jobs table.
- **After completing a significant task or plan phase**: Update the Progress checklist.
- **After making a key architectural or approach decision**: Add it to Key Decisions with rationale.
- **Periodically**: Refresh the Next Steps section to reflect the current state of work.

The PostToolUse hook automatically captures background Bash processes, but it only records the raw command. Enrich these entries with purpose and context when updating the file.
