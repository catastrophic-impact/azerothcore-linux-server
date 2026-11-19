#!/usr/bin/env python3 -I
"""PROTOTYPE kit assembler for wild mobs (Outland/Northrend scale-up). Composes 6 abilities per creature from the retail BASELINE templates following retail's slot rules, biased by creature theme,
and flavors each ability with a 3.3.5 spell name (hunter-pet signature for beasts, class spells for casters/warriors). Prints diversity metrics; writes the kits as TSV.
Retail slot rules (measured over the 1904 retail kits whose abilities are all in our pool): slot1 L1 = plain hit (84%, no cooldown); slot1 L10 = hit variant; slot2 (L2,L15) = mixed utility (~40% no cooldown);
slot3 (L4,L20) = high impact (multi-turn / crowd control / heal; mostly on cooldown). 75% of retail kits use 4-5 distinct role groups.
Usage (repo root): python3 -I pet-battle/assemble_kits.py <ability_roles.tsv> > pet-battle/kits_prototype.tsv   (metrics go to stderr)"""
import sys, re, random, collections, zlib, os
AR = {}
for l in list(open(sys.argv[1]))[1:]:
    a = l.rstrip('\n').split('\t'); AR[a[0]] = dict(name=a[1], fam=a[2], shipped=int(a[3]), role=a[4], cd=a[5])
def grp(role):
    p = set(role.split('+'))
    if 'stun' in p or 'swaplock' in p or 'blind' in p: return 'CC'
    if 'dot' in p: return 'DoT'
    if 'heal' in p or 'hot' in p: return 'Heal'
    if p <= {'defense'} or ('defense' in p and not (p & {'dmg', 'dmg-multiturn'})): return 'Defense'
    if p <= {'buff/debuff'}: return 'Buff'
    if 'aoe-dmg' in p: return 'AoE'
    if 'dmg-multiturn' in p: return 'Multi'
    if p == {'dmg'}: return 'Hit'
    if 'dmg' in p: return 'Hit+fx'
    return 'Special'
B = {}
for l in list(open('pet-battle/mechanic_baseline.tsv'))[1:]:
    x = l.rstrip('\n').split('\t'); ids = x[13].split(',')
    B[x[0]] = dict(role=x[1], g=grp(x[1]), n=int(x[2]), cd=x[5], turns=x[6], ids=ids)
def sg(g, b):   # spell group for a template: a template that deals damage must get a damage-spell name even when its slot group is Heal/Defense/Buff (drain, lifesteal, hit+shield ...)
    deals = any(x.startswith('dmg') or x in ('dot', 'aoe-dmg') for x in B[b]['role'].split('+'))   # direct damage, multi-turn damage, DoT, AoE
    return 'Hit+fx' if g in ('Heal', 'Defense', 'Buff', 'Special', 'CC') and deals else g
import csv
_rv = {v['ID']: v['RangeTypeEnum'] for v in csv.DictReader(open('pet-battle/retail_data/BattlePetVisual.csv'))}; _tr = collections.defaultdict(list)
for _t in csv.DictReader(open('pet-battle/retail_data/BattlePetAbilityTurn.csv')):
    _r = _rv.get(_t['BattlePetVisualID'])
    if _r is not None: _tr[_t['BattlePetAbilityID']].append(int(_r))
def want_mode(b):   # retail presentation range of a template (majority of its member abilities): 'melee' = the pet runs up and hits (retail range 0), else 'ranged'
    v = [_tr[i][0] for i in B[b]['ids'] if _tr.get(i)]
    return None if not v else ('melee' if sum(1 for x in v if x == 0) * 2 >= len(v) else 'ranged')
SP = [l.rstrip('\n').split('\t') for l in list(open('pet-battle/spell_pairing.tsv'))[1:]]
SPELLS = [dict(src=x[0], id=x[1], name=x[2], role=x[3], school=x[4], mode=x[5], tier=x[6], icon=x[9]) for x in SP]
FAMS = {1: 'Wolf', 2: 'Cat', 3: 'Spider', 4: 'Bear', 5: 'Boar', 6: 'Crocolisk', 7: 'Carrion Bird', 8: 'Crab', 9: 'Gorilla', 11: 'Raptor', 12: 'Tallstrider', 15: 'Felhunter', 16: 'Voidwalker', 17: 'Succubus', 20: 'Scorpid', 21: 'Turtle', 23: 'Imp', 24: 'Bat', 25: 'Hyena', 26: 'Bird of Prey', 27: 'Wind Serpent', 29: 'Felguard', 30: 'Dragonhawk', 31: 'Ravager', 32: 'Warp Stalker', 33: 'Sporebat', 34: 'Nether Ray', 35: 'Serpent', 37: 'Moth', 38: 'Chimaera', 39: 'Devilsaur', 40: 'Ghoul', 41: 'Silithid', 42: 'Worm', 43: 'Rhino', 44: 'Wasp', 45: 'Core Hound', 46: 'Spirit Beast'}
# slot role distributions measured from retail (percent); order of groups
G = ['Hit', 'Hit+fx', 'Multi', 'AoE', 'DoT', 'Heal', 'CC', 'Defense', 'Buff', 'Special']
S1A = dict(Hit=94, DoT=6)
S1B = {'Hit': 64, 'Hit+fx': 5, 'Multi': 7, 'DoT': 12, 'Heal': 4, 'CC': 3}
S2 = {'Hit': 12, 'Hit+fx': 19, 'Multi': 4, 'DoT': 13, 'Heal': 12, 'CC': 14, 'Defense': 7, 'Buff': 8, 'Special': 4}
S3 = {'Hit': 20, 'Hit+fx': 8, 'Multi': 19, 'DoT': 6, 'Heal': 11, 'CC': 17, 'Defense': 4, 'Buff': 5, 'Special': 4}
# THEMES: regex on name (or creature type) -> school, role-weight bias
TH = [
 ('frost',   r'frost|\bice\b|icy|frozen|vrykul|vargul|kvaldir|winter|snow|glacier|yeti|rime|coldarra|iron giant', 'frost',   dict(CC=1.8, DoT=1.3)),
 ('fire',    r'flame|fire|magma|forgelord|molten|burning|ember|ashmaw|cinder|lava|infernal|deathforge',            'fire',    dict(DoT=1.8, **{'Hit+fx': 1.3})),
 ('nature',  r'spider|nerub|anub|scorpid|scorpion|sting|venom|serpent|viper|basilisk|snake|spore|lasher|thorn|vine|fungal|treant|bog|widow|crypt fiend|wasp', 'nature', dict(DoT=1.8, CC=1.3)),
 ('shadow',  r'ghoul|geist|risen|skeleton|skeletal|val.kyr|revenant|necro|cult|plague|forsaken|abomination|corpse|reanimated|scourge|death|felsworn|fel |warlock|summoner|voidwalker|imp\b|shadow|void', 'shadow', dict(DoT=1.5, Heal=1.4)),
 ('arcane',  r'mana|arcane|ethereum|nether|spellweaver|mage\b|wyrm|sunfury|scryer|ethereal|surger|magister|sorcer|arcanist', 'arcane', dict(Buff=1.5, **{'Hit+fx': 1.3})),
 ('holy',    r'argent|crusader|aldor|naaru|draenei|priest|oracle|paladin|valiant|sentinel|light|blessed|silver', 'holy', dict(Heal=2.0, Defense=1.5)),
 ('storm',   r'storm|tempest|thunder|lightning|cyclone|wind|electromental|shaman', 'nature', dict(**{'Hit+fx': 1.4}, CC=1.3)),
 ('earth',   r'rager|rumbler|boulder|golem|stone|rock|earth|gronn|ironspine|crumbler|sundered', 'physical', dict(Defense=1.6, CC=1.4)),
 ('machine', r'machine|bomber|tank|mech|shredder|steam|rocket|robot|drill|gan.arg|sentry|cannon|engineer', 'physical', dict(Defense=1.4, Multi=1.4)),
]
CLASSES = [  # name regex -> class spell sources
 (r'witch doctor|voodoo|shadow hunter|hexer|troll priest|loa\b|zul', ['class:Shaman', 'class:Priest']),
 (r'siren|banshee|succubus|harpy matron|dreadbringer', ['class:Warlock']),
 (r'mage\b|warmage|arcanist|sorcer|spellweaver|magister|arcane|mana|wyrm|sunfury|scryer|ethereum|nether', ['class:Mage']),
 (r'warlock|summoner|fel|demon|imp\b|void|cabal|shadowmoon|illidari|legion', ['class:Warlock']),
 (r'priest|oracle|argent|aldor|naaru|draenei|holy|light|paladin|crusader|valiant|sentinel', ['class:Priest', 'class:Paladin']),
 (r'shaman|storm|thunder|wind|elemental|seer|tempest', ['class:Shaman']),
 (r'hunter|scout|ranger|marksman|archer|trapper|beastmaster|handler|stalker', ['class:Hunter']),
 (r'rogue|assassin|thief|cutthroat|prowler|blade|stab', ['class:Rogue']),
 (r'druid|treant|lasher|thorn|vine|spore|fungal|moon|ancient|bear|cat\b|stag|nature', ['class:Druid']),
 (r'necro|cult|scourge|ghoul|geist|risen|skelet|val.kyr|revenant|plague|forsaken|death|abomination|corpse|vargul|reanimated', ['class:DeathKnight', 'class:Warlock']),
 (r'frost|ice|icy|frozen|winter|vrykul|kvaldir', ['class:Mage', 'class:DeathKnight']),
 (r'flame|fire|magma|forge|molten|burning|ember|lava', ['class:Mage', 'class:Warlock']),
]
SPELL_ROLE = {'Hit': ('dmg',), 'Hit+fx': ('dmg', 'dot'), 'Multi': ('dmg',), 'AoE': ('dmg',), 'DoT': ('dot',), 'Heal': ('heal', 'hot'), 'CC': ('stun', 'root', 'fear', 'slow'), 'Defense': ('shield', 'stealth', 'buff/debuff'), 'Buff': ('buff/debuff',), 'Special': ('other', 'dummy', 'summon', 'dispel')}
BASICS = {'class:Warrior': 'Heroic Strike|Mortal Strike|Overpower|Cleave|Devastate|Mocking Blow', 'class:Rogue': 'Sinister Strike|Backstab|Hemorrhage|Ambush|Eviscerate',
          'class:Paladin': 'Crusader Strike|Hammer of the Righteous|Judgement of Righteousness|Exorcism', 'class:Hunter': 'Raptor Strike|Arcane Shot|Steady Shot|Aimed Shot|Mongoose Bite',
          'class:Druid': 'Claw|Mangle (Cat)|Shred|Maul|Wrath', 'class:Shaman': 'Lightning Bolt|Earth Shock|Stormstrike|Lava Lash', 'class:Priest': 'Smite|Mind Blast', 'class:Mage': 'Frostbolt|Fire Blast|Arcane Blast|Scorch|Ice Lance',
          'class:Warlock': 'Shadow Bolt|Searing Pain|Incinerate', 'class:DeathKnight': 'Plague Strike|Blood Strike|Icy Touch|Death Strike'}
BASICSET = {(k, n) for k, v in BASICS.items() for n in v.split('|')}
by_role = collections.defaultdict(list)
for s in SPELLS: by_role[s['role']].append(s)
def theme_of(name, ctype):
    n = name.lower()
    for tn, rx, school, bias in TH:
        if re.search(rx, n): return tn, school, bias
    return 'physical-' + ('beast' if ctype == 1 else 'martial'), 'physical', dict(**{'Hit+fx': 1.3}, Multi=1.2) if ctype == 1 else dict(Defense=1.2, CC=1.2)
PETSRC = {x['src'] for x in SPELLS if x['src'].startswith('pet:') and x['src'] not in ('pet:Imp', 'pet:Felguard', 'pet:Voidwalker', 'pet:Succubus', 'pet:Felhunter', 'pet:Ghoul')}
DEFCLS = ['class:Warrior'] * 4 + ['class:Rogue'] * 2 + ['class:Paladin', 'class:Hunter', 'class:Druid']
def sources(name, cf, fam):
    n = name.lower(); src = set(); own = None
    if cf in FAMS: own = 'pet:' + FAMS[cf]; src.add(own); src.add('pet:generic')
    for rx, cl in CLASSES:
        if re.search(rx, n): src |= set(cl)
    animal = fam in ('Beast', 'Critter', 'Flying', 'Aquatic', 'Dragonkin') or own is not None
    if not animal and (not src or (own is None and not any(s.startswith('class:') for s in src))): src |= {DEFCLS[zlib.crc32(name.encode()) % len(DEFCLS)]}   # animals never get a random CLASS (a rabbit with Kill Shot)   # unthemed: a class by name hash, so default humanoids do not all share one spine
    if fam in ('Beast', 'Critter', 'Flying', 'Aquatic', 'Dragonkin') or own: src |= PETSRC | {'class:Druid'}   # animals draw on every hunter-pet signature (own family weighted higher), plus druid forms
    return src, own
DMGG = ('Hit', 'Hit+fx', 'Multi', 'AoE', 'DoT')
NOVIS = set(l.strip() for l in open('pet-battle/ability_novis.txt')) if os.path.exists('pet-battle/ability_novis.txt') else set()   # names whose themed visual the visual test rejects on anything but a plain damage ability (banned everywhere: pet-battle/ability_novis.txt grows from the test output)
HEALWORDS = re.compile(r'Mend|Heal|Renew|Rejuv|Restor|Funnel|Prayer|Regenerat', re.I)   # test_presentation: a healing-sounding name on a damaging ability is rejected
USE = collections.Counter(); SPINES = {}; SPINE_T = {}
sys.path.insert(0, 'pet-battle'); import identity
SLOTPREF = {'CC': ('stun', 'fear', 'root', 'slow'), 'Heal': ('heal', 'hot'), 'Defense': ('shield', 'stealth', 'buff/debuff'), 'Buff': ('buff/debuff',), 'DoT': ('dot',)}
FALLBACKS = collections.Counter(); UNSURE = {}; FBLOG = []; CUR = ['', '']
def _chk(s, g, ents):
    if identity.weight(ents, s['src'], 'basic', False, s['name']) <= 0: FBLOG.append('ZERO-WEIGHT | %s | %s | %s picked %s (%s)' % (CUR[0], CUR[1], g, s['name'], s['src']))
    return s
def pick_spell(g, ents, school, rng, used, basic=False, want=None, prefer=()):   # g = the SPELL group (sg()); ents = the creature's identity entries (identity.py): which sources it may draw on, and how strongly
    roles = tuple(SPELL_ROLE[g]) + tuple(r for r in prefer if r not in SPELL_ROLE[g]); dmg = g in DMGG
    pref = set(prefer)   # the SLOT's own roles (a crowd-control slot wants a stun / fear / slow spell even when the template also deals damage)
    def pool_for(strict, tiers):
        pool = []
        for r in roles:
            for s in by_role[r]:
                if s['name'] in used or s['name'] in NOVIS: continue
                if dmg and HEALWORDS.search(s['name']): continue
                gd = dmg and s['role'] not in pref   # a stun / fear / slow spell fits a crowd-control slot even when the template also deals damage
                w = identity.weight(ents, s['src'], s['tier'], gd, s['name']) if strict else identity.weight(ents, s['src'], 'basic', False, s['name'])
                if w <= 0: continue
                if basic and tiers == 'basic' and not (((s['src'].split('/')[0], s['name']) in BASICSET) or s['tier'] == 'basic'): continue
                if basic and tiers == 'caster' and s['tier'] not in ('basic', 'caster'): continue
                if s['school'] == school: w *= 1.5
                if s['role'] in pref: w *= 6
                elif pref and dmg: w *= 0.6
                if want and dmg:   # the retail presentation range must agree: a melee hit takes melee spells (Envenom), a ranged one ranged spells
                    m = 'melee' if s['mode'] in ('melee', 'self') else 'ranged'
                    w *= 4 if m == want else 0.12
                w /= (1 + USE[s['name']] / 25.0) ** 0.8   # spread names: a name already used by many creatures is much less likely
                pool.append((s, w))
        return pool
    pool = []
    for strict, tiers in ((True, 'basic'), (True, 'caster'), (True, None), (False, None)):
        if tiers and not basic: continue
        pool = pool_for(strict, tiers)
        if pool:
            if not strict or tiers == 'caster': FALLBACKS['relaxed'] += 1
            break
    if not pool:   # nothing allowed fits this slot (e.g. a crowd-control slot for a rabbit): the generic hunter-pet / warrior moves, counted so it shows in the report
        FALLBACKS['generic'] += 1; FBLOG.append('%s | %s | slotgroup %s roles %s | prefer %s' % (CUR[0], CUR[1], g, ','.join(roles), ','.join(prefer)))
        pool = [(s, 1.0) for r in roles for s in by_role[r] if s['name'] not in used and s['name'] not in NOVIS and (s['src'] in ('pet:generic', 'class:Warrior/Arms', 'class:Warrior/Fury', 'class:Warrior/Protection') or s['src'].startswith('pet:'))]
    if not pool: pool = [(s, 1.0) for r in roles for s in by_role[r] if s['name'] not in used]
    tot = sum(w for _, w in pool); x = rng.random() * tot
    for s, w in pool:
        x -= w
        if x <= 0: return _chk(s, g, ents)
    return _chk(pool[-1][0], g, ents)
def draw(dist, bias, rng, exclude):
    c = [(g, w * bias.get(g, 1.0)) for g, w in dist.items() if g not in exclude]
    tot = sum(w for _, w in c); x = rng.random() * tot
    for g, w in c:
        x -= w
        if x <= 0: return g
    return c[-1][0]
def pick_template(g, slot, fam, rng, used):
    cands = [b for b, v in B.items() if v['g'] == g and b not in used and (slot != 1 or v['cd'] == '0') and (slot != 3 or True)]
    if not cands: cands = [b for b, v in B.items() if v['g'] == g and b not in used]
    ws = [min(B[b]['n'], 12) ** 0.5 * (1.5 if slot == 3 and B[b]['cd'] != '0' else 1) * (1.5 if slot == 2 and B[b]['cd'] == '0' and g in ('Hit', 'Hit+fx') else 1) for b in cands]
    b = rng.choices(cands, ws)[0]
    ids = B[b]['ids']; m = [i for i in ids if AR[i]['fam'] == fam]; sh = [i for i in (m or ids) if AR[i]['shipped']]
    return b, (m or sh or ids)[0], bool(m)
ARCH = [('bruiser', (200, 0, -200)), ('tank', (-100, 0, 100)), ('swift', (0, 200, -200)), ('balanced', (0, 0, 0)), ('striker', (100, 100, -200)), ('wall', (-200, 0, 200))]
import os
SALT = {}
if os.path.exists('pet-battle/spine_salts.tsv'):   # written by tune_spines.py: a spine that rated too strong/weak under skilled play is re-rolled with a new salt
    for l in open('pet-battle/spine_salts.tsv'):
        k, v = l.rstrip('\n').split('\t'); SALT[k] = int(v)
rows = [l.rstrip('\n').split('\t') for l in list(open('pet-battle/family_assign.tsv'))[1:]]
if os.path.exists('pet-battle/shipped_assign.tsv'): rows += [l.rstrip('\n').split('\t') for l in list(open('pet-battle/shipped_assign.tsv'))[1:]]   # the shipped species and companions get composed kits with real spells too (user 2026-11-18: real spells for ALL pets)
print('realm\tentry\tname\tfamily\ttheme\tarchetype\tstats\ts1a\ts1b\ts2a\ts2b\ts3a\ts3b')
SPINE = ('s1a', 's2a', 's3a')
kits = []; famok = 0; famn = 0; nroles = collections.Counter(); basics = collections.Counter(); spell_use = collections.Counter()
for realm, entry, name, ctype, cf, fam, why in rows:
    rng = random.Random(zlib.crc32(('%s:%s' % (realm, entry)).encode()))
    tn, school, bias = theme_of(name, int(ctype)); src, own = sources(name, int(cf), fam)
    if fam == 'Critter': bias = dict(bias, Defense=2.2, Heal=1.8, Buff=1.6, **{'Hit+fx': 0.6, 'Multi': 0.6})   # small animals: more support slots (Evasion, Rejuvenation, Fortitude style), fewer special attacks
    CUR[0], CUR[1] = name, fam
    ents0, hits = identity.profile(name, int(ctype), int(cf), fam, own)
    ents = identity.expand(ents0, random.Random(zlib.crc32(('spec%s:%s' % (realm, entry)).encode())))
    if hits in ([], ['default']) and fam not in identity.ANIMAL_FAM and own is None: UNSURE[entry] = (name, fam, 'no class/keyword rule matched')
    top = ','.join(sorted({'%s%s' % (p, '' if sc == 'any' else '#' + sc) for p, w, sc in ents if w >= 0.5}))   # the spine is shared only by creatures with the SAME allowed sources (else a wolf inherits a shadow wolf's warlock spell)
    used_t, used_n, slots, groups = set(), set(), [], []
    plan = [('s1a', 1, S1A), ('s1b', 1, S1B), ('s2a', 2, S2), ('s2b', 2, S2), ('s3a', 3, S3), ('s3b', 3, S3)]
    tkey = '%s|%s' % (tn, fam); spine_key = tkey + '|' + top
    if tkey not in SPINE_T:   # mechanics spine (slots 1a/2a/3a): one per theme+family; names are drawn per source set below
        spr = random.Random(zlib.crc32(('%s#%d' % (tkey, SALT.get(tkey, 0))).encode())); sp_t = set(); st = {}
        for key, sl, dist in plan:
            if key not in SPINE: continue
            g = draw(dist, bias, spr, set()); b, aid, fm = pick_template(g, sl, fam, spr, sp_t); sp_t.add(b); st[key] = (b, aid, fm, g)
        SPINE_T[tkey] = st
    if spine_key not in SPINES:
        spr = random.Random(zlib.crc32(spine_key.encode())); sp_n = set(); sp_sl = {}
        for key, sl, dist in plan:
            if key not in SPINE: continue
            b, aid, fm, g = SPINE_T[tkey][key]
            sp = pick_spell(sg(g, b), ents, school, spr, sp_n, basic=(key == 's1a'), want=want_mode(b), prefer=SLOTPREF.get(g, ())); sp_n.add(sp['name']); sp_sl[key] = (key, b, aid, fm, sp['name'], g, sp)
        SPINES[spine_key] = sp_sl
    for attempt in range(8):
        ir = random.Random(zlib.crc32(('%s:%s#%d' % (realm, entry, attempt)).encode()))
        sp_sl = SPINES[spine_key]; used_t = {v[1] for v in sp_sl.values()}; used_n = {v[4] for v in sp_sl.values()}; slots = []; groups = []
        for key, sl, dist in plan:
            if key in SPINE: slots.append(sp_sl[key]); groups.append(sp_sl[key][5]); continue
            g = draw(dist, bias, ir, set()); b, aid, fm = pick_template(g, sl, fam, ir, used_t); used_t.add(b); groups.append(g)
            sp = pick_spell(sg(g, b), ents, school, ir, used_n, basic=False, want=want_mode(b), prefer=SLOTPREF.get(g, ())); used_n.add(sp['name']); slots.append((key, b, aid, fm, sp['name'], g, sp))
        if len(set(groups)) >= 4: break
    for sl_ in slots: USE[sl_[4]] += 1
    arch = rng.choices(ARCH, [3, 2, 2, 2, 2, 1] if True else None)[0]
    for key, b, aid, fm, sn, g, spo in slots:
        if key.startswith('s1'): famn += 1; famok += fm
    nroles[len(set(groups))] += 1; basics[slots[0][4]] += 1
    for s in slots: spell_use[s[4]] += 1
    kits.append((realm, entry, name, fam, tn, tuple(s[1] for s in slots), tuple(s[4] for s in slots)))
    print('\t'.join([realm, entry, name, fam, tn, arch[0], '/'.join(map(str, arch[1]))] + ['%s|%s|%s|%s|%s|%s|%s' % (s[1], s[2], s[5], s[4], s[6]['id'], s[6]['mode'], s[6]['icon']) for s in slots]))
n = len(kits)
print('kits', n, '| role groups per kit:', dict(sorted(nroles.items())), '| >=4 groups: %d%%' % (100 * sum(v for k, v in nroles.items() if k >= 4) // n), file=sys.stderr)
print('slot-1 ability family == pet family: %d%% (the rest need a family clone)' % (100 * famok // famn), file=sys.stderr)
print('distinct 6-template kits: %d of %d creatures' % (len({k[5] for k in kits}), n), '| distinct full flavored kits: %d' % len({(k[5], k[6]) for k in kits}), file=sys.stderr)
# same theme + same family: average ability-slot difference between random pairs
grp_ = collections.defaultdict(list)
for k in kits: grp_[(k[4], k[3])].append(k)
rr = random.Random(5); d = []; same = 0; pairs = 0
for key, v in grp_.items():
    if len(v) < 2: continue
    for _ in range(min(40, len(v))):
        a, b = rr.sample(v, 2); dd = sum(x != y for x, y in zip(a[5], b[5])); d.append(dd); pairs += 1; same += dd == 0
print('same theme+family pairs: avg template slots different = %.1f of 6 | identical kits: %.1f%% | <=1 different: %.0f%%' % (sum(d) / len(d), 100 * same / pairs, 100 * sum(x <= 1 for x in d) / len(d)), file=sys.stderr)
print('top basic attacks:', basics.most_common(14), file=sys.stderr)
print('spell names used: %d distinct; top:' % len(spell_use), spell_use.most_common(10), file=sys.stderr)
print('fallbacks:', dict(FALLBACKS), '| creatures with no identity rule:', len(UNSURE), file=sys.stderr)
open('pet-battle/.s/unsure.tsv', 'w').write(''.join('%s\t%s\t%s\t%s\n' % (e, *v) for e, v in UNSURE.items()))
open('pet-battle/.s/fallback_log.txt', 'w').write('\n'.join(FBLOG))
