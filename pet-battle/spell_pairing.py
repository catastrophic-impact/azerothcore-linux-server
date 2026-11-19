#!/usr/bin/env python3 -I
"""Pair each 3.3.5 spell (pet-battle/spell_catalog.tsv) with the pet-battle mechanic ROLES it can plausibly carry. The spell lends NAME + VISUAL (+ a mode: melee / ranged / self / target);
the numbers always come from the retail baseline template of that role. Ability family (damage type) is chosen by the pet's kit, not by the spell.
Usage (repo root): python3 -I pet-battle/spell_pairing.py > pet-battle/spell_pairing.tsv
tier: basic = the signature plain hit of a pet family or an instant class strike; caster = a cast-time class damage spell (ranged basic for casters); else utility."""
import struct
rows = [l.rstrip('\n').split('\t') for l in open('pet-battle/spell_catalog.tsv')][1:]
d = open('release/data/dbc/Spell.dbc', 'rb').read(); _, c, f, rs, ss = struct.unpack('<4sIIII', d[:20])
RNG = {}
for i in range(c):
    r = struct.unpack_from('<%dI' % f, d, 20 + i * rs); RNG[r[0]] = (r[46], struct.unpack('<f', struct.pack('<I', r[47]))[0], r[4] & 0x40)
ELIG = {'dmg': ['dmg', 'dmg-multiturn', 'dmg+buff/debuff'], 'dot': ['dmg+dot', 'dmg-multiturn+dot'], 'heal': ['heal', 'dmg+heal'], 'hot': ['heal+hot', 'heal'], 'stun': ['stun', 'dmg+stun'],
        'fear': ['stun', 'dmg+stun'], 'root': ['dmg+swaplock', 'stun', 'defense'], 'slow': ['dmg+buff/debuff', 'buff/debuff'], 'shield': ['defense'], 'stealth': ['defense', 'special'],
        'dispel': ['cleanse'], 'buff/debuff': ['buff/debuff', 'defense', 'dmg+buff/debuff'], 'summon': ['special'], 'dummy': ['special'], 'other': ['special']}
print('source\tspell_id\tname\tspell_role\tschool\tmode\ttier\teligible_template_roles\tcast_ms\ticon')
for src, sid, name, role, school, cast, lvl, icon in rows:
    rng, speed, _ = RNG[int(sid)]
    if role in ('heal', 'hot', 'shield', 'stealth') or rng == 1: mode = 'self'
    elif role in ('dot', 'stun', 'fear', 'root', 'slow', 'buff/debuff') and rng > 2: mode = 'target'
    elif speed > 0 or rng > 2 or int(cast) > 0: mode = 'ranged'
    else: mode = 'melee'
    tier = 'utility'
    if role == 'dmg':
        if src.startswith('pet:') and int(cast) == 0: tier = 'basic'
        elif int(cast) == 0 and mode == 'melee': tier = 'basic'
        elif int(cast) > 0: tier = 'caster'
    print('\t'.join([src, sid, name, role, school, mode, tier, ','.join(ELIG.get(role, ['special'])), cast, icon]))
