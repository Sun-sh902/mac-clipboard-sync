#!/bin/bash
# Clipboard sync agent for macOS: mirrors one user's TEXT clipboard into
# /Users/Shared/.clipboard-sync so logged-in accounts on the same machine
# stay consistent. Managed as a per-user launchd agent (RunAtLoad, KeepAlive).
U="${1:-$(whoami)}"
DIR="/Users/Shared/.clipboard-sync"
BOARD="$DIR/board"
META="$DIR/board.meta"
LOCAL="/tmp/.cb-local-$U"

[ -w "$DIR" ] || exit 1

md5() { /sbin/md5 -q "$1" 2>/dev/null || echo none; }

# Startup: adopt the current board so a fresh login session is consistent.
if [ -s "$BOARD" ]; then
  pbpaste > "$LOCAL" 2>/dev/null
  [ -s "$LOCAL" ] || cat "$BOARD" | pbcopy
fi

LASTL=""; LASTB=""
while true; do
  pbpaste > "$LOCAL" 2>/dev/null || { sleep 1; continue; }
  L=$(md5 "$LOCAL")
  B=$(md5 "$BOARD")
  if [ -z "$LASTL" ]; then
    LASTL="$L"; LASTB="$B"; sleep 1; continue
  fi
  if [ ! -s "$LOCAL" ] && [ -s "$BOARD" ]; then
    # Non-text clipboard content (image/file) shows as empty text here.
    # Publish nothing and pull nothing, to avoid wiping the text board.
    sleep 1; continue
  fi
  if [ "$L" != "$LASTL" ] && [ "$L" != "$B" ]; then
    # This user's clipboard changed -> publish
    TMPB="$DIR/.board.tmp.$$"
    cp "$LOCAL" "$TMPB" && chmod 660 "$TMPB" && mv "$TMPB" "$BOARD"
    printf '%s|%s\n' "$U" "$(date +%s)" > "$DIR/.meta.tmp.$$"
    chmod 664 "$DIR/.meta.tmp.$$" && mv "$DIR/.meta.tmp.$$" "$META"
    LASTL="$L"; LASTB="$L"
  elif [ "$B" != "$LASTB" ] && [ "$B" != "$L" ]; then
    # Board changed by another user -> pull
    cat "$BOARD" | pbcopy
    LASTL="$B"; LASTB="$B"
  else
    LASTL="$L"
    LASTB="$B"
  fi
  sleep 1
done
