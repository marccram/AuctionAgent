local ADDON, AA = ...

-- First-run onboarding:
--  1. A welcome window (once): how prices get into tooltips, how to mark bag items, where
--     the settings are. Re-open any time with /aa welcome.
--  2. At the Auction House, until a full scan has been done (or "Don't ask again" is picked),
--     offer one: it is what fills tooltips with AH prices while questing.
-- Nothing here appears in combat. The decision logic is pure and tested outside the game.

local Ob = {}
AA.Onboarding = Ob

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- True while the user has never completed a full scan and has not opted out of the prompt.
function Ob.WantsFullScan(db)
    if not db then return false end
    if db.fullScanAt then return false end
    return not (db.onboarding and db.onboarding.noFullScanPrompt)
end

local MOD_LABEL = { alt = "Alt", ctrl = "Ctrl", shift = "Shift" }

-- "Alt + left-click" from the current mark settings.
function Ob.MarkHint(s)
    local parts = {}
    for tok in tostring(s and s.markModifier or "alt"):lower():gmatch("%a+") do
        parts[#parts + 1] = MOD_LABEL[tok] or tok
    end
    if #parts == 0 then parts[1] = "Alt" end
    local button = tostring(s and s.markButton or ""):lower():find("right", 1, true) and "right-click" or "left-click"
    return table.concat(parts, " + ") .. " + " .. button
end

if not CreateFrame then return end

---------------------------------------------------------------------------
-- Full-scan prompt at the AH
---------------------------------------------------------------------------

local function bagScanFallback()
    if AA.settings and AA.settings.autoScan and AA.Scanner.ahOpen then
        if AA.settings.scanScope == "full" then AA.Scanner.StartFull() else AA.Scanner.StartBags() end
    end
end

if StaticPopupDialogs then
    StaticPopupDialogs["AUCTIONAGENT_FIRSTSCAN"] = {
        text = "AuctionAgent: scan the whole auction house now?\n\nThis fills item tooltips with AH prices, "
            .. "so you can see what is worth auctioning while you quest. It takes a moment; you can keep browsing.",
        button1 = "Scan now",
        button2 = "Later",
        button3 = "Don't ask again",
        OnAccept = function() pcall(AA.Scanner.StartFull) end,
        OnCancel = function() pcall(bagScanFallback) end,
        OnAlt = function()
            AA.db.onboarding.noFullScanPrompt = true
            AA.Print("OK, the full-scan prompt will not appear again. Scan any time with the spyglass button in the Sell Panel or /aa scan.")
            pcall(bagScanFallback)
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

function Ob.AskFullScan()
    if StaticPopup_Show then StaticPopup_Show("AUCTIONAGENT_FIRSTSCAN") end
end

---------------------------------------------------------------------------
-- Welcome window: three boxes side by side
---------------------------------------------------------------------------

local frame

local BOX_W, BOX_H, BOX_GAP, MARGIN = 200, 226, 10, 18

local function box(parent, index, icon, heading, body)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(BOX_W, BOX_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", MARGIN + (index - 1) * (BOX_W + BOX_GAP), -84)
    pcall(b.SetBackdrop, b, {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    pcall(b.SetBackdropColor, b, 0.04, 0.04, 0.04, 0.75)
    pcall(b.SetBackdropBorderColor, b, 0.65, 0.52, 0.2, 1)

    local ring = b:CreateTexture(nil, "BACKGROUND")
    ring:SetSize(50, 50)
    ring:SetPoint("TOP", b, "TOP", 0, -12)
    ring:SetColorTexture(0.55, 0.45, 0.12, 0.95)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetSize(46, 46)
    ic:SetPoint("CENTER", ring, "CENTER")
    ic:SetTexture(icon)
    ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local h = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOP", ring, "BOTTOM", 0, -10)
    h:SetWidth(BOX_W - 20)
    h:SetHeight(24)
    h:SetJustifyV("TOP")
    h:SetText(heading)

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOP", h, "BOTTOM", 0, -6)
    t:SetWidth(BOX_W - 28)
    t:SetJustifyH("LEFT")
    t:SetJustifyV("TOP")
    t:SetText(body)
    return t
end

local function build()
    local width = MARGIN * 2 + BOX_W * 3 + BOX_GAP * 2
    frame = CreateFrame("Frame", "AuctionAgentWelcome", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(width, 84 + BOX_H + 66)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.TitleText then frame.TitleText:SetText("Welcome to AuctionAgent") end

    local quick = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    quick:SetPoint("TOP", frame, "TOP", 0, -36)
    pcall(function()
        local path = GameFontNormalHuge:GetFont()
        quick:SetFont(path, 26, "")
    end)
    quick:SetTextColor(1, 0.82, 0)
    quick:SetText("AuctionAgent Quick Start")

    box(frame, 1, "Interface\\Icons\\INV_Misc_Coin_01", "Get Latest Pricing",
        "Open the Auction House and a scan starts automatically. The first time, a prompt offers a full "
        .. "scan of the whole auction house. That scan loads prices for every item, so tooltips show the "
        .. "AH value, margin and an auction-or-vendor hint while questing. Bag items are re-priced on each visit.")
    frame.markText = box(frame, 2, "Interface\\Icons\\INV_Misc_Bag_08", "Mark Your Items", "")
    box(frame, 3, "Interface\\Icons\\INV_Misc_Gear_01", "Check Settings",
        "Type |cffffd100/aa|r to open the settings.\n\nCheck the default auction duration, pricing "
        .. "strategy, alert options and more.\n\nThey are also under Game Menu > Options > AddOns > AuctionAgent.")

    local open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    open:SetSize(130, 24)
    open:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", MARGIN, 16)
    open:SetText("Open settings")
    open:SetScript("OnClick", function() frame:Hide(); pcall(AA.OptionsUI.Open) end)

    local ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ok:SetSize(100, 24)
    ok:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -MARGIN, 16)
    ok:SetText("Got it")
    ok:SetScript("OnClick", function() frame:Hide() end)

    -- Closing the window any way counts as having seen it.
    frame:SetScript("OnHide", function() AA.db.onboarding.welcomed = true end)
    frame:Hide()
end

function Ob.ShowWelcome()
    if InCombatLockdown and InCombatLockdown() then
        Ob.pending = true   -- shown when combat ends
        return
    end
    if not frame then
        local ok, err = pcall(build)
        if not ok then AA.Print("Welcome window could not be built: " .. tostring(err)) return end
    end
    frame.markText:SetText(("|cffffd100%s|r on an item in your bags cycles its mark.\n\n"
        .. "|cffffd100AH|r (gold): auction it\n|cffc7c7cfV|r (grey): vendor it\nThird click: clear\n\n"
        .. "At a vendor, press |cffffd100Sell marked|r. At the AH, press |cffffd100Post all marked|r.")
        :format(Ob.MarkHint(AA.settings)))
    frame:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(6, function()
            if AA.db and not AA.db.onboarding.welcomed then pcall(Ob.ShowWelcome) end
        end)
    elseif Ob.pending then
        Ob.pending = false
        pcall(Ob.ShowWelcome)
    end
end)
