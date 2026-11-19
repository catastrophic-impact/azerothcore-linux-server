#!/usr/bin/env python3 -I
"""Turn a run_tests.sh output into pet-battle/ability_blocklist.txt (+ pet-battle/ability_novis.txt): the abilities the project's own tests reject, so the kit pipeline never picks them again.
Usage (repo root): sh pet-battle/run_tests.sh quick > out.txt; python3 -I pet-battle/tests_to_blocklist.py out.txt
  FAIL ability <id> ... / FAIL aura <id> ... / FAIL <name> (<id>): ...   -> that ability (clone ids 5,000,000 + base*10 + family decode to the base); an AURA's PARENT abilities are blocked too
  FAIL species ... uses known-gap ability <id>                           -> that ability
  FAIL <n> abilities with a themed name use a different visual: A vis ..; B vis ..   -> the NAMES go to ability_novis.txt (the generator then leaves their `vis` to the engine's name theme)"""
import sys, re, csv, collections, os
txt = open(sys.argv[1], encoding='utf-8', errors='replace').read()
d = 'pet-battle/retail_data/'
parents = collections.defaultdict(set); tu = collections.defaultdict(list); ef = collections.defaultdict(list)
for t in csv.DictReader(open(d + 'BattlePetAbilityTurn.csv', encoding='utf-8')): tu[t['BattlePetAbilityID']].append(t['ID'])
for e in csv.DictReader(open(d + 'BattlePetAbilityEffect.csv', encoding='utf-8')): ef[e['BattlePetAbilityTurnID']].append(e['AuraBattlePetAbilityID'])
for a, ts in tu.items():
    for t in ts:
        for x in ef[t]:
            if x != '0': parents[x].add(a)
def base(i): i = int(i); return str((i - 5000000) // 10) if i >= 5000000 else str(i)
def up(a, seen=None):   # the ability and every ability that (transitively) applies it as an aura
    seen = seen if seen is not None else set()
    if a in seen: return seen
    seen.add(a)
    for p in parents[a]: up(p, seen)
    return seen
import json
SHIPPED = {x['id'] for x in json.load(open('pet-battle/.s/abil.json')) if x['shipped']}   # abilities already in pb_retail: proven by the shipped game and its tests
hit = collections.OrderedDict()
def add(i, why, new_only=False):   # new_only: block only the NOT-yet-shipped abilities behind the aura (a label problem seen with the composed kits only is not a problem of the proven shipped abilities)
    for a in up(base(i)):
        if new_only and a in SHIPPED: continue
        hit.setdefault(a, why)
for m in re.finditer(r'FAIL ability (\d+) ', txt): add(m.group(1), 'text junk')
for m in re.finditer(r'FAIL aura (\d+)', txt): add(m.group(1), 'aura text/describe')
for m in re.finditer(r'FAIL [^\n(]*\((\d+)\):', txt): add(m.group(1), 'engine conformance (test_abilities)')
for m in re.finditer(r'(?:BUFF THAT HURTS|TURNS TOO HIGH)[^\n]*\[ids (\d+)\]', txt): add(m.group(1), 'status label audit (audit_labels)', new_only=True)
for m in re.finditer(r'uses known-gap ability (\d+)', txt): add(m.group(1), 'known gap')
old = {}
if os.path.exists('pet-battle/ability_blocklist.txt'):
    for l in open('pet-battle/ability_blocklist.txt'):
        if l.strip() and not l.startswith('#'): k, _, w = l.rstrip('\n').partition('\t'); old[k] = w
new = [a for a in hit if a not in old]; old.update({a: hit[a] for a in new})
open('pet-battle/ability_blocklist.txt', 'w').write('# base ability ids rejected by the pet tests (tests_to_blocklist.py); mechanic_templates.py never uses them\n' + ''.join('%s\t%s\n' % kv for kv in sorted(old.items(), key=lambda kv: int(kv[0]))))
nv = set()
if os.path.exists('pet-battle/ability_novis.txt'): nv = {l.strip() for l in open('pet-battle/ability_novis.txt') if l.strip()}
m = re.search(r'abilities with a themed name use a different visual: ([^\n]+)', txt)
if m:
    for it in m.group(1).split(';'): nv.add(re.sub(r'\s+vis \d+ expected \d+\s*$', '', it.strip()))
open('pet-battle/ability_novis.txt', 'w').write('\n'.join(sorted(nv)) + '\n')
print('blocklist: +%d new (total %d) | novis names: %d' % (len(new), len(old), len(nv)))
