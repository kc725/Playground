#!/bin/bash
# ═══════════════════════════════════════════════════════
#  setup.sh — One-time installer for Go2Sleep
#  Run once from Terminal: bash setup.sh
# ═══════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.user.go2sleep.plist"
PLIST_SRC="$SCRIPT_DIR/$PLIST_NAME"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo ""
echo "  ░░ Go2Sleep Setup ░░"
echo ""

# 1. Install lz4 Python dependency
echo "→ Installing Python dependency (lz4)..."
if python3 -m pip install lz4 --quiet --user; then
    echo "  ✓ lz4 installed."
else
    echo "  ✗ pip install failed. Try: python3 -m pip install lz4 --user"
    exit 1
fi

# 2. Make scripts executable
echo "→ Setting permissions..."
chmod +x "$SCRIPT_DIR/go2sleep.sh"
chmod +x "$SCRIPT_DIR/check_shorts.py"
echo "  ✓ Done."

# 3. Write the plist with the real path substituted in
echo "→ Installing launchd agent..."
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|SHORTS_GUARD_PATH|$SCRIPT_DIR|g" "$PLIST_SRC" > "$PLIST_DST"
echo "  ✓ Plist written to $PLIST_DST"

# 4. Load (or reload) the agent
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
echo "  ✓ Agent loaded."

# 5. Grant Accessibility permission reminder
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚠️  One manual step required:"
echo "  Go to System Settings → Privacy & Security → Accessibility"
echo "  and add Terminal (or your shell) to the allowed apps."
echo "  This lets the script close Firefox tabs."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ✅ Go2Sleep is running!"
echo ""
echo "  Settings (edit go2sleep.sh to change):"
echo "    Active window : Midnight – 4 AM"
echo "    Limit         : 10 minutes"
echo "    Warnings      : at 5 min, 8 min"
echo "    Cooldown      : 30 min after lockout"
echo ""
echo "  Logs: $SCRIPT_DIR/go2sleep.log"
echo ""
echo "  To uninstall:"
echo "    launchctl unload $PLIST_DST"
echo "    rm $PLIST_DST"
echo ""
