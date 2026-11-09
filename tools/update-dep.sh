#!/usr/bin/env bash
# Vendor an upstream dependency into deps/ (no .git) and record it in modules.lock.
#   tools/update-dep.sh <name> [commit-or-branch]    name = core | mod-xxx
#   tools/update-dep.sh --all                        re-vendor everything at its locked commit
# With no ref, the commit already in modules.lock is used (core: branch Playerbot if unlocked).
set -euo pipefail
cd "$(dirname "$0")/.."
LOCK=modules.lock
CORE_URL="https://github.com/mod-playerbots/azerothcore-wotlk.git"; CORE_BRANCH="Playerbot"

vendor() {
  local name=$1 ref=${2:-} url sha dest tmp
  if [ "$name" = core ]; then
    url=$CORE_URL; dest=deps/core; ref=${ref:-$(awk '$1=="core"{print $2}' $LOCK 2>/dev/null)}; ref=${ref:-$CORE_BRANCH}
  else
    url=$(awk -v n="$name" '$1==n{print $3}' $LOCK); [ -n "$url" ] || { echo "unknown module $name (add it to $LOCK first: '$name <sha> <url>')"; return 1; }
    dest=deps/modules/$name; ref=${ref:-$(awk -v n="$name" '$1==n{print $2}' $LOCK)}
  fi
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  git -C "$tmp" init -q; git -C "$tmp" remote add origin "$url"
  git -C "$tmp" fetch -q --depth 1 origin "$ref"; git -C "$tmp" checkout -q FETCH_HEAD
  sha=$(git -C "$tmp" rev-parse HEAD); rm -rf "$tmp/.git"
  if [ "$name" = core ]; then rm -rf "$tmp/.github" "$tmp/e2e" "$tmp/data/sql/old" "$tmp/data/sql/archive"; fi  # historical SQL + CI: not used by build/import
  find "$tmp" \( -name .gitignore -o -name .gitattributes \) -type f -delete  # would otherwise hide/alter files inside our repo
  rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; mv "$tmp" "$dest"; trap - RETURN
  if [ "$name" = core ]; then
    if grep -q '^core ' $LOCK; then sed -i "s|^core .*|core $sha $CORE_BRANCH|" $LOCK; else echo "core $sha $CORE_BRANCH" >> $LOCK; fi
  else sed -i "s|^$name .*|$name $sha $url|" $LOCK; fi
  echo "vendored $name @ ${sha:0:10}"
}

if [ "${1:-}" = --all ]; then
  for n in core $(awk '/^mod-/{print $1}' $LOCK); do vendor "$n"; done
else vendor "$@"; fi
