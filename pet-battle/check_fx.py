#!/usr/bin/env python3
"""Fails if a visual spell used by the pet battle script is not instant (no duration, no aura): such spells stay on the pet.
usage: python3 -I pet-battle/check_fx.py   (run from the project root; reads release/data/dbc)"""
import re, struct, sys
src = open('scripts/pb_battle.lua').read()
ids = set(int(x) for x in re.findall(r'\b(\d{4,6})\b', ' '.join(l for l in src.split('\n') if 'FX_' in l and l.strip().startswith('local FX'))))
ids |= set(int(x) for x in re.findall(r'Fx\([^)]*?,\s*(\d{4,6})\s*,', src))
d = open('release/data/dbc/Spell.dbc', 'rb').read(); _, c, f, rs, _ = struct.unpack('<4sIIII', d[:20]); sb = 20 + c * rs
dur = open('release/data/dbc/SpellDuration.dbc', 'rb').read(); _, dc, df, drs, _ = struct.unpack('<4sIIII', dur[:20])
D = {struct.unpack_from('<%di' % df, dur, 20 + i * drs)[0]: struct.unpack_from('<%di' % df, dur, 20 + i * drs)[1] for i in range(dc)}
bad = 0
for i in range(c):
    r = struct.unpack_from('<%dI' % f, d, 20 + i * rs)
    if r[0] in ids:
        name = d[sb + r[136]:d.index(b'\0', sb + r[136])].decode()
        aura = any(r[95 + e] for e in range(3)) or any(r[71 + e] == 6 for e in range(3))
        ms = D.get(r[40])
        ok = not aura and not ms
        print(('ok  ' if ok else 'BAD ') + str(r[0]), name, '| duration', ms, '| applies aura' if aura else '')
        bad += not ok
sys.exit(1 if bad else 0)
