#!/usr/bin/env bash
# Fetch the PORTABLE Electron runtime into <launcher>/electron (no Node, npm or root needed; only curl + python3, which the installer runs inside its build box).
# usage: fetch-electron.sh [launcher dir] [download cache dir]      (the installer calls this; you can re-run it to repair)
# The version is the one pinned in package.json; the zip is verified against the official SHASUMS256.txt before it is unpacked.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
L="$(readlink -m "${1:-$HERE}")"; CACHE="$(readlink -m "${2:-$L/data/electron-download}")"
VER="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['devDependencies']['electron'])" "$L/package.json")"
[ -x "$L/electron/electron" ] && [ "$(cat "$L/electron/version" 2>/dev/null)" = "$VER" ] && { echo "electron $VER already in place"; exit 0; }
ZIP="electron-v$VER-linux-x64.zip"; BASE="https://github.com/electron/electron/releases/download/v$VER"
mkdir -p "$CACHE"
if [ ! -s "$CACHE/$ZIP" ]; then
  curl -L --fail -o "$CACHE/$ZIP.part" "$BASE/$ZIP" || { rm -f "$CACHE/$ZIP.part"; echo "could not download $BASE/$ZIP"; exit 1; }
  mv -f "$CACHE/$ZIP.part" "$CACHE/$ZIP"
fi
curl -L --fail -s -o "$CACHE/SHASUMS256-$VER.txt" "$BASE/SHASUMS256.txt" || { echo "could not download the checksum list"; exit 1; }
WANT="$(awk -v f="*$ZIP" '$2==f||$2=="*"f||$2==f{print $1}' "$CACHE/SHASUMS256-$VER.txt" | head -1)"
GOT="$(sha256sum "$CACHE/$ZIP" | cut -d' ' -f1)"
[ -n "$WANT" ] && [ "$WANT" = "$GOT" ] || { echo "checksum mismatch for $ZIP (want '$WANT', got '$GOT'); removing the download"; rm -f "$CACHE/$ZIP"; exit 1; }
rm -rf "$L/electron.new"; mkdir -p "$L/electron.new"
python3 -I - "$CACHE/$ZIP" "$L/electron.new" <<'PY'
import sys, zipfile, os
z, out = sys.argv[1:3]
with zipfile.ZipFile(z) as f:
    for i in f.infolist():
        p = f.extract(i, out)
        mode = i.external_attr >> 16
        if mode and not i.is_dir(): os.chmod(p, mode & 0o7777)
PY
[ -x "$L/electron.new/electron" ] || { echo "unpack failed"; rm -rf "$L/electron.new"; exit 1; }
rm -rf "$L/electron"; mv "$L/electron.new" "$L/electron"
echo "electron $(cat "$L/electron/version") installed in $L/electron"
