#!/usr/bin/env python3 -I
"""Coverage matrix for the Outland/Northrend scale-up: creature THEMES (regex on name, creature type) vs the ability pool (shipped + candidates).
Usage: python3 -I pet-battle/coverage_matrix.py <census.tsv> <abil.json> <cand.json> > pet-battle/coverage_matrix.tsv
census.tsv = map,entry,name,type,family,rank,minlevel,maxlevel,spawns (acore_world, maps 530/571); abil.json = filt output; cand.json = candidate ability ids (not yet used)."""
import sys, json, re, collections
cen = [l.rstrip('\n').split('\t') for l in open(sys.argv[1])]
ab = json.load(open(sys.argv[2])); cand = set(json.load(open(sys.argv[3])))
pool = [a for a in ab if a['top'] and (a['shipped'] or a['id'] in cand)]
TN = {1: 'Beast', 2: 'Dragonkin', 3: 'Demon', 4: 'Elemental', 5: 'Giant', 6: 'Undead', 7: 'Humanoid', 9: 'Mechanical'}
JUNK = r'dummy|target|training|practice|trigger|stabled|riding|\bmount\b|parked|wants|conversing'
# theme: (creature-name regex, ability name/description regex)
T = [
 ('fel/demon',      r'illidari|gan.arg|mo.arg|terrorguard|infernal|felhound|wrathguard|fel |felguard|satyr|doomguard|warbringer|voidwalker|imp\b|legion|eredar|nethermancer|hound',            r'fel\b|demon|chaos|infern|burning|curse|corrupt|shadow'),
 ('arcane/mana',    r'sunfury|mana|arcane|ethereum|nether|spellweaver|warmage|arcanist|mage\b|wyrm|manabeast|surger|scryer|ethereal|consortium',                                         r'arcane|mana|magic|spark|nether|energy|beam'),
 ('void/shadow',    r'void|shadow|cultist|necromancer|cabal|warlock|summoner|dark|twilight|harbinger|nightmare',                                                                          r'void|shadow|dark|curse|drain|haunt|fear|soul'),
 ('frost/ice',      r'frost|ice|icy|frozen|vrykul|vargul|kvaldir|winter|snow|glacier|yeti|wooly|rime|coldarra|iron giant',                                                                  r'frost|ice|icy|chill|freez|cold|snow|blizzard|winter'),
 ('fire/magma',     r'flame|fire|magma|forgelord|deathforge|molten|burning|ember|infernal|ashmaw|cinder',                                                                                r'fire|flame|burn|magma|ember|inferno|lava|scorch|blaz|meteor|ignit'),
 ('nature/spore',   r'lasher|ancient|treant|thornvine|spore|fungal|root|creeper|sapling|bloom|vine|green|bog|marsh|tender|whitebark|feral',                                              r'nature|spore|thorn|vine|bloom|leaf|root|poison|toxic|photosynth|fungus|plant'),
 ('storm/lightning',r'storm|lightning|tempest|electromental|thunder|stormforged|cyclone|zephyr|wind',                                                                                    r'lightning|storm|thunder|shock|zap|jolt|static|wind|gust|tempest'),
 ('earth/stone',    r'rager|rumbler|boulder|sundered|crumbler|golem|stone|rock|earth|mountain|gronn|rumble|ironspine|mineral',                                                           r'earth|stone|rock|boulder|quake|crush|sand|mud|avalanche|pebble|crystal'),
 ('holy/light',     r'argent|crusader|aldor|naaru|draenei|sentinel|oracle|priest|paladin|holy|light|silver|valiance|valiant|blessed|shattered sun',                                       r'holy|light|bless|heal|radiant|divine|sacred|prayer|restor'),
 ('scourge undead', r'ghoul|geist|risen|skeleton|skeletal|val.kyr|revenant|abomination|gargoyle|forgotten|scourge|reanimated|corpse|plague|zombie|death|necrolord|crypt|anub|nerub|conclave',    r'plague|disease|bone|raise|corpse|undead|death|rot|decay|haunt|infect|grave|blight|zombie'),
 ('web/poison',     r'spider|nerub|anub|crypt fiend|widow|recluse|venom|sting|scorpid|scorpion|wasp|serpent|viper|basilisk|snake|naga',                                                    r'web|poison|venom|sting|toxic|spit|swarm|snare|acid|toxin'),
 ('bite/pack',      r'wolf|worg|hound|jackal|fox|hyena|cat\b|lynx|panther|saber|tiger|lion|bear|ursa|boar|raptor|devilsaur|springpaw|stalker|stag',                                       r'bite|claw|rend|pounce|howl|rake|maul|fang|savage|tear|slash|feral|frenzy|pounce'),
 ('charge/stomp',   r'elekk|talbuk|clefthoof|rhino|mammoth|shoveltusk|kodo|\bram\b|bull|horse|calf|wooly|hippo|ox\b|behemoth|gronn',                                                       r'charge|stomp|trample|gore|ram\b|horn|hoof|smash|bash|thunderclap|rush|buck'),
 ('flying/talon',   r'gryphon|windroc|kaliri|hawkstrider|hippogryph|eagle|dragonhawk|owl|bat\b|sporebat|nether ray|moth|bird|hawk|roc\b|raven|harpy|wyvern|wind serpent|skettis|arakkoa',      r'wing|talon|peck|swoop|dive|flap|feather|gale|buffet|flock|screech|caw|breath'),
 ('worm/burrow',    r'jormungar|worm|crawler|ravager|burrower|larva|devourer|mawer|grub|silithid|crab|crustacean|scarab|beetle|bug',                                                       r'burrow|dig|tunnel|acid|chitin|pincer|snap|claw|crawl|devour|swarm|shell|bore'),
 ('dragonkin',      r'drake|proto|whelp|dragon|wyrm|netherwing|drakonid|dreadwing|nether drake|serpent',                                                                                  r'breath|dragon|scale|wing|flame|frost|drake|tail|roar'),
 ('troll/voodoo',   r'drakkari|troll|witch doctor|shadow hunter|zandalari|amani|gundrak|darkspear',                                                                                      r'voodoo|hex|curse|spirit|totem|heal|shadow|poison'),
 ('orc/ogre melee', r'warrior|grunt|brute|raider|ogre|gronn|bonechewer|bloodmaul|dragonmaw|boulderfist|warsong|onslaught|footman|berserker|knight|defender|guard|champion|soldier|peon|laborer', r'strike|slash|smash|cleave|punch|bash|crush|stab|whirl|charge|slam|shield|rage|fury'),
 ('ranged/hunter',  r'hunter|scout|ranger|marksman|archer|sharpshooter|trapper|sniper|crossbow|rifle',                                                                                    r'shot|arrow|bow|fire\b|rifle|volley|aim|trap|bolt|snipe|gun|cannon|rapid'),
 ('shaman/healer',  r'shaman|healer|oracle|priest|druid|apothecary|physician|medic|tender|cleric',                                                                                       r'heal|restor|renew|mend|regenerat|cure|totem|inspire|bless|wrap|life'),
 ('rogue/stealth',  r'rogue|assassin|bandit|thief|cutthroat|stalker|shadowstalker|prowler|ninja|blade\b|dagger',                                                                           r'stab|stealth|shadow|backstab|ambush|dodge|vanish|puncture|blind|smoke|evasi|bleed'),
 ('mechanical',     r'machine|bomber|tank|mechagnome|shredder|steam|rocket|cannon|robot|mech|gizmo|clockwork|drill|golem|sentry|harvest|scavenge|collector|fizzcrank|flying machine',          r'rocket|bomb|gear|drill|laser|turret|shield|repair|overcharge|cannon|zap|gatling|steam|tesla|missile|bolt'),
 ('murloc/aquatic', r'murloc|gorloc|naga|coilskar|mariner|fish|reef|tide|crab|turtle|snapper|ray\b|shark|eel|whale|walrus|seal|coilfang|serpentshrine',                                      r'water|tide|bubble|wave|splash|tentacle|fin|gill|ink|drown|bite|whirlpool|squeeze'),
]
def cat(n, t):
    if re.search(JUNK, n.lower()): return None
    return TN.get(int(t), '?')
out = []; tot = collections.Counter(); hit = set()
for realm, mp in (('Outland', '530'), ('Northrend', '571')):
    cs = [x for x in cen if x[0] == mp and cat(x[2], x[3])]
    for th, crx, arx in T:
        cm = [x for x in cs if re.search(crx, x[2].lower())]
        for x in cm: hit.add((mp, x[1]))
        am = [a for a in pool if re.search(arx, (a['name'] + ' ' + re.sub(r'\[[^\]]*\]|\|c\w{8}|\|r', ' ', a['desc'])).lower())]
        sh = sum(a['shipped'] for a in am); ca = len(am) - sh
        out.append((realm, th, len(cm), sh, ca, len(am), len(cm) / max(1, len(am))))
print('realm\ttheme\tcreatures\tshipped_abil\tcandidate_abil\ttotal_abil\tcreatures_per_ability')
for r in out: print('%s\t%s\t%d\t%d\t%d\t%d\t%.1f' % r)
for realm, mp in (('Outland', '530'), ('Northrend', '571')):
    cs = [x for x in cen if x[0] == mp and cat(x[2], x[3])]
    left = [x for x in cs if (mp, x[1]) not in hit]
    print('# %s: %d eligible creature kinds, %d match no theme (they use the type default)' % (realm, len(cs), len(left)), file=sys.stderr)
