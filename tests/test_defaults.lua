-- The shipped defaults. The pure-logic tests that follow pin their own settings (see run.lua).
local P = AA.Prices

test("defaults: shipped pricing defaults", function()
    eq(P.DEFAULTS.strategy, "match")
    eq(P.DEFAULTS.duration, 8)
    eq(P.DEFAULTS.marginThreshold, 0.5)
end)

test("defaults: match strategy suggests the market value; 8h deposit is a fifth of vendor value", function()
    eq(P.SuggestPrice(990, 1000, 100), 1000)
    eq(P.Deposit(10000, 1), 2000)    -- 8h = 20% (assumed linear from the measured 24h = 60%)
end)
