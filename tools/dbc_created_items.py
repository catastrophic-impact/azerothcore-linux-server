#!/usr/bin/env python3
"""List item entries that any spell can CREATE (SPELL_EFFECT_CREATE_ITEM=24): i.e. profession-crafted items.
usage: dbc_created_items.py <Spell.dbc> [itemtype_offset]   -> prints item ids, one per line"""
import struct, sys
path = sys.argv[1]; off = int(sys.argv[2]) if len(sys.argv) > 2 else 110
d = open(path, 'rb').read()
magic, nrec, nfld, rsize, ssize = struct.unpack('<4sIIII', d[:20])
assert magic == b'WDBC' and nfld * 4 == rsize
items = set()
for r in range(nrec):
    rec = struct.unpack_from('<%dI' % nfld, d, 20 + r * rsize)
    for e in range(3):
        if rec[71 + e] == 24 and rec[off + e]: items.add(rec[off + e])
print('\n'.join(map(str, sorted(items))))
