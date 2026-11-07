local ADDON, AA = ...

-- Scan progress bar: sits under the Auction House window while a scan runs, so it is always
-- clear that a scan is happening, how far along it is, and that the AH must stay open. When a
-- scan ends it shows a green "done, you can close the AH" or a red failure message for a few
-- seconds. All UI work is under pcall.

local S = AA.Scanner
local B = {}
AA.ScanBar = B

local DONE_SECONDS, FAIL_SECONDS = 8, 14
local RUNNING = { 0.2, 0.55, 0.95 }
local GOOD = { 0.2, 0.7, 0.3 }
local BAD = { 0.75, 0.22, 0.22 }

local bar, waitingSince

local function now() return GetTime() end

local function create()
    local ah = _G.AuctionHouseFrame
    if not ah then return nil end
    bar = CreateFrame("StatusBar", "AuctionAgentScanBar", ah)
    bar:SetSize(470, 22)
    bar:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -4, 2)
    bar:SetFrameStrata("HIGH")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)

    local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.55, 0.45, 0.12, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar.text:SetWidth(460)
    bar.text:SetWordWrap(false)

    local acc = 0
    bar:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if self.indeterminate then
            self:SetAlpha(0.65 + 0.35 * math.sin(now() * 4))   -- gentle pulse while waiting
        else
            self:SetAlpha(1)
        end
        if acc >= 0.2 then
            acc = 0
            pcall(B.Update)   -- also expires the finished/failed message
        end
    end)
    bar:Hide()
    return bar
end

local function paint(color, text, frac, indeterminate)
    bar:SetStatusBarColor(color[1], color[2], color[3], 0.9)
    bar:SetValue(frac or 1)
    bar.indeterminate = indeterminate
    bar.text:SetText(text)
    bar:Show()
end

function B.Update()
    if not bar and not B.createFailed then
        local ok, res = pcall(create)
        if not ok then
            B.createFailed = true
            AA.Print("Scan progress bar could not be built: " .. tostring(res))
        end
    end
    if not bar then return end
    if not S.ahOpen then bar:Hide() return end

    local st = S.state
    if st then
        B.result = nil
        local text, frac = S.ProgressInfo(st)
        if frac == nil then
            waitingSince = waitingSince or now()
            local t = math.floor(now() - waitingSince)
            text = ("%s %d:%02d"):format(text, math.floor(t / 60), t % 60)
        else
            waitingSince = nil
        end
        paint(RUNNING, text .. "  -  keep the Auction House open", frac, frac == nil)
        return
    end

    waitingSince = nil
    local r = B.result
    if r and now() < r.expires then
        paint(r.ok and GOOD or BAD, r.text, 1, false)
    else
        B.result = nil
        bar:Hide()
    end
end

AA.Register("SCAN_UPDATE", function() pcall(B.Update) end)
AA.Register("SCAN_ENDED", function(ok, msg)
    B.result = { ok = ok, text = msg, expires = now() + (ok and DONE_SECONDS or FAIL_SECONDS) }
    pcall(B.Update)
end)
AA.Register("AH_CLOSED", function()
    B.result = nil
    waitingSince = nil
    if bar then bar:Hide() end
end)
