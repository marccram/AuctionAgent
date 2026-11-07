local ADDON, AA = ...

-- Options schema: every user-facing setting with its type, range and help text, plus the
-- pure helpers (parse, clamp, format, cycle) the options panel uses. Tested outside the game.
-- Values are stored in plain units (fractions, copper, seconds); `scale` only changes how a
-- number is shown and typed (e.g. 0.5 is shown as 50 with the "%" hint).

local O = {}
AA.Options = O

local floor, max, min = math.floor, math.max, math.min

local function choices(...)
    local out = {}
    for _, c in ipairs({ ... }) do out[#out + 1] = { value = c[1], label = c[2] } end
    return out
end

O.SCHEMA = {
    { section = "Worth auctioning" },
    { key = "marginThreshold", type = "number", scale = 100, hint = "% of vendor value", min = 0, max = 10,
      label = "Minimum margin",
      tip = "An item counts as worth auctioning when its profit (after the AH cut and deposit) is at least this percent of its vendor value." },
    { key = "minProfitCopper", type = "money", min = 0, max = 100000000,
      label = "Minimum profit",
      tip = "...and the profit is at least this much. Type e.g. 10s, 1g 50s or a plain copper number." },
    { key = "depositWeight", type = "number", scale = 100, hint = "% of the deposit", min = 0, max = 1,
      label = "Deposit counted as a cost",
      tip = "The deposit is refunded when the auction sells and lost when it expires. 100% is cautious, 0% ignores it." },
    { key = "duration", type = "choice", label = "Listing duration",
      tip = "Duration used when posting. Longer durations cost a bigger deposit.",
      choices = choices({ 2, "2 hours" }, { 8, "8 hours" }, { 24, "24 hours" }) },

    { section = "Suggested price" },
    { key = "strategy", type = "choice", label = "Pricing strategy",
      tip = "Undercut the lowest listing, match the market value, or post at a percent of market value.",
      choices = choices({ "undercut", "Undercut lowest" }, { "match", "Match market value" },
          { "percent", "Percent of market" }) },
    { key = "undercutMode", type = "choice", label = "Undercut by",
      tip = "How much to undercut: a fixed copper amount, a percent, or whichever is larger.",
      choices = choices({ "larger", "Larger of the two" }, { "copper", "Copper amount" }, { "percent", "Percent" }) },
    { key = "undercutCopper", type = "money", min = 0, max = 10000000, label = "Undercut amount",
      tip = "Fixed undercut in copper (type e.g. 5c or 1s)." },
    { key = "undercutPercent", type = "number", hint = "% of the price", min = 0, max = 50, label = "Undercut percent",
      tip = "Percentage undercut." },
    { key = "percentOfMarket", type = "number", hint = "% of market value", min = 1, max = 200,
      label = "Percent of market",
      tip = "Used by the \"Percent of market\" strategy." },
    { key = "minListingPrice", type = "money", min = 1, max = 100000000, label = "Lowest price ever suggested",
      tip = "Never suggest a price below this." },
    { key = "vendorFloorMult", type = "number", hint = "x vendor price", min = 1, max = 5, label = "Vendor floor",
      tip = "The suggested price never drops below the vendor price times this (1.05 = 5% above vendor)." },

    { section = "Market value" },
    { key = "outlierFraction", type = "number", scale = 100, hint = "% of listings", min = 0.01, max = 1,
      label = "Share of cheapest listings used",
      tip = "Market value is the median of the cheapest listings. This is the share of listings considered." },
    { key = "outlierMax", type = "number", int = true, hint = "listings", min = 1, max = 100,
      label = "Most listings used",
      tip = "Upper limit on how many of the cheapest listings count toward market value." },
    { key = "staleSeconds", type = "number", scale = 1 / 3600, hint = "hours", min = 3600, max = 2592000,
      label = "Dim prices older than",
      tip = "Price data older than this is shown dimmed in the Sell Panel." },
    { key = "maxAgeDays", type = "number", int = true, hint = "days", min = 1, max = 90,
      label = "Forget prices older than",
      tip = "Stored prices older than this are deleted at login." },

    { section = "Scanning" },
    { key = "autoScan", type = "bool", label = "Scan automatically when the AH opens",
      tip = "Off by default. A full scan can freeze the AH briefly; bag scans are light." },
    { key = "scanScope", type = "choice", label = "Automatic scan covers",
      tip = "What an automatic scan does when it runs.",
      choices = choices({ "bags", "Bag items only" }, { "full", "Whole auction house" }) },

    { section = "Tooltips" },
    { key = "tooltipMode", type = "choice", label = "Tooltip detail",
      tip = "How much AuctionAgent adds to item tooltips.",
      choices = choices({ "full", "Full" }, { "compact", "Compact (recommendation only)" }, { "off", "Off" }) },
    { key = "autoCompact", type = "bool", label = "Compact when Auctionator already shows a price",
      tip = "When Auctionator has a price for an item, only the margin and recommendation are added, avoiding duplicate price lines. Items Auctionator has no price for still get the full AH value line." },

    { section = "Alerts" },
    { key = "alertMinimap", type = "bool", label = "Minimap button",
      tip = "Show the minimap button; it turns red with a count when an item is worth auctioning." },
    { key = "alertBagBorder", type = "bool", label = "Gold border on flagged bag items",
      tip = "A thin gold border on bag slots the alerts flagged." },
    { key = "alertChat", type = "bool", label = "Chat message for flagged items",
      tip = "One quiet chat line per flagged item." },
    { key = "alertSound", type = "bool", label = "Sound for flagged items", tip = "A short sound when an item is flagged." },
    { key = "alertInCombat", type = "bool", label = "Alert during combat",
      tip = "Off: alerts wait until combat ends." },
    { key = "alertDelta", type = "number", scale = 100, hint = "% price change", min = 0, max = 10,
      label = "Re-alert when the price moves by",
      tip = "An item alerts once; it alerts again only if its market price changes by more than this." },
    { key = "minimapOffset", type = "number", int = true, hint = "pixels", min = -30, max = 60,
      label = "Minimap button distance",
      tip = "How far from the minimap edge the button sits. Drag the button to change its angle." },

    { section = "Marks" },
    { key = "markModifier", type = "choice", label = "Mark key",
      tip = "Hold this key and click an item in your bags to cycle its mark (Auction, Vendor, none).",
      choices = choices({ "alt", "Alt" }, { "ctrl", "Ctrl" }, { "alt+ctrl", "Alt + Ctrl" },
          { "alt+shift", "Alt + Shift" }, { "ctrl+shift", "Ctrl + Shift" }) },
    { key = "markButton", type = "choice", label = "Mark mouse button",
      tip = "Right-click sells an item when a vendor is open, so left is the safe choice.",
      choices = choices({ "LeftButton", "Left click" }, { "RightButton", "Right click" }) },
    { key = "rememberMarks", type = "bool", label = "Keep marks when an item leaves my bags",
      tip = "Off: a mark is dropped when the item leaves your bags. On: marks stay until you clear them." },
    { key = "autoSellMarked", type = "bool", label = "Sell vendor-marked items when a vendor opens",
      tip = "Off by default. On: no click needed, marked items sell as soon as you open a vendor." },

    { section = "Posting" },
    { key = "batchPost", type = "bool", label = "Experimental: post a whole queue from one click",
      tip = "Blizzard may only allow one post per click. If it does not work, leave this off." },
}

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

function O.Find(key)
    for _, e in ipairs(O.SCHEMA) do
        if e.key == key then return e end
    end
end

function O.Clamp(entry, v)
    if type(v) ~= "number" then return nil end
    if entry.min then v = max(entry.min, v) end
    if entry.max then v = min(entry.max, v) end
    if entry.int then v = floor(v + 0.5) end
    return v
end

-- "12g 3s 4c" style text, no color codes.
function O.MoneyText(copper)
    copper = floor(math.abs(copper or 0))
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- "1g 20s 5c", "20s", "150" (plain number = copper). Returns copper or nil.
function O.ParseMoney(text)
    text = tostring(text or ""):lower():gsub(",", "")
    local plain = tonumber(text)
    if plain then return plain >= 0 and floor(plain + 0.5) or nil end
    local total, found = 0, false
    for n, unit in text:gmatch("(%d+%.?%d*)%s*([gsc])") do
        found = true
        local v = tonumber(n)
        total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    if not found then return nil end
    -- reject leftovers like "5x"
    local rest = text:gsub("%d+%.?%d*%s*[gsc]", ""):gsub("%s", "")
    if rest ~= "" then return nil end
    return floor(total + 0.5)
end

-- Text typed into the box -> stored value (clamped), or nil when it cannot be understood.
function O.Parse(entry, text)
    if entry.type == "money" then
        local c = O.ParseMoney(text)
        return c and O.Clamp(entry, c) or nil
    elseif entry.type == "number" then
        local cleaned = tostring(text or ""):gsub("[%%xX]", ""):gsub("%s", "")
        local n = tonumber(cleaned)
        if not n then return nil end
        return O.Clamp(entry, n / (entry.scale or 1))
    end
    return nil
end

-- Stored value -> text for the box.
function O.Format(entry, value)
    if value == nil then return "" end
    if entry.type == "money" then return O.MoneyText(value) end
    local shown = value * (entry.scale or 1)
    if entry.int or math.abs(shown - floor(shown + 0.5)) < 1e-6 then
        return ("%d"):format(floor(shown + 0.5))
    end
    return (("%.2f"):format(shown):gsub("0+$", ""):gsub("%.$", ""))
end

function O.ChoiceLabel(entry, value)
    for _, c in ipairs(entry.choices or {}) do
        if c.value == value then return c.label end
    end
    return tostring(value)
end

-- The choice after `value` (wraps around; an unknown value goes to the first choice).
function O.NextChoice(entry, value)
    local list = entry.choices or {}
    for i, c in ipairs(list) do
        if c.value == value then return list[i % #list + 1].value end
    end
    return list[1] and list[1].value
end
