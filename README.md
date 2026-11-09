# Portable AzerothCore server + garrison / jukebox / shop / bot addons

A one-script installer for a self-contained **WotLK 3.3.5a** AzerothCore server (Playerbot fork, 9 modules), an admin TUI, and a set of **open-source ALE (Lua) systems with matching client addons**: player housing ("garrison"), jukebox, shop, bot manager and Timewalking-style dungeon extras.

> **Status: the addons are work in progress, but playable.** Expect rough edges; issues and pull requests welcome.

## Why the addons are different

Other player-housing and garrison projects for 3.3.5 usually need core changes, a custom client patch, or closed code. These **need none of that**: they are plain ALE scripts + SQL + stock-client addons, and they are **open source**, so you can read them, learn from them and build on them.

| Piece | What it is |
|---|---|
| **Garrison** | Your own phased garrison (pick a location at the Stormwind Mage Tower portal; every location has one fixed area shared by all players): place trainers, vendors, a Menagerie of roaming pets, and ~900 decor objects with a preview-grid placement window. Includes an admin tool (GM accounts only) for fitting previews, naming, categories and prices. |
| **Jukebox** | ~1000 game tracks, favorites, shuffle; works on its own with `/jukebox` (plays for you only); with Garrison installed too, the jukebox NPC plays music for everyone inside a garrison. |
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
| [mod-transmog-plus](https://github.com/Stefan2102/mod-transmog-plus) | Slot-based transmogrification (NPC + optional addon) |
| [mod-ah-bot-plus](https://github.com/NathanHandley/mod-ah-bot-plus) | Auction house bot |
| [mod-dungeon-clear](https://github.com/jrad7/mod-dungeon-clear) | Autonomous dungeon-clearing mode for tank bots |
| [mod-rndbot-buffs](https://github.com/Rockhopper1776/mod-rndbot-buffs) | Idle bots buff nearby real players |
| [mod-gm-realmfirst-fix](https://github.com/Haeniken/mod-gm-realmfirst-fix) | Stops GM accounts from earning Realm First achievements |

## Install the full server (Linux)

Needs `distrobox`, `git`, `curl` and podman or docker.

```
git clone <this repo> && cd <repo> && ./install.sh
```

It asks which components to install (all **on** by default), whether to use our **recommended settings** (XP x4, 300 playerbots, active auction bot, faster skills/reputation, relaxed instances) or plain AzerothCore defaults (`--stock-settings`), an optional server name, and the player accounts to create, then builds everything inside an Ubuntu 22.04 distrobox and writes a **self-contained server folder** (nothing is written to your home or `~/.config`). Unattended: `--yes`, with `--no-garrison --no-jukebox --no-shop --no-bots --no-timewalking` to leave things out, `--accounts FILE` (lines of `name password gmlevel`).

Run the admin TUI from the server folder: `./acore-admin`

- **Server** status dashboard (services, uptime, characters online, disk), start / safe stop, **reset to fresh install**. **Output** shows the game server's live text and takes console commands (`:`).
- **Logs** with scrolling (wheel / arrows), filter (`/`) and errors-only (`e`). **Debug** switches the individual log files on or off (Playerbots.log is off by default), clears `mysqld.log`, and has two garrison maintenance actions.
- **Accounts** add / delete / GM level / password, search, online status. **Config** realmlist and client patch. **Modules** toggle + rebuild.
- **Backups**: the only automatic backup is the install-time **master** (`backups/fresh`, pinned at the top, cannot be deleted in the TUI). Restore, reset and module changes ask "create a backup first?"; running servers are stopped safely (with an in-game countdown) and started again for you.
- Press `?` for the key list. Tabs are clickable. Quit (`q`) asks for confirmation and stops the servers safely first.

Copy the folders in `client-addons/` into your client's `Interface/AddOns`. The garrison portal and the garrison jukebox NPC only work for players who have the matching addon installed (each addon tells the server it is present when you enter the world; after installing one, `/reload`).

## Use the addons on your own server

You need an AzerothCore server with [mod-ale](https://github.com/azerothcore/mod-ale) (Bot Manager also needs mod-playerbots).

1. Copy the scripts of the pieces you want from `scripts/` to your `lua_scripts/` folder. Always include `acore_msg.lua` and `acore_settings.lua`. The files per component are listed in [`tools/components.sh`](tools/components.sh).
2. Run the matching `custom-sql/*.sql` files (they select their own database). Re-running is safe.
3. Copy the matching folders from `addons/` (always `AcoreLib`; the garrison admin tool is `tools/wotlk_garrison_admin`) into each player's `Interface/AddOns`.
4. Restart the server or run `reload ale`, then `/reload` in game.

Settings live in `scripts/acore_settings.lua`.

## Get the newest addons (client side)

The addons are updated often. You can take the latest version straight from this repo at any time, without reinstalling the server:

1. **Download:** on GitHub press **Code → Download ZIP** and unzip it (or `git clone` / `git pull` if you use git).
2. **Copy** the folders you want from the `addons/` folder into your WoW client's `Interface/AddOns` folder:
   - `AcoreLib` (always needed)
   - `wotlk_garrison`, `wotlk_jukebox`, `wotlk_shop`, `wotlk_botmanager` (only the ones your server uses)
   - `Transmog` (optional): the transmog window for the Warpweaver NPC; without it players get the normal NPC menu. Its UI comes from the mod-transmog-plus project (AGPL-3.0, see `addons/Transmog/LICENSE`)
   - `tools/wotlk_garrison_admin` is the garrison admin tool, for GM accounts only
3. **Load them:** after updating an addon, type `/reload` in game. After adding a new addon or an addon whose `.toc` changed, log out fully and back in. At the character screen, check **AddOns** and make sure they are enabled.

## Updating without rebuilding the server

You never need to rebuild or reinstall to get newer addons. Update the **client addons** (above) and the matching **server scripts**, because the two talk to each other and should stay on the same version.

Download the repo, then in your server folder:

1. Copy the scripts for the pieces you use from the repo's `scripts/` into the server's `lua_scripts/` folder:

   | Piece | Scripts |
   |---|---|
   | Always | `acore_msg.lua` |
   | Garrison | `garrison.lua`, `garrison_catalog.lua`, `garrison_anims.lua` and every `garrison_<name>.lua` (config, items, economy, store, locations, spawn, session, portal, placement, ghost, menagerie, props, perks, gm) |
   | Jukebox in a garrison | `garrison_jukebox.lua` (the addon alone needs no server script) |
   | Shop | `shop_server.lua`, `shop_catalog.lua`, `shop_prime.lua` |
   | Bot Manager | `bot_manager.lua` |
   | Timewalking | `dungeon_teleporter.lua`, `darkmoon_tickets.lua` |

   **Do not overwrite `acore_settings.lua`**: it holds your own settings. Check the repo's version for new options and add them by hand.
2. If there are new files in `custom-sql/`, copy them to the server's `custom-sql/` folder. The TUI applies them on every start (they are safe to re-run).
3. Restart the servers from the TUI (Server tab: `x` to stop, then `s`). For small changes to the non-garrison scripts, `reload ale` in the world console (`:`) is enough, but after a garrison update restart.
4. Update the client addons (copy, then `/reload` or relog).

Tip: take a backup first (TUI Backups tab, `b`).

## Layout

`scripts/` server-side ALE Lua · `addons/` client addons · `custom-sql/` database content · `tui/` admin TUI (Go) · `tools/` generators and installer parts · `config-overrides/` server tuning · `patches/` core patches · `modules.lock` pinned versions.

## License

Our code is GPL-3.0 (see [LICENSE](LICENSE)). AzerothCore, the Playerbot core and every module the installer downloads keep their own licenses and belong to their authors; the installer fetches them from their original repositories at pinned versions (`modules.lock`).
