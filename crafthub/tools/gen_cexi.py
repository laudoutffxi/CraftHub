#!/usr/bin/env python3
"""Build crafthub_cexi.lua: CatsEyeXI's custom recipes, from the bg-wiki page
CatsEyeXI Systems/Synthesis. Items are kept by their in-game names (crafthub
looks them up in the game client when it loads); LandSandBoat item ids are added
as a fallback for retail items. Where the wiki shows no quantity, it's 1.

usage: python gen_cexi.py <LandSandBoat server folder> <out crafthub_cexi.lua>
"""
import re, sys

LSB, OUT = sys.argv[1], sys.argv[2]
CRAFTS = ['wood', 'smith', 'gold', 'cloth', 'leather', 'bone', 'alchemy', 'cook']
CRYSTAL = {'fire': 4096, 'ice': 4097, 'wind': 4098, 'earth': 4099, 'lightning': 4100,
           'water': 4101, 'light': 4102, 'dark': 4103}

# (result, yield, crystal, {craft: level}, [(ingredient, qty)], section, note)
R = []
def add(n, crystal, lv, ings, sec, q=1, note=''):
    R.append((n, q, crystal, lv, [(i, 1) if isinstance(i, str) else i for i in ings], sec, note))

M = 'Custom materials'
add('Aether Key', 'wind', {'alchemy': 60}, ['Blank Key', 'Aether Dust'], M, 3, 'Aether Dust: Domain Invasion or Ventures.')
add('Prismatic Key', 'wind', {'alchemy': 90}, ['Blank Key', 'Prismatic Cluster'], M, 3, 'Prismatic Cluster: Synergy Furnace.')
add('Fable Cloth', 'earth', {'cloth': 105}, [('Fable Thread', 3)], M, note='Upgrade material for Dragonslaying.')
add('Dragon Powder', 'wind', {'bone': 94}, [('Dragon Bone', 4)], M)
add('Dragon Essence', 'light', {'alchemy': 92}, ['Refined Elementium', ('Dragon Powder', 2)], M, note='Upgrade material for final-tier Venture battles.')
add('Elementium Ingot', 'fire', {'gold': 94}, ['Fire Ore', 'Ice Ore', 'Wind Ore', 'Earth Ore', 'Lightning Ore', 'Water Ore', 'Light Ore', 'Dark Ore'], M, note='HQ gives Refined Elementium.')
add('Refined Elementium', 'fire', {'gold': 95}, [('Elementium Ingot', 4)], M)
add('Animated Lumber', 'wind', {'wood': 94}, ['Bloodwood Log', 'Refined Elementium'], M)
add('Embersteel Rivet', 'wind', {'smith': 94}, ['Embersteel Ingot'], M)
add('Elementium Stud', 'wind', {'smith': 94}, ['Refined Elementium'], M)
add('Elementium Thread', 'earth', {'cloth': 94}, ['Fable Thread', 'Refined Elementium'], M)
add('Ochre Dye', 'water', {'alchemy': 102}, [('Dragon Powder', 2), 'Fine Ochre'], M, note='Fine Ochre: T2 Wyrms (Dragonslaying).')
add('Goblin Powder', 'light', {'alchemy': 94}, ['Goblin Stone'], M, note='Goblin Stone: Goblin daily quests.')

F = 'Custom food'
add('Dragon Fruit Pie', 'fire', {'cook': 85}, [('Pie Dough', 2), 'Bird Egg', 'Honey', ('Dragon Fruit', 4)], F)
add('Rolanberry Cheesecake', 'ice', {'cook': 85}, [('Yogurt', 4), ('Kitron', 2), 'Wizard Cookie', 'Rolanberry'], F)

E = 'Custom equipment'
add('Swith Cape', 'earth', {'cloth': 100}, ['Sparkstrand', ('Wyrdweave', 2)], E)
add('Urja Trousers', 'earth', {'leather': 100}, [('Buffalo Leather', 2), ('Squamous Hide', 2)], E)
add('Visionary Obi', 'earth', {'cloth': 105}, ['Arachne Obi', ('Elementium Thread', 3), ('Sparkstrand', 4)], E)
add('Companion Belt', 'fire', {'gold': 105}, ['Life Belt', ('Embersteel Rivet', 3), ('Ph. Gold Ingot', 4)], E)
add('Elementium Torque', 'light', {'alchemy': 85}, ['Torque +1', 'Refined Elementium'], E)
add('Evader Earring', 'fire', {'gold': 100}, [('P. Brass Ingot', 2)], E)
add('Saida Ring', 'light', {'alchemy': 99}, [('Holy Water', 2), 'Hallowed Water', 'Orichalcum Ring'], E)
add('Areion Boots', 'earth', {'cloth': 106}, ['Strider Boots', 'Serica Cloth', ('Elementium Thread', 3)], E, note='Trotter Boots can be used instead of Strider Boots. Serica Cloth: Brjota (Dragonslaying).')
add("Harbinger's Gaiters", 'earth', {'cloth': 108}, ["Herald's Gaiters", ('Embersteel Rivet', 2), ('Elementium Thread', 2), 'Ochre Dye'], E, note="Crier's Gaiters can be used instead of Herald's Gaiters.")
for res, gem, base in [('Flame Earring', 'Carnelian', 'Triumph Earring'), ('Thunder Earring', 'Fulmenite', 'Adroit Earring'),
                       ('Soil Earring', 'Heliodor', 'Robust Earring'), ('Breeze Earring', 'Aventurine', 'Nimble Earring'),
                       ('Snow Earring', 'Clarite', 'Omn. Earring'), ('Aqua Earring', 'Larimar', 'Cmn. Earring'),
                       ('Light Earring', 'Selenite', 'Heavens Earring'), ('Darkness Earring', 'Tenebrite', 'Hades Earring')]:
    add(res, 'light', {'gold': 108}, [gem, ('Goblin Powder', 2), base], E)

D_ = 'Domain Invasion'
add('Voluspa Mantle', 'ice', {'leather': 114, 'cloth': 60}, ['Akaso Thread', 'Cehuetzi Pelt', 'Prism Cape'], D_)
add("Norn's Grip", 'wind', {'leather': 105, 'alchemy': 60}, ['Cerberus Hide', 'Cehuetzi Pelt', 'Bugard Strap +1'], D_)
add('Ydalir Ring', 'wind', {'bone': 110}, ['Khimaira Horn', 'Cehuetzi Claw', 'Behemoth Ring +1'], D_)
add('Yetshila', 'wind', {'cloth': 114, 'bone': 60}, ['Animal Glue', 'Waktza Rostrum', 'Waktza Crest'], D_)
add("Titan's Grip", 'wind', {'leather': 105, 'gold': 60}, ['Khimaira Tail', 'Yggdreant Root', 'Platinum Grip +1'], D_)
add('Valar Bow', 'light', {'wood': 105, 'alchemy': 60}, ['Khimaira Mane', 'Yggdreant Bole', 'Goblin Powder', "Eurytos' Bow"], D_)
add('Hjaldr Ring', 'wind', {'bone': 109}, ['Matamata Shell', 'Gabbrath Horn', "Merman's Ring"], D_)
add("Longbeard's Grip", 'wind', {'leather': 111}, ['Raaz Leather', 'Rockfin Fin', 'Raptor Strap +1'], D_)
add("Conjurer's Crook", 'light', {'wood': 110, 'gold': 60}, ['Tanzanite Jewel', ('Urunday Lumber', 2), 'Rockfin Tooth', 'Iridal Staff'], D_, note='Iridal Staff: Synergy Furnace.')
add('Reflexive Grip', 'wind', {'leather': 93, 'cloth': 32}, ['Raaz Leather', 'Bztavian Wing', 'Omni Grip'], D_, note='Omni Grip: Synergy Furnace.')
add('Starfall', 'light', {'gold': 113, 'alchemy': 60}, ['Urunday Lumber', 'Bztavian Stinger', 'Darksteel Maul +1', 'Goblin Powder'], D_)
add('Stormlord Shawl', 'light', {'leather': 93, 'cloth': 44, 'alchemy': 44}, ['Elementium Thread', 'Amphisbaena Hide', 'Amemet Mantle +1', 'Goblin Powder'], D_)
add('Chunin Ring', 'light', {'bone': 93, 'alchemy': 44}, ['Battosai Fang', 'Wivre Ring +1', 'Goblin Powder'], D_)
add('Askalaphos', 'light', {'bone': 93, 'smith': 44, 'alchemy': 44}, ['Titanium Ingot', 'Tortuga Shell', 'Acheron Shield +1', 'Goblin Powder'], D_)
add('Dux Visor', 'wind', {'bone': 95}, ['Runic Scales', 'Titanium Ingot', 'Matamata Shell', 'Elementium Stud'], D_, note='RUN JSE.')
add('Dux Scale Mail', 'wind', {'bone': 100}, [('Runic Scales', 2), ('Titanium Ingot', 2), ('Matamata Shell', 2), 'Elementium Stud', 'Squamous Hide'], D_, note='RUN JSE.')
add('Dux Fng. Gnt.', 'wind', {'bone': 96}, ['Runic Scales', ('Titanium Ingot', 2), ('Matamata Shell', 2), 'Elementium Stud'], D_, note='RUN JSE.')
add('Dux Cuisses', 'wind', {'bone': 97}, [('Runic Scales', 2), ('Titanium Ingot', 2), 'Matamata Shell', 'Elementium Stud'], D_, note='RUN JSE.')
add('Dux Greaves', 'wind', {'bone': 94}, ['Runic Scales', ('Titanium Ingot', 2), 'Matamata Shell', 'Elementium Stud'], D_, note='RUN JSE.')
add('Tempest Bonnet', 'earth', {'cloth': 95}, ['Geoweave', 'Fable Cloth', 'Akaso Thread', 'Elementium Thread'], D_, note='GEO JSE.')
add('Tempest Jacket', 'earth', {'cloth': 95}, [('Geoweave', 2), ('Fable Cloth', 2), ('Akaso Thread', 2), 'Elementium Thread', 'Gold Thread'], D_, note='GEO JSE.')
add('Tempest Wrists', 'earth', {'cloth': 96}, ['Geoweave', ('Fable Cloth', 2), ('Akaso Thread', 2), 'Elementium Thread'], D_, note='GEO JSE.')
add('Tempest Kecks', 'earth', {'cloth': 97}, [('Geoweave', 2), ('Fable Cloth', 2), 'Akaso Thread', 'Elementium Thread'], D_, note='GEO JSE.')
add('Tempest Gamashes', 'earth', {'cloth': 94}, ['Geoweave', ('Fable Cloth', 2), 'Akaso Thread', 'Elementium Thread'], D_, note='GEO JSE.')
add('Blurred Crossbow', 'fire', {'smith': 105, 'wood': 50}, ['Adaman Ingot', 'Wolfram Steel', ('Kapor Lumber', 2), ('Spectral Ore', 2), 'Rpt. Crossbow'], D_, note='Spectral Ore: Fomor Kings.')
add('Blurred Claws', 'fire', {'smith': 105, 'bone': 50}, ['Adaman Ingot', 'Wolfram Steel', ('Mammoth Tusk', 2), ('Spectral Ore', 2), 'Dragon Claws'], D_, note='Spectral Ore: Fomor Kings.')
add('Blurred Rod', 'fire', {'smith': 105, 'gold': 50}, ['Adaman Ingot', 'Wolfram Steel', ('Thokcha Ingot', 2), ('Spectral Ore', 2), 'Scepter'], D_, note='Spectral Ore: Fomor Kings.')

G = 'Guild NMs'
add('Exalted Bow', 'wind', {'wood': 106}, ['Akaso Thread', 'Akaso Cloth', ('Exalted Lumber', 2)], G)
add('Exalted C.bow', 'wind', {'wood': 106}, ['Akaso Thread', 'Bismuth Ingot', 'Exalted Lumber'], G)
add('Exalted Spear', 'wind', {'wood': 106}, ['Akaso Thread', 'Beryllium Ingot', 'Exalted Lumber'], G)
add('Exalted Staff', 'wind', {'wood': 106}, [('Exalted Lumber', 2)], G)
add('Bismuth Bullet', 'fire', {'alchemy': 94, 'smith': 43}, ['Firesand', 'Bismuth Ingot'], G, q=33, note='HQ makes 99.')
add('Beryllium Kris', 'fire', {'smith': 106}, ['Bismuth Ingot', 'Beryllium Ingot', 'Northern Pearl'], G)
add('Beryllium Sword', 'fire', {'smith': 106}, ['Urunday Lumber', 'Raaz Leather', ('Beryllium Ingot', 3)], G)
add('Beryllium Pick', 'fire', {'smith': 106}, ['Urunday Lumber', 'Beryllium Ingot'], G)
add('Beryllium Mace', 'fire', {'smith': 106}, [('Beryllium Ingot', 3)], G)
for res, tear, ring in [('Carb. Ring', 'Carbutear', 'Light Ring'), ('Fenrir Ring', 'Fenritear', 'Dark Ring'),
                        ('Garuda Ring', 'Garutear', 'Breeze Ring'), ('Ifrit Ring', 'Ifritear', 'Flame Ring'),
                        ('Levia. Ring', 'Leviatear', 'Aqua Ring'), ('Ramuh Ring', 'Ramutear', 'Thunder Ring'),
                        ('Shiva Ring', 'Shivatear', 'Snow Ring'), ('Titan Ring', 'Titatear', 'Soil Ring')]:
    add(res, 'light', {'gold': 114}, [tear, 'Rhodium Ring', ring, 'Goblin Powder'], G)
add('Hepatizon Rapier', 'fire', {'gold': 106}, ['Ocl. Ingot', 'Iolite', ('Hepatizon Ingot', 2)], G)
add('Hep. Baghnakhs', 'fire', {'gold': 106}, ['Raaz Leather', 'Hepatizon Ingot', ('Maliya. Coral Orb', 3)], G)
add('Verse Strap', 'wind', {'leather': 106}, [('Behemoth Pelt', 2)], G)
add('Gatta Strap', 'wind', {'leather': 106}, ['Behemoth Hide', 'Behemoth Pelt'], G)
add('Yacuruna Ring', 'wind', {'bone': 106, 'alchemy': 40}, ['Yggdreant Root', ('Maliya. Coral', 2)], G)
add('Maliya Sickle', 'wind', {'bone': 106, 'smith': 50, 'leather': 50}, ['Urunday Lumber', 'Raaz Leather', 'Maliya. Coral', 'Beryllium Ingot'], G)
add('Marzipan Cake', 'fire', {'cook': 105}, ['Selbina Butter', 'Maple Sugar', 'Imperial Flour', 'Apkallu Egg', 'Marzipan'], G)
add("Sage's Hat", 'earth', {'cloth': 95, 'smith': 40, 'leather': 40}, ['Southern Pearl', "Siren's Hair", ('Wyrdweave', 2), 'Northern Pearl', 'Crimsonweave'], G)
add("Sage's Coat", 'earth', {'cloth': 95, 'smith': 40, 'leather': 40}, ['Gold Chain', 'Behem. Leather', 'Eltoro Leather', ('Wyrdweave', 2), "Sif's Macrame", ('Crimsonweave', 2)], G)
add("Sage's Cuffs", 'earth', {'cloth': 96, 'leather': 40}, ['Eltoro Leather', ('Wyrdweave', 2), "Sif's Macrame", 'Crimsonweave'], G)
add("Sage's Pants", 'earth', {'cloth': 97, 'leather': 40}, ['Behem. Leather', 'Eltoro Leather', ('Wyrdweave', 2), "Sif's Macrame", ('Crimsonweave', 2)], G)
add("Sage's Sabots", 'earth', {'cloth': 94, 'leather': 40}, ['Behem. Leather', 'Eltoro Leather', 'Wyrdweave', "Sif's Macrame", 'Crimsonweave'], G)

# Retail recipes whose craft levels CatsEyeXI changed (ingredients unchanged).
OVERRIDES = [('Bakery Platter', {'cook': 90, 'smith': 21}), ('Banquet Set', {'alchemy': 99, 'gold': 32, 'cloth': 12}),
             ('Purifying Ewer', {'alchemy': 99, 'smith': 40, 'gold': 30}), ('Mock Hare', {'alchemy': 99, 'cook': 40})]

# ---------------------------------------------------------------- LSB ids (fallback)
def norm(s):
    return re.sub(r'[^a-z0-9+]', '', s.lower())
ids = {}
item_re = re.compile(r"^INSERT INTO `item_basic` VALUES \((\d+),\d+,'((?:[^'\\]|\\.)*)','((?:[^'\\]|\\.)*)'")
for line in open(f'{LSB}/sql/item_basic.sql', encoding='utf8'):
    m = item_re.match(line)
    if m:
        iid = int(m.group(1))
        for nm in (m.group(3), m.group(2)):
            ids.setdefault(norm(nm.replace('_', ' ')), iid)

def lsb_id(name):
    return ids.get(norm(name))

def lua(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"

out = ['-- crafthub: CatsEyeXI custom recipes, from bg-wiki "CatsEyeXI Systems/Synthesis".',
       '-- Generated by tools/gen_cexi.py. Items are by in-game name: crafthub finds their ids',
       '-- in the game client when it loads; `ids` holds LandSandBoat ids for retail items as a',
       '-- fallback. Where the wiki shows no quantity, it is 1.',
       '', 'local X = {}', '', 'X.recipes = {']
names = set()
for n, q, crystal, lv, ings, sec, note in R:
    total = sum(qty for _, qty in ings)
    assert total <= 8, (n, total)
    lvs = ', '.join(f'{k} = {v}' for k, v in lv.items())
    il = ', '.join('{ %s, %d }' % (lua(i), qty) for i, qty in ings)
    out.append(f'    {{ n = {lua(n)}, q = {q}, c = {CRYSTAL[crystal]}, lv = {{ {lvs} }}, i = {{ {il} }}, sec = {lua(sec)}' +
               (f', note = {lua(note)}' if note else '') + ' },')
    names.add(n); names.update(i for i, _ in ings)
out.append('}')
out.append('')
out.append('-- retail recipes with different craft levels on CatsEyeXI (same ingredients)')
out.append('X.overrides = {')
for n, lv in OVERRIDES:
    rid = lsb_id(n)
    assert rid, n
    lvs = ', '.join(f'{k} = {v}' for k, v in lv.items())
    out.append(f'    {{ n = {lua(n)}, r = {rid}, lv = {{ {lvs} }} }},')
    names.add(n)
out.append('}')
out.append('')
out.append('X.ids = {')
found = 0
for nm in sorted(names):
    iid = lsb_id(nm)
    if iid:
        found += 1
        out.append(f'    [{lua(nm)}] = {iid},')
out.append('}')
out.append('')
out.append('return X')
open(OUT, 'w', encoding='utf8').write('\n'.join(out) + '\n')
print(f'{len(R)} recipes, {len(OVERRIDES)} level changes, {len(names)} item names, {found} with LSB ids')
print('not in LSB (found in game at load):', ', '.join(sorted(n for n in names if not lsb_id(n))))
