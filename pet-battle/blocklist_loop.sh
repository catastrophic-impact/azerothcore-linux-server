#!/bin/sh
# Test -> blocklist -> rebuild loop for the composed kits (HOST, repo root): sh pet-battle/blocklist_loop.sh [max iterations]
# Stops when run_tests.sh quick passes, or when a round blocks nothing new (then the remaining failures need a human look).
N="${1:-5}"; LOG=pet-battle/.s/blocklist_loop.log; : > "$LOG"
for i in $(seq 1 "$N"); do
  sh pet-battle/run_tests.sh quick > pet-battle/.s/tests_loop$i.txt 2>&1
  if grep -q "TESTS FAILED" pet-battle/.s/tests_loop$i.txt; then
    echo "== iteration $i: FAILED ($(grep -c FAIL pet-battle/.s/tests_loop$i.txt) FAIL lines)" >> "$LOG"
    python3 -I pet-battle/tests_to_blocklist.py pet-battle/.s/tests_loop$i.txt >> "$LOG" 2>&1
    new=$(tail -n 1 "$LOG" | sed -n 's/^blocklist: +\([0-9]*\) new.*/\1/p')
    [ "$new" = "0" ] && { echo "nothing new to block: stop" >> "$LOG"; break; }
    sh pet-battle/rebuild_wild.sh >> "$LOG" 2>&1 || { echo "rebuild failed" >> "$LOG"; break; }
  else echo "== iteration $i: TESTS PASSED" >> "$LOG"; break; fi
done
echo "== done" >> "$LOG"
