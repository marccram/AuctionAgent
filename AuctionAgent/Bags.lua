local ADDON, AA = ...

-- Bag enumeration, sellable filter, vendor price cache and gained-item detection.
-- Diff() and Sellable() are pure so they can be tested outside the game.

local C, P = AA.Compat, AA.Prices
local B = {}
AA.Bags = B

local QUEST_CLASS = 12  -- Enum.ItemClass.Questitem

---------------------------------------------------------------------------
-- Enumeration
---------------------------------------------------------------------------

-- Returns an array of {bag, slot, itemID, link, name, quality, count, bound, noValue, locked}.
-- Any slot that errors (secret values, client change) is skipped, never fatal.
function B.Enumerate()
    local out = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return out
    end
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1)
    for bag = 0, last do
        local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
        slots = okN and C.SafeNumber(slots) or 0
        for slot = 1, slots do
            pcall(function()
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if type(info) ~= "table" then return end
                local id = C.SafeNumber(info.itemID)
                if not id then return end
                out[#out + 1] = {
                    bag = bag, slot = slot, itemID = id,
                    link = C.SafeString(info.hyperlink),
                    name = C.SafeString(info.itemName),
                    icon = C.SafeNumber(info.iconFileID),
                    quality = C.SafeNumber(info.quality) or 0,
                    count = C.SafeNumber(info.stackCount) or 1,
                    bound = info.isBound == true,
                    noValue = info.hasNoValue == true,
                    locked = info.isLocked == true,
                }
            end)
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Sellable filter
---------------------------------------------------------------------------

-- Returns true, or false plus a reason ("bound", "locked", "ignored", "quest").
-- classID is passed in so this stays pure; use C.GetItemClassID in the game.
function B.Sellable(entry, ignore, classID)
    if entry.bound then return false, "bound" end
    if entry.locked then return false, "locked" end
    if ignore and ignore[entry.itemID] then return false, "ignored" end
    if classID == QUEST_CLASS then return false, "quest" end
    return true
end

---------------------------------------------------------------------------
-- Vendor price cache (item info is asynchronous)
---------------------------------------------------------------------------

local vendorCache, pending = {}, {}

-- Per-unit vendor price in copper, or nil if the item is not cached yet.
-- A nil result triggers a load; ITEM_INFO_LOADED fires when it arrives.
function B.VendorPrice(itemID, link)
    local v = vendorCache[itemID]
    if v ~= nil then return v end
    v = C.GetVendorPrice(link or itemID)
    if v ~= nil then
        vendorCache[itemID] = v
        return v
    end
    if not pending[itemID] and Item and Item.CreateFromItemID then
        pending[itemID] = true
        pcall(function()
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                pending[itemID] = nil
                AA.Fire("ITEM_INFO_LOADED", itemID)
            end)
        end)
    end
    return nil
end

---------------------------------------------------------------------------
-- Summary: bag stacks merged per itemID with price evaluation
---------------------------------------------------------------------------

-- Returns array of {itemID, link, name, quality, count, slots, eval}, sorted by estimated
-- total profit descending (items without price data last). Includes only sellable items.
function B.Summarize()
    local db, s = AA.db, AA.settings
    local realmKey = AA.RealmKey()
    local now = time()
    local byID, list = {}, {}
    for _, e in ipairs(B.Enumerate()) do
        local g = byID[e.itemID]
        if not g then
            local ok, why = B.Sellable(e, db and db.ignore, nil)
            if ok and C.GetItemClassID(e.itemID) == QUEST_CLASS then ok = false end
            if ok then
                g = { itemID = e.itemID, link = e.link, name = e.name, quality = e.quality,
                      icon = e.icon, count = 0, slots = {} }
                byID[e.itemID] = g
                list[#list + 1] = g
            else
                byID[e.itemID] = false
            end
        end
        if g then
            g.count = g.count + e.count
            g.slots[#g.slots + 1] = { bag = e.bag, slot = e.slot, count = e.count }
        end
    end
    for _, g in ipairs(list) do
        local vendor = B.VendorPrice(g.itemID, g.link)
        g.vendor = vendor
        g.eval = P.Evaluate(P.Get(db, realmKey, g.itemID), vendor, g.count, now, s)
    end
    table.sort(list, function(a, b)
        local pa, pb = a.eval.profitTotal, b.eval.profitTotal
        if pa and pb and pa ~= pb then return pa > pb end
        if (pa ~= nil) ~= (pb ~= nil) then return pa ~= nil end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

---------------------------------------------------------------------------
-- Gained-item detection
---------------------------------------------------------------------------

-- old/new: maps of itemID -> total count. Returns array of {itemID, delta} for increases.
function B.Diff(old, new)
    local gained = {}
    for id, n in pairs(new) do
        local delta = n - (old[id] or 0)
        if delta > 0 then gained[#gained + 1] = { itemID = id, delta = delta } end
    end
    table.sort(gained, function(a, b) return a.itemID < b.itemID end)
    return gained
end

local function snapshot(entries)
    local m = {}
    for _, e in ipairs(entries) do m[e.itemID] = (m[e.itemID] or 0) + e.count end
    return m
end

local lastSnap
if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function()
        local ok, err = pcall(function()
            local entries = B.Enumerate()
            local snap = snapshot(entries)
            local gained = lastSnap and B.Diff(lastSnap, snap) or {}
            lastSnap = snap  -- first event after login is only a baseline: nothing "gained"
            AA.Fire("BAGS_CHANGED")
            if #gained > 0 then
                for _, g in ipairs(gained) do
                    for _, e in ipairs(entries) do
                        if e.itemID == g.itemID then g.link = e.link; g.name = e.name; break end
                    end
                end
                AA.Fire("ITEMS_GAINED", gained)
            end
        end)
        if not ok and AA.settings and AA.settings.debug then AA.Print("Bags error: " .. tostring(err)) end
    end)
end
