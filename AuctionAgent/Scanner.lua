local ADDON, AA = ...

-- Auction house scanning. Two paths, both read-only:
--   Full   : ReplicateItems -> whole-AH snapshot, processed in chunks across frames.
--   Bags   : targeted SendSearchQuery for each distinct sellable bag item, throttle-paced.
-- Prices are folded into unit-weighted accumulators and stored via Prices.Store.

local C, P = AA.Compat, AA.Prices
local S = {}
AA.Scanner = S

local CHUNK = 2000          -- replicate rows processed per frame
local QUERY_TIMEOUT = 6     -- seconds to wait for one targeted query before skipping it

S.ahOpen = false
S.state = nil       -- { kind = "full"|"bags", phase = ..., done = n, total = n }

local function say(msg) AA.Print(msg) end

function S.IsBusy() return S.state ~= nil end

function S.Status()
    local st = S.state
    if not st then return "idle" end
    return ("%s scan: %s %d/%d"):format(st.kind, st.phase, st.done or 0, st.total or 0)
end

function S.Cancel(reason)
    if S.state then
        say("Scan cancelled" .. (reason and (": " .. reason) or "") .. ".")
        S.state = nil
    end
end

local function finish(kind, stored)
    S.state = nil
    AA.settings.lastScan = time()
    if kind == "full" and AA.db then AA.db.fullScanAt = time() end
    say(("%s scan done: %d items priced."):format(kind == "full" and "Full" or "Bag", stored))
    AA.Fire("SCAN_DONE", kind, stored)
end

---------------------------------------------------------------------------
-- Full scan (replicate)
---------------------------------------------------------------------------

local function finishFull(st)
    local db, rk, now = AA.db, AA.RealmKey(), time()
    local stored = 0
    for itemID, acc in pairs(st.acc) do
        if P.Store(db, rk, itemID, acc:Result(), now, "scan") then stored = stored + 1 end
    end
    -- Bag items that appear nowhere in the scan really have no listings.
    for _, e in ipairs(AA.Bags.Enumerate()) do
        if not st.acc[e.itemID] and not e.bound then P.StoreNone(db, rk, e.itemID, now, "scan") end
    end
    finish("full", stored)
end

local function processChunk()
    local st = S.state
    if not st or st.kind ~= "full" or st.phase ~= "processing" then return end
    local ok, err = pcall(function()
        local GetInfo = C_AuctionHouse.GetReplicateItemInfo
        local stop = math.min(st.i + CHUNK, st.total)
        for i = st.i, stop - 1 do
            -- returns: name, icon, count, quality, usable, level, levelType, minBid, minIncrement,
            --          buyout (TOTAL for the stack), bid, highBidder, bidderFull, owner, ownerFull,
            --          saleStatus, itemID, hasAllInfo
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetInfo(i)
            if type(itemID) == "number" and type(buyout) == "number" and type(count) == "number"
                and buyout > 0 and count > 0 then
                local acc = st.acc[itemID]
                if not acc then
                    acc = P.NewAccumulator(AA.settings)
                    st.acc[itemID] = acc
                end
                acc:Add(buyout / count, count)
            end
        end
        st.i, st.done = stop, stop
    end)
    if not ok then
        S.state = nil
        say("Scan aborted: " .. tostring(err))
        return
    end
    if st.done >= st.total then
        finishFull(st)
    else
        local pct = math.floor(st.done / st.total * 100)
        if pct >= st.nextReport then
            say(("Scanning... %d%%"):format(pct))
            st.nextReport = st.nextReport + 25
        end
        C_Timer.After(0, processChunk)
    end
end

-- Number of auctions in the snapshot the client currently holds (0 if none).
local function snapshotSize()
    local ok, n = C.Call("C_AuctionHouse.GetNumReplicateItems")
    return (ok and C.SafeNumber(n)) or 0
end

local function beginProcessing(st)
    local n = snapshotSize()
    if n <= 0 then S.state = nil; say("Scan failed: no auction snapshot is loaded."); return end
    st.phase, st.total, st.done, st.i, st.acc, st.nextReport = "processing", n, 0, 0, {}, 25
    say(("Processing %d auctions..."):format(n))
    processChunk()
end

local function onReplicate()
    local st = S.state
    if not st or st.kind ~= "full" or st.phase ~= "waiting" then return end
    beginProcessing(st)
end

local WAIT_SECONDS = 120

function S.StartFull()
    if not S.ahOpen then say("Open the Auction House first.") return end
    if S.state then say("A scan is already running (" .. S.Status() .. ").") return end
    local ok, err = C.Call("C_AuctionHouse.ReplicateItems")
    if not ok then say("Full scan unavailable: " .. tostring(err)) return end
    S.state = { kind = "full", phase = "waiting", done = 0, total = 0 }
    say("Full scan requested. The server can take up to a minute or two to answer, and limits how often it allows this.")
    local st = S.state
    C_Timer.After(WAIT_SECONDS, function()
        if S.state == st and st.phase == "waiting" then
            S.state = nil
            local held = snapshotSize()
            say("Full scan timed out: the server never sent the auction list (probably its scan cooldown).")
            if held > 0 then
                say(("The client still holds an earlier snapshot of %d auctions. Use /aa scan cached to price from it."):format(held))
            end
        end
    end)
end

-- Price from whatever snapshot the client already holds (no server request).
function S.StartCached()
    if not S.ahOpen then say("Open the Auction House first.") return end
    if S.state then say("A scan is already running (" .. S.Status() .. ").") return end
    if snapshotSize() <= 0 then say("No snapshot is loaded yet. Run /aa scan first.") return end
    S.state = { kind = "full", phase = "waiting", done = 0, total = 0 }
    beginProcessing(S.state)
end

---------------------------------------------------------------------------
-- Targeted bag scan
---------------------------------------------------------------------------

local function makeKey(itemID)
    local ok, key = C.Call("C_AuctionHouse.MakeItemKey", itemID)
    if ok and type(key) == "table" then return key end
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

local function store(itemID, acc)
    local db, rk, now = AA.db, AA.RealmKey(), time()
    local result = acc:Result()
    if result then
        P.Store(db, rk, itemID, result, now, "search")
        return true
    end
    P.StoreNone(db, rk, itemID, now, "search")
    return false
end

local function sendNext()
    local st = S.state
    if not st or st.kind ~= "bags" then return end
    st.idx = st.idx + 1
    st.done = st.idx - 1
    if st.idx > #st.queue then
        finish("bags", st.priced)
        return
    end
    local itemID = st.queue[st.idx]
    st.current, st.got = itemID, false
    st.token = st.token + 1
    local token = st.token
    local ok = C.Call("C_AuctionHouse.SendSearchQuery", makeKey(itemID), {}, true)
    if not ok then st.got = true; return sendNext() end
    C_Timer.After(QUERY_TIMEOUT, function()
        if S.state == st and st.token == token and not st.got then
            st.got = true
            sendNext()
        end
    end)
end

function S.StartBags()
    if not S.ahOpen then say("Open the Auction House first.") return end
    if S.state then say("A scan is already running (" .. S.Status() .. ").") return end
    local queue, seen = {}, {}
    for _, g in ipairs(AA.Bags.Summarize()) do
        if not seen[g.itemID] then seen[g.itemID] = true; queue[#queue + 1] = g.itemID end
    end
    if #queue == 0 then say("No sellable items in your bags.") return end
    S.state = { kind = "bags", phase = "querying", queue = queue, idx = 0, done = 0,
                total = #queue, priced = 0, token = 0, got = true }
    say(("Scanning %d bag items (about %d seconds)..."):format(#queue, math.ceil(#queue * 0.6)))
    local ok, ready = C.Call("C_AuctionHouse.IsThrottledMessageSystemReady")
    if not ok or ready then sendNext() end   -- otherwise THROTTLED_SYSTEM_READY starts it
end

local function onCommodity(itemID)
    local st = S.state
    if not st or st.kind ~= "bags" or st.got or st.current ~= itemID then return end
    st.got = true
    local acc = P.NewAccumulator(AA.settings)
    local _, n = C.Call("C_AuctionHouse.GetNumCommoditySearchResults", itemID)
    n = C.SafeNumber(n) or 0
    for i = 1, math.min(n, 300) do
        local ok, r = C.Call("C_AuctionHouse.GetCommoditySearchResultInfo", itemID, i)
        if ok and type(r) == "table" then acc:Add(C.SafeNumber(r.unitPrice), C.SafeNumber(r.quantity)) end
    end
    if store(itemID, acc) then st.priced = st.priced + 1 end
end

local function onItemResults(itemKey)
    local st = S.state
    local itemID = type(itemKey) == "table" and C.SafeNumber(itemKey.itemID)
    if not st or st.kind ~= "bags" or st.got or st.current ~= itemID then return end
    st.got = true
    local acc = P.NewAccumulator(AA.settings)
    local _, n = C.Call("C_AuctionHouse.GetNumItemSearchResults", itemKey)
    n = C.SafeNumber(n) or 0
    for i = 1, math.min(n, 300) do
        local ok, r = C.Call("C_AuctionHouse.GetItemSearchResultInfo", itemKey, i)
        if ok and type(r) == "table" then
            local buyout, qty = C.SafeNumber(r.buyoutAmount), C.SafeNumber(r.quantity) or 1
            if buyout and buyout > 0 and qty > 0 then acc:Add(buyout / qty, qty) end
        end
    end
    if store(itemID, acc) then st.priced = st.priced + 1 end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

if CreateFrame then
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
        "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
        "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, arg1)
        local ok, err = pcall(function()
            if event == "AUCTION_HOUSE_SHOW" then
                S.ahOpen = true
                AA.Fire("AH_SHOW")
                C_Timer.After(0.5, function()
                    if not S.ahOpen then return end
                    if AA.Onboarding and AA.Onboarding.WantsFullScan(AA.db) then
                        AA.Onboarding.AskFullScan()      -- first-run: offer a full scan instead
                    elseif AA.settings and AA.settings.autoScan then
                        if AA.settings.scanScope == "full" then S.StartFull() else S.StartBags() end
                    end
                end)
            elseif event == "AUCTION_HOUSE_CLOSED" then
                S.ahOpen = false
                S.Cancel("auction house closed")
                AA.Fire("AH_CLOSED")
            elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
                onReplicate()
            elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
                onCommodity(arg1)
            elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
                onItemResults(arg1)
            elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" then
                if S.state and S.state.phase == "waiting" and S.state.kind == "full" then
                    say(event:find("DROPPED") and "The server dropped the scan request (throttled)."
                        or "The scan request is queued behind the server's throttle.")
                end
            elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
                local st = S.state
                if st and st.kind == "bags" and st.got then sendNext() end
            end
        end)
        if not ok and AA.settings and AA.settings.debug then AA.Print("Scanner error: " .. tostring(err)) end
    end)
end
