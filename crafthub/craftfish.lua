-- crafthub: fishing maths. Mirrors LandSandBoat's src/map/utils/fishingutils.cpp
-- (FishingSkillup, CalculateLoseChance) so the numbers match what the server rolls.
-- No game or ImGui calls in here.
local M = {}

M.SKILL_ID = 48   -- fishing in the skill list / skill-up messages

-- rate = FISHING_SKILL_MULTIPLIER; bonus = fishing skill from gear and moglification
-- (it helps you land fish, but skill-ups use your real skill)
M.rules = { rate = 1.0, bonus = 0, cap = nil }

-- Chance (0..1) of a skill-up when you land a fish of level `lv`, and the
-- average skill-up in tenths. tenths = your real fishing skill x10.
function M.skillup(lv, tenths, town, lu_shang)
    local s = math.floor(tenths / 10)
    local d = lv - s
    if d <= 0 or d > 50 then return 0, 0 end
    local norm = math.exp(-0.5 * math.log(2 * math.pi) - math.log(5) - ((d - 11) ^ 2) / 50)
    local chance = math.max(4, math.floor(norm * 200) + math.floor((100 - s) / 10) - math.floor(s / 10))
    chance = math.floor(chance * (M.rules.rate or 1))
    local roll = 90
    if lu_shang and s < 50 then roll = roll + 20 end      -- Lu Shang's rod under 50
    if not town then roll = roll - 10 end                 -- outside towns
    if s < 50 then roll = roll - (20 - math.floor(s / 3)) end
    local p = math.min(1, chance / roll)
    -- 1 in 8 skill-ups is a bonus of 1..max, max growing with the gap (up to 3)
    local maxamt = math.min(1 + math.floor(d / 5), 3)
    local amount = 7 / 8 + (1 / 8) * (1 + maxamt) / 2
    return p, amount
end

-- Chance (0..1) the fish gets away because your skill (with gear) is too low.
function M.lose_low_skill(lv, skill)
    if skill + 50 <= lv then return 1 end
    if skill + 7 >= lv then return 0 end
    return math.min(1, math.floor((lv - (skill + 7)) * 0.8) / 100)
end

-- Rod problems for a fish (rods: id -> { size, maxrank, legend }):
-- 'big' = fish can escape as too big, 'small' = large rod loses small fish.
function M.rod_issue(rod, fish)
    if not rod or rod.legend then return nil end
    if fish.size > rod.size and fish.rank > rod.maxrank then return 'big' end
    if fish.size < rod.size then return 'small' end
    return nil
end

-- A good rod for a fish from the common ones (Lu Shang's catches almost everything).
local SMALL_RODS = { 17015, 17386, 17011 }          -- Halcyon, Lu Shang's, Ebisu
local LARGE_RODS = { 17381, 17386, 17011 }          -- Composite, Lu Shang's, Ebisu
function M.pick_rod(rods, fish)
    for _, id in ipairs(fish.size == 1 and LARGE_RODS or SMALL_RODS) do
        local r = rods[id]
        if r and not M.rod_issue(r, fish) then return id end
    end
    return 17386
end

-- Evaluate a fish. skill = { tenths, level }. lv overrides the fish's level.
-- Returns gain in tenths per fish landed attempt, chances, etc.
function M.evaluate(fish, skill, opts)
    opts = opts or {}
    local lv = opts.lv or fish.lv
    local town = opts.town
    local p, amount = M.skillup(lv, skill.tenths, town, opts.lu_shang)
    local eff = skill.level + (M.rules.bonus or 0)
    local lose = M.lose_low_skill(lv, eff)
    local gain = (1 - lose) * p * amount
    return {
        fish = fish, lv = lv, d = lv - skill.level, chance = p, amount = amount, lose = lose,
        gain = gain, per_level = gain > 0 and (10 / gain) or nil, can_skill = gain > 0, town = town,
    }
end

M.MODES = { safe = 3, balanced = 1, fast = 0.25 }
function M.score(ev, mode)
    if not ev or not ev.can_skill then return -1 end
    return ev.gain * ((1 - ev.lose) ^ (M.MODES[mode] or 1))
end

-- Mostly-town spots count as town fishing (slower skill-ups) when every spot is a town.
function M.all_town(fish)
    if not fish.at or #fish.at == 0 then return false end
    for _, a in ipairs(fish.at) do if not a[3] then return false end end
    return true
end

return M
