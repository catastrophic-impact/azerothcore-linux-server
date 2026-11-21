#!/usr/bin/env python3 -I
"""Effect-only view of the golden list: label = what the effect does + cooldown, no ability names. Run from repo root: python3 -I pet-battle/golden_effects.py -> pet-battle/golden_effects.tsv"""
import csv,collections,re,os
d='pet-battle/retail_data/'
R=lambda n:list(csv.DictReader(open(d+n+'.csv',encoding='utf-8')))
ab={a['ID']:a for a in R('BattlePetAbility')}
st={s['ID']:s['LuaName'] for s in R('BattlePetState')}
abst=collections.defaultdict(set); SV=collections.defaultdict(dict)
for x in R('BattlePetAbilityState'):
    n_=st.get(x['BattlePetStateID'],x['BattlePetStateID']); abst[x['BattlePetAbilityID']].add(n_); SV[x['BattlePetAbilityID']][n_]=int(x['Value'])
tu=collections.defaultdict(list)
for t in R('BattlePetAbilityTurn'): tu[t['BattlePetAbilityID']].append(t)
ef=collections.defaultdict(list)
for e in R('BattlePetAbilityEffect'): ef[e['BattlePetAbilityTurnID']].append(e)
used={x['BattlePetAbilityID'] for x in R('BattlePetSpeciesXAbility')}
pool=[a for a in ab if a in used and not re.search(r'\btest\b',ab[a]['Name_lang'],re.I) and (ab[a]['Description_lang'] or '').strip() and not ab[a]['Name_lang'].startswith('[DNT]') and ab[a]['Name_lang']!='DATA ERROR']
DMG={'24','222','96','62','384','385','29','141','66','149','197','68','27','179','226'}; HEAL={'23','104','32','44'}
src=open('scripts/pb_core.lua').read()
INERT=set(re.findall(r'\[(\d+)\] = true',src.split('\n')[25]))
a0=src.index('local EFFECTS = {'); b0=src.index('\n}\n',a0)
SUP=set(re.findall(r'f\.prop == (\d+)',src[a0:b0]))
for t in('DAMAGE','APPLY','INERT'): SUP|=set(re.findall(r'\[(\d+)\]',re.search(r'local %s = \{(.*?)\}'%t,src).group(1)))
SUP|={'384','385'}; BLOCK={'248','358','363','112','86','45','145'}
VERIFIED=set(l.split('\t')[0].strip() for l in open('pet-battle/verified_gap_abilities.txt') if l.strip() and not l.startswith('#')) if os.path.exists('pet-battle/verified_gap_abilities.txt') else set()   # engine-gap abilities proven by the test layer (see that file)
bl={l.split('\t')[0].strip() for l in open('pet-battle/ability_blocklist.txt') if l.strip() and not l.startswith('#')}
# blocked for a REAL reason (2026-11-19: label-audit-only blocks were re-probed and pass; the audit blocklist entries no longer park an effect)
bl_real={l.split('\t')[0].strip() for l in open('pet-battle/ability_blocklist.txt') if l.strip() and not l.startswith('#') and 'status label audit' not in l}
def allprops(a,dep=0):
    for t in tu[a]:
        for e in ef[t['ID']]:
            yield e['BattlePetEffectPropertiesID']
            x=e['AuraBattlePetAbilityID']
            if x!='0' and dep<2: yield from allprops(x,dep+1)
def feats(a):
    props=set(); states=set(); aprops=set()
    for t in tu[a]:
        for e in ef[t['ID']]:
            props.add(e['BattlePetEffectPropertiesID'])
            x=e['AuraBattlePetAbilityID']
            if x!='0':
                states|={s for s in abst[x] if not s.startswith('Cosmetic')}
                for tt in tu[x]:
                    for ee in ef[tt['ID']]: aprops.add(ee['BattlePetEffectPropertiesID'])
    return props,states,aprops
def typ(a):
    props,states,ap=feats(a); allp=props|ap
    allp-=INERT
    if allp&{'112','248','358','363','86','45','145','373','254','370','97','128'}: return 'X  not in engine / special'
    if any(s.startswith('Weather') for s in states) or '80' in props: return 'WEATHER (area state for N rounds)'
    if states&{'Mechanic_IsObject','Mechanic_IsWall','Mechanic_IsBomb'} or props&{'150','75'}: return 'OBJECT (wall/decoy/trap/turret/bomb) - parked'
    dmg=bool(props&DMG); heal=bool(props&HEAL) or bool(ap&HEAL); multi=bool(props&{'384','385'}); aoe='141' in props
    dot='54' in (props|ap) or bool(states&{'Mechanic_IsPoisoned','Mechanic_IsBurning','Mechanic_IsBleeding','Add_PeriodicDamageTaken'})
    stun=bool(states&{'Mechanic_IsStunned','turnLock'}); lock=bool(states&{'swapOutLock','swapInLock','Mechanic_IsWebbed'})
    untarget=bool(states&{'untargettable','Mechanic_IsFlying','Mechanic_IsUnderground','Mechanic_IsInvisible'})
    base='AOE' if aoe else 'MULTI' if multi else 'DMG' if dmg else ''
    mods=[]
    if 'unkillable' in states: return 'SURVIVE (cannot drop below 1 HP)'
    if untarget: mods.append('untargetable round')
    if stun: mods.append('stun')
    if lock: mods.append('swap-lock')
    if dot: mods.append('DoT')
    if dmg and heal: mods.append('drain/heal')
    if not dmg and heal: mods.append('heal' if not (ap&HEAL or '63' in props) else 'heal over time')
    if 'Stat_Dodge' in states: mods.append('dodge/avoid')
    if 'Special_BlockedAttackCount' in states: mods.append('block N attacks')
    sg=collections.defaultdict(set)
    for t in tu[a]:
        for e in ef[t['ID']]:
            x=e['AuraBattlePetAbilityID']
            if x!='0':
                for n_,v_ in SV[x].items(): sg[n_].add(1 if v_>0 else -1)
    def pol(n_,pos,neg):
        r=[]
        if 1 in sg[n_]: r.append(pos)
        if -1 in sg[n_]: r.append(neg)
        return r
    mods+=pol('Mod_DamageTakenPercent','vulnerability (target takes more)','defense (takes less)')
    mods+=pol('Add_FlatDamageTaken','vulnerability (target takes more)','defense (takes less)')
    mods+=pol('Mod_DamageDealtPercent','damage buff','damage debuff')
    mods+=pol('Mod_SpeedPercent','speed buff','speed debuff')
    mods+=pol('Stat_Speed','speed buff','speed debuff')
    mods+=pol('Stat_Accuracy','accuracy buff','accuracy debuff')
    if 'Mechanic_IsBlind' in states and not sg['Stat_Accuracy']: mods.append('accuracy debuff')
    mods+=pol('Stat_CritChance','crit buff','crit debuff')
    if 'Critical_Damage_Bonus' in states: mods.append('crit buff')
    mods+=pol('Mod_HealingTakenPercent','healing-taken up','healing-taken down')
    mods+=pol('Mod_HealingDealtPercent','healing-dealt up','healing-dealt down')
    mods=list(dict.fromkeys(mods))
    if not dmg and '49' in props and not mods: mods.append('cleanse')
    if ap&DMG and not dot: mods.append('damage shield / retaliation')
    return ' + '.join(([base] if base else [])+mods) or 'other'
def runnable(a): 
    ps=set(allprops(a))-INERT
    return not(ps&BLOCK) and ps<=SUP and a not in bl


def clean(t):
    t = re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', t or '')
    t = re.sub(r'\[StandardAccuracy[^\]]*\]\s*Hit Chance\s*', '', t)
    t = re.sub(r'\[(Standard|Format|Simple)?(Damage|Healing)[^\]]*\]', 'X', t)
    t = re.sub(r'\[duration[^\]]*\]', 'N', t, flags=re.I)
    t = re.sub(r'\[(abs\()?abilityStateMod[^\]]*\]', 'X', t)
    t = re.sub(r'\[School\(\)\]\s*', '', t)
    t = re.sub(r'\[[^\]]*\]', 'X', t)
    t = re.sub(r'\|4(\w+):(\w+);', r'\2', t)
    return re.sub(r'\s+', ' ', t).strip()

# description-driven names for effects the property/state rules cannot name (checked by hand 2026-11-19)
OVERRIDE = [
    (r'removes all buffs and debuffs from the user.s team', 'cleanse-team'),
    (r'removes all buffs and debuffs from the user', 'cleanse-self'),
    (r'removes all buffs and debuffs from the enemy', 'cleanse-enemy'),
    (r'instantly kills the enemy pet', 'instakill'),
    (r'equalizes the health', 'equalizehp'),
    (r'consumes an allied corpse', 'healpct-corpse'),
    (r'bring all other friendly pets back to life', 'reviveall'),
    (r'instantly revive and repair your whole team', 'reviveteam-boost'),
    (r'next pet you swap in will have all of its cooldowns reset', 'swapin-resetcooldowns'),
    (r'opponent.s next ability becomes unusable', 'blockability'),
    (r'pull them out', 'forcedexit'),
    (r'choose which detriment', 'choosedebuff'),
    (r'blessing the next friendly pet to swap into battle', 'swapin-defense'),
    (r'become invisible for one round', 'delayed-untargetable'),
    (r'bring your plushie in for a hug', 'noeffect'),
    (r'next round, your active pet will be healed', 'healpct-delayed'),
    (r'heal for x.? every time they deal damage', 'lifesteal-aura'),
    (r'dealing x damage\. deals x additional damage for each additional pet', 'damage-conditional-samefamily'),
    (r'consume the target, dealing x damage, and 150% bonus damage if the caster is (slower|faster)', 'damage-conditional-speedcompare'),
    (r'healing for x\. this healing increased by x% if health is below', 'heal-conditional-lowhp'),
    (r'damage all enemy targets for x% of their current health', 'aoe-drain-pctcurrent'),
    (r'damage increases by x each time it is used', 'damage-escalating'),
    (r'active pet and x damage to the enemy.s backline', 'damage-backline'),
    (r'rushes at the enemy to inflict damage', 'damage-plain'),
    (r'restores x health every round for n rounds\. while healing, your type', 'hot-typechange'),
    (r'reborn with full health', 'rebirth-delayed'),
    (r'dealing 50% of the damage they take', 'damageshield-reflectpct'),
]


def apply_override(desc, lab):
    for rx, name in OVERRIDE:
        if re.search(rx, desc):
            return name
    return lab


def label(a):
    props, states, ap = feats(a)
    allp = (props | ap) - INERT
    desc = clean(ab[a]['Description_lang']).lower()
    sg = collections.defaultdict(set)
    for t in tu[a]:
        for e in ef[t['ID']]:
            x = e['AuraBattlePetAbilityID']
            if x != '0':
                for n_, v_ in SV[x].items():
                    sg[n_].add(1 if v_ > 0 else -1)
    T = []
    dmg = bool(props & DMG)
    heal = bool(props & HEAL)
    if props & {'384', '385'}: T.append('multihit')
    elif '141' in props: T.append('aoe')
    elif dmg: T.append('damage')
    if allp & {'145', '139', '107'}:
        if re.search(r'forces the opponent|swap into battle', desc): T.append('forceswap')
        elif 'avoid' in desc: T.append('avoidswap')
        elif re.search(r'swaps? (the user|automatically)', desc): T.append('swapself')
        else: T.append('swap')
    if allp & {'179', '204'}: T.append('damageshield')
    if heal and dmg: T.append('drain')
    elif heal: T.append('heal')
    if '53' in props: T.append('healpct')
    if '63' in allp or (ap & HEAL and not heal): T.append('hot')
    if '131' in allp: T.append('interrupt')
    if states & {'Mechanic_IsStunned', 'turnLock'}: T.append('stunchance' if ('chance' in desc and 'stun' in desc) else 'stun')
    if states & {'swapOutLock', 'swapInLock', 'Mechanic_IsWebbed'}: T.append('noswap')
    if '54' in allp or states & {'Mechanic_IsPoisoned', 'Mechanic_IsBurning', 'Mechanic_IsBleeding', 'Add_PeriodicDamageTaken'} or (ap & DMG and not allp & {'179', '204'}): T.append('dot')
    for n_, pos, neg in (('Mod_SpeedPercent', 'speedup', 'speeddown'), ('Stat_Speed', 'speedup', 'speeddown'), ('Mod_DamageDealtPercent', 'dmgup', 'dmgdown'),
                         ('Stat_Accuracy', 'accup', 'accdown'), ('Stat_CritChance', 'critup', 'critdown'), ('Mod_DamageTakenPercent', 'vuln', 'defense'),
                         ('Add_FlatDamageTaken', 'vuln', 'defense'), ('Mod_HealingTakenPercent', 'healtakenup', 'healtakendown')):
        if 1 in sg[n_]: T.append(pos)
        if -1 in sg[n_]: T.append(neg)
    if 'Mechanic_IsBlind' in states and 'accdown' not in T: T.append('accdown')
    if 'Critical_Damage_Bonus' in states: T.append('critup')
    if 'Stat_Dodge' in states and 'avoidswap' not in T: T.append('dodge')
    if 'Special_BlockedAttackCount' in states: T.append('block')
    if states & {'untargettable', 'Mechanic_IsFlying', 'Mechanic_IsUnderground', 'Mechanic_IsInvisible'}: T.append('untargetable')
    if 'unkillable' in states: T.append('survive')
    if '80' in props or any(s.startswith('Weather') for s in states): T.append('weather')
    if states & {'Mechanic_IsObject', 'Mechanic_IsWall', 'Mechanic_IsBomb'} or props & {'150', '75'}: T.append('object')
    if props & {'76', '77', '78'}: T.append('twostep')
    if re.search(r'always goes first|goes first', desc) or '79' in props: T.append('goesfirst')
    if 'must recharge' in desc: T.append('recharge')
    if re.search(r'after \w+ rounds|next round|in two rounds|rounds from now|fall .* rounds|second use|first use', desc) and 'twostep' not in T: T.append('delayed')
    if re.search(r'\bif\b|extra damage|bonus damage|double damage|increases? each|grows', desc) and 'cond' not in T: T.append('conditional')
    if '49' in props and not dmg and 'Stat_Dodge' not in states and not T: T.append('cleanse')
    pts = ''
    for t in tu[a]:
        for e in ef[t['ID']]:
            if e['BattlePetEffectPropertiesID'] in DMG | HEAL | {'53'}:
                pts = 'p' + e['Param_0']
                break
        if pts: break
    lab_ = apply_override(desc, '-'.join(dict.fromkeys(T) or ['special']))
    if lab_ in ('damage-backline','damage-escalating','damage-plain','damage-conditional-samefamily','damage-conditional-speedcompare','heal-conditional-lowhp'): pts_keep = pts
    return lab_, pts


REAL_FAIL = {'606', '2358', '1101', '2378', '774', '1063', '1962'}   # Elementium Bolt, Void Crash, Shieldstorm, Rays of Light, Rapid Fire, Pheromones, Tentacle Stab
rows = [l.split('\t') for l in open('pet-battle/retail_effects_golden.LOCKED.tsv').read().split('\n')[1:] if l.count('\t') > 4]
out = []
seen = collections.Counter()
for r in rows:
    ids = r[4].split(',')
    a = ids[0]
    ps = set(allprops(a)) - INERT
    f = feats(a)
    if f[1] & {'Mechanic_IsObject', 'Mechanic_IsWall', 'Mechanic_IsBomb'} or f[0] & {'150', '75'}: st_ = 'objects'
    elif ps & BLOCK or not ps <= SUP: st_ = 'engine-gap'
    elif set(ids) & REAL_FAIL or all(i in bl_real for i in ids): st_ = 'engine-gap'   # 2026-11-19: probed, the engine really gets these wrong (delayed bolt never lands, block aura, backline/aoe targeting, restores)
    else: st_ = 'keep'
    if st_ == 'engine-gap' and set(ids) <= VERIFIED: st_ = 'keep'   # every ability of the effect passed the ability tests with its distinctive mechanic checked
    lab, pts = label(a)
    full = '%s%s-cd%s' % (lab, ('-' + pts) if pts else '', r[1])
    seen[full] += 1
    if seen[full] > 1: full += '#%d' % seen[full]
    out.append((int(r[1]), full, r[0], len(ids), st_, ','.join(ids), clean(ab[a]['Description_lang'])))
out.sort(key=lambda o: (o[0], o[1]))
with open('pet-battle/golden_effects.tsv', 'w') as fh:
    fh.write('label\tcooldown\tgolden_id\tretail_abilities\tstatus\tability_ids\tplain_text\n')
    for o in out:
        fh.write('%s\t%d\t%s\t%d\t%s\t%s\t%s\n' % (o[1], o[0], o[2], o[3], o[4], o[5], o[6]))
print(len(out), collections.Counter(o[4] for o in out))
