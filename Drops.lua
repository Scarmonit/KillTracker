-- Drops.lua — the per-mob loot panel (drop %, quantity, vendor value) shown
-- when you click a mob in the main window.

local _, ns = ...

local ROW_HEIGHT, DROP_ROWS = 18, 12
local WHITE = ns.WHITE
local currentMob

local function Build()
    if ns.drops then return ns.drops end

    local f = CreateFrame("Frame", "KillTracker_Drops", UIParent, "BackdropTemplate")
    ns.drops = f
    f:SetSize(360, 340); f:SetPoint("CENTER", 360, 0)
    ns.MakeMovable(f)
    ns.StylePanel(f)
    f.title = ns.AddTitleBar(f, "Drops")   -- set to the mob name on open

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOP", 0, -34)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local hItem = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hItem:SetPoint("TOPLEFT", 16, -52); hItem:SetText("Item")
    local hQty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hQty:SetPoint("TOPRIGHT", -150, -52); hQty:SetText("Qty")
    local hValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hValue:SetPoint("TOPRIGHT", -64, -52); hValue:SetText("Value")
    local hRate = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRate:SetPoint("TOPRIGHT", -16, -52); hRate:SetText("Drop%")
    ns.AddDivider(f, -66)

    local scroll = CreateFrame("ScrollFrame", "KillTracker_DropScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -70); scroll:SetPoint("BOTTOMRIGHT", -28, 14)
    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_HEIGHT, ns.RefreshDrops)
    end)
    f.scroll = scroll

    f.rows = {}
    for i = 1, DROP_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(316, ROW_HEIGHT)
        if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else row:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, 0) end
        ns.AddRowStripe(row, i % 2 == 0)
        row:SetHighlightTexture(WHITE, "ADD")
        if row:GetHighlightTexture() then row:GetHighlightTexture():SetVertexColor(0.3, 0.5, 0.9, 0.25) end
        row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.item:SetPoint("LEFT", 6, 0); row.item:SetWidth(150); row.item:SetJustifyH("LEFT")
        row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.qty:SetPoint("RIGHT", row, "RIGHT", -130, 0); row.qty:SetWidth(34); row.qty:SetJustifyH("RIGHT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -48, 0); row.value:SetWidth(76); row.value:SetJustifyH("RIGHT")
        row.rate = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rate:SetPoint("RIGHT", -6, 0); row.rate:SetWidth(40); row.rate:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link); GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = row
    end

    f:Hide()
    return f
end

function ns.RefreshDrops()
    local f = ns.drops
    if not f or not currentMob then return end
    local entry = ns.EnsureDB().byName[currentMob]
    local drops = entry and entry.drops
    local kills = entry and entry.count or 0

    f.title:SetText(currentMob)

    local list, totalValue = {}, 0
    if drops then
        for itemName, d in pairs(drops) do
            local sell = select(11, GetItemInfo(d.link or itemName)) or 0
            local value = sell * d.q
            totalValue = totalValue + value
            list[#list + 1] = { name = itemName, q = d.q, link = d.link, quality = d.quality,
                                value = value, rate = (kills > 0) and (d.n / kills * 100) or 0 }
        end
    end
    table.sort(list, function(a, b) return a.rate > b.rate end)

    local avgXP = ns.MobAvgXP(currentMob)
    local avgStr = avgXP and ("  ·  " .. ns.CommaNum(avgXP) .. " avg XP") or ""
    local valStr = (totalValue > 0) and ("  ·  " .. ns.Money(totalValue)) or ""
    f.sub:SetText(string.format("%d kills · %d drops%s%s", kills, #list, valStr, avgStr))

    local offset = FauxScrollFrame_GetOffset(f.scroll)
    for i = 1, DROP_ROWS do
        local row, data = f.rows[i], list[i + offset]
        if data then
            local name = data.name
            if data.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[data.quality] then
                name = ITEM_QUALITY_COLORS[data.quality].hex .. name .. "|r"
            end
            row.item:SetText(name)
            row.qty:SetText(data.q)
            row.value:SetText(data.value > 0 and ns.Money(data.value) or "")
            row.rate:SetText(string.format("%.0f%%", data.rate))
            row.link = data.link
            row:Show()
        else
            row:Hide(); row.link = nil
        end
    end
    FauxScrollFrame_Update(f.scroll, #list, DROP_ROWS, ROW_HEIGHT)
end

function ns.ShowDrops(mob)
    Build()
    currentMob = mob
    ns.RefreshDrops()
    ns.drops:Show()
end

ns.AddRefresher(function() if ns.drops and ns.drops:IsShown() then ns.RefreshDrops() end end)
ns.AddWipeHandler(function() if ns.drops then ns.drops:Hide() end end)
