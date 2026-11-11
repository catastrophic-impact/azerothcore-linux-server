#!/usr/bin/env bash
# Optional server components: which scripts / SQL / client addons belong to which one. Sourced by install.sh (not run on its own).
# To add a component: add its name to COMPONENTS, a description in comp_desc, and its files in comp_files.
# All components default to ON. Jukebox works on its own (/jukebox plays for you only); with Garrison on too, the Jukebox NPC plays for everyone inside a garrison (server part: garrison_jukebox.lua).
COMPONENTS="garrison jukebox shop bots timewalking"

comp_desc() { case "$1" in
  garrison)    echo "Garrison (player housing at the Stormwind Mage Tower portal, decor catalog, pets; includes the admin tool for GM accounts)";;
  jukebox)     echo "Jukebox (music addon: /jukebox; with Garrison also a jukebox NPC for your garrison)";;
  shop)        echo "Shop (pets / mounts / toys / services addon)";;
  bots)        echo "Bot Manager (addon to build companion bot parties)";;
  timewalking) echo "Timewalking (Dungeon Teleporter NPC, extra boss rewards + XP, Hearthstone reset in dungeons)";;
esac; }

# one line per file: "<kind> <path relative to the project>"   kind = script | sql | addon (addon = a folder copied into client-addons/)
comp_files() { case "$1" in
  garrison)    echo "script scripts/garrison.lua"; echo "script scripts/garrison_catalog.lua"; echo "script scripts/garrison_anims.lua"
               for f in config items curate economy store locations spawn session portal placement ghost menagerie wildlife props perks gm; do echo "script scripts/garrison_$f.lua"; done
               for f in 002_garrison 003_garrison_npcs 004_menagerie 006_garrison_decor 007_marker 008_decor_templates 009_decor_effects 010_decor_fire 011_decor_shopfronts 012_decor_buildings 013_decor_rest 014_decor_types 015_wildlife; do echo "sql custom-sql/$f.sql"; done
               echo "sql custom-sql/001_chromie_teleporter_npc.sql"   # the garrison catalog lists the Dungeon Teleporter NPC (900001); without this row placing it fails
               echo "addon addons/wotlk_garrison"; echo "addon tools/wotlk_garrison_admin";;
  jukebox)     echo "addon addons/wotlk_jukebox"; echo "script scripts/garrison_jukebox.lua";;   # the script is inert without the garrison scripts
  shop)        echo "script scripts/shop_server.lua"; echo "script scripts/shop_catalog.lua"; echo "script scripts/shop_prime.lua"; echo "addon addons/wotlk_shop";;
  bots)        echo "script scripts/bot_manager.lua"; echo "addon addons/wotlk_botmanager";;
  timewalking) echo "script scripts/dungeon_teleporter.lua"; echo "script scripts/darkmoon_tickets.lua"; echo "sql custom-sql/001_chromie_teleporter_npc.sql";;
esac; }

# install_components <project dir> <server dir> : copies the shared files, then every component whose ENABLE_<name> is 1; writes config/components.conf
install_components() {
  local src="$1" dest="$2" c kind path
  mkdir -p "$dest/lua_scripts" "$dest/client-addons" "$dest/custom-sql" "$dest/config"
  cp -a "$src/scripts/acore_msg.lua" "$dest/lua_scripts/"; cp -n "$src/scripts/acore_settings.lua" "$dest/lua_scripts/"   # owner settings are never overwritten
  cp -a "$src/addons/AcoreLib" "$dest/client-addons/"
  cp -a "$src/addons/Transmog" "$dest/client-addons/"   # optional transmog window for mod-transmog-plus (a core module, not a component)
  cp -a "$src/addons/wotlk_minimap" "$dest/client-addons/"   # Minimap Drawer: client-only quality-of-life addon, always installed
  : > "$dest/config/components.conf"
  for c in $COMPONENTS; do
    local on; eval "on=\${ENABLE_$c:-1}"
    echo "$c=$on" >> "$dest/config/components.conf"
    [ "$on" = 1 ] || continue
    while read -r kind path; do
      case "$kind" in
        script) cp -a "$src/$path" "$dest/lua_scripts/";;
        sql)    cp -a "$src/$path" "$dest/custom-sql/";;
        addon)  cp -a "$src/$path" "$dest/client-addons/";;
      esac
    done < <(comp_files "$c")
  done
  # the shop's default currency is the Darkmoon ticket, which only Timewalking rewards hand out: without it the shop switches to gold
  if [ "${ENABLE_shop:-1}" = 1 ] && [ "${ENABLE_timewalking:-1}" != 1 ]; then
    sed -i '0,/currency = "item"/s//currency = "gold"/' "$dest/lua_scripts/acore_settings.lua"
  fi
}
