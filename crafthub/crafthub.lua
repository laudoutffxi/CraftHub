addon.name = 'crafthub'
addon.author = 'Laudout'
addon.version = '1.0.0'
addon.desc = 'Crafting advisor: the best synth for your current skill in every craft (CatseyeXI path + LSB recipes).'

require('common')

local chat = require('chat')
local imgui = require('imgui')
local bit = require('bit')

local T = require('crafttheme')   -- shared drawing helpers (VanaCore look)
local C = require('craftcalc')    -- synthesis maths (mirrors LSB synthutils)
local D = require('crafthub_data')
local ICON = require('crafticons')  -- item icons from the game client
local FM = require('craftfish')      -- fishing maths (mirrors LSB fishingutils)
local FD = require('crafthub_fish')  -- fish, rods, baits, spots, CatsEyeXI route

local HUD, ui, CORNERS_ALL = T.HUD, T.ui, T.CORNERS_ALL
local rgba, col, pulse, line_h, text_w, DL = T.rgba, T.col, T.pulse, T.line_h, T.text_w, T.DL
local text, rtext, fit, dot = T.text, T.rtext, T.fit, T.dot
local pill_w, pill, bar, card_bg = T.pill_w, T.pill, T.bar, T.card_bg
local hit, advance, avail_w = T.hit, T.advance, T.avail_w
local seg_tabs, seg_width, toggle_chip, toggle_w, panel, band = T.seg_tabs, T.seg_width, T.toggle_chip, T.toggle_w, T.panel, T.band

-- CatsEyeXI's custom recipes. Their items are looked up by name in the game client
-- (CEXI's own items only exist there); LandSandBoat ids are the fallback for retail
-- items, and anything not found gets a placeholder id so it still shows by name.
local X = require('crafthub_cexi')
do
    local function game_id(name)
        local ok, id = pcall(function()
            local rm = AshitaCore:GetResourceManager()
            for _, lang in ipairs({ 2, 0, 1 }) do
                local it = rm:GetItemByName(name, lang)
                if it and it.Id and it.Id > 0 then return it.Id end
            end
            return nil
        end)
        return ok and id or nil
    end
    local resolved, next_fake = {}, -1
    local function item_id(name)
        local id = resolved[name]
        if id then return id end
        id = game_id(name) or X.ids[name]
        if not id then id = next_fake; next_fake = next_fake - 1 end   -- not in your game data
        resolved[name] = id
        if not D.items[id] then D.items[id] = name end
        return id
    end
    local LV = { wood = 1, smith = 2, gold = 3, cloth = 4, leather = 5, bone = 6, alchemy = 7, cook = 8 }
    for i, cr in ipairs(X.recipes) do
        local lv = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for key, v in pairs(cr.lv) do lv[LV[key]] = v end
        local ings = {}
        for _, ing in ipairs(cr.i) do ings[#ings + 1] = { item_id(ing[1]), ing[2] } end
        local id = 900000 + i
        D.recipes[id] = { id = id, n = cr.n, c = cr.c, lv = lv, i = ings, r = item_id(cr.n), q = cr.q or 1,
            cexi = true, note = cr.note, sec = cr.sec }
    end
    -- a CEXI recipe for an item that also has a retail recipe replaces it on CEXI
    local custom_result = {}
    for _, rec in pairs(D.recipes) do if rec.cexi and rec.r > 0 then custom_result[rec.r] = true end end
    for _, rec in pairs(D.recipes) do
        if not rec.cexi and custom_result[rec.r] then rec.cexi_replaced = true end
    end
    -- retail recipes CatsEyeXI moved to other levels: both sets kept, swapped by the rules
    for _, ov in ipairs(X.overrides) do
        local lv = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for key, v in pairs(ov.lv) do lv[LV[key]] = v end
        for _, rec in pairs(D.recipes) do
            if rec.r == ov.r and not rec.cexi then rec.lv_retail, rec.lv_cexi = rec.lv, lv end
        end
    end
end

local BY_CRAFT = C.index(D.recipes, D.items)   -- recipes grouped by main craft
local BY_RESULT = {}                            -- result item id -> recipes that make it
for _, rec in pairs(D.recipes) do
    BY_RESULT[rec.r] = BY_RESULT[rec.r] or {}
    table.insert(BY_RESULT[rec.r], rec)
end

local ELEMENT_COLOR = {
    [4096] = { 1.00, 0.42, 0.24, 1 }, [4097] = { 0.58, 0.84, 1.00, 1 }, [4098] = { 0.40, 0.94, 0.62, 1 },
    [4099] = { 0.86, 0.72, 0.34, 1 }, [4100] = { 0.80, 0.58, 1.00, 1 }, [4101] = { 0.36, 0.58, 1.00, 1 },
    [4102] = { 1.00, 0.95, 0.76, 1 }, [4103] = { 0.66, 0.44, 0.80, 1 },
}

local NO_DOCK = ImGuiWindowFlags_NoDocking or 0

local state = {
    visible = { false },
    mini_open = { true },
    tab = 1,            -- 1 overview, 2 best synth, 3 recipes
    craft = 1,          -- focused craft (index into C.CRAFTS)
    mode = 'balanced',  -- safe / balanced / fast
    mini = false,       -- compact strip window
    follow = true,      -- focus whichever craft just skilled up
    path_all = false,   -- show the whole guide path, not just what's still useful
    kits = true,        -- consider guild kits (Lv 5-50) for the best synth
    pin = nil,          -- recipe id pinned into the detail panel
    search = { '' },
    rate = 1.0, modern = true, amount = 1.0,
    server = 'lsb',     -- rules: retail / lsb / cexi (rate, amount, modern above are LSB's own values)
    cexi_mode = '',     -- CEXI game mode whose rates apply: ace / cw / wew, or '' for none
    settings = false,   -- settings view open
    gear = {},          -- [craft key] = { mog, neck, body, hands = bool, support = 0 / 1 / 3 }
    kupo = false,       -- Kupo Shield: synthesis skill +3 to every craft
    gear_craft = nil,   -- craft shown in the skill bonuses panel (nil = focused craft)
    fish_rate = 1.0,    -- LSB FISHING_SKILL_MULTIPLIER
    fish_gear = {},     -- mog, torque, body, hands, legs = bool; feet = 0 / 1 (boots) / 2 (waders)
    fish_pin = nil,     -- fish id pinned on the Fishing tab
    fish_list = 'route',
    fish_pkt = nil,     -- fishing skill from the last 0x062 packet
    fish_session = { gain = 0, ups = 0, caught = 0 },
    tenths = {},        -- [char] = { [craft] = { level, dec } } known decimals
    session = {},       -- [craft] = { gain = tenths, ups = n }
    synths = { ok = 0, broke = 0 },
    pkt = {},           -- [craft] = { level, rank, capped } from 0x062
    win_size = nil,
}

--------------------------------------------------------------------------------
-- Window placement (no docking, kept on the game screen)
--------------------------------------------------------------------------------

local function call(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

local function undock_next()
    if type(imgui.SetNextWindowDockID) == 'function' then pcall(imgui.SetNextWindowDockID, 0, ImGuiCond_Always) end
end

local function main_viewport()
    local ok, vp = pcall(imgui.GetMainViewport)
    if ok and vp then
        local ok2, r = pcall(function() return { vp.Pos.x, vp.Pos.y, vp.Size.x, vp.Size.y, vp.ID } end)
        if ok2 and r and tonumber(r[3]) and r[3] > 0 then return r end
    end
    local io_ok, io = pcall(imgui.GetIO)
    local w = (io_ok and io and io.DisplaySize and io.DisplaySize.x) or 1920
    local h = (io_ok and io and io.DisplaySize and io.DisplaySize.y) or 1080
    return { 0, 0, w, h, nil }
end

local function clamp_pos(x, y, w, h)
    local vp = main_viewport()
    x = math.max(vp[1], math.min(x, vp[1] + vp[3] - w))
    y = math.max(vp[2], math.min(y, vp[2] + vp[4] - h))
    return x, y
end

local function place_window(st, w, h)
    local vp = main_viewport()
    if vp[5] ~= nil and type(imgui.SetNextWindowViewport) == 'function' then pcall(imgui.SetNextWindowViewport, vp[5]) end
    if st.pos then
        st.pos[1], st.pos[2] = clamp_pos(st.pos[1], st.pos[2], w, h)
        imgui.SetNextWindowPos({ st.pos[1], st.pos[2] }, ImGuiCond_Always)
    end
end

local function drag_window(st)
    local wx, wy = call(imgui.GetWindowPos)
    if not st.pos and tonumber(wx) then st.pos = { wx, wy } end
    local mx, my = call(imgui.GetMousePos)
    if not tonumber(mx) or not tonumber(my) then return end
    if st.drag then
        if call(imgui.IsMouseDown, 0) then
            st.pos = { st.drag[3] + (mx - st.drag[1]), st.drag[4] + (my - st.drag[2]) }
        else
            st.drag = nil
        end
    elseif call(imgui.IsMouseClicked, 0) and call(imgui.IsWindowHovered) and not call(imgui.IsAnyItemHovered) then
        st.drag = { mx, my, st.pos and st.pos[1] or wx, st.pos and st.pos[2] or wy }
    end
end

--------------------------------------------------------------------------------
-- Game data
--------------------------------------------------------------------------------

local function msg(s) print(chat.header(addon.name):append(chat.message(s))) end

local function player_name()
    local ok, n = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return nil
end

-- Item names: the game's own resources first (exact in-game spelling), else the data file.
local name_cache = {}
local function item_name(id)
    local n = name_cache[id]
    if n then return n end
    local ok, r = pcall(function()
        local it = AshitaCore:GetResourceManager():GetItemById(id)
        return it and it.Name and it.Name[1]
    end)
    n = (ok and type(r) == 'string' and r ~= '') and r or D.items[id] or ('Item #' .. tostring(id))
    name_cache[id] = n
    return n
end

-- Item stats for the hover card, read from the game client (cached).
local JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
    'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' }
local info_cache = {}
local function clean_text(t)
    if type(t) ~= 'string' then return '' end
    t = t:gsub('\r', ''):gsub('[%z\1-\9\11-\31\127]', ' ')
    -- keep valid UTF-8 only; the game's own symbol bytes (element icons etc.) are dropped
    local out, i, n = {}, 1, #t
    while i <= n do
        local c = t:byte(i)
        local len = (c < 0x80 and 1) or (c >= 0xC2 and c <= 0xDF and 2) or (c >= 0xE0 and c <= 0xEF and 3)
            or (c >= 0xF0 and c <= 0xF4 and 4) or 0
        local good = len > 0 and i + len - 1 <= n
        for j = i + 1, i + len - 1 do
            if not good then break end
            local cc = t:byte(j)
            if cc < 0x80 or cc > 0xBF then good = false end
        end
        if good then out[#out + 1] = t:sub(i, i + len - 1); i = i + len else i = i + 1 end
    end
    return (table.concat(out):gsub('  +', ' '))
end
local function item_info(id)
    if info_cache[id] ~= nil then return info_cache[id] or nil end
    local ok, info = pcall(function()
        local it = AshitaCore:GetResourceManager():GetItemById(id)
        if not it or not it.Id or it.Id == 0 then return nil end
        local function f(k) local o, v = pcall(function() return it[k] end); return o and v or nil end
        local desc = ''
        local d = f('Description')
        if d then desc = d[1] or d[0] or '' end
        local i = { name = item_name(id), desc = clean_text(desc), lines = {} }
        local lv = tonumber(f('Level')) or 0
        local jobs = tonumber(f('Jobs')) or 0
        if lv > 0 or jobs > 0 then
            local names, all = {}, true
            for j = 1, #JOBS do
                if bit.band(jobs, bit.lshift(1, j)) ~= 0 then names[#names + 1] = JOBS[j] else all = false end
            end
            local js = (#names == 0 and '') or (all and 'All Jobs') or table.concat(names, '/')
            local line = ((lv > 0) and ('Lv.%d  '):format(lv) or '') .. js
            if line ~= '' then i.lines[#i.lines + 1] = line:gsub('%s+$', '') end
        end
        local stack = tonumber(f('StackSize')) or 0
        if stack > 1 then i.stack = stack end
        local flags = tonumber(f('Flags')) or 0
        if bit.band(flags, 0x8000) ~= 0 then i.rare = true end          -- Rare
        if bit.band(flags, 0x4000) ~= 0 then i.ex = true end            -- Exclusive
        return i
    end)
    info_cache[id] = (ok and info) or false
    return info_cache[id] or nil
end

-- One craft skill from memory: Ashita's player CraftSkills[0] is Fishing, so
-- Woodworking..Cooking are 1..8. Returns level, rank, capped (or nil).
local function mem_craft(k)
    local ok, lv, rk, cap = pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer()
        local s = p:GetCraftSkill(k)
        if type(s) == 'number' then return C.decode(s) end
        local l = s.GetSkill and s:GetSkill() or s.Skill
        local r = s.GetRank and s:GetRank() or s.Rank
        local c = s.IsCapped and s:IsCapped() or s.Capped
        return tonumber(l), tonumber(r), c == true or c == 1
    end)
    if ok and lv then return lv, rk or 0, cap end
    return nil
end

local skills = {}   -- [k] = { level, rank, capped, tenths, dec_known }
local function char_tenths()
    local n = player_name()
    if not n then return nil end
    state.tenths[n] = state.tenths[n] or {}
    return state.tenths[n]
end

local PAIR_WINDOW = 3         -- seconds (wall clock); skill-up messages come in the same burst
local recent = {}             -- [key] = { kind = 38 | 53, at, prev, amount, level }

local function refresh_skills()
    local saved = char_tenths() or {}
    for k = 1, 8 do
        -- the server's own skill packet (0x062) wins once we've seen one; until
        -- then (addon loaded mid-session) read the client's memory
        local p = state.pkt[k]
        if p then
            skills[k] = { level = p[1], rank = p[2], capped = p[3] }
        else
            local lv, rk, cap = mem_craft(k)
            skills[k] = { level = lv or 0, rank = rk or 0, capped = cap or false }
        end
    end
    for k = 1, 8 do
        local s = skills[k]
        local t = saved[C.CRAFTS[k].key]
        if t and t[1] == s.level then
            s.dec, s.dec_known = math.min(9, t[2]), true
        elseif t and t[1] > s.level and not s.capped then
            -- counted past the level but the server hasn't levelled you: the saved decimal
            -- is too high, so show N.? until the next level-up (or /craft level) fixes it
            s.dec, s.dec_known, s.ahead = 0, false, true
        else
            s.dec, s.dec_known = 0, false
        end
        s.tenths = s.level * 10 + s.dec
        local rc = C.rank_cap(s.rank)
        s.cap = rc
        if s.level >= rc then s.capped = true end
        if s.capped then s.dec, s.dec_known, s.tenths = 0, true, s.level * 10 end
    end
end

-- Fishing skill: the server's 0x062 packet once seen, else memory (craft slot 0).
local fishing = { level = 0, rank = 0, capped = false, tenths = 0, dec_known = false, cap = 10 }
local function refresh_fishing()
    local p = state.fish_pkt
    local lv, rk, cap
    if p then lv, rk, cap = p[1], p[2], p[3] else lv, rk, cap = mem_craft(0) end
    local f = { level = lv or 0, rank = rk or 0, capped = cap or false }
    local t = (char_tenths() or {}).fish
    if t and t[1] == f.level then f.dec, f.dec_known = math.min(9, t[2]), true
    elseif t and t[1] > f.level and not f.capped then f.dec, f.dec_known = 0, false
    else f.dec, f.dec_known = 0, false end
    f.tenths = f.level * 10 + f.dec
    f.cap = C.rank_cap(f.rank)
    if f.level >= f.cap then f.capped = true end
    if f.capped then f.dec, f.dec_known, f.tenths = 0, true, f.level * 10 end
    fishing = f
end

-- Inventory counts by item id (main inventory, where synth materials have to be).
local inv_counts, inv_t = {}, -1

-- Hovering an item picture shows its stats. Icons note the hovered item while
-- drawing; the card is drawn once at the end of the frame so it wins over row tips.
local tip_item = nil
local function icon_draw(dl, id, x, y, size)
    local drawn = ICON.draw(dl, id, x, y, size)
    if drawn and id and id > 0 then
        local ok, hov = pcall(imgui.IsMouseHoveringRect, { x, y }, { x + size, y + size })
        if ok and hov then tip_item = id end
    end
    return drawn
end
local function draw_item_tip()
    local id = tip_item
    tip_item = nil
    if not id then return end
    local i = item_info(id)
    if not i then return end
    imgui.BeginTooltip()
    imgui.PushTextWrapPos(imgui.GetFontSize() * 22)
    local flags = {}
    if i.rare then flags[#flags + 1] = 'Rare' end
    if i.ex then flags[#flags + 1] = 'Ex' end
    imgui.TextColored(HUD.text, i.name .. (#flags > 0 and ('  [' .. table.concat(flags, ' ') .. ']') or ''))
    if i.desc ~= '' then imgui.TextColored(HUD.subtext, i.desc) end
    for _, l in ipairs(i.lines) do imgui.TextColored(HUD.muted, l) end
    if i.stack then imgui.TextColored(HUD.faint, ('Stacks to %d'):format(i.stack)) end
    local have = inv_counts and inv_counts[id]
    if have and have > 0 then imgui.TextColored(HUD.owned, ('You have %d'):format(have)) end
    imgui.PopTextWrapPos()
    imgui.EndTooltip()
end

local function refresh_inventory(force)
    if not force and os.clock() - inv_t < 0.75 then return end
    inv_t = os.clock()
    local counts = {}
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory()
        local max = tonumber(inv:GetContainerCountMax(0)) or 80
        for i = 1, max do
            local it = inv:GetContainerItem(0, i)
            if it and it.Id and it.Id > 0 and it.Id ~= 65535 then
                counts[it.Id] = (counts[it.Id] or 0) + (tonumber(it.Count) or 1)
            end
        end
    end)
    inv_counts = counts
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function settings_file() return ('%s/crafthub_settings.lua'):format(addon.path) end

local function ser(v, ind)
    ind = ind or ''
    local t = type(v)
    if t == 'string' then return ('%q'):format(v) end
    if t ~= 'table' then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do
        local key = type(k) == 'number' and ('[%d]'):format(k) or ('[%q]'):format(k)
        parts[#parts + 1] = ind .. '  ' .. key .. ' = ' .. ser(x, ind .. '  ')
    end
    table.sort(parts)
    return '{\n' .. table.concat(parts, ',\n') .. '\n' .. ind .. '}'
end

local function save_settings()
    pcall(function()
        local f = io.open(settings_file(), 'w')
        if not f then return end
        f:write('return ' .. ser({
            tab = state.tab, craft = state.craft, mode = state.mode, mini = state.mini, follow = state.follow,
            path_all = state.path_all, rate = state.rate, modern = state.modern, tenths = state.tenths,
            amount = state.amount, server = state.server, cexi_mode = state.cexi_mode,
            gear = state.gear, kupo = state.kupo,
            fish_rate = state.fish_rate, fish_gear = state.fish_gear, fish_list = state.fish_list,
            kits = state.kits,
            win_w = state.win_size and state.win_size[1], win_h = state.win_size and state.win_size[2],
        }) .. '\n')
        f:close()
    end)
end

local function load_settings()
    local ok, d = pcall(dofile, settings_file())
    if not ok or type(d) ~= 'table' then return end
    if tonumber(d.tab) and d.tab >= 1 and d.tab <= 4 then state.tab = d.tab end
    if tonumber(d.craft) and d.craft >= 1 and d.craft <= 8 then state.craft = d.craft end
    if C.MODES[d.mode or ''] then state.mode = d.mode end
    state.mini = d.mini == true
    if d.follow ~= nil then state.follow = d.follow == true end
    state.path_all = d.path_all == true
    if d.kits ~= nil then state.kits = d.kits == true end
    if tonumber(d.rate) and d.rate > 0 then state.rate = d.rate end
    if tonumber(d.amount) and d.amount > 0 then state.amount = d.amount end
    if d.server == 'retail' or d.server == 'lsb' or d.server == 'cexi' then
        state.server = d.server
    elseif d.server == 'ace' or d.server == 'cw' or d.server == 'wew' then   -- older settings file
        state.server, d.cexi_mode = 'cexi', d.server
        state.rate, state.amount, state.modern = 1.0, 1.0, true
    elseif d.server == 'custom' then
        state.server = 'lsb'
    end
    if d.cexi_mode == 'ace' or d.cexi_mode == 'cw' or d.cexi_mode == 'wew' or d.cexi_mode == '' then state.cexi_mode = d.cexi_mode end
    if type(d.gear) == 'table' then state.gear = d.gear end
    state.kupo = d.kupo == true
    if tonumber(d.fish_rate) and d.fish_rate > 0 then state.fish_rate = d.fish_rate end
    if type(d.fish_gear) == 'table' then state.fish_gear = d.fish_gear end
    if d.fish_list == 'route' or d.fish_list == 'all' then state.fish_list = d.fish_list end
    if d.modern ~= nil then state.modern = d.modern == true end
    if type(d.tenths) == 'table' then state.tenths = d.tenths end
    if tonumber(d.win_w) and tonumber(d.win_h) then state.win_size = { d.win_w, d.win_h } end
end

-- The rules in force: a fixed preset for Retail and CEXI (plus its game mode),
-- or LSB with your own server's values.
local function rules_info()
    if state.server == 'retail' then return C.SERVERS.retail end
    if state.server == 'cexi' then return C.SERVERS[state.cexi_mode] or C.SERVERS.cexi end
    return { label = 'LSB', name = 'LandSandBoat (your settings)', rate = state.rate, amount = state.amount,
        modern = state.modern, spec_points = 40, bonus70 = 0 }
end

-- Craft skill bonuses you own / have on. Values from LandSandBoat's item and effect
-- data (torques +2, guild body and gloves +1, Kupo Shield +3, image support +1 or
-- advanced +3) and the CatsEyeXI guide (crafting stall moglification +5). They make
-- synths easier (success and HQ tier) but skill-ups still use your real skill.
local BONUS_SOURCES = {
    { key = 'mog',   label = 'Moglification (crafting stall)', short = 'Mog', value = 5 },
    { key = 'neck',  label = 'Crafting torque (neck)',         short = 'Neck', value = 2 },
    { key = 'body',  label = 'Guild apron / smock',            short = 'Body', value = 1 },
    { key = 'hands', label = 'Guild gloves',                   short = 'Gloves', value = 1 },
}
local SUPPORT = { { 0, 'NONE' }, { 1, 'BASIC +1' }, { 3, 'ADVANCED +3' } }

local function gear_for(k)
    local key = C.CRAFTS[k].key
    state.gear[key] = state.gear[key] or {}
    return state.gear[key]
end

-- Total extra skill for craft k, and a short "Mog +5, Neck +2 ..." breakdown.
local function skill_bonus(k)
    local g = state.gear[C.CRAFTS[k].key] or {}
    local total, parts = 0, {}
    for _, b in ipairs(BONUS_SOURCES) do
        if g[b.key] then total = total + b.value; parts[#parts + 1] = ('%s +%d'):format(b.short, b.value) end
    end
    if state.kupo then total = total + 3; parts[#parts + 1] = 'Kupo +3' end
    local sup = tonumber(g.support) or 0
    if sup > 0 then total = total + sup; parts[#parts + 1] = ('Support +%d'):format(sup) end
    return total, table.concat(parts, ', ')
end

-- Fishing skill from gear and the Fisherman's Stall (LandSandBoat item data: torque +2,
-- waders +2, fisherman's / angler's tunica, gloves, hose and boots +1; CatsEyeXI guide:
-- Mega Moglification: Fishing +5). Helps you land fish, not skill-ups.
local FISH_BONUS = {
    { key = 'mog',   label = 'Mega Moglification: Fishing', value = 5 },
    { key = 'torque', label = "Fisher's Torque", value = 2 },
    { key = 'body',  label = "Fisherman's / Angler's Tunica", value = 1 },
    { key = 'hands', label = "Fisherman's / Angler's Gloves", value = 1 },
    { key = 'legs',  label = "Fisherman's / Angler's Hose", value = 1 },
}
local FISH_FEET = { { 0, 'NONE' }, { 1, 'BOOTS +1' }, { 2, 'WADERS +2' } }
local function fish_bonus()
    local g, t = state.fish_gear or {}, 0
    for _, b in ipairs(FISH_BONUS) do if g[b.key] then t = t + b.value end end
    return t + (tonumber(g.feet) or 0)
end

local function apply_rules()
    local r = rules_info()
    C.rules.spec_points = r.spec_points or 40
    C.rules.bonus70 = r.bonus70 or 0
    C.rules.amount = r.amount
    C.rules.rate = r.rate
    C.rules.modern = r.modern
    C.rules.skill_bonus = {}
    for k = 1, 8 do C.rules.skill_bonus[k] = skill_bonus(k) end
    -- CatsEyeXI custom recipes and level changes only count on CEXI
    C.rules.custom = state.server == 'cexi'
    -- fishing: skill-up rate per server, gear bonus, CatsEyeXI fish levels
    FM.rules.rate = (state.server == 'cexi' and 3.0) or (state.server == 'retail' and 1.0) or state.fish_rate
    FM.rules.bonus = fish_bonus()
    for id, lv in pairs(FD.cexi_levels or {}) do
        local f = FD.fish[id]
        if f then
            f.lv_retail = f.lv_retail or f.lv
            f.lv = C.rules.custom and lv or f.lv_retail
        end
    end
    for _, rec in pairs(D.recipes) do
        if rec.lv_cexi then rec.lv = C.rules.custom and rec.lv_cexi or rec.lv_retail end
    end
end

-- server: retail / lsb / cexi; mode (CEXI only): ace / cw / wew / '' (nil keeps the current one)
local function set_server(server, mode, quiet)
    state.server = server
    if mode ~= nil then state.cexi_mode = mode end
    apply_rules()
    save_settings()
    if quiet then return end
    local r = rules_info()
    msg(('Rules: %s - skill-up chance x%s, size x%s, %s rules%s.'):format(r.name, tostring(r.rate), tostring(r.amount),
        r.modern and 'modern' or 'era', (r.spec_points or 40) >= 320 and ', every craft to 110' or ''))
end

--------------------------------------------------------------------------------
-- Packets: skill list (0x062), skill-up messages (0x029), synth results (0x06F)
--------------------------------------------------------------------------------

local function remember_decimal(k, level, dec)
    local t = char_tenths()
    if not t then return end
    t[C.CRAFTS[k].key] = { level, dec }
end

-- Decimal tracking from the chat messages. A skill-up sends "rises 0.X points" (38)
-- and, when it crosses a level, "reaches level N" (53). The two can arrive in either
-- order, and on boosted servers one skill-up can be 1.0+ points, so each message is
-- matched with its partner: the level-up never wipes a carried-over decimal
-- (34.8 + 0.4 = 35.2, not 35.0), and a rise right after a level-up isn't added twice.

local function total_of(ent) return ent and (ent[1] * 10 + ent[2]) or nil end
-- Skill after a skill-up of `amount` that reached level N. Right before it you were
-- at most (N-1).9, so the carry-over is at most amount - 0.1; if the count had run
-- ahead it's pulled back, and if it was behind it's at least N.0.
local function after_level(prev, amount, level)
    local new = prev + amount
    return math.max(level * 10, math.min(new, (level - 1) * 10 + 9 + amount))
end
local function set_total(t, key, total)
    t[key] = { math.floor(total / 10), total % 10 }
end

local function track_rise(key, amount)
    local t = char_tenths()
    if not t then return end
    local prev = total_of(t[key])
    local r = recent[key]
    if r and r.kind == 53 and os.time() - r.at <= PAIR_WINDOW then
        -- the level-up came first: it has already set level N.0
        recent[key] = nil
        if r.prev then set_total(t, key, after_level(r.prev, amount, r.level)) end
        return
    end
    if prev then set_total(t, key, prev + amount) end
    recent[key] = { kind = 38, at = os.time(), prev = prev, amount = amount }
end

local function track_level(key, level)
    local t = char_tenths()
    if not t then return end
    local r = recent[key]
    recent[key] = nil
    if r and r.kind == 38 and os.time() - r.at <= PAIR_WINDOW and r.prev then
        -- the rise came first and was already added: keep the carry-over if it agrees
        set_total(t, key, after_level(r.prev, r.amount, level))
        return
    end
    recent[key] = { kind = 53, at = os.time(), prev = total_of(t[key]), level = level }
    t[key] = { level, 0 }
end

-- The server re-sends a packet until the client acknowledges it, so the same packet
-- (same bytes, same sequence number) can reach addons more than once. Count each once.
local seen_pkts, seen_prune = {}, 0
local function duplicate(e)
    local now = os.time()
    local key = e.data
    local t = seen_pkts[key]
    seen_pkts[key] = now
    if now - seen_prune > 30 then
        for k2, v in pairs(seen_pkts) do if now - v > 30 then seen_pkts[k2] = nil end end
        seen_prune = now
    end
    return t ~= nil and now - t <= 10
end

-- /craft trace: echo every skill message crafthub reads, to check it against the chat log
local function trace(fmt, ...)
    if state.trace then msg(fmt:format(...)) end
end

ashita.events.register('packet_in', 'crafthub_packet_cb', function(e)
    if (e.id == 0x029 or e.id == 0x06F) and duplicate(e) then
        if e.id == 0x029 then trace('(ignored a re-sent copy of a message)') end
        return
    end
    if e.id == 0x06F or e.id == 0x00A then
        inv_t = -1   -- inventory changes after a synth: re-read it next frame
    end
    if e.id == 0x062 then
        -- skill_base[64] (u16) starts at 0x80; crafts are skills 49-56
        for k = 1, 8 do
            local off = 0x80 + C.CRAFTS[k].skill * 2
            local ok, v = pcall(struct.unpack, 'H', e.data, off + 1)
            if ok and v then
                local lv, rk, cap = C.decode(v)
                state.pkt[k] = { lv, rk, cap }
            end
        end
        local okf, vf = pcall(struct.unpack, 'H', e.data, 0x80 + FM.SKILL_ID * 2 + 1)
        if okf and vf then
            local lv, rk, cap = C.decode(vf)
            state.fish_pkt = { lv, rk, cap }
        end
    elseif e.id == 0x029 then
        local ok, p1, p2, mid = pcall(function()
            return struct.unpack('I', e.data, 0x0C + 1), struct.unpack('I', e.data, 0x10 + 1), struct.unpack('H', e.data, 0x18 + 1)
        end)
        if not ok then return end
        if p1 == FM.SKILL_ID then              -- fishing skill-up / level-up
            local me = nil
            pcall(function() me = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) end)
            if me and struct.unpack('I', e.data, 0x04 + 1) ~= me then return end
            if mid == 38 then
                local fs = state.fish_session
                fs.gain, fs.ups = fs.gain + p2, fs.ups + 1
                track_rise('fish', p2)
            elseif mid == 53 then
                track_level('fish', p2)
                if state.fish_pkt then state.fish_pkt[1] = p2 end
                save_settings()
            end
            return
        end
        local k = C.BY_SKILL[p1 or -1]
        if not k then return end
        -- only our own messages: caster id == our server id
        local me = nil
        pcall(function() me = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) end)
        local cas = struct.unpack('I', e.data, 0x04 + 1)
        if me and cas ~= me then return end
        local s = skills[k]
        if mid == 38 then          -- skill rises 0.X points
            local ss = state.session[k] or { gain = 0, ups = 0 }
            ss.gain, ss.ups = ss.gain + p2, ss.ups + 1
            state.session[k] = ss
            track_rise(C.CRAFTS[k].key, p2)
            do local ent = char_tenths() and char_tenths()[C.CRAFTS[k].key]
                trace('%s rises %.1f -> %s', C.CRAFTS[k].name, p2 / 10, ent and ('%d.%d'):format(ent[1], ent[2]) or 'decimal not known yet')
            end
            if state.follow then state.craft = k end
        elseif mid == 53 then      -- skill reaches level N
            track_level(C.CRAFTS[k].key, p2)
            do local ent = char_tenths() and char_tenths()[C.CRAFTS[k].key]
                trace('%s reaches level %d -> %s', C.CRAFTS[k].name, p2, ent and ('%d.%d'):format(ent[1], ent[2]) or '?') end
            if state.pkt[k] then state.pkt[k][1] = p2 end
            if state.follow then state.craft = k end
            save_settings()
        elseif mid == 310 then     -- skill drops (specialisation limit)
            local ss = state.session[k] or { gain = 0, ups = 0 }
            ss.gain = ss.gain - p2
            state.session[k] = ss
            local t = char_tenths()
            if t then t[C.CRAFTS[k].key] = nil end
        end
    elseif e.id == 0x06F then
        local ok, res = pcall(struct.unpack, 'B', e.data, 0x04 + 1)
        if ok then
            if res == 0 or res == 0x0C then state.synths.ok = state.synths.ok + 1  -- success / desynth success
            elseif res == 1 then state.synths.broke = state.synths.broke + 1 end
        end
    end
end)

--------------------------------------------------------------------------------
-- Evaluation cache (recomputed when skills / mode / rules change)
--------------------------------------------------------------------------------

local cache = { sig = nil }
local function skill_sig()
    local p = { state.mode, C.rules.rate, tostring(C.rules.modern), tostring(state.kits), C.rules.amount,
        C.rules.bonus70, C.rules.spec_points, tostring(C.rules.custom) }
    for k = 1, 8 do p[#p + 1] = C.rules.skill_bonus[k] or 0 end
    for k = 1, 8 do local s = skills[k]; p[#p + 1] = s and s.tenths or 0 end
    return table.concat(p, ':')
end

local function path_recs(k)
    local set = {}
    for _, row in ipairs(D.path[C.CRAFTS[k].key] or {}) do if row.rec then set[row.rec] = true end end
    return set
end
local PATH_SET = {}
for k = 1, 8 do PATH_SET[k] = path_recs(k) end

local BETTER_MARGIN = 1.05   -- 5% better than the guide's pick to join the path

local function rebuild()
    local sig = skill_sig()
    if cache.sig == sig then return end
    cache.sig = sig
    cache.best, cache.best_i, cache.alts, cache.kits, cache.better, cache.all = {}, {}, {}, {}, {}, {}
    for k = 1, 8 do
        local ev, i = C.best_on_path(D.path[C.CRAFTS[k].key], D.recipes, k, skills, state.mode)
        cache.best[k], cache.best_i[k] = ev, i
        -- guild kits (Lv 5-50) win when they score better than the guide's pick
        if state.kits then
            local kit = C.best_kit(BY_CRAFT[k], k, skills, state.mode)
            if kit and (not ev or C.score(kit, state.mode) > C.score(ev, state.mode)) then cache.best[k] = kit end
        end
        cache.kits[k] = C.kits(BY_CRAFT[k], k, skills)
        cache.alts[k] = C.alternatives(BY_CRAFT[k], k, skills, state.mode, 8, PATH_SET[k], false)
        -- recipes off the guide that beat its best pick right now join the path (in level
        -- order) until you out-level them; they stay in Also good either way
        local better = {}
        local ps = C.score(ev, state.mode)
        if ps > 0 then
            for _, a in ipairs(C.alternatives(BY_CRAFT[k], k, skills, state.mode, 6, PATH_SET[k], false)) do
                if a.score > ps * BETTER_MARGIN then better[#better + 1] = a end
            end
            if better[1] and C.score(better[1], state.mode) > C.score(cache.best[k], state.mode) then cache.best[k] = better[1] end
            table.sort(better, function(a, b)
                if a.level ~= b.level then return a.level < b.level end
                return a.rec.id < b.rec.id
            end)
        end
        cache.better[k] = better
        cache.all[k] = nil   -- every recipe for the craft, built when the ALL tab is opened
        -- nothing left on the guide path: use the best LSB recipe instead
        if not cache.best[k] and cache.alts[k][1] then cache.best[k] = cache.alts[k][1] end
    end
end

-- Every recipe for craft k on your server (guild kits and CatsEyeXI customs too), by level.
local function all_recipes(k)
    if cache.all[k] then return cache.all[k] end
    local out = {}
    for _, rec in ipairs(BY_CRAFT[k] or {}) do
        if C.available(rec) then out[#out + 1] = C.evaluate(rec, k, skills) end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.rec.n < b.rec.n
    end)
    cache.all[k] = out
    return out
end

local function path_row_for(rec_id, k)
    for _, row in ipairs(D.path[C.CRAFTS[k].key] or {}) do if row.rec == rec_id then return row end end
    return nil
end

local function can_make(rec)
    local n = math.huge
    local need = {}
    for _, ing in ipairs(rec.i) do need[ing[1]] = (need[ing[1]] or 0) + ing[2] end
    need[rec.c] = (need[rec.c] or 0) + 1
    for id, q in pairs(need) do n = math.min(n, math.floor((inv_counts[id] or 0) / q)) end
    return n == math.huge and 0 or n
end

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------

local function pct(x) return ('%d%%'):format(math.floor(x * 100 + 0.5)) end
-- Small percentages keep a decimal (HQ odds: 1.6%, 0.4% ...).
local function pct2(x)
    local v = x * 100
    if v <= 0 then return '0%' end
    if v < 10 then return ('%.1f%%'):format(v) end
    return ('%d%%'):format(math.floor(v + 0.5))
end
local function hq_label(ev)
    if not ev.attempt or ev.hq_tier == 0 then
        return ev.attempt and ('none - %d below the recipe'):format(math.max(1, ev.d_eff or ev.d)) or '-'
    end
    return ('%s  \194\183  tier %d (%s)'):format(pct2(ev.hq), ev.hq_tier, C.HQ_RANGE[ev.hq_tier])
end
local function pts(tenths) return ('%.1f'):format(tenths / 10) end
-- A skill as shown everywhere: 34.6 when the decimal is known, 34.? until it is.
local function lvl_text(s)
    if s.dec_known then return pts(s.tenths) end
    return s.level > 0 and (tostring(s.level) .. '.?') or tostring(s.level)
end
local function per_synth(ev) return ev.gain > 0 and ('+%.3f'):format(ev.gain / 10) or '-' end

local function diff_label(d)
    if d > 0 then return ('%d above you'):format(d) end
    if d == 0 then return 'at your level' end
    return ('%d below you'):format(-d)
end

local function diff_color(d)
    if d >= 6 then return HUD.bad end
    if d >= 4 then return HUD.warn end
    if d >= 1 then return HUD.owned end
    return HUD.blue
end

local function success_color(s)
    if s >= 0.85 then return HUD.owned end
    if s >= 0.65 then return HUD.yellow end
    if s >= 0.45 then return HUD.warn end
    return HUD.bad
end

-- Word-wrapped text; returns height used.
-- Big number and small label centred inside a ring, kept clear of its stroke.
local function ring_label(cx, cy, R, TH, big, lbl)
    local lh = line_h()
    local inner = (R - TH * 0.5 - 6) * 2          -- room inside the stroke
    local sp = 1.5
    if T.caps_w(lbl, sp) > inner then sp = 0.5 end
    local bh, gap, ch = lh * 1.5, 1, lh * 0.82
    local top = cy - (bh + gap + ch) * 0.5
    text(cx - text_w(big) * 1.5 * 0.5, top, HUD.text, big, 1.5)
    T.caps(cx - T.caps_w(lbl, sp) * 0.5, top + bh + gap, HUD.faint, lbl, sp)
end

local function wrap(x, y, w, c, s)
    local lh = line_h()
    local line, yy = '', y
    for word in s:gmatch('%S+') do
        local try = line == '' and word or (line .. ' ' .. word)
        if text_w(try) > w and line ~= '' then
            text(x, yy, c, line); yy = yy + lh + 2; line = word
        else
            line = try
        end
    end
    if line ~= '' then text(x, yy, c, line); yy = yy + lh + 2 end
    return yy - y
end

-- Small stat tile: label on top, value below. Returns its width.
local function stat(x, y, w, label, value, c)
    local lh = line_h()
    T.frame(x, y, w, lh * 2 + 14, { fill = HUD.inset, k = 5 })
    text(x + 10, y + 6, HUD.faint, label)
    text(x + 10, y + 8 + lh, c or HUD.text, value)
    return w
end

local function craft_dot_color(k)
    local s = skills[k]
    if not s then return HUD.faint end
    if s.capped then return HUD.warn end
    if s.level >= s.cap - 2 then return HUD.gold end
    return nil
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------

local function search_box(x, y, w)
    local lh = line_h()
    local h = lh + 10
    local cx, cy = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ x, y })
    imgui.PushStyleColor(ImGuiCol_FrameBg, HUD.inset)
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, HUD.inset)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, HUD.inset)
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 28, 5 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 6)
    imgui.PushItemWidth(w - 24)
    imgui.InputText('##ch_search', state.search, 64)
    local active = imgui.IsItemActive()
    imgui.PopItemWidth()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(3)
    imgui.SetCursorScreenPos({ cx, cy })
    local dl = DL()
    local q = state.search[1] or ''
    dl:AddRectFilled({ x + w - 26, y }, { x + w, y + h }, col(HUD.inset), 6)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + w - 0.5, y + h - 0.5 }, col(HUD.edge, active and 0.8 or 0.25), 6, CORNERS_ALL, 1)
    if active then T.chamfer_line(x - 1, y - 1, w + 2, h + 2, 7, col(HUD.edge, 0.12), 3) end
    local my = y + h * 0.5
    local mc = (active or q ~= '') and HUD.accent or HUD.muted
    dl:AddCircle({ x + 13, my - 1 }, 4.5, col(mc), 12, 1.4)
    dl:AddLine({ x + 16, my + 2 }, { x + 19.5, my + 5.5 }, col(mc), 1.6)
    if q == '' and not active then text(x + 28, y + 5, HUD.faint, 'Search all recipes...') end
    if q ~= '' then
        local bx = x + w - 22
        local clicked, hov = hit('##ch_search_clear', bx, y + 3, 18, h - 6)
        local c = hov and HUD.text or HUD.muted
        dl:AddLine({ bx + 5, my - 4 }, { bx + 13, my + 4 }, col(c), 1.5)
        dl:AddLine({ bx + 13, my - 4 }, { bx + 5, my + 4 }, col(c), 1.5)
        if clicked then state.search[1] = '' end
    end
end

-- Ghost gear button (settings). Returns true when clicked.
local function gear_button(x, y, s, on)
    local dl = DL()
    local clicked, hov = hit('##ch_gear', x, y, s, s)
    local cx, cy = math.floor(x + s * 0.5) + 0.5, math.floor(y + s * 0.5) + 0.5   -- pixel-snapped centre
    if hov or on then dl:AddCircleFilled({ cx, cy }, s * 0.5, col(on and HUD.accent or { 1, 1, 1, 1 }, on and 0.18 or 0.06), 32) end
    local c = col(on and HUD.accent or (hov and HUD.text or HUD.muted))
    -- a real gear: a thick ring (open in the middle) with 8 flat, slightly tapered teeth
    local rr, rt = s * 0.20, s * 0.15             -- ring radius (middle of the stroke), stroke width
    local ri, ro = s * 0.22, s * 0.37             -- teeth run from inside the ring out to here
    local wi, wo = s * 0.10, s * 0.075            -- teeth half-width at the base / at the tip
    dl:AddCircle({ cx, cy }, rr, c, 24, rt)
    for i = 0, 7 do
        local a = i * math.pi / 4 + math.pi / 8
        local dx, dy = math.cos(a), math.sin(a)
        local px, py = -dy, dx
        local il = { cx + dx * ri - px * wi, cy + dy * ri - py * wi }
        local ir = { cx + dx * ri + px * wi, cy + dy * ri + py * wi }
        local orr = { cx + dx * ro + px * wo, cy + dy * ro + py * wo }
        local ol = { cx + dx * ro - px * wo, cy + dy * ro - py * wo }
        -- one shape per tooth (two triangles leave a faint seam down the middle)
        if not pcall(function() dl:AddQuadFilled(il, ol, orr, ir, c) end) then
            dl:AddTriangleFilled(il, ol, orr, c)
            dl:AddTriangleFilled(il, orr, ir, c)
        end
    end
    if hov then imgui.SetTooltip('Settings') end
    return clicked
end

local TITLE = 'CRAFT HUB'

-- Header: title, the three screens as one segmented switch, search, session,
-- settings and close on one row; who / craft / rules on a quiet line under it.
local function render_header()
    local lh = line_h()
    local nav = {
        { 2, 'BEST SYNTH' },
        { 3, 'RECIPES' },
        { 4, 'FISHING', tostring(fishing.level) },
    }
    band('ch_hdr', function(x, y, w)
        local nav_w = seg_width(nav, false)
        local nav_h = lh + 8 + 6
        local row_h = math.max(math.floor(lh * 1.4 + 6), nav_h)
        T.title_text(x, y, row_h, TITLE, HUD.text)
        local title_w = T.title_w(TITLE)
        local nx = x + title_w + 18
        local active = state.settings and 0 or (state.tab == 1 and 2 or state.tab)
        local picked = seg_tabs('ch_tab', nav, active, nx, y + (row_h - nav_h) * 0.5, HUD.accent, false)
        if picked and (picked ~= state.tab or state.settings) then
            state.tab, state.settings = picked, false
            state.search[1] = ''
            save_settings()
        end
        local bs = lh + 6
        local bx = x + w - bs
        if T.close_button(bx, y + (row_h - bs) * 0.5, bs) then state.visible[1] = false end
        local gx = bx - bs - 4
        if gear_button(gx, y + (row_h - bs) * 0.5, bs, state.settings) then state.settings = not state.settings end
        -- session pill (skill gained / synths this session)
        local right = gx - 10
        local total = 0
        for k = 1, 8 do total = total + ((state.session[k] and state.session[k].gain) or 0) end
        local synths = state.synths.ok + state.synths.broke
        if synths > 0 or total ~= 0 then
            local a, b = ('+%s'):format(pts(total)), ('%d synths'):format(synths)
            local pw = T.dot_pill_w(a, b)
            right = right - pw
            T.dot_pill(nil, right, y + (row_h - (lh + 8)) * 0.5, a, HUD.owned, b, HUD.muted, true)
            right = right - 10
        end
        -- search: in the top row when it fits, otherwise at the right of the second row
        -- (it never disappears, e.g. when the session pill takes the room)
        local sx0 = nx + nav_w + 16
        local sw = math.min(280, right - sx0)
        local search_row2 = sw < 160
        if not search_row2 then search_box(right - sw, y + (row_h - (lh + 10)) * 0.5, sw) end

        -- row 2: who, focused craft, rules
        local iy = y + row_h + 4
        local row2_h = lh
        local info_w = w
        if search_row2 then
            local sw2 = math.max(160, math.min(280, math.floor(w * 0.45)))
            row2_h = lh + 10
            search_box(x + w - sw2, iy, sw2)
            info_w = w - sw2 - 12
            iy = iy + 5
        end
        local who = player_name()
        if who then
            local wn = fit(who, info_w)
            text(x, iy, HUD.subtext, wn)
            local s = skills[state.craft]
            local r = rules_info()
            local info = ('  \194\183  %s %s  \194\183  %s: %s, rate x%s, size x%s'):format(C.CRAFTS[state.craft].name,
                s and lvl_text(s) or '?', r.label,
                r.modern and 'modern' or 'era', tostring(r.rate), tostring(r.amount))
            local left = info_w - text_w(wn)
            if left > 20 then text(x + text_w(wn), iy, HUD.faint, fit(info, left)) end
        else
            text(x, iy, HUD.faint, 'Not logged in')
        end
        ui.header_need = title_w + 18 + nav_w + bs * 2 + 18
        return (y + row_h + 4) + row2_h - y + 4
    end, { line = true })
end

-- Craft cards: all eight crafts at a glance (level, progress to the next cap,
-- rank-test state). Click one to focus it. Eight across, or two rows of four
-- when the window is narrow.
local function render_craft_picker()
    band('ch_crafts', function(x, y, w)
        local lh = line_h()
        local dl = DL()
        local gap = 6
        local cols = w >= 620 and 8 or 4
        local cw = (w - gap * (cols - 1)) / cols
        local ch = math.floor(lh * 0.85 + lh * 1.3 + 26)
        for k = 1, 8 do
            local ci, ri = (k - 1) % cols, math.floor((k - 1) / cols)
            local cx, cy = math.floor(x + ci * (cw + gap)), math.floor(y + ri * (ch + gap))
            local cwi = math.floor(cw)
            local s, c = skills[k], C.CRAFTS[k]
            local on = state.craft == k
            local clicked, hov = hit(('##ch_cc%d'):format(k), cx, cy, cwi, ch)
            if clicked and not on then state.craft = k; state.pin = nil; save_settings() end
            -- hover lifts the tile 2px (eased), its shadow growing under it
            local lift = T.ease('ch_lift' .. k, (hov or on) and 1 or 0, 12)
            cy = cy - math.floor(lift * 2 + 0.5)
            T.shadow(cx, cy, cwi, ch, 12, 0.55 + lift * 0.6)
            -- glass tile (as the /yui cards): dark see-through fill, soft edge, top light;
            -- the chosen craft gets a periwinkle wash and edge
            T.chamfer_fill(cx, cy, cwi, ch, 12, col(HUD.card))
            if on then T.chamfer_fill(cx, cy, cwi, ch, 12, col(HUD.card_on))
            elseif hov then T.chamfer_fill(cx, cy, cwi, ch, 12, col({ 1, 1, 1, 0.04 })) end
            T.chamfer_line(cx + 0.5, cy + 0.5, cwi - 1, ch - 1, 12,
                on and col(HUD.accent, 0.70) or col(HUD.edge, hov and 0.14 or 0.07), 1)
            dl:AddLine({ cx + 12, cy + 1 }, { cx + cwi - 12, cy + 1 }, col({ 1, 1, 1, on and 0.30 or 0.11 }), 1)
            local px = cx + 10
            T.caps(px, cy + 8, on and HUD.accent2 or HUD.muted, c.short:upper(), 1.2)
            -- state dot: gold = rank test open, orange = capped
            local st = s and (s.capped and HUD.warn or (s.level >= s.cap - 2 and HUD.gold or nil))
            if st then dot(cx + cwi - 11, cy + 8 + lh * 0.42, 3, st, on and 0.6 or 0) end
            local lv = s and lvl_text(s) or '-'
            local ly = cy + 8 + math.floor(lh * 0.85) + 2
            text(px, ly, on and { 1, 1, 1, 1 } or HUD.text, lv, 1.3)
            if s then
                local capt = ('/ %d'):format(s.cap)
                text(px + text_w(lv) * 1.3 + 5, ly + lh * 0.3, HUD.faint, capt, 0.85)
                local frac = T.ease('ch_bar' .. k, (s.tenths - (s.cap - 10) * 10) / 100, 5)
                bar(px, cy + ch - 10, cwi - 20, 3, frac, s.capped and HUD.warn or (st and HUD.gold or HUD.accent))
                -- the item this craft's best synth makes, small on the right (a face for each craft)
                local be = cache.best[k]
                local isz = math.floor(lh * 1.35)
                if be and cwi >= 90 then
                    icon_draw(dl, be.rec.r, cx + cwi - isz - 9, cy + ch - isz - 15, isz)
                end
            end
            if hov and s then
                local be = cache.best[k]
                imgui.SetTooltip(('%s  -  %s, cap %d%s\n%s'):format(c.name, C.rank_name(s.rank), s.cap,
                    s.capped and '  (capped)' or (st and '  (rank test open)' or ''),
                    be and ('Best now: %s (Lv %d)'):format(be.rec.n, be.level) or 'No skill-ups available right now.'))
            end
        end
        ui.picker_need = 0
        local rows = math.ceil(8 / cols)
        return rows * ch + (rows - 1) * gap
    end)
end

--------------------------------------------------------------------------------
-- Recipe detail (used by the BEST SYNTH tab and the mini window's tooltip)
--------------------------------------------------------------------------------

local function draw_ingredients(x, y, w, rec)
    local lh = line_h()
    local yy = y
    local rows = { { rec.c, 1, true } }
    for _, ing in ipairs(rec.i) do rows[#rows + 1] = { ing[1], ing[2], false } end
    local colw = math.floor((w - 12) / 2)
    for i, r in ipairs(rows) do
        local cx = x + ((i - 1) % 2) * (colw + 12)
        local id, need, crystal = r[1], r[2], r[3]
        local have = inv_counts[id] or 0
        local ok = have >= need
        local isz = lh + 2
        if not icon_draw(DL(), id, cx - 1, yy - 1, isz) then
            if crystal then
                dot(cx + 5, yy + lh * 0.5, 4, ELEMENT_COLOR[id] or HUD.accent, 0.3)
            else
                dot(cx + 5, yy + lh * 0.5, 3, ok and HUD.owned or HUD.faint)
            end
        end
        -- name, then "have / need" on the right (have in green or red, need quiet)
        local nd = (' / %d'):format(need)
        local hv = tostring(have)
        text(cx + 22, yy, HUD.text, fit(item_name(id), colw - 22 - text_w('9999 / 99') - 10))
        rtext(cx + colw, yy, HUD.faint, nd)
        rtext(cx + colw - text_w(nd), yy, ok and HUD.owned or HUD.bad, hv)
        if i % 2 == 0 or i == #rows then yy = yy + lh + 6 end
    end
    return yy - y
end

-- The best-synth card: a success ring on the left, the recipe and its odds to the
-- right of it, then the ingredients (have / need) and the main button.
-- Returns the height used.
local function draw_detail(x, y, w, ev, tag, tag_col, pinned)
    local lh = line_h()
    local rec, k = ev.rec, ev.craft
    local dl = DL()

    -- success ring
    local R, TH = math.floor(lh * 2.6), 7
    local cx, cy = x + R + TH * 0.5, y + R + TH * 0.5 + 2
    local sc = ev.attempt and success_color(ev.success) or HUD.bad
    -- the ring fills up (and the number counts) when the synth changes
    local sv = T.ease('ch_ring', ev.attempt and ev.success or 0, 6)
    T.ring(cx, cy, R, TH, sv, sc)
    local big = ev.attempt and pct(sv) or '-'
    ring_label(cx, cy, R, TH, big, ev.attempt and 'SUCCESS' or 'TOO HARD')

    -- recipe + odds, right of the ring
    local tx = x + R * 2 + TH + 18
    local tw = x + w - tx
    local ty = y + 2
    local isz = 36
    local has_icon = icon_draw(dl, rec.r, x + w - isz, y + 2, isz)
    if has_icon then
        T.chamfer_line(x + w - isz - 0.5, y + 1.5, isz + 1, isz + 1, 6, col(HUD.edge, 0.16), 1)
    end
    local nw = tw - (has_icon and (isz + 10) or 0)
    pill(tx, ty, tag, tag_col or HUD.accent, 0.14)
    ty = ty + lh + 4
    text(tx, ty, HUD.text, fit(rec.n, nw, 1.3), 1.3)
    ty = ty + math.floor(lh * 1.3) + 3
    local dlbl = diff_label(ev.d)
    text(tx, ty, diff_color(ev.d), dlbl)
    local meta = ('  \194\183  Lv %d%s%s'):format(ev.level, rec.q and rec.q > 1 and ('  \194\183  makes ' .. rec.q) or '',
        (ev.bonus or 0) > 0 and ('  \194\183  +%d skill'):format(ev.bonus) or '')
    text(tx + text_w(dlbl), ty, HUD.muted, fit(meta, tw - text_w(dlbl)))
    ty = ty + lh + 12
    local vx = tx + math.max(text_w('Synths per level'), 100) + 16
    local stats = {
        { 'Skill-up chance', pct(ev.chance), ev.chance > 0 and HUD.text or HUD.bad },
        { 'Per synth', per_synth(ev), ev.gain > 0 and HUD.owned or HUD.bad },
        { 'Synths per level', ev.per_level and ('~%d'):format(math.ceil(ev.per_level)) or '-', HUD.text },
        { 'HQ chance', hq_label(ev), ev.hq > 0 and HUD.gold or HUD.faint },
    }
    for _, s in ipairs(stats) do
        text(tx, ty, HUD.faint, s[1])
        text(vx, ty, s[3], fit(s[2], x + w - vx))
        ty = ty + lh + 5
    end
    -- HQ1 / HQ2 / HQ3 split when the tier can upgrade
    if ev.hq > 0 and ev.hq_tier >= 2 then
        local parts = { ('HQ1 %s'):format(pct2(ev.hq1)), ('HQ2 %s'):format(pct2(ev.hq2)) }
        if ev.hq_tier >= 3 then parts[#parts + 1] = ('HQ3 %s'):format(pct2(ev.hq3)) end
        text(vx, ty - 2, HUD.muted, fit(table.concat(parts, '  \194\183  '), x + w - vx))
        ty = ty + lh + 3
    end
    local yy = math.max(cy + R + TH * 0.5, ty) + 12

    -- sub-crafts this recipe also needs
    if #ev.subs > 0 then
        local sx = x
        T.caps(sx, yy + 1, HUD.faint, 'SUB-CRAFTS'); sx = sx + T.caps_w('SUB-CRAFTS') + 10
        for _, s in ipairs(ev.subs) do
            local label = ('%s %d (you %d)'):format(C.CRAFTS[s.craft].short, s.need, s.have)
            sx = sx + pill(sx, yy, label, s.ok and HUD.owned or HUD.warn) + 6
        end
        yy = yy + lh + 10
    end

    -- ingredients
    T.rule(x, yy, w); yy = yy + 10
    T.caps(x, yy + 1, HUD.faint, 'INGREDIENTS')
    local cm = can_make(rec)
    local note = cm > 0 and ('can make %d now'):format(cm) or 'not enough in your inventory'
    local room = w - T.caps_w('INGREDIENTS') - 12
    if text_w(note) > room then note = cm > 0 and ('x%d now'):format(cm) or 'not enough' end
    rtext(x + w, yy, cm > 0 and HUD.owned or HUD.faint, fit(note, room))
    yy = yy + lh + 8
    yy = yy + draw_ingredients(x, yy, w, rec)
    yy = yy + 6

    -- Unpin when a recipe is pinned
    if pinned then
        local uw = T.ghost_w('Unpin')
        local clicked, _, bh = T.ghost('##ch_unpin', x + w - uw, yy, 'Unpin')
        if clicked then state.pin = nil end
        yy = yy + (bh or (lh + 10)) + 4
    end

    -- guide note
    local row = ev.row or path_row_for(rec.id, k)
    local note = (row and row.note and row.note ~= '' and row.note)
        or (rec.cexi and ('CatsEyeXI custom recipe (%s).%s'):format(rec.sec or 'custom', rec.note and (' ' .. rec.note) or ''))
    if note then
        yy = yy + 6
        T.rule(x, yy, w); yy = yy + 10
        yy = yy + wrap(x, yy, w, HUD.subtext, note)
    end
    return yy - y
end

--------------------------------------------------------------------------------
-- Rank / test panel
--------------------------------------------------------------------------------

local function draw_rank(x, y, w, k)
    local lh = line_h()
    local s = skills[k]
    local c = C.CRAFTS[k]
    local yy = y
    local rn = C.rank_name(s.rank)
    T.heading(x, yy, c.name, rn, s.capped and HUD.warn or nil)
    local lv = lvl_text(s)
    rtext(x + w, yy, HUD.text, ('%s / %d'):format(lv, s.cap))
    yy = yy + lh + 6
    local base = s.cap - 10
    bar(x, yy, w, 5, T.ease('ch_rank' .. k, (s.tenths - base * 10) / 100, 5), s.capped and HUD.warn or HUD.accent)
    yy = yy + 5 + 10
    local test = C.TEST_ITEMS[c.key] and C.TEST_ITEMS[c.key][s.cap]
    if s.capped then
        pill(x, yy, 'CAPPED', HUD.warn, 0.18)
        local t = test and ('Trade %s to the guild master to rank up.'):format(test)
            or 'Trade the guild\'s test item to the guild master to rank up.'
        yy = yy + wrap(x + pill_w('CAPPED') + 10, yy, w - pill_w('CAPPED') - 10, HUD.text, t)
        yy = yy + wrap(x, yy, w, HUD.muted, C.GUILDS[c.key] or '')
    elseif s.level >= s.cap - 2 then
        pill(x, yy, 'TEST OPEN', HUD.gold, 0.18)
        local t = test and ('You can take the rank test now: %s.'):format(test) or 'You can take the rank test now.'
        yy = yy + wrap(x + pill_w('TEST OPEN') + 10, yy, w - pill_w('TEST OPEN') - 10, HUD.text, t)
        yy = yy + wrap(x, yy, w, HUD.muted, C.GUILDS[c.key] or '')
    else
        local t = test and ('Next test at %d: %s'):format(s.cap - 2, test) or ('Next rank test from %d.'):format(s.cap - 2)
        text(x, yy, HUD.muted, t)
        yy = yy + lh + 2
    end
    if not s.dec_known and s.level > 0 then
        yy = yy + 2
        yy = yy + wrap(x, yy, w, HUD.faint, 'Decimal unknown until your next level-up message; crafthub tracks it from then on.')
    end
    local ss = state.session[k]
    if ss and ss.ups > 0 then
        yy = yy + 2
        text(x, yy, HUD.owned, ('This session: +%s from %d skill-ups'):format(pts(ss.gain), ss.ups))
        yy = yy + lh + 2
    end
    return yy - y
end

--------------------------------------------------------------------------------
-- Recipe rows (path / alternatives / recipe list)
--------------------------------------------------------------------------------

-- Header for a recipe table. cols = { {label, x_offset, align} }
-- Column right edges (from the row's right side). ui.compact_rows (set by the
-- dashboard's narrow list card) drops the HAVE column and packs the rest.
local ROW_COLS = {
    full    = { lv = 250, su = 170, ps = 82, hv = 0 },
    compact = { lv = 150, su = 86, ps = 0 },
}

local function row_head(x, y, w)
    local lh = line_h()
    local cy = y + lh * 0.1
    local rc = ui.compact_rows and ROW_COLS.compact or ROW_COLS.full
    T.caps(x + lh + 9, cy, HUD.faint, 'RECIPE')
    for _, c in ipairs({ { rc.lv, 'LV' }, { rc.su, 'SUCCESS' }, { rc.ps, 'PER SYNTH' }, { rc.hv, 'HAVE' } }) do
        if c[1] then T.caps(x + w - c[1] - T.caps_w(c[2]), cy, HUD.faint, c[2]) end
    end
    T.rule(x - 6, y + lh + 3, w + 12)
    return lh + 8
end

-- One clickable recipe row. state: 'done' | 'best' | 'pin' | nil
local function recipe_row(id, x, y, w, ev, rowstate, extra_pill)
    local dl = DL()
    local lh = line_h()
    local h = lh + 6
    local clicked, hov = hit(id, x - 6, y - 3, w + 12, h)
    if rowstate == 'best' or rowstate == 'pin' then
        dl:AddRectFilled({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.10), 5)
        dl:AddRect({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.35), 5, CORNERS_ALL, 1)
    elseif hov then
        dl:AddRectFilled({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.07), 5)   -- soft periwinkle hover (glass)
        dl:AddRect({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.18), 5, CORNERS_ALL, 1)
    end
    local dim = rowstate == 'done'
    local dc = dim and HUD.faint or (ev.can_skill and diff_color(ev.d) or HUD.faint)
    local glow = rowstate == 'best' and (0.4 + pulse(2) * 0.6) or 0
    if icon_draw(dl, ev.rec.r, x - 1, y - 2, lh + 3) then
        dot(x + lh, y + lh - 1, 3, dc, glow)          -- difficulty badge on the icon's corner
    else
        dot(x + 6, y + lh * 0.5, 3.5, dc, glow)
    end
    local name = ev.rec.n
    local rc = ui.compact_rows and ROW_COLS.compact or ROW_COLS.full
    local nx = x + lh + 9
    local name_w = w - rc.lv - 30 - (nx - x)
    local sub_pill = nil
    for _, s in ipairs(ev.subs) do
        if not s.ok then sub_pill = ('%s %d'):format(C.CRAFTS[s.craft].short, s.need); break end
    end
    if extra_pill then name_w = name_w - pill_w(extra_pill) - 8 end
    if sub_pill and not dim then name_w = name_w - pill_w(sub_pill) - 8 end
    local shown = fit(name, name_w)
    text(nx, y, dim and HUD.faint or HUD.text, shown)
    local px = nx + text_w(shown) + 8
    if extra_pill then px = px + pill(px, y, extra_pill, HUD.accent2) + 6 end
    if sub_pill and not dim then pill(px, y, sub_pill, HUD.warn) end
    rtext(x + w - rc.lv, y, dim and HUD.faint or HUD.subtext, tostring(ev.level))
    rtext(x + w - rc.su, y, dim and HUD.faint or success_color(ev.success), ev.attempt and pct(ev.success) or '-')
    rtext(x + w - rc.ps, y, dim and HUD.faint or (ev.gain > 0 and HUD.owned or HUD.faint), per_synth(ev))
    if rc.hv then
        local cm = can_make(ev.rec)
        rtext(x + w - rc.hv, y, cm > 0 and HUD.owned or HUD.faint, tostring(cm))
    end
    if hov then
        local subs = {}
        for _, s in ipairs(ev.subs) do subs[#subs + 1] = ('%s %d (you %d)'):format(C.CRAFTS[s.craft].name, s.need, s.have) end
        local ings = {}
        for _, ing in ipairs(ev.rec.i) do ings[#ings + 1] = ('%dx %s'):format(ing[2], item_name(ing[1])) end
        imgui.SetTooltip(('%s  (Lv %d, %s)\n%s: %s%s\nSkill-up chance %s  -  ~%s synths per level\nClick to pin it at the top.'):format(
            ev.rec.n, ev.level, diff_label(ev.d), item_name(ev.rec.c), table.concat(ings, ', '),
            #subs > 0 and ('\nSub-crafts: ' .. table.concat(subs, ', ')) or '',
            pct(ev.chance), ev.per_level and tostring(math.ceil(ev.per_level)) or '-'))
    end
    return clicked, h + 2
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

-- The ALL tab: a scrolling list of every recipe, opened at your level.
local function draw_all_list(x, y, w, k, top, card_y)
    local lh = line_h()
    local rows = all_recipes(k)
    local rh = lh + 8                              -- recipe_row height + gap
    -- side by side: fill down to the bottom of the best-synth card; stacked: a fixed height
    local vh = ui.compact_rows and math.max(rh * 12, (ui.h.ch_dl or 280) - 36 - (y - card_y)) or rh * 14
    local lv = skills[k].level
    imgui.SetCursorScreenPos({ x - 8, y })
    imgui.BeginChild('##ch_all', { w + 16, vh }, false)
    if ui.all_jump ~= k then                       -- open at your level the first time
        local first = 1
        for i, e in ipairs(rows) do if e.level >= lv - 3 then first = i; break end end
        imgui.SetScrollY((first - 1) * rh)
        ui.all_jump = k
    end
    local cx, cy = imgui.GetCursorScreenPos()
    local sy = imgui.GetScrollY() or 0
    local i0 = math.max(1, math.floor(sy / rh))
    local i1 = math.min(#rows, i0 + math.ceil(vh / rh) + 2)
    local rx, rw = cx + 8, w - (#rows * rh > vh and 6 or 0)
    for i = i0, i1 do
        local e = rows[i]
        local id = e.rec.id
        local done = e.level <= lv - 11
        local st = (state.pin == id and 'pin') or (top(e) and not state.pin and 'best') or (done and 'done') or nil
        local tag = (top(e) and 'BEST') or (e.rec.cexi and 'CEXI') or (e.rec.kit and 'KIT')
            or (PATH_SET[k][id] and 'GUIDE') or nil
        local c = recipe_row(('##all%d'):format(i), rx, cy + 3 + (i - 1) * rh, rw, e, st, tag)
        if c then state.pin = (state.pin == id) and nil or id end
    end
    imgui.SetCursorScreenPos({ cx, cy })
    imgui.Dummy({ w, #rows * rh + 4 })
    imgui.EndChild()
    return vh + 6
end

local function select_craft_tab(k)
    state.craft = k
    state.tab = 2
    state.pin = nil
    save_settings()
end

-- OVERVIEW: one card per craft with the best synth right now.
local function render_overview()
    local lh = line_h()
    -- summary band
    band('ch_ov_sum', function(x, y, w)
        -- which rules are in force (changed in settings)
        local r = rules_info()
        local sw = pill(x, y, r.label, HUD.accent2) + 0
        local th = lh
        local ty = y
        local s
        if C.rules.spec_points >= 320 then
            s = 'Every craft can reach 110.'
        else
            s = ('Main craft to 110, others to %d  \194\183  %d / %d points above %d used'):format(
                C.rules.common_cap, C.spec_used(skills), C.rules.spec_points, C.rules.common_cap)
        end
        local b = C.success_bonus(skills)
        if b > 0 then s = s .. ('  \194\183  +%d%% success (crafts at 70+)'):format(b) end
        text(x + sw + 14, ty, HUD.muted, s)
        ui.ov_need = sw + 14 + text_w(s)
        return th
    end)

    local x0, y0 = imgui.GetCursorScreenPos()
    local w = avail_w()
    local gap = 8
    local cols = w >= 900 and 4 or (w >= 560 and 2 or 1)
    local cw = math.floor((w - gap * (cols - 1)) / cols)
    local ch = lh * 6 + 46
    for k = 1, 8 do
        local ci = (k - 1) % cols
        local ri = math.floor((k - 1) / cols)
        local x, y = x0 + ci * (cw + gap), y0 + ri * (ch + gap)
        local s = skills[k]
        local c = C.CRAFTS[k]
        local ev = cache.best[k]
        local ec = ev and ELEMENT_COLOR[ev.rec.c] or nil
        local accent = s.capped and HUD.warn or (state.craft == k and HUD.accent or ec)
        card_bg(x, y, cw, ch, accent, state.craft == k and 0.9 or 0.35)
        local clicked, hov = hit(('##ov%d'):format(k), x, y, cw, ch)
        if hov then DL():AddRectFilled({ x, y }, { x + cw, y + ch }, col(HUD.accent, 0.06), 6) end
        if clicked then select_craft_tab(k) end
        local clip = T.push_clip(x, y, x + cw, y + ch)
        if ec and clip then T.glow(x + cw - 30, y + ch - 34, 60, ec, 0.8) end
        local px, py, pw = x + 12, y + 10, cw - 24
        T.crystal(px + 5, py + lh * 0.5, 8, 15, ec or HUD.faint, { hollow = ec == nil })
        text(px + 16, py, state.craft == k and HUD.accent2 or HUD.text, c.name)
        local lv = lvl_text(s)
        rtext(px + pw, py, HUD.text, lv)
        py = py + lh + 4
        text(px, py, HUD.muted, ('%s  \194\183  cap %d'):format(C.rank_name(s.rank), s.cap))
        if s.capped then
            rtext(px + pw, py, HUD.warn, 'CAPPED')
        elseif s.level >= s.cap - 2 then
            rtext(px + pw, py, HUD.gold, 'TEST OPEN')
        end
        py = py + lh + 6
        bar(px, py, pw, 4, (s.tenths - (s.cap - 10) * 10) / 100, s.capped and HUD.warn or HUD.accent)
        py = py + 4 + 10
        if ev then
            text(px, py, HUD.faint, 'BEST NOW')
            py = py + lh + 2
            local isz = lh * 2 + 2
            local ox = icon_draw(DL(), ev.rec.r, px, py, isz) and (isz + 8) or 0
            text(px + ox, py, HUD.text, fit(ev.rec.n, pw - 50 - ox))
            rtext(px + pw, py, HUD.subtext, ('Lv %d'):format(ev.level))
            py = py + lh + 2
            text(px + ox, py, success_color(ev.success), pct(ev.success))
            text(px + ox + text_w(pct(ev.success)), py, HUD.muted, (' success  \194\183  %s / synth'):format(per_synth(ev)))
        elseif s.capped then
            text(px, py, HUD.warn, 'Take the rank test first.')
            local test = C.TEST_ITEMS[c.key] and C.TEST_ITEMS[c.key][s.cap]
            if test then py = py + lh + 2; text(px, py, HUD.muted, fit('Test item: ' .. test, pw)) end
        else
            text(px, py, HUD.faint, 'No skill-ups available.')
        end
        T.pop_clip(clip)
    end
    local rows = math.ceil(8 / cols)
    imgui.SetCursorScreenPos({ x0, y0 })
    advance(w, rows * ch + (rows - 1) * gap)
    imgui.Dummy({ 0, 2 })
end

-- For a guild-kit synth, the normal recipe for the same item (and the other way
-- round): the best-scoring one for this craft, evaluated, or nil.
local function counterpart(ev)
    local rec, k = ev.rec, ev.craft
    local best, bs = nil, -math.huge
    for _, o in ipairs(BY_RESULT[rec.r] or {}) do
        if not C.available(o) then goto continue end
        if o.id ~= rec.id and (o.kit or false) ~= (rec.kit or false) and (o.lv[k] or 0) > 0 then
            local e = C.evaluate(o, k, skills)
            local sc = e and (C.score(e, state.mode) + (e.success or 0) * 0.001) or -math.huge
            if sc > bs then best, bs = e, sc end
        end
        ::continue::
    end
    return best
end

-- Draws the counterpart under the best / pinned synth. Returns the height used.
local function draw_counterpart(x, y, w, ev)
    local other = counterpart(ev)
    if not other then return 0 end
    local lh = line_h()
    local yy = y + 4
    T.rule(x, yy, w); yy = yy + 10
    local title = other.rec.kit and 'ALSO WITH A GUILD KIT' or 'ALSO WITHOUT A KIT (normal recipe)'
    text(x, yy, HUD.faint, title)
    yy = yy + lh + 6
    -- name + stats: laid out left to right, wrapping onto new lines inside the card
    local isz = lh + 4
    local ox = icon_draw(DL(), other.rec.r, x, yy - 2, isz) and (isz + 8) or 0
    local parts = {
        { other.rec.n, HUD.text },
        { ('Lv %d'):format(other.level), HUD.muted },
        { diff_label(other.d), HUD.muted },
        { pct(other.success) .. ' success', success_color(other.success) },
        { per_synth(other) .. ' / synth', HUD.muted },
    }
    local sep = '  \194\183  '
    local lx, ly, right = x + ox, yy, x + w
    for i, pt in ipairs(parts) do
        local piece = fit(pt[1], w - ox)
        local pw = text_w(piece)
        local sw = (i > 1) and text_w(sep) or 0
        if i > 1 and lx + sw + pw > right then
            lx, ly = x + ox, ly + lh + 3            -- wrap: no separator at the start of a line
        elseif i > 1 then
            text(lx, ly, HUD.faint, sep); lx = lx + sw
        end
        text(lx, ly, pt[2], piece)
        lx = lx + pw
    end
    yy = math.max(ly + lh, yy + isz - 2) + 10
    yy = yy + draw_ingredients(x, yy, w, other.rec)
    -- action: pin it
    local cm = can_make(other.rec)
    local note = cm > 0 and ('can make %d now'):format(cm) or 'not in your inventory'
    text(x, yy, cm > 0 and HUD.owned or HUD.muted, fit(note, w))
    local pl = 'Pin this one'
    local pw = text_w(pl) + 20
    if text_w(note) + 12 + pw > w then yy = yy + lh + 10 end   -- button gets its own line
    local bx = x + w - pw
    local cp, hp = hit('##ch_cp_pin', bx, yy - 3, pw, lh + 6)
    T.frame(bx, yy - 3, pw, lh + 6, { fill = hp and HUD.sel_fill or HUD.inset, k = 4 })
    text(bx + 10, yy, hp and HUD.text or HUD.muted, pl)
    if cp then state.pin = other.rec.id end
    yy = yy + lh + 8
    return yy - y
end

-- BEST SYNTH dashboard: craft cards on top, a quiet controls row, then two
-- cards side by side - the best synth (success ring, odds, ingredients, the main
-- button) and one list card that switches between the guide path, guild kits
-- and other good recipes - and the rank strip at the bottom. Narrow windows
-- stack the two cards.
local function render_best()
    local lh = line_h()
    local k = state.craft
    render_craft_picker()

    -- controls: how much breaking you accept + options
    band('ch_ctl', function(x, y, w)
        local items = { { 'safe', 'SAFE' }, { 'balanced', 'BALANCED' }, { 'fast', 'FAST' } }
        local picked, mw, th = seg_tabs('ch_mode', items, state.mode, x, y, HUD.accent, true)
        if picked and picked ~= state.mode then state.mode = picked; save_settings() end
        -- the switches follow the picker; any that don't fit wrap onto the next line
        local rowh = math.max(th, lh + 10)
        local cx, cy = x + mw + 18, y
        local widest = mw
        local function switch(id, label, key)
            local tw = toggle_w(label)
            widest = math.max(widest, tw)
            if cx > x and cx + tw > x + w then cx, cy = x, cy + rowh + 6 end
            if toggle_chip(id, label, state[key], cx, cy + (rowh - (lh + 10)) * 0.5) then
                state[key] = not state[key]; save_settings()
            end
            cx = cx + tw + 14
        end
        switch('##ch_follow', 'Follow skill-ups', 'follow')
        switch('##ch_mini', 'Mini window', 'mini')
        switch('##ch_kits', 'Guild kits (to 50)', 'kits')
        -- quick on/off for the guild NPC's advanced synthesis support (+3, this craft only)
        do
            local g = gear_for(k)
            local label = 'Synth support +3'
            local tw = toggle_w(label)
            widest = math.max(widest, tw)
            if cx > x and cx + tw > x + w then cx, cy = x, cy + rowh + 6 end
            if toggle_chip('##ch_support', label, (tonumber(g.support) or 0) == 3, cx, cy + (rowh - (lh + 10)) * 0.5) then
                g.support = ((tonumber(g.support) or 0) == 3) and 0 or 3
                apply_rules(); save_settings()
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(('Advanced synthesis support from the %s guild: +3 %s while the buff is on.')
                    :format(C.CRAFTS[k].name, C.CRAFTS[k].name))
            end
            cx = cx + tw + 14
        end
        ui.ctl_need = widest
        return cy - y + rowh
    end)

    local pinned = state.pin and D.recipes[state.pin]
    local ev = pinned and C.evaluate(pinned, k, skills) or cache.best[k]
    local kits = cache.kits[k] or {}
    local alts = cache.alts[k] or {}
    local best_rec = cache.best[k] and cache.best[k].rec.id
    -- anything scoring the same as the best synth (within 0.5%) is tagged BEST too
    local best_score = cache.best[k] and C.score(cache.best[k], state.mode) or -1
    local function top(e) return e and best_score > 0 and C.score(e, state.mode) >= best_score * 0.995 end
    local list = state.list or 'path'
    if list == 'kits' and #kits == 0 then list = 'path' end

    -- left card: the synth itself
    local function best_card(x, y, w)
        if not ev then
            if skills[k].capped then
                return wrap(x, y, w, HUD.warn, ('You\'re capped at %d - no synth gives skill-ups until you pass the rank test (below).'):format(skills[k].cap))
            end
            return wrap(x, y, w, HUD.muted, 'Nothing on the path gives skill-ups at your level.')
        end
        local tag = (pinned and 'PINNED' or 'BEST NOW') .. (ev.rec.kit and '  -  GUILD KIT' or '')
        local h = draw_detail(x, y, w, ev, tag, pinned and HUD.gold or HUD.accent, pinned)
        h = h + draw_counterpart(x, y + h, w, ev)
        return h
    end

    -- right card: path / guild kits / also good, one at a time
    local function list_card(x, y, w)
        local yy = y
        local items = {
            { 'path', 'PATH' },
            { 'kits', 'GUILD KITS', #kits > 0 and tostring(#kits) or nil },
            { 'alts', 'ALSO GOOD', #alts > 0 and tostring(#alts) or nil },
            { 'all', 'ALL', tostring(#all_recipes(k)) },
        }
        local picked, tabs_w, th = seg_tabs('ch_list', items, list, x, yy, HUD.accent, true)
        if picked and picked ~= list and not (picked == 'kits' and #kits == 0) then state.list = picked; list = picked end
        local nb = #(cache.better[k] or {})
        local sub = (list == 'path' and (nb > 0 and ('CatseyeXI guide + %d good right now, click to pin'):format(nb)
                or 'CatseyeXI crafting guide, click a recipe to pin it'))
            or (list == 'kits' and (state.kits and 'Lv 5-50 from the guild vendors; the price climbs with the level' or 'Off: not used for the best synth'))
            or (list == 'all' and (C.rules.custom and 'Every recipe incl. kits and CatsEyeXI customs, by level'
                or 'Every recipe incl. guild kits, by level'))
            or 'Other recipes on your server that skill you up now, no kits'
        local tg = list == 'path' and (state.path_all and 'Hide finished' or 'Show all') or nil
        local tgw = tg and text_w(tg) or 0
        -- the link sits beside the tabs when there's room, otherwise at the end of the line below
        local beside = tg and (tabs_w + 16 + tgw <= w)
        local function link(ly)
            local clicked, hov = hit('##ch_pathall', x + w - tgw, ly, tgw, lh)
            rtext(x + w, ly, hov and HUD.text or HUD.accent, tg)
            if clicked then state.path_all = not state.path_all; save_settings() end
        end
        if beside then link(yy + (th - lh) * 0.5) end
        yy = yy + th + 8
        local sub_w = w
        if tg and not beside then link(yy); sub_w = w - tgw - 12 end
        text(x, yy, HUD.faint, fit(sub, sub_w))
        yy = yy + lh + 8
        yy = yy + row_head(x, yy, w)
        if list == 'path' then
            local path = D.path[C.CRAFTS[k].key] or {}
            local hidden, later = 0, 0
            local s = skills[k]
            local better, bn = cache.better[k] or {}, 1
            local function draw_better(upto)
                while better[bn] and (upto == nil or better[bn].level <= upto) do
                    local e = better[bn]
                    local id = e.rec.id
                    local st = (state.pin == id and 'pin') or (top(e) and not state.pin and 'best') or nil
                    local c, h = recipe_row(('##better%d'):format(bn), x, yy, w, e, st, top(e) and 'BEST' or 'GOOD')
                    if c then state.pin = (state.pin == id) and nil or id end
                    yy = yy + h
                    bn = bn + 1
                end
            end
            for i, row in ipairs(path) do
                local rec = row.rec and D.recipes[row.rec]
                draw_better((rec and rec.lv[k] or row.cap or 0) - 1)
                if rec then
                    local e = C.evaluate(rec, k, skills)
                    local done = (rec.lv[k] or 0) <= s.level - 11
                    local far = (rec.lv[k] or 0) > s.level + 14   -- too hard to even attempt yet
                    if done and not state.path_all then
                        hidden = hidden + 1
                    elseif far and not state.path_all then
                        later = later + 1
                    else
                        local st = (state.pin == rec.id and 'pin') or (top(e) and not state.pin and 'best') or (done and 'done') or nil
                        local c, h = recipe_row(('##path%d'):format(i), x, yy, w, e, st, top(e) and 'BEST' or nil)
                        if c then state.pin = (state.pin == rec.id) and nil or rec.id end
                        yy = yy + h
                    end
                else
                    text(x + lh + 9, yy, HUD.faint, fit(('%s  (Lv %d - not on your server)'):format(row.name, row.cap), w - lh - 9))
                    yy = yy + lh + 8
                end
            end
            draw_better(nil)
            if hidden > 0 or later > 0 then
                local parts = {}
                if hidden > 0 then parts[#parts + 1] = ('%d done'):format(hidden) end
                if later > 0 then parts[#parts + 1] = ('%d too hard yet'):format(later) end
                yy = yy + 2
                text(x + lh + 9, yy, HUD.faint, table.concat(parts, '  \194\183  ') .. '  \194\183  hidden')
                yy = yy + lh + 2
            end
        elseif list == 'all' then
            yy = yy + draw_all_list(x, yy, w, k, top, y)
        else
            local rows = list == 'kits' and kits or alts
            if #rows == 0 then
                text(x + lh + 9, yy, HUD.faint, 'Nothing right now.')
                yy = yy + lh + 2
            end
            local lv = skills[k].level
            for i, e in ipairs(rows) do
                local done = list == 'kits' and e.level <= lv - 11
                local st = (state.pin == e.rec.id and 'pin') or (top(e) and not state.pin and 'best') or (done and 'done') or nil
                local c, h = recipe_row(('##%s%d'):format(list, i), x, yy, w, e, st,
                    top(e) and 'BEST' or (e.rec.cexi and 'CEXI' or nil))
                if c then state.pin = (state.pin == e.rec.id) and nil or e.rec.id end
                yy = yy + h
            end
        end
        return yy - y
    end

    -- lay the two cards out: side by side with matching heights, or stacked
    local x0, y0 = imgui.GetCursorScreenPos()
    local w = avail_w()
    local gap = 10
    local two = w >= 720
    local lw = two and math.floor((w - gap) * 0.52) or w
    local rw = two and (w - gap - lw) or w
    local hl, hr = ui.h.ch_dl or 280, ui.h.ch_dr or 280
    local H = math.max(hl, hr)
    local rx, ry = two and (x0 + lw + gap) or x0, two and y0 or (y0 + hl + gap)
    if ev then T.hero_card(x0, y0, lw, two and H or hl, HUD.accent)       -- the lit card, as on /yui
    else card_bg(x0, y0, lw, two and H or hl, HUD.warn, 0.55) end
    ui.h.ch_dl = best_card(x0 + 16, y0 + 14, lw - 32) + 28
    card_bg(rx, ry, rw, two and H or hr, nil)
    ui.compact_rows = two
    ui.h.ch_dr = list_card(rx + 14, ry + 12, rw - 28) + 24
    ui.compact_rows = false
    imgui.SetCursorScreenPos({ x0, y0 })
    advance(w, two and H or (hl + gap + hr))
    imgui.Dummy({ 0, 2 })

    -- rank strip
    panel('ch_rank', skills[k].capped and HUD.warn or nil, function(x, y, pw) return draw_rank(x, y, pw, k) end)
end

--------------------------------------------------------------------------------
-- FISHING: best fish for your skill, with rod, bait and where to fish
--------------------------------------------------------------------------------

local ROUTE_BY_FISH = {}
for _, row in ipairs(FD.route) do ROUTE_BY_FISH[row.fish] = row end

local function fish_eval(fid)
    local f = FD.fish[fid]
    if not f then return nil end
    f.id = fid
    local row = ROUTE_BY_FISH[fid]
    local town
    if row then town = row.town else town = FM.all_town(f) end
    local ev = FM.evaluate(f, fishing, { town = town })
    ev.row = row
    return ev
end

local function fish_best()
    local best, bs = nil, 0
    for _, row in ipairs(FD.route) do
        local ev = fish_eval(row.fish)
        local sc = FM.score(ev, state.mode)
        if sc > bs then best, bs = ev, sc end
    end
    if best then return best end
    for fid, f in pairs(FD.fish) do
        if #f.at > 0 and not f.legend then
            local ev = fish_eval(fid)
            local sc = FM.score(ev, state.mode)
            if sc > bs then best, bs = ev, sc end
        end
    end
    return best
end

-- Every fish you can skill up on now (with a fishing spot), best first.
local function fish_all(limit)
    local out = {}
    for fid, f in pairs(FD.fish) do
        if #f.at > 0 and not f.legend then
            local ev = fish_eval(fid)
            if ev.can_skill then ev.score = FM.score(ev, state.mode); out[#out + 1] = ev end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.fish.n < b.fish.n
    end)
    while #out > (limit or 20) do table.remove(out) end
    return out
end

local function fish_rods(ev)
    if ev.row then return ev.row.rods end
    return { FM.pick_rod(FD.rods, ev.fish) }
end
local function fish_baits(ev)
    if ev.row then return ev.row.baits end
    local out = {}
    for i, b in ipairs(ev.fish.baits) do
        if i > 2 then break end
        out[#out + 1] = b[1]
    end
    return out
end
local function fish_where(ev)
    if ev.row then return ev.row.where end
    local parts, n = {}, 0
    for _, a in ipairs(ev.fish.at) do
        n = n + 1
        if n <= 5 then parts[#parts + 1] = a[2] ~= '' and ('%s (%s)'):format(a[1], a[2]) or a[1] end
    end
    local s = table.concat(parts, ', ')
    if n > 5 then s = s .. (', and %d more'):format(n - 5) end
    return s
end

local function per_catch(ev) return ev.gain > 0 and ('+%.3f'):format(ev.gain / 10) or '-' end
local function fish_diff(d)
    if d > 0 then return ('%d above you'):format(d) end
    if d == 0 then return 'at your level' end
    return ('%d below you'):format(-d)
end

-- One labelled line of items with icons: "ROD   [icon] Halcyon Rod  have 1".
local function item_line(x, y, w, label, ids, names)
    local lh = line_h()
    T.caps(x, y + 1, HUD.faint, label)
    local ix = x + 56
    local yy = y
    for i, id in ipairs(ids) do
        local nm = names[id] and names[id].n or item_name(id)
        local have = inv_counts[id] or 0
        local piece = ('%s%s'):format(i > 1 and 'or ' or '', nm)
        local hv = ('have %d'):format(have)
        local gap = 10
        local pw = lh + 6 + text_w(piece) + gap + text_w(hv)
        if i > 1 and ix + pw > x + w then ix, yy = x + 56, yy + lh + 6 end
        local ox = icon_draw(DL(), id, ix, yy - 2, lh + 3) and (lh + 6) or 0
        local room = x + w - ix - ox - gap - text_w(hv)
        local shown = fit(piece, room)
        text(ix + ox, yy, HUD.text, shown)
        local tx = ix + ox + text_w(shown) + gap
        text(tx, yy, have > 0 and HUD.owned or HUD.faint, hv)
        ix = tx + text_w(hv) + 14
    end
    return yy - y + lh + 8
end

local function fish_detail(x, y, w, ev, tag, tag_col)
    local lh = line_h()
    local dl = DL()
    local f = ev.fish
    -- skill-up ring
    local R, TH = math.floor(lh * 2.6), 7
    local cx, cy = x + R + TH * 0.5, y + R + TH * 0.5 + 2
    local sv = T.ease('ch_fring', ev.chance, 6)
    T.ring(cx, cy, R, TH, sv, ev.chance > 0 and success_color(math.min(1, ev.chance + 0.4)) or HUD.bad)
    local big = pct(sv)
    ring_label(cx, cy, R, TH, big, 'SKILL-UP')
    -- fish + odds
    local tx = x + R * 2 + TH + 18
    local tw = x + w - tx
    local ty = y + 2
    local isz = 36
    local has_icon = icon_draw(dl, f.id or 0, x + w - isz, y + 2, isz)
    local nw = tw - (has_icon and (isz + 10) or 0)
    pill(tx, ty, tag, tag_col or HUD.accent, 0.14)
    ty = ty + lh + 4
    text(tx, ty, HUD.text, fit(f.n, nw, 1.3), 1.3)
    ty = ty + math.floor(lh * 1.3) + 3
    local dlbl = fish_diff(ev.d)
    text(tx, ty, ev.can_skill and HUD.owned or HUD.faint, dlbl)
    text(tx + text_w(dlbl), ty, HUD.muted, fit(('  \194\183  Lv %d  \194\183  %s fish%s'):format(ev.lv, f.size == 1 and 'large' or 'small',
        ev.town and '  \194\183  town' or ''), tw - text_w(dlbl)))
    ty = ty + lh + 12
    local vx = tx + math.max(text_w('Catches per level'), 100) + 16
    local stats = {
        { 'Skill-up chance', pct(ev.chance), ev.chance > 0 and HUD.text or HUD.bad },
        { 'Per catch', per_catch(ev), ev.gain > 0 and HUD.owned or HUD.bad },
        { 'Catches per level', ev.per_level and ('~%d'):format(math.ceil(ev.per_level)) or '-', HUD.text },
        { 'Gets away', ev.lose > 0 and pct(ev.lose) or 'never (skill high enough)', ev.lose > 0.2 and HUD.warn or HUD.muted },
    }
    for _, st in ipairs(stats) do
        text(tx, ty, HUD.faint, st[1])
        text(vx, ty, st[3], fit(st[2], x + w - vx))
        ty = ty + lh + 5
    end
    local yy = math.max(ty, y + R * 2 + TH + 8) + 6
    T.rule(x, yy, w); yy = yy + 10
    -- rod, bait, where
    local rods = fish_rods(ev)
    yy = yy + item_line(x, yy, w, 'ROD', rods, FD.rods)
    yy = yy + item_line(x, yy, w, 'BAIT', fish_baits(ev), FD.baits)
    T.caps(x, yy + 1, HUD.faint, 'WHERE')
    yy = yy + wrap(x + 56, yy, w - 56, HUD.subtext, fish_where(ev))
    -- warnings and notes
    local notes = {}
    local issue = FM.rod_issue(FD.rods[rods[1]], f)
    if issue == 'big' then notes[#notes + 1] = 'It can escape as too big for this rod.' end
    if issue == 'small' then notes[#notes + 1] = 'A large rod can lose it as too small.' end
    if ev.row and ev.row.note then notes[#notes + 1] = ev.row.note end
    if f.ki then notes[#notes + 1] = 'Needs a key item to catch.' end
    if #notes > 0 then
        yy = yy + 4
        yy = yy + wrap(x, yy, w, HUD.warn, table.concat(notes, ' '))
    end
    yy = yy + 4
    yy = yy + wrap(x, yy, w, HUD.faint, "Lu Shang's Fishing Rod lands almost anything, but slows skill-ups below 50. Skill-ups are slower in towns.")
    return yy - y
end

local function fish_row(id, x, y, w, ev, rowstate, extra)
    local dl = DL()
    local lh = line_h()
    local h = lh + 6
    local clicked, hov = hit(id, x - 6, y - 3, w + 12, h)
    if rowstate == 'best' or rowstate == 'pin' then
        dl:AddRectFilled({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.10), 5)
        dl:AddRect({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.35), 5, CORNERS_ALL, 1)
    elseif hov then
        dl:AddRectFilled({ x - 6, y - 3 }, { x + w + 6, y - 3 + h }, col(HUD.accent, 0.07), 5)
    end
    local dim = rowstate == 'done'
    local dc = dim and HUD.faint or (ev.can_skill and HUD.owned or HUD.faint)
    if icon_draw(dl, ev.fish.id or 0, x - 1, y - 2, lh + 3) then dot(x + lh, y + lh - 1, 3, dc)
    else dot(x + 6, y + lh * 0.5, 3.5, dc) end
    local rc = ui.compact_rows and ROW_COLS.compact or ROW_COLS.full
    local nx = x + lh + 9
    local name_w = w - rc.lv - 30 - (nx - x) - (extra and (pill_w(extra) + 8) or 0)
    local shown = fit(ev.fish.n, name_w)
    text(nx, y, dim and HUD.faint or HUD.text, shown)
    if extra then pill(nx + text_w(shown) + 8, y, extra, HUD.accent2) end
    rtext(x + w - rc.lv, y, dim and HUD.faint or HUD.subtext, tostring(ev.lv))
    rtext(x + w - rc.su, y, dim and HUD.faint or (ev.chance > 0 and HUD.text or HUD.faint), ev.chance > 0 and pct(ev.chance) or '-')
    rtext(x + w - rc.ps, y, dim and HUD.faint or (ev.gain > 0 and HUD.owned or HUD.faint), per_catch(ev))
    if hov then
        imgui.SetTooltip(('%s  (Lv %d, %s)\nRod: %s\nBait: %s\n%s\nClick to pin it.'):format(ev.fish.n, ev.lv, fish_diff(ev.d),
            FD.rods[fish_rods(ev)[1]] and FD.rods[fish_rods(ev)[1]].n or '?',
            (function() local t = {} for _, b in ipairs(fish_baits(ev)) do t[#t + 1] = FD.baits[b] and FD.baits[b].n or item_name(b) end return table.concat(t, ' or ') end)(),
            fish_where(ev)))
    end
    return clicked, h + 2
end

local function fish_head(x, y, w)
    local lh = line_h()
    local rc = ui.compact_rows and ROW_COLS.compact or ROW_COLS.full
    T.caps(x + lh + 9, y + lh * 0.1, HUD.faint, 'FISH')
    for _, c in ipairs({ { rc.lv, 'LV' }, { rc.su, 'SKILL-UP' }, { rc.ps, 'PER CATCH' } }) do
        T.caps(x + w - c[1] - T.caps_w(c[2]), y + lh * 0.1, HUD.faint, c[2])
    end
    T.rule(x - 6, y + lh + 3, w + 12)
    return lh + 8
end

local function render_fishing()
    local lh = line_h()
    -- controls
    band('ch_fctl', function(x, y, w)
        local items = { { 'safe', 'SAFE' }, { 'balanced', 'BALANCED' }, { 'fast', 'FAST' } }
        local picked, mw, th = seg_tabs('ch_fmode', items, state.mode, x, y, HUD.accent, true)
        if picked and picked ~= state.mode then state.mode = picked; save_settings() end
        local info = ('Fishing %s / %d  \194\183  skill-up rate x%s%s'):format(
            lvl_text(fishing), fishing.cap, tostring(FM.rules.rate),
            FM.rules.bonus > 0 and ('  \194\183  gear +%d (%d to land fish)'):format(FM.rules.bonus, fishing.level + FM.rules.bonus) or '')
        if mw + 18 + text_w(info) <= w then
            text(x + mw + 18, y + (th - lh) * 0.5, HUD.muted, info)
            return th
        end
        text(x, y + th + 6, HUD.muted, fit(info, w))
        return th + 6 + lh
    end)

    local pinned = state.fish_pin and FD.fish[state.fish_pin] and fish_eval(state.fish_pin)
    local best = fish_best()
    local ev = pinned or best
    local list = state.fish_list or 'route'

    local function left(x, y, w)
        if not ev then
            if fishing.capped then
                return wrap(x, y, w, HUD.warn, ('You\'re capped at %d - pass the rank test (below) to keep skilling up.'):format(fishing.cap))
            end
            return wrap(x, y, w, HUD.muted, 'No fish gives skill-ups at your level.')
        end
        local h = fish_detail(x, y, w, ev, pinned and 'PINNED' or 'BEST NOW', pinned and HUD.gold or HUD.accent)
        if pinned then
            local clicked, _, bh = T.ghost('##ch_funpin', x + w - T.ghost_w('Unpin'), y + h + 6, 'Unpin')
            if clicked then state.fish_pin = nil end
            h = h + 6 + (bh or lh + 10)
        end
        return h
    end

    local function right(x, y, w)
        local yy = y
        local items = { { 'route', 'CEXI ROUTE' }, { 'all', 'ALL FISH' } }
        local picked, _, th = seg_tabs('ch_flist', items, list, x, yy, HUD.accent, true)
        if picked and picked ~= list then state.fish_list = picked; list = picked; save_settings() end
        yy = yy + th + 8
        local sub = list == 'route' and 'CatsEyeXI fishing guide: aim 9-13 levels above you. Click to pin.'
            or 'Every fish with a fishing spot that skills you up now, best first'
        text(x, yy, HUD.faint, fit(sub, w))
        yy = yy + lh + 8
        yy = yy + fish_head(x, yy, w)
        local best_id = best and best.fish.id
        local rows = {}
        if list == 'route' then
            for _, row in ipairs(FD.route) do rows[#rows + 1] = fish_eval(row.fish) end
        else
            rows = fish_all(20)
        end
        if #rows == 0 then text(x + lh + 9, yy, HUD.faint, 'Nothing right now.'); yy = yy + lh + 2 end
        for i, e in ipairs(rows) do
            local id = e.fish.id
            local done = e.lv <= fishing.level
            local st = (state.fish_pin == id and 'pin') or (best_id == id and not state.fish_pin and 'best') or (done and 'done') or nil
            local c, h = fish_row(('##fish%d'):format(i), x, yy, w, e, st, best_id == id and 'BEST' or nil)
            if c then state.fish_pin = (state.fish_pin == id) and nil or id end
            yy = yy + h
        end
        return yy - y
    end

    local x0, y0 = imgui.GetCursorScreenPos()
    local w = avail_w()
    local gap = 10
    local two = w >= 720
    local lw = two and math.floor((w - gap) * 0.52) or w
    local rw = two and (w - gap - lw) or w
    local hl, hr = ui.h.ch_fl or 280, ui.h.ch_fr or 280
    local H = math.max(hl, hr)
    local rx, ry = two and (x0 + lw + gap) or x0, two and y0 or (y0 + hl + gap)
    if ev then T.hero_card(x0, y0, lw, two and H or hl, HUD.accent) else card_bg(x0, y0, lw, two and H or hl, HUD.warn, 0.55) end
    ui.h.ch_fl = left(x0 + 16, y0 + 14, lw - 32) + 28
    card_bg(rx, ry, rw, two and H or hr, nil)
    ui.compact_rows = two
    ui.h.ch_fr = right(rx + 14, ry + 12, rw - 28) + 24
    ui.compact_rows = false
    imgui.SetCursorScreenPos({ x0, y0 })
    advance(w, two and H or (hl + gap + hr))
    imgui.Dummy({ 0, 2 })

    -- rank strip
    panel('ch_frank', fishing.capped and HUD.warn or nil, function(x, y, w)
        local yy = y
        local name = 'Fishing'
        text(x, yy, HUD.accent2, name)
        text(x + text_w(name) + 10, yy, HUD.muted, C.rank_name(fishing.rank))
        rtext(x + w, yy, HUD.text, ('%s / %d'):format(lvl_text(fishing), fishing.cap))
        yy = yy + lh + 6
        bar(x, yy, w, 5, (fishing.tenths - (fishing.cap - 10) * 10) / 100, fishing.capped and HUD.warn or HUD.accent)
        yy = yy + 15
        local test = FD.tests[fishing.cap]
        local guild = 'Fishing Guild: Thubu Parohren, Port Windurst.'
        if fishing.capped then
            yy = yy + wrap(x, yy, w, HUD.warn, ('Capped: trade %s to rank up. %s'):format(test or 'the test fish', guild))
        elseif fishing.level >= fishing.cap - 2 then
            yy = yy + wrap(x, yy, w, HUD.gold, ('Rank test open: %s. %s'):format(test or 'ask the guild master', guild))
        else
            text(x, yy, HUD.muted, fit(('Next test at %d: %s'):format(fishing.cap - 2, test or 'ask the guild master'), w))
            yy = yy + lh + 2
        end
        local fs = state.fish_session
        if fs.ups > 0 then
            text(x, yy, HUD.owned, ('This session: +%s from %d skill-ups'):format(pts(fs.gain), fs.ups))
            yy = yy + lh + 2
        end
        return yy - y
    end)
end

-- RECIPES tab shows recipes this many levels either side of your skill in the chosen craft.
local RECIPE_SPAN = 11

-- RECIPES: everything around your level for the focused craft, or search results.
local function render_recipes()
    local lh = line_h()
    local q = (state.search[1] or ''):lower()
    local searching = q:find('%S') ~= nil
    if not searching then render_craft_picker() end
    local k = state.craft
    local list = {}
    if searching then
        for _, rec in pairs(D.recipes) do
            if rec.n:lower():find(q, 1, true) and rec.main and C.available(rec) then
                list[#list + 1] = C.evaluate(rec, rec.main, skills)
            end
        end
        table.sort(list, function(a, b)
            if a.craft ~= b.craft then return a.craft < b.craft end
            if a.level ~= b.level then return a.level < b.level end
            return a.rec.id < b.rec.id
        end)
    else
        local lv = skills[k].level
        for _, rec in ipairs(BY_CRAFT[k]) do
            local l = rec.lv[k]
            if l >= lv - RECIPE_SPAN and l <= lv + RECIPE_SPAN and C.available(rec) then
                list[#list + 1] = C.evaluate(rec, k, skills)
            end
        end
    end
    local shown = math.min(#list, 300)
    panel('ch_rec', nil, function(x, y, w)
        local yy = y
        if searching then
            T.heading(x, yy, 'Search', ('%d recipes match "%s"'):format(#list, q))
        else
            T.heading(x, yy, C.CRAFTS[k].name, ('recipes from %d to %d (%d)'):format(
                math.max(1, skills[k].level - RECIPE_SPAN), skills[k].level + RECIPE_SPAN, #list))
        end
        if shown < #list then rtext(x + w, yy, HUD.faint, ('showing first %d'):format(shown)) end
        yy = yy + lh + 8
        yy = yy + row_head(x, yy, w)
        local last_craft = nil
        for i = 1, shown do
            local e = list[i]
            if searching and e.craft ~= last_craft then
                last_craft = e.craft
                yy = yy + 2
                text(x, yy, HUD.accent2, C.CRAFTS[e.craft].name)
                yy = yy + lh + 4
            end
            local tag = e.rec.kit and 'KIT' or (e.rec.cexi and 'CEXI') or (PATH_SET[e.craft][e.rec.id] and 'GUIDE' or nil)
            local st = state.pin == e.rec.id and 'pin' or nil
            local c, h = recipe_row(('##rec%d'):format(e.rec.id), x, yy, w, e, st, tag)
            if c then
                state.craft, state.pin, state.tab = e.craft, e.rec.id, 2
                state.search[1] = ''
            end
            yy = yy + h
        end
        if #list == 0 then text(x, yy, HUD.faint, 'Nothing here.'); yy = yy + lh end
        return yy - y
    end)
end

-- SETTINGS (gear icon): server rules + general options
local MODE_COLOR = {
    ace = { 0.45, 0.90, 0.60, 1 },   -- green crystal on bg-wiki
    cw  = { 1.00, 0.55, 0.85, 1 },   -- pink crystal
    wew = { 0.94, 0.77, 0.42, 1 },   -- the cat
}
local MODE_INFO = {
    ace = { 'ACE', 'Accelerated', 'skill-up chance x1.5, size x3.0' },
    cw  = { 'CW', 'Crystal Warrior', 'skill-up chance x1.5, every craft to 110' },
    wew = { 'WEW', 'Wings Era Warrior', 'skill-up chance x1.0, size x1.0' },
}

-- Small bordered button. Returns clicked, width.
local function small_button(id, x, y, label, c)
    local lh = line_h()
    local w, h = text_w(label) + 20, lh + 8
    local clicked, hov = hit(id, x, y, w, h)
    T.frame(x, y, w, h, { fill = hov and HUD.sel_fill or HUD.inset, edge = c, k = 4 })
    text(x + 10, y + 4, hov and HUD.text or (c or HUD.subtext), label)
    return clicked, w, h
end

-- "label   [-] value [+]" stepper. Returns the new value.
local function stepper(id, x, y, label, value, step, lo, hi)
    local lh = line_h()
    text(x, y + 4, HUD.text, label)
    local bx = x + 190
    local c1, w1 = small_button(id .. '_m', bx, y, '-')
    local vs = ('x%s'):format(tostring(value))
    text(bx + w1 + 10, y + 4, HUD.accent2, vs)
    local c2 = small_button(id .. '_p', bx + w1 + 20 + text_w('x0.00'), y, '+')
    if c1 then value = math.max(lo, value - step) end
    if c2 then value = math.min(hi, value + step) end
    return math.floor(value * 100 + 0.5) / 100, lh + 14
end

local function render_settings()
    local lh = line_h()
    panel('ch_set_rules', HUD.accent, function(x, y, w)
        local yy = y
        T.heading(x, yy, 'Server rules', 'how skill-up odds and caps are worked out')
        yy = yy + lh + 10
        local items = { { 'retail', 'RETAIL' }, { 'lsb', 'LSB' }, { 'cexi', 'CEXI' } }
        local picked, _, th = seg_tabs('ch_server', items, state.server, x, yy, HUD.accent, false)
        if picked and picked ~= state.server then set_server(picked) end
        yy = yy + th + 12

        if state.server == 'retail' then
            yy = yy + wrap(x, yy, w, HUD.subtext, 'Retail FFXI: modern skill-ups (until 10 levels over a recipe), normal chance and size, one main craft to 110 and the rest to 70.')
        elseif state.server == 'lsb' then
            yy = yy + wrap(x, yy, w, HUD.subtext, 'Your LandSandBoat server. Match these to settings/map.lua.')
            yy = yy + 6
            local v, h = stepper('##st_rate', x, yy, 'Skill-up chance', state.rate, 0.25, 0.25, 10)
            if v ~= state.rate then state.rate = v; set_server('lsb', nil, true) end
            yy = yy + h
            v, h = stepper('##st_size', x, yy, 'Skill-up size', state.amount, 0.5, 0.5, 10)
            if v ~= state.amount then state.amount = v; set_server('lsb', nil, true) end
            yy = yy + h
            local c, tw = toggle_chip('##st_era', 'Era rules (skill-ups only below a recipe)', not state.modern, x, yy)
            if c then state.modern = not state.modern; set_server('lsb', nil, true) end
            yy = yy + lh + 14
            text(x, yy, HUD.faint, 'CRAFT_CHANCE_MULTIPLIER, CRAFT_MODERN_SYSTEM. Size is x1.0 on stock LSB.')
            yy = yy + lh + 4
        else
            yy = yy + wrap(x, yy, w, HUD.subtext, 'CatsEyeXI: modern skill-ups (until 11 over a recipe\'s cap) and +1% success for every craft at 70+ (max 99%). Switch on your game mode\'s rates:')
            yy = yy + 8
            for _, key in ipairs(C.CEXI_MODES) do
                local mi = MODE_INFO[key]
                local on = state.cexi_mode == key
                local c, tw = toggle_chip('##st_' .. key, ('%s  %s'):format(mi[1], mi[2]), on, x, yy, MODE_COLOR[key])
                text(x + tw + 12, yy + 5, on and HUD.subtext or HUD.faint, mi[3])
                if c then set_server('cexi', on and '' or key) end   -- one mode at a time; click again for none
                yy = yy + lh + 16
            end
            if state.cexi_mode == '' then
                text(x, yy, HUD.warn, 'No mode switched on: using normal rates.')
                yy = yy + lh + 4
            end
        end

        -- what's in force
        yy = yy + 6
        T.rule(x, yy, w); yy = yy + 10
        local r = rules_info()
        local cells = {
            { 'IN USE', r.label },
            { 'CHANCE', ('x%s'):format(tostring(r.rate)) },
            { 'SIZE', ('x%s'):format(tostring(r.amount)) },
            { 'RULES', r.modern and 'Modern' or 'Era' },
            { 'CAPS', (r.spec_points or 40) >= 320 and 'All 110' or '110 / 70' },
            { 'SUCCESS', (r.bonus70 or 0) > 0 and '+1% per 70' or 'normal' },
        }
        local cw = math.floor(w / #cells)
        for i, cl in ipairs(cells) do
            T.caps(x + (i - 1) * cw, yy + lh * 0.1, HUD.faint, cl[1])
            text(x + (i - 1) * cw, yy + lh + 2, i == 1 and HUD.accent2 or HUD.text, cl[2])
        end
        yy = yy + lh * 2 + 4
        return yy - y
    end, 1.0)

    -- skill bonuses: what you own / have on, per craft
    panel('ch_set_gear', nil, function(x, y, w)
        local yy = y
        T.heading(x, yy, 'Skill bonuses', 'switch on what you own; they raise success and HQ, not skill-ups')
        yy = yy + lh + 10
        local gk = state.gear_craft or state.craft
        local items = {}
        for k, c in ipairs(C.CRAFTS) do
            local b = skill_bonus(k)
            items[#items + 1] = { k, c.short, b > 0 and ('+' .. b) or nil }
        end
        local natural = seg_width(items, true)
        local picked, _, th = seg_tabs('ch_gear_craft', items, gk, x, yy, HUD.accent, true, { width = math.max(natural, w) })
        if picked then state.gear_craft = picked; gk = picked end
        ui.gear_need = natural
        yy = yy + th + 12
        local g = gear_for(gk)
        local function changed() apply_rules(); save_settings() end
        -- per-craft gear, two columns when there's room
        local colw = (w >= 560) and math.floor((w - 16) / 2) or w
        for i, b in ipairs(BONUS_SOURCES) do
            local ci = (colw < w) and ((i - 1) % 2) or 0
            local bx = x + ci * (colw + 16)
            local label = ('%s  +%d'):format(b.label, b.value)
            if toggle_chip('##sb_' .. b.key, fit(label, colw - 50), g[b.key] == true, bx, yy) then
                g[b.key] = not g[b.key]; changed()
            end
            if ci == 1 or colw == w or i == #BONUS_SOURCES then yy = yy + lh + 14 end
        end
        -- image support from the guild NPC
        text(x, yy + 5, HUD.text, 'Synthesis support')
        local sx = x + text_w('Synthesis support') + 14
        local sitems = {}
        for _, sp in ipairs(SUPPORT) do sitems[#sitems + 1] = { sp[1], sp[2] } end
        local sp_w = seg_width(sitems, true)
        if sx + sp_w > x + w then sx = x; yy = yy + lh + 10 end
        local sp_pick, _, sth = seg_tabs('ch_gear_sup', sitems, tonumber(g.support) or 0, sx, yy, HUD.accent, true)
        if sp_pick ~= nil and sp_pick ~= (tonumber(g.support) or 0) then g.support = sp_pick; changed() end
        yy = yy + sth + 10
        -- every craft
        if toggle_chip('##sb_kupo', 'Kupo Shield  +3 to every craft', state.kupo, x, yy) then
            state.kupo = not state.kupo; changed()
        end
        yy = yy + lh + 16
        -- total for this craft
        T.rule(x, yy, w); yy = yy + 10
        local total, list = skill_bonus(gk)
        local s = skills[gk]
        local name = C.CRAFTS[gk].name
        text(x, yy, HUD.text, name)
        local line = total > 0 and ('  %d + %d = %d effective for success and HQ'):format(s.level, total, s.level + total)
            or '  no bonuses switched on'
        text(x + text_w(name), yy, total > 0 and HUD.owned or HUD.faint, fit(line, w - text_w(name)))
        yy = yy + lh + 4
        if total > 0 then
            yy = yy + wrap(x, yy, w, HUD.faint, list .. '. The torque, apron and gloves only count while you wear them, and support only while the buff is on.')
        end
        return yy - y
    end)

    -- fishing: skill-up rate and gear that helps you land fish
    panel('ch_set_fish', nil, function(x, y, w)
        local yy = y
        T.heading(x, yy, 'Fishing', 'gear helps you land fish; skill-ups use your real skill')
        yy = yy + lh + 10
        if state.server == 'lsb' then
            local v, h = stepper('##st_frate', x, yy, 'Fishing skill-up rate', state.fish_rate, 0.5, 0.5, 10)
            if v ~= state.fish_rate then state.fish_rate = v; apply_rules(); save_settings() end
            yy = yy + h
            text(x, yy, HUD.faint, 'FISHING_SKILL_MULTIPLIER in settings/map.lua.')
            yy = yy + lh + 8
        else
            text(x, yy, HUD.subtext, ('Skill-up rate x%s (%s)'):format(tostring(FM.rules.rate),
                state.server == 'cexi' and 'CatsEyeXI, every game mode' or 'retail'))
            yy = yy + lh + 10
        end
        local g = state.fish_gear
        local colw = (w >= 560) and math.floor((w - 16) / 2) or w
        for i, b in ipairs(FISH_BONUS) do
            local ci = (colw < w) and ((i - 1) % 2) or 0
            local bx = x + ci * (colw + 16)
            if toggle_chip('##fb_' .. b.key, fit(('%s  +%d'):format(b.label, b.value), colw - 50), g[b.key] == true, bx, yy) then
                g[b.key] = not g[b.key]; apply_rules(); save_settings()
            end
            if ci == 1 or colw == w or i == #FISH_BONUS then yy = yy + lh + 14 end
        end
        text(x, yy + 5, HUD.text, 'Feet')
        local fx = x + text_w('Feet') + 14
        local fitems = {}
        for _, f in ipairs(FISH_FEET) do fitems[#fitems + 1] = { f[1], f[2] } end
        local fp, _, fth = seg_tabs('ch_fish_feet', fitems, tonumber(g.feet) or 0, fx, yy, HUD.accent, true)
        if fp ~= nil and fp ~= (tonumber(g.feet) or 0) then g.feet = fp; apply_rules(); save_settings() end
        yy = yy + fth + 10
        T.rule(x, yy, w); yy = yy + 10
        local b = FM.rules.bonus
        local line = b > 0 and ('Fishing %d + %d = %d to land fish'):format(fishing.level, b, fishing.level + b) or 'No fishing gear switched on'
        text(x, yy, b > 0 and HUD.owned or HUD.faint, fit(line, w))
        yy = yy + lh + 4
        return yy - y
    end)

    panel('ch_set_gen', nil, function(x, y, w)
        local yy = y
        T.heading(x, yy, 'General')
        yy = yy + lh + 10
        text(x, yy + 4, HUD.subtext, 'Best synth picks')
        local items = { { 'safe', 'SAFE' }, { 'balanced', 'BALANCED' }, { 'fast', 'FAST' } }
        local picked, _, th = seg_tabs('ch_set_mode', items, state.mode, x + 190, yy, HUD.accent, true)
        if picked and picked ~= state.mode then state.mode = picked; save_settings() end
        yy = yy + th + 10
        local opts = {
            { '##sg_follow', 'Follow skill-ups (focus the craft that just skilled up)', 'follow' },
            { '##sg_kits', 'Guild kits (Lv 5-50) can be the best synth', 'kits' },
            { '##sg_mini', 'Mini window', 'mini' },
            { '##sg_path', 'Show the whole guide path', 'path_all' },
        }
        for _, o in ipairs(opts) do
            local c = toggle_chip(o[1], o[2], state[o[3]], x, yy)
            if c then state[o[3]] = not state[o[3]]; save_settings() end
            yy = yy + lh + 14
        end
        return yy - y
    end)
end

--------------------------------------------------------------------------------
-- Mini window: focused craft + best synth, for while you're crafting
--------------------------------------------------------------------------------

local mini_win = {}
local function render_mini()
    if not state.mini then return end
    local k = state.craft
    local s = skills[k]
    if not s then return end
    local pinned = state.pin and D.recipes[state.pin]
    local ev = pinned and C.evaluate(pinned, k, skills) or cache.best[k]
    local lh = line_h()
    local W = 340
    local H = lh * 3 + 40
    T.push_style()
    local fp = T.push_font()
    imgui.SetNextWindowSize({ W, H }, ImGuiCond_Always)
    place_window(mini_win, W, H)
    undock_next()
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoScrollbar, NO_DOCK)
    if imgui.Begin('crafthub mini##crafthub_mini', state.mini_open, flags) then
        local x, y = imgui.GetCursorScreenPos()
        local w = W - 28
        local lv = lvl_text(s)
        T.crystal(x + 5, y + lh * 0.5, 8, 15, HUD.accent, { glow = 0.5 })
        text(x + 16, y, HUD.accent2, C.CRAFTS[k].name)
        text(x + 16 + text_w(C.CRAFTS[k].name) + 8, y, HUD.text, lv)
        local ss = state.session[k]
        if ss and ss.gain ~= 0 then rtext(x + w, y, HUD.owned, ('+%s'):format(pts(ss.gain))) end
        if s.capped then rtext(x + w - 60, y, HUD.warn, 'CAPPED') end
        y = y + lh + 6
        bar(x, y, w, 4, (s.tenths - (s.cap - 10) * 10) / 100, s.capped and HUD.warn or HUD.accent)
        y = y + 10
        if ev then
            local isz = lh * 2 + 4
            local ox = icon_draw(DL(), ev.rec.r, x, y, isz) and (isz + 8) or 0
            text(x + ox, y, HUD.text, fit(ev.rec.n, w - 70 - ox))
            rtext(x + w, y, HUD.subtext, ('Lv %d'):format(ev.level))
            y = y + lh + 4
            local cm = can_make(ev.rec)
            text(x + ox, y, success_color(ev.success), pct(ev.success))
            text(x + ox + text_w(pct(ev.success)), y, HUD.muted, ('  \194\183  %s/synth  \194\183  can make %d'):format(per_synth(ev), cm))
        else
            text(x, y, HUD.faint, 'No skill-ups available.')
        end
        imgui.Dummy({ w, lh * 3 + 10 })
        drag_window(mini_win)
    end
    draw_item_tip()
    imgui.End()
    T.pop_font(fp)
    T.pop_style()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function help()
    msg('/craft - open or close the window   (/crafthub works too)')
    msg('/craft <wood|smith|gold|cloth|leather|bone|alchemy|cook> - focus a craft')
    msg('/craft fish - fishing: best fish, rod and bait for your skill')
    msg('/craft trace - echo each skill-up crafthub reads (to check the decimals)')
    msg('/craft mode <safe|balanced|fast> - how much breaking you\'ll accept')
    msg('/craft mini - toggle the mini window   /craft follow - toggle following skill-ups')
    msg('/craft kits - toggle using guild kits (Lv 5-50) for the best synth')
    msg('/craft settings - open settings (gear icon)   /craft server <retail|lsb|cexi|ace|cw|wew> - server rules')
    msg('/craft rate <n> / size <n> / era - your LSB server\'s skill-up chance, size and era rules')
    msg('/craft era - toggle LSB CRAFT_MODERN_SYSTEM (modern: skill-ups until 10 over a recipe)')
    msg('/craft level <craft> <decimal> - tell crafthub your decimal, e.g. /craft level wood 4')
    msg('/craft reset - re-centre and re-fit the window   /craft debug - show raw skill values')
end

local win = { reset = false }

ashita.events.register('command', 'crafthub_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local root = args[1]:lower()
    if root ~= '/craft' and root ~= '/crafthub' then return end
    e.blocked = true
    local sub = (args[2] or ''):lower()
    if sub == '' then
        state.visible[1] = not state.visible[1]
    elseif sub == 'show' then state.visible[1] = true
    elseif sub == 'hide' then state.visible[1] = false
    elseif sub == 'help' then help()
    elseif sub == 'mini' then state.mini = not state.mini; save_settings()
    elseif sub == 'follow' then
        state.follow = not state.follow; save_settings()
        msg('Follow skill-ups: ' .. (state.follow and 'on' or 'off'))
    elseif sub == 'mode' and C.MODES[(args[3] or ''):lower()] then
        state.mode = args[3]:lower(); save_settings(); msg('Mode: ' .. state.mode)
    elseif sub == 'server' and (args[3] or '') ~= '' then
        local v = args[3]:lower()
        if v == 'retail' or v == 'lsb' or v == 'cexi' then set_server(v)
        elseif v == 'ace' or v == 'cw' or v == 'wew' then set_server('cexi', v)
        else msg('Use /craft server retail, lsb or cexi (or ace / cw / wew for a CEXI mode).') end
    elseif sub == 'settings' then
        state.visible[1], state.settings = true, true
    elseif sub == 'size' and tonumber(args[3]) and tonumber(args[3]) > 0 then
        state.amount = tonumber(args[3]); set_server('lsb', nil, true)
        msg('LSB skill-up size multiplier: x' .. state.amount)
    elseif sub == 'rate' and tonumber(args[3]) and tonumber(args[3]) > 0 then
        state.rate = tonumber(args[3]); set_server('lsb', nil, true); msg('LSB skill-up chance multiplier: x' .. state.rate)
    elseif sub == 'era' then
        state.modern = not state.modern; set_server('lsb', nil, true)
        msg('Rules: ' .. (state.modern and 'modern (skill-ups until 10 over a recipe)' or 'era (skill-ups only below a recipe)'))
    elseif sub == 'level' and C.BY_KEY[(args[3] or ''):lower()] and tonumber(args[4]) then
        local k = C.BY_KEY[args[3]:lower()]
        local d = math.floor(tonumber(args[4]))
        if not skills[k] then refresh_skills() end
        if d >= 0 and d <= 9 then
            remember_decimal(k, skills[k].level, d); save_settings()
            msg(('%s set to %d.%d'):format(C.CRAFTS[k].name, skills[k].level, d))
        end
    elseif sub == 'fish' or sub == 'fishing' then
        state.visible[1], state.tab, state.settings = true, 4, false
    elseif sub == 'kits' then
        state.kits = not state.kits; save_settings()
        msg('Guild kits (Lv 5-50) for the best synth: ' .. (state.kits and 'on' or 'off'))
    elseif sub == 'trace' then
        state.trace = not state.trace
        msg('Skill-up trace ' .. (state.trace and 'on: each skill-up crafthub reads is echoed here' or 'off'))
    elseif sub == 'debug' then
        for k = 1, 8 do
            local lv, rk, cap = mem_craft(k)
            local p = state.pkt[k]
            msg(('%-12s memory %s/r%s%s   packet %s'):format(C.CRAFTS[k].name, tostring(lv), tostring(rk), cap and ' capped' or '',
                p and ('%d/r%d%s'):format(p[1], p[2], p[3] and ' capped' or '') or 'not seen yet (zone once)'))
        end
    elseif sub == 'reset' then
        win.reset = true; mini_win.pos = nil; state.visible[1] = true
    elseif C.BY_KEY[sub] then
        select_craft_tab(C.BY_KEY[sub]); state.visible[1] = true
    else
        help()
    end
end)

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local PAD_X, PAD_Y, SCROLL_W = 14, 12, 0   -- our own scrollbar sits in the right padding
local MIN_CW = 640

ashita.events.register('d3d_present', 'crafthub_present_cb', function()
    refresh_skills()
    refresh_fishing()
    ICON.new_frame()
    if not state.visible[1] and not state.mini then return end
    refresh_inventory()
    rebuild()
    -- tint the window with the pinned / best synth's crystal. HQ crystals = base element.
    do
        local pr = state.pin and D.recipes[state.pin]
        local be = cache.best[state.craft]
        local cr = (pr and pr.c) or (be and be.rec.c)
        if cr and cr >= 4238 and cr <= 4245 then cr = cr - 142 end
        T.set_tint(cr and ELEMENT_COLOR[cr] or nil)
    end
    render_mini()
    if not state.visible[1] then return end

    T.push_style()
    local font_pushed = T.push_font()

    local io_ok, io = pcall(imgui.GetIO)
    local sh = (io_ok and io and io.DisplaySize and io.DisplaySize.y) or 1080
    local need = math.max(MIN_CW, ui.header_need or 0, ui.picker_need or 0, ui.ctl_need or 0, ui.ov_need or 0, ui.gear_need or 0)
    local min_cw = need + ui.inset * 2
    local min_w = min_cw + PAD_X * 2 + SCROLL_W
    local fit_w = min_w
    local fit_h = math.min((win.content_h or 500) + PAD_Y * 2, math.floor(sh * 0.85))
    local vp = main_viewport()
    if win.reset or not win.size then
        local sz = (not win.reset) and state.win_size or nil
        win.size = sz and { sz[1], sz[2] } or { fit_w, fit_h }
        win.fit_frames = sz and 0 or 3
        win.set_size = true
    elseif (win.fit_frames or 0) > 0 then
        win.fit_frames = win.fit_frames - 1
        win.size = { fit_w, fit_h }
        win.set_size = true
    end
    if win.reset then
        win.pos = { vp[1] + (vp[3] - win.size[1]) * 0.5, vp[2] + (vp[4] - win.size[2]) * 0.5 }
        win.reset, win.drag = false, nil
    end
    local px, py = (win.pos or { vp[1], vp[2] })[1], (win.pos or { vp[1], vp[2] })[2]
    local max_w = math.max(min_w, vp[1] + vp[3] - px)
    local max_h = math.max(200, vp[2] + vp[4] - py)
    if type(imgui.SetNextWindowSizeConstraints) == 'function' then
        imgui.SetNextWindowSizeConstraints({ math.min(min_w, max_w), 200 }, { max_w, max_h })
    end
    if win.set_size then
        imgui.SetNextWindowSize({ math.min(win.size[1], max_w), math.min(win.size[2], max_h) }, ImGuiCond_Always)
        win.set_size = false
    end
    place_window(win, win.size[1], win.size[2])
    if win.content_h and type(imgui.SetNextWindowContentSize) == 'function' then
        imgui.SetNextWindowContentSize({ 0, win.content_h })
    end

    -- ImGui's own scrollbar runs into the rounded corners, so it's hidden and
    -- drawn by hand below (the mouse wheel still scrolls).
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoScrollbar, NO_DOCK)
    undock_next()
    if imgui.Begin('Craft Hub##crafthub_main', state.visible, flags) then
        pcall(imgui.SetScrollX, 0)
        local _, top = imgui.GetCursorScreenPos()
        local ww, wh = imgui.GetWindowSize()
        if tonumber(ww) and tonumber(wh) then
            if (win.fit_frames or 0) == 0 and (not state.win_size or math.abs(state.win_size[1] - ww) > 0.5 or math.abs(state.win_size[2] - wh) > 0.5) then
                state.win_size = { math.floor(ww), math.floor(wh) }
                win.size = { ww, wh }
                win.size_dirty = os.clock()
            end
        end
        do  -- the window's thin top light (as on the /yui panel)
            local wx0, wy0 = call(imgui.GetWindowPos)
            if tonumber(wx0) and tonumber(ww) then
                T.blueprint(wx0, wy0, ww, tonumber(wh) or 600)   -- faint workbench grid behind everything
                T.window_light(wx0, wy0, ww, 12)
            end
        end
        if win.size_dirty and os.clock() - win.size_dirty > 1.0 and not call(imgui.IsMouseDown, 0) then
            win.size_dirty = nil
            save_settings()
        end
        local scrolling = (win.content_h or 0) > (tonumber(wh) or 0) - PAD_Y * 2
        local cw = math.max(min_cw, (tonumber(ww) or fit_w) - PAD_X * 2 - (scrolling and SCROLL_W or 0))
        T.begin_content(cw)
        render_header()
        if state.settings then
            render_settings()
        elseif (state.search[1] or ''):find('%S') then
            render_recipes()
        elseif state.tab == 1 then
            render_best()          -- the craft cards replace the old Overview tab
        elseif state.tab == 4 then
            render_fishing()
        elseif state.tab == 3 then
            render_recipes()
        else
            render_best()
        end
        T.end_content()
        local _, bottom = imgui.GetCursorScreenPos()
        win.content_h = math.max(60, bottom - top)
        local view_h = (tonumber(wh) or 0) - PAD_Y * 2
        local max_scroll = math.max(0, win.content_h - view_h)
        local sy = tonumber(call(imgui.GetScrollY)) or 0
        if sy > max_scroll + 0.5 then pcall(imgui.SetScrollY, max_scroll) end
        -- thin scrollbar in the right padding, starting and ending clear of the
        -- rounded corners. Drag the bar, or click the track to jump there.
        local wx, wy = call(imgui.GetWindowPos)
        wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
        if max_scroll > 0.5 and wx and wy and ww and wh then
            local tx, t1, t2 = wx + ww - 9, wy + 18, wy + wh - 18
            local th = t2 - t1
            local gh = math.max(30, th * view_h / win.content_h)
            local mx, my = call(imgui.GetMousePos)
            mx, my = tonumber(mx), tonumber(my)
            local over = mx and my and mx >= tx - 6 and mx <= wx + ww and my >= t1 and my <= t2
                and call(imgui.IsWindowHovered) and true or false
            if win.sdrag then
                if call(imgui.IsMouseDown, 0) and my then
                    local v = win.sdrag[2] + (my - win.sdrag[1]) / math.max(1, th - gh) * max_scroll
                    sy = math.max(0, math.min(max_scroll, v))
                    pcall(imgui.SetScrollY, sy)
                else
                    win.sdrag = nil
                end
            elseif over and call(imgui.IsMouseClicked, 0) then
                local gy0 = t1 + (th - gh) * (sy / max_scroll)
                if my < gy0 or my > gy0 + gh then
                    sy = math.max(0, math.min(max_scroll, (my - t1 - gh * 0.5) / math.max(1, th - gh) * max_scroll))
                    pcall(imgui.SetScrollY, sy)
                end
                win.sdrag = { my, sy }
            end
            local gy = t1 + (th - gh) * (math.min(sy, max_scroll) / max_scroll)
            local dl = DL()
            dl:PushClipRect({ wx, wy }, { wx + ww, wy + wh }, false)
            dl:AddRectFilled({ tx, t1 }, { tx + 4, t2 }, col(HUD.track, 0.05), 2)
            local hot = over or win.sdrag ~= nil
            dl:AddRectFilled({ tx, gy }, { tx + 4, gy + gh }, col(HUD.accent, hot and 0.70 or 0.38), 2)
            dl:PopClipRect()
        end
        if not win.sdrag then drag_window(win) end
    end
    draw_item_tip()
    imgui.End()
    T.pop_font(font_pushed)
    T.pop_style()
end)

ashita.events.register('load', 'crafthub_load_cb', function()
    T.load_font()
    load_settings()
    apply_rules()
    print(chat.header(addon.name):append(chat.success(
        ('v%s loaded - best synth for your skill in every craft. /craft to open, /craft help for commands.'):format(addon.version)
    )))
end)

ashita.events.register('unload', 'crafthub_unload_cb', function()
    save_settings()
end)
