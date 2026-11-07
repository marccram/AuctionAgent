local ADDON, AA = ...

-- Pure Lua: no WoW API calls in this file, so it can be unit tested outside the game
-- (see tests/). All money values are copper. Per-unit unless a name says otherwise.

local P = {}
AA.Prices = P

P.DEFAULTS = {
    ahCut = 0.05,             -- verify against the live client (deposit rules also apply)
    marginThreshold = 0.50,   -- 0.50 = 50%
    minProfitCopper = 1000,   -- 10 silver
    strategy = "match",       -- "undercut" | "match" | "percent"
    undercutMode = "larger",  -- "copper" | "percent" | "larger"
    undercutCopper = 1,
    undercutPercent = 1,      -- percent of the base price
    percentOfMarket = 95,     -- used by the "percent" strategy
    minListingPrice = 1,
    vendorFloorMult = 1.05,
    duration = 8,             -- listing duration in hours (2/8/24 on this client)
    -- Deposit = max(minDeposit, vendor * qty * depositRate * hours / 24), per LISTING.
    -- Verified against the live client (WoW Forever 1.60.1): durations are 2h / 8h / 24h,
    -- and 24h costs 60% of vendor value; 100c minimum even for vendor-price-0 items.
    -- The 2h and 8h rates are assumed linear (5% / 20%): they only ever showed the minimum.
    -- Deposit is refunded when the auction sells and lost if it expires, so depositWeight
    -- is how much of it counts as a cost: 1 = all (conservative), 0 = ignore it.
    depositRate = 0.6,        -- fraction of vendor value per 24 hours
    minDeposit = 100,         -- copper floor per listing
    depositWeight = 1.0,
    outlierFraction = 0.15,   -- market value = median of the lowest 15% of listings
    outlierMax = 10,
    staleSeconds = 86400,     -- dim data older than this
    maxAgeDays = 14,          -- prune data older than this
}

local floor, ceil, max = math.floor, math.ceil, math.max

local function opt(s, key)
    if s and s[key] ~= nil then return s[key] end
    return P.DEFAULTS[key]
end

local function isNum(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
P.IsNum = isNum

---------------------------------------------------------------------------
-- Market value (swap this function to change the algorithm)
---------------------------------------------------------------------------

-- prices: array of per-unit buyout prices, one entry per unit-weighted listing.
-- Lowest ~15% of listings (min 1, max 10), take the median. Fewer than 3 listings
-- falls back to the lowest. Returns copper (integer) or nil.
function P.MarketValue(prices, s)
    if type(prices) ~= "table" then return nil end
    local list = {}
    for _, p in ipairs(prices) do
        if isNum(p) and p > 0 then list[#list + 1] = p end
    end
    local n = #list
    if n == 0 then return nil end
    table.sort(list)
    if n < 3 then return floor(list[1]) end

    local k = ceil(n * opt(s, "outlierFraction"))
    if k < 1 then k = 1 end
    if k > opt(s, "outlierMax") then k = opt(s, "outlierMax") end
    if k > n then k = n end

    if k % 2 == 1 then
        return floor(list[(k + 1) / 2])
    end
    return floor((list[k / 2] + list[k / 2 + 1]) / 2)
end

-- Streaming, unit-weighted version of MarketValue for scans. Add(unitPrice, quantity)
-- once per auction row; only the lowest `outlierMax` units are kept, so folding in a
-- 96k-row bulk scan stays cheap. Equivalent to MarketValue over the expanded unit list.
local Acc = {}
Acc.__index = Acc

function P.NewAccumulator(s)
    return setmetatable({ s = s, cap = opt(s, "outlierMax"), low = {}, units = 0, rows = 0 }, Acc)
end

function Acc:Add(unitPrice, quantity)
    if not isNum(unitPrice) or unitPrice <= 0 then return end
    quantity = (isNum(quantity) and quantity >= 1) and floor(quantity) or 1
    self.units = self.units + quantity
    self.rows = self.rows + 1
    local low, cap = self.low, self.cap
    for _ = 1, math.min(quantity, cap) do
        if #low >= cap and unitPrice >= low[#low] then break end
        local i = #low + 1
        while i > 1 and low[i - 1] > unitPrice do
            low[i] = low[i - 1]
            i = i - 1
        end
        low[i] = unitPrice
        if #low > cap then low[#low] = nil end
    end
end

-- Returns { market, low, count (rows), qty (units) } or nil if nothing was added.
function Acc:Result()
    local low, n = self.low, self.units
    if n == 0 or #low == 0 then return nil end
    local market
    if n < 3 then
        market = floor(low[1])
    else
        local k = ceil(n * opt(self.s, "outlierFraction"))
        if k < 1 then k = 1 end
        if k > self.cap then k = self.cap end
        if k > #low then k = #low end
        if k % 2 == 1 then
            market = floor(low[(k + 1) / 2])
        else
            market = floor((low[k / 2] + low[k / 2 + 1]) / 2)
        end
    end
    return { market = market, low = floor(low[1]), count = self.rows, qty = n }
end

---------------------------------------------------------------------------
-- Profit math
---------------------------------------------------------------------------

function P.AhNet(market, s)
    if not isNum(market) then return nil end
    return floor(market * (1 - opt(s, "ahCut")))
end

-- Estimated deposit for ONE listing of `qty` units, in copper (before depositWeight).
function P.Deposit(vendor, qty, s)
    local v = isNum(vendor) and vendor or 0
    local n = (isNum(qty) and qty >= 1) and qty or 1
    local d = floor(v * n * opt(s, "depositRate") * opt(s, "duration") / 24)
    return max(d, opt(s, "minDeposit"))
end

-- `extra` below is an optional per-unit cost of listing (the weighted deposit share).

-- Margin of selling on the AH vs vendoring. nil = unknown, math.huge = vendor price 0
-- with a positive take (any AH value is unbounded profit).
function P.Margin(market, vendor, s, extra)
    if not isNum(market) or market <= 0 then return nil end
    if not isNum(vendor) then return nil end
    local net = P.AhNet(market, s) - (extra or 0)
    if vendor <= 0 then return net > 0 and math.huge or 0 end
    return (net - vendor) / vendor
end

-- Per-unit profit of auctioning instead of vendoring. nil if market unknown.
function P.Profit(market, vendor, s, extra)
    if not isNum(market) or market <= 0 then return nil end
    local net = P.AhNet(market, s)
    return net - (isNum(vendor) and vendor or 0) - (extra or 0)
end

-- Returns isHigh, margin, profitPerUnit
function P.IsHighMargin(market, vendor, s, extra)
    local margin = P.Margin(market, vendor, s, extra)
    if margin == nil then return false, nil, nil end
    local profit = P.Profit(market, vendor, s, extra)
    local ok = margin >= opt(s, "marginThreshold") and profit >= opt(s, "minProfitCopper")
    return ok, margin, profit
end

-- Everything a UI needs to describe one item. entry is a price DB entry (or nil),
-- vendor is per-unit copper (or nil if not cached yet), qty is the stack size.
-- state: "nodata" (never scanned) | "nolistings" | "ok"
-- rec: "auction" | "vendor" | nil (marginal)
function P.Evaluate(entry, vendor, qty, now, s)
    qty = (isNum(qty) and qty >= 1) and qty or 1
    local r = { vendor = vendor, qty = qty }
    if not entry then
        r.state = "nodata"
        return r
    end
    r.age = P.AgeString(entry.t, now)
    r.stale = P.IsStale(entry.t, now, s)
    if not entry.market then
        r.state = "nolistings"
        return r
    end
    r.state = "ok"
    r.market, r.low = entry.market, entry.low
    r.marketTotal = entry.market * qty
    -- One listing of the whole stack: its deposit, weighted, spread per unit.
    r.deposit = P.Deposit(vendor, qty, s)
    local extra = r.deposit * opt(s, "depositWeight") / qty
    r.margin = P.Margin(entry.market, vendor, s, extra)
    r.profit = P.Profit(entry.market, vendor, s, extra)   -- per unit, net of deposit
    r.profitTotal = r.profit and r.profit * qty or nil
    r.high = P.IsHighMargin(entry.market, vendor, s, extra)
    if r.high then
        r.rec = "auction"
    elseif isNum(vendor) and vendor > 0 and r.profit and r.profit <= 0 then
        r.rec = "vendor"
    end
    return r
end

---------------------------------------------------------------------------
-- Suggested listing price
---------------------------------------------------------------------------

function P.PriceFloor(vendor, s)
    local v = isNum(vendor) and vendor or 0
    return max(ceil(v * opt(s, "vendorFloorMult")), opt(s, "minListingPrice"))
end

local function undercutAmount(base, s)
    local mode = opt(s, "undercutMode")
    local c = opt(s, "undercutCopper")
    local pct = floor(base * opt(s, "undercutPercent") / 100)
    if mode == "copper" then return c end
    if mode == "percent" then return pct end
    return max(c, pct)
end

-- lowest: lowest current buyout per unit (or nil), market: market value per unit (or nil).
-- Returns price (copper per unit) or nil, note. note: "nodata" | "floor" | nil
function P.SuggestPrice(lowest, market, vendor, s)
    local strategy = opt(s, "strategy")
    local price
    if strategy == "match" then
        price = isNum(market) and market or nil
    elseif strategy == "percent" then
        price = isNum(market) and floor(market * opt(s, "percentOfMarket") / 100) or nil
    else
        local base = isNum(lowest) and lowest or (isNum(market) and market or nil)
        if base then price = base - undercutAmount(base, s) end
    end
    if not price then return nil, "nodata" end

    local fl = P.PriceFloor(vendor, s)
    if price < fl then return fl, "floor" end
    return floor(price), nil
end

---------------------------------------------------------------------------
-- Staleness and formatting
---------------------------------------------------------------------------

function P.IsStale(t, now, s)
    if not isNum(t) or not isNum(now) then return true end
    return (now - t) > opt(s, "staleSeconds")
end

function P.AgeString(t, now)
    if not isNum(t) or not isNum(now) then return "never" end
    local d = now - t
    if d < 60 then return "just now" end
    if d < 3600 then return floor(d / 60) .. "m ago" end
    if d < 86400 then return floor(d / 3600) .. "h ago" end
    return floor(d / 86400) .. "d ago"
end

-- Money with the game's coin icons, e.g. "12 [gold] 34 [silver] 56 [copper]". The |T escapes
-- render in tooltips, fontstrings, chat and popups; size 0 means "match the text height".
local ICON = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
P.ICON = ICON

function P.FormatMoneyIcons(copper)
    if not isNum(copper) then return "?" end
    local neg = copper < 0
    copper = floor(math.abs(copper))
    local g, sv, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. ICON.g end
    if sv > 0 then parts[#parts + 1] = sv .. ICON.s end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. ICON.c end
    return (neg and "-" or "") .. table.concat(parts, " ")
end

-- Money text. In the game P.icons is true (set in Core) and this returns the icon form;
-- plain "12g 34s 56c" otherwise (tests, any non-UI use).
function P.FormatMoney(copper)
    if P.icons then return P.FormatMoneyIcons(copper) end
    if not isNum(copper) then return "?" end
    local neg = copper < 0
    copper = floor(math.abs(copper))
    local g, sv, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if sv > 0 then parts[#parts + 1] = sv .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return (neg and "-" or "") .. table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Price database
---------------------------------------------------------------------------

function P.MakeRealmKey(realm, faction)
    return (realm or "?") .. "-" .. (faction or "Neutral")
end

function P.Get(db, realmKey, itemID)
    local r = db and db.prices and db.prices[realmKey]
    return r and r[itemID] or nil
end

-- listings: array of per-unit prices. Stores {market, low, count, qty, t, source}.
-- Returns the stored entry, or nil if there were no usable listings.
function P.Update(db, realmKey, itemID, listings, qty, now, source, s)
    local market = P.MarketValue(listings, s)
    if not market then return nil end
    local low
    for _, p in ipairs(listings) do
        if isNum(p) and p > 0 and (not low or p < low) then low = p end
    end
    db.prices = db.prices or {}
    db.prices[realmKey] = db.prices[realmKey] or {}
    local e = { market = market, low = floor(low), count = #listings, qty = qty or #listings,
                t = now, source = source or "search" }
    db.prices[realmKey][itemID] = e
    return e
end

-- Record that an item was checked and has no listings (so UIs can say "No listings").
function P.StoreNone(db, realmKey, itemID, now, source)
    db.prices = db.prices or {}
    db.prices[realmKey] = db.prices[realmKey] or {}
    local e = { count = 0, qty = 0, t = now, source = source or "scan" }
    db.prices[realmKey][itemID] = e
    return e
end

-- Store an accumulator result ({market, low, count, qty}). Returns the entry.
function P.Store(db, realmKey, itemID, result, now, source)
    if not result then return nil end
    db.prices = db.prices or {}
    db.prices[realmKey] = db.prices[realmKey] or {}
    local e = { market = result.market, low = result.low, count = result.count,
                qty = result.qty, t = now, source = source or "scan" }
    db.prices[realmKey][itemID] = e
    return e
end

-- Remove entries older than maxAgeDays. Returns number removed.
function P.Prune(db, now, maxAgeDays)
    if not (db and db.prices and isNum(now)) then return 0 end
    local cutoff = now - (maxAgeDays or P.DEFAULTS.maxAgeDays) * 86400
    local removed = 0
    for _, realm in pairs(db.prices) do
        for id, e in pairs(realm) do
            if not isNum(e.t) or e.t < cutoff then
                realm[id] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end
