-- crafthub: item icons, read from the game client's own item resources.
-- Each item's 32x32 icon comes from AshitaCore's resource manager (Bitmap /
-- ImageSize) and is turned into a Direct3D 8 texture that ImGui can draw.
-- Nothing is downloaded or bundled. If anything here isn't available, every
-- call simply returns false and crafthub draws its coloured dots instead.
local M = {}

local ok_ffi, ffi = pcall(require, 'ffi')
local ok_d3d, d3d = pcall(require, 'd3d8')
local device = nil
if ok_ffi and ok_d3d and d3d and type(d3d.get_device) == 'function' then
    local ok, dev = pcall(d3d.get_device)
    if ok then device = dev end
end
M.available = device ~= nil

local cache = {}          -- [item id] = { tex = texture, id = imgui texture id } or false
local MAX_LOADS = 6       -- icons created per frame (spreads the work out, no hitches)
local loads_left = MAX_LOADS

function M.new_frame() loads_left = MAX_LOADS end

local function load(id)
    local okr, item = pcall(function() return AshitaCore:GetResourceManager():GetItemById(id) end)
    if not okr or item == nil then return false end
    local size = tonumber(item.ImageSize) or 0
    if size <= 0 or item.Bitmap == nil then return false end
    local ok, entry = pcall(function()
        local C = ffi.C
        local ptr = ffi.new('IDirect3DTexture8*[1]')
        local hr = C.D3DXCreateTextureFromFileInMemoryEx(device, item.Bitmap, size, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, C.D3DX_DEFAULT, C.D3DX_DEFAULT, 0xFF000000, nil, nil, ptr)
        if hr ~= C.S_OK or ptr[0] == nil then return false end
        local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]))
        return { tex = tex, id = tonumber(ffi.cast('uint32_t', tex)) }
    end)
    return (ok and entry) or false
end

-- Texture id for an item, or nil (not loaded yet / no icon / icons unavailable).
function M.get(id)
    if not M.available or not id or id <= 0 then return nil end
    local e = cache[id]
    if e == nil then
        if loads_left <= 0 then return nil end   -- try again next frame
        loads_left = loads_left - 1
        e = load(id)
        cache[id] = e
    end
    return e and e.id or nil
end

-- Draw item id's icon in the box (x, y, size). Returns true if an icon was drawn.
function M.draw(dl, id, x, y, size)
    local tid = M.get(id)
    if not tid then return false end
    local ok = pcall(function() dl:AddImage(tid, { x, y }, { x + size, y + size }) end)
    if not ok then cache[id] = false end
    return ok
end

return M
