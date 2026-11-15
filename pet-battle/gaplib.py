"""Shared helper for the zone tools: which retail species are USABLE as a kit (no unhandled effect, not a boss/elite/NPC-style kit)?
usable_species() -> set of retail species ids; gap_species() -> {species: [ability names]}.  (static census, same logic as gap_census.py)"""
import csv, re, collections
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
def _handled():
    core = open('scripts/pb_core.lua').read()
    h = set(re.findall(r'prop == (\d+)', core))
    for m in re.finditer(r'^local (DAMAGE|APPLY|INERT) = \{([^}]*)\}', core, re.M): h |= set(re.findall(r'\[(\d+)\]', m.group(2)))
    return h
_cache = {}
def load():
    if _cache: return _cache
    handled = _handled()
    eff = collections.defaultdict(list); turns = {t['ID']: t['BattlePetAbilityID'] for t in R('BattlePetAbilityTurn')}
    for e in R('BattlePetAbilityEffect'):
        a = turns.get(e['BattlePetAbilityTurnID'])
        if a: eff[a].append((e['BattlePetEffectPropertiesID'], e['AuraBattlePetAbilityID']))
    name = {a['ID']: a['Name_lang'] for a in R('BattlePetAbility')}
    def bad_props(a, seen=None):
        seen = seen if seen is not None else set()
        if a in seen: return set()
        seen.add(a); out = set()
        for p, aura in eff.get(a, []):
            if p not in handled: out.add(p)
            if aura and aura != '0': out |= bad_props(aura, seen)
        return out
    sx = collections.defaultdict(list)
    for x in R('BattlePetSpeciesXAbility'): sx[x['BattlePetSpeciesID']].append(x['BattlePetAbilityID'])
    stn = {s['ID']: s['LuaName'] for s in R('BattlePetState')}
    boss = set()
    for x in R('BattlePetSpeciesState'):
        k = stn.get(x['BattlePetStateID'], ''); v = int(x['Value'])
        if 'Passive_Boss' in k or 'Passive_Elite' in k or k == 'Internal_InitialLevel' or (k == 'Stat_Power' and v >= 200) or (k == 'Stat_Stamina' and v >= 300) or (k == 'Stat_Speed' and v >= 300): boss.add(x['BattlePetSpeciesID'])
    gap = {}
    for sid, abs_ in sx.items():
        bp = set()
        for a in abs_: bp |= bad_props(a)
        if bp: gap[sid] = sorted(bp)
    fam = {s['ID']: int(s['PetTypeEnum']) for s in R('BattlePetSpecies')}
    _cache.update(sx=sx, boss=boss, gap=gap, fam=fam, name=name)
    return _cache
def usable(sid):
    c = load(); return sid in c['sx'] and sid not in c['boss'] and sid not in c['gap']
def gap_species(): return load()['gap']
