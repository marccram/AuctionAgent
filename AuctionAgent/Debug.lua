local ADDON, AA = ...

-- Step 0 API probe. `/aa debug` logs what exists in the live client. Output goes to a
-- copyable window and to AuctionAgentDB.debugLog (WTF/Account/<acct>/SavedVariables).

local C = AA.Compat
local D = {}
AA.Debug = D

local lines = {}
D.lines = lines

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if not ok then s = tostring(fmt) end
    lines[#lines + 1] = s
end
D.Log = log

local function describe(v)
    local t = type(v)
    if C.IsSecret(v) then return t .. "(SECRET)" end
    if t == "number" or t == "boolean" then return t .. "=" .. tostring(v) end
    if t == "string" then return 'string="' .. v:sub(1, 40) .. '"' end
    return t
end

local function dumpTable(prefix, tbl)
    if type(tbl) ~= "table" then
        log("%s%s", prefix, describe(tbl))
        return
    end
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local v = tbl[k]
        if type(v) == "table" and not C.IsSecret(v) then
            log("%s%s = table", prefix, tostring(k))
            for k2, v2 in pairs(v) do log("%s  .%s = %s", prefix, tostring(k2), describe(v2)) end
        else
            log("%s%s = %s", prefix, tostring(k), describe(v))
        end
    end
end

---------------------------------------------------------------------------
-- Probes
---------------------------------------------------------------------------

local FUNCS = {
    -- Auction house
    "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.SendSearchQuery",
    "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems",
    "C_AuctionHouse.GetReplicateItemInfo", "C_AuctionHouse.GetReplicateItemLink",
    "C_AuctionHouse.GetBrowseResults", "C_AuctionHouse.HasFullBrowseResults",
    "C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.GetCommoditySearchResultsQuantity",
    "C_AuctionHouse.GetNumItemSearchResults", "C_AuctionHouse.GetItemSearchResultInfo",
    "C_AuctionHouse.PostItem", "C_AuctionHouse.PostCommodity",
    "C_AuctionHouse.GetItemCommodityStatus", "C_AuctionHouse.GetItemKeyInfo",
    "C_AuctionHouse.MakeItemKey", "C_AuctionHouse.GetItemKeyFromItem",
    "C_AuctionHouse.CalculateItemDeposit", "C_AuctionHouse.CalculateCommodityDeposit",
    "C_AuctionHouse.GetAuctionHouseDuration", "C_AuctionHouse.IsThrottledMessageSystemReady",
    -- Bags and items
    "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
    "C_Container.GetContainerItemLink", "C_Container.UseContainerItem",
    "C_Container.PickupContainerItem",
    "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemSellPrice",
    "C_Item.IsBound", "C_Item.DoesItemExist", "C_Item.GetItemQualityByID",
    "Item.CreateFromItemID", "ItemLocation.CreateFromBagAndSlot",
    -- Tooltips
    "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Item",
    "C_TooltipInfo.GetBagItem",
    -- Settings and misc
    "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterVerticalLayoutCategory",
    "Settings.RegisterAddOnCategory", "Settings.OpenToCategory",
    "C_AddOns.IsAddOnLoaded", "C_AddOns.GetAddOnMetadata", "C_Timer.After",
    "C_MerchantFrame.GetBuybackItemID",
    -- Secret value helpers (Midnight)
    "issecretvalue", "issecrettable", "canaccessvalue", "hasanysecretvalues", "C_Secrets",
    -- Frames
    "AuctionHouseFrame", "MerchantFrame", "ContainerFrameCombinedBags", "ContainerFrame1",
}

local function probeClient()
    log("== Client ==")
    local ok, ver, build, date, toc = pcall(GetBuildInfo)
    if ok then log("GetBuildInfo: version=%s build=%s date=%s toc=%s", tostring(ver), tostring(build), tostring(date), tostring(toc)) end
    log("WOW_PROJECT_ID=%s", tostring(_G.WOW_PROJECT_ID))
    log("addon TOC Interface = %s", tostring(select(2, C.Call("C_AddOns.GetAddOnMetadata", ADDON, "Interface"))))
    local okR, realm = pcall(GetNormalizedRealmName)
    local okF, faction = pcall(UnitFactionGroup, "player")
    log("Realm=%s Faction=%s", okR and tostring(realm) or "?", okF and tostring(faction) or "?")
    local okC, conn = pcall(GetAutoCompleteRealms)
    if okC and type(conn) == "table" then log("Connected realms: %s", table.concat(conn, ", ")) end
    local others = { "Auctionator", "VendorPricePlus", "Bagnon", "AdiBags", "ElvUI", "BugSack", "TradeSkillMaster", "Baganator" }
    local on = {}
    for _, n in ipairs(others) do if C.IsAddOnLoaded(n) then on[#on + 1] = n end end
    log("Loaded relevant addons: %s", #on > 0 and table.concat(on, ", ") or "(none)")
end

local function probeFuncs()
    log("== API presence ==")
    local missing = 0
    for _, path in ipairs(FUNCS) do
        local v = C.Resolve(path)
        if v == nil then
            log("MISSING  %s", path)
            missing = missing + 1
        else
            log("ok       %s (%s)", path, type(v))
        end
    end
    return missing
end

local function eachBagItem(limit, cb)
    if not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
    local n = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                n = n + 1
                cb(bag, slot, info)
                if n >= limit then return n end
            end
        end
    end
    return n
end
D.EachBagItem = eachBagItem

local function probeBags()
    log("== Bag items (first 4) ==")
    local ok, err = pcall(function()
        local n = eachBagItem(4, function(bag, slot, info)
            log("-- bag %d slot %d", bag, slot)
            dumpTable("  info.", info)
            local id = info.itemID
            local link = info.hyperlink
            if C.SafeNumber(id) then
                local okp, p = C.Call("C_Item.GetItemSellPrice", id)
                log("  C_Item.GetItemSellPrice(itemID) -> ok=%s %s", tostring(okp), describe(p))
                local okg, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 = pcall((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)
                log("  C_Item.GetItemInfo(itemID) -> ok=%s name=%s sellPrice(11th)=%s", tostring(okg), describe(a1), describe(a11))
            end
            if link and C.SafeString(link) then
                local okb, bound = C.Call("C_Item.IsBound", ItemLocation:CreateFromBagAndSlot(bag, slot))
                log("  C_Item.IsBound(location) -> ok=%s %s", tostring(okb), describe(bound))
            end
        end)
        log("(%d items logged)", n)
    end)
    if not ok then log("bag probe error: %s", tostring(err)) end
end

local function probeFrames()
    log("== Frames ==")
    for _, name in ipairs({ "AuctionHouseFrame", "MerchantFrame", "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local f = _G[name]
        if f then
            log("%s: %s shown=%s", name, f:GetObjectType(), tostring(f:IsShown()))
        else
            log("%s: nil (load-on-demand frames appear once first opened)", name)
        end
    end
    local ah = _G.AuctionHouseFrame
    if ah then
        local okM, mode = pcall(function() return ah:GetDisplayMode() end)
        local modeName = "?"
        if okM and _G.AuctionHouseFrameDisplayMode then
            for k, v in pairs(_G.AuctionHouseFrameDisplayMode) do if v == mode then modeName = k end end
        end
        log("AuctionHouseFrame:GetDisplayMode() -> ok=%s current mode=%s", tostring(okM), modeName)
        if _G.AuctionHouseFrameDisplayMode then
            local ks = {}
            for k in pairs(_G.AuctionHouseFrameDisplayMode) do ks[#ks + 1] = tostring(k) end
            table.sort(ks)
            log("AuctionHouseFrameDisplayMode: %s", table.concat(ks, ", "))
        end
        local kids = {}
        for k, v in pairs(ah) do
            if type(k) == "string" and type(v) == "table" and v.GetObjectType then kids[#kids + 1] = k end
        end
        table.sort(kids)
        log("AuctionHouseFrame frame children: %s", table.concat(kids, ", "))
        local okT, ready = C.Call("C_AuctionHouse.IsThrottledMessageSystemReady")
        log("IsThrottledMessageSystemReady -> ok=%s %s", tostring(okT), describe(ready))
    end
end

---------------------------------------------------------------------------
-- Live event logging and result dumps (AH must be open)
---------------------------------------------------------------------------

local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_FAILURE", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_ERROR",
    "AUCTION_HOUSE_POST_WARNING", "MERCHANT_SHOW", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED_DISABLED",
}

local function dumpCommodity(itemID)
    local _, n = C.Call("C_AuctionHouse.GetNumCommoditySearchResults", itemID)
    local _, q = C.Call("C_AuctionHouse.GetCommoditySearchResultsQuantity", itemID)
    log("  commodity itemID=%s numResults=%s totalQuantity=%s", describe(itemID), describe(n), describe(q))
    if C.SafeNumber(n) then
        for i = 1, math.min(3, n) do
            local ok, r = C.Call("C_AuctionHouse.GetCommoditySearchResultInfo", itemID, i)
            log("  result %d (ok=%s):", i, tostring(ok))
            if ok then dumpTable("    ", r) end
        end
    end
end

local function dumpItemResults(itemKey)
    local _, n = C.Call("C_AuctionHouse.GetNumItemSearchResults", itemKey)
    log("  item search numResults=%s", describe(n))
    if C.SafeNumber(n) then
        for i = 1, math.min(3, n) do
            local ok, r = C.Call("C_AuctionHouse.GetItemSearchResultInfo", itemKey, i)
            log("  result %d (ok=%s):", i, tostring(ok))
            if ok then dumpTable("    ", r) end
        end
    end
end

local function dumpReplicate()
    local _, n = C.Call("C_AuctionHouse.GetNumReplicateItems")
    log("  replicate numItems=%s", describe(n))
    if C.SafeNumber(n) then
        for i = 0, math.min(2, n - 1) do
            local vals = { C.Call("C_AuctionHouse.GetReplicateItemInfo", i) }
            local parts = {}
            for j = 2, #vals do parts[#parts + 1] = j - 1 .. ":" .. describe(vals[j]) end
            log("  GetReplicateItemInfo(%d) -> ok=%s %s", i, tostring(vals[1]), table.concat(parts, " "))
        end
    end
end

local evFrame
local function onEvent(_, event, ...)
    local args = {}
    for i = 1, select("#", ...) do args[#args + 1] = describe((select(i, ...))) end
    log("[%.1f] %s %s", GetTime(), event, table.concat(args, ", "))
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        pcall(dumpCommodity, (...))
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        pcall(dumpItemResults, (...))
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        pcall(dumpReplicate)
    end
end

local function startEvents()
    if not evFrame then
        evFrame = CreateFrame("Frame")
        evFrame:SetScript("OnEvent", onEvent)
    end
    local reg, bad = 0, {}
    for _, e in ipairs(EVENTS) do
        if pcall(evFrame.RegisterEvent, evFrame, e) then reg = reg + 1 else bad[#bad + 1] = e end
    end
    log("Event logging ON (%d registered; rejected: %s)", reg, #bad > 0 and table.concat(bad, ", ") or "none")
end

local function stopEvents()
    if evFrame then evFrame:UnregisterAllEvents() end
    log("Event logging OFF")
end

---------------------------------------------------------------------------
-- Active, read-only probes
---------------------------------------------------------------------------

local function makeKey(itemID)
    local ok, key = C.Call("C_AuctionHouse.MakeItemKey", itemID)
    if ok and type(key) == "table" then return key, "MakeItemKey" end
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, "manual table"
end

-- /aa debug query [itemID]  -- search the AH for one item (first bag item by default)
local function queryCmd(arg)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        AA.Print("Open the Auction House first.")
        return
    end
    startEvents()
    local itemID = tonumber(arg)
    local bag, slot
    if not itemID then
        -- first tradable item: not soulbound, has a vendor value
        eachBagItem(500, function(b, s, info)
            if not bag and not info.isBound and not info.hasNoValue then bag, slot, itemID = b, s, info.itemID end
        end)
    end
    if not itemID then AA.Print("No item found in bags and no itemID given.") return end
    if bag and ItemLocation then
        local okS, status = C.Call("C_AuctionHouse.GetItemCommodityStatus", ItemLocation:CreateFromBagAndSlot(bag, slot))
        log("GetItemCommodityStatus(bag %d slot %d) -> ok=%s %s", bag, slot, tostring(okS), describe(status))
    end
    local key, how = makeKey(itemID)
    log("Query itemID=%s key via %s:", tostring(itemID), how)
    dumpTable("  key.", key)
    local okK, keyInfo = C.Call("C_AuctionHouse.GetItemKeyInfo", key)
    log("GetItemKeyInfo -> ok=%s", tostring(okK))
    if okK then dumpTable("  ", keyInfo) end
    local ok, err = C.Call("C_AuctionHouse.SendSearchQuery", key, {}, true)
    log("SendSearchQuery -> ok=%s %s (results arrive via events; run /aa debug copy)", tostring(ok), ok and "" or tostring(err))
    AA.Print("Query sent. Wait a moment, then /aa debug copy.")
end

-- /aa debug deposit -- read the AH's real deposit for up to 10 tradable bag items, all three
-- durations, to calibrate Prices.Deposit. Read-only; AH must be open.
local function depositCmd()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        AA.Print("Open the Auction House first.")
        return
    end
    log("== Deposit probe (duration 1/2/3 = 2h/8h/24h) ==")
    local n = 0
    eachBagItem(500, function(bag, slot, info)
        if n >= 10 or info.isBound or not C.SafeNumber(info.itemID) then return end
        n = n + 1
        local id = info.itemID
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local _, status = C.Call("C_AuctionHouse.GetItemCommodityStatus", loc)
        local vendor = C.GetVendorPrice(info.hyperlink or id)
        local qty = C.SafeNumber(info.stackCount) or 1
        log("-- %s (id %s) status=%s vendor=%s stack=%s", tostring(info.itemName), tostring(id),
            describe(status), describe(vendor), tostring(qty))
        for dur = 1, 3 do
            local parts = {}
            for _, q in ipairs(qty > 1 and { 1, qty } or { 1 }) do
                local ok, dep
                if status == 2 then
                    ok, dep = C.Call("C_AuctionHouse.CalculateCommodityDeposit", id, dur, q)
                else
                    ok, dep = C.Call("C_AuctionHouse.CalculateItemDeposit", loc, dur, q)
                end
                local ratio = (C.SafeNumber(dep) and vendor and vendor > 0) and (" ratio=%.3f"):format(dep / (vendor * q)) or ""
                parts[#parts + 1] = ("qty %d -> ok=%s %s%s"):format(q, tostring(ok), describe(dep), ratio)
            end
            log("   dur %d: %s", dur, table.concat(parts, " | "))
        end
    end)
    log("(%d items)", n)
    AA.Print("Deposit probe done. Run /aa debug copy and paste it.")
end

local function replicateCmd()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        AA.Print("Open the Auction House first.")
        return
    end
    startEvents()
    local ok, err = C.Call("C_AuctionHouse.ReplicateItems")
    log("ReplicateItems -> ok=%s %s", tostring(ok), ok and "" or tostring(err))
    AA.Print("ReplicateItems sent (this has a long server cooldown). Then /aa debug copy.")
end

---------------------------------------------------------------------------
-- Output window
---------------------------------------------------------------------------

local function showWindow()
    local ok, err = pcall(function()
        if not D.frame then
            local f = CreateFrame("Frame", "AuctionAgentDebugFrame", UIParent, "BasicFrameTemplateWithInset")
            f:SetSize(680, 440)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetMovable(true)
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
            if f.TitleText then f.TitleText:SetText("AuctionAgent debug  (click text, Ctrl+A, Ctrl+C)") end
            local sf = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
            sf:SetPoint("TOPLEFT", 12, -32)
            sf:SetPoint("BOTTOMRIGHT", -12, 12)
            sf.EditBox:SetFontObject("ChatFontNormal")
            sf.EditBox:SetMaxLetters(0)
            sf.EditBox:SetWidth(620)
            if sf.CharCount then sf.CharCount:Hide() end
            sf.EditBox:SetScript("OnEscapePressed", function() f:Hide() end)
            f.edit = sf.EditBox
            table.insert(UISpecialFrames, "AuctionAgentDebugFrame")
            D.frame = f
        end
        D.frame.edit:SetText(table.concat(lines, "\n"))
        D.frame:Show()
    end)
    if not ok then
        AA.Print("Could not open debug window (" .. tostring(err) .. "). Log is saved in AuctionAgentDB.debugLog after /reload.")
    end
end

---------------------------------------------------------------------------
-- Command entry
---------------------------------------------------------------------------

function D.Command(rest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    if sub == "" or sub == "run" then
        wipe(lines)
        log("AuctionAgent debug probe, %s", date("%Y-%m-%d %H:%M:%S"))
        local steps = { probeClient, probeFuncs, probeBags, probeFrames }
        local missing
        for _, step in ipairs(steps) do
            local ok, r = pcall(step)
            if not ok then log("PROBE ERROR: %s", tostring(r)) elseif step == probeFuncs then missing = r end
        end
        AA.Print(("Probe done: %s APIs missing. Full report in the debug window and AuctionAgentDB.debugLog."):format(tostring(missing)))
        showWindow()
    elseif sub == "copy" or sub == "show" then
        showWindow()
    elseif sub == "events" then
        if arg:lower() == "off" then stopEvents() else startEvents() end
        AA.Print("Event logging " .. (arg:lower() == "off" and "off" or "on") .. ".")
    elseif sub == "query" then
        queryCmd(arg)
    elseif sub == "replicate" then
        replicateCmd()
    elseif sub == "deposit" then
        depositCmd()
    elseif sub == "clear" then
        wipe(lines)
        AA.Print("Debug log cleared.")
    else
        AA.Print("/aa debug [run | copy | events [off] | query [itemID] | replicate | deposit | clear]")
    end
end
