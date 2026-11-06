#!/usr/bin/env bash
# Runs INSIDE the build distrobox. usage: rebuild.sh <release_root>
# Reads <root>/modules/{all,enabled}.txt written by acore-admin, rebuilds core+enabled modules, installs into <root>.
set -e
ROOT="$1"; SRC="$HOME/src/azerothcore-wotlk"; B="$SRC/build"
echo "== syncing modules"
cd "$SRC/modules"
while read -r n || [ -n "$n" ]; do [ -n "$n" ] && rm -rf "$SRC/modules/$n"; done < "$ROOT/modules/all.txt"
while read -r n || [ -n "$n" ]; do [ -n "$n" ] && cp -a "$ROOT/modules/$n" "$SRC/modules/$n"; done < "$ROOT/modules/enabled.txt"
cd "$SRC"
for pf in "$ROOT"/patches/*.patch; do
  if git apply --check "$pf" 2>/dev/null; then git apply "$pf" && echo "applied $(basename "$pf")"; fi
done
echo "== configuring"
mkdir -p "$B" && cd "$B"
cmake .. -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_INSTALL_PREFIX="$HOME/src/install" -DWITH_WARNINGS=0 -DTOOLS_BUILD=none -DSCRIPTS=static -DMODULES=static -DCMAKE_BUILD_TYPE=RelWithDebInfo > "$HOME/cmake.log" 2>&1 || { tail -30 "$HOME/cmake.log"; exit 1; }
echo "== compiling (ccache makes repeat builds fast)"
make -j"$(nproc)" 2>&1 | grep -E 'error|Error|Linking|Built target (worldserver|authserver)|^\[ *[0-9]+%\].*(Building).*' | awk 'NR%25==1 || /error|Error|Linking|Built/' 
[ "${PIPESTATUS[0]}" = 0 ] || { echo "BUILD FAILED"; exit 1; }
make install > /dev/null 2>&1
echo "== installing into release"
cp -f "$HOME/src/install/bin/worldserver" "$ROOT/bin/worldserver.new" && mv -f "$ROOT/bin/worldserver.new" "$ROOT/bin/worldserver"
cp -f "$HOME/src/install/bin/authserver" "$ROOT/bin/authserver.new" && mv -f "$ROOT/bin/authserver.new" "$ROOT/bin/authserver"
mkdir -p "$ROOT/lua_scripts" "$ROOT/etc/modules"
cp -a "$HOME/src/install/bin/lua_scripts/." "$ROOT/lua_scripts/" 2>/dev/null || true
cp -f "$HOME/src/install/etc/"*.dist "$ROOT/etc/"
cp -f "$HOME/src/install/etc/modules/"*.dist "$ROOT/etc/modules/" 2>/dev/null || true
echo "== module SQL sources"
rm -rf "$ROOT/source/modules"
while read -r n || [ -n "$n" ]; do
  [ -n "$n" ] && [ -d "$ROOT/modules/$n/data/sql" ] && mkdir -p "$ROOT/source/modules/$n/data" && cp -a "$ROOT/modules/$n/data/sql" "$ROOT/source/modules/$n/data/"
done < "$ROOT/modules/enabled.txt"
echo "== bundling new libraries"
ldd "$ROOT/bin/worldserver" | awk '/=> \//{print $3}' | grep -vE '/(libc|libm|libdl|libpthread|librt|libresolv|libutil)\.so' | while read -r l; do
  [ -e "$ROOT/libs/$(basename "$l")" ] || { cp -L "$l" "$ROOT/libs/" && echo "  + $(basename "$l")"; }
done
mkdir -p "$ROOT/libs" && cp -a /usr/lib/x86_64-linux-gnu/ossl-modules "$ROOT/libs/"   # OpenSSL3 legacy provider (RC4) needed by the WoW client protocol
echo "REBUILD_OK"
