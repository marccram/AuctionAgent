local Ob = AA.Onboarding

test("onboarding: asks for a full scan until one is done or declined", function()
    eq(Ob.WantsFullScan({ onboarding = {} }), true)
    eq(Ob.WantsFullScan({ onboarding = {}, fullScanAt = 123 }), false)
    eq(Ob.WantsFullScan({ onboarding = { noFullScanPrompt = true } }), false)
    eq(Ob.WantsFullScan({}), true)          -- no onboarding table yet
    eq(Ob.WantsFullScan(nil), false)
end)

test("onboarding: mark hint follows the settings", function()
    eq(Ob.MarkHint({ markModifier = "alt", markButton = "LeftButton" }), "Alt + left-click")
    eq(Ob.MarkHint({ markModifier = "ctrl+shift", markButton = "RightButton" }), "Ctrl + Shift + right-click")
    eq(Ob.MarkHint(nil), "Alt + left-click")
    eq(Ob.MarkHint({ markModifier = "", markButton = "LeftButton" }), "Alt + left-click")
end)
