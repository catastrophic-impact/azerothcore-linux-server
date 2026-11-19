#!/usr/bin/env python3 -I
"""Builds pet-battle/lab/pb_abilab_data.lua: the queue for the ability lab (.pblab). One entry per Elwynn ability with 1+ candidate spells to look at.
DECISIONS below = what the user and the developer agreed per ability (2026-11-16); abilities not listed use the same-name 3.3.5 spell when one exists.
Spell NAMES are resolved against Spell.dbc (a name may be a number = spell id). Prints the resolution so a wrong pick is visible.
usage: python3 -I pet-battle/lab_build.py"""
import csv, re, struct, sys, collections
csv.field_size_limit(10 ** 9)
RD = 'pet-battle/retail_data/'
def dbc(name):
    d = open('release/data/dbc/%s.dbc' % name, 'rb').read(); _, c, f, rs, ss = struct.unpack('<4sIIII', d[:20])
    recs = [struct.unpack_from('<%dI' % f, d, 20 + i * rs) for i in range(c)]; sb = 20 + c * rs
    return recs, (lambda off: d[sb + off:d.index(b'\0', sb + off)].decode('latin1'))
SP, sps = dbc('Spell'); DUR, _ = dbc('SpellDuration'); DURMS = {r[0]: struct.unpack('<i', struct.pack('<I', r[1]))[0] for r in DUR}
SL, _ = dbc('SkillLineAbility'); SK = {r[2] for r in SL}
JUNK = ('dnd', 'dummy', 'test', 'zzold', 'deprecated', '[ph]', 'unused')
byname = collections.defaultdict(list); byid = {}; DMG = set()   # DMG: spells whose own effects deal damage (school damage / weapon damage): only these may be retried after a miss
DMG_EFFECTS = (2, 17, 19, 31, 58)
for r in SP:
    n = sps(r[136]); byid[r[0]] = n
    if any(r[71 + e] in DMG_EFFECTS for e in range(3)): DMG.add(r[0])
    if n and r[131] and not any(j in n.lower() for j in JUNK):
        aura = any(r[95 + e] for e in range(3)) or DURMS.get(r[40], 0) != 0
        byname[n.lower()].append((r[0], r[0] in SK, not aura))
def resolve(x):
    if isinstance(x, int): return x, byid.get(x, '?')
    full = x; x = x.split('#')[0]   # 'Prayer of Healing#2' = the same spell again after a fix: it gets its own label, so the lab shows it once more
    L = byname.get(x.lower())
    if not L: return None, full
    L = sorted(L, key=lambda t: (not t[1], not t[2], t[0]))   # a real player spell first, then instant, then the lowest id
    return L[0][0], full

HOP = {669}      # the pet JUMPS back to its place after the hit (Backflip) instead of running
RETEST = {440}   # abilities that already have a 'y' but got NEW candidates the user asked to see (the lab shows the untried ones again)
# ---- decisions: abilityId -> (mode, [candidates], hits)   mode: melee | ranged | self | target | lift | emote | defer
# a candidate is a spell name / id, or (spell, modeOverride), or ('emote', id), ('lift', 0)
D = {
 112: ('melee', ['Bite', 'Kick'], 1),            # Peck: user: Bite (beaks have no claws), also try Kick's landing
 114: ('ranged', ['Drain Soul', 'Arcane Shot'], 1),
 118: ('ranged', ['Water Spout'], 1),   # LAB 1 RESULT: Water Spout = y. Chain Heal looks green (every rank), hostile-cast did nothing
 119: ('melee', [3009], 1),                      # Scratch: hunter-pet Claw (user: perfect)
 1400: ('ranged', ['Water Spout'], 1),   # Udder Destruction: LAB 1 RESULT: Water Spout = y (Chain Heal is green)
 1401: ('self', ['Evasion', 'Feint', 'Blade Flurry'], 1),   # Where's the Beef?: dodge buff (lab)
 155: ('ranged', ['Taunt', 'Wing Clip'], 1),     # Hiss: the taunt effect (user)
 165: ('self', ['Shield Wall', 'Defensive Stance'], 1),   # Crouch: -50% damage (lab)
 170: ('lift', [('Vanish', 'self'), ('Evasion', 'self'), ('lift', 0)], 1),     # Lift-Off: rise in the air; else transparent (user)
 1758: ('self', ['Barkskin', 'Stoneform', 'Inner Fire'], 1),   # Ironskin (lab)
 186: ('melee', ['Heroic Strike', 'Recklessness'], 1),    # Reckless Strike (lab)
 193: ('melee', ['Backstab', 'Sinister Strike'], 2),      # Flank (lab)
 221: ('melee', ['Bash', 'Charge'], 1),                   # Takedown (lab)
 227: ('melee', ['Kick', 'Cheap Shot', 'Hammer of Justice'], 1),   # Blackout Kick: the landing of Kick (user curious)
 230: ('self', ['Riptide', 'Chain Heal', 'Tranquility'], 1),       # Cleansing Rain (Healing Rain does not exist in 3.3.5)
 232: ('ranged', ['Insect Swarm'], 1),                    # Swarm of Flies (user: perfect)
 233: ('ranged', ['Hex', 'Polymorph'], 1),                # Frog Kiss: the shaman frog (user)
 250: ('defer', [], 1),                                   # Spiderling Swarm: little summoned spider runs in, bites, vanishes (choreography)
 253: ('melee', ['Heroic Strike', 'Sinister Strike'], 1), # Comeback (lab)
 273: ('self', ['Riptide', 'Heal', 'Renew'], 1),          # Wish
 283: ('self', ['Shield Wall', 'Divine Shield'], 1),      # Survival (lab; the mechanic itself is in the engine)
 350: ('melee', ['Bash', 'Cheap Shot', 'Hammer of Justice'], 1),   # Clobber: stun effects
 355: ('melee', ['Kick'], 3),                            # Triple Snap: LAB 3: Kick best, but the hits need a slight delay between them (retest with 3 hits)
 366: ('self', ['Bloodlust', 'Divine Hymn'], 1),          # Dazzling Dance (lab)
 371: ('ranged', ['Web', 'Rancid Ooze Effect'], 1),       # Sticky Goo: spiders shoot web
 375: ('melee', ['Sonic Screech'], 1),                    # Trumpet Strike: LAB 3: Sonic Screech = y (Horn of Winter showed nothing on the enemy)
 376: ('melee', ['Kick'], 1),                            # Headbutt: LAB 3: user wants the Kick landing (Bash n, Charge: nothing happened)
 382: ('ranged', ['Web', 'Entangling Roots'], 1),         # Brittle Webbing (user: good)
 383: ('ranged', ['Drain Life'], 1),                      # Leech Life (user: good; the channel must be cut after ~1 s)
 398: ('melee', [39967, 'Poison Shock', 'Poison Spit'], 1),   # Poison Lash: LAB 3: the player Envenom/Deadly Poison are weapon buffs (nothing on the enemy); 39967 = the creature Envenom the matcher found (envenom cast + impact models)
 420: ('melee', ['Whirlwind', 'Wind Shear'], 2),          # Slicing Wind
 440: ('self', ['Fade', 'Cloak of Shadows'], 1),         # Evanescence: LAB 4: Vanish n (user: what about the priest Fade), Cloak of Shadows y
 453: ('ranged', ['Dust Field', 'Sand Storm', 'Dust Cloud'], 1),   # Sandstorm: LAB 4: Sand Breath = green skulls/poison (user: awesome, keep for a poison cloud later) but not sand
 489: ('ranged', ['Arcane Blast', 'Arcane Missiles'], 1), # Mana Surge
 493: ('melee', ['War Stomp'], 1),                        # Hoof
 521: ('self', [('Aspect of the Hawk#3', 'aura')], 1),   # Hawk Eye: LAB 4+5: Aspect of the Hawk, Dragonhawk, Trueshot Aura ALL show a green animation on the caster (n); the user wants the aspect animation above the pet. LAB 6: Hunter's Mark / Rapid Fire n. Now: the AURA applied directly (no cast glow): mode 'aura'
 524: ('ranged', [('Sonic Screech', 'ranged', 'Screech'), 'Demoralizing Roar'], 1),   # Squawk: LAB 4: Screech on the caster is perfect but nothing lands on the enemy -> Screech first, then Sonic Screech on the enemy
 539: ('self', ['Prayer of Healing#2'], 1),                 # Bleat: a pulse for a second or two (user); totems would place a real totem
 541: ('melee', ['Ferocious Bite', 'Bite'], 1),          # Chew: LAB 4: Bite n (user: Ferocious Bite from the druid?)
 571: ('melee', ['Sinister Strike', 'Heroic Strike', 'Mortal Strike'], 1),   # Horn Attack: LAB 4: antlers = a stab/strike landing; Gore n, Bash/Charge: nothing on the enemy
 574: ('self', ['Rejuvenation'], 1),                      # Nature's Ward
 579: ('melee', ['Bite'], 1),                             # Gobble Strike
 580: ('target', ['Hibernate', 'Sleep'], 1),              # Food Coma
 581: ('defer', [], 1),                                   # Flock: little summoned birds (choreography)
 598: ('self', [('Hibernate#3', 'aura'), ('Sleep#3', 'aura')], 1),         # Emerald Dream: LAB 5: self-cast Hibernate plays nothing (it needs a hostile beast target); the user wants zzz above the pet -> LAB 6: another pet casting it was wrong (user: use common sense) -> the aura is applied to the pet itself (mode 'aura'). FALLBACK the user accepted: Rejuvenation 774 (answered n but 'a good fallback if zzz doesnt work')
 668: ('ranged', ['Acid Breath', 'Poison Spit'], 1),      # Dreadful Breath
 669: ('melee', ['Kick#2'], 1),                          # Backflip: LAB 5: Kick n only because the pet ran back and faced the wrong way: now it JUMPS back and faces the enemy again (user: a hop)
 713: ('melee', ['Sinister Strike', 'Kick'], 2),          # Blitz
 743: ('ranged', ['Plague Strike', 'Poison Spit'], 1),    # Creeping Fungus
 745: ('ranged', ['Drain Life', 'Seed of Corruption'], 1),# Leech Seed
 746: ('ranged', ['Acid Breath', 'Poison Shock'], 1),     # Spore Shrooms: a mushroom model by the enemy comes later
 751: ('self', ['Shadow Ward'], 1),                       # Soul Ward
 756: ('melee', [39967, 'Acid Spit'], 1),                 # Acid Touch: LAB 4: ranged Envenom 'the pet never attacked' (melee Envenom worked for Poison Lash), Poison Shock n ('attacked himself')
 757: ('self', ['Divine Hymn', 'Bloodlust'], 1),          # Lucky Dance
 763: ('self', ['Dispel Magic'], 1),                      # Sear Magic
 461: ('ranged', ['Smite'], 1),                           # Light
 202: ('melee', ['Swipe', 21919, 47480], 1),              # Thrash: Swipe (user), the creature Thrash spells as fallbacks
 492: ('melee', ['Rake', 'Claw'], 1),                     # Rake: the druid bleed (the aura is stripped), Claw as the instant fallback
 110: ('melee', ['Bite#2', 'Ferocious Bite#2'], 1),
 314: ('melee', ['Shred', 'Claw'], 1),                   # Mangle: LAB 9: the cat Mangle 33917 showed nothing on the enemy (n)
 357: ('ranged', ['Sonic Screech#2', 'Psychic Scream'], 1),   # Screech (frighten + damage, ranged): LAB 10: the caster Screech 31273 plays nothing on the enemy
 360: ('melee', [('Claw', 'melee')], 2),                  # Flurry = 1-2 quick hits (retail text): LAB 10: 12966 is a self buff, not an attack ('test super flawed')
 362: ('target', ['Psychic Scream', 'Intimidating Shout'], 1),   # Howl = a frightening howl on the TARGET (+100% damage taken): LAB 10: no effect from 37502
 364: ('melee', [('Claw', 'melee', 'Dash'), 'Pounce'], 1),   # Leap = damage + a speed buff (retail text): LAB 10: 47482 plays nothing
 162: ('melee', [('Kick', 'melee', 'Berserking')], 1),   # Adrenaline Rush = damage + speed buff (retail text): LAB 9: the buff alone was good ('Berserking even better') but the pet never attacked -> Berserking, then a Kick attack
 228: ('ranged', ['Lash of Pain', 'Poison Spit'], 1),     # Tongue Lash: DECIDED by the user in LAB 9: 'have the mob just run up to the other and do Kick' (the creature Tongue Lash 36398 landed - hp 1000->340 - but has no hit visual; Lash of Pain did not land). See lab_accept OVERRIDE
 163: ('defer', [], 1),                                   # Stampede: user: 'we talked about what Stampede should be' -> the choreography work (little summoned copies run in)
 706: ('defer', [], 1),                                   # Swarm: the same Stampede-type choreography   # Bite: LAB 7: 'nothing played on enemy' but the server log says the Bite LANDED (hp 1000->970): inconclusive, shown once more (17253 worked for Peck and Gobble Strike)                              # Bite: hunter-pet Bite
}

abil = {}
for l in open('pet-battle/.elw_abilities.tsv'):
    c = l.rstrip('\n').split('\t'); abil[int(c[0])] = c
names = {c: a[1] for c, a in abil.items()}
species = {int(a): int(s) for a, s in (l.split() for l in open('pet-battle/.elw_species.tsv'))}
txt = {}
rng = {}
for r in csv.DictReader(open(RD + 'BattlePetAbility.csv')):
    d = re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', r['Description_lang']).replace('\n', ' ')
    d = re.sub(r'\[StandardAccuracy[^\]]*\]\s*Hit Chance\s*', '', d)
    d = re.sub(r'\|4(\w+):(\w+);', r'\2', d)
    d = re.sub(r'\[[^\]]*\]', 'X', d).strip()
    txt[int(r['ID'])] = d
ranged_by_vis = {}
for v in csv.DictReader(open(RD + 'BattlePetVisual.csv')): ranged_by_vis[v['ID']] = v['RangeTypeEnum']
turns = collections.defaultdict(list)
for t in csv.DictReader(open(RD + 'BattlePetAbilityTurn.csv')): turns[int(t['BattlePetAbilityID'])].append(t['BattlePetVisualID'])
def retail_range(a):
    for v in turns.get(a, []):
        if v in ranged_by_vis: return ranged_by_vis[v]
    return '0'

# RETRY OF UNRELIABLE REJECTIONS: before pb_cast repeated missed spells (2026-11-16) a damaging spell could MISS and show nothing. An 'n' for a DAMAGING spell whose comment only says it showed nothing
# (or has no comment) is not trusted: the candidate comes back once, with the label suffix '#r2' (its own result key).
import os
WEAK = re.compile(r"nothing|no effect|never|flawed|not play|didn.t see|did not|no animation", re.I)
rejected_weak = set()
if os.path.exists('release/logs/pb_abilab.tsv'):
    for l in open('release/logs/pb_abilab.tsv'):
        c = l.rstrip('\n').split('\t')
        if len(c) >= 5 and c[4] == 'n' and (len(c) < 6 or c[5] == '' or WEAK.search(c[5])): rejected_weak.add((c[1], c[3]))
# default for abilities with no decision: the same-name spell (instant preferred), mode from the retail range (0 melee, 1 ranged, 2 none = self)
out, report, missing = [], [], []
order = [a for a in D if a in abil] + [a for a in sorted(abil) if a not in D]   # the abilities discussed with the user come first, in that order
for aid in order:
    nm = names[aid]
    mode, cands, hits = D.get(aid, (None, None, 1))
    if mode is None:
        sid, _ = resolve(nm)
        rg = retail_range(aid)
        mode = {'0': 'melee', '1': 'ranged', '2': 'self'}.get(rg, 'melee')
        cands = [sid] if sid else []
        if not sid: missing.append((aid, nm))
    res = []
    for c in cands:
        m2 = pre = None
        if isinstance(c, tuple): c, m2, *rest = c; pre = rest[0] if rest else None
        if c == 'lift': res.append({'kind': 'lift', 'label': 'lift the pet up, hold, drop'}); continue
        sid, label = resolve(c)
        if sid is None: missing.append((aid, '%s -> candidate %r not found' % (nm, c))); continue
        if sid in DMG and (str(aid), '%s=%s' % (label, sid)) in rejected_weak and '#r2' not in str(label): label = str(label) + '#r2'   # shown once more (see RETRY above)
        res.append({'kind': 'spell', 'spell': sid, 'label': label if isinstance(label, str) else str(label), 'mode': m2 or mode, 'pre': resolve(pre)[0] if pre else None, 'dmg': True if sid in DMG else None})
    if mode != 'defer' and not res: mode = 'defer'
    out.append({'retest': True if aid in RETEST else None, 'hop': True if aid in HOP else None, 'id': aid, 'name': nm, 'text': txt.get(aid, ''), 'species': species.get(aid), 'mode': mode, 'hits': hits, 'cands': res})
    report.append('%5d %-22s %-7s %s' % (aid, nm, mode, ', '.join('%s=%s' % (r.get('label'), r.get('spell', r['kind'])) for r in res)))
print('\n'.join(report)); print('\nNOT RESOLVED / NO SPELL (deferred):', missing, file=sys.stderr)
def lua(v):
    if isinstance(v, dict): return '{' + ', '.join('%s = %s' % (k, lua(x)) for k, x in v.items() if x is not None) + '}'
    if isinstance(v, list): return '{' + ', '.join(lua(x) for x in v) + '}'
    if v is True: return 'true'
    if v is False: return 'false'
    if isinstance(v, str): return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return str(v)
open('pet-battle/lab/pb_abilab_data.lua', 'w').write('-- GENERATED by pet-battle/lab_build.py (do not edit)\nreturn {\n' + ',\n'.join(lua(e) for e in out) + '\n}\n')
print('\n%d abilities, %d deferred' % (len(out), sum(1 for e in out if e['mode'] == 'defer')))
