local S, P = AA.Sell, AA.Prices

local NOW = 100000

local function group(id, name, count, vendor)
    return { itemID = id, name = name, quality = 1, count = count, vendor = vendor, slots = { { bag = 0, slot = id } } }
end

local function entry(market, low) return { market = market, low = low or market, t = NOW - 60, count = 5, qty = 5 } end

test("row: commodity lists the whole stack at a per-unit suggested price", function()
    local r = S.BuildRow(group(1, "Linen Cloth", 20, 50), entry(1000, 990), NOW, nil, true)
    eq(r.commodity, true)
    eq(r.listQty, 20)
    eq(r.suggested, 981)            -- lowest 990 undercut by the larger of 1c or 1% (9c)
    eq(r.listingValue, 981 * 20)
    eq(r.state, "ok")
    assert(r.deposit >= 100)
end)

test("row: regular item is a single listing regardless of bag count", function()
    local r = S.BuildRow(group(2, "Green Sword", 3, 1000), entry(50000), NOW, nil, false)
    eq(r.listQty, 1)
    eq(r.commodity, false)
    eq(r.listingValue, r.suggested)
end)

test("row: profit is evaluated at the suggested price, net of deposit", function()
    local r = S.BuildRow(group(3, "Thing", 1, 10000), entry(50000, 50000), NOW, nil, false)
    -- suggested = 50000 - 1% (500) = 49500; net 47025; deposit 6000 (60% at 24h); vendor 10000
    eq(r.suggested, 49500)
    eq(r.eval.profitTotal, 47025 - 6000 - 10000)
    eq(r.eval.high, true)
end)

test("row: no data and no listings rows have no suggested price", function()
    local a = S.BuildRow(group(4, "A", 1, 100), nil, NOW, nil, false)
    eq(a.state, "nodata"); eq(a.suggested, nil); eq(a.eval, nil)
    local b = S.BuildRow(group(5, "B", 1, 100), { count = 0, t = NOW - 5 }, NOW, nil, false)
    eq(b.state, "nolistings"); eq(b.suggested, nil)
end)

test("row: price below vendor floor is flagged as floor", function()
    local r = S.BuildRow(group(6, "Junk", 1, 1000), entry(900), NOW, nil, false)
    eq(r.note, "floor")
    eq(r.suggested, 1050)
end)

local function sampleRows()
    return {
        S.BuildRow(group(10, "Bravo", 1, 10000), entry(50000), NOW, nil, false),   -- high profit
        S.BuildRow(group(11, "Alpha", 1, 100), nil, NOW, nil, false),               -- no data
        S.BuildRow(group(12, "Charlie", 1, 10000), entry(9000), NOW, nil, false),   -- floor, bad
        S.BuildRow(group(13, "Delta", 1, 5000), entry(30000), NOW, nil, false),     -- decent
    }
end

test("sort: default profit descending, rows without data last", function()
    local rows = sampleRows()
    S.Sort(rows, "profit", true)
    eq(rows[1].name, "Bravo")
    eq(rows[4].name, "Alpha")
end)

test("sort: ascending flips order but still puts missing values last", function()
    local rows = sampleRows()
    S.Sort(rows, "profit", false)
    eq(rows[4].name, "Alpha")
    assert(rows[1].eval.profitTotal <= rows[2].eval.profitTotal)
end)

test("sort: by name both directions", function()
    local rows = sampleRows()
    S.Sort(rows, "name", false)
    eq(rows[1].name, "Alpha"); eq(rows[4].name, "Delta")
    S.Sort(rows, "name", true)
    eq(rows[1].name, "Delta")
end)

test("sort: unknown key falls back to profit", function()
    local rows = sampleRows()
    S.Sort(rows, "nonsense", true)
    eq(rows[1].name, "Bravo")
end)

test("filter: text is case-insensitive and literal", function()
    local rows = sampleRows()
    eq(#S.Filter(rows, { text = "ALP" }), 1)
    eq(#S.Filter(rows, { text = "" }), 4)
    eq(#S.Filter(rows, { text = "a.b" }), 0)   -- not a pattern
end)

test("filter: high margin only", function()
    local rows = S.Filter(sampleRows(), { highOnly = true })
    for _, r in ipairs(rows) do eq(r.eval.high, true) end
    assert(#rows >= 1)
end)

test("high margin rows exclude floor-priced and no-data rows", function()
    local rows = S.HighMarginRows(sampleRows())
    for _, r in ipairs(rows) do
        eq(r.note ~= "floor", true)
        eq(r.eval.high, true)
    end
end)

test("plan post: commodity vs item and duration mapping", function()
    local c = S.BuildRow(group(20, "Cloth", 15, 100), entry(5000), NOW, nil, true)
    local plan = S.PlanPost(c, { duration = 24 })
    eq(plan.commodity, true); eq(plan.quantity, 15); eq(plan.duration, 3); eq(plan.price, c.suggested)
    local i = S.BuildRow(group(21, "Sword", 1, 100), entry(5000), NOW, nil, false)
    local plan2 = S.PlanPost(i, { duration = 2 })
    eq(plan2.commodity, false); eq(plan2.quantity, 1); eq(plan2.duration, 1)
    eq(S.PlanPost(i, { duration = 8 }).duration, 2)
    eq(S.PlanPost(i, { duration = 99 }).duration, 3)   -- unknown duration falls back to 24h
end)

test("plan post: refuses rows without a price", function()
    local r = S.BuildRow(group(22, "Nothing", 1, 100), nil, NOW, nil, false)
    local plan, why = S.PlanPost(r, { duration = 24 })
    eq(plan, nil)
    eq(why, "no price data")
end)

test("marked: filter, marked-first ordering and post-all-marked selection", function()
    local rows = sampleRows()          -- Bravo, Alpha(no data), Charlie, Delta
    rows[3].mark = "auction"           -- Charlie (priced, floor)
    rows[2].mark = "auction"           -- Alpha: marked but no price data
    rows[4].mark = "vendor"            -- Delta
    eq(#S.Filter(rows, { markedOnly = true }), 3)
    local ordered = S.MarkedFirst(rows)
    eq(ordered[1].name, "Alpha"); eq(ordered[2].name, "Charlie")      -- keeps relative order
    eq(ordered[3].name, "Bravo"); eq(ordered[4].name, "Delta")
    local chosen, skipped = S.MarkedRows(rows)
    eq(#chosen, 1); eq(chosen[1].name, "Charlie")                     -- vendor-marked and unpriced excluded
    eq(skipped, 1)
end)
