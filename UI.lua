-- UI.lua — the main Kill Tracker window (stats block, searchable + sortable mob
-- list) and the unit-tooltip kill count.

local _, ns = ...

local ROW_HEIGHT, NUM_ROWS = 18, 14
local WHITE = ns.WHITE
local CLS_COLOR = ns.CLS_COLOR
local UNKNOWN = ns.UNKNOWN

-- ---------------------------------------------------------------------------
-- Tooltip kill count
-- ---------------------------------------------------------------------------
local function AddTooltipKills(tooltip, unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    ns.CacheUnit(unit)
    local name = UnitName(unit)
    if not name then return end
    local entry = ns.EnsureDB().byName[name]
    if entry then
        tooltip:AddDoubleLine("Killed", entry.count .. "x", 0.4, 1, 0.6, 1, 0.82, 0)
        tooltip:Show()
    end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            if tt == GameTooltip then local _, u = tt:GetUnit(); AddTooltipKills(tt, u) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
            local _, u = tt:GetUnit(); AddTooltipKills(tt, u)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
local function BuildUI()
    if ns.ui then return ns.ui end

    local frame = CreateFrame("Frame", "KillTracker_UI", UIParent, "BackdropTemplate")
    ns.ui = frame
    frame:SetSize(340, 488)
    frame:SetPoint("CENTER")
    ns.MakeMovable(frame)   -- main window position isn't persisted by design
    ns.StylePanel(frame)
    ns.AddTitleBar(frame, "Kill Tracker")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- hover the title bar for a quick summary (incl. Mobs to Level)
    local titleHover = CreateFrame("Button", nil, frame)
    titleHover:SetPoint("TOPLEFT", 1, -1)
    titleHover:SetPoint("TOPRIGHT", -48, -1)
    titleHover:SetHeight(24)
    titleHover:SetScript("OnEnter", function(self) ns.ShowSummaryTooltip(self) end)
    titleHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- gear button (options) next to the close button
    local gear = CreateFrame("Button", nil, frame)
    gear:SetSize(20, 20); gear:SetPoint("TOPRIGHT", -26, -4)
    gear:SetNormalTexture("Interface\\GossipFrame\\BinderGossipIcon")
    gear:SetScript("OnClick", function() if ns.ShowOptions then ns.ShowOptions() end end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Options"); GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- stat block
    frame.totalText   = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalText:SetPoint("TOP", 0, -34)
    frame.sessionText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.sessionText:SetPoint("TOP", 0, -52)
    frame.xpText      = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.xpText:SetPoint("TOP", 0, -68)
    frame.goldText    = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.goldText:SetPoint("TOP", 0, -84)
    frame.repText     = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.repText:SetPoint("TOP", 0, -100)

    ns.AddDivider(frame, -116)

    -- search box with placeholder + History button
    local search = CreateFrame("EditBox", "KillTracker_Search", frame, "InputBoxTemplate")
    search:SetSize(232, 20); search:SetPoint("TOPLEFT", 16, -124); search:SetAutoFocus(false)
    search:SetTextInsets(6, 6, 0, 0)
    local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 8, 0); ph:SetText("Search mobs..."); ph:SetTextColor(0.5, 0.5, 0.5)
    search:SetScript("OnTextChanged", function(self)
        ns.searchText = self:GetText():lower()
        ph:SetShown(self:GetText() == "")
        ns.RefreshUI()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    local histBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    histBtn:SetSize(70, 22); histBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    histBtn:SetText("History")
    histBtn:SetScript("OnClick", function() if ns.ShowHistory then ns.ShowHistory() end end)

    -- clickable column headers (sort)
    frame.hName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.hName:SetPoint("TOPLEFT", 16, -152)
    frame.hType = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.hType:SetPoint("TOPLEFT", 188, -152)
    frame.hKills = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.hKills:SetPoint("TOPRIGHT", -34, -152)

    local function headerButton(key, x, w)
        local b = CreateFrame("Button", nil, frame)
        b:SetPoint("TOPLEFT", x, -150); b:SetSize(w, 16)
        b:SetScript("OnClick", function() ns.SetSort(key) end)
    end
    headerButton("name", 14, 150)
    headerButton("ctype", 186, 70)
    headerButton("count", 270, 50)
    ns.AddDivider(frame, -166)

    local scroll = CreateFrame("ScrollFrame", "KillTracker_Scroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -170)
    scroll:SetPoint("BOTTOMRIGHT", -28, 58)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, ns.RefreshUI)
    end)
    frame.scroll = scroll

    frame.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(296, ROW_HEIGHT)
        if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else row:SetPoint("TOPLEFT", frame.rows[i - 1], "BOTTOMLEFT", 0, 0) end
        ns.AddRowStripe(row, i % 2 == 0)
        row:SetHighlightTexture(WHITE, "ADD")
        if row:GetHighlightTexture() then row:GetHighlightTexture():SetVertexColor(0.3, 0.5, 0.9, 0.25) end
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(176); row.name:SetJustifyH("LEFT")
        row.type = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.type:SetPoint("LEFT", 182, 0); row.type:SetWidth(78); row.type:SetJustifyH("LEFT")
        row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.kills:SetPoint("RIGHT", -6, 0); row.kills:SetWidth(40); row.kills:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.mob and ns.ShowDrops then ns.ShowDrops(self.mob) end
        end)
        frame.rows[i] = row
    end

    -- footer
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 40); hint:SetText("|cff707070click a mob to see its drops|r")

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(82, 22); reset:SetPoint("BOTTOMLEFT", 12, 12); reset:SetText("Reset All")
    reset:SetScript("OnClick", function() StaticPopup_Show("KILLTRACKER_RESET") end)
    local hudBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    hudBtn:SetSize(92, 22); hudBtn:SetPoint("BOTTOM", 0, 12); hudBtn:SetText("Toggle HUD")
    hudBtn:SetScript("OnClick", function() if ns.ToggleHUD then ns.ToggleHUD() end end)
    local sesBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sesBtn:SetSize(112, 22); sesBtn:SetPoint("BOTTOMRIGHT", -12, 12); sesBtn:SetText("Reset Session")
    sesBtn:SetScript("OnClick", function() ns.ResetSession() end)

    frame:Hide()
    return frame
end
ns.BuildUI = BuildUI

local function HeaderLabel(base, key)
    local sortKey, sortDir = ns.GetSort()
    if key ~= sortKey then return base end
    return base .. (sortDir == 1 and " |cffffd100^|r" or " |cffffd100v|r")
end

function ns.RefreshUI()
    local frame = ns.ui
    if not frame then return end
    local db = ns.EnsureDB()
    local list = ns.GetSorted()

    frame.hName:SetText(HeaderLabel("Mob", "name"))
    frame.hType:SetText(HeaderLabel("Type", "ctype"))
    frame.hKills:SetText(HeaderLabel("Kills", "count"))

    local sp = db.special
    local spStr = ""
    if (sp.rare + sp.elite + sp.boss) > 0 then
        spStr = string.format("  ·  |cffa335ee%d|r rare |cffffd100%d|r elite |cffff8000%d|r boss",
            sp.rare, sp.elite, sp.boss)
    end
    frame.totalText:SetText(string.format(
        "Total |cffffd100%d|r kills  ·  Deaths |cffff5555%d|r%s", db.total, db.deaths, spStr))

    local _, kph, _, _, _, gph = ns.RecentRates()
    frame.sessionText:SetText(string.format(
        "Session: |cffffd100%d|r kills  |  |cffffd100%.0f|r KPH  |  %s  |  |cffff5555%d|r deaths",
        ns.session.count, kph, ns.FormatTime(ns.SessionElapsed()), ns.session.deaths))

    local xs = ns.XPStats()
    if xs then
        local ttl = xs.ttl and ns.FormatTime(xs.ttl) or "--"
        local rested = (xs.rested > 0) and ("  |cffff80ff+" .. ns.CommaNum(xs.rested) .. " rested|r") or ""
        local mobsSeg = ""
        if db.showMobsToLevel then
            mobsSeg = " · |cff66ccff" .. (xs.mobs and tostring(xs.mobs) or "--") .. "|r mobs"
        end
        frame.xpText:SetText(string.format("XP |cff66ccff%s|r/hr · to level |cff66ccff%s|r%s%s",
            ns.CommaNum(xs.xph), ttl, mobsSeg, rested))
    else
        frame.xpText:SetText("|cff808080Max level — XP tracking off|r")
    end

    local earned = ns.session.gold + ns.session.loot
    frame.goldText:SetText("Gold: " .. ns.Money(gph) .. "/hr  ( " .. ns.Money(earned) .. " )")

    local rs = ns.RepStats()
    if rs then
        frame.repText:SetText(string.format(
            "|cffff80ff%s|r %s · |cffff80ff%s|r/hr · to next |cffff80ff%s|r · |cffff80ff%s|r kills",
            rs.name, rs.standing, ns.CommaNum(rs.reph),
            rs.ttl and ns.FormatTime(rs.ttl) or "--", rs.kills and tostring(rs.kills) or "--"))
    else
        frame.repText:SetText("|cff606060No watched faction|r")
    end

    local offset = FauxScrollFrame_GetOffset(frame.scroll)
    for i = 1, NUM_ROWS do
        local row, data = frame.rows[i], list[i + offset]
        if data then
            local c = data.cls and CLS_COLOR[data.cls]
            if c then row.name:SetTextColor(c[1], c[2], c[3]) else row.name:SetTextColor(1, 1, 1) end
            local mark = c and (" |cff" .. string.format("%02x%02x%02x",
                math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) .. "[" .. c[4] .. "]|r") or ""
            row.name:SetText(data.name .. mark)
            row.type:SetText(data.ctype ~= UNKNOWN and data.ctype or "")
            row.kills:SetText(data.count)
            row.mob = data.name
            row:Show()
        else
            row:Hide(); row.mob = nil
        end
    end
    FauxScrollFrame_Update(frame.scroll, #list, NUM_ROWS, ROW_HEIGHT)
end

-- Summary shown when hovering the window's title bar.
function ns.ShowSummaryTooltip(anchor)
    local db = ns.EnsureDB()
    GameTooltip:SetOwner(anchor, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Kill Tracker")
    GameTooltip:AddDoubleLine("Total kills", db.total, 1, 1, 1, 1, 0.82, 0)
    local _, kph, _, _, _, gph = ns.RecentRates()
    GameTooltip:AddDoubleLine("Session", string.format("%d kills  (%.0f KPH)", ns.session.count, kph),
        1, 1, 1, 1, 0.82, 0)
    local xs = ns.XPStats()
    if xs then
        GameTooltip:AddDoubleLine("XP / hour", ns.CommaNum(xs.xph), 1, 1, 1, 0.4, 0.8, 1)
        GameTooltip:AddDoubleLine("Time to level", xs.ttl and ns.FormatTime(xs.ttl) or "--", 1, 1, 1, 0.4, 0.8, 1)
        if db.showMobsToLevel then
            GameTooltip:AddDoubleLine("Mobs to level", xs.mobs and tostring(xs.mobs) or "--", 1, 1, 1, 1, 0.82, 0)
        end
    else
        GameTooltip:AddLine("Max level", 0.5, 0.5, 0.5)
    end
    GameTooltip:AddDoubleLine("Gold / hour", ns.Money(gph), 1, 1, 1, 1, 0.82, 0)
    local rs = ns.RepStats()
    if rs then
        GameTooltip:AddDoubleLine(rs.name .. " to next", rs.kills and (rs.kills .. " kills") or "--",
            1, 1, 1, 0.9, 0.5, 0.9)
    end
    GameTooltip:Show()
end

function ns.ToggleUI()
    BuildUI()
    if ns.ui:IsShown() then ns.ui:Hide()
    else ns.RefreshUI(); ns.ui:Show() end
end

-- repaint when shown
ns.AddRefresher(function() if ns.ui and ns.ui:IsShown() then ns.RefreshUI() end end)
ns.On("PLAYER_LOGIN", HookTooltips)
