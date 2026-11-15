#!/usr/bin/env python3 -I
"""List the species in scripts/pb_data.lua whose retail kit contains an ability from the OPEN-GAP list (not implemented): python3 -I pet-battle/find_gaps.py   (edit GAP_ABILITIES when one is implemented). Then fix with rekit.py."""
import re
GAP_ABILITIES = {'652': 'Haunt (effect 230/165)', '323': 'Gravity (effect 86)', '794': 'Dark Rebirth (138/111)', '795': 'Dark Rebirth (138/111)', '120': 'Howling Blast (138)', '267': 'Photosynthesis (171)', '785': 'Blistering Cold (140)'}
d = open('scripts/pb_data.lua').read(); used = {}
for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]*)", retail = (\d+)', d): used.setdefault(m.group(3), []).append((m.group(1), m.group(2)))
for l in open('scripts/pb_retail.lua'):
    m = re.match(r'R.species\[(\d+)\] = \{ name = "([^"]*)"', l)
    if not m: continue
    hit = [GAP_ABILITIES[a] for a in re.findall(r'\{ \d, \d+, (\d+) \}', l) if a in GAP_ABILITIES]
    if hit and m.group(1) in used: print('retail %s %s -> %s  uses %s' % (m.group(1), m.group(2), used[m.group(1)], hit))
