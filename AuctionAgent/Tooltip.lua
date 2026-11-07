local ADDON, AA = ...

-- Item tooltip lines: AH value, margin, and a Worth auctioning / Vendor it hint.
-- Everything runs under pcall and fails silent: a tooltip must never error.

local C, P = AA.Compat, AA.Prices
local T = {}
AA.Tooltip = T

local L = AA.L

local function coin(copper)
    return P.FormatMoney(copper)
end

local function pct(margin)
    if margin == math.huge then return "no vendor value" end
    return ("%+d%%"):format(math.floor(margin * 100 + 0.5))
end

-- Compact mode: Forever Auctionator / VendorPricePlus already show prices, so we only
-- add what they lack (margin and recommendation).
-- Pure: which tooltip mode applies. Compact (margin and recommendation only) is used only when
-- Auctionator is loaded AND already shows a price for this item; otherwise our own AH value
-- line is shown, so an item Auctionator reports as "Unknown" still gets a price from our scan.
function T.ChooseMode(settings, auctionatorHasPrice)
    if not settings then return "off" end
    local mode = settings.tooltipMode
    if mode == "full" and settings.autoCompact ~= false and auctionatorHasPrice then
        return "compact"
    end
    return mode
end

-- Auctionator's own price for an item (its database is filled by its own scans, not ours).
local function auctionatorPrice(id)
    if not id or not C.IsAddOnLoaded("Auctionator") then return nil end
    local ok, price = pcall(function()
        local A = _G.Auctionator
        local api = A and A.API and A.API.v1
        if api and api.GetAuctionPriceByItemID then
            return api.GetAuctionPriceByItemID("AuctionAgent", id)
        end
    end)
    price = ok and C.SafeNumber(price) or nil
    return price and price > 0 and price or nil
end

function T.EffectiveMode(itemID)
    return T.ChooseMode(AA.settings, auctionatorPrice(itemID) ~= nil)
end

-- Pure-ish: turns an Evaluate() result into {left, right, r, g, b} line specs.
-- Separated from the tooltip calls so the wording is easy to test.
function T.BuildLines(eval, mode, bound)
    local lines = {}
    if eval.state == "nodata" then
        if mode == "full" then lines[#lines + 1] = { L["NO_DATA"], nil, 0.6, 0.6, 0.6 } end
        return lines
    end
    local dim = eval.stale and 0.6 or 1
    if eval.state == "nolistings" then
        if mode == "full" then lines[#lines + 1] = { L["NO_LISTINGS"] .. " (" .. eval.age .. ")", nil, 0.6, 0.6, 0.6 } end
        return lines
    end
    if mode == "full" then
        local right = coin(eval.market) .. " ea"
        if eval.qty > 1 then right = right .. "  x" .. eval.qty .. " = " .. coin(eval.marketTotal) end
        lines[#lines + 1] = { "AH value (" .. eval.age .. ")", right, 1 * dim, 0.82 * dim, 0 }
    end
    if bound then return lines end   -- soulbound: cannot be auctioned, so no recommendation
    if mode == "full" and eval.deposit then
        lines[#lines + 1] = { "Est. deposit (counted in profit)", coin(eval.deposit), 0.7, 0.7, 0.7 }
    end
    if eval.rec == "auction" then
        local detail = eval.margin and pct(eval.margin) or ""
        lines[#lines + 1] = { "Worth auctioning " .. detail, "+" .. coin(eval.profit) .. " ea", 0.3, 1, 0.3 }
    elseif eval.rec == "vendor" then
        lines[#lines + 1] = { "Vendor it", nil, 0.75, 0.75, 0.75 }
    elseif mode == "compact" and eval.margin then
        lines[#lines + 1] = { "AH vs vendor " .. pct(eval.margin), nil, 0.7, 0.7, 0.7 }
    end
    return lines
end

local function stackAndBound(tooltip)
    local ok, count, bound = pcall(function()
        local owner = tooltip:GetOwner()
        if owner and owner.GetBagID and owner.GetID then
            local info = C_Container.GetContainerItemInfo(owner:GetBagID(), owner:GetID())
            if type(info) == "table" then
                return C.SafeNumber(info.stackCount) or 1, info.isBound == true
            end
        end
    end)
    if ok then return count or 1, bound or false end
    return 1, false
end

local function onTooltip(tooltip, data)
    pcall(function()
        local id = C.SafeNumber(data and data.id)
        if not id then return end
        local mode = T.EffectiveMode(id)
        if mode == "off" or not AA.db then return end
        local qty, bound = stackAndBound(tooltip)
        local entry = P.Get(AA.db, AA.RealmKey(), id)
        local eval = P.Evaluate(entry, AA.Bags.VendorPrice(id, data.hyperlink), qty, time(), AA.settings)
        for _, l in ipairs(T.BuildLines(eval, mode, bound)) do
            if l[2] then
                tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 1, 1, 1)
            else
                tooltip:AddLine(l[1], l[3], l[4], l[5])
            end
        end
    end)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, onTooltip)
end

-- Refresh nothing here: the tooltip is rebuilt on every hover, so new prices and
-- newly cached vendor prices show up the next time the item is hovered.
