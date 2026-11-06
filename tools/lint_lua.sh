#!/usr/bin/env bash
# Catches the bug class "attempt to call global 'X' (a nil value)" before the server does: lists every global name a server script reads
# that is neither standard Lua nor part of the ALE global API. Run in the build box (needs luac5.1: apt install lua5.1).
# usage: tools/lint_lua.sh [scripts_dir]      env: ALE_SRC (default release/modules/mod-ale/src/LuaEngine)
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
DIR="${1:-$HERE/scripts}"; ALE="${ALE_SRC:-$HERE/release/modules/mod-ale/src/LuaEngine}"
STD="assert collectgarbage error getmetatable ipairs load loadstring next pairs pcall print rawequal rawget rawset require select setmetatable tonumber tostring type unpack xpcall math string table os io debug coroutine _G _VERSION package"
api=$(grep -ho '{ "[A-Za-z0-9_]*", &LuaGlobalFunctions::' "$ALE/LuaFunctions.cpp" | sed 's/{ "\(.*\)",.*/\1/' | sort -u)
rc=0
for f in "$DIR"/*.lua; do
  used=$(luac5.1 -l "$f" 2>/dev/null | grep -o 'GETGLOBAL.*; [A-Za-z0-9_]*' | sed 's/.*; //' | sort -u)
  for g in $used; do
    echo " $STD " | grep -q " $g " && continue
    echo "$api" | grep -qx "$g" && continue
    case "$g" in ACORE|WotlkShopCatalog|WotlkGarrisonCatalog) continue;; esac
    # defined by the script itself as a global?
    luac5.1 -l "$f" 2>/dev/null | grep -q "SETGLOBAL.*; $g\$" && continue
    echo "$(basename "$f"): unknown global '$g'"; rc=1
  done
done
[ $rc = 0 ] && echo "lint ok"
exit $rc
