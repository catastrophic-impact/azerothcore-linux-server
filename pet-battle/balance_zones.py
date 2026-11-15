#!/usr/bin/env python3 -I
"""Per-zone-band balance check (HOST needed for luajit): python3 -I pet-battle/balance_zones.py <zone> [<zone> ...] [--duels 40] [--repick]
Measures ONLY the species of the named zones (roster Y rows) at the zones' pet levels (lo..hi union), opponents from the whole roster, then optionally applies ONE auto_repick round.
Writes pet-battle/.bal_<first zone>.txt. Flags non-critters >= 82% or <= 5% (the PM rule)."""
import sys, re, subprocess, os
args = [a for a in sys.argv[1:] if not a.startswith('--')]; duels = '40'
if '--duels' in sys.argv: duels = sys.argv[sys.argv.index('--duels') + 1]; args = [a for a in args if a != duels]
rows = {}
for l in open('pet-battle/zone_ranges.tsv', encoding='utf-8'):
    c = l.rstrip('\n').split('\t')
    if c and not c[0].startswith('#') and len(c) > 10: rows[c[0]] = c
ents, levels = set(), set()
for z in args:
    r = rows[z]; lo, hi = int(r[8]), int(r[9]); levels |= set(range(lo, hi + 1))
    for l in open('pet-battle/%s_roster.tsv' % z, encoding='utf-8'):
        c = l.rstrip('\n').split('\t')
        if len(c) > 1 and c[0] == 'Y' and c[1].isdigit(): ents.add(c[1])
src = open('scripts/pb_data.lua').read()
shipped = set(re.findall(r'\[(\d+)\] = \{ name = "[^"]*", retail =', src))
ents = sorted([e for e in ents if e in shipped], key=int)
base = '.bal_' + args[0]
open('pet-battle/%s_species.txt' % base, 'w').write('\n'.join(ents) + '\n')
out = 'pet-battle/%s.txt' % base
lv = ','.join(str(x) for x in sorted(levels))
print('measuring %d species at levels %s (%s duels each)' % (len(ents), lv, duels))
subprocess.run(['sh', '-c', 'luajit pet-battle/sim_balance.lua %s %s pet-battle/%s_species.txt > %s 2>&1' % (duels, lv, base, out)], check=True)
print(open(out).read().strip().splitlines()[-1])
if '--repick' in sys.argv: subprocess.run(['python3', '-I', 'pet-battle/auto_repick.py', out, '82', '5'], check=True)
