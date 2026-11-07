local S = AA.Scanner

test("scanner progress: full scan waiting has no fraction", function()
    local text, frac = S.ProgressInfo({ kind = "full", phase = "waiting" })
    assert(text:find("Requesting the auction list", 1, true), text)
    eq(frac, nil)
end)

test("scanner progress: full scan processing reports percent", function()
    local text, frac = S.ProgressInfo({ kind = "full", phase = "processing", done = 25000, total = 100000 })
    assert(text:find("25%", 1, true), text)
    eq(frac, 0.25)
    local _, zero = S.ProgressInfo({ kind = "full", phase = "processing", done = 0, total = 0 })
    eq(zero, 0)
end)

test("scanner progress: bag scan reports items done of total", function()
    local text, frac = S.ProgressInfo({ kind = "bags", phase = "querying", done = 7, total = 23 })
    assert(text:find("7/23", 1, true), text)
    assert(math.abs(frac - 7 / 23) < 1e-9)
end)

test("scanner progress: no scan, no info", function()
    eq(S.ProgressInfo(nil), nil)
end)
