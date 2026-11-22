# AzerothCore Launcher (Electron)

A desktop launcher for the portable server in this repo. It does everything the admin TUI (`acore-admin`) does, in a window, and adds
**installing / removing our client addons** in a WoW client folder you pick. It never starts the WoW client.

## Portable by design
Everything lives in this one folder. Electron's profile, cache, logs, crash dumps, the launcher's own settings and even npm's cache are
redirected into `launcher/data/`; `run.sh` points the `XDG_*` variables there too. Nothing is written to the user's home or `~/.config`.
Delete the folder and nothing is left behind. (`launcher/data/` and `launcher/node_modules/` are git-ignored.)

## Use
1. Put the `launcher/` folder inside the server folder (next to `acore-admin`), or run it from this repo (it then uses `../release`).
   Another server folder: `ACORE_ROOT=/path/to/server ./run.sh`.
2. One-time: `./setup.sh` installs Electron into `launcher/node_modules` (needs Node.js 20+ / npm; inside a distrobox with Node it works too).
3. `./run.sh` starts the launcher.

## Tabs (the TUI's tabs plus one)
| Tab | What it does |
|---|---|
| Server | status cards (services, world uptime, characters online, disk), Start / Safe stop / MySQL only / Reset to fresh install (optional backup first) |
| Output | live `world.out` and a console command box |
| Logs | any file in `logs/`, text filter, errors-only, pause |
| Accounts | list, search, create, delete, GM level, password |
| Modules | enable / disable, Apply (rebuild), Undo, Add by git URL, Remove |
| Backups | full / player backups, restore (pick databases), delete, open folder; the install-time master `fresh` is pinned |
| Options | free class / riding training, log-file switches, clear logs, garrison data wipe and clean-up |
| Config | realmlist (address + LAN address, Detect LAN, localhost), build the client patch archive |
| **Client addons** | choose your WoW folder; install / update / remove OUR addons; optional client `realmlist.wtf` |

Risky actions (reset, restore, wipe, module rebuild, training switch) ask first and offer "create a full backup first".

## Client addons: safety rules
* Accepts the client root (Wow.exe + Data), its `Interface` or its `AddOns` folder.
* Only addons from our own list (`client-addons/` of the server folder, or `addons/` in a checkout) are ever copied or deleted. Other AddOns are never touched.
* `AcoreLib` and declared `## Dependencies` are installed automatically; the GM-only `wotlk_garrison_admin` is left out of "Install all (players)".
* An update swaps the folder atomically (old copy restored if the copy fails); the original `realmlist.wtf` is kept once as `realmlist.wtf.bak-launcher`.

## How it works
`lib/admin.js` calls the proven `acore-admin` command line (the same Go code the TUI runs) for starting / stopping, MySQL, backups, restore,
module rebuilds, the client patch and the training switches, and reads status, logs, accounts, backups, modules and the realmlist directly.
So the launcher needs the `acore-admin` binary next to it. Module **add / remove** need an `acore-admin` built from the current `tui/cli.go`
(which gained `modules add|remove`).

## Tests
`node --test test/run.js` (needs Node 22): backend tests against throw-away fake server and client folders, no Electron needed.
`node test/live_readonly.js [server root]`: read-only smoke test against a running server.
With xvfb, `ACORE_LAUNCHER_SHOTS=<dir> ./run.sh` renders every tab off-screen to PNGs (test hook in `test/shots.js`).
