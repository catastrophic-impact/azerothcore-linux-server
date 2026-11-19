#!/usr/bin/env python3 -I
"""GOLDEN BASE TEMPLATE (user 2026-11-19): every retail pet-battle ability used by a species, de-duplicated like a unique-array pass.
Two abilities are the same effect when the per-turn effect list (property id + all 6 params + turn type), the aura they apply (state names+values, recursively) and the cooldown are identical. Names, icons, visuals, descriptions are ignored.
Run from repo root: python3 -I pet-battle/retail_effects_golden.py  -> pet-battle/retail_effects_golden.tsv (571 effects from 854 abilities on the 2026-11 retail dump)."""
import csv,collections,re
d='pet-battle/retail_data/'
R=lambda n:list(csv.DictReader(open(d+n+'.csv',encoding='utf-8')))
ab={a['ID']:a for a in R('BattlePetAbility')}
st={s['ID']:s['LuaName'] for s in R('BattlePetState')}
abst=collections.defaultdict(list)
for x in R('BattlePetAbilityState'): abst[x['BattlePetAbilityID']].append((st.get(x['BattlePetStateID']),int(x['Value'])))
tu=collections.defaultdict(list)
for t in R('BattlePetAbilityTurn'): tu[t['BattlePetAbilityID']].append(t)
ef=collections.defaultdict(list)
for e in R('BattlePetAbilityEffect'): ef[e['BattlePetAbilityTurnID']].append(e)
used={x['BattlePetAbilityID'] for x in R('BattlePetSpeciesXAbility')}
pool=[a for a in ab if a in used and not re.search(r'\btest\b',ab[a]['Name_lang'],re.I) and (ab[a]['Description_lang'] or '').strip() and not ab[a]['Name_lang'].startswith('[DNT]') and ab[a]['Name_lang']!='DATA ERROR']
def sig(a,depth=0):
    out=[]
    for t in sorted(tu[a],key=lambda t:int(t['OrderIndex'])):
        es=[]
        for e in sorted(ef[t['ID']],key=lambda e:int(e['OrderIndex'])):
            x=e['AuraBattlePetAbilityID']; p=tuple(e['Param_%d'%i] for i in range(6)); au=None
            if x!='0': au=(tuple(sorted((str(n),v) for n,v in abst[x] if not str(n).startswith('Cosmetic'))), sig(x,depth+1) if depth<2 else None)
            es.append((e['BattlePetEffectPropertiesID'],p,au))
        out.append((t['TurnTypeEnum'],tuple(es)))
    return tuple(out)
g=collections.OrderedDict()
for a in sorted(pool,key=int): g.setdefault((sig(a),ab[a]['Cooldown']),[]).append(a)
def brief(s):
    r=[]
    for tt,es in s:
        r.append('T%s[%s]'%(tt,' '.join('p%s(%s)%s'%(p,','.join(x for x in q if x!='0') or '-','+aura:'+'/'.join('%s=%d'%kv for kv in au[0]) if au and au[0] else ('+aura' if au else '')) for p,q,au in es)))
    return ' '.join(r)
if __name__=='__main__':
    with open('pet-battle/retail_effects_golden.tsv','w') as f:
        f.write('golden_id\tcooldown\tretail_abilities\teffect\tability_ids\tnames\n')
        for i,((s,cd),v) in enumerate(sorted(g.items(),key=lambda kv:-len(kv[1])),1):
            f.write('G%03d\t%s\t%d\t%s\t%s\t%s\n'%(i,cd,len(v),brief(s),','.join(v),'; '.join(dict.fromkeys(ab[a]['Name_lang'] for a in v))[:120]))
    print(len(pool),'abilities ->',len(g),'unique effects')
