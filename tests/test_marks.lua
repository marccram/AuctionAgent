local M = AA.Marks

test("marks: set, get and clear", function()
    local db = {}
    eq(M.Get(db, 5), nil)
    eq(M.Set(db, 5, "vendor"), true)
    eq(M.Get(db, 5), "vendor")
    eq(M.Set(db, 5, nil), true)
    eq(M.Get(db, 5), nil)
    eq(M.Set(db, 5, "bogus"), false)
    eq(M.Get(db, 5), nil)
end)

test("marks: cycle goes auction, vendor, none", function()
    eq(M.Cycle(nil), "auction")
    eq(M.Cycle("auction"), "vendor")
    eq(M.Cycle("vendor"), nil)
end)

test("marks: soulbound items skip the auction mark", function()
    eq(M.Cycle(nil, true), "vendor")
    eq(M.Cycle("vendor", true), nil)
    eq(M.Cycle("auction", true), nil)   -- a stale auction mark on a bound item just clears
end)

test("marks: slash words", function()
    eq(M.ParseKind("Auction"), "auction"); eq(M.ParseKind("ah"), "auction")
    eq(M.ParseKind("vendor"), "vendor"); eq(M.ParseKind("v"), "vendor")
    eq(M.ParseKind("clear"), "clear"); eq(M.ParseKind("zzz"), nil); eq(M.ParseKind(nil), nil)
end)

test("marks: modifier matching is exact and never matches a plain click", function()
    eq(M.ModifierMatches("alt", true, false, false), true)
    eq(M.ModifierMatches("alt", true, true, false), false)    -- extra modifier held
    eq(M.ModifierMatches("alt", false, false, false), false)
    eq(M.ModifierMatches("ALT+CTRL", true, true, false), true)
    eq(M.ModifierMatches("alt+ctrl", true, false, false), false)
    eq(M.ModifierMatches("", false, false, false), false)     -- bad setting must not mark every click
    eq(M.ModifierMatches("nonsense", false, false, false), false)
    eq(M.ModifierMatches(nil, false, false, false), false)
end)

test("marks: button normalizing", function()
    eq(M.NormalizeButton("RightButton"), "RightButton")
    eq(M.NormalizeButton("right"), "RightButton")
    eq(M.NormalizeButton("LeftButton"), "LeftButton")
    eq(M.NormalizeButton(nil), "LeftButton")
end)

test("marks: prune drops items no longer present", function()
    local db = { marks = { [1] = "vendor", [2] = "auction", [3] = "vendor" } }
    eq(M.Prune(db, { [2] = true }), 2)
    eq(M.Get(db, 1), nil); eq(M.Get(db, 3), nil); eq(M.Get(db, 2), "auction")
    eq(M.Prune({}, {}), 0)
end)

test("marks: counts", function()
    local c = M.Counts({ marks = { [1] = "vendor", [2] = "auction", [3] = "vendor" } })
    eq(c.vendor, 2); eq(c.auction, 1)
    eq(M.Counts(nil).vendor, 0)
end)

local function e(bag, slot, id, count, extra)
    local t = { bag = bag, slot = slot, itemID = id, count = count, link = "link" .. id, name = "n" .. id }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

test("vendor plan: only vendor-marked, unlocked stacks with a known price", function()
    local entries = {
        e(0, 1, 10, 5),                        -- marked vendor, 5 x 20
        e(0, 2, 11, 1),                        -- marked auction: never sold
        e(0, 3, 12, 1),                        -- unmarked: never sold
        e(0, 4, 10, 3),                        -- second stack of 10
        e(0, 5, 13, 1, { locked = true }),     -- marked vendor but locked
        e(0, 6, 14, 1, { noValue = true }),    -- marked vendor but cannot be sold
        e(0, 7, 15, 2),                        -- marked vendor, price not loaded yet
        e(0, 8, 16, 2),                        -- marked vendor, vendor price 0
    }
    local marks = { [10] = "vendor", [11] = "auction", [13] = "vendor", [14] = "vendor",
        [15] = "vendor", [16] = "vendor" }
    local prices = { [10] = 20, [16] = 0 }
    local plan, total, unknown = M.VendorPlan(entries, marks, function(id) return prices[id] end)
    eq(#plan, 2)
    eq(plan[1].value, 100); eq(plan[2].value, 60)
    eq(total, 160)
    eq(unknown, 1)
    eq(plan[1].bag, 0); eq(plan[1].slot, 1)
end)
