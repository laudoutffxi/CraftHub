#!/usr/bin/env python3
"""Build crafthub_fish.lua from LandSandBoat's fishing tables (fish, rods, baits,
bait affinity, zones / areas / groups) plus the CatsEyeXI fishing guide route
(bg-wiki CatseyeXI/Fishing_Guide).

usage: python gen_fish.py <LandSandBoat server folder> <out crafthub_fish.lua>
"""
import re, sys, collections

LSB, OUT = sys.argv[1], sys.argv[2]

def rows(table):
    out = []
    pat = re.compile(r"^INSERT INTO `%s` VALUES \((.*)\);" % table)
    for line in open(f'{LSB}/sql/{table}.sql', encoding='utf8'):
        m = pat.match(line)
        if not m:
            continue
        parts, cur, q, esc = [], '', False, False
        for ch in m.group(1):
            if esc:
                cur += ch; esc = False
            elif ch == '\\' and q:
                esc = True
            elif ch == "'":
                q = not q
            elif ch == ',' and not q:
                parts.append(cur); cur = ''
            else:
                cur += ch
        parts.append(cur)
        out.append([p.strip() for p in parts])
    return out

def pretty_zone(z):
    z = z.replace('_', ' ').replace('dOria', "d'Oria").replace('dOraguille', "d'Oraguille").replace(' S]', ' [S]')
    z = z.replace('Ruaun', "Ru'Aun").replace('RuLude', "Ru'Lude").replace('Uggalepih', "Ugg'Alepih")
    return z.replace('Qufim', 'Qufim').replace('  ', ' ')

# ---------------------------------------------------------------- fish
fish = {}
for r in rows('fishing_fish'):
    fid = int(r[0])
    f = dict(id=fid, n=r[1], lv=int(r[2]), rank=int(r[8]), size=int(r[9]), legend=int(r[18]),
             item=int(r[20]), quest_only=int(r[26]), contest=int(r[27]), disabled=int(r[28]),
             keyitem=int(r[23]))
    if f['disabled'] or f['quest_only'] or f['item']:
        continue
    fish[fid] = f

rods = {}
for r in rows('fishing_rod'):
    rods[int(r[0])] = dict(n=r[1], material=int(r[2]), size=int(r[3]), flags=int(r[4]),
                           minrank=int(r[5]), maxrank=int(r[6]), legend=int(r[19]))

baits = {}
for r in rows('fishing_bait'):
    baits[int(r[0])] = dict(n=r[1], lure=int(r[2]) >= 1)

aff = collections.defaultdict(list)
for r in rows('fishing_bait_affinity'):
    b, f, p = int(r[0]), int(r[1]), int(r[2])
    if f in fish and b in baits:
        aff[f].append((p, b))

zones = {int(r[0]): pretty_zone(r[1]) for r in rows('fishing_zone')}
areas = {(int(r[0]), int(r[1])): r[2] for r in rows('fishing_area')}
groups = collections.defaultdict(list)
for r in rows('fishing_group'):
    groups[int(r[0])].append((int(r[1]), int(r[2])))
where = collections.defaultdict(list)
for r in rows('fishing_catch'):
    z, a, g = int(r[0]), int(r[1]), int(r[2])
    for fid, rarity in groups[g]:
        if fid in fish:
            where[fid].append((z, a, rarity))

CITY = set([26, 48, 50, 53, 80, 87, 94] + list(range(230, 251)) + [252, 256, 257])

# ---------------------------------------------------------------- CatsEyeXI route
def fid_of(name):
    for f in fish.values():
        if f['n'].lower() == name.lower():
            return f['id']
    raise SystemExit('fish not found: ' + name)

def bait_of(name):
    alias = {'insect ball': 'Ball of Insect Paste', 'sardine ball': 'Ball of Sardine Paste',
             'trout ball': 'Ball of Trout Paste', 'sliced cod': 'Slice of Cod'}
    name = alias.get(name.lower(), name)
    for bid, b in baits.items():
        if b['n'].lower() == name.lower():
            return bid
    raise SystemExit('bait not found: ' + name)

ROD = {'Halcyon': 17015, 'Composite': 17381, 'Hume': 17014}
# (fish, level on CEXI, rods, baits, where, in town, note)
ROUTE = [
    ('Crayfish', 7, ['Halcyon'], ['Little Worm'], 'West Ronfaure, Knightwell (G-10)', False, ''),
    ('Moat Carp', 11, ['Halcyon'], ['Insect Ball'], 'West Ronfaure, Knightwell (G-10)', False, ''),
    ('Quus', 19, ['Halcyon'], ['Sabiki Rig'], 'Korroloka Tunnel, pool (K-6)', False, ''),
    ('Cheval Salmon', 21, ['Halcyon'], ['Fly Lure'], 'East Ronfaure, river', False, ''),
    ('Nebimonite', 27, ['Halcyon'], ['Shrimp Lure'], 'Sea Serpent Grotto, pool (J-12)', False, ''),
    ('Pipira', 29, ['Halcyon'], ['Minnow'], 'Windurst Waters', True, ''),
    ('Ogre Eel', 35, ['Halcyon'], ['Shrimp Lure'], 'South Gustaberg, East or West Sarutabaruta (sea)', False, ''),
    ('Nosteau Herring', 39, ['Halcyon'], ['Sardine Ball'], 'Qufim Island (H-6)', False, ''),
    ('Coral Butterfly', 40, ['Halcyon'], ['Worm Lure'], 'Kazham', True, ''),
    ('Black Eel', 47, ['Halcyon'], ['Trout Ball'], 'Zeruhn Mines (H-11)', False, ''),
    ('Icefish', 49, ['Halcyon'], ['Sabiki Rig'], 'Beaucedine Glacier, ponds (H-9)', False, ''),
    ('Giant Donko', 50, ['Composite'], ['Frog Lure'], 'Rabao / Eastern Altepa Desert oasis (F-9)', False, ''),
    ('Elshimo Newt', 60, ['Halcyon'], ['Frog Lure'], 'Yhoator Jungle, pool (E-9)', False, ''),
    ('Crescent Fish', 69, ['Halcyon'], ['Fly Lure'], 'East Sarutabaruta, Lake Tepokalipuka (F/G-9)', False, ''),
    ('Zebra Eel', 70, ['Composite'], ['Shrimp Lure'], 'Den of Rancor (E-9)', False, ''),
    ('Bladefish', 71, ['Composite'], ['Meatball', 'Slice of Bluetail'], 'South Gustaberg, East or West Sarutabaruta (sea)', False, ''),
    ('Gavial Fish', 81, ['Composite'], ['Lizard Lure', 'Meatball'], 'North Gustaberg, Drachenfall (F-7/8), via Dangruf Wadi', False, ''),
    ('Bastore Bream', 86, ['Composite'], ['Shrimp Lure'], 'Port Windurst / Port Bastok', True, ''),
    ('Mercanbaligi', 86, ['Composite'], ['Shrimp Lure'], 'Nashmau', True, ''),
    ('Ahtapot', 90, ['Composite'], ['Shrimp Lure'], 'Nashmau', True, ''),
    ('Emperor Fish', 91, ['Composite'], ['Peeled Crayfish', 'Trout Ball'], 'Beaucedine Glacier ponds / Jugner Forest, Lake Mechieume river mouth', False, ''),
    ('Dil', 96, ['Halcyon'], ['Sliced Cod'], 'Talacca Cove', False, 'The line can snap.'),
    ('Black Sole', 96, ['Composite', 'Halcyon', 'Hume'], ['Sinking Minnow', 'Sliced Cod'], 'Port Jeuno / Lower Jeuno / Qufim Island pond (H-7)', True, 'The line can snap.'),
    ('Armored Pisces', 108, ['Composite'], ['Frog Lure', 'Minnow'], 'Oldton Movalpolos', False, 'Can be lost as too small.'),
    ('Gerrothorax', 110, ['Composite'], ['Meatball'], 'Pashhow Marshlands [S]', False, 'Can break the rod: repair it at Woodworking 70 or via The Immortal Lu Shang.'),
]
TESTS = [(10, 'Moat Carp'), (20, 'Cheval Salmon'), (30, 'Giant Catfish'), (40, 'Gugru Tuna'), (50, 'Monke-Onke'),
         (60, 'Bhefhel Marlin'), (70, 'Bladefish'), (80, 'Three-eyed Fish'), (90, 'Gigant Squid'), (100, 'Tiger Shark')]

def lua(s):
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'"

out = ['-- crafthub fishing data. Generated by tools/gen_fish.py from LandSandBoat\'s fishing',
       '-- tables and the CatsEyeXI fishing guide (bg-wiki CatseyeXI/Fishing_Guide).',
       '', 'local F = {}', '']
out.append('-- fish: lv = skill level, size 0 small / 1 large, rank vs a rod\'s max rank,')
out.append('-- baits = { {bait, power} } strongest first, at = { {zone, area, town} }')
out.append('F.fish = {')
for fid in sorted(fish, key=lambda i: (fish[i]['lv'], fish[i]['n'])):
    f = fish[fid]
    bl = sorted(aff[fid], key=lambda pb: (-pb[0], baits[pb[1]]['n']))
    bs = ', '.join('{ %d, %d }' % (b, p) for p, b in bl)
    seen, at = set(), []
    for z, a, rar in sorted(where[fid], key=lambda t: (zones.get(t[0], ''), t[1])):
        key = (z, areas.get((z, a), ''))
        if key in seen:
            continue
        seen.add(key)
        an = areas.get((z, a), '')
        at.append('{ %s, %s, %s }' % (lua(zones.get(z, 'Zone %d' % z)), lua('' if an == 'Whole Zone' else an),
                                     'true' if z in CITY else 'false'))
    out.append(f"    [{fid}] = {{ n = {lua(f['n'])}, lv = {f['lv']}, size = {f['size']}, rank = {f['rank']}" +
               (', legend = true' if f['legend'] else '') + (', ki = true' if f['keyitem'] else '') +
               f", baits = {{ {bs} }}, at = {{ {', '.join(at)} }} }},")
out.append('}')
out.append('')
out.append('F.rods = {')
for rid, r in sorted(rods.items()):
    if r['flags'] & 8:   # goldfish scooping
        continue
    out.append(f"    [{rid}] = {{ n = {lua(r['n'])}, size = {r['size']}, maxrank = {r['maxrank']}, flags = {r['flags']}" +
               (', legend = true' if r['legend'] else '') + ' },')
out.append('}')
out.append('')
out.append('F.baits = {')
for bid, b in sorted(baits.items()):
    out.append(f"    [{bid}] = {{ n = {lua(b['n'])}, lure = {'true' if b['lure'] else 'false'} }},")
out.append('}')
out.append('')
out.append('-- CatsEyeXI skill-up route: aim for fish 9-13 levels above you')
out.append('F.route = {')
for name, lv, rl, bl, wh, town, note in ROUTE:
    fid = fid_of(name)
    out.append(f"    {{ fish = {fid}, lv = {lv}, rods = {{ {', '.join(str(ROD[x]) for x in rl)} }}, " +
               f"baits = {{ {', '.join(str(bait_of(x)) for x in bl)} }}, where = {lua(wh)}, town = {'true' if town else 'false'}" +
               (f', note = {lua(note)}' if note else '') + ' },')
out.append('}')
out.append('')
out.append('-- fish whose level is different on CatsEyeXI')
cexi_lv = {fid_of(n): lv for n, lv, *_ in ROUTE if fish[fid_of(n)]['lv'] != lv}
out.append('F.cexi_levels = { ' + ', '.join(f'[{k}] = {v}' for k, v in cexi_lv.items()) + ' }')
out.append('')
out.append('-- rank tests: trade to Thubu Parohren (Fishing Guild, Port Windurst) from cap - 2')
out.append('F.tests = { ' + ', '.join(f'[{c}] = {lua(n)}' for c, n in TESTS) + ' }')
out.append('')
out.append('return F')
open(OUT, 'w', encoding='utf8').write('\n'.join(out) + '\n')
print(f'{len(fish)} fish, {len(rods)} rods, {len(baits)} baits, {sum(len(v) for v in aff.values())} affinities, '
      f'{len(ROUTE)} route rows, CEXI level changes: {cexi_lv}')
missing = [fish[f]['n'] for f in fish if not where[f]]
print('fish with no fishing spot in LSB:', len(missing))
