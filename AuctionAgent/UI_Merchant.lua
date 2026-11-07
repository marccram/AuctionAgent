local ADDON, AA = ...

-- Vendor button: sits inside the merchant window and sells every item marked "Vendor" with
-- one click ("Sell marked (N)"; the tooltip lists them with their value). Only marked items are ever
-- sold. Items are sold one per timer tick with the merchant window re-checked each time,
-- so UseContainerItem can never fire outside a vendor (where it would USE the item).

local C, P, M = AA.Compat, AA.Prices, AA.Marks
local V = {}
AA.Merchant = V

local btn, ticker
V.selling = false
V.open = false   -- tracked from MERCHANT_SHOW/CLOSED; never trust frame timing for display

-- Used as the safety check before every sale: both our own flag and the real frame.
local function merchantOpen()
    return V.open and _G.MerchantFrame ~= nil and MerchantFrame:IsShown()
end

function V.Plan()
    return M.VendorPlan(AA.Bags.Enumerate(), AA.db.marks, function(id, link)
        return AA.Bags.VendorPrice(id, link)
    end)
end

-- Marked-for-vendor stacks that are worth more on the AH by the usual margin rules.
local function worthMoreOnAH(it)
    local entry = P.Get(AA.db, AA.RealmKey(), it.itemID)
    local e = P.Evaluate(entry, it.vendor, it.count, time(), AA.settings)
    return e.state == "ok" and e.rec == "auction"
end

---------------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------------

local function finish(why)
    if ticker then ticker:Cancel() ticker = nil end
    V.selling = false
    if V.report then
        local r = V.report
        V.report = nil
        if r.sold > 0 then
            AA.Print(("Sold %d marked stack%s for about %s.%s"):format(r.sold, r.sold == 1 and "" or "s",
                P.FormatMoney(r.value), why and (" (" .. why .. ")") or ""))
        elseif why then
            AA.Print("Selling stopped: " .. why)
        end
    end
    V.Update()
end

function V.SellMarked()
    if V.selling or not merchantOpen() then return end
    local plan = V.Plan()
    if #plan == 0 then return end
    V.selling = true
    V.report = { sold = 0, value = 0 }
    local i = 0
    ticker = C_Timer.NewTicker(0.12, function()
        local ok, err = pcall(function()
            i = i + 1
            local it = plan[i]
            if not it then finish() return end
            if not merchantOpen() then finish("merchant closed") return end
            local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
            if type(info) == "table" and C.SafeNumber(info.itemID) == it.itemID
                and not info.isLocked and M.Get(AA.db, it.itemID) == "vendor" then
                local n = C.SafeNumber(info.stackCount) or it.count
                C_Container.UseContainerItem(it.bag, it.slot)
                V.report.sold = V.report.sold + 1
                V.report.value = V.report.value + it.vendor * n
            end
        end)
        if not ok then finish("error: " .. tostring(err)) end
    end)
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------

local function showTooltip(self)
    local plan = btn and btn.plan
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not plan or #plan == 0 then
        GameTooltip:AddLine("AuctionAgent", 1, 0.82, 0)
        GameTooltip:AddLine("Nothing marked for vendor. Alt+click items in your bags to mark them.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine("Sell items marked for vendor", 1, 0.82, 0)
    for n, it in ipairs(plan) do
        if n > 15 then GameTooltip:AddLine(("... and %d more"):format(#plan - 15), 0.7, 0.7, 0.7) break end
        local warn = worthMoreOnAH(it) and "  |cffff8000! worth more on the AH|r" or ""
        GameTooltip:AddLine(("%s x%d  %s%s"):format(it.link or it.name or ("item " .. it.itemID), it.count,
            P.FormatMoney(it.value), warn))
    end
    GameTooltip:AddLine("Total: " .. P.FormatMoney(btn.total or 0), 1, 1, 1)
    GameTooltip:Show()
end

local function create()
    btn = CreateFrame("Button", "AuctionAgentSellMarkedButton", MerchantFrame, "UIPanelButtonTemplate")
    -- Below the window's bottom-right corner: inside the frame the bottom row is taken by the
    -- repair and junk buttons, and the tabs only occupy the left.
    btn:SetSize(140, 24)
    btn:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -6, 4)
    btn:SetFrameLevel(MerchantFrame:GetFrameLevel() + 10)
    btn:SetText("Sell marked")
    btn:SetScript("OnClick", function() pcall(V.SellMarked) end)
    btn:SetScript("OnEnter", showTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local reported
function V.Update()
    if not AA.db then return end
    if not V.open then
        if btn then btn:Hide() end
        return
    end
    if not btn and not V.createFailed then
        local ok, err = pcall(create)
        if not ok then
            V.createFailed = true
            AA.Print("Sell-marked button could not be built: " .. tostring(err))
        end
    end
    if not btn then return end
    local plan, total, unknown = V.Plan()
    btn.plan, btn.total = plan, total
    btn:SetText(("Sell marked (%d)"):format(#plan + unknown))
    if V.selling or #plan == 0 then btn:Disable() else btn:Enable() end
    btn:Show()
end

-- Errors in refreshes are reported once instead of vanishing.
local function safeUpdate()
    local ok, err = pcall(V.Update)
    if not ok and not reported then
        reported = true
        AA.Print("Vendor button error: " .. tostring(err))
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        V.open = true
        safeUpdate()
        C_Timer.After(0.3, safeUpdate)   -- again once the merchant window has surely finished opening
        if AA.settings and AA.settings.autoSellMarked then
            C_Timer.After(0.4, function() pcall(V.SellMarked) end)
        end
    else
        if V.selling then finish("merchant closed") end
        V.open = false
        safeUpdate()
    end
end)

for _, ev in ipairs({ "BAGS_CHANGED", "MARKS_CHANGED", "ITEM_INFO_LOADED", "SCAN_DONE", "SETTINGS_CHANGED" }) do
    AA.Register(ev, safeUpdate)
end
