# Third-party software in `deps/`

This repository vendors unmodified snapshots (no git history) of the projects below so the server can be built from this repo alone, at the exact commits recorded in [`modules.lock`](modules.lock). **They are not our work.** Each keeps its own copyright and license, and each folder under `deps/` still contains the license text and headers that upstream shipped. Do not remove them.

Our own code (everything outside `deps/`) is GPL-3.0, see [LICENSE](LICENSE). Our changes to vendored code are kept as separate patch files in [`patches/`](patches/), applied at build time, so upstream files stay byte-for-byte as published.

| Path | Project | Authors | License | Upstream |
|---|---|---|---|---|
| `deps/core` | AzerothCore, Playerbot fork | AzerothCore contributors; mod-playerbots team | GPL-2.0 (see `deps/core/LICENSE`; AzerothCore is also offered under AGPL-3.0 upstream) | https://github.com/mod-playerbots/azerothcore-wotlk |
| `deps/modules/mod-ale` | mod-ale (ALE Lua engine) | AzerothCore contributors | GPL-3.0 | https://github.com/azerothcore/mod-ale |
| `deps/modules/mod-playerbots` | mod-playerbots | mod-playerbots contributors | GPL-2.0 | https://github.com/mod-playerbots/mod-playerbots |
| `deps/modules/mod-individual-progression` | mod-individual-progression | ZhengPeiRu21, AzerothCore | MIT | https://github.com/ZhengPeiRu21/mod-individual-progression |
| `deps/modules/mod-autobalance` | mod-autobalance | AzerothCore contributors | No license file upstream; source headers say GPL / AGPL-3.0 (AzerothCore) | https://github.com/azerothcore/mod-autobalance |
| `deps/modules/mod-transmog-plus` | mod-transmog-plus | Stefan2102 | AGPL-3.0 | https://github.com/Stefan2102/mod-transmog-plus |
| `deps/modules/mod-ah-bot-plus` | mod-ah-bot-plus | Nathan Handley, AzerothCore | No license file upstream; source headers say GPL (v2 or later) | https://github.com/NathanHandley/mod-ah-bot-plus |
| `deps/modules/mod-dungeon-clear` | mod-dungeon-clear | Jared Wright (jrad7) and contributors | See `deps/modules/mod-dungeon-clear/LICENSE` | https://github.com/jrad7/mod-dungeon-clear |
| `deps/modules/mod-rndbot-buffs` | mod-rndbot-buffs | Rockhopper1776 | AGPL-3.0 | https://github.com/Rockhopper1776/mod-rndbot-buffs |
| `deps/modules/mod-gm-realmfirst-fix` | mod-gm-realmfirst-fix | Haeniken | MIT | https://github.com/Haeniken/mod-gm-realmfirst-fix |

## Notes

- **Source availability (AGPL/GPL):** the complete corresponding source for everything we distribute is this repository. If you run a modified build as a network service, the AGPL modules (mod-transmog-plus, mod-rndbot-buffs) require you to offer your users the source of your modified version.
- **Trimmed core:** `deps/core` omits `.git`, `.github`, nested `.gitignore`/`.gitattributes` files, `e2e/` and the historical SQL in `data/sql/old` and `data/sql/archive` (not used for install or import). Nothing else is changed.
- **Bundled libraries:** `deps/core/deps/` carries AzerothCore's own bundled third-party libraries (boost, fmt, zlib, etc.), each under its own license in its folder.
- **Missing license files:** mod-autobalance and mod-ah-bot-plus ship no license file upstream. We keep their copyright headers intact and credit them above; if an author states a specific license, update this table.
- **Not vendored:** the WoW client, client Data.zip (wowgaming), MySQL, and the Go toolchain are downloaded or supplied separately under their own terms.
- **Adding or updating a dependency:** run `tools/update-dep.sh <name> [commit]`, then update this table if the license or authors change.
