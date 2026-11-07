local ADDON, AA = ...

-- Marks: tag an item "auction" or "vendor" while questing. State lives in AuctionAgentDB.marks
-- (itemID -> kind). The pure helpers at the top are tested outside the game. The second half
-- hooks the bag buttons (modifier-click to cycle the mark), draws a small badge on marked
-- items and adds a tooltip line. All of it is under pcall and uses only hooks, never
-- replaces Blizzard functions.

local C = AA.Compat
local M = {}
AA.Marks = M

local KINDS = { auction = true, vendor = true }
M.LABEL = { auction = "Auction", vendor = "Vendor" }

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

function M.Get(db, id)
    return db and db.marks and db.marks[id] or nil
end

-- kind nil clears. Returns true on success, false for an invalid kind or missing input.
function M.Set(db, id, kind)
    if not (db and id) then return false end
    db.marks = db.marks or {}
    if kind == nil then db.marks[id] = nil return true end
    if not KINDS[kind] then return false end
    db.marks[id] = kind
    return true
end

-- nil -> auction -> vendor -> nil. Soulbound items cannot be auctioned: nil -> vendor -> nil.
function M.Cycle(kind, bound)
    if kind == nil then return bound and "vendor" or "auction" end
    if kind == "auction" and not bound then return "vendor" end
    return nil
end

-- Slash-command word -> "auction" | "vendor" | "clear" | nil
function M.ParseKind(word)
    word = (word or ""):lower()
    if word == "auction" or word == "ah" or word == "a" then return "auction" end
    if word == "vendor" or word == "v" or word == "sell" then return "vendor" end
    if word == "clear" or word == "none" or word == "off" or word == "unmark" then return "clear" end
    return nil
end

-- spec like "alt", "ctrl", "alt+ctrl". A plain click (no modifier in the spec) never matches,
-- so a bad setting can never turn every bag click into a mark.
function M.ModifierMatches(spec, alt, ctrl, shift)
    local want = {}
    for tok in tostring(spec or ""):lower():gmatch("%a+") do want[tok] = true end
    if not (want.alt or want.ctrl or want.shift) then return false end
    return (want.alt or false) == (alt and true or false)
        and (want.ctrl or false) == (ctrl and true or false)
        and (want.shift or false) == (shift and true or false)
end

function M.NormalizeButton(s)
    if tostring(s or ""):lower():find("right", 1, true) then return "RightButton" end
    return "LeftButton"
end

-- Removes marks for items that are not in `present` (a set of itemIDs). Returns how many.
function M.Prune(db, present)
    local n = 0
    if not (db and db.marks) then return 0 end
    for id in pairs(db.marks) do
        if not present[id] then db.marks[id] = nil; n = n + 1 end
    end
    return n
end

function M.Counts(db)
    local c = { auction = 0, vendor = 0 }
    for _, kind in pairs(db and db.marks or {}) do
        if c[kind] then c[kind] = c[kind] + 1 end
    end
    return c
end

-- entries: Bags.Enumerate() output. marks: itemID -> kind. vendorOf(itemID, link) -> copper or nil.
-- Returns plan (array of {bag, slot, itemID, count, vendor, value, link, name}), total value,
-- and how many marked stacks were skipped because the vendor price is not loaded yet.
-- Locked stacks and items without a vendor value are never planned.
function M.VendorPlan(entries, marks, vendorOf)
    local plan, total, unknown = {}, 0, 0
    for _, e in ipairs(entries) do
        if marks[e.itemID] == "vendor" and not e.locked and not e.noValue then
            local v = vendorOf(e.itemID, e.link)
            if v == nil then
                unknown = unknown + 1
            elseif v > 0 then
                local value = v * e.count
                plan[#plan + 1] = { bag = e.bag, slot = e.slot, itemID = e.itemID, count = e.count,
                    vendor = v, value = value, link = e.link, name = e.name }
                total = total + value
            end
        end
    end
    return plan, total, unknown
end

---------------------------------------------------------------------------
-- Slash command: /aa mark auction|vendor|clear [itemlink|id]   (no item = the one in the tooltip)
---------------------------------------------------------------------------

local function resolveItem(arg)
    local id = tonumber(arg) or tonumber((arg or ""):match("item:(%d+)"))
    local link = (arg or ""):match("(|c.-|h|r)")
    if id then return id, link end
    if (arg or "") == "" and GameTooltip and GameTooltip:IsShown() then
        local ok, _, l = pcall(GameTooltip.GetItem, GameTooltip)
        if ok and l then return tonumber(l:match("item:(%d+)")), l end
    end
end

local function label(id, link) return link or ("item " .. id) end

function M.Command(rest)
    local word, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    local kind = M.ParseKind(word)
    if not kind then
        AA.Print("Usage: /aa mark auction|vendor|clear [item link or id]  (no item: the one under your mouse)")
        AA.Print("In bags: " .. (AA.settings.markModifier or "alt") .. "+click cycles the mark: Auction, Vendor, none.")
        return
    end
    local id, link = resolveItem(arg)
    if not id then
        AA.Print("No item given. Shift-click an item link into the command, or point at an item first.")
        return
    end
    if kind == "auction" then
        for _, e in ipairs(AA.Bags.Enumerate()) do
            if e.itemID == id and e.bound then
                AA.Print(label(id, link) .. " is soulbound and cannot be auctioned; marking it for Vendor instead.")
                kind = "vendor"
                break
            end
        end
    end
    M.Set(AA.db, id, kind ~= "clear" and kind or nil)
    AA.Print(("%s: %s"):format(label(id, link), kind == "clear" and "mark cleared" or ("marked for " .. M.LABEL[kind])))
    AA.Fire("MARKS_CHANGED")
end

function M.List()
    local counts = M.Counts(AA.db)
    local ids = {}
    for id in pairs(AA.db.marks) do ids[#ids + 1] = id end
    table.sort(ids)
    AA.Print(("%d marked for Auction, %d marked for Vendor."):format(counts.auction, counts.vendor))
    for _, id in ipairs(ids) do
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
        AA.Print(("  %s: %s"):format(name, M.LABEL[AA.db.marks[id]] or "?"))
    end
    if AA.Merchant then
        local plan, total, unknown = AA.Merchant.Plan()
        AA.Print(("Sellable at a vendor right now: %d stack(s) worth %s%s."):format(#plan,
            AA.Prices.FormatMoney(total), unknown > 0 and (", " .. unknown .. " still loading") or ""))
    end
    if not AA.settings.rememberMarks then
        AA.Print("Marks clear when the item leaves your bags (/aa set rememberMarks true to keep them).")
    end
end

function M.ClearAll()
    wipe(AA.db.marks)
    AA.Print("All marks cleared.")
    AA.Fire("MARKS_CHANGED")
end

if not CreateFrame then return end

---------------------------------------------------------------------------
-- Bag buttons: click handler and badge
---------------------------------------------------------------------------

local overlays = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function buttonItem(btn)
    local ok, id, link, bound = pcall(function()
        local bag = btn.GetBagID and btn:GetBagID() or btn:GetParent():GetID()
        local info = C_Container.GetContainerItemInfo(bag, btn:GetID())
        if type(info) ~= "table" then return nil end
        return C.SafeNumber(info.itemID), C.SafeString(info.hyperlink), info.isBound == true
    end)
    if ok then return id, link, bound end
end

local borders = setmetatable({}, { __mode = "k" })

-- Thin gold border on bag slots the alerts flagged as worth auctioning.
local function setBorder(btn, on)
    local b = borders[btn]
    if not on then
        if b then for _, t in ipairs(b) do t:Hide() end end
        return
    end
    if not b then
        b = {}
        for i = 1, 4 do
            b[i] = btn:CreateTexture(nil, "OVERLAY", nil, 6)
            b[i]:SetColorTexture(1, 0.82, 0, 0.95)
        end
        b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("TOPRIGHT"); b[1]:SetHeight(2)
        b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(2)
        b[3]:SetPoint("TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT"); b[3]:SetWidth(2)
        b[4]:SetPoint("TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(2)
        borders[btn] = b
    end
    for _, t in ipairs(b) do t:Show() end
end

local function refreshButton(btn)
    local id, _, bound = buttonItem(btn)
    local flagged = id and AA.settings and AA.settings.alertBagBorder
        and AA.Alerts and AA.Alerts.IsFlagged(id)
    pcall(setBorder, btn, flagged and true or false)
    local mark = id and M.Get(AA.db, id)
    if mark == "auction" and bound then   -- e.g. marked before it became soulbound
        mark = "vendor"
        M.Set(AA.db, id, mark)
    end
    local o = overlays[btn]
    if not mark then
        if o then o:Hide() end
        return
    end
    if not o then
        o = btn:CreateFontString(nil, "OVERLAY")
        o:SetDrawLayer("OVERLAY", 7)
        o:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        o:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        overlays[btn] = o
    end
    if mark == "auction" then
        o:SetText("AH"); o:SetTextColor(1, 0.82, 0)
    else
        o:SetText("V"); o:SetTextColor(0.3, 1, 0.3)
    end
    o:Show()
end

local function onClick(btn, button)
    local s = AA.settings
    if not s or button ~= M.NormalizeButton(s.markButton) then return end
    if not M.ModifierMatches(s.markModifier, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()) then return end
    local id, _, bound = buttonItem(btn)
    if not id then return end
    -- A plain left click would have picked the item up; put it straight back.
    if button == "LeftButton" and GetCursorInfo and GetCursorInfo() == "item" then ClearCursor() end
    M.Set(AA.db, id, M.Cycle(M.Get(AA.db, id), bound))   -- the badge is the feedback; no chat output
    AA.Fire("MARKS_CHANGED")
end

local function hookButton(btn)
    if hooked[btn] then return end
    hooked[btn] = true
    pcall(btn.HookScript, btn, "PostClick", onClick)
end

local function bagFrames()
    local list = { _G.ContainerFrameCombinedBags }
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do list[#list + 1] = _G["ContainerFrame" .. i] end
    return list
end

local function refreshFrame(frame)
    if not (frame and frame.EnumerateValidItems) then return end
    for _, btn in frame:EnumerateValidItems() do
        hookButton(btn)
        refreshButton(btn)
    end
end

function M.RefreshAll()
    for _, frame in ipairs(bagFrames()) do pcall(refreshFrame, frame) end
end

local function setupHooks()
    for _, frame in ipairs(bagFrames()) do
        if frame.UpdateItems then
            pcall(hooksecurefunc, frame, "UpdateItems", function(self) pcall(refreshFrame, self) end)
        end
        pcall(frame.HookScript, frame, "OnShow", function(self) pcall(refreshFrame, self) end)
    end
end

local function later() C_Timer.After(0.05, M.RefreshAll) end
AA.Register("MARKS_CHANGED", later)
AA.Register("ALERTS_CHANGED", later)

---------------------------------------------------------------------------
-- Drop marks for items that left the bags (unless rememberMarks)
---------------------------------------------------------------------------

M.pruneReady = false   -- becomes true shortly after login, once bags are surely loaded

AA.Register("BAGS_CHANGED", function()
    later()
    if M.pruneReady and AA.settings and not AA.settings.rememberMarks then
        local present, any = {}, false
        for _, e in ipairs(AA.Bags.Enumerate()) do present[e.itemID] = true; any = true end
        if any and M.Prune(AA.db, present) > 0 then AA.Fire("MARKS_CHANGED") end
    end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    pcall(setupHooks)
    C_Timer.After(15, function() M.pruneReady = true end)
end)

---------------------------------------------------------------------------
-- Tooltip line for marked items
---------------------------------------------------------------------------

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
        pcall(function()
            if tt ~= GameTooltip or not AA.db then return end
            local id = data and C.SafeNumber(data.id)
            local mark = id and M.Get(AA.db, id)
            if mark then tt:AddLine("AuctionAgent: marked for " .. M.LABEL[mark], 1, 0.82, 0) end
        end)
    end)
end
