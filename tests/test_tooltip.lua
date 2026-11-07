local T, P = AA.Tooltip, AA.Prices

local function eval(entry, vendor, qty)
    return P.Evaluate(entry, vendor, qty, 1000)
end

test("tooltip: nodata shows hint in full mode only", function()
    eq(#T.BuildLines(eval(nil, 5), "full"), 1)
    eq(T.BuildLines(eval(nil, 5), "full")[1][1], "No AH data yet")
    eq(#T.BuildLines(eval(nil, 5), "compact"), 0)
end)

test("tooltip: full mode shows value row then recommendation", function()
    local lines = T.BuildLines(eval({ market = 50000, t = 1000 }, 10000, 1), "full")
    eq(#lines, 3)
    assert(lines[1][1]:find("AH value"))
    assert(lines[2][1]:find("deposit"))
    assert(lines[3][1]:find("Worth auctioning"))
end)

test("tooltip: stack shows per-unit and total, labeled", function()
    local lines = T.BuildLines(eval({ market = 500, t = 1000 }, 100, 5), "full")
    assert(lines[1][2]:find("ea"), lines[1][2])
    assert(lines[1][2]:find("x5"), lines[1][2])
end)

test("tooltip: compact mode omits the price row (no duplicates with Auctionator)", function()
    local lines = T.BuildLines(eval({ market = 50000, t = 1000 }, 10000, 1), "compact")
    eq(#lines, 1)
    assert(lines[1][1]:find("Worth auctioning"))
end)

test("tooltip: compact marginal item still shows margin", function()
    local lines = T.BuildLines(eval({ market = 22000, t = 1000 }, 10000, 1), "compact")
    eq(#lines, 1)
    assert(lines[1][1]:find("AH vs vendor"), lines[1][1])
end)

test("tooltip: soulbound items get no recommendation", function()
    local lines = T.BuildLines(eval({ market = 50000, t = 1000 }, 10000, 1), "full", true)
    eq(#lines, 1)
    assert(lines[1][1]:find("AH value"))
end)

test("tooltip: vendor hint", function()
    local lines = T.BuildLines(eval({ market = 10000, t = 1000 }, 10000, 1), "full")
    eq(lines[3][1], "Vendor it")
end)

test("tooltip: no listings", function()
    local lines = T.BuildLines(eval({ count = 0, t = 1000 }, 10000, 1), "full")
    assert(lines[1][1]:find("No listings"))
end)

test("tooltip: effective mode off without settings", function()
    AA.settings = nil
    eq(T.EffectiveMode(), "off")
end)

test("tooltip mode: compact only when Auctionator already has a price", function()
    local s = { tooltipMode = "full", autoCompact = true }
    eq(T.ChooseMode(s, true), "compact")
    eq(T.ChooseMode(s, false), "full")          -- Auctionator says Unknown: show our own price
    eq(T.ChooseMode({ tooltipMode = "full", autoCompact = false }, true), "full")
    eq(T.ChooseMode({ tooltipMode = "off", autoCompact = true }, true), "off")
    eq(T.ChooseMode({ tooltipMode = "compact" }, false), "compact")
    eq(T.ChooseMode(nil, true), "off")
end)
