#!/bin/bash
# Install the clipboard-sync launchd agent for one or more macOS user accounts.
#
# Usage:
#   ./install.sh                  install for the current user (no sudo needed)
#   sudo ./install.sh alice bob   additionally install for other local accounts
#
# Shared assets (agent script + exchange dir) live under /Users/Shared and are
# installed once; every account runs the same agent against the same board.
set -eu

SELF="$(cd "$(dirname "$0")" && pwd)"
AGENT_SRC="$SELF/clipboard-sync.sh"
AGENT_DST="/Users/Shared/clipboard-sync-agent.sh"
SYNC_DIR="/Users/Shared/.clipboard-sync"
LABEL="com.local.clipboard-sync"

logged_in() { ps axo user,command | awk -v u="$1" '$1==u && /loginwindow/' | grep -q .; }

install_shared_assets() {
  mkdir -p "$SYNC_DIR"
  chgrp staff "$SYNC_DIR" 2>/dev/null || true
  chmod 2770 "$SYNC_DIR" 2>/dev/null || true
  if [ ! -w "$SYNC_DIR" ]; then
    echo "error: cannot write $SYNC_DIR (re-run with sudo)" >&2
    exit 1
  fi
  cp "$AGENT_SRC" "$AGENT_DST"
  chmod 755 "$AGENT_DST"
}

write_plist() { # $1 = username
  U="$1"
  PLIST="/Users/$U/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "/Users/$U/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$AGENT_DST</string>
    <string>$U</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF
  echo "$PLIST"
}

start_agent() { # $1 = username, $2 = plist
  U="$1"
  PLIST="$2"
  N=$(id -u "$U")
  if ! logged_in "$U"; then
    echo "  $U: not logged in — agent starts automatically at next login"
    return 0
  fi
  if [ "$(whoami)" = "root" ]; then
    launchctl asuser "$N" launchctl bootout "gui/$N/$LABEL" 2>/dev/null || true
    launchctl asuser "$N" launchctl bootstrap "gui/$N" "$PLIST"
  else
    launchctl bootout "gui/$N/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$N" "$PLIST"
  fi
  echo "  $U: agent started"
}

if [ "$(whoami)" = "root" ]; then
  [ $# -ge 1 ] || { echo "usage: sudo ./install.sh <username> [more...]  (or run without sudo to install for the current user)"; exit 1; }
  install_shared_assets
  for U in "$@"; do
    id "$U" >/dev/null 2>&1 || { echo "error: no such user: $U" >&2; exit 1; }
    PLIST=$(write_plist "$U")
    chown "$U:staff" "$PLIST"
    start_agent "$U" "$PLIST"
  done
else
  install_shared_assets
  PLIST=$(write_plist "$(whoami)")
  start_agent "$(whoami)" "$PLIST"
fi

echo "Done. Copy text in one logged-in account and it appears in the others within ~1-2s."
