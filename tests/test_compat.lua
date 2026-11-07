local C = AA.Compat

test("SafeNumber accepts plain numbers only", function()
    eq(C.SafeNumber(5), 5)
    eq(C.SafeNumber("5"), nil)
    eq(C.SafeNumber(nil), nil)
    eq(C.SafeNumber(0 / 0), nil)
    eq(C.SafeNumber(math.huge), nil)
end)

test("SafeNumber rejects values flagged secret", function()
    local saved = _G.issecretvalue
    _G.issecretvalue = function(v) return v == 42 end
    eq(C.SafeNumber(42), nil)
    eq(C.SafeNumber(41), 41)
    _G.issecretvalue = saved
end)

test("Resolve walks dotted paths and tolerates absence", function()
    _G.FakeNS = { fn = function() return 7 end }
    eq(type(C.Resolve("FakeNS.fn")), "function")
    eq(C.Resolve("FakeNS.nope"), nil)
    eq(C.Resolve("Missing.thing.deep"), nil)
    local ok, v = C.Call("FakeNS.fn")
    eq(ok, true)
    eq(v, 7)
    local ok2 = C.Call("FakeNS.nope")
    eq(ok2, false)
    _G.FakeNS = nil
end)
