local A, P = AA.Alerts, AA.Prices
local NOW = 100000

local function group(id, count, vendor, market)
    return {
        itemID = id, link = "L" .. id, name = "Item" .. id, count = count, vendor = vendor,
        eval = P.Evaluate(market and { market = market, t = NOW - 30 } or nil, vendor, count, NOW),
    }
end

local function ctx() return { marks = {}, ignore = {}, delta = 0.25 } end

test("alerts: flags a high-margin item, ignores no-data and low-margin ones", function()
    local good = group(1, 1, 1000, 50000)
    local nodata = group(2, 1, 1000, nil)
    local meh = group(3, 1, 1000, 1500)
    eq(A.ShouldFlag(good, ctx()), true)
    local ok, why = A.ShouldFlag(nodata, ctx()); eq(ok, false); eq(why, "nodata")
    ok, why = A.ShouldFlag(meh, ctx()); eq(ok, false); eq(why, "notworth")
end)

test("alerts: ignored and already-marked items are never flagged", function()
    local g = group(1, 1, 1000, 50000)
    local c = ctx(); c.ignore[1] = true
    local ok, why = A.ShouldFlag(g, c); eq(ok, false); eq(why, "ignored")
    c = ctx(); c.marks[1] = "vendor"
    ok, why = A.ShouldFlag(g, c); eq(ok, false); eq(why, "marked")
end)

test("alerts: de-duplicates unless the price moved by more than the delta", function()
    local c = ctx(); c.seen = { [1] = 50000 }
    local ok, why = A.ShouldFlag(group(1, 1, 1000, 52000), c); eq(ok, false); eq(why, "seen")
    eq(A.ShouldFlag(group(1, 1, 1000, 80000), c), true)    -- +60%
end)

test("alerts: process flags gained items once and records the price", function()
    local st = A.NewState()
    local groups = { group(1, 2, 1000, 50000), group(2, 1, 1000, 1500) }
    local newly = A.Process(st, groups, { { itemID = 1, delta = 1 }, { itemID = 2, delta = 1 } }, ctx())
    eq(#newly, 1); eq(newly[1].itemID, 1)
    eq(A.Count(st), 1)
    eq(st.seen[1], 50000)
    -- the same item gained again while still flagged does not re-flag
    eq(#A.Process(st, groups, { { itemID = 1, delta = 1 } }, ctx()), 0)
    -- items not in the sellable groups (bound, quest) are skipped
    eq(#A.Process(A.NewState(), groups, { { itemID = 99, delta = 1 } }, ctx()), 0)
end)

test("alerts: prune drops items that left the bags, got marked or ignored", function()
    local st = A.NewState()
    A.Process(st, { group(1, 1, 1000, 50000), group(2, 1, 1000, 50000), group(3, 1, 1000, 50000) },
        { { itemID = 1 }, { itemID = 2 }, { itemID = 3 } }, ctx())
    eq(A.Count(st), 3)
    local n = A.Prune(st, { [1] = true, [2] = true }, { [2] = "auction" }, nil)   -- 3 left bags, 2 marked
    eq(n, 2); eq(A.Count(st), 1)
    eq(A.List(st)[1].itemID, 1)
end)

test("alerts: message text", function()
    local m = A.Message({ link = "L", count = 3, market = 20000, vendor = 5000, margin = 2.5 })
    assert(m:find("L x3", 1, true), m)
    assert(m:find("+250%", 1, true), m)
    assert(A.Message({ name = "N", count = 1, market = 100, vendor = 0, margin = math.huge }):find("no vendor value"))
end)
