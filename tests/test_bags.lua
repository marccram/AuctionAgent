local B, P = AA.Bags, AA.Prices

test("diff: reports only increases", function()
    local gained = B.Diff({ [1] = 5, [2] = 3, [3] = 1 }, { [1] = 8, [2] = 3, [4] = 2 })
    eq(#gained, 2)
    eq(gained[1].itemID, 1)
    eq(gained[1].delta, 3)
    eq(gained[2].itemID, 4)
    eq(gained[2].delta, 2)
end)

test("diff: nothing gained when items only leave", function()
    eq(#B.Diff({ [1] = 5 }, { [1] = 2 }), 0)
    eq(#B.Diff({ [1] = 5 }, {}), 0)
end)

test("sellable: bound, locked, ignored, quest are excluded with reasons", function()
    local ok, why = B.Sellable({ itemID = 1, bound = true })
    eq(ok, false); eq(why, "bound")
    ok, why = B.Sellable({ itemID = 1, locked = true })
    eq(ok, false); eq(why, "locked")
    ok, why = B.Sellable({ itemID = 7 }, { [7] = true })
    eq(ok, false); eq(why, "ignored")
    ok, why = B.Sellable({ itemID = 1 }, nil, 12)
    eq(ok, false); eq(why, "quest")
    eq((B.Sellable({ itemID = 1 }, {}, 0)), true)
end)

-- Evaluate -------------------------------------------------------------------

test("evaluate: no entry means nodata", function()
    eq(P.Evaluate(nil, 100, 1, 1000).state, "nodata")
end)

test("evaluate: entry without market means nolistings", function()
    local r = P.Evaluate({ count = 0, t = 940 }, 100, 1, 1000)
    eq(r.state, "nolistings")
    eq(r.age, "1m ago")
end)

test("evaluate: cheap item, minimum deposit swamps the sale -> vendor it", function()
    -- market 19c vs vendor 3c x5: raw margin is large, but the 1s minimum deposit costs
    -- far more than the whole stack is worth.
    local r = P.Evaluate({ market = 19, low = 19, t = 1000 }, 3, 5, 1000)
    eq(r.state, "ok")
    eq(r.high, false)
    eq(r.rec, "vendor")
    eq(r.marketTotal, 95)
    eq(r.deposit, 100)
end)

test("evaluate: low-level enchanting wand (vendor 1s, AH 1s 50c) is not worth listing", function()
    -- the example from play: vendors for 1s, deposit is 1s
    local r = P.Evaluate({ market = 150, t = 1000 }, 100, 1, 1000)
    eq(r.deposit, 100)
    eq(r.rec, "vendor")
    eq(r.high, false)
    assert(r.profit < 0)
end)

test("evaluate: depositWeight 0 ignores the deposit", function()
    local r = P.Evaluate({ market = 150, t = 1000 }, 100, 1, 1000, { depositWeight = 0 })
    eq(r.profit, 42)   -- 142 net - 100 vendor
end)

test("evaluate: worth auctioning", function()
    -- deposit for 2 x 10000c vendor at 24h = 12000, weighted 1 -> 6000 per unit
    local r = P.Evaluate({ market = 50000, low = 48000, t = 1000 }, 10000, 2, 1000)
    eq(r.high, true)
    eq(r.rec, "auction")
    eq(r.profitTotal, (47500 - 6000 - 10000) * 2)
end)

test("evaluate: vendor it when AH net does not beat vendor", function()
    local r = P.Evaluate({ market = 10000, t = 1000 }, 10000, 1, 1000)
    eq(r.rec, "vendor")
end)

test("evaluate: unknown vendor price never recommends", function()
    local r = P.Evaluate({ market = 50000, t = 1000 }, nil, 1, 1000)
    eq(r.rec, nil)
    eq(r.margin, nil)
end)

test("evaluate: stale flag after 24h", function()
    eq(P.Evaluate({ market = 5, t = 0 }, 1, 1, 86401).stale, true)
    eq(P.Evaluate({ market = 5, t = 0 }, 1, 1, 100).stale, false)
end)
