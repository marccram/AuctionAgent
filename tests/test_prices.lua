local P = AA.Prices

-- Market value --------------------------------------------------------------

test("market: no listings", function()
    eq(P.MarketValue({}), nil)
    eq(P.MarketValue(nil), nil)
end)

test("market: ignores invalid entries", function()
    eq(P.MarketValue({ 0, -5, "x", 100 }), 100)
end)

test("market: fewer than 3 listings uses the lowest", function()
    eq(P.MarketValue({ 500, 200 }), 200)
    eq(P.MarketValue({ 700 }), 700)
end)

test("market: 3-6 listings -> k=1, the lowest", function()
    eq(P.MarketValue({ 900, 100, 500 }), 100)
    eq(P.MarketValue({ 900, 100, 500, 600, 700, 800 }), 100)
end)

test("market: 20 listings -> k=3, median of lowest 3", function()
    local l = {}
    for i = 1, 20 do l[i] = i * 100 end
    eq(P.MarketValue(l), 200)
end)

test("market: low outlier is dampened by median", function()
    -- one bait listing at 1, then a real market around 1000
    local l = { 1 }
    for i = 1, 19 do l[#l + 1] = 1000 + i end
    -- n=20 -> k=3 -> lowest three are 1, 1001, 1002 -> median 1001
    eq(P.MarketValue(l), 1001)
end)

test("market: capped at 10 listings (even k averages the middle two)", function()
    local l = {}
    for i = 1, 200 do l[i] = i * 10 end
    -- k capped at 10 -> median of 10,20..100 = (50+60)/2
    eq(P.MarketValue(l), 55)
end)

test("market: unsorted input is fine", function()
    eq(P.MarketValue({ 30, 10, 20 }), 10)
end)

-- Accumulator ---------------------------------------------------------------

test("accumulator: matches MarketValue for qty-1 rows", function()
    local seed = 12345
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
    for _, size in ipairs({ 1, 2, 3, 7, 20, 60, 200 }) do
        local list, acc = {}, P.NewAccumulator()
        for i = 1, size do
            local p = rnd(100000)
            list[i] = p
            acc:Add(p, 1)
        end
        eq(acc:Result().market, P.MarketValue(list), "size " .. size)
    end
end)

test("accumulator: weights by quantity (real Oil of Olaf listings)", function()
    -- 10 @19, 58 @20, 5 @25 ... 324 units total; lowest 10 units are all 19
    local acc = P.NewAccumulator()
    acc:Add(19, 10)
    acc:Add(20, 58)
    acc:Add(25, 5)
    for _ = 1, 10 do acc:Add(30, 25) end
    local r = acc:Result()
    eq(r.market, 19)
    eq(r.low, 19)
    eq(r.count, 13)
    eq(r.qty, 73 + 250)
end)

test("accumulator: a single bait unit does not set the price", function()
    local acc = P.NewAccumulator()
    acc:Add(1, 1)
    acc:Add(1000, 200)
    -- n=201 -> k capped at 10 -> lowest 10 units: 1, then 9x1000 -> median (5th+6th)/2 = 1000
    eq(acc:Result().market, 1000)
end)

test("accumulator: ignores bad rows, empty gives nil", function()
    local acc = P.NewAccumulator()
    acc:Add(0, 5)
    acc:Add(nil, 5)
    acc:Add(-3, 1)
    eq(acc:Result(), nil)
end)

test("store writes entry from accumulator result", function()
    local db = { prices = {} }
    local acc = P.NewAccumulator()
    acc:Add(50, 3)
    local e = P.Store(db, "R-A", 9, acc:Result(), 100, "scan")
    eq(e.market, 50)
    eq(e.qty, 3)
    eq(P.Get(db, "R-A", 9), e)
end)

-- Profit --------------------------------------------------------------------

test("ahNet applies 5% cut", function()
    eq(P.AhNet(10000), 9500)
    eq(P.AhNet(10000, { ahCut = 0.10 }), 9000)
end)

test("margin basic", function()
    -- market 20000 -> net 19000, vendor 10000 -> +90%
    local m = P.Margin(20000, 10000)
    assert(math.abs(m - 0.9) < 1e-9, tostring(m))
end)

test("margin: vendor 0 is unbounded, unknown vendor is nil", function()
    eq(P.Margin(5000, 0), math.huge)
    eq(P.Margin(5000, nil), nil)
    eq(P.Margin(nil, 100), nil)
end)

test("high margin: needs both margin and min profit", function()
    -- 2c vendor, 5c market: huge margin but tiny profit
    local ok = P.IsHighMargin(5, 2)
    eq(ok, false)
    -- 100s vendor, 200s market: net 190s, margin 90%, profit 90s
    local ok2, m, profit = P.IsHighMargin(20000, 10000)
    eq(ok2, true)
    eq(profit, 9000)
end)

test("high margin: 50% threshold boundary", function()
    -- vendor 10000, need net >= 15000 -> market 15790 gives net 15000 (floor 15000.5)
    local ok = P.IsHighMargin(15790, 10000)
    eq(ok, true)
    eq((P.IsHighMargin(15700, 10000)), false)
end)

test("high margin: vendor 0 flagged only if profit clears minimum", function()
    eq((P.IsHighMargin(100000, 0)), true)
    eq((P.IsHighMargin(500, 0)), false)
end)

test("high margin: respects custom threshold", function()
    eq((P.IsHighMargin(20000, 10000, { marginThreshold = 2.0 })), false)
    eq((P.IsHighMargin(20000, 10000, { marginThreshold = 0.2 })), true)
end)

test("high margin: no market data is never flagged", function()
    eq((P.IsHighMargin(nil, 100)), false)
    eq((P.IsHighMargin(0, 100)), false)
end)

-- Deposit -------------------------------------------------------------------

test("deposit: minimum applies to cheap items", function()
    eq(P.Deposit(100, 1), 100)
    eq(P.Deposit(0, 1), 100)
    eq(P.Deposit(nil, 20), 100)
end)

test("deposit: scales with vendor value, quantity and duration", function()
    eq(P.Deposit(10000, 1), 6000)                          -- 24h default = 60%
    eq(P.Deposit(10000, 2), 12000)
    eq(P.Deposit(10000, 1, { duration = 8 }), 2000)        -- assumed linear
    eq(P.Deposit(10000, 1, { duration = 2 }), 500)
end)

test("deposit: matches real values read from the live AH", function()
    local function dep(vendor, qty, hours) return P.Deposit(vendor, qty, { duration = hours }) end
    -- Small Red Pouch, vendor 250: 2h and 8h show the 100c minimum, 24h shows 150c
    eq(dep(250, 1, 2), 100); eq(dep(250, 1, 8), 100); eq(dep(250, 1, 24), 150)
    -- Linen Bandage, vendor 10 x 17
    eq(dep(10, 17, 2), 100); eq(dep(10, 17, 8), 100); eq(dep(10, 17, 24), 102)
    -- Scroll of Imbue Lesser Flame, vendor 75 x 4
    eq(dep(75, 4, 24), 180)
    -- vendor price 0 items still pay the minimum
    eq(dep(0, 1, 24), 100)
    -- minimum is per listing, not per unit
    eq(dep(10, 1, 8), dep(10, 17, 8))
end)

test("deposit: extra cost lowers margin and profit", function()
    local m0 = P.Margin(20000, 10000)
    local m1 = P.Margin(20000, 10000, nil, 2000)
    assert(m1 < m0)
    eq(P.Profit(20000, 10000, nil, 2000), 19000 - 10000 - 2000)
    eq((P.IsHighMargin(20000, 10000, nil, 5000)), false)  -- 14000 net: +40%, under 50%
end)

test("margin: vendor 0 with deposit larger than the sale is not unbounded", function()
    eq(P.Margin(100, 0, nil, 500), 0)
    eq(P.Margin(100000, 0, nil, 500), math.huge)
end)

-- Suggested price -----------------------------------------------------------

test("suggest: undercut default = larger of 1c or 1%", function()
    eq((P.SuggestPrice(100000, 120000, 1000)), 99000)   -- 1% = 1000c
    eq((P.SuggestPrice(500, 600, 100)), 495)            -- 1% = 5c beats 1c
end)

test("suggest: undercut small price uses 1 copper", function()
    -- lowest 50: 1% floors to 0, so 1c undercut -> 49, floor is max(ceil(10*1.05)=11, 1)
    eq((P.SuggestPrice(50, 60, 10)), 49)
end)

test("suggest: never below vendor floor", function()
    local price, note = P.SuggestPrice(1000, 1000, 1000)
    eq(price, 1050)
    eq(note, "floor")
end)

test("suggest: no data", function()
    local price, note = P.SuggestPrice(nil, nil, 100)
    eq(price, nil)
    eq(note, "nodata")
end)

test("suggest: match and percent strategies", function()
    eq((P.SuggestPrice(900, 1000, 100, { strategy = "match" })), 1000)
    eq((P.SuggestPrice(900, 1000, 100, { strategy = "percent", percentOfMarket = 95 })), 950)
end)

test("suggest: undercut falls back to market when lowest unknown", function()
    eq((P.SuggestPrice(nil, 10000, 100, { undercutMode = "copper" })), 9999)
end)

test("suggest: vendor 0 uses minimum listing price floor", function()
    eq((P.SuggestPrice(1, 1, 0, { undercutMode = "copper" })), 1)
end)

-- Staleness / formatting ----------------------------------------------------

test("age strings", function()
    eq(P.AgeString(1000, 1030), "just now")
    eq(P.AgeString(1000, 1000 + 120), "2m ago")
    eq(P.AgeString(1000, 1000 + 7200), "2h ago")
    eq(P.AgeString(1000, 1000 + 86400 * 3), "3d ago")
    eq(P.AgeString(nil, 5), "never")
end)

test("stale after 24h", function()
    eq(P.IsStale(0, 86400), false)
    eq(P.IsStale(0, 86401), true)
    eq(P.IsStale(nil, 100), true)
end)

test("format money", function()
    eq(P.FormatMoney(0), "0c")
    eq(P.FormatMoney(5), "5c")
    eq(P.FormatMoney(12 * 10000 + 34 * 100 + 56), "12g 34s 56c")
    eq(P.FormatMoney(10000), "1g")
    eq(P.FormatMoney(-150), "-1s 50c")
end)

-- DB ------------------------------------------------------------------------

test("update stores market, low, count", function()
    local db = { prices = {} }
    local e = P.Update(db, "R-A", 123, { 300, 100, 200, 400 }, 40, 5000, "search")
    eq(e.market, 100)
    eq(e.low, 100)
    eq(e.count, 4)
    eq(e.qty, 40)
    eq(P.Get(db, "R-A", 123), e)
end)

test("update with no usable listings stores nothing", function()
    local db = { prices = {} }
    eq(P.Update(db, "R-A", 1, {}, 0, 1), nil)
    eq(P.Get(db, "R-A", 1), nil)
end)

test("prune removes only old entries", function()
    local now = 100 * 86400
    local db = { prices = { r = {
        [1] = { t = now - 15 * 86400 },
        [2] = { t = now - 2 * 86400 },
        [3] = {},
    } } }
    eq(P.Prune(db, now, 14), 2)
    eq(db.prices.r[1], nil)
    assert(db.prices.r[2] ~= nil)
end)

test("realm key", function()
    eq(P.MakeRealmKey("Foo", "Horde"), "Foo-Horde")
    eq(P.MakeRealmKey(nil, nil), "?-Neutral")
end)

test("money: icon format uses the coin textures", function()
    local s = AA.Prices.FormatMoneyIcons(12 * 10000 + 34 * 100 + 56)
    assert(s:find("12|T", 1, true), s)
    assert(s:find("34|T", 1, true), s)
    assert(s:find("56|T", 1, true), s)
    assert(s:find("UI-GoldIcon", 1, true) and s:find("UI-SilverIcon", 1, true) and s:find("UI-CopperIcon", 1, true))
    assert(AA.Prices.FormatMoneyIcons(100):find("1|T", 1, true))
    assert(not AA.Prices.FormatMoneyIcons(100):find("UI-GoldIcon", 1, true))   -- no gold part
    assert(AA.Prices.FormatMoneyIcons(0):find("0|T", 1, true))
    assert(AA.Prices.FormatMoneyIcons(-150):sub(1, 1) == "-")
    eq(AA.Prices.FormatMoneyIcons(nil), "?")
end)
