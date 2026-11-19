#!/bin/sh
# Test -> ban rejected visual names -> rebuild, until the quick tier passes or nothing new is learned (HOST, repo root): sh pet-battle/names_loop.sh [max iterations]
N="${1:-6}"; LOG=pet-battle/.s/names_loop.log; : > "$LOG"
for i in $(seq 1 "$N"); do
  sh pet-battle/run_tests.sh quick > pet-battle/.s/tests_names$i.txt 2>&1
  if ! grep -q "TESTS FAILED" pet-battle/.s/tests_names$i.txt; then echo "== iteration $i: TESTS PASSED" >> "$LOG"; break; fi
  echo "== iteration $i: $(grep -c FAIL pet-battle/.s/tests_names$i.txt) FAIL lines" >> "$LOG"
  b=$(wc -l < pet-battle/ability_blocklist.txt); n=$(wc -l < pet-battle/ability_novis.txt)
  python3 -I pet-battle/tests_to_blocklist.py pet-battle/.s/tests_names$i.txt >> "$LOG" 2>&1
  [ "$b $n" = "$(wc -l < pet-battle/ability_blocklist.txt) $(wc -l < pet-battle/ability_novis.txt)" ] && { echo "nothing new learned: stop" >> "$LOG"; break; }
  sh pet-battle/rebuild_wild.sh >> "$LOG" 2>&1 || { echo "rebuild failed" >> "$LOG"; break; }
done
echo "== done" >> "$LOG"
