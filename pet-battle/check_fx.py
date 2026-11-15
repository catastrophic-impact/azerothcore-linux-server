#!/usr/bin/env python3
"""Fails if a visual spell used by the pet battle script is not instant (no duration, no aura): such spells stay on the pet.
usage: python3 -I pet-battle/check_fx.py   (run from the project root; reads release/data/dbc)"""
import re, struct, sys
src = open('scripts/pb_battle.lua').read()
ids = set(int(x) for x in re.findall(r'\b(\d{4,6})\b', ' '.join(l for l in src.split('\n') if 'FX_' in l and l.strip().startswith('local FX'))))
ids |= set(int(x) for x in re.findall(r'Fx\([^)]*?,\s*(\d{4,6})\s*,', src))
core = open('scripts/pb_core.lua').read()   # the themed ability visuals (THEME_VIS rows) must be instant too
block = core[core.index('local THEME_VIS'):core.index('local function ThemeVis')]
ids |= set(int(x) for x in re.findall(r',\s*(\d{4,6})\s*}', block))
d = open('release/data/dbc/Spell.dbc', 'rb').read(); _, c, f, rs, _ = struct.unpack('<4sIIII', d[:20]); sb = 20 + c * rs
dur = open('release/data/dbc/SpellDuration.dbc', 'rb').read(); _, dc, df, drs, _ = struct.unpack('<4sIIII', dur[:20])
D = {struct.unpack_from('<%di' % df, dur, 20 + i * drs)[0]: struct.unpack_from('<%di' % df, dur, 20 + i * drs)[1] for i in range(dc)}
bad = 0
# themed ability visuals must show a PROJECTILE that lands: school damage effect, travel speed > 0, a missile model (a dummy or speed-0 spell shows no missile)
vd = open('release/data/dbc/SpellVisual.dbc', 'rb').read(); _, vc, vf, vrs, _ = struct.unpack('<4sIIII', vd[:20])
VIS = {struct.unpack_from('<%dI' % vf, vd, 20 + i * vrs)[0]: struct.unpack_from('<%dI' % vf, vd, 20 + i * vrs) for i in range(vc)}
theme_ids = set(int(x) for x in re.findall(r',\s*(\d{3,6})\s*}', block))
for i in range(c):
    r = struct.unpack_from('<%dI' % f, d, 20 + i * rs)
    if r[0] in theme_ids:
        speed = struct.unpack('<f', struct.pack('<I', r[47]))[0]; v = VIS.get(r[131])
        if 2 not in (r[71], r[72], r[73]) or speed <= 0 or not v or not v[7]: print('BAD projectile', r[0], 'effect', r[71], 'speed', speed, 'missile', bool(v and v[7])); bad += 1
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
