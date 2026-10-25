# mac-clipboard-sync

Sync the clipboard across **macOS user accounts on the same machine**.

macOS gives every login session its own isolated pasteboard, so when you use
multiple local accounts (work / personal / review, fast user switching), each
account starts with an empty clipboard and nothing you copy carries over.
This project fixes that with ~60 lines of shell and a launchd agent.

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

```bash
# current user only (no sudo needed)
./install.sh

# additionally install for other local accounts (needs sudo)
sudo ./install.sh alice bob
```

What it sets up:

| Path | Purpose |
|---|---|
| `/Users/Shared/clipboard-sync-agent.sh` | the agent script (installed once, shared by all accounts) |
| `/Users/Shared/.clipboard-sync/` | the exchange dir: `board` + `board.meta`, mode `2770 staff` |
| `~/Library/LaunchAgents/com.local.clipboard-sync.plist` | per-user launchd agent (RunAtLoad, KeepAlive, Background priority) |

Accounts that are logged in start syncing immediately; accounts that are not
logged in start automatically at their next login.

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
./uninstall.sh                      # remove the current user's agent
sudo ./uninstall.sh alice bob       # remove other accounts' agents
sudo ./uninstall.sh --purge alice   # ... and delete the shared board
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
