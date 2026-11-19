#!/usr/bin/env python3 -I
"""Runs the build fit over every zone roster. Writes pet-battle/.s/fit_all.tsv (pet, zone, family, fitting builds, picked build's spells) and pet-battle/nofit_pets.txt (pets with no fitting build)."""
import sys, glob, os, importlib.util, collections
sys.argv = ['x']
spec = importlib.util.spec_from_file_location('fb', 'pet-battle/fit_builds.py'); fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
meta = {}
for fn in ('pet-battle/family_assign.tsv', 'pet-battle/shipped_assign.tsv'):
    for l in open(fn).read().split('\n')[1:]:
        f = l.split('\t')
        if len(f) > 5: meta[f[1]] = f
import csv, zlib, re
# --- kit rows (the kits_prototype.tsv shape gen_wild_kits.py reads): the build's OWN retail abilities (numbers) dressed with the fitted real spells (name / visual / icon)
PAIR = {}; BYNAME = collections.defaultdict(list)
for l in open('pet-battle/spell_pairing.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) > 9: PAIR[(f[0], f[2])] = (f[1], f[5], f[9]); BYNAME[f[2]].append(f[0])
_d = 'pet-battle/retail_data/'
_stn = {r['ID']: r['LuaName'] for r in csv.DictReader(open(_d + 'BattlePetState.csv'))}
SPSTAT = collections.defaultdict(dict)
for r in csv.DictReader(open(_d + 'BattlePetSpeciesState.csv')):
    if _stn.get(r['BattlePetStateID'], '').startswith('Stat_'): SPSTAT[r['BattlePetSpeciesID']][_stn[r['BattlePetStateID']]] = int(r['Value'])
SPFAM = {r['ID']: int(r['PetTypeEnum']) for r in csv.DictReader(open(_d + 'BattlePetSpecies.csv'))}
SPAB = collections.defaultdict(list)
for r in csv.DictReader(open(_d + 'BattlePetSpeciesXAbility.csv')): SPAB[r['BattlePetSpeciesID']].append((int(r['SlotEnum']), int(r['RequiredLevel']), r['BattlePetAbilityID']))
PT = ['Humanoid', 'Dragonkin', 'Flying', 'Undead', 'Critter', 'Magic', 'Elemental', 'Beast', 'Aquatic', 'Mechanical']
BL = {l.split('\t')[0].strip() for l in open('pet-battle/ability_blocklist.txt') if l.strip() and not l.startswith('#') and 'status label audit' not in l}
def kit_row(zone, entry, name, fam, ids, spells, ents):
    sps = fb.BUILDS[ids]; pf = PT.index(fam)
    same = [x for x in sps if SPFAM.get(x) == pf] or sps
    sp = same[zlib.crc32(('sp:%s' % entry).encode()) % len(same)]
    st = SPSTAT[sp]; stats = '%d/%d/%d' % (st.get('Stat_Power', 0), st.get('Stat_Speed', 0), st.get('Stat_Stamina', 0))
    used = set(); cells = []
    for slot, lvl, a in sorted(SPAB[sp]):
        g = fb.gid.get(a, '?')
        if a in BL:   # the species' own ability fails a test: another retail ability with the SAME effect (same numbers) stands in
            alts = sorted((x for x, gg in fb.gid.items() if gg == g and x not in BL), key=int)
            if alts: a = alts[0]
        j = next(i for i, x in enumerate(ids) if x == g and i not in used); used.add(j)
        sname = spells[j][1].replace(' *', '')
        srcs = BYNAME.get(sname) or ['?']
        src = max(srcs, key=lambda c: fb.identity.weight(ents, c, 'x', False, sname))
        sid, mode, icon = PAIR.get((src, sname), ('0', 'self', ''))
        grp = 'Hit' if set(fb.EFF[g][1]) & fb.ATTACK else 'Util'
        cells.append('B%s|%s|%s|%s|%s|%s|%s' % (g, a, grp, sname, sid, mode, icon))
    cd = lambda c: int((re.search(r'-cd(\d+)', fb.EFF[c.split('|')[0][1:]][0]) or [0, 9])[1])
    if cd(cells[0]) >= 2 > cd(cells[1]): cells[0], cells[1] = cells[1], cells[0]   # the level-1 slot gets the basic (cooldown < 2) ability
    return '\t'.join([zone, entry, name, fam, '-', '-', stats] + cells)
seen = set(); out = []; nofit = []
tasks = []
for fn in sorted(glob.glob('pet-battle/*_roster.tsv')):
    zone = os.path.basename(fn).replace('_roster.tsv', '')
    for l in open(fn).read().split('\n'):
        if not l or l.startswith(('#', 'include')): continue
        r = l.split('\t')
        if r[0] != 'Y' or r[1] not in meta or r[1] in seen: continue
        seen.add(r[1]); tasks.append((zone, r[1], meta[r[1]]))
if os.environ.get('FIT_EXTRA'):   # creatures that are in no zone roster (collectable companions ...): same fit, own output files (.s/*_extra)
    tasks = [('companion', e, m) for e, m in meta.items() if e not in seen]
SUF = '_extra' if os.environ.get('FIT_EXTRA') else ''
def work(t):
    zone, entry, m = t
    prey = (m[5] == 'Critter' or m[3] == '8') and m[3] != '7'   # a peon or a wounded soldier is a person, not prey
    ents, hits = fb.creature(entry, m[2], int(m[3]), int(m[4]), m[5]); cache = {}; sc = []
    for ids in fb.BUILDS:
        d = fb.dress(ids, ents, cache, prey)
        if d: sc.append((d[0], ids, d[1]))
    sc.sort(key=lambda x: -x[0])
    if not sc: return ('nofit', (zone, entry, m[2], m[5], hits))
    pk = fb.pick_build(sc, entry)
    return ('ok', (zone, entry, m[2], m[5], len(sc), round(pk[0], 2), ' | '.join(s for _, s in pk[2]), ','.join(hits)), kit_row(zone, entry, m[2], m[5], pk[1], pk[2], ents))
if __name__ == '__main__':
    import multiprocessing
    with multiprocessing.get_context('fork').Pool(max(2, (os.cpu_count() or 4) - 1)) as pool:
        kits = []
        for r_ in pool.imap(work, tasks, chunksize=20):
            if r_[0] == 'ok': out.append(r_[1]); kits.append(r_[2])
            else: nofit.append(r_[1])
    os.makedirs('pet-battle/.s', exist_ok=True)
    with open('pet-battle/.s/fit_all%s.tsv' % SUF, 'w') as fh:
        fh.write('zone\tentry\tname\tfamily\tfitting_builds\tfit\tspells\trules\n')
        for o in out: fh.write('\t'.join(map(str, o)) + '\n')
    with open('pet-battle/.s/kits_golden%s.tsv' % SUF, 'w') as fh:
        fh.write('realm\tentry\tname\tfamily\ttheme\tarchetype\tstats\ts1a\ts1b\ts2a\ts2b\ts3a\ts3b\n')
        for k in kits: fh.write(k + '\n')
    with open('pet-battle/nofit_pets%s.txt' % SUF, 'w') as fh:
        fh.write('# pets with NO fitting retail build (every build has an effect no allowed spell can dress)\n')
        for z in nofit: fh.write('%s\t%s\t%s\t%s\t%s\n' % (z[0], z[1], z[2], z[3], ','.join(z[4])))
    print('pets evaluated', len(out) + len(nofit), '| no fitting build', len(nofit))
    c = collections.Counter(o[4] // 100 * 100 for o in out); print('fitting-build count buckets', sorted(c.items()))
    print('fit score quartiles', [sorted(o[5] for o in out)[int(len(out) * q)] for q in (0.1, 0.25, 0.5, 0.75)])
