#!/usr/bin/env python3 -I
"""Assign a PET FAMILY (Humanoid/Dragonkin/Flying/Undead/Critter/Magic/Elemental/Beast/Aquatic/Mechanical) to every wild creature kind by THEME, not only by creature type, so the family
strength triangle stays meaningful (a roster that is 44% Humanoid makes Undead abilities always best). First matching rule wins; reason column says which.
Usage (repo root): python3 -I pet-battle/family_rules.py <census.tsv> > pet-battle/family_assign.tsv
census.tsv = map, entry, name, creature_type, creature_family, rank, minlevel, maxlevel, spawns (acore_world maps 530/571)."""
import sys, re, collections
JUNK = r'dummy|target|training|practice|trigger|stabled|riding|\bmount\b|parked|wants|conversing|\bbunny\b|visual|invisible|\[ph\]'
FLY_F = {7, 24, 26, 27, 30, 33, 34, 37, 44}           # carrion bird, bat, bird of prey, wind serpent, dragonhawk, sporebat, nether ray, moth, wasp
AQ_F = {8, 21}                                         # crab, turtle
R = [  # (type set or None, name regex, family, reason)   evaluated top to bottom
 ({9}, r'', 'Mechanical', 'type mechanical'),
 ({2}, r'', 'Dragonkin', 'type dragonkin'),
 ({6}, r'', 'Undead', 'type undead'),
 ({4}, r'arcane|mana|surger|spellweaver|nether|ethereal|aspect|wisp|spark|flavor', 'Magic', 'arcane elemental'),
 ({4}, r'', 'Elemental', 'type elemental'),
 ({3}, r'gan.arg|engineer|tinkerer|forgelord|smith|terrorguard|mo.arg|infernal', 'Mechanical', 'demon constructs/forgeworks'),
 ({3}, r'hound|stalker|felhunter|wolf|boar|hog|ravager|beast', 'Beast', 'demon beast'),
 ({3}, r'', 'Magic', 'type demon'),
 ({8}, r'wisp', 'Magic', 'wisp'), ({8}, r'crab|fish|turtle|frog|toad|biletoad', 'Aquatic', 'water critter'),
 ({8}, r'horse|sheep|deer|fawn|stag|elk|cat\b|boar|bear', 'Beast', 'large critter'),
 ({8}, r'', 'Critter', 'type critter'),
 ({1}, r'', None, 'beast: by creature family'),                                   # resolved below
 ({5}, r'', 'Elemental', 'type giant'),
 ({0, 7}, r'murloc|gorloc|naga|coilskar|mariner|kvaldir|merman|mermaid|siltfin|wrathscale|bloodscale|blacksilt|serpentshrine|sea giant|tidecaller', 'Aquatic', 'water humanoid'),
 ({0, 7}, r'mage\b|warmage|arcanist|sorcer|spellweaver|magister|nethermancer|sunfury|ethereum|scryer|enchant|conjur|wizard|magus|illusion|arcane|mana|archmage|cabalist|spellbinder|sage', 'Magic', 'caster'),
 ({0, 7}, r'warlock|summoner|fel |felsworn|dark ?(?:cleric|adept|priest)|shadow ?(?:priest|mage|council)|cabal|twilight|legion', 'Magic', 'fel/shadow caster'),
 ({0, 7}, r'necro|cultist|plague|reanimat|crypt|geist|acolyte|death|scourge|forsaken|apothecary|cult\b|ebon blade|undercity', 'Undead', 'death-themed'),
 ({0, 7}, r'shaman|\bstorm ?(?:caller|shaman|weaver)|wind ?caller|elementalist|earthen|thunder ?caller|seer\b|ancestral|spirit ?(?:walker|talker)|tempest', 'Elemental', 'shaman'),
 ({0, 7}, r'hunter|scout|ranger|marksman|trapper|sniper|beastmaster|handler|tamer|stalker|wolf ?rider|skinner|huntsman|archer|falconer|stable', 'Beast', 'hunter/handler'),
 ({0, 7}, r'peon|laborer|refugee|villager|peasant|worker|farmer|child|orphan|miner|servant|prisoner|captive|injured|wounded|slave|bonded|trainee|initiate|neophyte|apprentice|novice|recruit|conscript', 'Critter', 'non-combatant/trainee'),
 ({0, 7}, r'engineer|tinker|mechanic|goblin|gnome|machinist|gearsmith|artificer', 'Mechanical', 'engineer'),
 ({0, 7}, r'', 'Humanoid', 'default humanoid'),
]
def beast(name, cf):
    n = name.lower()
    if cf in FLY_F or re.search(r'gryphon|windroc|kaliri|hawk|owl|bat\b|eagle|raven|vulture|hippogryph|roc\b|drake|wyvern|wind serpent|crow|swoop|\bmoth|teromoth|wasp|bee\b|sporebat|nether ?ray|flayer|harpy', n): return 'Flying', 'flying beast'
    if cf in AQ_F or re.search(r'crab|turtle|shark|walrus|seal\b|fish|eel|snapper|croc|basilisk|jormungar|lobster|clam|worm\b|serpent|snake|ray\b|whale|penguin|gorloc', n): return 'Aquatic', 'water/serpent beast'
    if re.search(r'rat\b|rabbit|squirrel|chicken|toad|frog|mouse|roach|beetle|scarab|cricket|fly\b|bug\b|hatchling|whelp|pup\b|calf|kit\b|cub\b|fawn|spider ?ling|spiderling|crawler|scavenger|sprite', n): return 'Critter', 'small beast'
    return 'Beast', 'beast'
rows = [l.rstrip('\n').split('\t') for l in open(sys.argv[1])]
print('realm\tentry\tname\tctype\tcfamily\tpet_family\treason')
for m, e, name, t, cf, rk, lo, hi, n in rows:
    t, cf = int(t), int(cf)
    if re.search(JUNK, name.lower()): continue
    fam = why = None
    for ts, rx, f, why in R:
        if (ts is None or t in ts) and re.search(rx, name.lower()):
            fam = f; break
    if fam is None: fam, why = beast(name, cf)
    print('%s\t%s\t%s\t%d\t%d\t%s\t%s' % ({'530': 'Outland', '571': 'Northrend'}.get(m, m), e, name, t, cf, fam, why))
