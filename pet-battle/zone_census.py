#!/usr/bin/env python3 -I
"""Per-zone census for the Outland/Northrend scale-up. Assigns every eligible creature kind to ONE zone (where most of its spawns sit, by the client's WorldMapArea boxes: the creature table's zoneId
column is empty), drops kinds that are already species (D.species in scripts/pb_data.lua) and the zones that are shipped or excluded (Eversong, Azuremyst, Bloodmyst, Isle of Quel'Danas),
and writes the census in the 9-column format family_rules.py reads (first column = zone name).
Inputs (pet-battle/.s/, from acore_world; filters: rank 0, npcflag 0, maxlevel <= 82, type not in 10..15, maps 530/571):
  census2.tsv : map, entry, name, type, family, rank, minlevel, maxlevel, spawns          spawns.tsv : entry, map, x, y, minlevel, maxlevel
Usage (repo root): python3 -I pet-battle/zone_census.py > pet-battle/zone_census.tsv     (stderr = per-zone summary)"""
import struct, re, collections
BAD = ('guard', 'citizen', 'celebrant', 'protector', 'woodworker', 'lumberjack', 'spirit', 'turkey', 'farmer', 'militia', 'watchman', 'deputy', 'peasant', 'dockworker', 'merchant', 'innkeeper')   # gen_zone.py
PRUNE = re.compile(r'\b(corpse|bunny|trigger|dummy|target|orphan|reveler|celebrant|invisible|stalker bunny|\[dn[dt]\]|training|projection|event|worker|guard|citizen|villager|peasant)\b', re.I)   # zone_batch.py
Z = {3483: 'Hellfire Peninsula', 3521: 'Zangarmarsh', 3519: 'Terokkar Forest', 3518: 'Nagrand', 3522: "Blade's Edge Mountains", 3523: 'Netherstorm', 3520: 'Shadowmoon Valley',
     3537: 'Borean Tundra', 495: 'Howling Fjord', 65: 'Dragonblight', 394: 'Grizzly Hills', 66: "Zul'Drak", 3711: 'Sholazar Basin', 67: 'The Storm Peaks', 210: 'Icecrown', 2817: 'Crystalsong Forest', 4197: 'Wintergrasp'}
SKIP = {3430: 'Eversong Woods', 3524: 'Azuremyst Isle', 3525: 'Bloodmyst Isle', 4080: "Isle of Quel'Danas"}   # shipped / excluded: they still take part in the nearest-box test so their creatures do not leak into a neighbour
d = open('release/data/dbc/WorldMapArea.dbc', 'rb').read(); _, c, f, rs, ss = struct.unpack('<4sIIII', d[:20]); fl = lambda v: struct.unpack('<f', struct.pack('<I', v))[0]
boxes = []
for i in range(c):
    r = struct.unpack_from('<%dI' % f, d, 20 + i * rs)
    if r[2] in Z or r[2] in SKIP:
        L, R, T, B = [fl(x) for x in r[4:8]]; boxes.append((r[2], r[1], min(B, T), max(B, T), min(L, R), max(L, R)))
cnt = collections.defaultdict(collections.Counter)
for l in open('pet-battle/.s/spawns.tsv'):
    e, m, x, y, lo, hi = l.split(); m = int(m); x = float(x); y = float(y); best = None
    for a, mp, x0, x1, y0, y1 in boxes:
        if mp == m and x0 <= x <= x1 and y0 <= y <= y1:
            dist = (x - (x0 + x1) / 2) ** 2 + (y - (y0 + y1) / 2) ** 2
            if best is None or dist < best[1]: best = (a, dist)
    cnt[e][best[0] if best else 0] += 1
zone = {e: cc.most_common(1)[0][0] for e, cc in cnt.items()}
have = set(re.findall(r'^\s*\[(\d+)\] = \{ name = ', open('scripts/pb_data.lua').read().split('D.species = {')[1], re.M))
n = collections.Counter(); lv = collections.defaultdict(lambda: [99, 0]); dropped = collections.Counter()
for l in open('pet-battle/.s/census2.tsv'):
    m, e, name, t, cf, rk, lo, hi, sp = l.rstrip('\n').split('\t'); z = zone.get(e, 0)
    if int(sp) < 3: dropped['fewer than 3 spawns'] += 1; continue          # gen_zone.py: HAVING sp>=3
    if any(b in name.lower() for b in BAD) or PRUNE.search(name) or t in ('0', '10', '11', '12'): dropped['citizen/guard/event/odd type'] += 1; continue
    if z not in Z: dropped['skipped zone/none' if z in SKIP or z == 0 else '?'] += 1; continue
    if e in have: dropped['already a species'] += 1; continue
    print('\t'.join([Z[z], e, name, t, cf, rk, lo, hi, sp])); n[Z[z]] += 1
    a = lv[Z[z]]; a[0] = min(a[0], int(lo)); a[1] = max(a[1], int(hi))
import sys
print('kept %d creature kinds in %d zones; dropped %s' % (sum(n.values()), len(n), dict(dropped)), file=sys.stderr)
for zn, k in sorted(n.items()): print('  %-24s %4d kinds, mob level %d-%d' % (zn, k, lv[zn][0], lv[zn][1]), file=sys.stderr)
