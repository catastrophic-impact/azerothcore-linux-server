#!/usr/bin/env bash
# Independence check: every optional component (tools/components.sh) must load ALONE, with only the shared core scripts next to it.
# For each component: copy core + that component's scripts into an empty folder, stub the game API, load every script with package.path
# restricted to that folder. A script that reaches into another component (require / global) fails here.
# usage (host, project root):  bash tools/test_independence.sh        needs luajit

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
T="$ROOT/cache/indep_test"; rm -rf "$T"; mkdir -p "$T"
. tools/components.sh
rc=0
for c in $COMPONENTS; do
  D="$T/$c/lua_scripts"; mkdir -p "$D"
  for f in msg prime bus util settings; do cp "scripts/acore_$f.lua" "$D/"; done
  comp_files "$c" | while read -r k p; do if [ "$k" = script ]; then cp "$p" "$D/"; fi; done
  luajit tools/indep_load.lua "$D" 2>&1 | grep -E 'LOAD FAIL|scripts,' || rc=1
  luajit tools/indep_load.lua "$D" >/dev/null 2>&1 || rc=1
done
[ $rc = 0 ] && echo "INDEPENDENCE OK" || { echo "INDEPENDENCE FAILED"; exit 1; }
