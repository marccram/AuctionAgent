-- Plain-Lua test runner. Run from the project root:  luajit tests/run.lua
-- Loads addon modules the way WoW does: each file is called with (addonName, sharedTable).

local ns = {}
local function load(path)
    local f = assert(loadfile(path))
    f("AuctionAgent", ns)
end
load("AuctionAgent/Locales/enUS.lua")
load("AuctionAgent/Compat.lua")
load("AuctionAgent/Prices.lua")
load("AuctionAgent/Options.lua")
load("AuctionAgent/Bags.lua")
load("AuctionAgent/Marks.lua")
load("AuctionAgent/Scanner.lua")
load("AuctionAgent/Tooltip.lua")
load("AuctionAgent/Sell.lua")
load("AuctionAgent/Alerts.lua")
load("AuctionAgent/Onboarding.lua")

local passed, failed = 0, 0
function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL  " .. name .. "\n      " .. tostring(err))
    end
end

function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

AA = ns
dofile("tests/test_defaults.lua")
-- The remaining pure-logic tests were written against an undercut / 24h setup; pin those so
-- they keep testing the logic itself while test_defaults.lua covers what actually ships.
AA.Prices.DEFAULTS.strategy = "undercut"
AA.Prices.DEFAULTS.duration = 24
dofile("tests/test_prices.lua")
dofile("tests/test_compat.lua")
dofile("tests/test_bags.lua")
dofile("tests/test_tooltip.lua")
dofile("tests/test_sell.lua")
dofile("tests/test_marks.lua")
dofile("tests/test_alerts.lua")
dofile("tests/test_options.lua")
dofile("tests/test_onboarding.lua")
dofile("tests/test_scanner.lua")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
