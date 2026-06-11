-- History.lua — the saved-session history panel (`/kt history`).

local _, ns = ...

local ROW_HEIGHT, HIST_ROWS = 18, 14

local function Build()
    if ns.history then return ns.history end

    local f = CreateFrame("Frame", "KillTracker_History", UIParent, "BackdropTemplate")
    ns.history = f
    f:SetSize(380, 360); f:SetPoint("CENTER", -370, 0)
    ns.MakeMovable(f)
    ns.StylePanel(f)
    ns.AddTitleBar(f, "Session History")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOP", 0, -34)

    local cols = { {"When", 14, "LEFT"}, {"Time", 92, "LEFT"}, {"Kills", 150, "LEFT"},
                   {"XP", 210, "LEFT"}, {"Gold", 286, "LEFT"}, {"Deaths", -14, "RIGHT"} }
    for _, c in ipairs(cols) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if c[3] == "RIGHT" then h:SetPoint("TOPRIGHT", c[2], -52) else h:SetPoint("TOPLEFT", c[2], -52) end
        h:SetText(c[1])
    end
    ns.AddDivider(f, -66)

    local scroll = CreateFrame("ScrollFrame", "KillTracker_HistScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -70); scroll:SetPoint("BOTTOMRIGHT", -28, 14)
    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_HEIGHT, ns.RefreshHistory)
    end)
    f.scroll = scroll

    f.rows = {}
    for i = 1, HIST_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(336, ROW_HEIGHT)
        if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else row:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, 0) end
        ns.AddRowStripe(row, i % 2 == 0)
        local function cell(x, w, justify, font)
            local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
            if justify == "RIGHT" then fs:SetPoint("RIGHT", x, 0) else fs:SetPoint("LEFT", x, 0) end
            fs:SetWidth(w); fs:SetJustifyH(justify)
            return fs
        end
        row.when   = cell(4, 74, "LEFT")
        row.time   = cell(82, 56, "LEFT")
        row.kills  = cell(140, 54, "LEFT")
        row.xp     = cell(198, 70, "LEFT")
        row.gold   = cell(270, 70, "LEFT", "GameFontDisableSmall")
        row.deaths = cell(-6, 40, "RIGHT")
        f.rows[i] = row
    end

    f:Hide()
    return f
end

function ns.RefreshHistory()
    local f = ns.history
    if not f then return end
    local hist = ns.EnsureDB().history

    f.sub:SetText(#hist .. " saved sessions (newest first)")
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    for i = 1, HIST_ROWS do
        local row, h = f.rows[i], hist[i + offset]
        if h then
            row.when:SetText(h.when or "?")
            row.time:SetText(ns.FormatTime(h.dur or 0))
            row.kills:SetText(h.kills or 0)
            row.xp:SetText("|cff66ccff" .. ns.CommaNum(h.xp or 0) .. "|r")
            row.gold:SetText(ns.Money(h.gold or 0))
            row.deaths:SetText((h.deaths and h.deaths > 0) and ("|cffff5555" .. h.deaths .. "|r") or "0")
            row:Show()
        else
            row:Hide()
        end
    end
    FauxScrollFrame_Update(f.scroll, #hist, HIST_ROWS, ROW_HEIGHT)
end

function ns.ShowHistory()
    Build()
    ns.RefreshHistory()
    ns.history:Show()
end

ns.AddRefresher(function() if ns.history and ns.history:IsShown() then ns.RefreshHistory() end end)
ns.AddWipeHandler(function() if ns.history then ns.history:Hide() end end)
