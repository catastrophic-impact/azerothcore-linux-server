# Portable AzerothCore server + garrison / jukebox / shop / bot addons

A one-script installer for a self-contained **WotLK 3.3.5a** AzerothCore server (Playerbot fork, 9 modules), an admin TUI, and a set of **open-source ALE (Lua) systems with matching client addons**: player housing ("garrison"), jukebox, shop, bot manager and Timewalking-style dungeon extras.

> **Status: the addons are work in progress, but playable.** Expect rough edges; issues and pull requests welcome.

## Why the addons are different

Other player-housing and garrison projects for 3.3.5 usually need core changes, a custom client patch, or closed code. These **need none of that**: they are plain ALE scripts + SQL + stock-client addons, and they are **open source**, so you can read them, learn from them and build on them.

| Piece | What it is |
|---|---|
| **Garrison** | Your own phased garrison (Northshire Abbey): place trainers, vendors, a Menagerie of roaming pets, and ~900 decor objects with a preview-grid placement window. Includes an admin tool (GM accounts only) for fitting previews, naming, categories and prices. |
| **Jukebox** | ~1000 game tracks, favorites, shuffle; in a garrison the jukebox NPC plays music for everyone inside. (Needs Garrison.) |
| **Shop** | Pets, mounts, toys and services bought with Darkmoon Prize Tickets (or gold). |
| **Bot Manager** | `/bots` window to build companion bot parties by class, spec and role. (Needs mod-playerbots.) |
| **Timewalking** | Dungeon Teleporter NPC, extra boss rewards + XP, free Hearthstone after leaving a dungeon. |

## What the installer builds

AzerothCore (the [Playerbot fork](https://github.com/mod-playerbots/azerothcore-wotlk)) plus these modules, pinned to exact versions in `modules.lock`. Each can be turned off later in the TUI's Modules tab.

| Module | Purpose |
|---|---|
| [mod-ale](https://github.com/azerothcore/mod-ale) | Lua scripting engine (ALE); runs all of our server-side scripts |
| [mod-playerbots](https://github.com/mod-playerbots/mod-playerbots) | Random and companion bots that play like real players |
| [mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression) | Per-player progression through the expansion tiers |
| [mod-autobalance](https://github.com/azerothcore/mod-autobalance) | Scales instance difficulty to the group |
| [mod-transmog](https://github.com/azerothcore/mod-transmog) | Transmogrification NPC |
| [mod-ah-bot-plus](https://github.com/NathanHandley/mod-ah-bot-plus) | Auction house bot |
| [mod-dungeon-clear](https://github.com/jrad7/mod-dungeon-clear) | Autonomous dungeon-clearing mode for tank bots |
| [mod-rndbot-buffs](https://github.com/Rockhopper1776/mod-rndbot-buffs) | Idle bots buff nearby real players |
| [mod-gm-realmfirst-fix](https://github.com/Haeniken/mod-gm-realmfirst-fix) | Stops GM accounts from earning Realm First achievements |

## Install the full server (Linux)

Needs `distrobox`, `git`, `curl` and podman or docker.

```
git clone <this repo> && cd <repo> && ./install.sh
```

It asks which components to install (all **on** by default), an optional server name, and the player accounts to create, then builds everything inside an Ubuntu 22.04 distrobox and writes a **self-contained server folder** (nothing is written to your home or `~/.config`). Unattended: `--yes`, with `--no-garrison --no-jukebox --no-shop --no-bots --no-timewalking` to leave things out, `--accounts FILE` (lines of `name password gmlevel`).

Run the admin TUI from the server folder: `./acore-admin`

- **Server** start / safe stop, world console, **reset to fresh install** (restores the install-time master snapshot after a confirmation).
- **Accounts** add / delete / GM level / password.
- **Backups**, **Modules** (toggle + rebuild), **Logs**, **Config**.
- Quit (`q`) asks for confirmation and stops the servers safely first.

Copy the folders in `client-addons/` into your client's `Interface/AddOns`.

## Use the addons on your own server

You need an AzerothCore server with [mod-ale](https://github.com/azerothcore/mod-ale) (Bot Manager also needs mod-playerbots).

1. Copy the scripts of the pieces you want from `scripts/` to your `lua_scripts/` folder. Always include `acore_msg.lua` and `acore_settings.lua`. The files per component are listed in [`tools/components.sh`](tools/components.sh).
2. Run the matching `custom-sql/*.sql` files (they select their own database). Re-running is safe.
3. Copy the matching folders from `addons/` (always `AcoreLib`; the garrison admin tool is `tools/wotlk_garrison_admin`) into each player's `Interface/AddOns`.
4. Restart the server or run `reload ale`, then `/reload` in game.

Settings live in `scripts/acore_settings.lua`.

## Layout

`scripts/` server-side ALE Lua · `addons/` client addons · `custom-sql/` database content · `tui/` admin TUI (Go) · `tools/` generators and installer parts · `config-overrides/` server tuning · `patches/` core patches · `modules.lock` pinned versions.

## License

Our code is GPL-3.0 (see [LICENSE](LICENSE)). AzerothCore, the Playerbot core and every module the installer downloads keep their own licenses and belong to their authors; the installer fetches them from their original repositories at pinned versions (`modules.lock`).
