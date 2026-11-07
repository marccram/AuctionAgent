local ADDON, AA = ...

-- Sell Panel: docked beside the Auction House frame while its Sell tab is active.
-- Lists sellable bag items with vendor/market/suggested price, profit net of deposit,
-- margin and data age. All UI work is isolated under pcall so a client change breaks
-- this panel, never the addon.

local C, P, S = AA.Compat, AA.Prices, AA.Sell
local UI = {}
AA.SellPanel = UI

local ROW_H = 24
local COLS = {
    { key = "name",      label = "Item",      w = 176 },
    { key = "qty",       label = "Qty",       w = 34 },
    { key = "vendor",    label = "Vendor",    w = 84 },
    { key = "market",    label = "Market",    w = 84 },
    { key = "suggested", label = "Suggested", w = 90 },
    { key = "profit",    label = "Profit",    w = 92 },
    { key = "margin",    label = "Margin",    w = 52 },
    { key = "age",       label = "Age",       w = 54 },
}
local ACTION_W = 78
local PAD = 6
local CONTENT_W = PAD
for _, c in ipairs(COLS) do CONTENT_W = CONTENT_W + c.w end
CONTENT_W = CONTENT_W + ACTION_W
local PANEL_W = CONTENT_W + 40   -- scrollbar + insets

UI.sortKey, UI.sortDesc = "profit", true

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------

-- Money with the game's coin icons (see Prices.FormatMoneyIcons).
local function money(copper)
    if copper == nil then return "-" end
    return P.FormatMoneyIcons(copper)
end

local function pct(m)
    if m == nil then return "-" end
    if m == math.huge then return "inf" end   -- vendor price 0: any sale is pure gain
    return ("%+d%%"):format(math.floor(m * 100 + 0.5))
end

local function qualityHex(q)
    local ok, hex = pcall(function()
        local c = ITEM_QUALITY_COLORS[q]
        return c and c.color and c.color:GenerateHexColor()
    end)
    return (ok and hex) and ("|c" .. hex) or "|cffffffff"
end

local DIM = { 0.55, 0.55, 0.55 }
local GREEN, RED, WHITE, ORANGE = { 0.3, 1, 0.3 }, { 1, 0.35, 0.35 }, { 1, 1, 1 }, { 1, 0.6, 0.2 }

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function newFont(parent, x, w, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", parent, "LEFT", x, 0)
    fs:SetWidth(w - 4)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function createRow(parent, index)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(CONTENT_W, ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.08)

    local x = PAD
    r.cell = {}
    for _, col in ipairs(COLS) do
        if col.key == "name" then
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", r, "LEFT", x, 0)
            r.cell.name = newFont(r, x + 22, col.w - 22)
        else
            r.cell[col.key] = newFont(r, x, col.w, "RIGHT")
        end
        x = x + col.w
    end

    r.post = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.post:SetSize(44, 20)
    r.post:SetPoint("LEFT", r, "LEFT", x + 2, 0)
    r.post:SetText("Post")
    r.post:SetScript("OnClick", function()
        if r.row then pcall(S.PostRow, r.row) end
    end)

    r.ignore = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.ignore:SetSize(24, 20)
    r.ignore:SetPoint("LEFT", r.post, "RIGHT", 2, 0)
    r.ignore:SetText("X")
    r.ignore:SetScript("OnClick", function()
        if r.row and AA.db then
            AA.db.ignore[r.row.itemID] = true
            AA.Print(("Ignoring %s from now on (clear with /aa unignore %d)."):format(r.row.name, r.row.itemID))
            AA.Fire("SETTINGS_CHANGED", "ignore")
            UI.MarkDirty()
        end
    end)
    r.ignore:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Ignore this item (never show it here)")
        GameTooltip:Show()
    end)
    r.ignore:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnEnter", function(self)
        if not self.row then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.row.link then GameTooltip:SetHyperlink(self.row.link) else GameTooltip:SetText(self.row.name) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function fillRow(r, row)
    r.row = row
    local c = r.cell
    if row.icon then r.icon:SetTexture(row.icon) else r.icon:SetTexture(nil) end
    local tag = row.mark == "auction" and "|cffffd100[AH]|r "
        or (row.mark == "vendor" and "|cffc7c7cf[V]|r " or "")
    c.name:SetText(tag .. qualityHex(row.quality) .. row.name .. "|r")
    c.qty:SetText(row.count)
    setColor(c.qty, WHITE)
    c.vendor:SetText(row.vendor and money(row.vendor) or "...")

    if row.state == "ok" and row.eval then
        local tone = row.stale and DIM or WHITE
        c.market:SetText(money(row.market)); setColor(c.market, tone)
        c.suggested:SetText(money(row.suggested))
        setColor(c.suggested, row.note == "floor" and ORANGE or tone)
        local pt = row.eval.profitTotal
        c.profit:SetText(money(pt and math.floor(pt) or nil))
        setColor(c.profit, (pt and pt < 0) and RED or (row.eval.high and GREEN or tone))
        c.margin:SetText(pct(row.eval.margin)); setColor(c.margin, row.eval.high and GREEN or tone)
        c.age:SetText(row.age); setColor(c.age, row.stale and ORANGE or DIM)
        r.post:Enable()
    else
        local label = row.state == "nolistings" and "no listings" or "no data"
        c.market:SetText(label); setColor(c.market, DIM)
        c.suggested:SetText(""); c.profit:SetText(""); c.margin:SetText("")
        c.age:SetText(row.age or ""); setColor(c.age, DIM)
        r.post:Disable()
    end
    r:Show()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function updateHeaders()
    local f = UI.frame
    for _, h in ipairs(f.headers) do
        local arrow = (h.key == UI.sortKey) and (UI.sortDesc and " v" or " ^") or ""
        h:SetText(h.label .. arrow)
    end
end

local function create()
    local ah = AuctionHouseFrame
    local f = CreateFrame("Frame", "AuctionAgentSellPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(PANEL_W, math.max(ah:GetHeight(), 420))
    f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 2, 0)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("AuctionAgent - Sell") end
    if f.CloseButton then f.CloseButton:HookScript("OnClick", function() UI.userClosed = true end) end

    -- Top controls: icon buttons on the left, filters on the right
    local function iconButton(slot, texture, title, desc, onClick)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(30, 30)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + (slot - 1) * 34, -28)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0.55, 0.45, 0.12, 0.95)   -- thin gold frame around the icon
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexture(texture)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.count = b:CreateFontString(nil, "OVERLAY")
        b.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        b.count:SetTextColor(1, 0.95, 0.4)
        b.title, b.desc = title, desc
        b:SetScript("OnClick", function() pcall(onClick) end)
        b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 3, -3) end)
        b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("TOPLEFT", 2, -2) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self.title, 1, 0.82, 0)
            GameTooltip:AddLine(self.desc, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- n: badge number (hidden when 0 or nil)
        function b:SetCount(n)
            if n and n > 0 then self.count:SetText(n) else self.count:SetText("") end
        end
        return b
    end

    f.scanBags = iconButton(1, "Interface\\Icons\\INV_Misc_Bag_08", "Scan bags",
        "Look up AH prices for the sellable items in your bags.", function() AA.Scanner.StartBags() end)
    f.scanFull = iconButton(2, "Interface\\Icons\\INV_Misc_Spyglass_03", "Full scan",
        "Download the whole auction house to price every item. The server limits how often this can run.",
        function() AA.Scanner.StartFull() end)
    f.postHigh = iconButton(3, "Interface\\Icons\\INV_Misc_Coin_01", "Post all high-margin",
        "Post every item flagged high-margin (asks for confirmation first). The number is how many are flagged.",
        function() S.ConfirmPostAll(S.Rows()) end)
    f.postMarked = iconButton(4, "Interface\\Icons\\INV_Misc_Note_01", "Post all marked",
        "Post every item you marked for the Auction House (asks for confirmation first). Alt+click an item in your bags to mark it.",
        function()
            local rows, skipped = S.MarkedRows(S.Rows())
            if skipped > 0 then
                AA.Print(("%d marked item(s) have no price data and are skipped (scan first)."):format(skipped))
            end
            if #rows == 0 then
                AA.Print("No marked items to post. Alt+click an item in your bags to mark it for the Auction House.")
                return
            end
            S.ConfirmPost(rows)
        end)
    f.postNext = iconButton(5, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Post next",
        "Posts the next queued item (one post per click). The number is how many are left.",
        function() S.PostNext() end)
    f.postNext:Hide()

    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(130, 20)
    f.search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -33)
    f.search:SetAutoFocus(false)
    f.search:SetScript("OnTextChanged", function() UI.MarkDirty() end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local sl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sl:SetPoint("RIGHT", f.search, "LEFT", -6, 0)
    sl:SetText("Filter")

    -- Both checkboxes sit together just left of the filter box.
    local function checkbox(anchorTo, gap, label, onClick)
        local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("RIGHT", anchorTo, "LEFT", gap, 0)
        text:SetText(label)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("RIGHT", text, "LEFT", 0, 0)
        cb:SetScript("OnClick", onClick)
        return cb, text
    end
    local markedText
    f.markedOnly, markedText = checkbox(sl, -16, "Marked only", function() UI.MarkDirty() end)
    f.highOnly = checkbox(f.markedOnly, -8, "High margin only", function(self)
        if AA.settings then AA.settings.panelHighOnly = self:GetChecked() and true or false end
        UI.MarkDirty()
    end)
    f.highOnly:SetChecked(AA.settings and AA.settings.panelHighOnly or false)

    -- Headers
    f.headers = {}
    local x = 10 + PAD
    for _, col in ipairs(COLS) do
        local h = CreateFrame("Button", nil, f)
        h:SetSize(col.w, 18)
        h:SetPoint("TOPLEFT", f, "TOPLEFT", x, -64)
        h.key, h.label = col.key, col.label
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetAllPoints()
        h.text:SetJustifyH(col.key == "name" and "LEFT" or "RIGHT")
        h.SetText = function(self, t) self.text:SetText(t) end
        h:SetScript("OnClick", function()
            if UI.sortKey == col.key then
                UI.sortDesc = not UI.sortDesc
            else
                UI.sortKey, UI.sortDesc = col.key, (col.key ~= "name")
            end
            updateHeaders()
            UI.MarkDirty()
        end)
        f.headers[#f.headers + 1] = h
        x = x + col.w
    end

    -- Scrolling list
    local sf
    if not pcall(function()
        sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    end) or not sf then
        sf = CreateFrame("ScrollFrame", nil, f)
    end
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -84)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 28)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(CONTENT_W, 10)
    sf:SetScrollChild(content)
    f.content, f.scroll, f.rows = content, sf, {}

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.status:SetWidth(PANEL_W - 24)
    f.status:SetJustifyH("LEFT")

    f:SetScript("OnShow", function() UI.MarkDirty() end)
    f:Hide()
    UI.frame = f
    updateHeaders()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function UI.Refresh()
    local f = UI.frame
    if not f or not f:IsShown() or not AA.db then return end
    local all = S.Rows()
    local rows = S.Filter(all, { text = f.search:GetText(), highOnly = f.highOnly:GetChecked(),
        markedOnly = f.markedOnly:GetChecked() })
    S.Sort(rows, UI.sortKey, UI.sortDesc)
    rows = S.MarkedFirst(rows)   -- items marked for auction sit at the top
    local nMarked = #S.MarkedRows(all)
    f.postMarked:SetCount(nMarked)

    for i, row in ipairs(rows) do
        local r = f.rows[i]
        if not r then
            r = createRow(f.content, i)
            f.rows[i] = r
        end
        fillRow(r, row)
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    f.content:SetHeight(math.max(#rows * ROW_H, 10))

    local nHigh = #S.HighMarginRows(all)
    f.postHigh:SetCount(nHigh)
    local q = #S.queue
    if q > 0 then
        f.postNext:SetCount(q)
        f.postNext:Show()
    else
        f.postNext:Hide()
    end
    f.status:SetText(("%d items shown (%d sellable). %d flagged high-margin. Scanner: %s. Prices are net of deposit. %s")
        :format(#rows, #all, nHigh, AA.Scanner.Status(), #all > 0 and "" or "Open your bags to list items."))
end

local dirty
function UI.MarkDirty()
    if dirty then return end
    dirty = true
    C_Timer.After(0.1, function()
        dirty = false
        pcall(UI.Refresh)
    end)
end

---------------------------------------------------------------------------
-- Show only while the AH Sell tab is active
---------------------------------------------------------------------------

local function sellModeActive()
    local ah = _G.AuctionHouseFrame
    if not (ah and ah:IsShown()) then return false end
    local ok, mode = pcall(ah.GetDisplayMode, ah)
    local dm = _G.AuctionHouseFrameDisplayMode
    return ok and dm ~= nil and (mode == dm.ItemSell or mode == dm.CommoditiesSell)
end

local ticker
local function tick()
    if not _G.AuctionHouseFrame then return end
    if UI.createFailed then return end
    if not UI.frame then
        local ok, err = pcall(create)
        if not ok then
            UI.createFailed = true   -- never retry: repeated named CreateFrame calls would collide
            AA.Print("Sell panel could not be built: " .. tostring(err))
            return
        end
    end
    local f = UI.frame
    local want = sellModeActive() and not UI.userClosed
    if want and not f:IsShown() then f:Show()
    elseif not want and f:IsShown() then f:Hide() end
end

function UI.Toggle()
    if not AA.Scanner.ahOpen then AA.Print("Open the Auction House first.") return end
    UI.userClosed = not UI.userClosed
    AA.Print("Sell panel " .. (UI.userClosed and "hidden." or "enabled (shows on the Sell tab)."))
end

AA.Register("AH_SHOW", function()
    UI.userClosed = false
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.3, function() pcall(tick) end)
end)

AA.Register("AH_CLOSED", function()
    if ticker then ticker:Cancel() ticker = nil end
    if UI.frame then UI.frame:Hide() end
end)

for _, ev in ipairs({ "BAGS_CHANGED", "SCAN_DONE", "ITEM_INFO_LOADED", "QUEUE_CHANGED", "POST_RESULT", "SETTINGS_CHANGED", "MARKS_CHANGED" }) do
    AA.Register(ev, function() UI.MarkDirty() end)
end
