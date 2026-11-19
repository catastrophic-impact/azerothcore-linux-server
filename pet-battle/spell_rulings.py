#!/usr/bin/env python3 -I
"""Builds pet-battle/spell_effect_map.tsv: which golden-list effect tokens each 3.3.5 spell (class, hunter/warlock/DK pet family, racial) can dress.
Basis per spell: 'data' = read from Spell.dbc effects/auras, 'tooltip' = read from the game's tooltip text, 'ruling' = decided with the user (2026-11-19) from what the spell does in a battle.
RULINGS win over data. A token is an effect-label token of golden_effects_player.tsv (damage, dot, heal, hot, drain, stun, noswap, speedup, speeddown, dmgup, dmgdown, vuln, defense, dodge, block, untargetable, damageshield, cleanse, critup, accdown, interrupt, aoe, multihit, rebirth, stunchance).
Run from repo root: python3 -I pet-battle/spell_rulings.py"""
import csv, collections, importlib.util, sys

sys.argv = ['x']
spec = importlib.util.spec_from_file_location('sig', 'pet-battle/spell_signatures.py')
sig = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sig)

DROP = set()
RULE = {}


def r(tokens, names):
    for n in [x.strip() for x in names.split(';') if x.strip()]:
        RULE[n] = tokens.split()


def drop(names):
    DROP.update(x.strip() for x in names.split(';') if x.strip())


# --- Part B (34 unresolved) + Part A corrections, answered by the user 2026-11-19
r('dot', 'Pestilence; Death and Decay')                      # damage over time on the whole enemy team
r('critup', 'Deathchill; Combustion; Cold Blood; Tidal Force; Divine Favor')
r('stun', 'Hungering Cold; Mind Control; Psychic Horror; Enslave Demon')
r('aoe', 'Starfall; Fire Nova; Bladestorm')
r('aoe dot', 'Volley; Immolation Aura; Rain of Fire; Mind Sear; Blizzard')
r('dmgdown', 'Demoralizing Roar; Demoralizing Shout; Mind Soothe; Curse of Idiocy; Dismantle; Curse of Weakness')
r('speedup', "Nature's Swiftness; Sprint; Dash; Shadowstep; Aspect of the Cheetah; Blazing Speed")
r('accdown', 'Scorpid Sting; Dust Cloud')
r('dodge', 'Deterrence')
r('dmgup', 'Focus Magic; Amplify Magic; Berserk; Metamorphosis; Savage Roar; Aspect of the Beast; Aspect of the Hawk; Aspect of the Dragonhawk; Kill Command; Arcane Power; Rapid Fire; '
           'Slice and Dice; Blade Flurry; Icy Veins; Power Infusion; Elemental Mastery; Unholy Presence; Seal of Righteousness; Seal of Command; Seal of Corruption; Seal of Vengeance; '
           'Blessing of Might; Hunger For Blood; Battle Shout; Commanding Shout; Horn of Winter; Trueshot Aura; Demonic Frenzy; Furious Howl; Call of the Wild; Rabid; Adrenaline Rush; '
           'Death Wish; Recklessness; Bestial Wrath; The Beast Within; Avenging Wrath; Tiger\'s Fury; Berserker Rage; Inner Fire; Hysteria')
r('defense', 'Pain Suppression; Feint; Fade; Soothing Kiss; Vigilance; Mana Shield; Sacred Shield; Blessing of Sanctuary; Shamanistic Rage; Roar of Sacrifice; Divine Protection; Barkskin; '
             'Frost Armor; Ice Armor; Mage Armor; Molten Armor; Demon Armor; Fire Ward; Frost Ward; Shadow Ward; Ice Barrier; Power Word: Shield; Shield Wall; Survival Instincts; Icebound Fortitude; Last Stand')
r('block', 'Shield Block; Holy Shield')
r('damageshield', 'Retaliation; Spell Reflection; Lightning Shield; Thorns; Nature\'s Grasp')
r('hot', 'Enraged Regeneration; Cannibalize; Lick Your Wounds; Carrion Feeder; Second Wind; Renew; Rejuvenation; Lifebloom; Regrowth; Wild Growth')
r('heal', 'Blood Pact; Tranquility; Prayer of Mending; Vampiric Embrace; Seal of Light; Earth Shield')
r('rebirth', 'Heart of the Phoenix')
r('damage', 'Slam; Holy Shock; Penance')
r('damage vuln', 'Mangle')
r('damage conditional', 'Execute')
r('drain', 'Bloodthirst; Drain Life')
r('vuln', "Hunter's Mark; Sunder Armor; Expose Armor; Faerie Fire; Faerie Fire (Feral)")
r('cleanse', 'Heroic Fury; Bullheaded; Stoneform; Escape Artist; Every Man for Himself; Will of the Forsaken; Cleanse; Purify; Dispel Magic; Cure Poison; Abolish Poison; Remove Curse; Cure Toxins; Cleanse Spirit; Purge')
r('untargetable', 'Disengage; Feign Death; Phase Shift; Warp; Vanish; Invisibility; Blink; Dispersion; Divine Shield; Ice Block; Evasion; Cloak of Shadows; Hand of Protection')
r('damage dot', 'Explosive Shot; Shiv')
r('multihit', 'Killing Spree; Arcane Missiles')
r('damage stun', 'Charge; Demon Charge')
r('damage noswap', 'Feral Charge - Bear; Swoop')
r('damage interrupt', 'Kick; Pummel; Mind Freeze; Silence; Strangulate; Shield Bash; Spell Lock; Counterspell; Wind Shear')
r('stunchance', 'Seal of Justice')
# --- dropped (no retail effect, forms, threat taunts, mana/stat/resource, travel, user rulings)
drop("Death Pact; Lichborne; Presence of Mind; Concentration Aura; Divine Sacrifice; Find Treasure; Bear Form; Tree of Life; Mark of Blood; Flamethrower; Activate MG Turret; Feral Charge; Shadow Dance; Fear Ward; "
     "Greater Blessing of Might; Greater Blessing of Kings; Greater Blessing of Sanctuary; Greater Blessing of Wisdom; Crusader Aura; Hand of Sacrifice; Taunt; Growl; Dark Command; Hand of Reckoning; "
     "Challenging Roar; Challenging Shout; Challenging Howl; Cower; Righteous Defense; Distracting Shot; Misdirection; Anguish; Suffering; Torment; Intercept; Intervene; Aspect of the Wild; "
     "Arcane Intellect; Arcane Brilliance; Dalaran Brilliance; Blessing of Kings; Blessing of Wisdom; Divine Spirit; Power Word: Fortitude; Prayer of Fortitude; Prayer of Spirit; Fel Intelligence; "
     "Shadow Protection; Prayer of Shadow Protection; Fire Resistance Aura; Frost Resistance Aura; Shadow Resistance Aura; Devotion Aura; Retribution Aura; Hymn of Hope; Evocation; Innervate; Viper Sting; "
     "Mana Burn; Drain Mana; Water Shield; Curse of Tongues; Life Tap; Dark Pact; Inner Focus; Divine Illumination; Blood Tap; Rune Tap; Enrage; Bloodrage; Premeditation")


# --- extra tokens for the 11 effects no spell could express (2026-11-19): spells appended to the map even when not mapped otherwise
EXTRA = {
    'survive': 'Guardian Spirit; Last Stand; Heart of the Phoenix',                       # endure at 1 health until the end of next round
    'sleepdelay': 'Hibernate; Polymorph; Hex; Fear; Psychic Scream; Mind Soothe',          # drowsy, falls asleep next round unless hurt
    'delayedhit': 'Pyroblast; Chaos Bolt; Unstable Affliction; Starfall',                  # bolt that strikes after N rounds
    'meteor': 'Inferno; Rain of Fire; Meteor',                                             # big delayed strike
    'heal': 'Rejuvenation; Regrowth; Nourish; Swiftmend; Healing Touch; Mend Pet; Lick Your Wounds; Lifebloom',   # small prey needs more than one heal
    'accup': 'Trueshot Aura; Aspect of the Hawk; Aspect of the Dragonhawk; Eagle Eye',     # team hit chance up
    'avoidswap': 'Feign Death; Vanish; Disengage; Phase Shift; Warp; Blink',               # avoid the attack, then swap out
}


def tokens_from_features(f):
    m = {'D': 'damage', 'P': 'dot', 'H': 'heal', 'HOT': 'hot', 'L': 'drain', 'S': 'stun', 'SL': 'stun', 'R': 'noswap', 'SD': 'speeddown', 'SU': 'speedup', 'DU': 'dmgup', 'DD': 'dmgdown',
         'VU': 'vuln', 'DEF': 'defense', 'DG': 'dodge', 'SH': 'damageshield', 'CL': 'cleanse', 'IM': 'untargetable', 'CR': 'critup', 'A': 'aoe', 'AD': 'accdown', 'BL': 'block', 'MH': 'multihit'}
    return [m[x] for x in sorted(f) if x in m]


if __name__ == '__main__':
    tri = {}
    for l in open('pet-battle/spell_triage.tsv').read().split('\n')[1:]:
        f = l.split('\t')
        if len(f) > 5: tri[f[3]] = f[5]
    rows = list(csv.reader(open('pet-battle/spell_pairing.tsv'), delimiter='\t'))[1:]
    seen = set()
    out = []
    unresolved = []
    for row in rows:
        n = row[2]
        key = (row[0], n) if row[0].startswith(('pet:', 'race:')) else n
        if key in seen: continue
        seen.add(key)
        sid = int(row[1])
        if n in DROP: continue
        if n in RULE:
            out.append((row[0], sid, n, ' '.join(RULE[n]), 'ruling', sig.cooldown_ms(sid)))
            continue
        if row[0].startswith('class:') and tri.get(n) in ('EXCL', 'DROP', 'PARK'): continue
        f = sig.features(sid) or set()
        tk = tokens_from_features(f)
        basis = 'tooltip' if sig.TXT.get(sid) else 'data'
        if tk:
            out.append((row[0], sid, n, ' '.join(tk), basis, sig.cooldown_ms(sid)))
        else:
            unresolved.append((n, sig.tooltip(sid)[:100]))
    byname = {}
    for i, o in enumerate(out): byname.setdefault(o[2], []).append(i)
    pairing = {}
    for row in rows:
        pairing.setdefault(row[2], row)
    for tok, names in EXTRA.items():
        for n in [x.strip() for x in names.split(';') if x.strip()]:
            if n in byname:
                for i in byname[n]:
                    o = list(out[i]); o[3] = o[3] + ' ' + tok; out[i] = tuple(o)
            elif n in pairing:
                row = pairing[n]; out.append((row[0], int(row[1]), n, tok, 'ruling', sig.cooldown_ms(int(row[1])))); byname[n] = [len(out) - 1]
    for row in rows:                                                         # twostep: a long cast = the 'load, then fire' feeling
        n = row[2]
        if n in byname and row[8] and int(row[8] or 0) >= 2500:
            for i in byname[n]:
                if 'damage' in out[i][3].split() and 'twostep' not in out[i][3].split():
                    o = list(out[i]); o[3] += ' twostep'; out[i] = tuple(o)
    with open('pet-battle/spell_effect_map.tsv', 'w') as fh:
        fh.write('source\tspell_id\tname\teffect_tokens\tbasis\tcooldown_ms\n')
        for o in out: fh.write('\t'.join(map(str, o)) + '\n')
    c = collections.Counter(o[4] for o in out)
    print('mapped spells:', len(out), dict(c), '| unresolved:', len(unresolved))
    for u in unresolved: print('  ?', u[0], '|', u[1])
