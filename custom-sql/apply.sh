#!/usr/bin/env bash
# Apply our custom-sql files to YOUR server, whatever your databases are called. Not needed on our own server (the admin tool applies these on every start).
#
#   custom-sql/apply.sh [--world NAME] [--characters NAME] [--only 002,008,015] [--dry-run] -- <mysql client arguments>
#   custom-sql/apply.sh --remove garrison,pets,timewalking [--dry-run] -- <mysql arguments>          remove what a component's files created (content)
#   custom-sql/apply.sh --remove-data garrison,pets --yes [--dry-run] -- <mysql arguments>           ALSO delete the players' data tables (NOT undoable)
#   Removal: stop the server, delete the component's scripts (or it installs itself again), back up, run this, start the server.
#
# --world / --characters   your world and characters database names (default: acore_world / acore_characters)
# --only                   file number prefixes to apply (default: every file). See tools/components.sh for which files belong to which piece.
# --dry-run                print the files that would be applied and the database names, run nothing
# everything after `--`    is passed to the mysql client (user, password, host or socket), e.g.  -- -uacore -p'secret' -h127.0.0.1
# MYSQL=/path/to/mysql     use a specific mysql client binary
#
# The files are idempotent: running them again is safe. They name their database with a USE line; this script swaps the default
# names for yours on the fly and never edits the files.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORLD=acore_world; CHARS=acore_characters; ONLY=""; DRY=0; REMOVE=""; REMOVEDATA=""; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --world) WORLD="$2"; shift 2;;
    --characters) CHARS="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    --remove) REMOVE="$2"; shift 2;;
    --remove-data) REMOVEDATA="$2"; shift 2;;
    --yes) YES=1; shift;;
    --) shift; break;;
    *) echo "unknown option $1 (see the header of this script)"; exit 2;;
  esac
done
for n in "$WORLD" "$CHARS"; do
  case "$n" in *[!A-Za-z0-9_]*|"") echo "database name '$n' may only contain letters, digits and _"; exit 2;; esac
done
MYSQL="${MYSQL:-mysql}"
if [ -n "$REMOVE$REMOVEDATA" ]; then
  [ -z "$REMOVEDATA" ] || [ $YES = 1 ] || { echo "--remove-data deletes player data for good: add --yes to confirm (back up first)"; exit 2; }
  todo=()
  for n in $(echo "$REMOVE" | tr ',' ' '); do todo+=("$n"); done
  for n in $(echo "$REMOVEDATA" | tr ',' ' '); do todo+=("${n}_playerdata"); done
  for n in "${todo[@]}"; do
    case "$n" in *[!a-z_]*) echo "bad component name '$n'"; exit 2;; esac
    [ -f "$HERE/remove/$n.sql" ] || { echo "no removal file for '$n' (available: $(cd "$HERE/remove" && ls *.sql | sed 's/\.sql$//' | tr '\n' ' '))"; exit 2; }
  done
  echo "world database: $WORLD   characters database: $CHARS   removing: ${todo[*]}"
  for n in "${todo[@]}"; do
    if [ $DRY = 1 ]; then echo "  would run remove/$n.sql"; continue; fi
    if sed -E "s/\b(acore_world)\b/$WORLD/g; s/\b(acore_characters)\b/$CHARS/g" "$HERE/remove/$n.sql" | "$MYSQL" "$@"; then echo "  removed $n"
    else echo "  FAILED  remove/$n.sql (stopped)"; exit 1; fi
  done
  echo "done: now start the server"; exit 0
fi
files=()
for f in "$HERE"/*.sql; do
  b="$(basename "$f")"
  if [ -n "$ONLY" ]; then case ",$ONLY," in *",${b%%_*},"*) ;; *) continue;; esac; fi
  files+=("$f")
done
[ ${#files[@]} -gt 0 ] || { echo "no sql files selected"; exit 2; }
echo "world database: $WORLD   characters database: $CHARS   files: ${#files[@]}"
for f in "${files[@]}"; do
  b="$(basename "$f")"
  if [ $DRY = 1 ]; then echo "  would apply $b"; continue; fi
  # only the two database names are swapped; the word boundary keeps unrelated text (acore_settings ...) alone
  if sed -E "s/\b(acore_world)\b/$WORLD/g; s/\b(acore_characters)\b/$CHARS/g" "$f" | "$MYSQL" "$@"; then echo "  applied $b"
  else echo "  FAILED  $b (stopped: fix the error above, then run again; the files are safe to repeat)"; exit 1; fi
done
echo "done"
