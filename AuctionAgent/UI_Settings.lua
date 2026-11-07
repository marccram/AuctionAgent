local ADDON, AA = ...

-- Options panel: registered in Blizzard's Settings window as an AddOns category, built from
-- Options.SCHEMA. Rows are created the first time the panel is shown and re-read from the
-- saved settings on every show. All UI work is under pcall.

local O = AA.Options
local U = {}
AA.OptionsUI = U

local CONTENT_W = 620
local CTRL_X = 330
local ROW_H = 28

local function set(key, value)
    AA.settings[key] = value
    AA.Fire("SETTINGS_CHANGED", key)
end

local function hookTooltip(frame, title, text)
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A mouse-over area over the label so every row shows its help text.
local function labelArea(content, y, width, title, text)
    local hit = CreateFrame("Frame", nil, content)
    hit:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
    hit:SetSize(width, ROW_H - 4)
    hookTooltip(hit, title, text)
end

local function newLabel(content, text, x, y)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - 4)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function addBool(content, e, y, refreshers)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(e.label)
    cb:SetScript("OnClick", function(self) set(e.key, self:GetChecked() and true or false) end)
    hookTooltip(cb, e.label, e.tip)
    labelArea(content, y, CTRL_X - 20, e.label, e.tip)
    refreshers[#refreshers + 1] = function() cb:SetChecked(AA.settings[e.key] and true or false) end
end

local function addNumber(content, e, y, refreshers)
    newLabel(content, e.label, 12, y)
    labelArea(content, y, CTRL_X - 20, e.label, e.tip)
    local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    eb:SetSize(110, 20)
    eb:SetPoint("TOPLEFT", content, "TOPLEFT", CTRL_X, y - 2)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(24)
    local function show() eb:SetText(O.Format(e, AA.settings[e.key])) end
    local function commit()
        local v = O.Parse(e, eb:GetText())
        if v ~= nil and v ~= AA.settings[e.key] then set(e.key, v) end
        show()
    end
    eb:SetScript("OnEnterPressed", function(self) commit(); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) show(); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", commit)
    hookTooltip(eb, e.label, e.tip)
    if e.hint then
        local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", eb, "RIGHT", 8, 0)
        hint:SetText(e.hint)
    end
    refreshers[#refreshers + 1] = show
end

local function addChoice(content, e, y, refreshers)
    newLabel(content, e.label, 12, y)
    labelArea(content, y, CTRL_X - 20, e.label, e.tip)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(190, 22)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", CTRL_X - 4, y - 2)
    local function show() b:SetText(O.ChoiceLabel(e, AA.settings[e.key])) end
    b:SetScript("OnClick", function()
        set(e.key, O.NextChoice(e, AA.settings[e.key]))
        show()
    end)
    hookTooltip(b, e.label, e.tip .. "\n\nClick to change.")
    refreshers[#refreshers + 1] = show
end

---------------------------------------------------------------------------
-- Reset / clear
---------------------------------------------------------------------------

local KEEP_ON_RESET = { lastScan = true, minimapAngle = true }

function U.Reset()
    for k, v in pairs(AA.DEFAULTS) do
        if type(v) ~= "table" and not KEEP_ON_RESET[k] then AA.settings[k] = v end
    end
    AA.Fire("SETTINGS_CHANGED", "reset")
    U.Refresh()
    AA.Print("Settings reset to defaults.")
end

if StaticPopupDialogs then
    StaticPopupDialogs["AUCTIONAGENT_RESET"] = {
        text = "Reset all AuctionAgent settings to their defaults? Your marks and price data are kept.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function() pcall(U.Reset) end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local function countIgnored()
    local n = 0
    for _ in pairs(AA.db.ignore) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local refreshers = {}
local ignoreButton

function U.Refresh()
    for _, fn in ipairs(refreshers) do pcall(fn) end
    if ignoreButton and AA.db then
        local n = countIgnored()
        ignoreButton:SetText(("Clear ignored items (%d)"):format(n))
        if n > 0 then ignoreButton:Enable() else ignoreButton:Disable() end
    end
end

local function buildContent(content)
    local y = -6
    for _, e in ipairs(O.SCHEMA) do
        if e.section then
            y = y - 12
            local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
            fs:SetText(e.section)
            y = y - 26
        else
            if e.type == "bool" then addBool(content, e, y, refreshers)
            elseif e.type == "choice" then addChoice(content, e, y, refreshers)
            else addNumber(content, e, y, refreshers) end
            y = y - ROW_H
        end
    end

    y = y - 20
    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetSize(170, 24)
    reset:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function() if StaticPopup_Show then StaticPopup_Show("AUCTIONAGENT_RESET") end end)

    ignoreButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    ignoreButton:SetSize(200, 24)
    ignoreButton:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    ignoreButton:SetScript("OnClick", function()
        wipe(AA.db.ignore)
        AA.Print("Ignore list cleared.")
        AA.Fire("SETTINGS_CHANGED", "ignore")
        U.Refresh()
    end)
    hookTooltip(ignoreButton, "Ignored items", "Items you hid from the Sell Panel with the X button.")

    content:SetSize(CONTENT_W, -y + 50)
end

local function createPanel()
    local panel = CreateFrame("Frame", "AuctionAgentOptionsPanel")
    panel.name = "AuctionAgent"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("AuctionAgent")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Hover any setting for details. Changes apply immediately.")

    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -58)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(CONTENT_W, 10)
    sf:SetScrollChild(content)

    local built
    panel:SetScript("OnShow", function()
        if not built then
            built = true
            local ok, err = pcall(buildContent, content)
            if not ok then AA.Print("Options panel could not be built: " .. tostring(err)) end
        end
        U.Refresh()
    end)
    return panel
end

function U.Register()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return false
    end
    local panel = createPanel()
    U.category = Settings.RegisterCanvasLayoutCategory(panel, "AuctionAgent")
    Settings.RegisterAddOnCategory(U.category)
    return true
end

function U.Open()
    if InCombatLockdown and InCombatLockdown() then
        AA.Print("The options panel cannot be opened during combat.")
        return
    end
    if U.category and Settings and Settings.OpenToCategory then
        local id = U.category.GetID and U.category:GetID() or U.category.ID
        if pcall(Settings.OpenToCategory, id) then return end
    end
    AA.Print("Could not open the options panel. Use /aa set <key> <value> instead (/aa set lists the keys).")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local ok, err = pcall(U.Register)
    if not ok then AA.Print("Options panel could not be registered: " .. tostring(err)) end
end)
