#!/usr/bin/env python3 -I
"""Ability -> 3.3.5 spell visual matcher. For each ability id (stdin/file: 'id<TAB>retailName<TAB>...') it
  1. traces the RETAIL visual: BattlePetAbilityTurn -> BattlePetVisual -> SpellVisualEvent -> SpellVisualKit -> SpellVisualKitEffect(type 2) -> ModelAttach -> EffectName -> listfile path,
  2. finds the 3.3.5 SPELLS (release/data/dbc) whose visual uses the same models, and prints the best instant, aura-free candidates.
Data: pet-battle/retail_data (+ visual/ from wago.tools, listfile).  usage: python3 -I pet-battle/visual_match.py abilities.tsv [--top 3]"""
import csv, struct, sys, collections
csv.field_size_limit(10 ** 9)
RD = 'pet-battle/retail_data/'
def R(n): return list(csv.DictReader(open(RD + n + '.csv')))
def dbc(name):
    d = open('release/data/dbc/%s.dbc' % name, 'rb').read(); _, c, f, rs, ss = struct.unpack('<4sIIII', d[:20])
    recs = [struct.unpack_from('<%dI' % f, d, 20 + i * rs) for i in range(c)]; sb = 20 + c * rs
    return recs, (lambda off: d[sb + off:d.index(b'\0', sb + off)].decode('latin1'))
def stem(p): p = p.lower().replace('\\', '/'); return p.rsplit('.', 1)[0]
# ---- retail side
vis = {v['ID']: v for v in R('BattlePetVisual')}; ab = {a['ID']: a for a in R('BattlePetAbility')}
turns = collections.defaultdict(list)
for t in R('BattlePetAbilityTurn'): turns[t['BattlePetAbilityID']].append(t)
byvis = collections.defaultdict(set)
for e in R('visual/SpellVisualEvent'): byvis[e['SpellVisualID']].add(e['SpellVisualKitID'])
eff = collections.defaultdict(list)
for e in R('visual/SpellVisualKitEffect'): eff[e['ParentSpellVisualKitID']].append(e)
att = {a['ID']: a['SpellVisualEffectNameID'] for a in R('visual/SpellVisualKitModelAttach')}
en = {e['ID']: e['ModelFileDataID'] for e in R('visual/SpellVisualEffectName')}
lf = {}
for l in open(RD + 'visual/listfile.csv'):
    i, _, p = l.strip().partition(';')
    if i.isdigit(): lf[i] = p
def retail_models(aid):
    vs, fns, rng = set(), set(), set()
    a = ab.get(aid); cand = [vis.get(t['BattlePetVisualID']) for t in turns.get(aid, [])] + ([vis.get(a['BattlePetVisualID'])] if a else [])
    for v in cand:
        if not v: continue
        if v['SpellVisualID'] != '0': vs.add(v['SpellVisualID'])
        f = v['SceneScriptFunction'].split('(')[0].strip()
        if f and f != '0': fns.add(f)
        rng.add(v['RangeTypeEnum'])
    out = set()
    for x in vs:
        for k in byvis.get(x, ()):
            for e in eff.get(k, ()):
                if e['EffectType'] == '2':
                    n = att.get(e['Effect']); m = en.get(n) if n else None
                    if m and m in lf: out.add(stem(lf[m]))
    return out, fns, rng
# ---- 3.3.5 side
EN, ens = dbc('SpellVisualEffectName'); ENP = {r[0]: stem(ens(r[2])) for r in EN}
KIT, _ = dbc('SpellVisualKit'); KITM = {}
for r in KIT: KITM[r[0]] = {ENP[x] for x in (r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13]) if x in ENP}
SV, _ = dbc('SpellVisual'); SVM = {}
for r in SV:
    m = set()
    for k in (r[1], r[2], r[3], r[4], r[5], r[6], r[14], r[15], r[23], r[24], r[25]):
        m |= KITM.get(k, set())
    if r[7] and r[8] in ENP: m.add(ENP[r[8]])   # missile model
    SVM[r[0]] = (m, bool(r[7]))
SP, sps = dbc('Spell')
DUR, _ = dbc('SpellDuration'); DURMS = {r[0]: struct.unpack('<i', struct.pack('<I', r[1]))[0] for r in DUR}
spells = []
for r in SP:
    sv = r[131]
    if sv in SVM and SVM[sv][0]:
        aura = any(r[95 + e] for e in range(3)) or any(r[71 + e] == 6 for e in range(3))
        speed = struct.unpack('<f', struct.pack('<I', r[47]))[0]
        spells.append(dict(id=r[0], name=sps(r[136]), models=SVM[sv][0], missile=SVM[sv][1] and speed > 0, school=2 in (r[71], r[72], r[73]),
                           instant=not aura and not DURMS.get(r[40], 0) , cast=r[28]))
# RARITY: a model shared by hundreds of spells (bloodyexplosion, nature_cast_hand) proves nothing; one used by 1-3 spells (kick_chest_impact) is a real match.
# idf weight = 1 / number of 3.3.5 spells that use the model. coverage = weight of the retail models the spell has / weight of the retail models that EXIST in 3.3.5.
DF = collections.Counter()
for s in spells:
    for m in s['models']: DF[m] += 1
JUNK = ('dnd', 'dummy', 'test', 'zzold', 'deprecated', '[ph]', 'unused', 'npc ', 'visual only', 'icecrown airship')
def wt(m): return 1.0 / DF[m] if DF.get(m) else 0.0
def coverage(models, sm):
    have = [m for m in models if DF.get(m)]
    tot = sum(wt(m) for m in have)
    return (sum(wt(m) for m in have if m in sm) / tot) if tot else 0.0
def best(models, top):
    sc = []
    for s in spells:
        ov = len(models & s['models'])
        if ov and not any(j in s['name'].lower() for j in JUNK):
            cov = coverage(models, s['models'])
            sc.append((cov + (0.15 if s['instant'] else 0) + (0.05 if s['school'] else 0) - 0.02 * max(0, len(s['models']) - len(models)), ov, s))
    sc.sort(key=lambda x: -x[0]); seen, out = set(), []
    for v, ov, s in sc:
        if s['id'] in seen: continue
        seen.add(s['id']); out.append((v, ov, s))
        if len(out) >= top: break
    return out
def verdict(models, cand):
    """STRONG = the spell shows every retail model that exists in 3.3.5, it is instant, and the shared models are RARE (each used by <= 12 spells). Anything else is not trusted."""
    if not models: return 'NOMODEL'
    have = [m for m in models if DF.get(m)]
    if not have: return 'ABSENT'   # none of the retail models exists in the 3.3.5 client: themed substitute
    if not cand: return 'NOCAND'
    v, ov, sp = cand
    if sp['instant'] and coverage(models, sp['models']) >= 0.999 and all(DF[m] <= 12 for m in have if m in sp['models']): return 'STRONG'
    return 'WEAK'
if __name__ == '__main__' and '--table' in sys.argv:   # usage: visual_match.py abilities.tsv --table  -> TSV: id name choreography range verdict spellId spellName retailModels
    for l in open(sys.argv[1]):
        c = l.rstrip('\n').split('\t')
        if not c or not c[0].isdigit(): continue
        ms, fns, rng = retail_models(c[0]); b = best(ms, 1) if ms else []
        cand = b[0] if b else None
        print('\t'.join([c[0], c[1], ','.join(sorted(fns)) or 'plain', ','.join(sorted(rng)), verdict(ms, cand), str(cand[2]['id']) if cand else '', cand[2]['name'] if cand else '', ','.join(sorted(ms))]))
    sys.exit(0)
if __name__ == '__main__':
    top = int(sys.argv[sys.argv.index('--top') + 1]) if '--top' in sys.argv else 3
    for l in open(sys.argv[1]):
        c = l.rstrip('\n').split('\t')
        if not c or not c[0].isdigit(): continue
        ms, fns, rng = retail_models(c[0])
        print('== %s %s | choreography: %s | range %s' % (c[0], c[1], ','.join(sorted(fns)) or 'plain', ','.join(sorted(rng))))
        print('   retail models: %s' % (', '.join(sorted(ms)) or '-'))
        for v, ov, s in best(ms, top) if ms else []:
            print('   score %.2f ' % v, end='')
            print('   -> spell %d %-28s overlap %d/%d  %s%s%s' % (s['id'], s['name'][:28], ov, len(ms), 'instant ' if s['instant'] else 'AURA/DURATION ', 'missile ' if s['missile'] else '', 'school-dmg' if s['school'] else ''))
