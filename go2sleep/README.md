# Go2Sleep 🌙

A lightweight macOS background agent that tracks how long you watch YouTube Shorts in Firefox late at night — and locks your screen when you've had enough.

---

## How It Works

A `launchd` agent runs `go2sleep.sh` every 60 seconds. Each time it fires, it reads Firefox's live session store to check whether any tab is open on `youtube.com/shorts`. If so, it accumulates time and — depending on how long you've been watching — warns you or locks your screen.

```
Every 60 seconds (via launchd)
        │
        ▼
  In the enforcement window? (default: midnight – 4 AM)
        │ No → decay the counter slightly, then exit
        │ Yes
        ▼
  In a post-lockout cooldown?
        │ Yes → if Shorts still open, close the tab, then exit
        │ No
        ▼
  check_shorts.py → Shorts tab open in Firefox?
        │ No  → if idle ≥ 10 min, decay counter
        │ Yes → add 60s to cumulative counter
        │           ├─ ≥ 5 min  → warning notification
        │           ├─ ≥ 8 min  → final warning notification
        │           └─ ≥ 10 min → close tab, lock screen, start 30-min cooldown
```

---

## Files

| File | Purpose |
|---|---|
| `go2sleep.sh` | Main script. Tracks watch time, sends notifications, and locks the screen. |
| `check_shorts.py` | Reads Firefox's compressed session file to detect open Shorts tabs. |
| `com_user_go2sleep.plist` | `launchd` agent definition — runs `go2sleep.sh` every 60 seconds. |
| `com_user_shortsguard.plist` | Alternate/secondary `launchd` plist (same role). |
| `setup.sh` | One-time installer. Run this first. |

---

## Requirements

- macOS
- Firefox
- Python 3 (pre-installed on macOS)
- The [`lz4`](https://pypi.org/project/lz4/) Python package (installed automatically by `setup.sh`)

---

## Installation

1. Put all files in the same folder, e.g. `~/scripts/go2sleep/`.
2. Open Terminal, `cd` into that folder, and run:

```bash
bash setup.sh
```

`setup.sh` will:
- Install the `lz4` Python dependency via `pip`
- Make `go2sleep.sh` and `check_shorts.py` executable
- Write the `launchd` plist to `~/Library/LaunchAgents/` with the correct path
- Load the agent so it starts immediately (and on every login)

3. **Grant Accessibility permission** — this is required for the script to close Firefox tabs:
   > System Settings → Privacy & Security → Accessibility → add Terminal (or your shell)

That's it. The agent will run silently in the background from now on.

---

## Default Settings

These are all defined at the top of `go2sleep.sh` and can be edited freely.

| Setting | Default | Description |
|---|---|---|
| `NIGHT_START` | `0` (midnight) | Start of enforcement window |
| `NIGHT_END` | `4` (4 AM) | End of enforcement window |
| `WARN1_SECS` | `300` (5 min) | First warning notification |
| `WARN2_SECS` | `480` (8 min) | Second warning notification |
| `LIMIT_SECS` | `600` (10 min) | Watch time before lockout |
| `COOLDOWN_SECS` | `1800` (30 min) | How long the screen stays locked |
| `DECAY_SECS` | `30` | Seconds subtracted per idle minute (rewards breaks) |

Outside the enforcement window, the counter decays by `DECAY_SECS` every time the agent fires — so stepping away resets your progress.

---

## Notifications

| When | Message |
|---|---|
| 5 minutes watched | 📵 Check-in — time so far + seconds remaining |
| 8 minutes watched | ⚠️ Final warning — seconds until lockout |
| Limit reached | 🔒 Screen locked — back in 30 minutes |
| Tab open during cooldown | 🔒 Tab closed automatically |

---

## State & Logs

- **State file:** `~/.shorts_state` — stores the cumulative watch counter and cooldown expiry. Delete it to reset.
- **Log file:** `go2sleep.log` in the same folder as the scripts.

---

## Uninstalling

```bash
launchctl unload ~/Library/LaunchAgents/com.user.go2sleep.plist
rm ~/Library/LaunchAgents/com.user.go2sleep.plist
```

You can then delete the script folder and `~/.shorts_state`.

---

## How `check_shorts.py` Works

Firefox stores its open tabs in a compressed binary file (`recovery.jsonlz4`) inside your Firefox profile directory. This file uses a custom format called **mozlz4** — standard LZ4 compression with an 8-byte `mozLz40\0` magic header prepended.

`check_shorts.py` finds this file, strips the header, decompresses the rest with the `lz4` library, parses the JSON session data, and checks whether any tab's current URL contains `youtube.com/shorts`.

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | Shorts tab found |
| `1` | No Shorts tab found |
| `2` | `lz4` module not installed |
| `3` | Firefox not installed |