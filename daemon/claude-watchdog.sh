#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
PROJECT_DIR="${1:-$PWD}"
ATTACH_PID="${2:-}"
HANDOFF_DIR="$PROJECT_DIR/.claude/handoff"
PID_FILE="$HANDOFF_DIR/watchdog.pid"
LOG_FILE="$HANDOFF_DIR/watchdog.log"

MAX_CRASHES=5
CRASH_WINDOW=600  # 10 minutes in seconds
BACKOFF_DELAYS=(2 5 10 30 60)
STABLE_RESET=600  # reset crash counter after 10 min stable

# ── Logging ────────────────────────────────────────────────────
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $*" >> "$LOG_FILE"
}

# ── Desktop notification (best-effort) ─────────────────────────
notify() {
    local title="$1"
    local body="$2"
    if command -v notify-send &>/dev/null; then
        notify-send "$title" "$body" 2>/dev/null || true
    fi
    log "ALERT: $title — $body"
}

# ── Cleanup on exit ───────────────────────────────────────────
cleanup() {
    log "Watchdog shutting down (PID $$)"
    rm -f "$PID_FILE"
    if [[ -n "${CLAUDE_PID:-}" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
        log "Forwarding SIGTERM to Claude (PID $CLAUDE_PID)"
        kill -TERM "$CLAUDE_PID" 2>/dev/null || true
        wait "$CLAUDE_PID" 2>/dev/null || true
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP EXIT

# ── Validate project directory ─────────────────────────────────
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: project directory does not exist: $PROJECT_DIR" >&2
    exit 1
fi

# ── Ensure handoff directory exists ────────────────────────────
mkdir -p "$HANDOFF_DIR"

# ── Check for existing watchdog ────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Watchdog already running (PID $existing_pid) for $PROJECT_DIR" >&2
        exit 0
    fi
    rm -f "$PID_FILE"
fi

# ── Write PID file ─────────────────────────────────────────────
echo $$ > "$PID_FILE"
log "Watchdog started (PID $$) for project: $PROJECT_DIR"
log "Config: max_crashes=$MAX_CRASHES crash_window=${CRASH_WINDOW}s"

# ── Attach mode: monitor existing Claude session first ─────────
# When spawned from SessionStart hook, Claude is already running.
# Wait for that session to exit before entering the restart loop.
if [[ -n "$ATTACH_PID" ]]; then
    if kill -0 "$ATTACH_PID" 2>/dev/null; then
        log "Attach mode: monitoring existing Claude session (PID $ATTACH_PID)"
        while kill -0 "$ATTACH_PID" 2>/dev/null; do
            sleep 2
        done
        log "Existing Claude session (PID $ATTACH_PID) has exited"
    else
        log "Attach PID $ATTACH_PID is not running, entering restart loop"
    fi
fi

# ── Crash tracking ─────────────────────────────────────────────
declare -a crash_timestamps=()
crash_count=0

record_crash() {
    local now
    now="$(date +%s)"
    crash_timestamps+=("$now")
    crash_count=$((crash_count + 1))

    # Prune timestamps outside the crash window
    local cutoff=$((now - CRASH_WINDOW))
    local new_timestamps=()
    for ts in "${crash_timestamps[@]}"; do
        if (( ts >= cutoff )); then
            new_timestamps+=("$ts")
        fi
    done
    crash_timestamps=("${new_timestamps[@]}")
    crash_count=${#crash_timestamps[@]}
}

is_crash_loop() {
    (( crash_count >= MAX_CRASHES ))
}

get_backoff_delay() {
    local idx=$((crash_count - 1))
    if (( idx >= ${#BACKOFF_DELAYS[@]} )); then
        idx=$(( ${#BACKOFF_DELAYS[@]} - 1 ))
    fi
    echo "${BACKOFF_DELAYS[$idx]}"
}

maybe_reset_crash_counter() {
    local now
    now="$(date +%s)"
    if (( ${#crash_timestamps[@]} == 0 )); then
        return
    fi
    local latest="${crash_timestamps[-1]}"
    if (( now - latest >= STABLE_RESET )); then
        crash_timestamps=()
        crash_count=0
        log "Crash counter reset (stable for ${STABLE_RESET}s)"
    fi
}

# ── Main loop ──────────────────────────────────────────────────
CLAUDE_PID=""

while true; do
    maybe_reset_crash_counter

    log "Starting Claude session in $PROJECT_DIR"

    cd "$PROJECT_DIR"
    claude --dangerously-skip-permissions -p "I've been restarted by the watchdog daemon after a session interruption. Run /handoff resume to restore session context." &
    CLAUDE_PID=$!
    log "Claude started (PID $CLAUDE_PID)"

    # Wait for Claude to exit
    set +e
    wait "$CLAUDE_PID"
    exit_code=$?
    set -e
    CLAUDE_PID=""

    log "Claude exited with code $exit_code"

    # Check if watchdog was told to stop (cleanup trap sets this)
    if [[ ! -f "$PID_FILE" ]]; then
        log "PID file removed, exiting"
        exit 0
    fi

    if (( exit_code != 0 )); then
        record_crash
        log "Crash detected (count: $crash_count in window)"

        if is_crash_loop; then
            notify "Claude Watchdog — Crash Loop Detected" \
                "Claude has crashed $crash_count times in $(( CRASH_WINDOW / 60 )) minutes in $PROJECT_DIR. Watchdog is stopping. Check $LOG_FILE for details. You may want to manually save your session state."
            log "CRASH LOOP: Stopping watchdog. Manual intervention required."
            log "To manually save state, start Claude and run: /handoff save"
            log "To restart the watchdog, remove $PID_FILE and start a new Claude session."
            rm -f "$PID_FILE"
            exit 1
        fi

        delay="$(get_backoff_delay)"
        log "Backing off for ${delay}s before restart (crash $crash_count/$MAX_CRASHES)"
        notify "Claude Session Crashed" \
            "Restarting in ${delay}s (attempt $crash_count/$MAX_CRASHES) — $PROJECT_DIR"
        sleep "$delay"
    else
        # Clean exit — short delay before restart
        log "Clean exit, restarting in 2s"
        sleep 2
    fi
done
