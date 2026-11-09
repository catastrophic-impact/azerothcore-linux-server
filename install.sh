#!/usr/bin/env bash
# Portable AzerothCore (Playerbot fork) one-script installer.
# Builds everything inside an Ubuntu 22.04 distrobox (home under ~/boxes), then produces a self-contained
# server folder next to where you ran this. The server folder never touches your home or ~/.config.
# usage: ./install.sh [--dest DIR] [--box NAME] [--clean-box] [--accounts FILE] [--no-configure] [--yes]
#                     [--stock-settings] [--no-garrison] [--no-jukebox] [--no-shop] [--no-bots] [--no-timewalking]   (--yes = no questions, all defaults)
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="$PWD/azerothcore-server"; BOX="acore-box"; CLEAN=0; ACCTS="$HERE/local/accounts.txt"; CONFIGURE=1; ASSUME_YES=0
ENABLE_garrison=1; ENABLE_jukebox=1; ENABLE_shop=1; ENABLE_bots=1; ENABLE_timewalking=1; SETTINGS=recommended
SERVER_NAME=""; NEWACCTS=()   # NEWACCTS entries: "name<TAB>password<TAB>gmlevel" (kept in memory only, never written to disk)
source "$HERE/tools/components.sh"
while [ $# -gt 0 ]; do case "$1" in
  --dest) DEST="$(readlink -m "$2")"; shift 2;; --box) BOX="$2"; shift 2;;
  --clean-box) CLEAN=1; shift;; --accounts) ACCTS="$2"; shift 2;; --no-configure) CONFIGURE=0; shift;;
  --yes) ASSUME_YES=1; shift;; --stock-settings) SETTINGS=stock; shift;; --no-garrison|--no-jukebox|--no-shop|--no-bots|--no-timewalking) eval "ENABLE_${1#--no-}=0"; shift;;
  *) echo "unknown option $1"; exit 1;; esac; done
CACHE="${ACORE_CACHE:-$HERE/cache}"; BOXHOME="$HOME/boxes/$BOX"
MYSQL_URL="https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.7-linux-glibc2.28-x86_64.tar.xz"
DATA_URL="https://github.com/wowgaming/client-data/releases/download/v20.0/Data.zip"

say(){ printf '\n\033[1;33m== %s\033[0m\n' "$*"; }
bx(){ distrobox enter "$BOX" -- bash -c "$*"; }

say "0/9 host checks"
for c in distrobox git curl; do command -v $c >/dev/null || { echo "missing on host: $c"; exit 1; }; done
command -v podman >/dev/null || command -v docker >/dev/null || { echo "need podman or docker for distrobox"; exit 1; }
# ---- questions (all asked up front, so the long build can run unattended) ----
INTERACTIVE=0; [ -t 0 ] && [ "$ASSUME_YES" = 0 ] && INTERACTIVE=1
yn(){ local a; read -r -p "$1 [Y/n] " a; case "$a" in n|N|no|NO) return 1;; *) return 0;; esac; }
if [ "$INTERACTIVE" = 1 ]; then
  say "Optional components (all on by default; press Enter to keep, n to skip)"
  for c in $COMPONENTS; do
    eval "cur=\$ENABLE_$c"; [ "$cur" = 1 ] || continue   # already switched off by a --no-... flag
    yn "  $(comp_desc "$c")?" || eval "ENABLE_$c=0"
  done
  say "Server settings"
  echo "  recommended = our tuning (XP x4, 300 playerbots, auction bot active, faster skills/reputation, relaxed instances and battlegrounds)"
  echo "  stock       = plain AzerothCore defaults (portable paths and database settings are always applied)"
  read -r -p "Use the recommended settings? [Y/n] " a; case "$a" in n|N|no|NO) SETTINGS=stock;; esac
  read -r -p "Server name for the welcome message (Enter = generic message): " SERVER_NAME
  say "Player accounts (a fresh server has none; you can also add more later in the admin TUI, Accounts tab)"
  while yn "Create a player account now?"; do
    read -r -p "  account name (letters/digits/_ , max 17): " an; read -r -s -p "  password (max 16): " ap; echo; read -r -p "  GM level (0 player, 1 mod, 2 GM, 3 admin) [0]: " al
    case "$an" in ''|*[!A-Za-z0-9_]*) echo "  invalid name, skipped"; continue;; esac
    case "$al" in 1|2|3) ;; *) al=0;; esac
    [ -n "$ap" ] && [ "${#ap}" -le 16 ] && [[ "$ap" != *[[:space:]\'\"\;]* ]] && NEWACCTS+=("$an"$'\t'"$ap"$'\t'"$al") || echo "  invalid password (1-16 characters, no spaces or quotes), skipped"
  done
fi
echo "settings: $SETTINGS"
echo "components: $(for c in $COMPONENTS; do eval "[ \$ENABLE_$c = 1 ]" && printf '%s ' "$c"; done)"

mkdir -p "$CACHE" "$DEST"/{bin,etc/modules,libs,config,logs,backups,database,modules,lua_scripts,tools,patches,config-overrides,source}

say "1/9 build box '$BOX' (Ubuntu 22.04, home $BOXHOME)"
if ! distrobox list 2>/dev/null | grep -qw "$BOX"; then
  mkdir -p "$BOXHOME"; distrobox create --yes --name "$BOX" --image ubuntu:22.04 --home "$BOXHOME"
fi
bx 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git rsync cmake make gcc g++ clang libssl-dev zlib1g-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev libmysqlclient-dev wget curl p7zip-full unzip xz-utils libaio-dev numactl file pkg-config ccache >/dev/null'
bx '[ -x ~/go-sdk/bin/go ] || { V=$(curl -s "https://go.dev/dl/?mode=json" | grep -m1 -o "go[0-9.]*linux-amd64.tar.gz" ); curl -sL https://go.dev/dl/$V -o ~/go.tgz && mkdir -p ~/go-sdk && tar -xzf ~/go.tgz -C ~/go-sdk --strip-components=1 && rm ~/go.tgz; }; ~/go-sdk/bin/go version'

say "2/9 core source (vendored in deps/core, pinned by modules.lock)"
[ -f "$HERE/deps/core/CMakeLists.txt" ] || { echo "deps/core is missing - re-clone the repo."; exit 1; }
CORE_SHA=$(awk '$1=="core"{print substr($2,1,10)}' "$HERE/modules.lock")
bx "mkdir -p ~/src/azerothcore-wotlk && rsync -a --delete --exclude=/build '$HERE/deps/core/' ~/src/azerothcore-wotlk/ && echo core $CORE_SHA vendored" \
  || { echo "Could not copy deps/core into the build box."; exit 1; }

say "3/9 module sources -> $DEST/modules (no git history; pinned)"
python3 - "$HERE" "$DEST" <<'PY'
import sys,os,subprocess,json,shutil
here,dest=sys.argv[1:3]; mods=[]
for l in open(os.path.join(here,'modules.lock')):
    t=l.split()
    if len(t)==3 and t[0].startswith('mod-'): mods.append(dict(name=t[0],commit=t[1],url=t[2],enabled=True,built=False))
mf=os.path.join(dest,'modules','modules.json')
old=json.load(open(mf)) if os.path.exists(mf) else None
for m in mods:
    d=os.path.join(dest,'modules',m['name'])
    if os.path.isdir(d): continue
    src=os.path.join(here,'deps','modules',m['name'])
    if not os.path.isdir(src): sys.exit('deps/modules/%s is missing - re-clone the repo.' % m['name'])
    shutil.copytree(src,d); print('  +',m['name'])
if old is None: json.dump(dict(mods=mods,lastSnapshot='',prevEnabled=[]),open(mf,'w'),indent=1)
names=[m['name'] for m in (old['mods'] if old else mods)]
open(os.path.join(dest,'modules','all.txt'),'w').write('\n'.join(names)+'\n')
open(os.path.join(dest,'modules','enabled.txt'),'w').write('\n'.join(m['name'] for m in (old['mods'] if old else mods) if m['enabled'])+'\n')
PY

say "4/9 project files (tools, patches, config overrides, custom scripts)"
[ -d "$HERE/custom-sql" ] && { mkdir -p "$DEST/custom-sql"; cp -a "$HERE/custom-sql/." "$DEST/custom-sql/"; }
cp -a "$HERE/tools/rebuild.sh" "$DEST/tools/"; cp -a "$HERE/patches/." "$DEST/patches/"; cp -a "$HERE/config-overrides/." "$DEST/config-overrides/"
[ -f "$HERE/modules.lock" ] && cp -f "$HERE/modules.lock" "$DEST/modules.lock"
install_components "$HERE" "$DEST"
printf 'BOX=%s\n' "$BOX" > "$DEST/config/build.conf"
printf '[mysqld]\nbind-address=127.0.0.1\nport=3308\nmysqlx=OFF\nskip-log-bin\nmax_connections=200\ninnodb_buffer_pool_size=512M\n' > "$DEST/config/my.cnf"

say "5/9 build admin TUI"
bx "cd '$HERE/tui' && export PATH=\$HOME/go-sdk/bin:\$PATH && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o '$DEST/acore-admin' ."

say "6/9 build server + modules (long on first run: ~1.5h cold; ccache speeds repeats)"
bx "bash '$DEST/tools/rebuild.sh' '$DEST'" | tee "$DEST/logs/install-build.log" | awk 'NR%40==1 || /==|error|FAILED|REBUILD_OK/'
grep -q REBUILD_OK "$DEST/logs/install-build.log" || { echo "build failed, see $DEST/logs/install-build.log"; exit 1; }
python3 - "$DEST" <<'PY'
import json,sys; f=sys.argv[1]+'/modules/modules.json'; d=json.load(open(f))
for m in d['mods']: m['built']=m['enabled']
json.dump(d,open(f,'w'),indent=1)
PY
bx "mkdir -p '$DEST/source/data' && cp -a ~/src/azerothcore-wotlk/data/sql '$DEST/source/data/'"

say "7/9 MySQL 8.4 + client data (cached in $CACHE)"
[ -s "$CACHE/mysql.tar.xz" ] || curl -L --fail -o "$CACHE/mysql.tar.xz" "$MYSQL_URL"
[ -s "$CACHE/Data.zip" ] || curl -L --fail -o "$CACHE/Data.zip" "$DATA_URL"
[ -x "$DEST/mysql/bin/mysqld" ] || { mkdir -p "$DEST/mysql" && tar -xf "$CACHE/mysql.tar.xz" -C "$DEST/mysql" --strip-components=1; }
[ -d "$DEST/data/maps" ] || { mkdir -p "$DEST/data" && unzip -q -o "$CACHE/Data.zip" -d "$DEST/data"; }
bx "export LD_LIBRARY_PATH='$DEST/mysql/lib/private':'$DEST/mysql/lib'; for f in mysqld mysql mysqldump mysqladmin; do ldd '$DEST/mysql/bin/'\$f; done | awk '/=> \\//{print \$3}' | grep -vE '/(libc|libm|libdl|libpthread|librt|libresolv|libutil)\.so' | grep -v '$DEST' | sort -u | while read l; do [ -e '$DEST/libs/'\$(basename \$l) ] || cp -L \$l '$DEST/libs/'; done"
bx "ldd '$DEST/bin/worldserver' | grep 'not found' || true"

say "8/9 configs + first boot (creates databases, imports all SQL, makes accounts)"
A="$DEST/acore-admin"; cd "$DEST"
if [ -n "$SERVER_NAME" ] && [[ "$SERVER_NAME" != *[\"\\\&\|]* ]]; then
  sed -i "s|^PlayerStart.String = .*|PlayerStart.String = \"Welcome to $SERVER_NAME!\"|" "$DEST/config-overrides/worldserver.conf"
fi
echo "settings=$SETTINGS" > "$DEST/config/settings.conf"
"$A" confs
if [ "$CONFIGURE" = 1 ] && [ -t 0 ]; then
  say "Module settings (optional, best done BEFORE the first login)"
  echo "Settings live in: $DEST/etc/modules/*.conf (+ $DEST/etc/worldserver.conf, $DEST/lua_scripts/acore_settings.lua)"
  echo "Worth a look: mod-individual-progression (which content is open and in what order), playerbot count, XP rates, AutoBalance."
  if command -v xdg-open >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    xdg-open "$DEST/etc/modules" >/dev/null 2>&1 || true
  fi
  read -r -p "Edit them now, then press Enter to continue (or just Enter to keep defaults): " _
fi
"$A" start
"$A" wait-ready 3600
AHPW=$(head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 16)   # random; not stored, bot never logs in
"$A" console "account create ahbot $AHPW"; sleep 3
AID=$("$A" sql "select id from acore_auth.account where username='AHBOT'")
"$A" sql "SET SESSION sql_mode=''; INSERT IGNORE INTO acore_characters.characters (guid,account,name,race,class,gender,level,position_x,position_y,position_z,map,zone,online,taximask) VALUES (900001,$AID,'Stockmarket',1,1,1,80,-8949.95,-132.493,83.5312,0,12,0,'')" >/dev/null
"$A" stop-game
"$A" snapshot-fresh && echo "master snapshot created (backups/fresh): TUI > Server > R resets the server to this state"   # before any player accounts exist

if [ -f "$ACCTS" ] || [ "${#NEWACCTS[@]}" -gt 0 ]; then
  say "player accounts"
  "$A" start; "$A" wait-ready 3600
  mkacct(){ "$A" console "account create $1 $2"; sleep 2; [ "${3:-0}" != 0 ] && { "$A" console "account set gmlevel $1 $3 -1"; sleep 2; } || true; }
  if [ -f "$ACCTS" ]; then
    while read -r n pw lvl; do case "$n" in ''|\#*) continue;; esac; mkacct "$n" "$pw" "$lvl"; done < "$ACCTS"
  fi
  for e in "${NEWACCTS[@]}"; do IFS=$'\t' read -r n pw lvl <<<"$e"; mkacct "$n" "$pw" "$lvl"; done
  "$A" stop-game
fi
"$A" stop

say "9/9 done"
distrobox stop --yes "$BOX" >/dev/null 2>&1 || true
[ "$CLEAN" = 1 ] && { distrobox rm --force --yes "$BOX" >/dev/null 2>&1 || true; echo "build box removed (the TUI's module rebuilds need it; re-run install.sh to recreate)"; }
echo "Server folder: $DEST"; echo "Run:  cd '$DEST' && ./acore-admin"
