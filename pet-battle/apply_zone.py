#!/usr/bin/env python3 -I
"""Apply a zone's hand-picked kits: reads pet-battle/<zone>_roster.tsv (include=Y rows) and pet-battle/<zone>_picks.tsv, then
  (1) appends `[entry] = { name, retail, [critter = true,] wild = true, icon }` lines to D.species in scripts/pb_data.lua (species that already exist are skipped),
  (2) adds the D.zones row and the zone id to ZONES in scripts/pb_wild.lua, (3) regenerates scripts/pb_retail.lua (gen_retail.py).
Usage: python3 -I pet-battle/apply_zone.py <zone> <zoneId> <retailLo> <retailHi> <minMob> <maxMob> "<Zone Name>"
picks.tsv columns (tab): entry <TAB> retail species id <TAB> icon <TAB> flags (optional: critter)   (lines starting with # ignored)
Kit rules: pick ORDINARY retail wild species of the same kind (never Passive_Boss / Passive_Elite / Internal_InitialLevel species: the script refuses them)."""
import sys, re, csv, subprocess, collections
zone, zid, lo, hi, mn, mx, zname = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]
roster = {}
for l in open('pet-battle/%s_roster.tsv' % zone, encoding='utf-8'):
    if l.startswith('#') or l.startswith('include'): continue
    p = l.rstrip('\n').split('\t')
    if p[0] == 'Y': roster[p[1]] = p
picks = {}
for l in open('pet-battle/%s_picks.tsv' % zone, encoding='utf-8'):
    if l.startswith('#') or not l.strip(): continue
    p = l.rstrip('\n').split('\t'); picks[p[0]] = p
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
sx = collections.Counter(x['BattlePetSpeciesID'] for x in R('BattlePetSpeciesXAbility'))
stn = {s['ID']: s['LuaName'] for s in R('BattlePetState')}
bad = collections.defaultdict(list)
for x in R('BattlePetSpeciesState'):
    k = stn.get(x['BattlePetStateID'], ''); v = int(x['Value'])
    if 'Passive_Boss' in k or 'Passive_Elite' in k or k == 'Internal_InitialLevel': bad[x['BattlePetSpeciesID']].append(k)
    if (k == 'Stat_Power' and v >= 200) or (k == 'Stat_Stamina' and v >= 300) or (k == 'Stat_Speed' and v >= 300): bad[x['BattlePetSpeciesID']].append('%s=%d (NPC-style stat bonus)' % (k, v))
src = open('scripts/pb_data.lua').read()
existing = set(re.findall(r'\[(\d+)\] = \{ name', src))
lines, problems = [], []
for e, r in roster.items():
    if e in existing: continue
    if e not in picks: problems.append('no pick for %s %s' % (e, r[2])); continue
    p = picks[e]; rid, icon = p[1], p[2]; flags = (p[3] if len(p) > 3 else '')
    if not sx.get(rid): problems.append('retail species %s has no abilities (%s)' % (rid, r[2])); continue
    if bad.get(rid): problems.append('retail species %s is a boss/elite kit %s (%s)' % (rid, bad[rid], r[2])); continue
    lines.append('    [%s] = { name = "%s", retail = %s, %swild = true, icon = "%s" },' % (e, r[2], rid, 'critter = true, ' if 'critter' in flags else '', icon))
extra = [e for e in picks if e not in roster]
if extra: problems.append('picks for entries not in the roster (include=Y): %s' % ','.join(extra))
if problems:
    print('\n'.join('PROBLEM ' + x for x in problems)); sys.exit(1)
i = src.index('-- EVERY species spawns from a stand-in'); j = src.rindex('\n}', 0, i)
src = src[:j] + '\n    -- ---- %s roster (retail pet levels %s-%s; kits hand-picked, %s_picks.tsv)\n' % (zname, lo, hi, zone) + '\n'.join(lines) + src[j:]
row = '    [%s] = { name = "%s", lo = %s, hi = %s, minMob = %s, maxMob = %s },\n' % (zid, zname, lo, hi, mn, mx)
k = src.index('D.zones = {\n') + len('D.zones = {\n'); e2 = src.index('\n}', k)
if '[%s] = {' % zid not in src[k:e2]: src = src[:e2 + 1] + row + src[e2 + 1:]
open('scripts/pb_data.lua', 'w').write(src)
w = open('scripts/pb_wild.lua').read()
if '[%s] = true' % zid not in w.split('\n')[9]: w = w.replace('local ZONES = { ', 'local ZONES = { [%s] = true, ' % zid, 1)
open('scripts/pb_wild.lua', 'w').write(w)
ids = sorted(set(re.findall(r'retail = (\d+)', src)), key=int)
subprocess.run(['python3', '-I', 'pet-battle/gen_retail.py'] + ids, check=True)
print('%d new species for %s, zone %s enabled' % (len(lines), zname, zid))
