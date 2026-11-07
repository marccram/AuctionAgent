local ADDON, AA = ...
_G.AuctionAgent = AA

local L = AA.L
AA.name = ADDON

AA.Prices.icons = true   -- show money with the game coin icons everywhere in the game UI

local function getVersion()
    local ok, v = pcall(function() return C_AddOns.GetAddOnMetadata(ADDON, "Version") end)
    return ok and v or "dev"
end
AA.version = getVersion()

function AA.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[AuctionAgent]|r " .. tostring(msg))
end

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Settings defaults. Price-related defaults live in Prices.DEFAULTS.
AA.DEFAULTS = copyDefaults(AA.Prices.DEFAULTS, {
    debug = false,
    duration = 8,             -- hours (2/8/24)
    autoScan = true,
    scanScope = "bags",       -- "bags" | "full"
    tooltipMode = "full",     -- "full" | "compact" | "off"
    autoCompact = true,       -- compact tooltip only for items Auctionator already prices
    lastScan = 0,
    batchPost = false,        -- EXPERIMENTAL: try to post the whole queue from one click
    panelHighOnly = false,
    markModifier = "alt",     -- bag click that cycles an item's mark: alt, ctrl, shift or combos like alt+ctrl
    markButton = "LeftButton", -- LeftButton | RightButton (right-click sells at a vendor, so left is safer)
    rememberMarks = false,    -- false: a mark is dropped when the item leaves your bags
    autoSellMarked = false,   -- sell vendor-marked items as soon as a merchant opens (no click)
    alertMinimap = true,
    alertBagBorder = true,
    alertChat = false,
    alertSound = false,
    alertInCombat = false,
    alertDelta = 0.25,        -- re-alert an item only if its market price moved by more than this fraction
    minimapOffset = 5,        -- distance of the button from the minimap edge; raise it to sit further out
    minimapAngle = 225,       -- minimap button position (degrees); drag the button to move it
})

function AA.RealmKey()
    return AA.Prices.MakeRealmKey(GetNormalizedRealmName(), UnitFactionGroup("player"))
end

local function initDB()
    AuctionAgentDB = AuctionAgentDB or {}
    local db = AuctionAgentDB
    db.settings = copyDefaults(AA.DEFAULTS, db.settings or {})
    db.prices = db.prices or {}
    db.marks = db.marks or {}
    db.ignore = db.ignore or {}
    db.onboarding = db.onboarding or {}
    db.debugLog = AA.Debug.lines   -- saved at logout/reload so the probe output is readable on disk
    AuctionAgentCharDB = AuctionAgentCharDB or { sessionMarks = {} }
    AA.db = db
    AA.settings = db.settings
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        initDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        AA.Prices.Prune(AA.db, time(), AA.settings.maxAgeDays)
        AA.Print(L["LOADED"]:format(AA.version))
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function printHelp()
    AA.Print(L["HELP_HEADER"])
    AA.Print("  /aa              open the options panel (also under Game Menu > Options > AddOns)")
    AA.Print("  /aa scan [bags|cached]  at the AH: full scan (default), bag items only, or reuse the snapshot the client already holds")
    AA.Print("  /aa list         sellable bag items with AH value, vendor price, profit")
    AA.Print("  /aa price <item> AH data for an item link or id")
    AA.Print("  /aa status       scan status and data age")
    AA.Print("  /aa set [key val] list or change settings (e.g. /aa set minProfitCopper 100)")
    AA.Print("  /aa panel        show/hide the Sell panel (it appears on the AH Sell tab)")
    AA.Print("  /aa welcome      show the quick-start window again")
    AA.Print("  /aa mark auction|vendor|clear [item]  mark an item (or alt+click it in your bags to cycle)")
    AA.Print("  /aa marks [clear]  list or clear all marks")
    AA.Print("  /aa unignore [id|all]  list or clear ignored items")
    AA.Print("  /aa debug        run the API probe (see /aa debug help)")
end

local P = AA.Prices

local function money(c) return c and P.FormatMoney(c) or "?" end

local function listCmd()
    if AA.Alerts then AA.Alerts.Clear() end   -- looking at the list counts as seeing the alerts
    local list = AA.Bags.Summarize()
    if #list == 0 then AA.Print("No sellable items in your bags.") return end
    AA.Print(("%d sellable item types (best first):"):format(#list))
    for i, g in ipairs(list) do
        if i > 20 then AA.Print(("  ... and %d more"):format(#list - 20)) break end
        local e = g.eval
        local label = g.link or g.name or ("item " .. g.itemID)
        if e.state == "ok" then
            AA.Print(("  %s x%d  AH %s ea  vendor %s  %s  (%s)%s"):format(label, g.count, money(e.market),
                money(g.vendor), e.profitTotal and ("profit " .. money(e.profitTotal)) or "profit ?", e.age,
                e.rec == "auction" and "  [AUCTION]" or (e.rec == "vendor" and "  [vendor]" or "")))
        else
            AA.Print(("  %s x%d  %s  vendor %s"):format(label, g.count,
                e.state == "nolistings" and "no listings" or "no AH data", money(g.vendor)))
        end
    end
end

AA.ListCmd = listCmd

local function priceCmd(arg)
    local id = tonumber(arg) or tonumber((arg or ""):match("item:(%d+)"))
    if not id then AA.Print("Usage: /aa price <item link or id>") return end
    local entry = P.Get(AA.db, AA.RealmKey(), id)
    local vendor = AA.Bags.VendorPrice(id)
    local e = P.Evaluate(entry, vendor, 1, time(), AA.settings)
    if e.state == "ok" then
        AA.Print(("Item %d: market %s, lowest %s, %d listings / %d units (%s, via %s). Vendor %s. Margin %s.")
            :format(id, money(e.market), money(e.low), entry.count or 0, entry.qty or 0, e.age,
                entry.source or "?", money(vendor), e.margin and (e.margin == math.huge and "unbounded" or
                ("%+d%%"):format(math.floor(e.margin * 100 + 0.5))) or "?"))
    else
        AA.Print(("Item %d: %s. Vendor %s."):format(id, e.state == "nolistings" and "no listings" or "no AH data", money(vendor)))
    end
end

-- /aa set <key> <value>, /aa set  (lists keys). Stopgap until the settings panel exists.
local function setCmd(rest)
    local key, value = rest:match("^(%S+)%s+(.-)%s*$")
    if not key then
        local keys = {}
        for k, v in pairs(AA.settings) do
            if type(v) ~= "table" then keys[#keys + 1] = k .. "=" .. tostring(v) end
        end
        table.sort(keys)
        AA.Print("Settings: " .. table.concat(keys, ", "))
        AA.Print("Change one with /aa set <key> <value>, e.g. /aa set minProfitCopper 100")
        return
    end
    local cur = AA.settings[key]
    if cur == nil or type(cur) == "table" then AA.Print("Unknown setting: " .. key) return end
    local new
    if type(cur) == "number" then new = tonumber(value)
    elseif type(cur) == "boolean" then
        local v = value:lower()
        if v == "true" or v == "on" or v == "1" or v == "yes" then new = true
        elseif v == "false" or v == "off" or v == "0" or v == "no" then new = false end
    else new = value end
    if new == nil then AA.Print(("Bad value for %s (currently %s)."):format(key, tostring(cur))) return end
    AA.settings[key] = new
    AA.Print(("%s = %s"):format(key, tostring(new)))
    AA.Fire("SETTINGS_CHANGED", key)
end

local function statusCmd()
    local n, oldest = 0, nil
    for _, e in pairs(AA.db.prices[AA.RealmKey()] or {}) do
        n = n + 1
        if e.t and (not oldest or e.t < oldest) then oldest = e.t end
    end
    AA.Print(("Scanner: %s. %d items stored for %s (oldest %s). Last scan: %s."):format(
        AA.Scanner.Status(), n, AA.RealmKey(), P.AgeString(oldest, time()),
        AA.settings.lastScan > 0 and P.AgeString(AA.settings.lastScan, time()) or "never"))
end

SLASH_AUCTIONAGENT1 = "/aa"
SLASH_AUCTIONAGENT2 = "/auctionagent"
SlashCmdList["AUCTIONAGENT"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "debug" then
        AA.Debug.Command(rest)
    elseif cmd == "scan" then
        local what = rest:lower()
        if what == "bags" then AA.Scanner.StartBags()
        elseif what == "cached" then AA.Scanner.StartCached()
        else AA.Scanner.StartFull() end
    elseif cmd == "list" then
        listCmd()
    elseif cmd == "price" then
        priceCmd(rest)
    elseif cmd == "status" then
        statusCmd()
    elseif cmd == "set" then
        setCmd(rest)
    elseif cmd == "panel" then
        AA.SellPanel.Toggle()
    elseif cmd == "mark" then
        AA.Marks.Command(rest)
    elseif cmd == "marks" then
        if rest:lower() == "clear" then AA.Marks.ClearAll() else AA.Marks.List() end
    elseif cmd == "unignore" then
        local id = tonumber(rest) or tonumber(rest:match("item:(%d+)"))
        if rest:lower() == "all" then
            wipe(AA.db.ignore)
            AA.Print("Ignore list cleared.")
            AA.Fire("SETTINGS_CHANGED", "ignore")
        elseif id and AA.db.ignore[id] then
            AA.db.ignore[id] = nil
            AA.Print("No longer ignoring item " .. id .. ".")
            AA.Fire("SETTINGS_CHANGED", "ignore")
        else
            local ids = {}
            for k in pairs(AA.db.ignore) do ids[#ids + 1] = k end
            table.sort(ids)
            AA.Print("Ignored item ids: " .. (#ids > 0 and table.concat(ids, ", ") or "(none)")
                .. ". Use /aa unignore <id|all>.")
        end
    elseif cmd == "" or cmd == "options" or cmd == "settings" or cmd == "config" then
        AA.OptionsUI.Open()
    elseif cmd == "welcome" then
        AA.Onboarding.ShowWelcome()
    elseif cmd == "help" then
        printHelp()
    else
        printHelp()
    end
end
