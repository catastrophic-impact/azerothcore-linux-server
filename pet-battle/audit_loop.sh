#!/bin/sh
# Label-audit -> blocklist -> rebuild loop (HOST, repo root): sh pet-battle/audit_loop.sh [max iterations] [battles]
N="${1:-6}"; B="${2:-3000}"; LOG=pet-battle/.s/audit_loop.log; : > "$LOG"
for i in $(seq 1 "$N"); do
  luajit pet-battle/audit_labels.lua "$B" 5 > pet-battle/.s/audit_it$i.txt 2>&1
  f=$(grep -c "BUFF THAT HURTS\|TURNS TOO HIGH\|BAD LABEL" pet-battle/.s/audit_it$i.txt)
  echo "== iteration $i: $f findings" >> "$LOG"
  [ "$f" = "0" ] && break
  b=$(wc -l < pet-battle/ability_blocklist.txt)
  python3 -I pet-battle/tests_to_blocklist.py pet-battle/.s/audit_it$i.txt >> "$LOG" 2>&1
  [ "$b" = "$(wc -l < pet-battle/ability_blocklist.txt)" ] && { echo "nothing new learned: stop" >> "$LOG"; break; }
  sh pet-battle/rebuild_wild.sh >> "$LOG" 2>&1 || { echo "rebuild failed" >> "$LOG"; break; }
done
echo "== done" >> "$LOG"
