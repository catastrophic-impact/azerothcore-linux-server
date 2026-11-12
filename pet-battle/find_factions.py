#!/usr/bin/env python3 -I
"""Find faction template pairs for pb_cast: X hostile to Y (a real spell only lands on an attackable target), but BOTH friendly to every player race of a side and hostile to
no guard faction of that side (so the names stay green and city guards stay calm). Reads release/data/dbc/FactionTemplate.dbc with the core's own rules (FactionTemplateEntry).
Result used (works for Alliance AND Horde): attacker 1690, target 1691."""
import struct
d = open('release/data/dbc/FactionTemplate.dbc', 'rb').read()
_, rc, fc, rs, ss = struct.unpack('<4sIIII', d[:20])
T = {}
for i in range(rc):
    f = struct.unpack('<' + 'I' * fc, d[20 + i * rs:20 + i * rs + rs])
    T[f[0]] = dict(id=f[0], faction=f[1], flags=f[2], group=f[3], friend=f[4], enemy=f[5], enemies=[x for x in f[6:10] if x], friends=[x for x in f[10:14] if x])
def hostile(a, b):
    if a['id'] == b['id']: return False
    if b['faction']:
        if b['faction'] in a['enemies']: return True
        if b['faction'] in a['friends']: return False
    return (a['enemy'] & b['group']) != 0
def friendly(a, b):
    if a['id'] == b['id']: return True
    if b['faction']:
        if b['faction'] in a['enemies']: return False
        if b['faction'] in a['friends']: return True
    return ((a['friend'] & b['group']) != 0) or ((a['group'] & b['friend']) != 0)
sides = {'Alliance': ([1, 3, 4, 115, 1629], [11, 12, 79]), 'Horde': ([2, 5, 6, 116, 1610], [85, 68, 104])}
res = None
for name, (pl, gd) in sides.items():
    c = [i for i in T if i >= 2 and all(friendly(T[i], T[p]) and not hostile(T[i], T[p]) and not hostile(T[p], T[i]) for p in pl) and not any(hostile(T[g], T[i]) or hostile(T[i], T[g]) for g in gd)]
    pairs = set((a, b) for a in c for b in c if hostile(T[a], T[b]) and T[a]['flags'] == 0 and T[b]['flags'] == 0)
    res = pairs if res is None else res & pairs
print(sorted(res)[:20])
