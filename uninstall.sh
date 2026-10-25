#!/bin/bash
# Uninstall the clipboard-sync agent for one or more macOS user accounts.
#
# Usage:
#   ./uninstall.sh                        remove the current user's agent
#   sudo ./uninstall.sh alice bob         remove agents of other local accounts
#   sudo ./uninstall.sh --purge alice bob ... and also delete the shared board
set -eu

LABEL="com.local.clipboard-sync"
SYNC_DIR="/Users/Shared/.clipboard-sync"
PURGE=0
if [ "${1:-}" = "--purge" ]; then
  PURGE=1
  shift
fi

remove_for() { # $1 = username
  U="$1"
  N=$(id -u "$U")
  PLIST="/Users/$U/Library/LaunchAgents/$LABEL.plist"
  if ps axo user,command | awk -v u="$U" '$1==u && /loginwindow/' | grep -q .; then
    if [ "$(whoami)" = "root" ]; then
      launchctl asuser "$N" launchctl bootout "gui/$N/$LABEL" 2>/dev/null || true
    else
      launchctl bootout "gui/$N/$LABEL" 2>/dev/null || true
    fi
  fi
  if rm -f "$PLIST" 2>/dev/null; then
    echo "  $U: agent removed"
  else
    echo "  $U: could not remove $PLIST (need sudo for other users)"
  fi
}

if [ "$(whoami)" = "root" ]; then
  [ $# -ge 1 ] || { echo "usage: sudo ./uninstall.sh [--purge] <username> [more...]  (or run without sudo for the current user)"; exit 1; }
  for U in "$@"; do
    id "$U" >/dev/null 2>&1 || { echo "error: no such user: $U" >&2; exit 1; }
    remove_for "$U"
  done
  if [ "$PURGE" -eq 1 ]; then
    rm -rf "$SYNC_DIR"
    rm -f /Users/Shared/clipboard-sync-agent.sh
    echo "shared board and agent script removed"
  fi
else
  remove_for "$(whoami)"
  echo "(shared board kept — other accounts may still use it; run 'sudo ./uninstall.sh --purge <user>' to delete)"
fi
