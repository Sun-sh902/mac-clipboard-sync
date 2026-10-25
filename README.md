# mac-clipboard-sync

**Clipboard sync when you switch Mac users.** Copy text in one macOS account,
switch to another user, paste — the clipboard is already there. While both
accounts are logged in, anything you copy in one shows up in the other within
~1–2 seconds, and a freshly logged-in account adopts the latest content
automatically.

macOS gives every login session its own isolated pasteboard, so nothing you
copy carries over between local accounts (work / personal / review, fast user
switching). This project fixes that with ~60 lines of shell and a launchd agent.

```
┌──────────────┐   publish/pull    ┌─────────────────────────────┐   publish/pull    ┌──────────────┐
│  Account A   │ ◄───────────────► │  /Users/Shared/.clipboard-  │ ◄───────────────► │  Account B   │
│  launchd     │    every 1s       │  sync/board  (text)         │    every 1s       │  launchd     │
│  agent       │                   │  board.meta (who/when)      │                   │  agent       │
└──────────────┘                   └─────────────────────────────┘                   └──────────────┘
```

Copy text in one logged-in account and it appears in the others within
~1–2 seconds. Survives reboots; a freshly logged-in account automatically
adopts the latest board content.

## Requirements

- macOS (Apple Silicon or Intel), multiple local user accounts
- All participating accounts are in the default `staff` group (the macOS default)
- No third-party dependencies — only `pbcopy` / `pbpaste` / `launchd`

## Install

Two steps. Step 1 installs the agent for the account you are in right now;
step 2 adds every other local account you want to sync with.

```bash
git clone https://github.com/Sun-sh902/mac-clipboard-sync.git
cd mac-clipboard-sync

# Step 1 — install for the current account (no sudo needed)
./install.sh

# Step 2 — install for the other local accounts (needs sudo, run from any admin account)
# Replace <username> with each account's short name — list them with `ls /Users`
sudo ./install.sh <username> [<username> ...]
```

What the installer sets up:

| Path | Purpose |
|---|---|
| `/Users/Shared/clipboard-sync-agent.sh` | the agent script (installed once, shared by all accounts) |
| `/Users/Shared/.clipboard-sync/` | the exchange dir: `board` + `board.meta`, mode `2770 staff` |
| `~/Library/LaunchAgents/com.local.clipboard-sync.plist` | per-user launchd agent (RunAtLoad, KeepAlive, Background priority) |

Accounts that are logged in start syncing immediately; accounts that are not
logged in start automatically at their next login. Everything survives
reboots — the agents are plain launchd agents, no extra setup needed.

## Usage

Day to day there is nothing to learn — keep using ⌘C / ⌘V as usual:

1. Copy text in any installed account (`⌘C`, or `echo hi | pbcopy`).
2. Switch to another user via fast user switching
   (user icon in the menu bar, or lock screen → pick the account; enable the
   switcher under **System Settings → Control Center → Fast User Switching**
   if it is not shown).
3. Paste (`⌘V`) — the text is already there, within ~1–2 seconds.

How accounts participate:

- Sync runs between accounts that are **logged in**. A switched-out account
  (fast user switching) stays logged in and keeps syncing.
- An account that was fully **logged out** catches up with the latest board
  content automatically the next time you log into it — macOS empties the
  clipboard at logout, the agent refills it from the shared board.
- Only text participates. Images and files don't sync (see
  [Limitations](#limitations)).

Verify that it works:

```bash
# in account A
echo "sync-test-$(date +%s)" | pbcopy

# a few seconds later, in account B
cat /Users/Shared/.clipboard-sync/board   # should show the same text
pbpaste                                   # should paste the same text
```

Check that the agents are running:

```bash
ps aux | grep clipboard-sync-agent | grep -v grep          # one line per logged-in account
launchctl print gui/$(id -u)/com.local.clipboard-sync | grep state
```

If an account's agent is missing: log into that account once, then run
`./install.sh` there (or `sudo ./install.sh <user>` from any admin account).

## Troubleshooting

- **Not syncing?** Confirm both accounts have the agent installed
  (`ls ~/Library/LaunchAgents/com.local.clipboard-sync.plist` in each) and
  running (commands above).
- **Agent disabled?** Check
  **System Settings → General → Login Items & Extensions → Allow in the
  Background** — the `com.local.clipboard-sync` item must be enabled.
- **Permission errors on the shared dir?** Restore it with:
  `sudo chgrp staff /Users/Shared/.clipboard-sync && sudo chmod 2770 /Users/Shared/.clipboard-sync`
- **Copied an image or file?** Only text syncs — that's by design.

## How it works

1. Each agent wakes once per second, dumps its own clipboard with `pbpaste`,
   and compares **MD5 hashes** — its own clipboard vs. the shared board file.
2. If the local hash changed (and differs from the board), the agent publishes:
   it writes the new content to the board atomically (`tmp file` + `mv`) and
   records author/timestamp in `board.meta`.
3. If the board hash changed (and differs from the local clipboard), the agent
   pulls: it loads the board content with `pbcopy`.
4. Per-agent "last seen" hashes for both sides are what break the feedback
   loop — a pull does not look like a fresh local copy on the next tick.

This is a tiny blackboard pattern with last-write-wins semantics. Polling is
used because macOS exposes no cross-session pasteboard change notifications.

## Limitations

- **Text only.** `pbcopy`/`pbpaste` carry plain text; images and file
  references are not synced (they are also deliberately ignored so they can't
  wipe the text board).
- **Logged-in accounts only.** A logged-out account has no pasteboard; it
  catches up automatically on next login.
- **~1–2 s latency**, last write wins on near-simultaneous copies.
- Fresh sessions can't clear the remote board by "copying nothing" — an empty
  local clipboard is treated as non-text content and skipped.

## Security notes

- The board file is readable/writable by every participating account (that is
  the point). Anything you copy is effectively shared between the local
  accounts on this machine — **avoid copying passwords or one-time codes while
  multi-account sync is active**.
- Everything stays on the local machine; nothing is sent over the network.

## Resource usage

Measured on Apple Silicon: each agent averages ~0.2% of one core
(≈7 CPU-seconds per hour per account, a few milliwatts). Logged-out accounts
cost nothing because their agent isn't running.

## Uninstall

```bash
./uninstall.sh                                  # remove the current user's agent
sudo ./uninstall.sh <username> [<username> ...] # remove other accounts' agents
sudo ./uninstall.sh --purge <username>          # ... and delete the shared board
```

If sync ever stops working, check **System Settings → General → Login Items &
Extensions → Allow in the Background** — the `com.local.clipboard-sync` item
must be enabled.

## Files

- `clipboard-sync.sh` — the agent (runs as a per-user launchd service)
- `install.sh` / `uninstall.sh` — setup and teardown
- `LICENSE` — MIT

## License

MIT — see [LICENSE](LICENSE).
