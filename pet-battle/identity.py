"""Creature IDENTITY -> weighted spell sources (user 2026-11-18: spells must make sense for what the creature IS; no random class, no family-only rules).
profile(name, ctype, cf, fam, own) -> list of (prefix, weight, scope): prefix matches a spell source ('pet:Wolf', 'class:Rogue', 'class:Rogue/Assassination', 'race:Human'), longest prefix wins;
scope 'any' | 'util' (non-damage slots only) | 'basic' (damage slots: plain attacks only).
expand(entries, rng) gives classes a seeded SPEC mix (pure or a hybrid of two) so no two rogues are the same. KEYWORDS carry the earned borrowings (diseased -> poison, spirit -> arcane, frost -> frost ...).
Everything here is rules + data; creatures the rules cannot place confidently are reported (UNSURE) for the evaluator / the user."""
import re
ANIMAL_FAM = ('Beast', 'Critter', 'Flying', 'Aquatic', 'Dragonkin')
SPECS = {'Warrior': ['Arms', 'Fury', 'Protection'], 'Rogue': ['Assassination', 'Combat', 'Subtlety'], 'Mage': ['Arcane', 'Fire', 'Frost'], 'Priest': ['Discipline', 'Holy', 'Shadow Magic'],
         'Paladin': ['Holy', 'Protection', 'Retribution'], 'Druid': ['Balance', 'Feral Combat', 'Restoration'], 'Shaman': ['Elemental Combat', 'Enhancement', 'Restoration'],
         'Warlock': ['Affliction', 'Demonology', 'Destruction'], 'Hunter': ['Beast Mastery', 'Marksmanship', 'Survival'], 'DeathKnight': ['Blood', 'Frost', 'Unholy']}
# (regex on the lower-cased name, [(prefix, weight, scope)], note)   -- applied to humanoid-like creatures; every matching rule adds its entries
CLASS_RULES = [
 (r'mage\b|wizard|apprentice|conjur|magus|sorcer|arcanist|warmage|spellweaver|magister|enchanter|enchantress|illusionist|magician', [('class:Mage', 3.0, 'any')]),
 (r'geomancer|shaman|witch doctor|seer|mystic|tidehunter|stormcaller|hexer|spiritwalker', [('class:Shaman', 3.0, 'any')]),
 (r'warlock|imp\b|imps\b|familiar|voidwalker|felhunter|succubus|felguard|infernal|summoner|necromancer|cultist|cabal|shadow ?council|felsworn|demon', [('class:Warlock', 3.0, 'any')]),
 (r'priest|cleric|acolyte|oracle|monk|healer|chaplain|vicar', [('class:Priest', 3.0, 'any')]),
 (r'paladin|crusader|templar|justicar|argent|champion of the light', [('class:Paladin', 3.0, 'any')]),
 (r'druid|treant|keeper of the grove|sentinel of the grove', [('class:Druid', 3.0, 'any')]),
 (r'hunter|ranger|archer|scout|trapper|outrunner|tracker|marksman|sniper|rifleman|riflemen|sharpshooter|gunner|musketeer|beastmaster|handler|stalker', [('class:Hunter', 2.5, 'any'), ('class:Rogue', 0.8, 'any')]),
 (r'thief|rogue|bandit|cutpurse|assassin|smuggler|pirate|pickpocket|cutthroat|prowler|syndicate|defias|burglar|outlaw|saboteur|ambusher|footpad|brigand', [('class:Rogue', 3.0, 'any'), ('class:Warrior', 0.6, 'any')]),
 (r'guard|soldier|footman|knight|deputy|militia|defender|marshal|captain|sergeant|lieutenant|enforcer|legionnaire|warden|protector|vanguard|shieldbearer|stormwind|ironforge', [('class:Warrior/Protection', 3.5, 'any'), ('class:Warrior', 1.8, 'any'), ('class:Paladin/Protection', 0.5, 'any')]),
 (r'thug|brute|grunt|warrior|berserker|gladiator|fighter|marauder|raider|slayer|champion|bruiser|ruffian|goon|mercenary|warband|warlord|chieftain|slave', [('class:Warrior', 3.0, 'any'), ('class:Rogue', 0.8, 'any')]),
 (r'miner|worker|laborer|peon|digger|foreman|taskmaster|vermin|runt|workman|scavenger|looter|grubber', [('class:Warrior', 2.2, 'any'), ('class:Rogue', 1.6, 'any')]),
 (r'murloc|naga|sea|tide|tidal|siren|mermaid|merman|merloc|gilnean?', [('class:Shaman/Restoration', 2.2, 'any'), ('class:Shaman/Elemental Combat', 1.4, 'any'), ('class:Rogue/Combat', 0.9, 'any'), ('pet:Crab', 0.8, 'any')]),
 (r'gnoll|riverpaw|mongrel|hyena', [('class:Warrior', 2.0, 'any'), ('class:Hunter', 1.2, 'any'), ('class:Rogue', 1.0, 'any')]),
]
# earned borrowings, any creature (animals included): (regex, entries)
KEYWORDS = [
 (r'diseased|plague|rot|mangy|sickly|infected|rabid|festering|putrid|venom|poison|toxic|fetid', [('class:Rogue/Assassination', 1.8, 'any'), ('class:DeathKnight/Unholy', 1.2, 'any'), ('class:Warlock/Affliction', 0.8, 'any')]),
 (r'spirit|ghost|wraith|specter|spectre|spectral|phantom|banshee|astral|ethereal', [('class:Druid/Balance', 2.2, 'any'), ('class:Priest/Shadow Magic', 1.4, 'any'), ('class:Mage/Arcane', 1.6, 'any'), ('race:Blood Elf', 0.8, 'util')]),
 (r'frost|ice|icy|snow|winter|glacier|frozen|chill|rime|cold|polar|arctic|glacial|tundra|yeti', [('class:Mage/Frost', 2.2, 'any'), ('class:DeathKnight/Frost', 1.6, 'any'), ('class:Shaman/Elemental Combat', 1.1, 'any')]),
 (r'fire|flame|lava|magma|molten|ember|burning|blaze|cinder|inferno|scorch', [('class:Mage/Fire', 2.2, 'any'), ('class:Warlock/Destruction', 1.5, 'any'), ('class:Shaman/Elemental Combat', 1.3, 'any')]),
 (r'storm|thunder|lightning|tempest|cyclone|dragonhawk|serpent hawk|wind|gale', [('class:Shaman/Elemental Combat', 2.0, 'any'), ('class:Druid/Balance', 1.2, 'any')]),
 (r'water|river|stream|marsh|swamp|coast|tide|ocean|sea|lake', [('class:Shaman/Restoration', 1.6, 'any')]),
 (r'holy|light|sun|silver|angel|radiant|blessed|argent', [('class:Priest/Holy', 1.6, 'any'), ('class:Paladin/Holy', 1.2, 'any'), ('race:Draenei', 1.0, 'util')]),
 (r'dark|shadow(?!forge)|night|dusk|void|umbral|twilight|gloom', [('class:Priest/Shadow Magic', 1.5, 'any'), ('class:Warlock', 1.2, 'any'), ('class:DeathKnight', 0.8, 'any')]),
 (r'stone|rock|earth|golem|boulder|mountain|granite|crag|iron|stoneskin', [('race:Dwarven', 1.6, 'util'), ('class:Shaman/Enhancement', 1.0, 'any'), ('class:Warrior/Protection', 1.0, 'util')]),
 (r'ghoul|skelet|zombie|forsaken|risen|undead|scourge|corpse|revenant|geist|cadaver|plagued|abomination|banshee|lich|death', [('class:DeathKnight', 2.2, 'any'), ('race:Undead', 1.6, 'util'), ('class:Warlock/Affliction', 1.0, 'any')]),
 (r'wild|feral|savage|ravenous|dire|alpha', [('class:Druid/Feral Combat', 1.4, 'any')]),
 (r'\bhuman\b|stormwind|alliance|defias|westfall|gilnean', [('race:Human', 1.2, 'util')]),
 (r'orc\b|grunt|horde|blackrock|warsong', [('race:Orc', 1.2, 'util')]),
 (r'troll|witch doctor|amani|zandalari|darkspear', [('race:Troll', 1.2, 'util')]),
 (r'tauren|taurajo|bloodhoof', [('race:Tauren', 1.2, 'util')]),
 (r'dwarf|dwarven|ironforge|dark iron|wildhammer', [('race:Dwarven', 1.6, 'util')]),
 (r'gnome|gnomish|mechano|tinker', [('race:Gnome', 1.4, 'util')]),
 (r'night ?elf|sentinel|kaldorei', [('race:Night Elf', 1.4, 'util')]),
 (r'blood ?elf|sunfury|quel|magister|sin.dorei', [('race:Blood Elf', 1.6, 'util')]),
 (r'draenei|naaru|vindicator|exodar', [('race:Draenei', 1.6, 'util')]),
]
ANIMAL_BASE = {   # an animal: its own family's signatures first, generic hunter-pet moves, feral druid melee, a few warrior shouts
    'own': 4.0, 'generic': 2.0, 'feral': 2.0, 'shouts': 0.7, 'others': 0.05}
def is_animal(fam, own, ctype):
    if ctype == 7 and own is None: return False   # a humanoid typed 'Aquatic'/'Flying' by family (Kvaldir, mariners) still fights like a person
    return fam in ANIMAL_FAM or own is not None or ctype in (1, 8)
def profile(name, ctype, cf, fam, own, famname=None):
    n = name.lower(); ent = []; hit = []
    animal = is_animal(fam, own, ctype)
    humanoid_like = ctype in (7, 5, 3, 4, 6, 10) or (fam == 'Humanoid' and not animal)
    if animal:
        if own: ent.append((own, ANIMAL_BASE['own'], 'any'))
        ent += [('pet:generic', ANIMAL_BASE['generic'], 'any'), ('class:Druid/Feral Combat', ANIMAL_BASE['feral'], 'any'), ('class:Warrior/Fury', ANIMAL_BASE['shouts'], 'util'), ('class:Warrior/Arms', 0.4, 'util')]
        if fam != 'Critter' and ctype != 8: ent.append(('pet:', ANIMAL_BASE['others'], 'any'))   # another family's signature: a rare surprise (never for small critters)
        if fam == 'Critter' or ctype == 8:   # small things: plain attacks, a little support (Evasion, Rejuvenation, Fortitude), never breaths / spits / big spells
            ent = [(p, w, ('basic' if (p.startswith('pet:') or p.startswith('class:Druid/Feral')) else sc)) for p, w, sc in ent]
            ent += [('spell:Evasion', 1.6, 'util'), ('spell:Rejuvenation', 1.3, 'util'), ('spell:Regrowth', 0.9, 'util'), ('spell:Power Word: Fortitude', 1.0, 'util'), ('spell:Mark of the Wild', 1.0, 'util'), ('spell:Prowl', 0.6, 'util')]
    typed = False
    if ctype == 6:   # Undead: death-knight flavoured by default (Flesh Eater, Bone Chewer, Mindless Ghoul carry no keyword); no plain-fighter fallback
        ent += [('class:DeathKnight', 2.6, 'any'), ('pet:Ghoul', 1.6, 'any')]; hit.append('type:undead'); typed = True
    elif ctype == 4:   # Elemental: shaman/balance flavoured, never a plain warrior
        ent += [('class:Shaman/Elemental Combat', 2.6, 'any'), ('class:Shaman/Enhancement', 1.8, 'any'), ('class:Druid/Balance', 1.0, 'any')]; hit.append('type:elemental'); typed = True
    elif ctype == 9:   # Mechanical: guns and shocks
        ent += [('class:Hunter/Marksmanship', 2.4, 'any'), ('class:Shaman/Elemental Combat', 1.6, 'any'), ('class:Warrior', 0.8, 'any')]; hit.append('type:mechanical'); typed = True
    if humanoid_like or not animal:
        for rx, es in CLASS_RULES:
            if re.search(r'\b(?:' + rx + ')', n): ent += es; hit.append(rx.split('|')[0])
        if not hit:   # nothing in the name says what it does: a plain fighter
            ent += [('class:Warrior', 1.8, 'any'), ('class:Rogue', 1.0, 'any'), ('class:Warrior/Protection', 0.6, 'any')]; hit.append('default')
    for rx, es in KEYWORDS:
        if re.search(r'\b(?:' + rx + ')', n): ent += es; hit.append('kw:' + rx.split('|')[0])
    if animal or ctype == 9: ent.append(('spell:Hex', 0.0, 'any'))   # Hex = shaman witch-doctor magic: never on beasts or machines
    return ent, hit
def expand(entries, rng):
    """give every class (with no spec named) a spec mix: one pure spec (65%) or a hybrid of two (35%); the chosen spec(s) are boosted, the others kept at a low weight so slots can still be filled"""
    out = []; classes = []
    for p, w, sc in entries:
        if p.startswith('class:') and '/' not in p: classes.append((p, w, sc))
        else: out.append((p, w, sc))
    for p, w, sc in classes:
        cn = p.split(':')[1]; specs = SPECS.get(cn)
        if not specs: out.append((p, w, sc)); continue
        k = 2 if rng.random() < 0.35 else 1; pick = rng.sample(specs, k)
        for sp in specs: out.append(('%s/%s' % (p, sp), w * (1.6 if sp in pick else 0.45), sc))
    return out
def weight(entries, src, tier, g_is_dmg, name=None):
    """weight of one spell source for this creature + slot kind (0 = not allowed)"""
    best = None
    for p, w, sc in entries:
        if p.startswith('spell:'):   # a single named spell (finer than a class line)
            if name == p[6:] and (best is None or len(p) + 1000 > len(best[0])): best = (p + '\x00' * 1000, w, sc)
            continue
        if src == p or src.startswith(p) and (p.endswith(':') or p.endswith('/') or src[len(p)] in '/'):
            if best is None or len(p) > len(best[0]): best = (p, w, sc)
    if best is None: return 0.0
    p, w, sc = best
    if sc == 'util' and g_is_dmg: return 0.0
    if sc == 'basic' and g_is_dmg and tier != 'basic': return 0.0
    return w
