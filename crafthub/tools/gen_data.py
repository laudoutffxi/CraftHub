#!/usr/bin/env python3
"""Build crafthub_data.lua from LandSandBoat's synth_recipes.sql + item_basic.sql
and the CatseyeXI crafting guide skill-up path (bg-wiki)."""
import re, sys, collections

LSB = sys.argv[1]
OUT = sys.argv[2]

CRAFTS = ['wood', 'smith', 'gold', 'cloth', 'leather', 'bone', 'alchemy', 'cook']

# ---------------------------------------------------------------- items
names = {}
item_re = re.compile(r"^INSERT INTO `item_basic` VALUES \((\d+),\d+,'((?:[^'\\]|\\.|'')*)','((?:[^'\\]|\\.|'')*)'")
for line in open(f'{LSB}/sql/item_basic.sql', encoding='utf8'):
    m = item_re.match(line)
    if m:
        names[int(m.group(1))] = m.group(3)   # sortname (e.g. maple_lumber)

def pretty(iid):
    n = names.get(iid, f'item {iid}').replace('_', ' ')
    small = {'of', 'the', 'au', 'with', 'a'}
    out = []
    for i, w in enumerate(n.split(' ')):
        if i > 0 and w in small:
            out.append(w)
        else:
            out.append('-'.join(p[:1].upper() + p[1:] for p in w.split('-')))
    return ' '.join(out)

# ---------------------------------------------------------------- recipes
rec_re = re.compile(r"^INSERT INTO `synth_recipes` VALUES \((.*)\);(?:\s*--.*)?\s*$")
recipes = []
for line in open(f'{LSB}/sql/synth_recipes.sql', encoding='utf8'):
    m = rec_re.match(line)
    if not m:
        continue
    body = m.group(1)
    # split on commas outside quotes
    parts, cur, q, esc = [], '', False, False
    for ch in body:
        if esc:
            cur += ch; esc = False
        elif ch == '\\' and q:
            esc = True
        elif ch == "'" :
            q = not q
            cur += ch
        elif ch == ',' and not q:
            parts.append(cur); cur = ''
        else:
            cur += ch
    parts.append(cur)
    v = [p.strip() for p in parts]
    rid, desynth, ki = int(v[0]), int(v[1]), int(v[2])
    levels = [int(x) for x in v[3:11]]
    crystal, hqcrystal = int(v[11]), int(v[12])
    ings = [int(x) for x in v[13:21] if int(x) > 0]
    result, qty = int(v[21]), int(v[25])
    rname = v[29][1:-1] if v[29].startswith("'") else v[29]
    tag = v[30].strip("'") if len(v) > 30 and v[30] != 'NULL' else None
    if desynth or ki or not ings:
        continue
    recipes.append(dict(id=rid, levels=levels, crystal=crystal, ings=ings,
                        result=result, qty=qty, name=rname, tag=tag))

def main_craft(r):
    lv = r['levels']
    best = max(range(8), key=lambda i: (lv[i], -i))
    return best if lv[best] > 0 else None

# ---------------------------------------------------------------- CatseyeXI path
P = {
 'wood': [(5,'Maple Lumber',''),(8,'Ash Lumber',''),(13,'Willow Lumber',''),(19,'Walnut Lumber',''),(22,'Yew Lumber',''),(25,'Elm Lumber',''),(28,'Chestnut Lumber',''),(32,'Chestnut Wand','Can also desynth these for twice the skill-up chances.'),(35,'Oak Lumber',''),(36,'Fairweather Fetish','Can skill up on these instead of Oak Logs.'),(41,'Oak Cudgel','Only uses 1x Lumber. Desynth for double skill-up chances.'),(45,'Rosewood Lumber',''),(51,'Mahogany Lumber',''),(55,'Oak Pole',''),(61,'Ebony Lumber',''),(68,'Mahogany Pole',''),(71,'Ebony Harp',''),(77,'Clothespole',''),(81,'Cabinet',''),(87,'Mithran Fishing Rod',''),(88,'Half Partition',''),(94,'Eight-Sided Pole',''),(97,'Kapor Lumber',''),(100,'Vejovis Wand',''),(104,'Jacaranda Lumber','Jacaranda Logs: Logging in East Ronfaure (S) and Jugner Forest (S).')],
 'smith': [(4,'Bronze Sheet',''),(10,'Bronze Scales',''),(15,'Tin Ingot',''),(20,'Iron Ingot',''),(24,'Debahocho',''),(26,'Iron Scales',''),(30,'Iron Chain',''),(36,'Steel Sheet',''),(41,'Iron Mittens',''),(47,'Mythril Pick',''),(52,'Darksteel Ingot',''),(55,'Darksteel Sheet',''),(59,'Darksteel Scales',''),(62,'Darksteel Bolt Heads',''),(64,'Darksteel Mufflers',''),(66,'Nodowa',''),(70,'Hien',''),(73,'Darksteel Pick',''),(74,'Dark Bronze Ingot',''),(75,'Dark Bronze Sheet',''),(75,'Darksteel Leggings',''),(80,'Katzbalger',''),(83,'Darksteel Nodowa',''),(84,'Thick Mufflers',''),(90,'Adaman Ingot','Adaman Ore: Mining in Grauberg (S) or Pygmytoise in Gustav Tunnel.'),(94,'Adaman Chain',''),(98,'Thokcha Ingot','Thokcha Ore is a custom drop from Sky NMs.'),(99,'Wootz Ingot',''),(104,'Bahadur','')],
 'gold': [(3,'Copper Ingot',''),(7,'Copper Hairpin','8-10 test item.'),(9,'Brass Ingot',''),(15,'Brass Ring',''),(20,'Silver Ingot',''),(27,'Silver Hairpin','28-30 test item.'),(32,'Silver Ring',''),(40,'Mythril Ingot',''),(47,'Mythril Ring','48-50 test item.'),(51,'Sardonyx','Sardonyx etc. with Flame Geode etc. - use the ones from levelling jobs.'),(53,'Gold Ingot',''),(58,'Gold Hairpin',''),(60,'Gold Arrowheads',''),(63,'Platinum Ingot',''),(66,'Mythril Gauntlets','Can desynth.'),(67,'Hydro Patas',''),(70,'Platinum Ring',''),(75,'Jadeite Ring',''),(81,'Zircon','Zircon etc. with Shivite etc. - easy from levelling or meriting.'),(85,'Platinum Bangles',''),(89,'Orichalcum Ingot','Orichalcum Ore: chocobo digging in Bhaflau Thickets / Rolanberry Fields, or mining in Garlaige Citadel (S), Halvung, Ifrit\'s Cauldron.'),(92,'Muscle Belt',''),(95,'Ruby Ring',''),(97,'Koenig Shield',''),(104,'Silver Cassandra','')],
 'cloth': [(3,'Grass Thread','Skill up on this until level 6.'),(4,'Grass Cloth','Skill up on this until level 7.'),(8,'Cape',''),(11,'Cotton Thread','Skill up on this until level 16.'),(12,'Cotton Cloth','Skill up on this until level 17.'),(18,'Cotton Cape',''),(22,'Yagudo Fletchings','Very cheap - worth trying from shortly after Lv.10 even with breaks.'),(22,'Linen Cloth',''),(27,'Linen Robe',''),(31,'Soil Hachimaki',''),(35,'Wool Thread',''),(42,'Bird Fletchings','Very cheap - worth trying from early-mid 30s.'),(43,'Hemp Gorget',''),(45,'Velvet Cloth',''),(51,'Silk Thread',''),(52,'Insect Fletchings','Very cheap - try right after Bird Fletchings.'),(53,'Silk Cloth',''),(55,'Karakul Thread',''),(57,'Karakul Cloth',''),(62,'Green Ribbon',''),(67,'Apkallu Fletchings',''),(72,'Black Chocobo Fletchings',''),(77,'Colibri Fletchings',''),(78,'Rainbow Thread',''),(80,'Rainbow Cloth',''),(82,'Puk Fletchings',''),(84,'Rainbow Headband',''),(88,'Wamoura Silk',''),(90,'Wamoura Cloth',''),(94,'Rainbow Cape',''),(98,'Wyrdweave','Farm Wyrdstrand from King Crawler in Crawlers\' Nest.'),(100,'Swith Cape',''),(103,'Spolia Chapeau','')],
 'leather': [(2,'Sheep Leather',''),(7,'Rabbit Mantle',''),(11,'Solea',''),(17,'Lizard Cesti',''),(21,'Dhalmel Leather',''),(27,'Dhalmel Mantle',''),(31,'Parchment',''),(35,'Ram Leather',''),(43,'Waistbelt',''),(49,'Ram Mantle',''),(53,'Raptor Strap',''),(58,'Raptor Jerkin',''),(61,'Tiger Leather',''),(62,'Hard Leather Ring',''),(69,'Beak Jerkin',''),(71,'Coeurl Leather',''),(75,'Tiger Mantle',''),(80,'Manticore Leather',''),(85,'Coeurl Mantle',''),(89,'Coeurl Jerkin',''),(95,'Tiger Mask',''),(102,'Panther Mask','')],
 'bone': [(4,'Bone Hairpin',''),(10,'Bone Arrowheads',''),(16,'Gelatin',''),(21,'Carapace Powder',''),(25,'Beetle Ring',''),(31,'Beetle Gorget',''),(33,'Beetle Arrowheads',''),(37,'Horn Ring',''),(41,'Bone Knife',''),(43,'Horn Arrowheads',''),(47,'Horn',''),(53,'Scorpion Arrowheads',''),(60,'Scorpion Ring',''),(63,'Demon Arrowheads',''),(64,'Scorpion Mask',''),(68,'Bone Patas',''),(69,'Beast Horn',''),(70,'Demon\'s Ring',''),(78,'Marid Tusk Arrowheads',''),(81,'Marid Ring',''),(87,'Dragon Mask',''),(93,'Carapace Helm',''),(97,'Scorpion Helm',''),(100,'Chronos Tooth','')],
 'alchemy': [(6,'Tsurara',''),(9,'Cornstarch',''),(11,'Poison Dust','Giant Stinger: bees in Wajaom Woodlands.'),(16,'Mercury',''),(18,'Poison Potion',''),(24,'Silent Oil',''),(29,'Yellow Textile Dye',''),(34,'Artificial Lens',''),(40,'Potion',''),(45,'Carbon Fiber',''),(50,'Ether',''),(56,'Cermet Chunk',''),(60,'Hi-Potion',''),(61,'Venom Dust',''),(68,'Venom Potion',''),(71,'Holy Maul',''),(75,'Venom Kukri',''),(78,'Paralyze Potion','Buy Paralysis Dust from Stinknix in Lower Jeuno.'),(81,'Holy Wand',''),(86,'Stun Kukri',''),(87,'Holy Leather',''),(91,'Mamushito',''),(93,'Icarus Wing',''),(97,'Ice Shield',''),(99,'Ephedra Ring',''),(102,'Sun Water','Philosopher\'s Stone: chocobo digging in Western / Eastern Altepa Desert.')],
 'cook': [(3,'Carrot Broth',''),(4,'Hard-boiled Egg',''),(10,'Orange Juice',''),(14,'Tortilla',''),(20,'Selbina Butter',''),(20,'Apple Juice','Buy from Kopopo / Chomo Jinjahl (or Aveline with San d\'Oria conquest) ~10g; craft and vendor.'),(22,'Baked Popoto',''),(29,'Insect Ball',''),(34,'Iron Bread',''),(40,'Ulbuconut Milk',''),(42,'Pie Dough',''),(48,'Apple Pie','Also the 48-50 rank test item.'),(50,'Grape Juice','Make extras - used in later synths at 56 and 86.'),(51,'Orange au Lait',''),(56,'Mulsum',''),(60,'Yagudo Drink','Also the 58-60 rank test item. Purchasable from !chef.'),(61,'Stone Cheese','Cheaper than Yagudo Drink; vendor back to break even.'),(62,'Apple au Lait',''),(68,'Colored Egg',''),(72,'Pear au Lait',''),(79,'Chocomilk',''),(81,'Pamama au Lait',''),(86,'Marron Glace',''),(90,'Fried Popoto','Can be ridden to 101 while vendoring the results.'),(97,'Dawn Mulsum',''),(105,'Dragon Fruit au Lait','')],
}

def norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())

by_name = collections.defaultdict(list)
for r in recipes:
    by_name[norm(r['name'])].append(r)
    by_name[norm(pretty(r['result']))].append(r)

def pick(craft_i, cap, name):
    cands = [r for r in by_name.get(norm(name), []) if r['levels'][craft_i] > 0]
    if not cands:
        # result-name partial match (e.g. "Sardonyx" from a geode synth)
        cands = [r for r in recipes if r['levels'][craft_i] > 0 and norm(name) in norm(r['name'])]
    if not cands:
        return None
    def key(r):
        subs = sum(1 for i, l in enumerate(r['levels']) if l > 0 and i != craft_i)
        kit = any('kit' in names.get(i, '') for i in r['ings'])
        return (kit, abs(r['levels'][craft_i] - cap), subs, len(r['ings']), r['id'])
    return sorted(set(map(lambda r: r['id'], cands)) and cands, key=key)[0]

# ---------------------------------------------------------------- emit
def lua_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"

def rec_lua(r):
    cnt = collections.Counter(r['ings'])
    ings = ','.join(f'{{{i},{n}}}' for i, n in sorted(cnt.items(), key=lambda kv: r['ings'].index(kv[0])))
    lv = ','.join(str(x) for x in r['levels'])
    return f"{{id={r['id']},n={lua_str(r['name'])},c={r['crystal']},lv={{{lv}}},i={{{ings}}},r={r['result']},q={r['qty']}}}"

used_items = set()
lines = ['-- crafthub data. Generated from LandSandBoat sql/synth_recipes.sql + item_basic.sql',
         '-- and the CatseyeXI Crafting Guide (bg-wiki) skill-up path. Do not edit by hand:',
         '-- re-run tools/gen_data.py against your server\'s SQL instead.',
         '-- lv = {Wood, Smith, Gold, Cloth, Leather, Bone, Alchemy, Cook}', '',
         'local D = {}', '', 'D.path = {']
missing = []
for ci, craft in enumerate(CRAFTS):
    lines.append(f'    {craft} = {{')
    for cap, name, note in P[craft]:
        r = pick(ci, cap, name)
        if r is None:
            missing.append((craft, name))
            lines.append(f"        {{cap={cap},name={lua_str(name)},note={lua_str(note)}}},")
        else:
            used_items.update(r['ings']); used_items.add(r['crystal']); used_items.add(r['result'])
            lines.append(f"        {{cap={cap},name={lua_str(name)},note={lua_str(note)},rec={r['id']}}},")
    lines.append('    },')
lines.append('}')
lines.append('')

lines.append('-- every LSB recipe (no desynths / key-item recipes), keyed by id')
lines.append('D.recipes = {')
for r in recipes:
    if main_craft(r) is None:
        continue
    used_items.update(r['ings']); used_items.add(r['crystal']); used_items.add(r['result'])
    lines.append(f'    [{r["id"]}]={rec_lua(r)},')
lines.append('}')
lines.append('')
lines.append('-- item names (fallback when the game resources can\'t be read)')
lines.append('D.items = {')
row = []
for iid in sorted(used_items):
    row.append(f'[{iid}]={lua_str(pretty(iid))}')
    if len(row) == 6:
        lines.append('    ' + ','.join(row) + ','); row = []
if row:
    lines.append('    ' + ','.join(row) + ',')
lines.append('}')
lines.append('')
lines.append('return D')
open(OUT, 'w', encoding='utf8').write('\n'.join(lines) + '\n')
print('recipes', len(recipes), 'items', len(used_items))
print('unmatched path rows:', missing)
