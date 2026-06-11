-- HUD.lua — the compact live grinding readout. Movable, resizable, and lockable;
-- position, size, and lock/shown state are all saved per character.

local _, ns = ...

local DEFAULT_W, DEFAULT_H = 180, 98
local MIN_W, MIN_H, MAX_W, MAX_H = 150, 64, 420, 280

-- Apply the locked state: when locked the HUD ignores the mouse (click-through),
-- can't be dragged, and hides its resize grip + drag hint.
local function ApplyLock(hud, locked)
    hud:EnableMouse(not locked)
    if locked then hud:RegisterForDrag() else hud:RegisterForDrag("LeftButton") end
    if hud.grip then hud.grip:SetShown(not locked) end
    if hud.hint then hud.hint:SetShown(not locked) end
end

local function Build()
    if ns.hud then return ns.hud end
    local db = ns.EnsureDB()

    local hud = CreateFrame("Frame", "KillTracker_HUD", UIParent, "BackdropTemplate")
    ns.hud = hud
    hud:SetSize(db.hud.w or DEFAULT_W, db.hud.h or DEFAULT_H)
    hud:SetScale(db.hud.scale or 1.0)
    if db.hud.point then hud:SetPoint(db.hud.point, UIParent, db.hud.point, db.hud.x or 0, db.hud.y or 0)
    else hud:SetPoint("TOP", 0, -160) end
    hud:SetClampedToScreen(true)

    -- movable
    hud:SetMovable(true)
    hud:SetScript("OnDragStart", function(self) if not db.hud.locked then self:StartMoving() end end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        db.hud.point, db.hud.x, db.hud.y = p, x, y
    end)

    -- resizable
    hud:SetResizable(true)
    if hud.SetResizeBounds then
        hud:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif hud.SetMinResize then
        hud:SetMinResize(MIN_W, MIN_H); hud:SetMaxResize(MAX_W, MAX_H)
    end

    if hud.SetBackdrop then
        hud:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        hud:SetBackdropColor(0, 0, 0, 0.7)
    end

    hud.line1 = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hud.line1:SetPoint("TOP", 0, -6)
    hud.line2 = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.line2:SetPoint("TOP", hud.line1, "BOTTOM", 0, -3)
    hud.line3 = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.line3:SetPoint("TOP", hud.line2, "BOTTOM", 0, -2)
    hud.line4 = hud:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hud.line4:SetPoint("TOP", hud.line3, "BOTTOM", 0, -2)
    hud.line5 = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hud.line5:SetPoint("TOP", hud.line4, "BOTTOM", 0, -2)

    -- drag/resize hint (only visible when unlocked)
    hud.hint = hud:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hud.hint:SetPoint("BOTTOMLEFT", 6, 4)
    hud.hint:SetText("|cff555555drag · resize|r")

    -- resize grip (bottom-right)
    local grip = CreateFrame("Button", nil, hud)
    grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetSize(16, 16)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() if not db.hud.locked then hud:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        hud:StopMovingOrSizing()
        db.hud.w, db.hud.h = math.floor(hud:GetWidth()), math.floor(hud:GetHeight())
    end)
    hud.grip = grip

    -- live ticker so the elapsed time / rates update even without events
    hud.elapsed = 0
    hud:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1 then self.elapsed = 0; ns.RefreshHUD() end
    end)

    ApplyLock(hud, db.hud.locked)
    hud:Hide()
    return hud
end
ns.BuildHUD = Build

function ns.RefreshHUD()
    local hud = ns.hud
    if not hud then return end
    local _, kph, _, _, _, gph = ns.RecentRates()
    hud.line1:SetText("Session: |cffffd100" .. ns.session.count .. "|r")
    hud.line2:SetText(string.format("|cff00ff00%.0f|r KPH   %s", kph, ns.FormatTime(ns.SessionElapsed())))
    local xs = ns.XPStats()
    if xs then
        hud.line3:SetText(string.format("|cff66ccff%s|r xp/hr  TTL |cff66ccff%s|r",
            ns.CommaNum(xs.xph), xs.ttl and ns.FormatTime(xs.ttl) or "--"))
    else
        hud.line3:SetText("|cff808080max level|r")
    end
    hud.line4:SetText(ns.Money(gph) .. "/hr")

    -- Mobs to next level (optional, hidden at max level / before any XP sample)
    if ns.EnsureDB().showMobsToLevel and xs and xs.mobs then
        hud.line5:SetText("Mobs to lvl: |cffffd100" .. xs.mobs .. "|r")
        hud.line5:Show()
    else
        hud.line5:SetText("")
        hud.line5:Hide()
    end
end

function ns.ToggleHUD()
    Build()
    local db = ns.EnsureDB()
    if ns.hud:IsShown() then
        ns.hud:Hide(); db.hud.shown = false
    else
        ns.RefreshHUD(); ns.hud:Show(); db.hud.shown = true
    end
end

function ns.SetHUDLock(locked)
    local db = ns.EnsureDB()
    db.hud.locked = locked and true or false
    if ns.hud then ApplyLock(ns.hud, db.hud.locked) end
end

function ns.ToggleHUDLock()
    local db = ns.EnsureDB()
    ns.SetHUDLock(not db.hud.locked)
    ns.Print("HUD " .. (db.hud.locked and "locked." or "unlocked — drag to move, grip to resize."))
end

function ns.IsHUDLocked() return ns.EnsureDB().hud.locked end

function ns.SetHUDScale(scale)
    scale = tonumber(scale) or 1.0
    if scale < 0.5 then scale = 0.5 elseif scale > 2.0 then scale = 2.0 end
    ns.EnsureDB().hud.scale = scale
    if ns.hud then ns.hud:SetScale(scale) end
end

function ns.GetHUDScale() return ns.EnsureDB().hud.scale or 1.0 end

-- Recenter the HUD and forget the saved position.
function ns.ResetHUDPosition()
    local db = ns.EnsureDB()
    db.hud.point, db.hud.x, db.hud.y = nil, nil, nil
    if ns.hud then
        ns.hud:ClearAllPoints()
        ns.hud:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    ns.Print("HUD position reset.")
end

-- repaint immediately on data changes (the ticker handles idle updates)
ns.AddRefresher(function() if ns.hud and ns.hud:IsShown() then ns.RefreshHUD() end end)

ns.On("PLAYER_LOGIN", function()
    if ns.EnsureDB().hud.shown then Build(); ns.RefreshHUD(); ns.hud:Show() end
end)
