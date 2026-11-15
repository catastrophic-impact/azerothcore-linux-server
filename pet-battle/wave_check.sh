#!/bin/sh
# WAVE CHECK (host): run from the project root:  flatpak-spawn --host sh pet-battle/wave_check.sh
# tests + stand-in audit + gap census + privacy sweep of every changed/untracked file (excluding gitignored); prints the file list for the commit block.
fail=0
sh pet-battle/run_tests.sh 2>&1 | grep -E "FAIL|ALL TESTS PASSED|TESTS FAILED" ; sh pet-battle/run_tests.sh >/dev/null 2>&1 || fail=1
echo "== audit_standins"; sh pet-battle/audit_standins.sh 2>&1 | grep -v "^==" | grep -v "^[0-9]*$" | head -5
echo "== gap census"; python3 -I pet-battle/gap_census.py 5 | head -3
FILES=$(git status --short | awk '{print $2}' | grep -v '^pet-battle/\.' )
echo "== privacy sweep of $(echo "$FILES" | wc -w) files"
for f in $FILES; do [ "$f" != "pet-battle/wave_check.sh" ] && [ -f "$f" ] && grep -nEi "[a-z0-9._-]+@[a-z0-9-]+\.(com|net|org)|/home/deck|192\.168\.|passwd=|secret=|api[_-]?key" "$f" | grep -v '^README.md' | sed "s|^|$f: |" ; done
echo "== files for the commit block"; echo "$FILES"
[ $fail = 0 ] && echo "WAVE CHECK: OK" || echo "WAVE CHECK: TESTS FAILED"
