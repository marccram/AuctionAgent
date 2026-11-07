local ADDON, AA = ...

-- Subtle alerts: when a newly looted item is worth auctioning (high margin, net of deposit),
-- flag it quietly: a minimap button that turns red with a count, a thin gold border on the
-- bag slot, and optionally a chat line or sound. Nothing fires in combat (queued until it
-- ends), nothing pops up, and each item alerts once unless its price moves a lot.
-- The flagging rules are pure and tested outside the game; the UI is under pcall so a
-- client change can break the alerts, never the addon.

local C, P = AA.Compat, AA.Prices
local A = {}
AA.Alerts = A

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------

function A.NewState()
    return { flagged = {}, seen = {}, pending = {} }
end

-- g: group from Bags.Summarize (with .eval). ctx: { marks, ignore, seen, delta }.
-- Returns true, or false plus a reason.
function A.ShouldFlag(g, ctx)
    local e = g.eval
    if not e or e.state ~= "ok" then return false, "nodata" end
    if not (e.high and e.rec == "auction") then return false, "notworth" end
    if ctx.ignore and ctx.ignore[g.itemID] then return false, "ignored" end
    if ctx.marks and ctx.marks[g.itemID] then return false, "marked" end   -- you already decided
    local prev = ctx.seen and ctx.seen[g.itemID]
    local price = e.market
    if prev and prev > 0 and price and math.abs(price - prev) / prev <= (ctx.delta or 0.25) then
        return false, "seen"   -- alerted before and the price has not moved much
    end
    return true
end

-- gained: array of {itemID, delta} (Bags ITEMS_GAINED). groups: Bags.Summarize() output.
-- Updates state.flagged / state.seen and returns the entries that are newly flagged.
function A.Process(state, groups, gained, ctx)
    local byID = {}
    for _, g in ipairs(groups) do byID[g.itemID] = g end
    ctx.seen = state.seen
    local out = {}
    for _, item in ipairs(gained) do
        local g = byID[item.itemID]
        if g and not state.flagged[g.itemID] then
            local ok = A.ShouldFlag(g, ctx)
            if ok then
                local entry = { itemID = g.itemID, link = g.link, name = g.name, count = g.count,
                    market = g.eval.market, vendor = g.vendor, profitTotal = g.eval.profitTotal,
                    margin = g.eval.margin }
                state.flagged[g.itemID] = entry
                state.seen[g.itemID] = g.eval.market
                out[#out + 1] = entry
            end
        end
    end
    return out
end

-- Drops flags for items that left the bags, got marked, or are ignored. Returns how many.
function A.Prune(state, present, marks, ignore)
    local n = 0
    for id in pairs(state.flagged) do
        if not present[id] or (marks and marks[id]) or (ignore and ignore[id]) then
            state.flagged[id] = nil
            n = n + 1
        end
    end
    return n
end

function A.Count(state)
    local n = 0
    for _ in pairs(state.flagged) do n = n + 1 end
    return n
end

-- Flagged entries, best profit first.
function A.List(state)
    local list = {}
    for _, e in pairs(state.flagged) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        local pa, pb = a.profitTotal or 0, b.profitTotal or 0
        if pa ~= pb then return pa > pb end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- "Name: ~Xg AH vs Yg vendor (+Z%)"
function A.Message(e)
    local margin
    if e.margin == math.huge then margin = "no vendor value"
    elseif e.margin then margin = ("%+d%%"):format(math.floor(e.margin * 100 + 0.5)) end
    return ("%s x%d: ~%s AH vs %s vendor%s"):format(e.link or e.name or ("item " .. tostring(e.itemID)),
        e.count or 1, P.FormatMoney(e.market or 0), P.FormatMoney(e.vendor or 0),
        margin and (" (" .. margin .. ")") or "")
end

A.state = A.NewState()

function A.IsFlagged(id)
    return A.state.flagged[id] ~= nil
end

function A.Clear()
    if next(A.state.flagged) then
        A.state.flagged = {}
        if AA.Fire then AA.Fire("ALERTS_CHANGED") end
    end
end

if not CreateFrame then return end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local button
local atan2 = math.atan2 or math.atan

local function place()
    if not button then return end
    local angle = math.rad((AA.settings and AA.settings.minimapAngle) or 225)
    button:ClearAllPoints()
    -- On the ring: minimap radius plus an offset (this client's ring is thicker than the default).
    local radius = (Minimap:GetWidth() / 2) + ((AA.settings and AA.settings.minimapOffset) or 5)
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function updateButton()
    if not button then return end
    if not (AA.settings and AA.settings.alertMinimap) then button:Hide() return end
    button:Show()
    local n = A.Count(A.state)
    if n > 0 then
        button.icon:SetVertexColor(1, 0.25, 0.25)
        button.badge:SetText(n)
        button.badge:Show()
    else
        button.icon:SetVertexColor(1, 1, 1)
        button.badge:Hide()
    end
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("AuctionAgent", 1, 0.82, 0)
    local list = A.List(A.state)
    if #list == 0 then
        GameTooltip:AddLine("Nothing worth auctioning has been flagged.", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("Worth auctioning:", 1, 1, 1)
        for i, e in ipairs(list) do
            if i > 10 then GameTooltip:AddLine(("... and %d more"):format(#list - 10), 0.7, 0.7, 0.7) break end
            GameTooltip:AddLine(A.Message(e))
        end
    end
    GameTooltip:AddLine("Click: mark as seen. Right-click: list bag items.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function createButton()
    button = CreateFrame("Button", "AuctionAgentMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(17, 17)
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon:SetPoint("TOPLEFT", 7, -6)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button.badge = button:CreateFontString(nil, "OVERLAY")
    button.badge:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    button.badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 3)
    button.badge:SetTextColor(1, 0.9, 0.2)
    button.badge:Hide()

    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then
            if AA.ListCmd then AA.ListCmd() end
        end
        A.Clear()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            AA.settings.minimapAngle = math.deg(atan2(py / scale - my, px / scale - mx))
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    place()
    updateButton()
end

---------------------------------------------------------------------------
-- Gained items -> flags (deferred while in combat)
---------------------------------------------------------------------------

local function inCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function announce(newly)
    local s = AA.settings
    if s.alertChat then
        for _, e in ipairs(newly) do AA.Print(A.Message(e)) end
    end
    if s.alertSound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

local function handle(gained)
    local s = AA.settings
    if not s or not AA.db or #gained == 0 then return end
    local newly = A.Process(A.state, AA.Bags.Summarize(), gained,
        { marks = AA.db.marks, ignore = AA.db.ignore, delta = s.alertDelta })
    if #newly > 0 then
        AA.Fire("ALERTS_CHANGED")
        announce(newly)
    end
end

AA.Register("ITEMS_GAINED", function(gained)
    local s = AA.settings
    if not s then return end
    if inCombat() and not s.alertInCombat then
        for _, g in ipairs(gained) do
            if #A.state.pending < 100 then A.state.pending[#A.state.pending + 1] = g end
        end
        return
    end
    handle(gained)
end)

local function refreshFlags()
    if not AA.db then return end
    local present = {}
    for _, e in ipairs(AA.Bags.Enumerate()) do present[e.itemID] = true end
    if A.Prune(A.state, present, AA.db.marks, AA.db.ignore) > 0 then
        AA.Fire("ALERTS_CHANGED")
    end
end

local function onChange()
    pcall(refreshFlags)
    pcall(updateButton)
end

AA.Register("BAGS_CHANGED", onChange)
AA.Register("MARKS_CHANGED", onChange)
AA.Register("SETTINGS_CHANGED", function() pcall(place); onChange() end)
AA.Register("ALERTS_CHANGED", function() pcall(updateButton) end)
AA.Register("AH_SHOW", function() A.Clear() end)   -- visiting the AH counts as having looked

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(createButton)
        if not ok then AA.Print("Minimap button could not be built: " .. tostring(err)) end
    else
        local pending = A.state.pending
        A.state.pending = {}
        pcall(handle, pending)
    end
end)
