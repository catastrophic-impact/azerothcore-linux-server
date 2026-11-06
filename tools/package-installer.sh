#!/usr/bin/env bash
# Builds dist/acore-install.sh: ONE self-extracting file holding the installer and everything it needs (build scripts, patches, config
# overrides, Lua scripts, client addons, custom SQL, admin TUI source). Nothing private is included (no local/, DEVNOTES, release/, cache/).
# usage: tools/package-installer.sh        run the result anywhere:  ./acore-install.sh [--dest DIR] [--box NAME] [--clean-box] [--accounts FILE] [--no-configure] [--yes] [--no-garrison|--no-jukebox|--no-shop|--no-bots|--no-timewalking]
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; cd "$HERE"
mkdir -p dist
tar czf dist/payload.tgz --exclude='*.pyc' install.sh modules.lock tools/rebuild.sh tools/components.sh tools/apply_overrides.py tools/wotlk_garrison_admin patches config-overrides scripts addons custom-sql \
    tui/*.go tui/go.mod tui/go.sum
cat > dist/acore-install.sh <<'STUB'
#!/usr/bin/env bash
# Self-extracting AzerothCore (Playerbot fork) portable-server installer. Extracts to ./.acore-work, runs, then cleans up.
set -euo pipefail
SELF="$(readlink -f "$0")"
WORK="${ACORE_WORK:-$PWD/.acore-work}"
export ACORE_CACHE="${ACORE_CACHE:-$(dirname "$SELF")/acore-install-cache}"   # downloads (MySQL, client data) are kept here and reused
rm -rf "$WORK"; mkdir -p "$WORK"
tail -n +"$(awk '/^__PAYLOAD__$/{print NR + 1; exit}' "$SELF")" "$SELF" | tar xz -C "$WORK"
rc=0; bash "$WORK/install.sh" "$@" || rc=$?
[ "$rc" = 0 ] && rm -rf "$WORK" || echo "kept $WORK for debugging (failed with exit code $rc)"
exit "$rc"
__PAYLOAD__
STUB
cat dist/payload.tgz >> dist/acore-install.sh; rm dist/payload.tgz; chmod +x dist/acore-install.sh
echo "built dist/acore-install.sh ($(du -h dist/acore-install.sh | cut -f1))"
