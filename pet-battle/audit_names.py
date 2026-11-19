#!/usr/bin/env python3 -I
"""NAME AUDIT (static, no battles): do the spell NAMES the kits show make sense on those pets and for what the ability does?   python3 -I pet-battle/audit_names.py  -> pet-battle/name_audit.tsv + summary
Checks per kit slot (pet, shown spell, effect):
  FAMILY   the spell exists only as one hunter-pet family's signature (Swoop, Lava Breath, Pin ...) but the creature is another family
  ANIMAL   the spell name contains an animal (Wolverine, Scorpid, Monkey ...) that the creature name / family does not
  COVER    the effect has parts (buff/debuff riders) that the spell itself does not express (Frenzied Regeneration = heal over time, shown for heal + team hit/crit)
Aliases (name_aliases.tsv) are applied first, so this audits what the player really reads."""
import sys, re, collections, importlib.util
sys.argv = ['x']
spec = importlib.util.spec_from_file_location('fb', 'pet-battle/fit_builds.py'); fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
alias_rows = [l.rstrip('\n').split('\t') for l in open('pet-battle/name_aliases.tsv') if not l.startswith('#') and l.count('\t') >= 3]
glab = {l.split('\t')[2]: l.split('\t')[0] for l in list(open('pet-battle/golden_effects.tsv'))[1:]}
def alias(sn, ename, bid):
    lab = glab.get(bid[1:], '')
    for sp, keep, eff, new, *_ in alias_rows:
        if sp == sn and not (keep and re.search(keep, ename, re.I)) and not (eff and not re.search(eff, lab)): return new
    return sn
meta = {}
for fn in ('pet-battle/family_assign.tsv', 'pet-battle/shipped_assign.tsv'):
    for l in open(fn).read().split('\n')[1:]:
        f = l.split('\t')
        if len(f) > 5: meta[f[1]] = f
ANIMALS = 'wolverine scorpid monkey raptor cobra serpent spider wolf boar bear cat hawk eagle viper rhino turtle bat owl crab gorilla hyena chimera devilsaur mongoose wasp moth silithid ravager hound dragonhawk'.split()
OWN = {'wolverine': 'critter', 'monkey': 'critter', 'mongoose': 'critter'}
HUNTERISH = re.compile(r'hunter|ranger|archer|scout|trapper|outrunner|marksman|sniper|rifleman|handler|stalker|sharpshooter|gunner|beastmaster|tracker|collect-a-tron|cannon|core', re.I)   # hunter spells on hunters are right
rows = []; cnt = collections.Counter()
for l in open('pet-battle/kits_prototype.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) < 13: continue
    entry, name, fam = f[1], f[2], f[3]; cf = int(meta[entry][4]); own = fb.FAMS.get(cf)
    for c in f[7:13]:
        b, a, g, sn0, sid, mode, icon = c.split('|'); sn = alias(sn0, name, b)
        flags = []
        if sn0 in fb.PET_ONLY and sn0 not in fb.OPEN_MOVES and ('pet:' + (own or '')) not in fb.PET_ONLY[sn0] and not any(p == 'pet:Ghoul' for p in fb.PET_ONLY[sn0]): flags.append('FAMILY(%s vs %s)' % ('/'.join(sorted(x[4:] for x in fb.PET_ONLY[sn0])), own or '-'))
        for an in ANIMALS:
            if re.search(r'\b' + an + r's?\b', sn, re.I) and not re.search(an, name, re.I) and not HUNTERISH.search(name) and (own or '').lower() != an and fam.lower() != OWN.get(an, '#'):
                flags.append('ANIMAL(%s)' % an); break
        tk = set(fb.EFF[b[1:]][1]) - {'damage'}; st = fb.SPELLTOK.get(sn0, set())
        miss = [t for t in tk if t not in st and t not in ('heal',)]
        if miss and sn == sn0 and 'heal' in tk and tk - st - {'heal'}: flags.append('COVER(effect also: %s)' % ' '.join(sorted(tk - st - {'heal'})))
        if flags:
            for fl in flags: cnt[(sn, fl.split('(')[0])] += 1
            rows.append((sn, ';'.join(flags), name, fam, fb.EFF[b[1:]][0]))
with open('pet-battle/name_audit.tsv', 'w') as fh:
    fh.write('shown_name\tflags\tpet\tfamily\teffect\n')
    for r in sorted(rows): fh.write('\t'.join(r) + '\n')
print(len(rows), 'flagged slots;', len({r[0] for r in rows}), 'distinct names')
for (n, k), c in cnt.most_common(25): print('%4d %-8s %s' % (c, k, n))
