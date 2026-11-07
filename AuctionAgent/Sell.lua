local ADDON, AA = ...

-- Sell model: turns bag groups + price data into rows (suggested price, profit net of
-- deposit), sorting, filtering, and the posting workflow. The UI lives in UI_SellPanel.lua.
-- BuildRow / Sort / Filter / PlanPost are pure and tested outside the game.

local C, P = AA.Compat, AA.Prices
local S = {}
AA.Sell = S

-- PostItem/PostCommodity duration arg. Verified in game: the dropdown offers 2, 8 and 24
-- hours (enum 1/2/3). Old 12 and 48 settings are mapped to the nearest option.
local DURATION_ENUM = { [2] = 1, [8] = 2, [12] = 2, [24] = 3, [48] = 3 }

local function say(msg) AA.Print(msg) end

---------------------------------------------------------------------------
-- Commodity or single-item listing?
---------------------------------------------------------------------------

local commodityCache = {}

-- True = commodity (priced per unit, whole stack in one listing), false = regular item.
-- Uses the AH's own answer (GetItemCommodityStatus: 1 item, 2 commodity); until that is
-- available it guesses from stack size without caching.
function S.IsCommodity(g)
    local cached = commodityCache[g.itemID]
    if cached ~= nil then return cached end
    local slot = g.slots and g.slots[1]
    if slot and ItemLocation then
        local ok, status = C.Call("C_AuctionHouse.GetItemCommodityStatus",
            ItemLocation:CreateFromBagAndSlot(slot.bag, slot.slot))
        status = ok and C.SafeNumber(status) or nil
        if status == 2 then commodityCache[g.itemID] = true return true end
        if status == 1 then commodityCache[g.itemID] = false return false end
    end
    return (g.count or 1) > 1
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- g: group from Bags.Summarize. entry: price DB entry or nil. commodity: boolean.
-- Profit/margin are evaluated at the SUGGESTED price (what you would actually post),
-- net of the deposit for one listing.
function S.BuildRow(g, entry, now, s, commodity)
    local listQty = commodity and g.count or 1
    local row = {
        itemID = g.itemID, link = g.link, name = g.name or ("item " .. g.itemID),
        quality = g.quality, icon = g.icon, count = g.count, slots = g.slots,
        vendor = g.vendor, commodity = commodity and true or false, listQty = listQty,
        entry = entry, market = entry and entry.market, low = entry and entry.low,
        t = entry and entry.t,
    }
    local base = P.Evaluate(entry, g.vendor, listQty, now, s)
    row.state, row.age, row.stale = base.state, base.age, base.stale
    if row.market then
        row.suggested, row.note = P.SuggestPrice(row.low, row.market, g.vendor, s)
        if row.suggested then
            row.eval = P.Evaluate({ market = row.suggested, low = row.suggested, t = entry.t },
                g.vendor, listQty, now, s)
            row.listingValue = row.suggested * listQty
            row.deposit = row.eval.deposit
        end
    end
    return row
end

function S.Rows()
    local now, s, db, rk = time(), AA.settings, AA.db, AA.RealmKey()
    local rows = {}
    for _, g in ipairs(AA.Bags.Summarize()) do
        local row = S.BuildRow(g, P.Get(db, rk, g.itemID), now, s, S.IsCommodity(g))
        row.mark = AA.Marks and AA.Marks.Get(db, g.itemID) or nil
        rows[#rows + 1] = row
    end
    return rows
end

local KEYS = {
    name = function(r) return r.name:lower() end,
    qty = function(r) return r.count end,
    vendor = function(r) return r.vendor end,
    market = function(r) return r.market end,
    suggested = function(r) return r.suggested end,
    profit = function(r) return r.eval and r.eval.profitTotal end,
    margin = function(r) return r.eval and r.eval.margin end,
    age = function(r) return r.t end,   -- larger = fresher
}

-- Sorts in place. Rows missing the sort value always go last; ties break by name.
function S.Sort(rows, key, desc)
    local f = KEYS[key] or KEYS.profit
    table.sort(rows, function(a, b)
        local va, vb = f(a), f(b)
        if va == nil and vb == nil then return a.name:lower() < b.name:lower() end
        if va == nil then return false end
        if vb == nil then return true end
        if va == vb then return a.name:lower() < b.name:lower() end
        if desc then return va > vb end
        return va < vb
    end)
end

-- opts: { text = "substring", highOnly = bool, markedOnly = bool }
function S.Filter(rows, opts)
    local text = (opts and opts.text or ""):lower()
    local out = {}
    for _, r in ipairs(rows) do
        local nameOk = text == "" or r.name:lower():find(text, 1, true) ~= nil
        local highOk = not (opts and opts.highOnly) or (r.eval ~= nil and r.eval.high == true)
        local markOk = not (opts and opts.markedOnly) or r.mark ~= nil
        if nameOk and highOk and markOk then out[#out + 1] = r end
    end
    return out
end

-- Stable: rows marked for auction first, everything else keeps its order.
function S.MarkedFirst(rows)
    local top, rest = {}, {}
    for _, r in ipairs(rows) do
        if r.mark == "auction" then top[#top + 1] = r else rest[#rest + 1] = r end
    end
    for _, r in ipairs(rest) do top[#top + 1] = r end
    return top
end

-- Rows for "Post all marked": marked for auction and priceable. Second result counts
-- marked rows skipped for lack of price data (scan first).
function S.MarkedRows(rows)
    local out, skipped = {}, 0
    for _, r in ipairs(rows) do
        if r.mark == "auction" then
            if r.suggested then out[#out + 1] = r else skipped = skipped + 1 end
        end
    end
    return out, skipped
end

-- Rows eligible for "Post all high-margin": flagged high, and not priced at the floor.
function S.HighMarginRows(rows)
    local out = {}
    for _, r in ipairs(rows) do
        if r.eval and r.eval.high and r.note ~= "floor" then out[#out + 1] = r end
    end
    return out
end

---------------------------------------------------------------------------
-- Posting (each call needs a hardware event, i.e. must run from a click)
---------------------------------------------------------------------------

-- Pure: what to send to the AH for a row. Commodities: whole stack, per-unit price.
-- Regular items: one item, buyout = price.
function S.PlanPost(row, s)
    if not row.suggested then return nil, "no price data" end
    return {
        commodity = row.commodity, itemID = row.itemID, quantity = row.listQty,
        price = row.suggested, duration = DURATION_ENUM[s.duration] or 3,
    }
end

local function locate(itemID)
    for _, e in ipairs(AA.Bags.Enumerate()) do
        if e.itemID == itemID and not e.bound and not e.locked then return e end
    end
end

function S.Post(row)
    local plan, why = S.PlanPost(row, AA.settings)
    if not plan then return false, why end
    local slot = locate(row.itemID)
    if not slot then return false, "item not in bags" end
    local loc = ItemLocation:CreateFromBagAndSlot(slot.bag, slot.slot)
    local ok, err
    if plan.commodity then
        ok, err = C.Call("C_AuctionHouse.PostCommodity", loc, plan.duration, plan.quantity, plan.price)
    else
        ok, err = C.Call("C_AuctionHouse.PostItem", loc, plan.duration, plan.quantity, nil, plan.price)
    end
    if not ok then return false, tostring(err) end
    return true, plan
end

S.queue = {}   -- itemIDs waiting to be posted, one per click

local function describe(row, plan)
    return ("%s x%d @ %s%s"):format(row.link or row.name, plan.quantity,
        P.FormatMoney(plan.price), plan.commodity and " ea" or "")
end

function S.PostRow(row)
    local ok, res = S.Post(row)
    if ok then
        say("Posting " .. describe(row, res))
    else
        say(("Could not post %s: %s"):format(row.name, tostring(res)))
    end
    AA.Fire("QUEUE_CHANGED")
    return ok
end

-- Posts the next queued item (re-reading bags, so stale rows cannot post the wrong thing).
function S.PostNext()
    while #S.queue > 0 do
        local id = table.remove(S.queue, 1)
        for _, row in ipairs(S.Rows()) do
            if row.itemID == id and row.suggested then
                return S.PostRow(row)
            end
        end
    end
    AA.Fire("QUEUE_CHANGED")
    return false
end

-- Experimental (setting batchPost): try the whole queue from one click.
function S.PostAll()
    local n = #S.queue
    for _ = 1, n do
        if not S.PostNext() then break end
    end
end

function S.StartQueue(rows)
    S.queue = {}
    for _, r in ipairs(rows) do S.queue[#S.queue + 1] = r.itemID end
    if AA.settings.batchPost then S.PostAll() else S.PostNext() end
end

function S.ConfirmPostAll(rows)
    local chosen = S.HighMarginRows(rows)
    if #chosen == 0 then say("Nothing is flagged as high margin right now.") return end
    S.ConfirmPost(chosen)
end

-- Confirmation dialog for any chosen set of rows (high-margin, marked, ...).
function S.ConfirmPost(chosen)
    local value, deposit = 0, 0
    for _, r in ipairs(chosen) do
        value = value + (r.listingValue or 0)
        deposit = deposit + (r.deposit or 0)
    end
    S.pending = chosen
    local text = ("Post %d listings?\nTotal listing value: %s\nTotal deposit: %s\n\n%s"):format(
        #chosen, P.FormatMoney(value), P.FormatMoney(deposit),
        AA.settings.batchPost and "Experimental: trying to post all at once."
            or "The first posts now; use Post next for the rest (one post per click).")
    if StaticPopup_Show then StaticPopup_Show("AUCTIONAGENT_POST_ALL", text) end
end

if StaticPopupDialogs then
    StaticPopupDialogs["AUCTIONAGENT_POST_ALL"] = {
        text = "%s",
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        OnAccept = function()
            if S.pending then S.StartQueue(S.pending) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

if CreateFrame then
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "AUCTION_HOUSE_AUCTION_CREATED")
    pcall(f.RegisterEvent, f, "AUCTION_HOUSE_POST_ERROR")
    f:SetScript("OnEvent", function(_, event)
        AA.Fire("POST_RESULT", event == "AUCTION_HOUSE_AUCTION_CREATED")
    end)
end
