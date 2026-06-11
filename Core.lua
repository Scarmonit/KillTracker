-- Core.lua — addon namespace, shared utilities, widget helpers, and the
-- event/refresh plumbing every other module hooks into.
--
-- All modules share state through the second value of the addon vararg (`ns`),
-- so there are almost no globals. Load order (see the .toc): Core is first, then
-- Data, Stats, and the UI modules.

local ADDON, ns = ...
ns.name = ADDON

-- Global table used only by the wowUnit test suite (see KillTracker_Tests.lua).
KillTracker = KillTracker or {}
ns.api = KillTracker

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
ns.UNKNOWN = "Unknown"
ns.WHITE   = "Interface\\Buttons\\WHITE8X8"
ns.PREFIX  = "|cff33ff99Kill Tracker|r "

-- classification -> { r, g, b, short tag }
ns.CLS_COLOR = {
    rare      = { 0.64, 0.21, 0.93, "Rare" },   -- purple
    rareelite = { 0.64, 0.21, 0.93, "Rare+" },
    elite     = { 1.00, 0.82, 0.00, "Elite" },  -- gold
    worldboss = { 1.00, 0.50, 0.00, "Boss" },   -- orange
}

-- ---------------------------------------------------------------------------
-- Small utilities
-- ---------------------------------------------------------------------------
function ns.Print(msg)
    print(ns.PREFIX .. tostring(msg))
end

function ns.FormatTime(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 0 then sec = 0 end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm %02ds", m, sec % 60)
end

function ns.Money(copper)
    return GetCoinTextureString(math.max(0, math.floor(tonumber(copper) or 0)))
end

function ns.CommaNum(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- expose the pure helpers to the wowUnit test suite
ns.api.FormatTime = ns.FormatTime
ns.api.CommaNum   = ns.CommaNum

function ns.IsMaxLevel()
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    local max
    if GetMaxLevelForPlayerExpansion then max = GetMaxLevelForPlayerExpansion()
    elseif GetMaxPlayerLevel then max = GetMaxPlayerLevel() end
    return UnitLevel("player") >= (max or 999)
end

-- ---------------------------------------------------------------------------
-- Widget helpers (shared dark theme used by every panel)
-- ---------------------------------------------------------------------------
local WHITE = ns.WHITE

function ns.StylePanel(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.25, 0.27, 0.32, 1)
end

function ns.AddTitleBar(frame, text)
    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)
    bar:SetVertexColor(0.10, 0.45, 0.40, 0.85)
    bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(26)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOP", 0, -7); fs:SetText(text)
    fs:SetTextColor(1, 1, 1)
    return fs
end

function ns.AddDivider(frame, yOffset, inset)
    inset = inset or 12
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE); t:SetVertexColor(0.3, 0.32, 0.36, 0.8)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", inset, yOffset)
    t:SetPoint("TOPRIGHT", -inset, yOffset)
    return t
end

function ns.AddRowStripe(row, even)
    local t = row:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(WHITE); t:SetAllPoints(row)
    t:SetVertexColor(1, 1, 1, even and 0.04 or 0.0)
    row.stripe = t
end

-- Make a movable panel that remembers its position in `db` (keys point/x/y).
function ns.MakeMovable(frame, db)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if db then
            local p, _, _, x, y = self:GetPoint()
            db.point, db.x, db.y = p, x, y
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Event system: ns.On(event|{events}, handler). Handlers run in pcall so one
-- bad handler can't break the others.
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
ns._handlers = {}

function ns.On(event, fn)
    if type(event) == "table" then
        for _, e in ipairs(event) do ns.On(e, fn) end
        return
    end
    if not ns._handlers[event] then
        ns._handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(ns._handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local hs = ns._handlers[event]
    if not hs then return end
    for _, fn in ipairs(hs) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.Print("|cffff5555error|r (" .. event .. "): " .. tostring(err)) end
    end
end)

-- ---------------------------------------------------------------------------
-- Throttled refresh: data handlers call ns.Refresh(); UI modules register a
-- refresher via ns.AddRefresher. All registered refreshers run once, ~0.2s
-- after the first request in a burst, instead of once per event.
-- ---------------------------------------------------------------------------
ns._refreshers = {}
function ns.AddRefresher(fn) table.insert(ns._refreshers, fn) end

local dirty = false
local function doRefresh()
    dirty = false
    for _, fn in ipairs(ns._refreshers) do
        local ok, err = pcall(fn)
        if not ok then ns.Print("|cffff5555refresh error|r: " .. tostring(err)) end
    end
end

function ns.Refresh()
    if dirty then return end
    dirty = true
    C_Timer.After(0.2, doRefresh)
end

-- Cleanup hooks run when the player wipes all data (used to hide sub-panels).
ns._wipeHandlers = {}
function ns.AddWipeHandler(fn) table.insert(ns._wipeHandlers, fn) end
function ns.RunWipeHandlers()
    for _, fn in ipairs(ns._wipeHandlers) do pcall(fn) end
end

-- Welcome message once everything has loaded.
ns.On("PLAYER_LOGIN", function()
    ns.Print("loaded. |cffffff00/kt|r window · |cffffff00/kt hud|r HUD · |cffffff00/kt options|r · |cffffff00/kt help|r")
end)
