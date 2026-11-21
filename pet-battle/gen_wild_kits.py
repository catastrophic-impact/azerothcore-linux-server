#!/usr/bin/env python3 -I
"""Turn pet-battle/kits_prototype.tsv into DATA the engine already understands (no engine change):
  R.species[<synthetic id>]  = family, stats, 6 abilities (slot, unlock level, ability id)        (retail species shape)
  R.abilities[...]           = retail abilities that pb_retail.lua does not hold yet + FAMILY CLONES (same effects, another damage family; id 5,000,000 + id*10 + family, field base = original id)
  D.species[<creature>]      = { name, retail = synthetic id, wild = true }
  D.rename[<creature>][<retail ability name>] = { name, icon, vis, ranged }   the 3.3.5 spell that lends name + visual (damage abilities only; other roles keep the retail presentation)
Ability family: sampled per slot from retail's own rates (same family as the pet in ~55% of retail kit slots) with retail's real off-family pairings, seeded per creature.
Usage (repo root): python3 -I pet-battle/gen_wild_kits.py <out.lua> [limit]"""
import sys, csv, re, random, zlib, collections
out_path = sys.argv[1]; limit = int(sys.argv[2]) if len(sys.argv) > 2 else 10 ** 9
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
ab = {a['ID']: a for a in R('BattlePetAbility')}
tu = collections.defaultdict(list)
for t in R('BattlePetAbilityTurn'): tu[t['BattlePetAbilityID']].append(t)
ef = collections.defaultdict(list)
for e in R('BattlePetAbilityEffect'): ef[e['BattlePetAbilityTurnID']].append(e)
pr = {p['ID']: p for p in R('BattlePetEffectProperties')}
st = {s['ID']: s['LuaName'] for s in R('BattlePetState')}
abst = collections.defaultdict(dict)
for x in R('BattlePetAbilityState'):
    if x['BattlePetStateID'] in st: abst[x['BattlePetAbilityID']][st[x['BattlePetStateID']]] = int(x['Value'])
FAM = ['Humanoid', 'Dragonkin', 'Flying', 'Undead', 'Critter', 'Magic', 'Elemental', 'Beast', 'Aquatic', 'Mechanical']
q = lambda s: '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'
have = set(re.findall(r'^R\.abilities\[(\d+)\]', open('scripts/pb_retail.lua').read(), re.M))
KEEP_AURA = {'831', '1124'}   # the engine compares these two aura ids literally (pb_core), so they are never cloned
# --- retail's own family habits: P(ability family == pet family) per slot, and the off-family pairings
spf = {s['ID']: int(s['PetTypeEnum']) for s in R('BattlePetSpecies')}; abf = {a: int(v['PetTypeEnum']) for a, v in ab.items()}
same = collections.defaultdict(lambda: [0, 0]); off = collections.defaultdict(collections.Counter)
for x in R('BattlePetSpeciesXAbility'):
    sp = spf.get(x['BattlePetSpeciesID']); af = abf.get(x['BattlePetAbilityID'], -1)
    if sp is None or af < 0 or int(x['RequiredLevel']) == 0: continue
    k = (int(x['SlotEnum']), int(x['RequiredLevel']) >= 10); same[k][1] += 1
    if sp == af: same[k][0] += 1
    else: off[sp][af] += 1
P_OWN = {k: v[0] / v[1] for k, v in same.items() if v[1] > 100}
need_base, clones, lua_ab = set(), {}, []
def clone_id(a, fam): return 5000000 + int(a) * 10 + fam
def want_ability(a, fam):
    """ability id usable as retail ability `a` in damage family `fam` (original if it already is, else a clone, aura helpers cloned too)"""
    stack = [a]; seen = {a}; need_base.add(a)   # the ability and every aura ability it applies (down the chain) must exist as base data, cloned or not
    while stack:
        x = stack.pop()
        for t in tu[x]:
            for e in ef[t['ID']]:
                y = e['AuraBattlePetAbilityID']
                if y != '0' and y not in seen: seen.add(y); stack.append(y); need_base.add(y)
    if abf[a] == fam or abf[a] < 0: return int(a)
    cid = clone_id(a, fam); clones[cid] = (a, fam)
    return cid
def ser(aid, fam=None, newid=None):
    A = ab[aid]; turns = []
    for t in sorted(tu[aid], key=lambda t: int(t['OrderIndex'])):
        es = []
        for e in sorted(ef[t['ID']], key=lambda e: int(e['OrderIndex'])):
            x = e['AuraBattlePetAbilityID']
            if fam is not None and x != '0' and x not in KEEP_AURA and abf.get(x, -1) >= 0 and abf[x] != fam: xid = clone_id(x, fam)
            else: xid = x
            es.append('{ prop = %s, aura = %s, p = { %s } }' % (e['BattlePetEffectPropertiesID'], xid, ', '.join(e['Param_%d' % i] for i in range(6))))
        turns.append('{ turn = %s, event = %s, fx = { %s } }' % (t['TurnTypeEnum'], t['EventTypeEnum'], ', '.join(es)))
    f = int(A['PetTypeEnum']) if fam is None else fam
    return 'R.abilities[%s] = { name = %s, family = %d, cd = %s, text = %s, base = %s, turns = { %s } }' % (newid or aid, q(A['Name_lang']), f, A['Cooldown'], q(A['Description_lang']), aid, ', '.join(turns))
rows = [l.rstrip('\n').split('\t') for l in list(open('pet-battle/kits_prototype.tsv'))[1:]][:limit]
CEN = {}   # entry -> (creature type, creature family) from the census the kits were built for
import os
for fn in ('pet-battle/family_assign.tsv', 'pet-battle/shipped_assign.tsv'):
    if os.path.exists(fn):
        for l in list(open(fn))[1:]:
            x = l.rstrip('\n').split('\t'); CEN[x[1]] = (int(x[3]), int(x[4]))
BEASTICON = {1: 'Ability_Hunter_Pet_Wolf', 2: 'Ability_Hunter_Pet_Cat', 3: 'Ability_Hunter_Pet_Spider', 4: 'Ability_Hunter_Pet_Bear', 5: 'Ability_Hunter_Pet_Boar', 6: 'Ability_Hunter_Pet_Crocolisk', 7: 'Ability_Hunter_Pet_Vulture',
             8: 'Ability_Hunter_Pet_Crab', 9: 'Ability_Hunter_Pet_Gorilla', 11: 'Ability_Hunter_Pet_Raptor', 12: 'Ability_Hunter_Pet_TallStrider', 20: 'Ability_Hunter_Pet_Scorpid', 21: 'Ability_Hunter_Pet_Turtle', 24: 'Ability_Hunter_Pet_Bat',
             25: 'Ability_Hunter_Pet_Hyena', 26: 'Ability_Hunter_Pet_Owl', 27: 'Ability_Hunter_Pet_WindSerpent', 30: 'Ability_Hunter_Pet_Dragonhawk', 31: 'Ability_Hunter_Pet_Ravager', 32: 'Ability_Hunter_Pet_WarpStalker', 33: 'Ability_Hunter_Pet_Sporebat',
             34: 'Ability_Hunter_Pet_NetherRay', 35: 'Ability_Hunter_Pet_Serpent', 37: 'Ability_Hunter_Pet_Moth', 38: 'Ability_Hunter_Pet_Chimera', 39: 'Ability_Hunter_Pet_Devilsaur', 41: 'Ability_Hunter_Pet_Silithid', 42: 'Ability_Hunter_Pet_Worm',
             43: 'Ability_Hunter_Pet_Rhino', 44: 'Ability_Hunter_Pet_Wasp', 45: 'Ability_Hunter_Pet_CoreHound', 46: 'Ability_Hunter_Pet_SpiritBeast'}
FAMICON = {'Humanoid': 'INV_Misc_Bandana_03', 'Undead': 'Spell_Nature_NullifyDisease', 'Magic': 'Spell_Shadow_ShadowBolt', 'Elemental': 'Spell_Nature_HealingWay', 'Mechanical': 'INV_Gizmo_01', 'Dragonkin': 'INV_Misc_Head_Dragon_01',
           'Aquatic': 'INV_Misc_Fish_02', 'Critter': 'Ability_Druid_Dash', 'Flying': 'Ability_Hunter_Pet_Bat', 'Beast': 'Ability_Hunter_Pet_Wolf'}
NOVIS = set(l.strip() for l in open('pet-battle/ability_novis.txt')) if __import__('os').path.exists('pet-battle/ability_novis.txt') else set()   # names whose explicit spell visual the tests rejected: the engine's name theme decides instead
ALIAS = []   # display-name aliases (pet-battle/name_aliases.tsv): spell | keep-regex (creature) | effect-label regex | new name | new icon
GLAB = {}
if os.path.exists('pet-battle/name_aliases.tsv'):
    for l in open('pet-battle/name_aliases.tsv', encoding='utf-8'):
        f = l.rstrip('\n').split('\t')
        if not l.startswith('#') and len(f) >= 4: ALIAS.append((f[0], f[1], f[2], f[3], f[4] if len(f) > 4 else '', f[5] if len(f) > 5 else '', f[6] if len(f) > 6 else '', f[7] if len(f) > 7 else ''))
    for l in list(open('pet-battle/golden_effects.tsv', encoding='utf-8'))[1:]:
        f = l.split('\t'); GLAB[f[2]] = f[0]
CTYPE = {}
if os.path.exists('pet-battle/creature_types.tsv'):
    for l in open('pet-battle/creature_types.tsv'):
        f = l.split()
        if len(f) == 2 and f[0].isdigit(): CTYPE[f[0]] = f[1]
def alias(sname, icon, ename, bid, fam='', entry=''):
    lab = GLAB.get(bid[1:], '')
    for sp, keep, eff, new, nicon, famre, crre, cts in ALIAS:
        if sp != sname: continue
        if famre and not re.search('^(' + famre + ')$', fam): continue   # optional 6th column: only for pets of these families
        if cts and CTYPE.get(str(entry)) not in cts.split(','): continue   # optional 8th column: only creatures of these creature types (1,2,8 = animals)
        if crre and not re.search(crre, ename, re.I): continue   # optional 7th column: only for creatures whose name matches
        if keep and re.search(keep, ename, re.I): continue
        if eff and not re.search(eff, lab): continue
        return new, (nicon or icon)
    return sname, icon
ZROWS = []   # zone manifest rows added by wire_wild_kits.py (status 'composed'): id, name, lo, hi, minMob, maxMob
for l in open('pet-battle/zone_ranges.tsv', encoding='utf-8'):
    f = l.rstrip('\n').split('\t')
    if not l.startswith('#') and len(f) > 14 and f[14] == 'composed': ZROWS.append((f[1], f[12], f[8], f[9], f[10], f[11]))
sp_lines, d_lines, rn_lines = [], [], []; stats_fam = collections.Counter(); dup = 0; sid = 1000000
FAM_ADJ = {}   # optional per-family stat offsets; iteration 1 (Flying speed -100) did not move the win rate, so the spine is the lever (tune_spines.py)
LV = [(0, 1), (0, 10), (1, 2), (1, 15), (2, 4), (2, 20)]
for realm, entry, name, fam, theme, arch, stats, *slots in rows:
    rng = random.Random(zlib.crc32(('fam%s:%s' % (realm, entry)).encode())); pf = FAM.index(fam)
    kit, names, ren = [], set(), {}
    for (slot, lvl), s in zip(LV, slots):
        b, aid, g, sname, spid, mode, icon = s.split('|')
        sname, icon = alias(sname, icon, name, b, fam, entry)
        po = P_OWN.get((slot, lvl >= 10), 0.55)
        if rng.random() < po or not off[pf]: af = pf
        else:
            c = off[pf]; af = rng.choices(list(c), list(c.values()))[0]
        stats_fam[(slot, af == pf)] += 1
        cands = [aid] + [i for i in [aid]]       # the prototype's pick; its own family wins over a clone
        use = want_ability(aid, af)
        rn = ab[aid]['Name_lang']
        if rn in names: dup += 1; kit.append('{ %d, %d, %d }' % (slot, lvl, use)); continue     # D.rename is keyed by the retail name: two slots with one retail name would share a rename -> skip the slot's rename, keep the mechanics
        names.add(rn)
        if re.search(r'\b' + re.escape(rn) + r'\b', sname, re.I): kit.append('{ %d, %d, %d }' % (slot, lvl, use)); continue   # the new name contains the retail name as a word (Devour -> Devour Magic Effect): the test rejects it, keep the retail name
        kit.append('{ %d, %d, %d }' % (slot, lvl, use))
        dmg = g in ('Hit', 'Hit+fx', 'Multi', 'AoE')
        r = '{ name = %s' % q(sname)
        if icon: r += ', icon = %s' % q(icon)
        if dmg and sname not in NOVIS: r += ', vis = %s, ranged = %s' % (spid, 'true' if mode in ('ranged', 'target') else 'nil')
        elif not dmg and sname not in NOVIS: r += ', vis = %s, vm = "%s"' % (spid, mode if mode in ('self', 'target', 'ranged', 'melee') else 'self')   # buffs / heals / crowd control: the real spell is cast in its own mode (self = on the pet, target = at the enemy)
        ren[rn] = r + ' }'
    p, sv, sa = (int(x) for x in stats.split('/')); sid += 1
    ap, asv, asa = FAM_ADJ.get(fam, (0, 0, 0)); p, sv, sa = p + ap, sv + asv, sa + asa   # per-family calibration from the skilled sweep (sim_skill_kits.lua)
    sp_lines.append('R.species[%d] = { name = %s, family = %s, stats = { Stat_Power = %d, Stat_Speed = %d, Stat_Stamina = %d }, abil = { %s } }' % (sid, q(name), q(fam), p, sv, sa, ', '.join(kit)))
    ct, cf = CEN.get(entry, (0, 0)); icon = BEASTICON.get(cf) if ct == 1 and BEASTICON.get(cf) else FAMICON[fam]
    d_lines.append('do local s = D.species[%s]; if s then s.retail0 = s.retail; s.retail = %d; s.synthetic = true else D.species[%s] = { name = %s, retail = %d, %swild = true, synthetic = true, icon = %s } end end' % (entry, sid, entry, q(name), sid, 'critter = true, ' if ct == 8 else '', q(icon)))
    rn_lines.append('D.rename0[%s] = D.rename[%s] or false; D.rename[%s] = { %s }' % (entry, entry, entry, ', '.join('[%s] = %s' % (q(k), v) for k, v in ren.items())))
# abilities: every base ability not yet in pb_retail + every clone (+ their states / effect labels)
for a in sorted(need_base, key=int):
    if a not in have: lua_ab.append(ser(a))
st_lines = []; effp = set()
for a in sorted(need_base, key=int):
    if a not in have and abst.get(a): st_lines.append('R.states[%s] = { %s }' % (a, ', '.join('%s = %d' % kv for kv in sorted(abst[a].items()))))
for a in list(need_base):
    for t in tu[a]:
        for e in ef[t['ID']]: effp.add(e['BattlePetEffectPropertiesID'])
# aura helper clones (ser() references clone_id(x, fam) for aura children): emit them
extra = []
done = set(clones)
changed = True
while changed:
    changed = False
    for cid, (a, f) in list(clones.items()):
        for t in tu[a]:
            for e in ef[t['ID']]:
                x = e['AuraBattlePetAbilityID']
                if x != '0' and x not in KEEP_AURA and abf.get(x, -1) >= 0 and abf[x] != f:
                    c2 = clone_id(x, f)
                    if c2 not in clones: clones[c2] = (x, f); changed = True
eff_lines = ['R.effects[%s] = { %s }' % (p, ', '.join(q(pr[p]['ParamLabel_%d' % i]) for i in range(6) if pr[p]['ParamLabel_%d' % i])) for p in sorted(effp, key=int)]
with open(out_path, 'w', encoding='utf-8') as f:
    f.write('-- GENERATED by pet-battle/gen_wild_kits.py (composed wild-mob kits for the Outland/Northrend zones). Do not edit by hand.\nlocal R = require("pb_retail")\nlocal D = require("pb_data")\n')
    f.write('\n'.join(lua_ab + st_lines) + '\n')
    f.write('local KEEP = { [831] = true, [1124] = true }   -- aura ids the engine compares literally\nlocal CL = {\n' + ''.join('{%d,%s,%d},' % (cid, a, f) + ('\n' if i % 12 == 11 else '') for i, (cid, (a, f)) in enumerate(sorted(clones.items()))) + '\n}\n')
    f.write('''local function chain(x, fam, map, d)   -- the aura ids this ability applies (down the chain) that get a clone in `fam`
    local a = R.abilities[x]; if not a or d > 3 then return end
    for _, t in ipairs(a.turns) do for _, f in ipairs(t.fx) do
        local au = f.aura
        if au and au ~= 0 and not KEEP[au] then
            local ba = R.abilities[au]
            if ba and ba.family >= 0 and ba.family ~= fam and not map[au] then map[au] = 5000000 + au * 10 + fam; chain(au, fam, map, d + 1) end
        end
    end end
end
for _, c in ipairs(CL) do   -- FAMILY CLONES: the same ability with another damage family (aura helpers follow, except the literal ids)
    local cid, base, fam = c[1], c[2], c[3]; local b = R.abilities[base]
    local map = { [base] = cid }; chain(base, fam, map, 1)
    -- the description text names auras by id inside [..] (Fx() only accepts an aura the ability really applies): follow the remapped ids
    local text = b.text and b.text:gsub("%[[^%]]*%]", function(expr) return (expr:gsub("%f[%d](%d+)%f[%D]", function(n) local m = map[tonumber(n)]; return m and tostring(m) or n end)) end) or b.text
    local a = { name = b.name, family = fam, cd = b.cd, text = text, base = base, turns = {} }
    for i, t in ipairs(b.turns) do
        local fx = {}
        for j, f in ipairs(t.fx) do fx[j] = { prop = f.prop, aura = (f.aura and map[f.aura]) or f.aura, p = f.p } end
        a.turns[i] = { turn = t.turn, event = t.event, fx = fx }
    end
    R.abilities[cid] = a; if R.states[base] then R.states[cid] = R.states[base] end
end
''')
    f.write('for p, labels in pairs({\n' + '\n'.join('  [%s] = { %s },' % (p, ', '.join(q(pr[p]['ParamLabel_%d' % i]) for i in range(6) if pr[p]['ParamLabel_%d' % i])) for p in sorted(effp, key=int)) + '\n}) do if not R.effects[p] then R.effects[p] = labels end end\n')
    f.write('\n'.join('D.zones[%s] = { name = %s, lo = %s, hi = %s, minMob = %s, maxMob = %s }' % (z[0], q(z[1]), z[2], z[3], z[4], z[5]) for z in ZROWS) + '\n')
    ICONOV = [l.rstrip('\n').split('\t') for l in open('pet-battle/icon_overrides.tsv') if l.strip() and not l.startswith('#')] if os.path.exists('pet-battle/icon_overrides.tsv') else []
    f.write('\n'.join(sp_lines) + '\n' + '\n'.join(d_lines) + '\nD.rename = D.rename or {}; D.rename0 = D.rename0 or {}\n' + '\n'.join(rn_lines) + '\n' + ''.join('do local s = D.species[%s]; if s then s.icon = %s end end\n' % (o[0], q(o[1])) for o in ICONOV) + 'if os.getenv and os.getenv("PB_LEGACY") then D.UseLegacyKits() end   -- engine tests use the original hand-picked retail kits as fixtures\n')
print('creatures', len(rows), '| base abilities added', sum(1 for a in need_base if a not in have), '| family clones', len(clones), '| duplicate-retail-name slots dropped', dup)
own = sum(v for (s, o), v in stats_fam.items() if o); tot = sum(stats_fam.values()); print('own-family ability slots: %d%% (retail 55%%)' % (100 * own // tot))
