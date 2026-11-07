local ADDON, AA = ...

-- Client/API shims and secret-value-safe helpers. Everything here must tolerate the
-- Midnight client returning "secret" values or missing APIs. Never error.

local C = {}
AA.Compat = C

local pcall, type, select = pcall, type, select

-- True if v is a Midnight secret value (cannot be compared or used in arithmetic).
function C.IsSecret(v)
    local f = _G.issecretvalue
    if f then
        local ok, r = pcall(f, v)
        if ok and r then return true end
    end
    return false
end

-- Returns v only if it is a plain, finite, non-secret number; otherwise nil.
function C.SafeNumber(v)
    if type(v) ~= "number" then return nil end
    if C.IsSecret(v) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- Returns v only if it is a plain, non-secret string.
function C.SafeString(v)
    if type(v) ~= "string" then return nil end
    if C.IsSecret(v) then return nil end
    return v
end

-- Resolve a dotted global path like "C_AuctionHouse.SendBrowseQuery". nil if absent.
function C.Resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        local ok, nxt = pcall(function() return v[part] end)
        if not ok then return nil end
        v = nxt
    end
    return v
end

-- Call a function found by dotted path; returns ok, ...results
function C.Call(path, ...)
    local f = C.Resolve(path)
    if type(f) ~= "function" then return false, "missing: " .. path end
    return pcall(f, ...)
end

-- Vendor sell price per unit in copper, or nil if unknown/unavailable.
-- Item info is async: nil can also mean "not cached yet".
function C.GetVendorPrice(item)
    local ok, price = C.Call("C_Item.GetItemSellPrice", item)
    if ok then
        price = C.SafeNumber(price)
        if price then return price end
    end
    local ok2, info = pcall(function() return select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(item)) end)
    if ok2 then return C.SafeNumber(info) end
    return nil
end

-- Item class ID (e.g. 12 = quest item) via C_Item.GetItemInfoInstant, or nil.
function C.GetItemClassID(item)
    local ok, _, _, _, _, _, classID = C.Call("C_Item.GetItemInfoInstant", item)
    if ok then return C.SafeNumber(classID) end
    return nil
end

-- Tiny callback registry so modules can talk without hard dependencies.
-- Handlers run under pcall: one broken listener never breaks the rest.
local handlers = {}
function AA.Register(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
function AA.Fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do pcall(fn, ...) end
end

function C.IsAddOnLoaded(name)
    local ok, r = C.Call("C_AddOns.IsAddOnLoaded", name)
    if ok then return r and true or false end
    if type(_G.IsAddOnLoaded) == "function" then
        local ok2, r2 = pcall(_G.IsAddOnLoaded, name)
        return ok2 and r2 and true or false
    end
    return false
end
