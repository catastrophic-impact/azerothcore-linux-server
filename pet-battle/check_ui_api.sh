#!/bin/sh
# Static check of the client addons for APIs that do not exist in WoW 3.3.5 (and that every .toc lists only existing files).
# Run from the project root:  flatpak-spawn --host sh pet-battle/check_ui_api.sh   (exits non-zero on any hit)
fail=0
# pattern|why   (comments are stripped before matching; table.wipe / wipe are fine in 3.3.5)
PATTERNS='SetShown|added in 4.0 (use ShowIf / Show()/Hide())
SetEnabled|added in 4.0 (use Enable()/Disable())
C_Timer|added in 6.0
C_[A-Z][A-Za-z]*|C_ namespaces are 6.0+
SetColorTexture|added in 5.x (use SetTexture(r,g,b,a))
string\.split|not a 3.3.5 function (use strsplit)
strsplittable|added in 8.x
SetClipsChildren|added in 7.x
SetObeyStepOnDrag|added in 4.x
Mixin|added in 6.0
CreateFromMixin|added in 6.0
SetAtlas|atlases are 4.x+
'
hits=$(mktemp); trap 'rm -f "$hits"' EXIT
echo "$PATTERNS" | while IFS='|' read -r pat why; do
  [ -n "$pat" ] || continue
  for f in addons/wotlk_pets/*.lua addons/wotlk_minimap/*.lua; do
    [ -f "$f" ] || continue
    sed -e 's/--.*$//' "$f" | grep -nE "$pat" | sed "s|^|API FAIL $f:|; s|\$|   <- $why|" >> "$hits"
  done
done
if [ -s "$hits" ]; then sort -u "$hits"; fail=1; fi
# every file named in a .toc must exist next to it
for toc in addons/wotlk_pets/*.toc addons/wotlk_minimap/*.toc; do
  [ -f "$toc" ] || continue
  d=$(dirname "$toc")
  grep -v '^[[:space:]]*##' "$toc" | tr -d '\r' | grep -v '^[[:space:]]*$' | while read -r ent; do
    [ -f "$d/$ent" ] || { echo "TOC FAIL $toc: listed file missing: $ent"; exit 1; }
  done || fail=1
done
[ "$fail" = 0 ] && echo "ui api check: OK"
exit $fail
