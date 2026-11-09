-- crafthub: synthesis maths. Mirrors LandSandBoat's src/map/utils/synthutils.cpp
-- (getSynthDifficulty / getSynthResult / doSynthSkillUp) so the numbers match
-- what your server actually rolls. No game or ImGui calls in here.
local M = {}

M.CRAFTS = {
    { key = 'wood',    name = 'Woodworking',  short = 'WOOD',    skill = 49 },
    { key = 'smith',   name = 'Smithing',     short = 'SMITH',   skill = 50 },
    { key = 'gold',    name = 'Goldsmithing', short = 'GOLD',    skill = 51 },
    { key = 'cloth',   name = 'Clothcraft',   short = 'CLOTH',   skill = 52 },
    { key = 'leather', name = 'Leathercraft', short = 'LEATHER', skill = 53 },
    { key = 'bone',    name = 'Bonecraft',    short = 'BONE',    skill = 54 },
    { key = 'alchemy', name = 'Alchemy',      short = 'ALCH',    skill = 55 },
    { key = 'cook',    name = 'Cooking',      short = 'COOK',    skill = 56 },
}
M.BY_SKILL = {}
M.BY_KEY = {}
for i, c in ipairs(M.CRAFTS) do M.BY_SKILL[c.skill] = i; M.BY_KEY[c.key] = i end

M.RANKS = { 'Amateur', 'Recruit', 'Initiate', 'Novice', 'Apprentice', 'Journeyman',
    'Craftsman', 'Artisan', 'Adept', 'Veteran', 'Expert', 'Authority' }

function M.rank_name(rank) return M.RANKS[(rank or 0) + 1] or ('Rank ' .. tostring(rank)) end
-- A rank's cap: Amateur 10, Recruit 20, ... (rank + 1) * 10.
function M.rank_cap(rank) return ((rank or 0) + 1) * 10 end

-- Rank-up test items, traded to the guild master from cap-2 (8, 18, 28 ...).
-- Sources: bg-wiki rank pages, FFXIclopedia guild pages, Creative Uncut guild
-- pages and the CatseyeXI guide. Missing entries: ask the guild master.
M.TEST_ITEMS = {
    wood    = { [10] = 'Workbench', [50] = 'Rose Wand', [100] = 'Vejovis Wand' },
    smith   = { [10] = 'Xiphos', [50] = 'Mythril Pick' },
    gold    = { [10] = 'Copper Hairpin', [20] = 'Brass Hairpin', [30] = 'Silver Hairpin', [40] = 'Chain Gorget',
                [50] = 'Mythril Ring', [60] = 'Mythril Gorget', [70] = 'Mythril Breastplate', [80] = 'Torque',
                [90] = 'Colichemarde', [100] = 'Evader Earring' },
    cloth   = { [10] = 'Cape', [50] = 'Wool Bracers', [100] = 'Swith Cape' },
    leather = { [10] = 'Rabbit Mantle', [50] = 'Cuir Bouilli' },
    bone    = { [10] = 'Shell Ring', [20] = 'Bone Ring', [30] = 'Beetle Earring', [40] = 'Horn Ring',
                [50] = 'Carapace Gorget', [60] = 'Astragalos', [70] = 'Bone Patas', [80] = 'Coral Hairpin',
                [90] = 'Coral Bangles', [100] = 'Hajduk Ring' },
    alchemy = { [10] = 'Animal Glue', [20] = 'Poison Potion', [30] = 'Blinding Potion', [40] = 'Firesand',
                [50] = 'Fire Sword', [60] = 'Hi-Potion', [70] = 'Acid Kukri', [80] = 'X-Potion',
                [90] = 'Bloody Sword', [100] = 'Saida Ring' },
    cook    = { [10] = 'Salmon Sub Sandwich', [20] = 'Pea Soup', [30] = 'Vegetable Gruel', [40] = 'Meat Mithkabob',
                [50] = 'Apple Pie', [60] = 'Yagudo Drink', [70] = 'Raisin Bread', [80] = 'Whitefish Stew',
                [90] = 'Seafood Stew', [100] = 'Sprightly Soup (HQ crystal)' },
}

M.GUILDS = {
    wood    = "Carpenters' Guild, Northern San d'Oria",
    smith   = "Blacksmiths' Guild: Mevreauche (N. San d'Oria) or Ghemp (Metalworks)",
    gold    = "Goldsmiths' Guild: Reinberta, Bastok Markets",
    cloth   = "Weavers' Guild: Ponono, Windurst Woods",
    leather = "Tanners' Guild, Southern San d'Oria",
    bone    = "Boneworkers' Guild: Peshi Yohnts, Windurst Woods",
    alchemy = "Alchemists' Guild: Abd-al-Raziq, Bastok Mines",
    cook    = "Culinarians' Guild: Piketo-Puketo, Windurst Waters",
}

-- Server rules. modern = LSB CRAFT_MODERN_SYSTEM (skill-ups until 10 over a
-- recipe); rate = CRAFT_CHANCE_MULTIPLIER; common_cap / spec_points = the
-- specialisation system (points shared by every craft above 70).
M.rules = { modern = true, rate = 1.0, amount = 1.0, common_cap = 70, spec_points = 40, bonus70 = 0,
    skill_bonus = {},   -- [craft] = extra skill from gear / moghancement / support (synth difficulty only)
    hq_mult = 1.0 }     -- CRAFT_HQ_CHANCE_MULTIPLIER

-- HQ chance per tier (LSB synthutils, from CraftyMath): tier 1 = 0-10 levels over the
-- recipe, 2 = 11-30, 3 = 31-50, 4 = 51+. After an HQ, tier 2 can upgrade once and
-- tiers 3-4 twice, 25% each time (HQ1 -> HQ2 -> HQ3). Capped at 80%.
M.HQ_CHANCE = { [0] = 0, 0.015625, 0.0625, 0.25, 0.50 }
M.HQ_RANGE = { [0] = 'below the recipe', '0-10 over', '11-30 over', '31-50 over', '51+ over' }

-- Server presets. lsb = stock LandSandBoat. The CatsEyeXI ones come from the
-- bg-wiki CatseyeXI Crafting Guide (rate 1.5x for ACE and CW, skill-up size 3.0x
-- for ACE) and the mode pages (WEW: era rates and amounts; CW: slightly above era,
-- every craft can reach 110; ACE / WEW: one main craft to 110, sub crafts to 70).
-- bonus70: CatsEyeXI gives +1% synth success for every craft at 70 or higher (max 99%).
-- Every CatsEyeXI mode uses the modern system: skill-ups until 11 levels over a recipe's cap.
M.SERVERS = {
    retail = { label = 'Retail', name = 'Retail FFXI',          rate = 1.0, amount = 1.0, modern = true,  spec_points = 40, bonus70 = 0 },
    cexi = { label = 'CEXI',    name = 'CatsEyeXI (no mode rates)', rate = 1.0, amount = 1.0, modern = true, spec_points = 40, bonus70 = 1 },
    lsb = { label = 'LSB',      name = 'LandSandBoat defaults',  rate = 1.0, amount = 1.0, modern = true,  spec_points = 40, bonus70 = 0 },
    ace = { label = 'CEXI ACE', name = 'CatsEyeXI Accelerated',  rate = 1.5, amount = 3.0, modern = true,  spec_points = 40, bonus70 = 1 },
    cw  = { label = 'CEXI CW',  name = 'CatsEyeXI Crystal Warrior', rate = 1.5, amount = 1.0, modern = true,  spec_points = 320, bonus70 = 1 },
    wew = { label = 'CEXI WEW', name = 'CatsEyeXI Wings Era Warrior', rate = 1.0, amount = 1.0, modern = true,  spec_points = 40, bonus70 = 1 },
}
M.SERVER_ORDER = { 'retail', 'lsb', 'cexi' }
M.CEXI_MODES = { 'ace', 'cw', 'wew' }

-- Success chance (0..1) for one craft at difficulty d = recipe level - your level.
function M.success_one(d, bonus)
    if d >= 15 then return 0 end
    local s
    if d >= 4 then s = 80 - 10 * (d - 3)
    elseif d >= 1 then s = 95 - 5 * d
    else s = 95 end
    return math.max(0, math.min(99, s + (bonus or 0))) / 100
end

-- Success bonus (%) from crafts at 70+ (CatsEyeXI rule; 0 on stock LSB).
function M.success_bonus(skills)
    local per = M.rules.bonus70 or 0
    if per == 0 then return 0 end
    local n = 0
    for j = 1, 8 do if skills[j] and (skills[j].level or 0) >= 70 then n = n + 1 end end
    return n * per
end

-- HQ tier when you're at/over the recipe (0 = no HQ possible).
function M.hq_tier(d)
    if d >= 1 then return 0 end
    if d >= -10 then return 1 end
    if d >= -30 then return 2 end
    if d >= -50 then return 3 end
    return 4
end

-- Chance of a skill-up on a successful synth / on a break. tenths = your skill in 0.1s.
function M.skillup_chance(d, tenths)
    local r = M.rules
    if r.modern then
        if d <= -11 then return 0, 0 end
    else
        if d <= 0 then return 0, 0 end
    end
    local c
    if r.modern then
        local k = 3.0 - math.log(1.2 + tenths / 100.0)
        if d > 1 then c = d * k / 5.0 else c = k / (6 - d) end
    else
        c = tenths < 500 and 0.6 or 0.25
    end
    c = math.max(0, math.min(1, c * (r.rate or 1)))
    -- a break only skills up when the recipe is 1-5 above you, at half the chance
    local f = (d > 0 and d <= 5) and (c / 2) or 0
    return c, f
end

-- Average skill-up size in 0.1s (LSB skillUpAmountWeights; only 0.1 at 60+).
local WEIGHTS = {
    [0] = { 85, 15, 0, 0, 0 }, { 85, 15, 0, 0, 0 }, { 85, 15, 0, 0, 0 }, { 80, 20, 0, 0, 0 },
    { 80, 20, 0, 0, 0 }, { 70, 30, 0, 0, 0 }, { 70, 30, 0, 0, 0 }, { 60, 40, 0, 0, 0 },
    { 60, 40, 0, 0, 0 }, { 50, 40, 10, 0, 0 }, { 40, 40, 20, 0, 0 }, { 40, 40, 20, 0, 0 },
    { 15, 45, 30, 10, 0 }, { 10, 40, 25, 25, 0 }, { 0, 40, 30, 20, 10 },
}
function M.avg_amount(d, tenths)
    local mult = M.rules.amount or 1
    if tenths >= 600 then return 1 * mult end
    local w = WEIGHTS[math.max(0, math.min(14, d))]
    local sum = 0
    for i = 1, 5 do sum = sum + i * w[i] end
    return sum / 100 * mult
end

-- Evaluate a recipe for craft k. skills[j] = { level = n, tenths = n*10+dec }.
-- Returns a table, or nil when the recipe doesn't use craft k.
function M.evaluate(rec, k, skills)
    local lvk = rec.lv[k] or 0
    if lvk <= 0 then return nil end
    local me = skills[k] or { level = 0, tenths = 0 }
    local d = lvk - me.level                 -- real difficulty: skill-ups and the attempt limit
    local sb = M.rules.skill_bonus or {}
    local d_eff = d - (sb[k] or 0)           -- with gear / support: success and HQ
    local succ = 1
    local attempt = true
    local bonus = M.success_bonus(skills)
    local subs = {}
    local tier = 4
    for j = 1, 8 do
        local l = rec.lv[j] or 0
        if l > 0 then
            local sj = skills[j] or { level = 0 }
            local dj = l - sj.level
            local dje = dj - (sb[j] or 0)
            if dj >= 15 then attempt = false end
            succ = succ * M.success_one(dje, bonus)
            tier = math.min(tier, M.hq_tier(dje))   -- the weakest craft sets the HQ tier
            if j ~= k then subs[#subs + 1] = { craft = j, need = l, have = sj.level, eff = sj.level + (sb[j] or 0), ok = dje < 1 } end
        end
    end
    if not attempt then succ = 0 end
    -- HQ odds per synth (already including the chance to break)
    local hqc = math.min(0.80, (M.HQ_CHANCE[tier] or 0) * (M.rules.hq_mult or 1))
    local up = (tier >= 3) and 2 or ((tier == 2) and 1 or 0)
    local hq1, hq2, hq3 = 1, 0, 0
    if up >= 1 then hq1, hq2 = 0.75, 0.25 end
    if up >= 2 then hq2, hq3 = 0.25 * 0.75, 0.25 * 0.25 end
    local p_hq = succ * hqc
    local cs, cf = M.skillup_chance(d, me.tenths)
    if me.capped then cs, cf = 0, 0 end   -- no skill-ups at a rank cap until the test is passed
    local amt = M.avg_amount(d, me.tenths)
    local gain = attempt and (succ * cs + (1 - succ) * cf) * amt or 0   -- tenths per synth
    return {
        rec = rec, craft = k, level = lvk, d = d, d_eff = d_eff, bonus = sb[k] or 0, success = succ, attempt = attempt,
        chance = cs, chance_fail = cf, amount = amt, gain = gain,
        per_level = gain > 0 and (10 / gain) or nil,
        can_skill = attempt and gain > 0, hq_tier = tier, subs = subs,
        hq = p_hq, hq_given = hqc, hq1 = p_hq * hq1, hq2 = p_hq * hq2, hq3 = p_hq * hq3,
    }
end

-- Scoring: expected gain, weighted against breaks by mode.
M.MODES = { safe = 4, balanced = 2, fast = 0.75 }
function M.score(ev, mode)
    if not ev or not ev.can_skill then return -1 end
    return ev.gain * (ev.success ^ (M.MODES[mode] or 1))
end

-- Best row on the guide path for craft k. Returns ev, row index.
function M.best_on_path(path, recipes, k, skills, mode)
    local best, bi, bs = nil, nil, -1
    for i, row in ipairs(path or {}) do
        local rec = row.rec and recipes[row.rec]
        local ev = rec and M.evaluate(rec, k, skills)
        local s = M.score(ev, mode)
        if s > bs then best, bi, bs = ev, i, s end
    end
    if bs <= 0 then return nil, nil end
    best.row = path[bi]
    return best, bi
end

-- Other good recipes for craft k (k is the recipe's main craft). list = per-craft index.
-- CatsEyeXI recipes only count on CEXI, and there they replace the retail recipe
-- for the same item.
function M.available(rec)
    if M.rules.custom then return not rec.cexi_replaced end
    return not rec.cexi
end

M.KIT_MAX = 50   -- guild kits are only considered up to this recipe level

function M.kit_ok(rec, k, allow_kits)
    if not rec.kit then return true end
    return allow_kits and (rec.lv[k] or 0) <= M.KIT_MAX
end

function M.alternatives(list, k, skills, mode, limit, skip, allow_kits)
    local out = {}
    for _, rec in ipairs(list or {}) do
        if not (skip and skip[rec.id]) and M.kit_ok(rec, k, allow_kits) and M.available(rec) then
            local ev = M.evaluate(rec, k, skills)
            if ev and ev.can_skill then
                ev.score = M.score(ev, mode)
                out[#out + 1] = ev
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.rec.id < b.rec.id
    end)
    while #out > (limit or 8) do table.remove(out) end
    return out
end

-- Every guild kit for craft k up to KIT_MAX, evaluated, in level order.
function M.kits(list, k, skills)
    local out = {}
    for _, rec in ipairs(list or {}) do
        if rec.kit and (rec.lv[k] or 0) <= M.KIT_MAX then out[#out + 1] = M.evaluate(rec, k, skills) end
    end
    return out
end

-- Best guild kit for craft k right now (nil if none skill up).
function M.best_kit(list, k, skills, mode)
    local best, bs = nil, 0
    for _, ev in ipairs(M.kits(list, k, skills)) do
        local s = M.score(ev, mode)
        if s > bs then best, bs = ev, s end
    end
    return best
end

-- Index the recipe table by main craft (highest level) and flag guild kits.
function M.index(recipes, items)
    local by = {}
    for k = 1, 8 do by[k] = {} end
    for _, rec in pairs(recipes) do
        local main, ml = nil, 0
        for j = 1, 8 do if (rec.lv[j] or 0) > ml then main, ml = j, rec.lv[j] end end
        for _, ing in ipairs(rec.i) do
            local n = items and items[ing[1]]
            -- guild kits are "<Craft>. Kit 5" ... "Kit 50" (not Kitron, not furnishing kits)
            if n and n:find('Kit %d+$') then rec.kit = true end
        end
        if main then rec.main = main; table.insert(by[main], rec) end
    end
    for k = 1, 8 do
        table.sort(by[k], function(a, b)
            if a.lv[k] ~= b.lv[k] then return a.lv[k] < b.lv[k] end
            return a.id < b.id
        end)
    end
    return by
end

-- Decode a 0x062 / memory craft value: level in bits 5-14, rank bits 0-4, 0x8000 = capped.
function M.decode(v)
    v = tonumber(v) or 0
    local capped = v >= 0x8000
    if capped then v = v - 0x8000 end
    return math.floor(v / 32) % 1024, v % 32, capped
end

-- Specialisation points used above the common cap (decimals round up).
function M.spec_used(skills)
    local used = 0
    for k = 1, 8 do
        local s = skills[k]
        if s and s.tenths > M.rules.common_cap * 10 then
            used = used + math.ceil((s.tenths - M.rules.common_cap * 10) / 10)
        end
    end
    return used
end

return M
