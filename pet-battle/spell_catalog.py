#!/usr/bin/env python3 -I
"""Catalog of the 3.3.5 spells that can lend their NAME + VISUAL to a pet-battle ability (numbers always stay retail pet-battle).
Usage (repo root): python3 -I pet-battle/spell_catalog.py > pet-battle/spell_catalog.tsv
Sources (release/data/dbc): hunter/warlock/DK pet skill lines per CreatureFamily (family-specific line only; line 270 'Generic Hunter' is a separate source 'pet:generic'),
and the class skill lines (SkillLineAbility.ClassMask). Passives, DND, scaling, talents-only entries are dropped; ranks collapse to the highest-id rank per (source,name).
role = first matching rule of the spell's effects: dmg / dot / heal / hot / stun / root / fear / slow / buff / debuff / shield / stealth / dispel / summon / dummy."""
import struct, collections, re
def dbc(name):
    d = open('release/data/dbc/%s.dbc' % name, 'rb').read(); _, c, f, rs, ss = struct.unpack('<4sIIII', d[:20])
    recs = [struct.unpack_from('<%dI' % f, d, 20 + i * rs) for i in range(c)]; sb = 20 + c * rs
    return recs, (lambda off: d[sb + off:d.index(b'\0', sb + off)].decode('latin1'))
SL, sls = dbc('SkillLine'); SLN = {r[0]: (r[1], sls(r[3])) for r in SL}
CF, cfs = dbc('CreatureFamily'); SLA, _ = dbc('SkillLineAbility'); SP, sps = dbc('Spell'); SPI = {r[0]: r for r in SP}
CLS = {1: 'Warrior', 2: 'Paladin', 4: 'Hunter', 8: 'Rogue', 16: 'Priest', 32: 'DeathKnight', 64: 'Shaman', 128: 'Mage', 256: 'Warlock', 1024: 'Druid'}
SCH = {1: 'physical', 2: 'holy', 4: 'fire', 8: 'nature', 16: 'frost', 32: 'shadow', 64: 'arcane'}
# aura names
A_DOT, A_HOT, A_STUN, A_ROOT, A_FEAR, A_CONF, A_SLOW, A_SHIELD, A_STEALTH = {3, 89}, {8, 20, 24}, {12}, {26}, {7}, {5}, {33}, {69, 15}, {16}
def role(r):
    ef = [r[71 + i] for i in range(3)]; au = [r[95 + i] for i in range(3)]
    if any(e in (2, 9, 17, 31, 58, 62, 121) for e in ef): base = 'dmg'   # school damage, health leech, weapon damage variants (Heroic Strike, Backstab ...)
    elif 10 in ef or 35 in ef: base = 'heal'
    else: base = None
    for a in au:
        if a in A_STUN: return 'stun'
        if a in A_FEAR or a in A_CONF: return 'fear'
        if a in A_ROOT: return 'root'
        if a in A_DOT: return 'dot'
        if a in A_HOT: return 'hot'
    if base: return base
    for a in au:
        if a in A_SHIELD: return 'shield'
        if a in A_STEALTH: return 'stealth'
        if a in A_SLOW: return 'slow'
    if 38 in ef: return 'dispel'
    if any(e in (28, 56, 41, 42, 50, 87) for e in ef): return 'summon'
    if any(a for a in au): return 'buff/debuff'
    return 'dummy' if 3 in ef or 77 in ef else 'other'
BAD = re.compile(r'^Glyph of|\(DND\)|scaling|pet passive|\[ph\]|zzold|deprecated|test|\bdnd\b|^\?$', re.I)
rows = {}
def add(src, a):
    sp = SPI.get(a[2])
    if not sp: return
    n = sps(sp[136])
    if not n or BAD.search(n) or sp[4] & 0x40: return   # passive
    key = (src, n)
    if key not in rows or sp[0] > rows[key][0][0]: rows[key] = (sp, a)
pet_lines = {}
for r in CF:
    n = cfs(r[10]) if r[10] else ''
    for s in (r[5], r[6]):
        if s and s != 270 and n: pet_lines.setdefault(s, n)
for s, fam in pet_lines.items():
    for a in SLA:
        if a[1] == s: add('pet:' + fam, a)
for a in SLA:
    if a[1] == 270: add('pet:generic', a)
LINECLS = {}   # a class skill line belongs to the class most of its ClassMask-tagged spells name (spells with ClassMask 0 - Riptide, Lava Burst - then belong to it too)
_cnt = collections.defaultdict(collections.Counter)
for a in SLA:
    cat, nm = SLN.get(a[1], (0, ''))
    if cat == 7 and not nm.startswith('Pet') and a[4] and a[1] not in (777, 778, 769, 633, 776):
        cl = [CLS[b] for b in CLS if a[4] & b]
        if len(cl) == 1: _cnt[a[1]][cl[0]] += 1
for ln, c in _cnt.items(): LINECLS[ln] = c.most_common(1)[0][0]
for a in SLA:
    cat, nm = SLN.get(a[1], (0, ''))
    if cat == 7 and not nm.startswith('Pet') and a[1] in LINECLS and a[1] not in (777, 778, 769, 633, 776): add('class:' + LINECLS[a[1]] + '/' + nm, a)
    elif cat == 9 and 'acial' in nm: add('race:' + nm.replace('Racial', '').replace('-', '').strip(), a)   # racial abilities (Cannibalize, Stoneform, Gift of the Naaru, Arcane Torrent ...)
SI, sis = dbc('SpellIcon'); ICO = {r[0]: sis(r[1]).replace('\\', '/').rsplit('/', 1)[-1] for r in SI}   # SpellIconID -> texture name (Interface\\Icons\\X)
print('source\tspell_id\tname\trole\tschool\tcast_ms\tlevel\ticon')
CT, _ = dbc('SpellCastTimes'); CTM = {r[0]: struct.unpack('<i', struct.pack('<I', r[1]))[0] for r in CT}
for (src, n), (sp, a) in sorted(rows.items()):
    sch = SCH.get(struct.unpack('<I', struct.pack('<I', sp[225]))[0] & 127 if len(sp) > 225 else 0, 'mixed')
    print('%s\t%d\t%s\t%s\t%s\t%d\t%d\t%s' % (src, sp[0], n, role(sp), sch, CTM.get(sp[28], 0), sp[39], ICO.get(sp[133], '')))
