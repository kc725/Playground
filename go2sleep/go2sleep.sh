#!/bin/bash
# ══════════════════════════════════════════════════════════════
#  go2sleep.sh — YouTube Shorts Night Guard for macOS
#  Runs every 60s via launchd. Tracks Shorts watch time in
#  Firefox and locks your screen when you've had enough.
# ═══════════════════════════════════════════════════════════════

# ── Configuration (edit these) ─────────────────────────────────
NIGHT_START=0      # Start hour of enforcement window (0 = midnight)
NIGHT_END=4        # End hour (exclusive, 4 = until 3:59 AM)
WARN1_SECS=300     # First warning at 5 minutes
WARN2_SECS=480     # Second warning at 8 minutes
LIMIT_SECS=600     # Lockout at 10 minutes
COOLDOWN_SECS=1800 # 30-minute cooldown after a lockout
DECAY_SECS=30      # Seconds to subtract per idle minute (rewards breaks)
# ───────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$HOME/.shorts_state"
PYTHON_SCRIPT="$SCRIPT_DIR/check_shorts.py"
LOG="$SCRIPT_DIR/go2sleep.log"


# ── State helpers ───────────────────────────────────────────────

get_state() {
    local key="$1" default="$2" val
    if [[ -f "$STATE_FILE" ]]; then
        val=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

set_state() {
    local key="$1" value="$2" tmp
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "${key}=${value}" > "$STATE_FILE"
        return
    fi
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        tmp=$(mktemp)
        sed "s|^${key}=.*|${key}=${value}|" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    else
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}


# ── Actions ─────────────────────────────────────────────────────

notify() {
    local title="$1" message="$2"
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Basso\"" 2>/dev/null
}

lock_screen() {
    log "Locking screen."
    /System/Library/CoreServices/Menu\ Extras/User.lc/Contents/Resources/CGSession -suspend 2>/dev/null
}

# Close any Firefox tabs whose title contains "YouTube".
# Firefox doesn't expose tab URLs via AppleScript, so we use
# the accessibility API to find tabs by page title.
close_shorts_tab() {
    log "Attempting to close Shorts tab in Firefox..."
    osascript 2>/dev/null <<'APPLESCRIPT'
tell application "Firefox" to activate
delay 0.6
tell application "System Events"
    tell process "Firefox"
        repeat with w in windows
            try
                -- Tab bar lives inside nested group elements; depth varies by Firefox version.
                -- We try a few common paths.
                set candidates to {}
                try
                    set candidates to buttons of group 1 of group 1 of group 1 of w
                end try
                if (count of candidates) = 0 then
                    try
                        set candidates to buttons of group 1 of group 1 of w
                    end try
                end if
                repeat with btn in candidates
                    try
                        if (description of btn) contains "YouTube" then
                            perform action "AXPress" of btn
                            delay 0.25
                            keystroke "w" using {command down}
                            delay 0.1
                        end if
                    end try
                end repeat
            end try
        end repeat
    end tell
end tell
APPLESCRIPT
}


# ── Time window check ───────────────────────────────────────────

current_hour=$(date +%-H)   # %-H strips leading zero on macOS
now=$(date +%s)

in_window=false
if [[ $current_hour -ge $NIGHT_START && $current_hour -lt $NIGHT_END ]]; then
    in_window=true
fi


# ── Outside enforcement window: gently decay counter ───────────

if [[ "$in_window" == false ]]; then
    seconds=$(get_state "seconds" "0")
    if [[ $seconds -gt 0 ]]; then
        new=$(( seconds - DECAY_SECS ))
        [[ $new -lt 0 ]] && new=0
        set_state "seconds" "$new"
        log "Outside window. Counter decayed to ${new}s."
    fi
    exit 0
fi


# ── Cooldown check ──────────────────────────────────────────────

cooldown_until=$(get_state "cooldown_until" "0")
if [[ $now -lt $cooldown_until ]]; then
    remaining_mins=$(( (cooldown_until - now) / 60 ))
    shorts_status=$(python3 "$PYTHON_SCRIPT" 2>/dev/null)
    if [[ "$shorts_status" == "found" ]]; then
        log "Shorts detected during cooldown (${remaining_mins}m left). Closing tab."
        notify "🔒 Still Cooling Down" "Shorts blocked for ${remaining_mins} more minutes. Closing tab..."
        close_shorts_tab
    fi
    exit 0
fi


# ── Check for Shorts ────────────────────────────────────────────

shorts_status=$(python3 "$PYTHON_SCRIPT" 2>/dev/null)

if [[ "$shorts_status" == "lz4_missing" ]]; then
    notify "Go2Sleep ⚠️" "Missing dependency. Run setup.sh to fix."
    log "ERROR: lz4 Python module not installed."
    exit 1
fi

seconds=$(get_state "seconds" "0")
last_seen=$(get_state "last_seen" "0")


# ── Shorts detected ─────────────────────────────────────────────

if [[ "$shorts_status" == "found" ]]; then
    seconds=$(( seconds + 60 ))
    set_state "seconds" "$seconds"
    set_state "last_seen" "$now"
    log "Shorts active. Cumulative: ${seconds}s / ${LIMIT_SECS}s."

    if [[ $seconds -ge $LIMIT_SECS ]]; then
        # ── LOCKOUT ──
        mins=$(( LIMIT_SECS / 60 ))
        notify "🔒 Go2Sleep Locked" "That's ${mins} minutes of Shorts tonight. Screen locked — back in 30 min."
        log "Limit reached. Closing tab and locking screen."
        close_shorts_tab
        sleep 1
        lock_screen
        set_state "cooldown_until" "$(( now + COOLDOWN_SECS ))"
        set_state "seconds" "0"

    elif [[ $seconds -ge $WARN2_SECS ]]; then
        remaining=$(( LIMIT_SECS - seconds ))
        notify "⚠️ Last Warning (Go2Sleep)" "2 minutes left before Shorts lockout (${remaining}s remaining tonight)."

    elif [[ $seconds -ge $WARN1_SECS ]]; then
        remaining=$(( LIMIT_SECS - seconds ))
        notify "📵 Go2Sleep Check-in" "5 minutes of Shorts so far. ${remaining}s until lockout."
    fi


# ── Not watching ────────────────────────────────────────────────

else
    # Reward breaks: if Shorts hasn't been seen in 10+ minutes, decay.
    if [[ $last_seen -gt 0 ]]; then
        idle=$(( now - last_seen ))
        if [[ $idle -ge 600 && $seconds -gt 0 ]]; then
            new=$(( seconds - DECAY_SECS ))
            [[ $new -lt 0 ]] && new=0
            set_state "seconds" "$new"
            log "No Shorts for ${idle}s. Counter decayed to ${new}s."
        fi
    fi
fi
