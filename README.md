# crafthub

An Ashita v4 addon for FFXI that reads your craft skills and shows **the best synth to skill up on right now** in every craft, using the CatseyeXI crafting guide's skill-up path and the full LandSandBoat recipe list. A Fishing tab does the same for fishing: the best fish for your skill, with the rod, bait and where to catch it.

Look and feel: VanaCore style, with a glass dashboard finish based on Yuna's YunaUI.

## What it shows

- **Overview**: all eight crafts at once. Each card shows your level and rank, progress to the rank cap, and the best synth right now. Capped crafts and open rank tests are flagged.
- **Best synth**: a detailed view for one craft.
  - The recommended recipe, with success chance, skill-up chance, expected skill per synth and roughly how many synths each level takes.
  - The crystal and ingredients, with how many of each you're holding and how many synths you can make now.
  - Any sub-craft requirements, checked against your own levels.
  - Your rank, the rank-up test item when you're at or near a cap, and where the guild is.
  - The CatseyeXI skill-up path for that craft, with the recommended row highlighted. Click any row to pin it.
  - Any other recipe that beats the guide's best pick at your level (by 5% or more) is added to the path in level order, and can be the best synth. The top recipe is tagged **BEST** (several if they score the same) and the added ones just under it are tagged **GOOD**. Once you out-level one, it drops off the path and is only in Also good.
  - "Also good right now": other recipes on your server that skill up well at your level. Guild kits have their own list.
  - **All**: every recipe for that craft on your server, guild kits included, plus CatsEyeXI's custom recipes when CEXI is picked. It's sorted by level, opens at your level, and scrolls. Recipes are tagged BEST, CEXI, KIT or GUIDE, and any row can be pinned.
- **Recipes**: every recipe from 11 levels below your skill in the chosen craft to 11 above. The search box finds any recipe in any craft. Guild kits are tagged KIT, and path recipes are tagged GUIDE.
- **Guild kits**: the guild-vendor kits from Lv 5 to 50 are listed for each craft with live odds. With the "Guild kits (to 50)" toggle on, a kit becomes the best synth whenever it beats the guide's pick. Kit prices rise steeply with level, so turn the toggle off if you'd rather not buy them. When the best or pinned synth can also be made the other way (normal recipe or guild kit), both versions are shown, each with its ingredients, odds and its own Pin button.
- **Fishing**: the best fish to skill up on, picked from the CatseyeXI fishing route.
  - The fish's skill-up chance, expected skill per catch, roughly how many catches each level takes, and the chance it gets away because your skill is too low.
  - The rod and bait to use, with how many you're holding, and where to fish.
  - Warnings when the fish can escape as too big for the rod, or when a large rod can lose a small fish.
  - Two lists: **CEXI route** (the guide's fish from 1 to 110) and **All fish** (every fish with a fishing spot that skills you up now, best first). Click a row to pin it.
  - Your rank, the rank-up test fish, and skill gained this session.
- **Mini window** (`/craft mini`): a small strip with your focused craft, its level and the best synth, for while you're crafting.
- **Item icons**: every recipe, ingredient and crystal shows its in-game icon. Icons are read straight from your own FFXI client through Ashita, so nothing is downloaded or bundled. If an icon can't be loaded, a coloured dot is shown instead.
- **Session tracking**: skill gained and synth count this session. Your exact decimal (e.g. 34.6) is shown once you've had a level-up message, and is remembered between sessions.

## How "best" is worked out

The maths is taken from LandSandBoat's `synthutils.cpp`, so it matches what the server rolls:

- **Success chance:** 95% at or under your level; 95 − 5×d for recipes 1–3 above you; 80 − 10×(d−3) beyond that. It is rolled per craft involved, so sub-crafts count. Recipes 15 or more above you can't be attempted.
- **Skill-up chance** (modern system):
  - Recipes 2+ above you: d × (3 − ln(1.2 + skill/10)) / 5.
  - Otherwise: (3 − ln(1.2 + skill/10)) / (6 − d).
  - Skill-ups stop once you're 11 or more levels above a recipe.
  - A break can still skill up (at half the chance) when the recipe is 1–5 levels above you.
- **Skill-up size:** LSB's 0.1–0.5 weight table. Above level 60, skill-ups are always 0.1.

Each recipe gets a score from its expected skill per synth, weighted by its success rate. The mode decides how much breaks count against it:

| Mode | Behaviour |
|---|---|
| **Safe** | Avoids breaks. Typically picks recipes about 1–2 above you. |
| **Balanced** | The default. Typically 2–3 above you. |
| **Fast** | Accepts more breaks for bigger, more frequent skill-ups. |

## How the best fish is worked out

The maths is taken from LandSandBoat's `fishingutils.cpp`:

- **Skill-ups** only come from fish above your real skill level, up to 50 above. The chance peaks around 11 above you and is higher at low skill.
- **Where:** skill-ups come faster outside towns. Below skill 50 they're easier again, but Lu Shang's Fishing Rod slows them down until 50.
- **Skill-up size:** usually 0.1. One in eight is a bonus of up to 0.3 for fish well above you.
- **Getting away:** a fish more than 7 levels above your skill (with gear) can get away. It always gets away at 50 or more above.
- **Gear** (Settings) raises the skill used to land fish, not skill-ups.

The Safe / Balanced / Fast mode works like crafting: Safe avoids fish that get away, Fast takes the biggest skill-ups.

Fishing skill-up rate: **CEXI** x3.0 in every game mode (cap 110), **Retail** x1.0, **LSB** set in Settings (`FISHING_SKILL_MULTIPLIER`).

## Settings (gear icon)

The gear in the top-right corner opens Settings. You can also type `/craft settings`.

**Server rules:** pick **Retail**, **LSB** or **CEXI**.

- **Retail**: modern skill-ups (until 10 levels over a recipe), normal chance and size, one main craft to 110 and the rest to 70.
- **LSB**: your own LandSandBoat server. Set the skill-up chance and size with the steppers and switch era rules on or off, to match `settings/map.lua`.
- **CEXI**: CatsEyeXI. Every mode uses modern skill-ups (until 11 levels over a recipe's cap) and gets +1% success for every craft at 70+ (max 99%). Then switch on your game mode's rates. One mode is on at a time; with none on, normal rates are used.

| CEXI mode | Skill-up chance | Skill-up size | Rules | Caps |
|---|---|---|---|---|
| **ACE** (Accelerated) | x1.5 | x3.0 | modern | 1 main craft to 110, others 70 |
| **CW** (Crystal Warrior) | x1.5 | x1.0 | modern | every craft to 110 |
| **WEW** (Wings Era Warrior) | x1.0 | x1.0 | modern | 1 main craft to 110, others 70 |

**Skill bonuses:** switch on what you own, per craft. Bonuses make synths easier, so they raise success and the HQ tier. Skill-ups still count your real skill, which is how the server works too.

| Bonus | Skill | Applies to |
|---|---|---|
| Moglification (crafting stall in your Mog House, CatsEyeXI) | +5 | that craft |
| Crafting torque (neck) | +2 | that craft |
| Guild apron / smock | +1 | that craft |
| Guild gloves | +1 | that craft |
| Synthesis support from the guild NPC | basic +1 / advanced +3 | that craft |
| Kupo Shield | +3 | every craft |

Your effective skill (for example Bonecraft 24 + 15 = 39) is shown under the toggles.

**Fishing:** Mega Moglification: Fishing (+5), Fisher's Torque (+2), Fisherman's / Angler's tunica, gloves and hose (+1 each), and boots (+1) or waders (+2). On LSB, set the fishing skill-up rate here too.

**General:** best-synth mode (Safe / Balanced / Fast), follow skill-ups, guild kits, mini window, and showing the whole guide path.

The CatsEyeXI values come from the [CatseyeXI Crafting Guide](https://www.bg-wiki.com/ffxi/CatseyeXI_Crafting_Guide) and the CatsEyeXI game mode pages on bg-wiki.

## CatsEyeXI custom recipes

With **CEXI** picked in Settings, crafthub adds CatsEyeXI's 88 custom recipes from [CatsEyeXI Systems/Synthesis](https://www.bg-wiki.com/ffxi/CatsEyeXI_Systems/Synthesis):

- custom materials (Elementium, Embersteel Rivets, Goblin Powder, Dragon Powder, Fable Cloth, keys)
- food
- equipment (Swith Cape, Companion Belt, the elemental earrings, Domain Invasion gear, Dux and Tempest JSE, Blurred weapons)
- guild NM recipes (Exalted, Beryllium, Hepatizon, the avatar rings, Sage's set)

How they work:

- They're tagged **CEXI** in the lists and can be the best synth or pinned.
- Where CEXI changed the recipe for an item that also exists on retail, only CEXI's version is shown.
- CEXI's own items only exist in its game files, so crafthub looks them up by name in your client when it loads.
- An item it can't find still shows by name, without an icon or inventory count.

Not included:

- **Blank Key**: the wiki lists its ingredient as "any coffer key".
- **The earring desynthesis.**
- **The four furnishings with new levels** (Bakery Platter, Banquet Set, Purifying Ewer, Mock Hare): they aren't in LandSandBoat's recipe list.

`tools/gen_cexi.py` rebuilds `crafthub_cexi.lua` if the page changes.

## HQ chance

The best synth card shows your HQ chance and tier, with the HQ1 / HQ2 / HQ3 split. These use LandSandBoat's HQ rules, counting your skill bonuses:

| Tier | Effective skill over the recipe | HQ chance on a success | Upgrades |
|---|---|---|---|
| 1 | 0-10 | 1/64 (1.6%) | none |
| 2 | 11-30 | 1/16 (6.25%) | 25% to HQ2 |
| 3 | 31-50 | 1/4 (25%) | 25% to HQ2, then 25% to HQ3 |
| 4 | 51+ | 1/2 (50%) | 25% to HQ2, then 25% to HQ3 |

- There's no HQ while any craft in the recipe is below its level.
- The craft furthest behind sets the tier.

## Install

1. Copy the `crafthub` folder into `Ashita/addons/`.
2. In game: `/addon load crafthub`
3. To load it automatically, add that line to your Ashita script, e.g. `scripts/default.txt`.

## Commands

| Command | What it does |
|---|---|
| `/craft` (or `/crafthub`) | Open / close the window |
| `/craft wood` · `smith` · `gold` · `cloth` · `leather` · `bone` · `alchemy` · `cook` | Focus a craft |
| `/craft fish` | Open the Fishing tab |
| `/craft mode safe\|balanced\|fast` | How much breaking you'll accept |
| `/craft mini` | Toggle the mini window |
| `/craft follow` | Toggle auto-focusing the craft that just skilled up |
| `/craft kits` | Toggle using guild kits (Lv 5–50) for the best synth |
| `/craft settings` | Open Settings (same as the gear icon) |
| `/craft server retail\|lsb\|cexi` | Server rules. `ace`, `cw` or `wew` picks CEXI with that mode's rates switched on |
| `/craft rate <n>` · `size <n>` · `era` | Your LSB server's skill-up chance, skill-up size, and era rules |
| `/craft level <craft> <0-9>` | Tell crafthub your current decimal, e.g. `/craft level wood 4` |
| `/craft debug` | Show the raw skill values read from memory and from the server packet |
| `/craft reset` | Re-centre and re-fit the window |

## Data sources

- [CatseyeXI Crafting Guide (bg-wiki)](https://www.bg-wiki.com/ffxi/CatseyeXI_Crafting_Guide): the skill-up path and notes for each craft. One row, Black Chocobo Fletchings, has no LSB recipe and is shown as a note only.
- [LandSandBoat](https://github.com/LandSandBoat/server): recipes, item names, the success and skill-up formulas, and the skill packet layouts.
- [CatseyeXI Fishing Guide (bg-wiki)](https://www.bg-wiki.com/ffxi/CatseyeXI/Fishing_Guide): the fishing route, rods, bait and spots. Gerrothorax is level 110 on CEXI.
- LandSandBoat's fishing tables (`sql/fishing_*.sql`): every fish, rod, bait and fishing area. `tools/gen_fish.py` rebuilds `crafthub_fish.lua`.
- Rank-up test items: [bg-wiki rank pages](https://www.bg-wiki.com/ffxi/Rank-up_Test), [FFXIclopedia guild pages](https://ffxiclopedia.fandom.com/wiki/Category:Bonecraft) and [Creative Uncut guild pages](https://www.creativeuncut.com/ffxi_guild_alchemy.html). Ranks without a known item say "ask the guild master".

## Credits

- **Yuna** of CatsEyeXI: the YunaUI glass panel design that crafthub's dashboard look is based on.
