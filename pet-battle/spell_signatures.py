#!/usr/bin/env python3 -I
"""What a 3.3.5 spell DOES, read from Spell.dbc effects/auras/mechanics (never from its name), as a feature set that can be compared with an effect-list label.
Features: D direct damage, P periodic damage (DoT), H direct heal, HOT periodic heal, L leech/drain, S stun, SL sleep/fear/polymorph/confuse, R root, SD slow, SU speed up,
A area/cone, AD hit-chance aura (accuracy), BL block aura, MH channeled repeated hits, DU damage-done up, DD damage-done down, VU damage-taken up, DEF damage-taken down/absorb/armor, DG dodge, SH damage shield, CL dispel, IM immunity/untargetable, ST stealth, SUM summon, CR crit up, DUM dummy (cannot classify from data).
Run from repo root: python3 -I pet-battle/spell_signatures.py  -> pet-battle/spell_signatures.tsv + known-case test."""
import struct, csv, sys

d = open('release/data/dbc/Spell.dbc', 'rb').read()
_, cnt, nf, rs, ss = struct.unpack('<4sIIII', d[:20])
strs = d[20 + cnt * rs:]
ROW = {}
for i in range(cnt):
    r = struct.unpack_from('<%dI' % nf, d, 20 + i * rs)
    ROW[r[0]] = r


def name(r):
    o = r[136]
    return strs[o:strs.index(b'\0', o)].decode('latin1')


def sgn(x):
    return struct.unpack('<i', struct.pack('<I', x))[0]


AURA = {54: 'AD', 51: 'BL', 278: 'DD', 3: 'P', 53: 'L', 8: 'HOT', 12: 'S', 5: 'SL', 7: 'SL', 26: 'R', 33: 'SD', 31: 'SU', 15: 'SH', 69: 'DEF', 49: 'DG', 39: 'IM', 18: 'ST', 16: 'ST', 52: 'CR', 216: 'SU', 192: 'SU', 193: 'SU'}
MECH = {12: 'S', 10: 'SL', 17: 'SL', 5: 'SL', 7: 'R', 11: 'SD', 2: 'SL'}
EFF = {2: 'D', 17: 'D', 31: 'D', 58: 'D', 121: 'D', 10: 'H', 67: 'H', 38: 'CL', 28: 'SUM', 41: 'SUM', 42: 'SUM', 98: 'SUM', 3: 'DUM'}


def features(sid):
    r = ROW.get(sid)
    if not r:
        return None
    f = set()
    mech = r[3]
    if mech in MECH: f.add(MECH[mech])
    for i in range(3):
        e = r[71 + i]
        if e in EFF: f.add(EFF[e])
        if e in (6, 35, 65, 27):                     # apply aura (self / party / raid / pet)
            a = r[95 + i]
            pts = sgn(r[83 + i])
            if a in AURA: f.add(AURA[a])
            elif a in (79, 13): f.add('DU' if pts >= 0 else 'DD')
            elif a in (87, 14): f.add('VU' if pts >= 0 else 'DEF')
            elif a in (101, 22): f.add('DEF' if pts >= 0 else 'VU')
            elif a in (4,): f.add('DUM')
            if r[86 + i] in MECH: f.add(MECH[r[86 + i]])
    if any(r[71 + i] == 27 for i in range(3)) or any(r[89 + i] in (15, 16, 28) for i in range(3)):
        f.add('A')                                    # area: persistent area aura, or enemy area / cone target
    if (r[5] & 0x44) and any(r[95 + i] in (3, 23) for i in range(3) if r[71 + i] == 6):
        f.add('MH')                                   # channeled spell that fires repeatedly (Arcane Missiles, Mind Flay)
    if not (f - {'DUM'}):
        tf = text_features(sid)
        if tf:
            f = (f | tf)
            TXT[sid] = True
    return f


import re
TEXT = [  # (feature, regex on the lower-cased tooltip) - the game's own wording
    ('VU', r'(takes?|suffer\w*) .{0,20}(more|additional|increased) .{0,15}damage|damage (taken|they take|suffered) .{0,15}increased|increas\w+ .{0,25}damage (taken|they take|suffered)'),
    ('DEF', r'reduc\w+ .{0,25}damage (taken|you take|suffered)|takes? .{0,15}less damage|absorb|damage taken .{0,15}reduced'),
    ('DD', r'reduc\w+ .{0,30}(damage (done|dealt|caused)|attack power)|damage (done|dealt) .{0,15}reduced'),
    ('DU', r'increas\w+ .{0,40}(damage|attack power|spell power|strength|physical)|(additional|extra) .{0,20}damage|damage (done|dealt|caused) .{0,15}increased'),
    ('CR', r'critical strike'),
    ('SU', r'(movement|run) speed .{0,20}increas|increas\w+ .{0,20}(movement|run|attack|casting) speed|haste|speed .{0,15}increased'),
    ('SD', r'reduc\w+ .{0,25}(movement )?speed|slow'),
    ('H', r'\bheal(s|ing)?\b|restores? .{0,20}health'),
    ('P', r'(every|each) .{0,12}sec.{0,40}damage|damage .{0,30}over|damage .{0,25}every .{0,12}sec'),
    ('CL', r'dispel|removes? .{0,25}(poison|disease|curse|magic|effects)'),
    ('S', r'\bstun'), ('SL', r'sleep|polymorph|\bfear|incapacitat|confus|disorient'), ('R', r'\broot|immobil'),
    ('DG', r'dodge'), ('SH', r'damage .{0,25}(attacker|strikes you|hits you)|each time .{0,20}(struck|hit)'),
    ('IM', r'immune|invulnerab'), ('ST', r'stealth|invisib'),
]
TXT = {}


def tooltip(sid):
    r = ROW[sid]
    out = []
    for col in (170, 187):
        o = r[col]
        if o:
            t = strs[o:strs.index(b'\0', o)].decode('latin1')
            if t: out.append(t)
    return re.sub(r'\$\w+', 'X', ' '.join(out).lower())


def text_features(sid):
    t = tooltip(sid)
    t = re.sub(r'frees [^.]*|immune to [^.]*|can always be seen[^.]*|stealths? or [^.]*|only (useable|usable) [^.]*', ' ', t)
    return {f for f, rx in TEXT if re.search(rx, t)}


def cooldown_ms(sid):
    r = ROW[sid]
    return max(r[29], r[30])


# effect-list label tokens -> required feature(s)
TOKEN = {'damage': 'D', 'dot': 'P', 'heal': 'H', 'hot': 'HOT', 'drain': 'L', 'stun': 'S', 'stunchance': 'S', 'noswap': 'R', 'speeddown': 'SD', 'speedup': 'SU', 'dmgup': 'DU',
         'dmgdown': 'DD', 'vuln': 'VU', 'defense': 'DEF', 'dodge': 'DG', 'damageshield': 'SH', 'cleanse-self': 'CL', 'cleanse-team': 'CL', 'cleanse-enemy': 'CL', 'critup': 'CR',
         'untargetable': 'IM', 'block': 'DEF', 'multihit': 'D', 'aoe': 'D'}


def need(label):
    root = label.split('-cd')[0]
    toks = [t for t in root.split('-') if t in TOKEN]
    n = {TOKEN[t] for t in toks}
    return n


def fit(spell_f, eff_need):
    """EXACT: same feature set. SUPERSET: spell does everything the effect needs and more (harmless extras). PARTIAL: spell lacks a part. NONE otherwise."""
    if not eff_need: return 'NONE'
    core = spell_f - {'DUM'}
    if core == eff_need: return 'EXACT'
    if eff_need <= core: return 'SUPERSET'
    if eff_need & core: return 'PARTIAL'
    return 'NONE'


KNOWN = {  # spell id: (name, features that MUST be present, features that MUST NOT be present)
    42833: ('Fireball', {'D'}, {'H', 'S'}),
    47813: ('Corruption', {'P'}, {'H'}),
    42917: ('Frost Nova', {'D', 'R'}, {'H'}),
    48071: ('Flash Heal', {'H'}, {'D'}),
    42842: ('Frostbolt', {'D', 'SD'}, {'H'}),
    48441: ('Rejuvenation', {'HOT'}, {'D'}),
    53307: ('Thorns', {'SH'}, {'D'}),
    61780: ('Polymorph', {'SL'}, {'D'}),
    53408: ('Judgement of Wisdom (sanity: dummy ok)', set(), set()),
}

if __name__ == '__main__':
    bad = 0
    for sid, (n, must, mustnot) in KNOWN.items():
        f = features(sid)
        ok = f is not None and must <= f and not (mustnot & f)
        bad += 0 if ok else 1
        print('%-6s %-40s %s  %s' % ('OK' if ok else 'FAIL', n, sorted(f) if f is not None else 'missing', name(ROW[sid]) if sid in ROW else ''))
    rows = list(csv.reader(open('pet-battle/spell_pairing.tsv'), delimiter='\t'))[1:]
    with open('pet-battle/spell_signatures.tsv', 'w') as fh:
        fh.write('source\tspell_id\tname\tfeatures\tcooldown_ms\n')
        for r in rows:
            f = features(int(r[1]))
            fh.write('%s\t%s\t%s\t%s\t%s\n' % (r[0], r[1], r[2], ','.join(sorted(f)) if f is not None else 'NOTFOUND', cooldown_ms(int(r[1])) if f is not None else ''))
    print('known-case failures:', bad)
