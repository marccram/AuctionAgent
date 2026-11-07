local O = AA.Options

test("options: every schema entry is well formed", function()
    local seen = {}
    for _, e in ipairs(O.SCHEMA) do
        if not e.section then
            assert(e.key and e.label and e.tip and e.type, "incomplete entry: " .. tostring(e.key))
            assert(not seen[e.key], "duplicate key " .. e.key)
            seen[e.key] = true
            if e.type == "choice" then assert(e.choices and #e.choices >= 2, e.key) end
            if e.type == "number" or e.type == "money" then assert(e.min and e.max and e.min <= e.max, e.key) end
        end
    end
end)

test("options: money text and parsing", function()
    eq(O.MoneyText(0), "0c"); eq(O.MoneyText(5), "5c"); eq(O.MoneyText(12345), "1g 23s 45c")
    eq(O.MoneyText(10000), "1g")
    eq(O.ParseMoney("1g 20s 5c"), 12005)
    eq(O.ParseMoney("20s"), 2000)
    eq(O.ParseMoney("150"), 150)
    eq(O.ParseMoney("1,000"), 1000)
    eq(O.ParseMoney("2G"), 20000)
    eq(O.ParseMoney("abc"), nil)
    eq(O.ParseMoney("5x"), nil)
    eq(O.ParseMoney(""), nil)
    eq(O.ParseMoney("-5"), nil)
end)

test("options: percent entries are typed as percent and stored as fractions", function()
    local e = O.Find("marginThreshold")
    eq(O.Parse(e, "60%"), 0.6)
    eq(O.Parse(e, " 25 "), 0.25)
    eq(O.Parse(e, "5000"), 10)        -- clamped to max (1000%)
    eq(O.Parse(e, "nonsense"), nil)
    eq(O.Format(e, 0.5), "50")
    eq(O.Format(e, 0.125), "12.5")
end)

test("options: hours entry converts to seconds", function()
    local e = O.Find("staleSeconds")
    eq(O.Parse(e, "24"), 86400)
    eq(O.Format(e, 86400), "24")
    eq(O.Parse(e, "0"), 3600)         -- clamped to the 1 hour minimum
end)

test("options: integer entries round and clamp", function()
    local e = O.Find("outlierMax")
    eq(O.Parse(e, "7.6"), 8)
    eq(O.Parse(e, "0"), 1)
    eq(O.Parse(e, "5000"), 100)
end)

test("options: money entries clamp to their range", function()
    local e = O.Find("minListingPrice")
    eq(O.Parse(e, "0"), 1)            -- never below 1 copper
    eq(O.Parse(e, "2s"), 200)
end)

test("options: choices cycle and wrap", function()
    local e = O.Find("duration")
    eq(O.NextChoice(e, 2), 8); eq(O.NextChoice(e, 8), 24); eq(O.NextChoice(e, 24), 2)
    eq(O.NextChoice(e, 12), 2)        -- legacy value goes to the first choice
    eq(O.ChoiceLabel(e, 24), "24 hours")
    eq(O.ChoiceLabel(e, 99), "99")
end)
