#!/usr/bin/env python3 -I
"""FIT of retail builds to our creatures. A build = the 6 golden effects of one retail species (3 slots x 2). A creature can only wear a build when EVERY one of its 6 effects can be dressed with a real 3.3.5
spell that the creature's identity allows (identity.weight > 0). Score = mean of the best spell weight per effect. Fit decides; evenness does not.
Usage (repo root): python3 -I pet-battle/fit_builds.py <roster.tsv>   (roster rows: include, entry, name, levels, type, family, ...)  -> summary + pet-battle/.s/fit_<zone>.tsv"""
import sys, csv, re, zlib, random, collections
sys.path.insert(0, 'pet-battle')
import identity

FAMS = {1: 'Wolf', 2: 'Cat', 3: 'Spider', 4: 'Bear', 5: 'Boar', 6: 'Crocolisk', 7: 'Carrion Bird', 8: 'Crab', 9: 'Gorilla', 11: 'Raptor', 12: 'Tallstrider', 15: 'Felhunter', 16: 'Voidwalker', 17: 'Succubus',
        20: 'Scorpid', 21: 'Turtle', 23: 'Imp', 24: 'Bat', 25: 'Hyena', 26: 'Bird of Prey', 27: 'Wind Serpent', 29: 'Felguard', 30: 'Dragonhawk', 31: 'Ravager', 32: 'Warp Stalker', 33: 'Sporebat',
        34: 'Nether Ray', 35: 'Serpent', 37: 'Moth', 38: 'Chimaera', 39: 'Devilsaur', 40: 'Ghoul', 41: 'Silithid', 42: 'Worm', 43: 'Rhino', 44: 'Wasp', 45: 'Core Hound', 46: 'Spirit Beast'}
LABEL_TOKEN = {'survive-delayed-cd3': 'survive', 'twostep-cd0': 'twostep', 'twostep-cd0#2': 'twostep', 'delayed-cd4': 'sleepdelay', 'delayed-cd20': 'meteor', 'delayed-cd5': 'delayedhit',
               'delayed-cd5#2': 'delayedhit', 'accup-cd0': 'accup', 'accup-cd0#2': 'accup', 'avoidswap-cd7': 'avoidswap', 'avoidswap-cd8': 'avoidswap', 'avoidswap-cd8#2': 'avoidswap'}
V = {'damage', 'dot', 'heal', 'hot', 'drain', 'stun', 'noswap', 'speeddown', 'speedup', 'dmgup', 'dmgdown', 'vuln', 'defense', 'dodge', 'block', 'untargetable', 'damageshield', 'cleanse', 'critup',
     'accdown', 'interrupt', 'aoe', 'multihit', 'rebirth', 'stunchance', 'conditional'}
ATTACK = {'damage', 'multihit', 'aoe', 'dot', 'drain', 'damageshield'}   # anything that hurts: critters/prey may only dress these with plain attacks
ALIAS = {'healpct': 'heal', 'blockability': None}

# effects (golden id -> label tokens, status)
EFF = {}
for l in open('pet-battle/golden_effects_player.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) > 5:
        lab = re.sub(r'-p\d+', '', f[0].split('-cd')[0])
        toks = [ALIAS.get(t, t) for t in lab.split('-') if (t in V and t != 'conditional') or t in ALIAS]
        toks = [t for t in toks if t]
        if f[0] in LABEL_TOKEN: toks = [LABEL_TOKEN[f[0]]]
        plain = bool(re.fullmatch(r'damage(-p\d+)?-cd\d+(#\d+)?', f[0]))
        if toks and toks[0] == 'damage' and re.search(r'all enem|enemy team|all other enemy|split', f[6].lower()) and 'multihit' not in toks: toks = ['aoe'] + toks
        EFF[f[2]] = (f[0], toks, f[4], plain)   # toks == [] means no spell can express this effect (healpct aside): such builds do not fit
OK_STATUS = {'keep', 'failed-our-tests'}

TIER = {}
for l in open('pet-battle/spell_pairing.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) > 6: TIER.setdefault((f[0], f[2]), f[6])
# spells: primary token -> [(source, name)]
BYTOK = collections.defaultdict(list)
for l in open('pet-battle/spell_effect_map.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) > 5:
        for t in f[3].split(): BYTOK[t].append((f[0], f[2]))

COV = {}   # (spell name, effect tokens) -> how many of the effect's parts the spell itself does (a rider such as 'untargetable' should come from a spell that has it)
for t_, lst in BYTOK.items(): pass
SPELLTOK = collections.defaultdict(set)
for l in open('pet-battle/spell_effect_map.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) > 5: SPELLTOK[f[2]] |= set(f[3].split())
# retail builds
d = 'pet-battle/retail_data/'
gid = {}
for l in open('pet-battle/retail_effects_golden.LOCKED.tsv').read().split('\n')[1:]:
    r = l.split('\t')
    if len(r) > 4:
        for a in r[4].split(','): gid[a] = r[0]
sp = collections.defaultdict(lambda: collections.defaultdict(list))
for x in csv.DictReader(open(d + 'BattlePetSpeciesXAbility.csv')): sp[x['BattlePetSpeciesID']][int(x['SlotEnum'])].append(gid.get(x['BattlePetAbilityID'], '?'))
BUILDS = collections.OrderedDict()
for s, v in sp.items():
    if len(v) == 3 and all(len(l) == 2 for l in v.values()):
        ids = tuple(sorted(v[0])) + tuple(sorted(v[1])) + tuple(sorted(v[2]))
        cd0 = lambda g: int((re.search(r'-cd(\d+)', EFF.get(g, ('-cd9',))[0]) or [0, 9])[1])
        if all(EFF.get(g, ('', [], ''))[2] in OK_STATUS for g in ids) and any(cd0(g) < 2 for g in v[0]): BUILDS.setdefault(ids, []).append(s)   # a level-1 pet needs one basic ability with cooldown < 2 (test_l1_kits)


def effect_fit(g, ents):
    lab, toks, st, basic = EFF[g]
    if not toks: return 0.0, None
    is_dmg = bool(set(toks) & ATTACK)
    best = 0.0; who = None
    for src, name in BYTOK.get(toks[0], []):
        w = identity.weight(ents, src, 'basic' if basic else 'x', is_dmg, name)
        if w > best: best, who = w, name
    return best, who


KW_BOOST = 2.5
KWP = []          # source prefixes this creature BORROWS through a keyword (diseased -> poison ...)
MAX_BORROW = 2    # a diseased wolf is still a wolf: at most two borrowed moves per build, never for plain attacks
PREY_OK = {'Bite', 'Smack', 'Gore', 'Thunderstomp', 'Wolverine Bite', 'Snatch'}   # Elwynn evaluation fix 1: small prey/critters get small moves, never Ravage/Shred/Maul


SHIELD = {'Shield Slam', 'Shield Bash', 'Shield Block', 'Shield Wall', 'Holy Shield', "Avenger's Shield", 'Shield of Righteousness', 'Spell Reflection', 'Devastate', 'Revenge'}
FORMS = {'(Bear)': 'pet:Bear', '- Bear': 'pet:Bear', 'Bear)': 'pet:Bear', '(Cat)': 'pet:Cat', '- Cat': 'pet:Cat'}


CUR = ['']
IS_ANIMAL = [False]
GUARDS = re.compile(r'guard|soldier|footman|knight|deputy|militia|defender|marshal|captain|sergeant|lieutenant|enforcer|legionnaire|warden|protector|vanguard|shieldbearer|paladin|crusader|templar')


WEAPON = {'Deadly Throw', 'Fan of Knives', 'Heroic Throw', 'Shattering Throw', 'Backstab', 'Sinister Strike', 'Mutilate', 'Eviscerate', 'Slice and Dice', 'Killing Spree', 'Mortal Strike', 'Garrote', 'Dismantle', 'Disarm', 'Shiv', 'Gouge', 'Riposte', 'Heroic Strike', 'Rend', 'Cleave', 'Execute', 'Slam', 'Whirlwind', 'Bladestorm', 'Overpower', 'Mocking Blow', 'Victory Rush', 'Sunder Armor'}
ANIMAL = {'pet:'}


# a spell that exists ONLY as one hunter-pet family's signature (Swoop, Lava Breath, Pin, Acid Spit ...) goes only to creatures of that family (user 2026-11-19: Wolverine Bite on a cow / Swoop on a crab is odd);
# plain moves every animal could plausibly do stay open for the old 'another family's signature' surprise
PET_ONLY = {}
for _l in open('pet-battle/spell_pairing.tsv').read().split('\n')[1:]:
    _f = _l.split('\t')
    if len(_f) > 9: PET_ONLY.setdefault(_f[2], set()).add(_f[0])
PET_ONLY = {n: {x for x in v} for n, v in PET_ONLY.items() if all(x.startswith('pet:') and x != 'pet:generic' for x in v)}
OPEN_MOVES = {'Claw', 'Bite', 'Smack', 'Gore', 'Charge', 'Dash', 'Thunderstomp', 'Cower', 'Rake', 'Gnaw', 'Snatch', 'Screech', 'Furious Howl', 'Lightning Breath'}


def allowed(name, ents):
    if name in PET_ONLY and name not in OPEN_MOVES and not any(p in PET_ONLY[name] for p, _, _ in ents): return False
    if name in WEAPON and IS_ANIMAL[0]: return False      # needs a weapon: animals do not throw knives or swing swords
    if name in SHIELD and not GUARDS.search(CUR[0]): return False      # needs a shield: soldiers/guards/paladins only
    for k, fam in FORMS.items():
        if k in name and not any(p == fam for p, _, _ in ents): return False                                                                          # bear/cat form moves: bears and cats only
    return True


def cands(g, ents, prey=False):
    lab, toks, st, basic = EFF[g]
    if not toks: return []
    for n_, t_ in SPELLTOK.items(): COV[(n_, tuple(toks))] = len(set(toks) & t_)
    is_dmg = bool(set(toks) & ATTACK)
    out = {}
    for src, name in BYTOK.get(toks[0], []):
        if prey and is_dmg and name not in PREY_OK: continue
        if not allowed(name, ents): continue
        w = identity.weight(ents, src, (TIER.get((src, name), 'utility') if basic else 'x'), is_dmg, name)
        if w > 0:
            borrowed = any(src == p or src.startswith(p + '/') for p in KWP)
            if name not in out or w > out[name][0]: out[name] = (w, borrowed)
    return sorted(((n, wb[0], wb[1]) for n, wb in out.items()), key=lambda c: (-(COV.get((c[0], tuple(toks)), 0)), -c[1], c[0]))


def dress(ids, ents, cache, prey=False):
    """best distinct spell per effect (greedy; a repeat costs half). Returns (normalized fit 0-1, [(effect label, spell)]) or None when an effect has no allowed spell."""
    top = max(w for _, w, _ in ents)
    used = set(); res = []; tot = 0.0; borrowed_n = 0
    for g in ids:
        if g not in cache: cache[g] = cands(g, ents, prey)
        c = cache[g]
        if not c: return None
        plain = EFF[g][3]
        ok = [x for x in c if not (x[2] and (plain or borrowed_n >= MAX_BORROW))]
        if not ok: ok = [(n, w * 0.4, b) for n, w, b in c]      # nothing but borrowed moves exist for this effect: allowed, but it scores badly
        pick = next(((n, w, b) for n, w, b in ok if n not in used), None)
        if pick is None: pick = (ok[0][0], ok[0][1] * 0.5, ok[0][2])
        borrowed_n += 1 if pick[2] else 0
        used.add(pick[0]); tot += min(pick[1] / top, 1.0); res.append((EFF[g][0], pick[0] + (' *' if pick[2] else '')))
    return tot / len(ids), res


def pick_build(scored, entry, margin=0.12):
    """scored = [(fit, ids, dressing)] best first. Many builds fit almost equally well: choose among those within `margin` of the best by the creature's own seed, so identical-looking creatures differ but a creature never changes."""
    if not scored: return None
    top = scored[0][0]
    pool = [x for x in scored if x[0] >= top - margin]
    return random.Random(zlib.crc32(('pick:%s' % entry).encode())).choice(pool)


def creature(entry, name, ctype, cf, fam):
    CUR[0] = name.lower()
    IS_ANIMAL[0] = identity.is_animal(fam, ('pet:' + FAMS[cf]) if cf in FAMS else None, ctype)
    own = 'pet:' + FAMS[cf] if cf in FAMS else None
    ents0, hits = identity.profile(name, ctype, cf, fam, own)
    # earned borrowings (diseased -> poison, spirit -> arcane, frost -> frost ...) must beat the generic animal base, or a diseased wolf is just a wolf
    boosted = set()
    for rx, es in identity.KEYWORDS:
        if re.search(r'\b(?:' + rx + ')', name.lower()): boosted |= {(p, w, sc) for p, w, sc in es}
    ents0 = [(p, w * KW_BOOST, sc) if (p, w, sc) in boosted else (p, w, sc) for p, w, sc in ents0]
    KWP[:] = sorted({p for p, w, sc in boosted})
    rng = random.Random(zlib.crc32(('1:%s' % entry).encode()))
    return identity.expand(ents0, rng), hits


if __name__ == '__main__':
    roster = sys.argv[1]
    meta = {}
    import os
    for fn in ('pet-battle/family_assign.tsv', 'pet-battle/shipped_assign.tsv'):
        if os.path.exists(fn):
            for l in open(fn).read().split('\n')[1:]:
                f = l.split('\t')
                if len(f) > 5: meta[f[1]] = f
    rows = [l.split('\t') for l in open(roster).read().split('\n') if l and not l.startswith('#') and not l.startswith('include')]
    rows = [r for r in rows if r[0] == 'Y' and r[1] in meta]
    summary = []
    for r in rows:
        m = meta[r[1]]
        ents, hits = creature(r[1], m[2], int(m[3]), int(m[4]), m[5])
        cache = {}
        def fit(g):
            if g not in cache: cache[g] = effect_fit(g, ents)
            return cache[g]
        scored = []
        for ids, specs in BUILDS.items():
            fs = [fit(g)[0] for g in ids]
            if min(fs) > 0: scored.append((sum(fs) / 6.0, ids, specs))
        scored.sort(key=lambda x: -x[0])
        # which effects block most builds for this creature
        blockers = collections.Counter(g for ids in BUILDS for g in set(ids) if fit(g)[0] == 0)
        summary.append((r[1], m[2], m[5], len(scored), scored[0][0] if scored else 0, scored, [EFF[g][0] for g, _ in blockers.most_common(3)]))
    print('creatures', len(summary), '| builds in pool', len(BUILDS))
    for e, n, fam, k, top, sc, bl in summary:
        print('%-6s %-28s %-9s fitting builds %4d  best score %.2f%s' % (e, n[:28], fam, k, top, ('   blockers: ' + ', '.join(bl)) if k == 0 else ''))
