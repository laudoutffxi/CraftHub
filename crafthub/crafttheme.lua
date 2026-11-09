-- crafthub theme: shared drawing helpers. "Dashboard" layout with the YunaUI /yui
-- panel's GLASS finish, tinted in Laudout's own navy with his periwinkle accent:
-- a see-through window, very dark see-through cards with a soft white hairline and
-- a thin light along their top edge, one lit card (the best synth), round corners.
-- Numbers carry the colour (green / yellow / red) only when they mean something.
local imgui = require('imgui')

-- Base palette: the /yui panel's glass values, in navy instead of warm brown.
-- frame / frame_hi / border / line are white washes, as on the /yui panel, so they
-- read as light on glass rather than as flat colours.
local C = {
    bg       = { 0.060, 0.068, 0.105, 0.92 },   -- window: navy, a little see-through
    side     = { 0.020, 0.025, 0.046, 0.72 },   -- glass card / inset (dark, see-through)
    card     = { 0.020, 0.025, 0.046, 0.72 },
    frame    = { 1.000, 1.000, 1.000, 0.07 },
    frame_hi = { 1.000, 1.000, 1.000, 0.12 },
    border   = { 1.000, 1.000, 1.000, 0.08 },
    line     = { 1.000, 1.000, 1.000, 0.07 },
    accent   = { 0.490, 0.557, 1.000, 1.00 },   -- Laudout's periwinkle
    text     = { 0.950, 0.955, 0.975, 1.00 },
    muted    = { 0.580, 0.605, 0.690, 1.00 },
}

local DEFAULT_TINT = C.accent

-- Names the rest of the addon uses.
local HUD = {
    accent      = C.accent,                      -- periwinkle: links, headings, selection
    accent2     = { 0.66, 0.71, 1.00, 1.00 },
    lavender    = { 0.78, 0.81, 1.00, 1.00 },
    text        = C.text,
    subtext     = { 0.72, 0.75, 0.84, 1.00 },
    muted       = C.muted,
    faint       = { 0.40, 0.43, 0.52, 1.00 },
    owned       = { 0.45, 0.90, 0.60, 1.00 },
    warn        = { 1.00, 0.68, 0.30, 1.00 },
    bad         = { 1.00, 0.45, 0.45, 1.00 },
    gold        = { 0.94, 0.77, 0.42, 1.00 },
    yellow      = { 1.00, 0.86, 0.45, 1.00 },
    red         = { 1.00, 0.45, 0.45, 1.00 },
    blue        = { 0.45, 0.66, 1.00, 1.00 },
    purple      = { 0.72, 0.56, 1.00, 1.00 },
    edge        = { 1.00, 1.00, 1.00, 1.00 },    -- hairline colour (drawn at low alpha, as on /yui)
    edge_hi     = C.accent,
    glow        = C.accent,
    window_bg   = C.bg,
    header_bg   = C.side,
    card        = C.card,
    inset       = C.side,
    frame       = C.frame,
    sel_fill    = C.frame_hi,
    card_line   = C.border,
    row_line    = C.line,
    track       = { 1.00, 1.00, 1.00, 0.07 },
    card_on     = { 0.490, 0.557, 1.000, 0.10 }, -- selected card: a periwinkle wash over the glass
}

local ui = { h = {} }   -- shared layout state (panel heights, content width)

local CORNERS_ALL = ImDrawFlags_RoundCornersAll or ImDrawCornerFlags_All or 15

local function rgba(c, a) return { c[1], c[2], c[3], a or c[4] } end
local function col(c, a) return imgui.GetColorU32(rgba(c, a)) end
local function pulse(speed) return (math.sin(os.clock() * (speed or 3.0)) + 1.0) * 0.5 end
local function line_h() return tonumber(imgui.GetTextLineHeight()) or 13 end
local function text_w(s) return tonumber((imgui.CalcTextSize(s))) or 0 end
local function DL() return imgui.GetWindowDrawList() end

-- Mix colour a towards b by t (0..1).
local function mix(a, b, t, alpha)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, alpha or a[4] or 1 }
end
local WHITE, BLACK = { 1, 1, 1, 1 }, { 0, 0, 0, 1 }

-- The window keeps Laudout's periwinkle everywhere; these stay so callers don't break.
local function set_tint() end
local function tint_step() end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function text(x, y, c, s, scale)
    local dl = DL()
    if scale and scale ~= 1 and type(imgui.GetFont) == 'function' and type(imgui.GetFontSize) == 'function' then
        local ok = pcall(function() dl:AddText(imgui.GetFont(), imgui.GetFontSize() * scale, { x, y }, col(c), s) end)
        if ok then return end
    end
    dl:AddText({ x, y }, col(c), s)
end

-- Right-aligned text ending at x (scale optional).
local function rtext(x, y, c, s, scale)
    text(x - text_w(s) * (scale or 1), y, c, s, scale)
end

-- Shorten s with a trailing '.' until it fits in w.
local function fit(s, w, scale)
    local k = scale or 1
    if text_w(s) * k <= w then return s end
    while #s > 2 and text_w(s .. '.') * k > w do s = s:sub(1, -2) end
    return s .. '.'
end

-- Small caps label: spaced-out letters. Returns its width.
local function caps(x, y, c, s, spacing)
    local sp = spacing or 1.5
    local cx = x
    for i = 1, #s do
        local ch = s:sub(i, i)
        text(cx, y, c, ch, 0.82)
        cx = cx + text_w(ch) * 0.82 + sp
    end
    return cx - x - sp
end

local function caps_w(s, spacing)
    local sp = spacing or 1.5
    local w = 0
    for i = 1, #s do w = w + text_w(s:sub(i, i)) * 0.82 + sp end
    return w - sp
end

--------------------------------------------------------------------------------
-- Small shapes
--------------------------------------------------------------------------------

-- Status dot. glow > 0 adds a soft halo (used for "in progress" states).
local function dot(cx, cy, r, c, glow)
    local dl = DL()
    if glow and glow > 0 then
        dl:AddCircleFilled({ cx, cy }, r * 2.2, col(c, 0.10 * glow), 20)
        dl:AddCircleFilled({ cx, cy }, r * 1.5, col(c, 0.18 * glow), 20)
    end
    dl:AddCircleFilled({ cx, cy }, r, col(c), 16)
end

-- Marker (kept as `diamond` for the callers): a small crystal-cut diamond.
local function diamond(cx, cy, r, c, filled, glow)
    local dl = DL()
    if glow and glow > 0 then dl:AddCircleFilled({ cx, cy }, r * 1.8, col(c, 0.12 * glow), 20) end
    local t, rr, b, l = { cx, cy - r }, { cx + r * 0.8, cy }, { cx, cy + r }, { cx - r * 0.8, cy }
    if filled then
        dl:AddTriangleFilled(t, rr, b, col(c))
        dl:AddTriangleFilled(t, b, l, col(mix(c, WHITE, 0.3)))
    else
        local cc = col(c, 0.85)
        dl:AddLine(t, rr, cc, 1.3); dl:AddLine(rr, b, cc, 1.3); dl:AddLine(b, l, cc, 1.3); dl:AddLine(l, t, cc, 1.3)
    end
end

-- Rounded box helpers (the old chamfer names stay so nothing else has to change).
-- k is the corner radius; c is an already-converted colour.
local function chamfer_fill(x, y, w, h, k, c)
    DL():AddRectFilled({ x, y }, { x + w, y + h }, c, k, CORNERS_ALL)
end

local function chamfer_line(x, y, w, h, k, c, t)
    DL():AddRect({ x, y }, { x + w, y + h }, c, k, CORNERS_ALL, t or 1)
end

-- Glass highlight: a faint bright line just inside the top edge.
local function glass_top(x, y, w, r)
    DL():AddRectFilled({ x + r, y + 1 }, { x + w - r, y + 2 }, col(WHITE, 0.06))
end

-- opts: k (corner radius-ish), fill (colour or false), edge (border colour), alpha (border strength)
local function frame(x, y, w, h, opts)
    opts = opts or {}
    local r = (opts.k or 6) + 2
    if opts.fill ~= false then chamfer_fill(x, y, w, h, r, col(opts.fill or HUD.card)) end
    local e = opts.edge or HUD.edge
    local a = opts.alpha or 0.85
    local ba = (e == HUD.edge) and (0.16 * a / 0.85) or (0.50 * a)
    chamfer_line(x + 0.5, y + 0.5, w - 1, h - 1, r, col(e, ba), 1)
end

-- Tag (status pill): small rounded tinted box, text a size smaller than the
-- row it sits on, centred on that row's line.
local PILL_SCALE = 0.76
local function pill_w(s) return text_w(s) * PILL_SCALE + 14 end

local function pill(x, y, s, c, fill)
    local lh = line_h()
    local th = lh * PILL_SCALE
    local w, h = pill_w(s), math.floor(th + 5)
    local top = math.floor(y + (lh - h) * 0.5)
    local dl = DL()
    -- /yui glass pill: a faint wash of the colour and a clear edge in it
    dl:AddRectFilled({ x, top }, { x + w, top + h }, col(c, math.min(0.16, (fill or 0.08))), h * 0.5)
    dl:AddRect({ x + 0.5, top + 0.5 }, { x + w - 0.5, top + h - 0.5 }, col(c, 0.65), h * 0.5, CORNERS_ALL, 1.2)
    text(x + 7, top + (h - th) * 0.5, c, s, PILL_SCALE)
    return w
end

local function bar(x, y, w, h, frac, c)
    local dl = DL()
    frac = math.max(0, math.min(1, frac))
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col(HUD.track), h * 0.5)
    if frac > 0 then
        local fw = math.max(h, w * frac)
        dl:AddRectFilled({ x, y - 1 }, { x + fw, y + h + 1 }, col(c, 0.18), h)
        dl:AddRectFilled({ x, y }, { x + fw, y + h }, col(c, 0.95), h * 0.5)
    end
end

-- Ten-step meter (one step per tenth of a level). filled = whole steps, part = 0..1 of the next.
local function meter(x, y, w, h, filled, part, c)
    local dl = DL()
    local gap = 3
    local sw = (w - gap * 9) / 10
    for i = 0, 9 do
        local sx = x + i * (sw + gap)
        if i < filled then
            dl:AddRectFilled({ sx - 1, y - 1 }, { sx + sw + 1, y + h + 1 }, col(c, 0.22), 3)
            dl:AddRectFilled({ sx, y }, { sx + sw, y + h }, col(c), 2)
        else
            dl:AddRectFilled({ sx, y }, { sx + sw, y + h }, col(HUD.track), 2)
            if i == filled and (part or 0) > 0 then
                dl:AddRectFilled({ sx, y }, { sx + sw * part, y + h }, col(c, 0.6), 2)
            end
        end
    end
end

-- Soft shadow under a floating card: a few dark rounded layers, growing and
-- fading, pushed a little down. Gives the glass cards depth over the window.
local function shadow(x, y, w, h, r, strength)
    local dl = DL()
    local s = strength or 1
    for i = 3, 1, -1 do
        local g = i * 2
        dl:AddRectFilled({ x - g * 0.5, y - g * 0.2 + 2 }, { x + w + g * 0.5, y + h + g + 1 },
            col(BLACK, (0.10 - i * 0.022) * s), r + g * 0.5)
    end
end

-- Smooth values for small animations (rings and bars fill up instead of jumping).
-- key: any string; target: where the value should go. Starts from `from` (default 0).
local anim = {}
local function ease(key, target, rate, from)
    local now = os.clock()
    local a = anim[key]
    if not a then a = { v = from or 0, t = now }; anim[key] = a end
    local dt = math.min(0.1, math.max(0, now - a.t))
    a.t = now
    a.v = a.v + (target - a.v) * math.min(1, dt * (rate or 7))
    if math.abs(target - a.v) < 0.0005 then a.v = target end
    return a.v
end

-- A faint blueprint grid on the window background: the crafter's workbench.
-- Brightest near the top, fading out lower down.
local function blueprint(x, y, w, h)
    local dl = DL()
    local step = 26
    local fade = math.min(h, 520)
    for gx = x + step, x + w - 1, step do
        pcall(function()
            dl:AddRectFilledMultiColor({ gx, y }, { gx + 1, y + fade },
                col(C.accent, 0.045), col(C.accent, 0.045), col(C.accent, 0), col(C.accent, 0))
        end)
    end
    for gy = y + step, y + fade, step do
        local a = 0.045 * (1 - (gy - y) / fade)
        dl:AddRectFilled({ x, gy }, { x + w, gy + 1 }, col(C.accent, a))
    end
end

-- Glass card (as on the /yui panel): dark see-through fill, a soft white hairline,
-- and a thin light along the top edge. An accent tints the edge instead.
local CARD_R = 16
local function card_bg(x, y, w, h, accent, strength)
    local s = strength or 1
    local dl = DL()
    shadow(x, y, w, h, CARD_R)
    chamfer_fill(x, y, w, h, CARD_R, col(HUD.card))
    if accent then
        chamfer_line(x + 0.5, y + 0.5, w - 1, h - 1, CARD_R, col(accent, 0.18 + 0.37 * s), 1)
    else
        chamfer_line(x + 0.5, y + 0.5, w - 1, h - 1, CARD_R, col(WHITE, 0.07), 1)
    end
    dl:AddLine({ x + CARD_R, y + 1 }, { x + w - CARD_R, y + 1 }, col(WHITE, 0.11), 1)
end

-- The lit card (the /yui panel's first card): dark glass with a faint wash of the
-- accent (a little more at the top), the accent on the edge (brighter on hover), a
-- light line along the top, and a soft light sweeping across it every 6 seconds.
local function hero_card(x, y, w, h, c)
    local dl = DL()
    local r = CARD_R
    c = c or C.accent
    local mx, my = imgui.GetMousePos()
    if type(mx) == 'table' then mx, my = mx.x or mx[1], mx.y or mx[2] end
    local hov = mx and my and mx >= x and mx <= x + w and my >= y and my <= y + h
    shadow(x, y, w, h, r, 1.3)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col({ 0.020, 0.025, 0.046, 0.70 }), r)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col(c, 0.08), r)
    -- a little more light at the top, fading out smoothly (no hard edge): the rounded
    -- top strip, then a plain gradient below the corners
    local wb = y + math.min(110, h * 0.5)
    dl:AddRectFilled({ x, y }, { x + w, y + r }, col(c, 0.05), r, ImDrawFlags_RoundCornersTop or ImDrawCornerFlags_Top or 3)
    pcall(function() dl:AddRectFilledMultiColor({ x, y + r }, { x + w, wb }, col(c, 0.05), col(c, 0.05), col(c, 0), col(c, 0)) end)
    local ph = (os.clock() % 6) / 1.1
    if ph < 1 then
        local bw = 70
        local sx = x - bw * 2 + (w + bw * 3) * ph
        if pcall(function() dl:PushClipRect({ x + 2, y + 2 }, { x + w - 2, y + h - 2 }, true) end) then
            pcall(function()
                dl:AddQuadFilled({ sx + bw, y }, { sx + bw * 2, y }, { sx + bw, y + h }, { sx, y + h },
                    col(WHITE, 0.05 * math.sin(ph * math.pi)))
            end)
            dl:PopClipRect()
        end
    end
    dl:AddRect({ x, y }, { x + w, y + h }, col(c, hov and 0.90 or 0.55), r, CORNERS_ALL, 1)
    dl:AddLine({ x + r, y + 0.5 }, { x + w - r, y + 0.5 }, col({ 0.92, 0.95, 1.00, 0.50 }), 1)
end

-- The window's own top light (as on /yui): one thin bright line along the top edge.
local function window_light(x, y, w, r)
    DL():AddLine({ x + r, y + 1 }, { x + w - r, y + 1 }, col({ 0.95, 0.96, 1.00, 0.22 }), 1)
end

-- Progress ring (e.g. success chance): a faint full track, the filled arc from the
-- top going clockwise, rounded ends.
local function ring(cx, cy, r, thick, frac, c)
    local dl = DL()
    frac = math.max(0, math.min(1, frac or 0))
    dl:AddCircle({ cx, cy }, r, col(HUD.track, 0.07), 64, thick)
    if frac <= 0 then return end
    local a0 = -math.pi * 0.5
    local a1 = a0 + frac * math.pi * 2
    local cc = col(c)
    local ok = pcall(function()
        dl:PathClear()
        dl:PathArcTo({ cx, cy }, r, a0, a1, math.max(8, math.floor(64 * frac)))
        dl:PathStroke(cc, 0, thick)
    end)
    if not ok then
        local n = math.max(8, math.floor(72 * frac))
        local px, py = cx + math.cos(a0) * r, cy + math.sin(a0) * r
        for i = 1, n do
            local a = a0 + (a1 - a0) * i / n
            local nx, ny = cx + math.cos(a) * r, cy + math.sin(a) * r
            dl:AddLine({ px, py }, { nx, ny }, cc, thick)
            px, py = nx, ny
        end
    end
    -- round caps
    dl:AddCircleFilled({ cx + math.cos(a0) * r, cy + math.sin(a0) * r }, thick * 0.5, cc, 16)
    dl:AddCircleFilled({ cx + math.cos(a1) * r, cy + math.sin(a1) * r }, thick * 0.5, cc, 16)
end

-- Card title: title, muted subtitle, optional right text.
local function card_title(x, y, w, c, title, sub, right, right_col)
    text(x, y, c, title)
    if sub then text(x + text_w(title) + 10, y, HUD.muted, sub) end
    if right then text(x + w - text_w(right), y, right_col or HUD.faint, right) end
end

-- Hairline. (c / a kept for callers; it's always a quiet line now.)
local function rule(x, y, w, c, a)
    DL():AddRectFilled({ x, y }, { x + w, y + 1 }, col(C.line, 0.10 + 0.06 * (a or 0.6)))
end

-- Panel heading: a small tinted gem, the title in spaced capitals, a muted note after it.
-- Returns its width.
local function heading(x, y, title, sub, c)
    local lh = line_h()
    local cc = c or C.accent
    diamond(x + 4, y + lh * 0.5, 4.5, cc, true, 0.7)
    local tw = caps(x + 15, y + lh * 0.1, cc, title:upper(), 1.6)
    if sub then text(x + 15 + tw + 12, y, HUD.muted, sub) end
    return 15 + tw + (sub and (12 + text_w(sub)) or 0)
end

-- Dark rounded backing for a small label that sits on top of the ring / glow.
local function label_bg(x, y, w, h)
    DL():AddRectFilled({ x, y }, { x + w, y + h }, col(C.bg, 0.78), math.min(8, h * 0.5))
end

--------------------------------------------------------------------------------
-- The crystal
--------------------------------------------------------------------------------

-- Soft round glow (stacked circles; ImGui has no radial gradient).
local function glow(cx, cy, r, c, strength)
    local dl = DL()
    local s = strength or 1
    -- many thin steps, faintest at the edge, so no ring shows
    for i = 16, 1, -1 do
        local f = i / 16
        dl:AddCircleFilled({ cx, cy }, r * f, col(c, (0.006 + 0.030 * (1 - f)) * s), 40)
    end
end

-- Motes of light drifting up around the crystal (n of them, within radius r).
local function sparkles(cx, cy, r, c, n)
    local dl = DL()
    local t = os.clock()
    local lc = mix(c, WHITE, 0.55)
    for i = 1, n or 10 do
        local ph = (t * (0.16 + (i % 4) * 0.03) + i * 0.618) % 1
        local sx = cx + math.sin(i * 12.9898) * r * 0.75 + math.sin(t * 0.9 + i) * 5
        local sy = cy + r * 0.55 - ph * r * 1.25
        local a = math.sin(ph * math.pi)
        local sz = 1.1 + (i % 3) * 0.55
        dl:AddCircleFilled({ sx, sy }, sz * 2.6, col(c, 0.10 * a), 12)
        dl:AddCircleFilled({ sx, sy }, sz, col(lc, 0.85 * a), 8)
    end
end

-- Pool of light under a floating crystal (bright in the middle, fading out sideways).
-- A real left-right gradient (two halves meeting in the middle), so there are no steps.
local function light_pool(cx, y, w, c)
    local dl = DL()
    local hw = w * 0.5
    local function band(h, a, aw)
        local mid, none = col(c, a), col(c, 0)
        local x1, x2 = cx - hw * aw, cx + hw * aw
        local ok = pcall(function()
            dl:AddRectFilledMultiColor({ x1, y - h }, { cx, y + h }, none, mid, mid, none)
            dl:AddRectFilledMultiColor({ cx, y - h }, { x2, y + h }, mid, none, none, mid)
        end)
        return ok
    end
    band(2.5, 0.10, 1.0)      -- soft wide haze
    band(0.6, 0.55, 0.8)      -- thin bright core
end

-- A crystal like the game's: a long six-sided prism pointed at both ends, seen
-- face-on (left face, front face, right face), lit softly from the upper left.
-- Centred on (cx, cy), w x h. opts.hollow draws an empty outline (no crystal yet);
-- opts.glow (0..1) adds the halo.
local function crystal(cx, cy, w, h, c, opts)
    opts = opts or {}
    local dl = DL()
    local hw, iw = w * 0.5, w * 0.17               -- outer half-width, front face half-width
    local T   = { cx, cy - h * 0.5 }
    local UL  = { cx - hw, cy - h * 0.22 }
    local UR  = { cx + hw, cy - h * 0.22 }
    local LL  = { cx - hw, cy + h * 0.22 }
    local LR  = { cx + hw, cy + h * 0.22 }
    local B   = { cx, cy + h * 0.5 }
    local IUL = { cx - iw, cy - h * 0.30 }
    local IUR = { cx + iw, cy - h * 0.30 }
    local ILL = { cx - iw, cy + h * 0.30 }
    local ILR = { cx + iw, cy + h * 0.30 }
    if opts.hollow then
        local cc = col(c, 0.35)
        dl:AddLine(T, UR, cc, 1.2); dl:AddLine(UR, LR, cc, 1.2); dl:AddLine(LR, B, cc, 1.2)
        dl:AddLine(B, LL, cc, 1.2); dl:AddLine(LL, UL, cc, 1.2); dl:AddLine(UL, T, cc, 1.2)
        return
    end
    if (opts.glow or 0) > 0 then glow(cx, cy, math.max(w, h) * 1.0, c, opts.glow) end
    local function f(t, k) return col(mix(c, t, k)) end
    local function tri(a, b, d, cc) dl:AddTriangleFilled(a, b, d, cc) end
    -- top cap (brightest, but only a little lighter than the colour)
    tri(T, IUL, UL, f(WHITE, 0.28))
    tri(T, IUR, IUL, f(WHITE, 0.18))
    tri(T, UR, IUR, f(BLACK, 0.05))
    -- sides
    tri(UL, IUL, ILL, f(BLACK, 0.10)); tri(UL, ILL, LL, f(BLACK, 0.10))
    tri(IUR, UR, LR, f(BLACK, 0.38)); tri(IUR, LR, ILR, f(BLACK, 0.38))
    -- front face: a soft top-to-bottom fade
    local ft, fb = col(mix(c, WHITE, 0.12)), col(mix(c, BLACK, 0.22))
    local ok = pcall(function() dl:AddRectFilledMultiColor(IUL, ILR, ft, ft, fb, fb) end)
    if not ok then dl:AddRectFilled(IUL, ILR, f(BLACK, 0.05)) end
    -- bottom point (darkest)
    tri(LL, ILL, B, f(BLACK, 0.30))
    tri(ILL, ILR, B, f(BLACK, 0.40))
    tri(ILR, LR, B, f(BLACK, 0.55))
    -- facet ridges, very faint
    local fe = col(WHITE, 0.10)
    dl:AddLine(T, IUL, fe, 1); dl:AddLine(T, IUR, fe, 1)
    dl:AddLine(IUL, IUR, fe, 1); dl:AddLine(ILL, ILR, fe, 1)
    dl:AddLine(IUL, ILL, fe, 1); dl:AddLine(IUR, ILR, fe, 1)
    dl:AddLine(ILL, B, fe, 1); dl:AddLine(ILR, B, fe, 1)
    dl:AddLine(UL, IUL, fe, 1); dl:AddLine(UR, IUR, fe, 1); dl:AddLine(LL, ILL, fe, 1); dl:AddLine(LR, ILR, fe, 1)
    -- outline
    local oe = col(mix(c, WHITE, 0.35), 0.65)
    dl:AddLine(T, UR, oe, 1); dl:AddLine(UR, LR, oe, 1); dl:AddLine(LR, B, oe, 1)
    dl:AddLine(B, LL, oe, 1); dl:AddLine(LL, UL, oe, 1); dl:AddLine(UL, T, oe, 1)
    -- a thin glassy streak down the front face, with a soft glint sliding down it now and then
    if h >= 30 then
        local sx = cx - iw * 0.45
        local y1, y2 = cy - h * 0.24, cy + h * 0.14
        dl:AddLine({ sx, y1 }, { sx, y2 }, col(WHITE, 0.13), 1.2)
        local g = (os.clock() * 0.30) % 1
        if g < 0.3 then
            local a = math.sin(g / 0.3 * math.pi)
            local gy = y1 + (y2 - y1) * (g / 0.3)
            dl:AddCircleFilled({ sx, gy }, 3.5, col(WHITE, 0.10 * a), 10)
            dl:AddCircleFilled({ sx, gy }, 1.5, col(WHITE, 0.55 * a), 8)
        end
    end
end

--------------------------------------------------------------------------------
-- Clipping / layout
--------------------------------------------------------------------------------

-- Clip drawing to a box. Ashita's renderer goes blank for the rest of the frame
-- if it's handed an empty clip rectangle, which is what ImGui produces when the
-- box is scrolled completely out of view. So only clip when the box is actually
-- inside the window; off-screen boxes are hidden by the window's own clipping.
-- Returns true if a clip rect was pushed (pass it to pop_clip).
local CLIP_MARGIN = 8
local function push_clip(x1, y1, x2, y2)
    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()
    wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
    if not (wx and wy and ww and wh) then return false end
    local ix1, iy1 = math.max(x1, wx + CLIP_MARGIN), math.max(y1, wy + CLIP_MARGIN)
    local ix2, iy2 = math.min(x2, wx + ww - CLIP_MARGIN), math.min(y2, wy + wh - CLIP_MARGIN)
    if ix2 - ix1 < 1 or iy2 - iy1 < 1 then return false end
    DL():PushClipRect({ x1, y1 }, { x2, y2 }, true)
    return true
end

local function pop_clip(pushed)
    if pushed then DL():PopClipRect() end
end

local function hit(id, x, y, w, h)
    local cx, cy = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ x, y })
    local clicked = imgui.InvisibleButton(id, { w, h })
    local hov = imgui.IsItemHovered()
    if hov then imgui.SetMouseCursor(ImGuiMouseCursor_Hand) end
    imgui.SetCursorScreenPos({ cx, cy })
    return clicked, hov
end

local function advance(w, h) imgui.Dummy({ w, h }) end

ui.cw = ui.cw or 760
ui.left_x = ui.left_x or 0
ui.inset = 4   -- keeps panel edges off the window's clip line
local function avail_w()
    local cx = imgui.GetCursorScreenPos()
    return ui.cw - (cx - ui.left_x) - ui.inset
end

-- Start a window's content: reserve the full width, then step in by ui.inset.
local function begin_content(cw)
    local x, y = imgui.GetCursorScreenPos()
    ui.left_x, ui.cw = x, cw
    imgui.Dummy({ cw, 0 })
    imgui.SetCursorScreenPos({ x + ui.inset, y + ui.inset })
end

local function end_content()
    imgui.Dummy({ 0, ui.inset })
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

-- Segmented control. items = { { key, label, badge, badge_col, light }, ... }
-- A dark rounded track; the selected segment is lifted (lighter fill, white text),
-- the rest are muted. opts.width stretches it to that width.
local SEG_PAD = 3   -- track padding around the segments
local function seg_item_w(t, pad) return text_w(t[2]) + (t[3] and (text_w(t[3]) + 8) or 0) + (t[5] and 14 or 0) + pad * 2 end

local function seg_tabs(id, items, active, x, y, color, small, opts)
    opts = opts or {}
    local dl = DL()
    local lh = line_h()
    local ih = lh + (small and 6 or 8)          -- segment height
    local th = ih + SEG_PAD * 2                  -- track height
    local pad = small and 10 or 13
    local natural = 0
    for _, t in ipairs(items) do natural = natural + seg_item_w(t, pad) end
    local extra = 0
    if opts.width then
        extra = math.max(0, (opts.width - SEG_PAD * 2 - natural) / #items)
    end
    local total = natural + extra * #items + SEG_PAD * 2
    dl:AddRectFilled({ x, y }, { x + total, y + th }, col(C.side), 8)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + total - 0.5, y + th - 0.5 }, col(C.border), 8, CORNERS_ALL, 1)

    local tx = x + SEG_PAD
    local sy = y + SEG_PAD
    local clicked_key = nil
    for i, t in ipairs(items) do
        local key, label, badge = t[1], t[2], t[3]
        local on = active == key
        local tw = seg_item_w(t, pad) + extra
        local clicked, hov = hit(('##%s_%s'):format(id, tostring(key)), tx, sy, tw, ih)
        if clicked then clicked_key = key end
        if on then
            dl:AddRectFilled({ tx, sy }, { tx + tw, sy + ih }, col(C.frame_hi), 6)
            dl:AddRect({ tx + 0.5, sy + 0.5 }, { tx + tw - 0.5, sy + ih - 0.5 }, col(C.border, 0.18), 6, CORNERS_ALL, 1)
        elseif hov then
            dl:AddRectFilled({ tx, sy }, { tx + tw, sy + ih }, col(C.frame, 0.55), 6)
        end
        local light = t[5]
        local cw = text_w(label) + (badge and (text_w(badge) + 8) or 0) + (light and 14 or 0)
        local lx = tx + (tw - cw) * 0.5
        local ty = sy + (ih - lh) * 0.5
        if light then
            dot(lx + 4, ty + lh * 0.5, 3.5, light, 0.4 + pulse(2) * 0.6)
            lx = lx + 14
        end
        text(lx, ty, on and { 1, 1, 1, 1 } or (hov and HUD.text or HUD.muted), label)
        if badge then
            text(lx + text_w(label) + 8, ty, t[4] or (on and HUD.accent2 or HUD.faint), badge)
        end
        tx = tx + tw
    end
    return clicked_key, total, th
end

local function seg_width(items, small)
    local pad = small and 10 or 13
    local w = 0
    for _, t in ipairs(items) do w = w + seg_item_w(t, pad) end
    return w + SEG_PAD * 2
end

-- Text tabs with a glowing tint underline (the main navigation).
-- items = { { key, label, badge, badge_col }, ... }. Returns clicked_key, width, height.
local function line_tabs(id, items, active, x, y)
    local dl = DL()
    local lh = line_h()
    local h = lh + 10
    local gap = 22
    local tx = x
    local clicked_key = nil
    for _, t in ipairs(items) do
        local key, label, badge = t[1], t[2], t[3]
        local on = active == key
        local lw = text_w(label) + (badge and (text_w(badge) + 7) or 0)
        local clicked, hov = hit(('##%s_%s'):format(id, tostring(key)), tx - 4, y, lw + 8, h)
        if clicked then clicked_key = key end
        text(tx, y + 2, on and WHITE or (hov and HUD.text or HUD.muted), label)
        if badge then text(tx + text_w(label) + 7, y + 2, t[4] or (on and HUD.accent2 or HUD.faint), badge) end
        if on then
            local uy = y + lh + 6
            dl:AddRectFilled({ tx - 2, uy - 2 }, { tx + lw + 2, uy + 4 }, col(C.accent, 0.15), 3)
            dl:AddRectFilled({ tx, uy }, { tx + lw, uy + 2 }, col(C.accent), 1)
        end
        tx = tx + lw + gap
    end
    return clicked_key, tx - gap - x, h
end

-- Pill switch with a label to its right. Returns clicked, width.
local function toggle_w(label) return 38 + 9 + text_w(label) + 6 end

-- The /yui switch: on = solid accent, off = dark glass with a faint edge; a white knob.
local function toggle_chip(id, label, on, x, y, c)
    local dl = DL()
    local lh = line_h()
    local h = lh + 10
    local sw, sh = 38, 20
    local w = toggle_w(label)
    local clicked, hov = hit(id, x, y, w, h)
    local sx, sy = x, y + (h - sh) * 0.5
    local cc = c or C.accent
    dl:AddRectFilled({ sx, sy }, { sx + sw, sy + sh }, on and col(cc) or col(BLACK, hov and 0.45 or 0.35), sh * 0.5)
    if not on then
        dl:AddRect({ sx, sy }, { sx + sw, sy + sh }, col(WHITE, 0.12), sh * 0.5, CORNERS_ALL, 1)
    end
    local kx = on and (sx + sw - sh * 0.5) or (sx + sh * 0.5)
    dl:AddCircleFilled({ kx, sy + sh * 0.5 }, sh * 0.5 - 2, col(WHITE, on and 1 or 0.92), 24)
    text(sx + sw + 9, y + (h - lh) * 0.5, on and HUD.text or (hov and HUD.subtext or HUD.muted), label)
    return clicked, w
end

-- Quiet outlined button. Returns clicked, width, height.
local function ghost_w(label) return text_w(label) + 24 end

local function ghost(id, x, y, label, c)
    local dl = DL()
    local lh = line_h()
    local w, h = ghost_w(label), lh + 12
    local clicked, hov = hit(id, x, y, w, h)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col(WHITE, hov and 0.08 or 0.035), 8)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + w - 0.5, y + h - 0.5 }, col(c or WHITE, c and 0.55 or 0.10), 8, CORNERS_ALL, 1)
    text(x + 12, y + 6, hov and HUD.text or (c or HUD.subtext), label)
    return clicked, w, h
end

-- Panel wrapper: card sized from last frame's measurement.
local function panel(id, accent, draw_fn, strength)
    local x, y = imgui.GetCursorScreenPos()
    local w = avail_w()
    local h = ui.h[id] or 120
    card_bg(x, y, w, h, accent, strength or 0.9)
    local content_h = draw_fn(x + 14, y + 12, w - 28)
    ui.h[id] = content_h + 24
    advance(w, h)
    imgui.Dummy({ 0, 2 })
end

-- Row of controls on the window background; draw_fn(x, y, w) returns its height.
-- opts.line draws a hairline under it (the header uses this).
local function band(id, draw_fn, opts)
    local x, y = imgui.GetCursorScreenPos()
    local w = avail_w()
    local h = ui.h[id] or 40
    local ch = draw_fn(x + 2, y + 4, w - 4)
    ui.h[id] = ch + 8
    if opts and opts.line then
        DL():AddRectFilled({ x - ui.inset, y + h + 2 }, { x + w + ui.inset, y + h + 3 }, col(C.line))
        advance(w, h + 6)
    else
        advance(w, h)
    end
    imgui.Dummy({ 0, 2 })
end

-- Title, pure type: CRAFT in Segoe UI Bold, a thin periwinkle line, HUB in Segoe UI
-- Light, both in wide capitals. The two weights come from the Windows font folder
-- (load_font below); without them the normal font is used.
local TITLE_PX = 21
local TITLE_SP = 3.4        -- extra space between letters
local TITLE_GAP = 12        -- space each side of the divider
local tfont = {}            -- b = bold, l = light (filled by load_font)

local function push_tfont(f)
    if f == nil then return false end
    local ok
    if f.LegacySize ~= nil then ok = pcall(imgui.PushFont, f, TITLE_PX) else ok = pcall(imgui.PushFont, f) end
    return ok and true or false
end

-- draws (or only measures, when c is nil) one spaced word in the current font
local function spaced_word(x, y, s, c)
    local cx = x
    for i = 1, #s do
        local ch = s:sub(i, i)
        if c then text(cx, y, c, ch) end
        cx = cx + text_w(ch) + TITLE_SP
    end
    return cx - x - TITLE_SP
end

local function title_parts(s)
    local first, rest = s:match('^(%S+)%s+(.*)$')
    return first or s, rest or ''
end

local function title_w(s)
    local first, rest = title_parts(s)
    local p = push_tfont(tfont.b)
    local w = spaced_word(0, 0, first, nil)
    if p then imgui.PopFont() end
    if rest ~= '' then
        p = push_tfont(tfont.l)
        w = w + TITLE_GAP * 2 + 1 + spaced_word(0, 0, rest, nil)
        if p then imgui.PopFont() end
    end
    return w
end

-- CRAFT gets built: when the window opens, its letters are made one by one (each
-- rises into place, starts hot in periwinkle, cools to white, and throws a little
-- spark as it lands); then every 12 s a quiet "forge pass" runs across the word,
-- each letter glowing for a moment with a tiny spark. Nothing ever disappears.
local title_anim = { last = 0, open = 0 }
local BUILD_STEP, BUILD_LEN = 0.11, 0.34   -- seconds between letters / one letter's build
local FORGE_EVERY, FORGE_STEP, FORGE_LEN = 12, 0.09, 0.45

local function spark(dl, sx, sy, f, cc)
    -- f 0..1: three short rays bursting from (sx, sy), growing and fading, plus a flash
    local a = 1 - f
    for _, ang in ipairs({ -2.5, -1.57, -0.64 }) do
        local r1, r2 = 1 + 3 * f, 3 + 6 * f
        dl:AddLine({ sx + math.cos(ang) * r1, sy + math.sin(ang) * r1 },
            { sx + math.cos(ang) * r2, sy + math.sin(ang) * r2 }, col(cc, 0.9 * a), 1.1)
    end
    dl:AddCircleFilled({ sx, sy }, 1.6 * a + 0.4, col(WHITE, 0.9 * a), 8)
end

local function title_text(x, y, h, s, c)
    local first, rest = title_parts(s)
    local dl = DL()
    local now = os.clock()
    if now - title_anim.last > 0.5 then title_anim.open = now end   -- window just (re)opened: build again
    title_anim.last = now
    local p = push_tfont(tfont.b)
    local lh = line_h()
    local ty = y + (h - lh) * 0.5
    local base = c or HUD.text
    local hot = HUD.accent2 or C.accent
    local tb = now - title_anim.open
    local tf = (tb - BUILD_STEP * #first - BUILD_LEN - 1.5) % FORGE_EVERY   -- time into the current forge pass
    local cx = x
    for i = 1, #first do
        local ch = first:sub(i, i)
        local cw = text_w(ch)
        local cc, dy, alpha = base, 0, 1
        local sp = nil
        -- build (once, on open)
        local bt = (tb - (i - 1) * BUILD_STEP) / BUILD_LEN
        if bt < 1 then
            if bt <= 0 then alpha = 0 else
                local e = 1 - (1 - bt) * (1 - bt)        -- ease out
                dy = (1 - e) * 7
                alpha = math.min(1, bt * 2.2)
                cc = mix(hot, base, e)
            end
        elseif bt < 1 + 0.9 then
            sp = (bt - 1) / 0.9                          -- the landing spark
        end
        -- forge pass (repeats), only once the word is built
        if bt >= 1 then
            local ft = (tf - (i - 1) * FORGE_STEP) / FORGE_LEN
            if tb > BUILD_STEP * #first + BUILD_LEN + 1.5 and ft >= 0 and ft < 1 then
                local g = math.sin(ft * math.pi)
                cc = mix(base, hot, g * 0.85)
                if ft < 0.6 then sp = sp or ft / 0.6 end
            end
        end
        if alpha > 0 then
            text(cx, ty + dy, { cc[1], cc[2], cc[3], alpha }, ch)
            if not p then text(cx + 0.6, ty + dy, { cc[1], cc[2], cc[3], alpha }, ch) end
        end
        if sp and sp < 1 then spark(dl, cx + cw * 0.5, ty + lh - 1, sp, hot) end
        cx = cx + cw + TITLE_SP
    end
    local w1 = cx - x - TITLE_SP
    if p then imgui.PopFont() end
    if rest == '' then return end
    local dx = x + w1 + TITLE_GAP
    local mid = y + h * 0.5
    DL():AddRectFilled({ dx, mid - lh * 0.42 }, { dx + 1, mid + lh * 0.42 }, col(C.accent, 0.55))
    p = push_tfont(tfont.l)
    lh = line_h()
    spaced_word(dx + 1 + TITLE_GAP, y + (h - lh) * 0.5, rest, mix(C.accent, HUD.lavender, 0.35))
    if p then imgui.PopFont() end
end

-- No logo in this style (kept so callers don't break).
local function logo() end

-- Ghost "X" close button. Returns true when clicked.
local function close_button(x, y, s)
    local dl = DL()
    local clicked, hov = hit('##ch_close', x, y, s, s)
    -- one centre for the circle and the X, snapped to the pixel grid so both line up
    local cx, cy = math.floor(x + s * 0.5) + 0.5, math.floor(y + s * 0.5) + 0.5
    -- hover: a soft light glass circle (a red wash on navy looked muddy)
    if hov then
        dl:AddCircleFilled({ cx, cy }, s * 0.5, col(WHITE, 0.08), 40)
        dl:AddCircle({ cx, cy }, s * 0.5 - 0.5, col(WHITE, 0.10), 40, 1)
    end
    -- each arm is one solid bar with round ends (thin 45-degree lines looked jagged)
    local d, t = s * 0.16, 1.25
    local cc = col(hov and WHITE or HUD.muted)
    local function arm(ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        local nx, ny = -dy / len * t * 0.5, dx / len * t * 0.5
        local p1, p2 = { ax + nx, ay + ny }, { bx + nx, by + ny }
        local p3, p4 = { bx - nx, by - ny }, { ax - nx, ay - ny }
        if not pcall(function() dl:AddQuadFilled(p1, p2, p3, p4, cc) end) then dl:AddLine({ ax, ay }, { bx, by }, cc, t) end
        dl:AddCircleFilled({ ax, ay }, t * 0.5, cc, 12)
        dl:AddCircleFilled({ bx, by }, t * 0.5, cc, 12)
    end
    arm(cx - d, cy - d, cx + d, cy + d)
    arm(cx + d, cy - d, cx - d, cy + d)
    return clicked
end

-- ImGui draws the window itself (rounded, thin border).
local function draw_window_frame() end

-- Rounded pill with a small dot (job / clock). Returns clicked, hovered, width.
local function dot_pill(id, x, y, label, c, label2, c2, glowing)
    local dl = DL()
    local lh = line_h()
    local w = text_w(label) + (label2 and (text_w(label2) + 8) or 0) + 32
    local h = lh + 8
    local clicked, hov = false, false
    if id then clicked, hov = hit(id, x, y, w, h) end
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col(WHITE, hov and 0.06 or 0.03), h * 0.5)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + w - 0.5, y + h - 0.5 }, col(c, 0.35), h * 0.5, CORNERS_ALL, 1)
    dot(x + 13, y + h * 0.5, 3, c, glowing and (0.3 + pulse(2) * 0.5) or 0)
    text(x + 22, y + (h - lh) * 0.5, label2 and HUD.text or c, label)
    if label2 then text(x + 22 + text_w(label) + 8, y + (h - lh) * 0.5, c2 or c, label2) end
    return clicked, hov, w
end

local function dot_pill_w(label, label2)
    return text_w(label) + (label2 and (text_w(label2) + 8) or 0) + 32
end

-- Segoe UI 17 (the font VanaCore / YunaGearOpt use). Windows ships it, so nothing is
-- bundled; if it can't be loaded the game's ImGui font is kept.
local font = nil
local function load_title_fonts(dir)
    tfont.b, tfont.l = nil, nil
    for key, names in pairs({ b = { 'segoeuib.ttf', 'seguisb.ttf' }, l = { 'segoeuisl.ttf', 'segoeuil.ttf' } }) do
        for _, name in ipairs(names) do
            local f = io.open(dir .. name, 'rb')
            if f then
                f:close()
                local ok, fnt = pcall(imgui.AddFontFromFileTTF, dir .. name, TITLE_PX)
                if ok and fnt then tfont[key] = fnt; break end
            end
        end
    end
end

local function load_font()
    font = nil
    if type(imgui.AddFontFromFileTTF) ~= 'function' then return end
    local dir = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    for _, name in ipairs({ 'segoeui.ttf', 'SegUIVar.ttf' }) do
        local f = io.open(dir .. name, 'rb')
        if f then
            f:close()
            local ok, fnt = pcall(imgui.AddFontFromFileTTF, dir .. name, 17)
            if ok and fnt then font = fnt; break end
        end
    end
    load_title_fonts(dir)
end

-- Push the font; newer ImGui (fonts with LegacySize) wants a size. Returns true if pushed.
local function push_font()
    if font == nil then return false end
    local ok
    if font.LegacySize ~= nil then ok = pcall(imgui.PushFont, font, 17) else ok = pcall(imgui.PushFont, font) end
    return ok and true or false
end

local function pop_font(pushed)
    if pushed then imgui.PopFont() end
end

-- Pushed only when the ImGui build has the slot, and counted so pops always match.
local pushed_c, pushed_v = {}, {}
local function pc(idx, c) if idx ~= nil then imgui.PushStyleColor(idx, c); pushed_c[#pushed_c] = pushed_c[#pushed_c] + 1 end end
local function pv(idx, v) if idx ~= nil then imgui.PushStyleVar(idx, v); pushed_v[#pushed_v] = pushed_v[#pushed_v] + 1 end end

local function push_style()
    tint_step()
    pushed_c[#pushed_c + 1], pushed_v[#pushed_v + 1] = 0, 0
    pc(ImGuiCol_WindowBg, C.bg)
    pc(ImGuiCol_Border, C.border)
    pc(ImGuiCol_Text, HUD.text)
    pc(ImGuiCol_PopupBg, { 0.067, 0.078, 0.118, 0.99 })
    pc(ImGuiCol_FrameBg, HUD.inset)
    pc(ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 })
    pc(ImGuiCol_ScrollbarGrab, rgba(C.accent, 0.18))
    pc(ImGuiCol_ScrollbarGrabHovered, rgba(C.accent, 0.32))
    pc(ImGuiCol_ScrollbarGrabActive, rgba(C.accent, 0.45))
    pc(ImGuiCol_ResizeGrip, { 1, 1, 1, 0.06 })
    pc(ImGuiCol_ResizeGripHovered, rgba(C.accent, 0.55))
    pc(ImGuiCol_ResizeGripActive, rgba(C.accent, 0.85))
    pc(ImGuiCol_Button, { 1, 1, 1, 0.035 })
    pc(ImGuiCol_ButtonHovered, rgba(C.accent, 0.25))
    pc(ImGuiCol_ButtonActive, rgba(C.accent, 0.40))
    pc(ImGuiCol_TextSelectedBg, rgba(C.accent, 0.35))
    pc(ImGuiCol_Separator, C.line)
    pv(ImGuiStyleVar_WindowRounding, 12.0)
    pv(ImGuiStyleVar_WindowBorderSize, 1.0)
    pv(ImGuiStyleVar_WindowPadding, { 14, 12 })
    pv(ImGuiStyleVar_ItemSpacing, { 8, 6 })
    pv(ImGuiStyleVar_ScrollbarSize, 6.0)
    pv(ImGuiStyleVar_ScrollbarRounding, 6.0)
    pv(ImGuiStyleVar_ChildRounding, 8.0)
    pv(ImGuiStyleVar_FrameRounding, 8.0)
    pv(ImGuiStyleVar_PopupRounding, 8.0)
end

local function pop_style()
    local nv, nc = table.remove(pushed_v) or 0, table.remove(pushed_c) or 0
    if nv > 0 then imgui.PopStyleVar(nv) end
    if nc > 0 then imgui.PopStyleColor(nc) end
end

return {
    HUD = HUD, C = C, ui = ui, CORNERS_ALL = CORNERS_ALL, DEFAULT_TINT = DEFAULT_TINT,
    rgba = rgba, col = col, mix = mix, pulse = pulse, line_h = line_h, text_w = text_w, DL = DL,
    text = text, rtext = rtext, fit = fit, caps = caps, caps_w = caps_w, dot = dot, diamond = diamond,
    chamfer_fill = chamfer_fill, chamfer_line = chamfer_line, frame = frame,
    pill_w = pill_w, pill = pill, bar = bar, meter = meter, card_bg = card_bg, card_title = card_title, rule = rule,
    heading = heading, label_bg = label_bg, sparkles = sparkles, light_pool = light_pool,
    glow = glow, crystal = crystal,
    set_tint = set_tint, tint_step = tint_step,
    push_clip = push_clip, pop_clip = pop_clip,
    hit = hit, advance = advance, avail_w = avail_w, begin_content = begin_content, end_content = end_content,
    seg_tabs = seg_tabs, seg_width = seg_width, line_tabs = line_tabs, toggle_chip = toggle_chip, toggle_w = toggle_w,
    ghost = ghost, ghost_w = ghost_w, ring = ring, hero_card = hero_card, window_light = window_light,
    shadow = shadow, ease = ease, blueprint = blueprint, panel = panel, band = band,
    title_w = title_w, title_text = title_text, logo = logo, close_button = close_button,
    draw_window_frame = draw_window_frame, dot_pill = dot_pill, dot_pill_w = dot_pill_w,
    load_font = load_font, push_font = push_font, pop_font = pop_font,
    push_style = push_style, pop_style = pop_style,
}
