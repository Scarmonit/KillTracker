-- Kill Tracker
-- Counts every mob you (or your pet/minions) kill, grouped by name and creature
-- type. Adds per-session kills/XP/gold-per-hour, time-to-level, a tooltip kill
-- count, a searchable window, a live HUD, and a minimap button.

-- ---------------------------------------------------------------------------
-- Saved data (per character)
-- ---------------------------------------------------------------------------
local DB_VERSION = 1   -- bump when the saved schema changes; see MigrateDB

local function EnsureDB()
    KillTrackerDB = KillTrackerDB or {}
    local db = KillTrackerDB
    db.total   = db.total   or 0
    db.byName  = db.byName  or {}   -- name -> { count = n, ctype = "Beast" }
    db.byType  = db.byType  or {}
    db.hud     = db.hud     or { shown = false }
    db.minimap = db.minimap or { hide = false }
    db.window  = db.window  or 600   -- sliding rate window, seconds
    db.deaths  = db.deaths  or 0
    db.special = db.special or { rare = 0, elite = 0, boss = 0 }  -- lifetime counts
    db.history = db.history or {}    -- saved past sessions (newest first)
    return db
end

-- Run once at login. Add `if db.version < N then ... end` blocks here to migrate
-- old saved data when the schema changes, then bump DB_VERSION.
local function MigrateDB()
    local db = EnsureDB()
    db.version = db.version or DB_VERSION
    -- (no migrations yet)
    db.version = DB_VERSION
end

local MAX_HISTORY = 50

-- ---------------------------------------------------------------------------
-- Session state (runtime only)
-- ---------------------------------------------------------------------------
local session = { count = 0, start = nil, xp = 0, gold = 0, loot = 0,
                  levelStart = nil, levelKills = 0, deaths = 0, rep = 0 }
local xpLog, killLog, repLog, goldLog = {}, {}, {}, {}  -- timestamped rolling-rate samples
local RATE_WINDOW = 600         -- seconds; sliding window for "current pace"
local pendingXPMob, pendingXPTime   -- attribute the next XP gain to this mob

local function StartSession()
    if not session.start then session.start = GetTime() end
    if not session.levelStart then session.levelStart = GetTime() end
end

-- Derive current pace from a sliding window rather than the whole session.
-- Whole-session averages get diluted by travel/looting/vendoring/AFK, which is
-- exactly what made the old time-to-level estimate run long. A recent window
-- also self-corrects for rested XP as the bonus depletes.
local function PruneLog(log, now)
    local cutoff = now - RATE_WINDOW
    while log[1] and log[1].t < cutoff do table.remove(log, 1) end
end

local function SumLog(log)
    local s = 0
    for _, e in ipairs(log) do s = s + e.amt end
    return s
end

-- All "per hour" stats use the same sliding window so they stay consistent.
local function RecentRates()
    local now = GetTime()
    PruneLog(xpLog, now); PruneLog(killLog, now); PruneLog(repLog, now); PruneLog(goldLog, now)
    local span = session.start and math.min(RATE_WINDOW, now - session.start) or 0
    if span < 1 then return 0, 0, 0, 0, 0, 0 end
    local hours = span / 3600
    local xpSum, repSum, goldSum, kills = SumLog(xpLog), SumLog(repLog), SumLog(goldLog), #killLog
    local xph    = xpSum / hours
    local kph    = kills / hours
    local avgXP  = (kills > 0) and (xpSum / kills) or 0
    local reph   = repSum / hours
    local avgRep = (kills > 0) and (repSum / kills) or 0
    local gph    = goldSum / hours
    return xph, kph, avgXP, reph, avgRep, gph
end

local function SessionElapsed()
    return session.start and (GetTime() - session.start) or 0
end

local function PerHour(amount)
    local e = SessionElapsed()
    if e < 1 then return 0 end
    return amount / (e / 3600)
end

local function FormatTime(sec)
    sec = math.floor(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm %02ds", m, sec % 60)
end

local function Money(copper)
    return GetCoinTextureString(math.max(0, math.floor(copper)))
end

local function CommaNum(n)
    n = math.floor(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function IsMaxLevel()
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    local max
    if GetMaxLevelForPlayerExpansion then max = GetMaxLevelForPlayerExpansion()
    elseif GetMaxPlayerLevel then max = GetMaxPlayerLevel() end
    return UnitLevel("player") >= (max or 999)
end

-- ---------------------------------------------------------------------------
-- Creature-type cache (combat log gives GUID + name, not type)
-- ---------------------------------------------------------------------------
-- typeCache:  guid -> creature type        (for the "Type" column)
-- classCache: guid -> classification        (rare/elite/worldboss flagging)
-- nameCache:  guid -> name                  (to attribute looted drops to a mob)
local typeCache, classCache, nameCache, cacheCount, CACHE_CAP = {}, {}, {}, 0, 400
local lastKillName   -- fallback for attributing loot to a mob

local function CacheUnit(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    if not typeCache[guid] and not classCache[guid] then
        cacheCount = cacheCount + 1
        if cacheCount > CACHE_CAP then
            wipe(typeCache); wipe(classCache); wipe(nameCache); cacheCount = 0
        end
    end
    local ctype = UnitCreatureType(unit)
    if ctype then typeCache[guid] = ctype end
    local cls = UnitClassification(unit)        -- normal/rare/elite/rareelite/worldboss
    if cls and cls ~= "normal" then classCache[guid] = cls end
    nameCache[guid] = UnitName(unit)
end

-- ---------------------------------------------------------------------------
-- Kill recording
-- ---------------------------------------------------------------------------
local UNKNOWN = "Unknown"

-- map a raw classification to one of our three special buckets (or nil)
local function SpecialBucket(cls)
    if cls == "worldboss" then return "boss"
    elseif cls == "rare" or cls == "rareelite" then return "rare"
    elseif cls == "elite" then return "elite" end
    return nil
end

local function RecordKill(name, ctype, cls)
    local db = EnsureDB()
    name, ctype = name or UNKNOWN, ctype or UNKNOWN
    local entry = db.byName[name]
    if not entry then entry = { count = 0, ctype = ctype } ; db.byName[name] = entry end
    entry.count = entry.count + 1
    if entry.ctype == UNKNOWN and ctype ~= UNKNOWN then entry.ctype = ctype end
    if cls and cls ~= "normal" then entry.cls = cls end
    db.byType[ctype] = (db.byType[ctype] or 0) + 1
    db.total = db.total + 1

    local bucket = SpecialBucket(cls)
    if bucket then db.special[bucket] = (db.special[bucket] or 0) + 1 end

    StartSession()
    session.count = session.count + 1
    session.levelKills = session.levelKills + 1
    killLog[#killLog + 1] = { t = GetTime() }
    pendingXPMob, pendingXPTime = name, GetTime()   -- next XP gain belongs to this mob
end

local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

-- Coalesce event-driven refreshes: many events can fire per second while
-- grinding, but the UI only needs to repaint a few times a second. Mark dirty
-- and run one real refresh on a short timer instead of rebuilding per event.
local refreshDirty = false

local function DoRefresh()
    refreshDirty = false
    if KillTracker_UI and KillTracker_UI:IsShown() then KillTracker_RefreshUI() end
    if KillTracker_HUD and KillTracker_HUD:IsShown() then KillTracker_RefreshHUD() end
    if KillTracker_Drops and KillTracker_Drops:IsShown() then KillTracker_RefreshDrops() end
    if KillTracker_History and KillTracker_History:IsShown() then KillTracker_RefreshHistory() end
end

local function RefreshAll()
    if refreshDirty then return end
    refreshDirty = true
    C_Timer.After(0.2, DoRefresh)
end

local function HandleCombatLog()
    local _, subevent, _, _, _, sourceFlags, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if subevent ~= "PARTY_KILL" then return end
    if bit.band(sourceFlags or 0, MINE) == 0 then return end
    local kind = destGUID and strsplit("-", destGUID)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    RecordKill(destName, typeCache[destGUID], classCache[destGUID])
    nameCache[destGUID] = destName   -- keep name for loot attribution, drop type/class
    lastKillName = destName
    typeCache[destGUID] = nil
    classCache[destGUID] = nil
    RefreshAll()
end

-- ---------------------------------------------------------------------------
-- XP & gold tracking
-- ---------------------------------------------------------------------------
local lastXP, lastXPMax, lastMoney

local function HandleXP()
    local cur = UnitXP("player") or 0
    if lastXP == nil then lastXP, lastXPMax = cur, UnitXPMax("player"); return end
    local gained
    if cur >= lastXP then gained = cur - lastXP
    else gained = (lastXPMax - lastXP) + cur end  -- leveled within one update
    if gained > 0 then
        StartSession()
        session.xp = session.xp + gained
        xpLog[#xpLog + 1] = { t = GetTime(), amt = gained }
        -- attribute this XP to the mob just killed (skips quest turn-ins: no recent kill)
        if pendingXPMob and (GetTime() - (pendingXPTime or 0)) < 3 then
            local e = EnsureDB().byName[pendingXPMob]
            if e then
                e.xpTotal = (e.xpTotal or 0) + gained
                e.xpKills = (e.xpKills or 0) + 1
            end
            pendingXPMob = nil
        end
    end
    lastXP, lastXPMax = cur, UnitXPMax("player")
    RefreshAll()
end

-- ---------------------------------------------------------------------------
-- Reputation tracking (watched faction = the one shown on the rep bar)
-- ---------------------------------------------------------------------------
local lastWatchedRep, lastWatchedName

local function HandleFaction()
    if not GetWatchedFactionInfo then return end
    local name, _, _, _, barValue = GetWatchedFactionInfo()
    if not name or name == "" then
        lastWatchedName, lastWatchedRep = nil, nil
        return
    end
    if name == lastWatchedName and lastWatchedRep then
        local delta = barValue - lastWatchedRep
        if delta > 0 then
            StartSession()
            session.rep = session.rep + delta
            repLog[#repLog + 1] = { t = GetTime(), amt = delta }
            RefreshAll()
        end
    end
    lastWatchedName, lastWatchedRep = name, barValue
end

local function HandleMoney()
    local cur = GetMoney() or 0
    if lastMoney == nil then lastMoney = cur; return end
    local delta = cur - lastMoney
    lastMoney = cur
    if delta > 0 then
        StartSession()
        session.gold = session.gold + delta
        goldLog[#goldLog + 1] = { t = GetTime(), amt = delta }
        RefreshAll()
    end
end

-- Resolve which mob a loot slot came from. Prefer the loot source GUID; fall
-- back to a dead creature target, then to the most recently killed mob (covers
-- single-target grinding and auto-loot where source info may be unavailable).
local function ResolveLootMob(slot)
    local sources = { GetLootSourceInfo and GetLootSourceInfo(slot) }
    for i = 1, #sources, 2 do
        local guid = sources[i]
        local kind = guid and strsplit("-", guid)
        if guid and (kind == "Creature" or kind == "Vehicle") then
            local mob = nameCache[guid]
            if mob then return mob, sources[i + 1] end
        end
    end
    local tguid = UnitGUID("target")
    if tguid then
        local kind = strsplit("-", tguid)
        if (kind == "Creature" or kind == "Vehicle") and UnitIsDead("target") then
            return nameCache[tguid] or UnitName("target")
        end
    end
    return lastKillName
end

-- Record one looted item against a mob's drop table. Returns false if the mob
-- has no kill entry yet. Kept separate so it can be unit-tested directly.
local function RecordDrop(mob, itemName, qty, link, quality)
    local entry = EnsureDB().byName[mob]
    if not entry then return false end
    entry.drops = entry.drops or {}
    local d = entry.drops[itemName]
    if not d then d = { n = 0, q = 0 }; entry.drops[itemName] = d end
    d.n = d.n + 1                  -- corpses that yielded this item
    d.q = d.q + (qty or 1)         -- total quantity looted
    d.link, d.quality = link, quality
    return true
end

-- Attribute looted items to the creature that dropped them.
local lootProcessed = false
local function HandleLootOpened()
    if lootProcessed or not GetNumLootItems then return end
    local num = GetNumLootItems()
    if num == 0 then return end
    local ITEM = (type(LOOT_SLOT_ITEM) == "number") and LOOT_SLOT_ITEM or 1

    for slot = 1, num do
        local link = GetLootSlotLink(slot)
        local slotType = GetLootSlotType and GetLootSlotType(slot)
        -- treat as an item if it has an item link and isn't explicitly money/currency
        if link and (slotType == nil or slotType == ITEM) then
            local _, itemName, slotQty, _, quality = GetLootSlotInfo(slot)
            if itemName then
                local mob, q = ResolveLootMob(slot)
                q = q or slotQty or 1
                if mob then RecordDrop(mob, itemName, q, link, quality) end
                -- accumulate vendor value here (locale-independent; replaces the
                -- old English-only CHAT_MSG_LOOT parse)
                local sell = select(11, GetItemInfo(link))
                if sell and sell > 0 then
                    StartSession()
                    session.loot = session.loot + sell * q
                    goldLog[#goldLog + 1] = { t = GetTime(), amt = sell * q }
                end
            end
        end
    end
    lootProcessed = true
    RefreshAll()
end

local function HandleDeath()
    local db = EnsureDB()
    db.deaths = db.deaths + 1
    session.deaths = session.deaths + 1
    RefreshAll()
end

-- average XP per kill for a specific mob (per-mob tracking), or nil
local function MobAvgXP(name)
    local e = name and EnsureDB().byName[name]
    if e and e.xpKills and e.xpKills > 0 then return e.xpTotal / e.xpKills end
    return nil
end

-- XP-derived projections
local function XPStats()
    if IsMaxLevel() then return nil end
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local remaining = max - cur
    local xph, _, avg = RecentRates()                          -- recent-window pace
    local ttl = (xph > 0) and (remaining / xph * 3600) or nil  -- seconds
    -- prefer the per-mob average of the mob you're actually farming
    local perMob = MobAvgXP(lastKillName)
    local useAvg = perMob or avg
    local mobs = (useAvg > 0) and math.ceil(remaining / useAvg) or nil
    return { remaining = remaining, xph = xph, ttl = ttl, mobs = mobs,
             rested = (GetXPExhaustion and GetXPExhaustion()) or 0 }
end

-- reputation projections for the watched faction, or nil if none watched
local function RepStats()
    if not GetWatchedFactionInfo then return nil end
    local name, standingID, barMin, barMax, barValue = GetWatchedFactionInfo()
    if not name or name == "" then return nil end
    local remaining = barMax - barValue
    local _, _, _, reph, avgRep = RecentRates()
    local ttl  = (reph > 0) and (remaining / reph * 3600) or nil
    local kills = (avgRep > 0) and math.ceil(remaining / avgRep) or nil
    local standing = _G["FACTION_STANDING_LABEL" .. (standingID or 0)] or ""
    return { name = name, standing = standing, remaining = remaining,
             cur = barValue - barMin, total = barMax - barMin,
             reph = reph, ttl = ttl, kills = kills }
end

-- ---------------------------------------------------------------------------
-- Sorted snapshot
-- ---------------------------------------------------------------------------
local searchText = ""

-- color + short tag for a classification
local CLS_COLOR = {
    rare      = { 0.64, 0.21, 0.93, "Rare" },   -- purple
    rareelite = { 0.64, 0.21, 0.93, "Rare+" },
    elite     = { 1.00, 0.82, 0.00, "Elite" },  -- gold
    worldboss = { 1.00, 0.50, 0.00, "Boss" },   -- orange
}

local sortKey, sortDir = "count", -1   -- column + direction (1 asc, -1 desc)

local function GetSorted()
    local db = EnsureDB()
    local list = {}
    for name, entry in pairs(db.byName) do
        if searchText == "" or name:lower():find(searchText, 1, true) then
            list[#list+1] = { name = name, count = entry.count, ctype = entry.ctype,
                              cls = entry.cls, drops = entry.drops }
        end
    end
    table.sort(list, function(a, b)
        local av, bv
        if sortKey == "name" then av, bv = a.name, b.name
        elseif sortKey == "ctype" then av, bv = (a.ctype or ""), (b.ctype or "")
        else av, bv = a.count, b.count end
        if av == bv then return a.name < b.name end   -- stable tiebreak
        if sortDir == 1 then return av < bv else return av > bv end
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Tooltip kill count
-- ---------------------------------------------------------------------------
local function AddTooltipKills(tooltip, unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    CacheUnit(unit)
    local name = UnitName(unit)
    if not name then return end
    local entry = EnsureDB().byName[name]
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
    else
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
            local _, u = tt:GetUnit(); AddTooltipKills(tt, u)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Shared modern styling: opaque dark panel + helpers
-- ---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- flat dark panel with a thin border (no parchment, no world bleed-through)
local function StylePanel(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.25, 0.27, 0.32, 1)
end

-- title bar strip across the top of a panel; returns the title fontstring
local function AddTitleBar(frame, text)
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

-- thin horizontal divider line at the given y offset from the top
local function AddDivider(frame, yOffset, inset)
    inset = inset or 12
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE); t:SetVertexColor(0.3, 0.32, 0.36, 0.8)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", inset, yOffset)
    t:SetPoint("TOPRIGHT", -inset, yOffset)
    return t
end

-- subtle zebra stripe behind a list row
local function AddRowStripe(row, even)
    local t = row:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(WHITE); t:SetAllPoints(row)
    t:SetVertexColor(1, 1, 1, even and 0.04 or 0.0)
    row.stripe = t
end

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
local ROW_HEIGHT, NUM_ROWS = 18, 14

local function BuildUI()
    if KillTracker_UI then return KillTracker_UI end

    local frame = CreateFrame("Frame", "KillTracker_UI", UIParent, "BackdropTemplate")
    frame:SetSize(340, 488)
    frame:SetPoint("CENTER")
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    StylePanel(frame)
    AddTitleBar(frame, "Kill Tracker")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- stat block (evenly spaced, no overlap)
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

    AddDivider(frame, -116)

    -- search box with greyed placeholder + History button on the same row
    local search = CreateFrame("EditBox", "KillTracker_Search", frame, "InputBoxTemplate")
    search:SetSize(232, 20); search:SetPoint("TOPLEFT", 16, -124); search:SetAutoFocus(false)
    search:SetTextInsets(6, 6, 0, 0)
    local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 8, 0); ph:SetText("Search mobs..."); ph:SetTextColor(0.5, 0.5, 0.5)
    search.placeholder = ph
    search:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower()
        ph:SetShown(self:GetText() == "")
        KillTracker_RefreshUI()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    local histBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    histBtn:SetSize(70, 22); histBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    histBtn:SetText("History")
    histBtn:SetScript("OnClick", function() KillTracker_ShowHistory() end)

    -- clickable column headers (sort) + divider
    frame.hName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.hName:SetPoint("TOPLEFT", 16, -152)
    frame.hType = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.hType:SetPoint("TOPLEFT", 188, -152)
    frame.hKills = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.hKills:SetPoint("TOPRIGHT", -34, -152)

    local function headerButton(key, tl_x, w)
        local b = CreateFrame("Button", nil, frame)
        b:SetPoint("TOPLEFT", tl_x, -150); b:SetSize(w, 16)
        b:SetScript("OnClick", function() KillTracker_SetSort(key) end)
    end
    headerButton("name", 14, 150)
    headerButton("ctype", 186, 70)
    headerButton("count", 270, 50)
    AddDivider(frame, -166)

    local scroll = CreateFrame("ScrollFrame", "KillTracker_Scroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -170)
    scroll:SetPoint("BOTTOMRIGHT", -28, 58)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, KillTracker_RefreshUI)
    end)
    frame.scroll = scroll

    frame.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(296, ROW_HEIGHT)
        if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else row:SetPoint("TOPLEFT", frame.rows[i-1], "BOTTOMLEFT", 0, 0) end
        AddRowStripe(row, i % 2 == 0)
        row:SetHighlightTexture(WHITE, "ADD")
        if row:GetHighlightTexture() then row:GetHighlightTexture():SetVertexColor(0.3, 0.5, 0.9, 0.25) end
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(176); row.name:SetJustifyH("LEFT")
        row.type = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.type:SetPoint("LEFT", 182, 0); row.type:SetWidth(78); row.type:SetJustifyH("LEFT")
        row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.kills:SetPoint("RIGHT", -6, 0); row.kills:SetWidth(40); row.kills:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.mob then KillTracker_ShowDrops(self.mob) end
        end)
        frame.rows[i] = row
    end

    -- footer hint + buttons
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 40); hint:SetText("|cff707070click a mob to see its drops|r")

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(82, 22); reset:SetPoint("BOTTOMLEFT", 12, 12); reset:SetText("Reset All")
    reset:SetScript("OnClick", function() StaticPopup_Show("KILLTRACKER_RESET") end)
    local hudBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    hudBtn:SetSize(92, 22); hudBtn:SetPoint("BOTTOM", 0, 12); hudBtn:SetText("Toggle HUD")
    hudBtn:SetScript("OnClick", function() KillTracker_ToggleHUD() end)
    local sesBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sesBtn:SetSize(112, 22); sesBtn:SetPoint("BOTTOMRIGHT", -12, 12); sesBtn:SetText("Reset Session")
    sesBtn:SetScript("OnClick", function() KillTracker_ResetSession() end)

    frame:Hide()
    return frame
end

local function HeaderLabel(base, key)
    if key ~= sortKey then return base end
    return base .. (sortDir == 1 and " |cffffd100^|r" or " |cffffd100v|r")
end

function KillTracker_RefreshUI()
    local frame = KillTracker_UI
    if not frame then return end
    local db = EnsureDB()
    local list = GetSorted()

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
    local _, kph = RecentRates()
    frame.sessionText:SetText(string.format(
        "Session: |cffffd100%d|r kills  |  |cffffd100%.0f|r KPH  |  %s  |  |cffff5555%d|r deaths",
        session.count, kph, FormatTime(SessionElapsed()), session.deaths))

    local xs = XPStats()
    if xs then
        local ttl = xs.ttl and FormatTime(xs.ttl) or "--"
        local mobs = xs.mobs and tostring(xs.mobs) or "--"
        local rested = (xs.rested > 0) and ("  |cffff80ff+" .. CommaNum(xs.rested) .. " rested|r") or ""
        frame.xpText:SetText(string.format(
            "XP |cff66ccff%s|r/hr · to level |cff66ccff%s|r · |cff66ccff%s|r mobs%s",
            CommaNum(xs.xph), ttl, mobs, rested))
    else
        frame.xpText:SetText("|cff808080Max level — XP tracking off|r")
    end

    local earned = session.gold + session.loot
    local _, _, _, _, _, gph = RecentRates()
    frame.goldText:SetText("Gold: " .. Money(gph) .. "/hr  ( " .. Money(earned) .. " )")

    local rs = RepStats()
    if rs then
        local ttl = rs.ttl and FormatTime(rs.ttl) or "--"
        local kills = rs.kills and tostring(rs.kills) or "--"
        frame.repText:SetText(string.format(
            "|cffff80ff%s|r %s · |cffff80ff%s|r/hr · to next |cffff80ff%s|r · |cffff80ff%s|r kills",
            rs.name, rs.standing, CommaNum(rs.reph), ttl, kills))
    else
        frame.repText:SetText("|cff606060No watched faction|r")
    end

    local offset = FauxScrollFrame_GetOffset(frame.scroll)
    for i = 1, NUM_ROWS do
        local row, data = frame.rows[i], list[i + offset]
        if data then
            local c = data.cls and CLS_COLOR[data.cls]
            if c then row.name:SetTextColor(c[1], c[2], c[3])
            else row.name:SetTextColor(1, 1, 1) end
            local mark = c and (" |cff" .. string.format("%02x%02x%02x",
                math.floor(c[1]*255), math.floor(c[2]*255), math.floor(c[3]*255)) .. "[" .. c[4] .. "]|r") or ""
            row.name:SetText(data.name .. mark)
            row.type:SetText(data.ctype ~= UNKNOWN and data.ctype or "")
            row.kills:SetText(data.count)
            row.mob = data.name
            row:Show()
        else row:Hide(); row.mob = nil end
    end
    FauxScrollFrame_Update(frame.scroll, #list, NUM_ROWS, ROW_HEIGHT)
end

-- click a column header: toggle direction if same column, else sort by it
-- (counts default to descending, text columns to ascending)
function KillTracker_SetSort(key)
    if key == sortKey then sortDir = -sortDir
    else sortKey, sortDir = key, (key == "count") and -1 or 1 end
    KillTracker_RefreshUI()
end

local function ToggleUI()
    BuildUI()
    if KillTracker_UI:IsShown() then KillTracker_UI:Hide()
    else KillTracker_RefreshUI(); KillTracker_UI:Show() end
end

-- ---------------------------------------------------------------------------
-- Drops panel (per-mob loot with drop %)
-- ---------------------------------------------------------------------------
local DROP_ROWS = 12
local currentDropMob

local function BuildDrops()
    if KillTracker_Drops then return KillTracker_Drops end

    local f = CreateFrame("Frame", "KillTracker_Drops", UIParent, "BackdropTemplate")
    f:SetSize(360, 340); f:SetPoint("CENTER", 360, 0)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    StylePanel(f)
    f.title = AddTitleBar(f, "Drops")   -- updated with the mob name on open

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
    AddDivider(f, -66)

    local scroll = CreateFrame("ScrollFrame", "KillTracker_DropScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -70); scroll:SetPoint("BOTTOMRIGHT", -28, 14)
    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_HEIGHT, KillTracker_RefreshDrops)
    end)
    f.scroll = scroll

    f.rows = {}
    for i = 1, DROP_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(316, ROW_HEIGHT)
        if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else row:SetPoint("TOPLEFT", f.rows[i-1], "BOTTOMLEFT", 0, 0) end
        AddRowStripe(row, i % 2 == 0)
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
        -- show item tooltip on hover
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

function KillTracker_RefreshDrops()
    local f = KillTracker_Drops
    if not f or not currentDropMob then return end
    local entry = EnsureDB().byName[currentDropMob]
    local drops = entry and entry.drops

    f.title:SetText(currentDropMob)
    local kills = entry and entry.count or 0

    local list, totalValue = {}, 0
    if drops then
        for itemName, d in pairs(drops) do
            local sell = select(11, GetItemInfo(d.link or itemName)) or 0
            local value = sell * d.q
            totalValue = totalValue + value
            list[#list+1] = { name = itemName, n = d.n, q = d.q, link = d.link,
                              quality = d.quality, value = value,
                              rate = (kills > 0) and (d.n / kills * 100) or 0 }
        end
    end
    table.sort(list, function(a, b) return a.rate > b.rate end)

    local avgXP = MobAvgXP(currentDropMob)
    local avgStr = avgXP and ("  ·  " .. CommaNum(avgXP) .. " avg XP") or ""
    local valStr = (totalValue > 0) and ("  ·  " .. Money(totalValue)) or ""
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
            row.value:SetText(data.value > 0 and Money(data.value) or "")
            row.rate:SetText(string.format("%.0f%%", data.rate))
            row.link = data.link
            row:Show()
        else row:Hide(); row.link = nil end
    end
    FauxScrollFrame_Update(f.scroll, #list, DROP_ROWS, ROW_HEIGHT)
end

function KillTracker_ShowDrops(mob)
    BuildDrops()
    currentDropMob = mob
    KillTracker_RefreshDrops()
    KillTracker_Drops:Show()
end

-- ---------------------------------------------------------------------------
-- Session history panel
-- ---------------------------------------------------------------------------
local HIST_ROWS = 14

local function BuildHistory()
    if KillTracker_History then return KillTracker_History end

    local f = CreateFrame("Frame", "KillTracker_History", UIParent, "BackdropTemplate")
    f:SetSize(380, 360); f:SetPoint("CENTER", -370, 0)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    StylePanel(f)
    AddTitleBar(f, "Session History")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOP", 0, -34)

    -- headers
    local cols = { {"When", 14, "LEFT"}, {"Time", 92, "LEFT"}, {"Kills", 150, "LEFT"},
                   {"XP", 210, "LEFT"}, {"Gold", 286, "LEFT"}, {"Deaths", -14, "RIGHT"} }
    for _, c in ipairs(cols) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if c[3] == "RIGHT" then h:SetPoint("TOPRIGHT", c[2], -52) else h:SetPoint("TOPLEFT", c[2], -52) end
        h:SetText(c[1])
    end
    AddDivider(f, -66)

    local scroll = CreateFrame("ScrollFrame", "KillTracker_HistScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -70); scroll:SetPoint("BOTTOMRIGHT", -28, 14)
    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_HEIGHT, KillTracker_RefreshHistory)
    end)
    f.scroll = scroll

    f.rows = {}
    for i = 1, HIST_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(336, ROW_HEIGHT)
        if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else row:SetPoint("TOPLEFT", f.rows[i-1], "BOTTOMLEFT", 0, 0) end
        AddRowStripe(row, i % 2 == 0)
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

function KillTracker_RefreshHistory()
    local f = KillTracker_History
    if not f then return end
    local hist = EnsureDB().history

    f.sub:SetText(#hist .. " saved sessions (newest first)")
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    for i = 1, HIST_ROWS do
        local row, h = f.rows[i], hist[i + offset]
        if h then
            row.when:SetText(h.when or "?")
            row.time:SetText(FormatTime(h.dur or 0))
            row.kills:SetText(h.kills or 0)
            row.xp:SetText("|cff66ccff" .. CommaNum(h.xp or 0) .. "|r")
            row.gold:SetText(Money(h.gold or 0))
            row.deaths:SetText((h.deaths and h.deaths > 0) and ("|cffff5555" .. h.deaths .. "|r") or "0")
            row:Show()
        else row:Hide() end
    end
    FauxScrollFrame_Update(f.scroll, #hist, HIST_ROWS, ROW_HEIGHT)
end

function KillTracker_ShowHistory()
    BuildHistory()
    KillTracker_RefreshHistory()
    KillTracker_History:Show()
end

-- ---------------------------------------------------------------------------
-- Live HUD
-- ---------------------------------------------------------------------------
local function BuildHUD()
    if KillTracker_HUD then return KillTracker_HUD end
    local db = EnsureDB()

    local hud = CreateFrame("Frame", "KillTracker_HUD", UIParent, "BackdropTemplate")
    hud:SetSize(180, 82)
    if db.hud.point then hud:SetPoint(db.hud.point, UIParent, db.hud.point, db.hud.x or 0, db.hud.y or 0)
    else hud:SetPoint("TOP", 0, -160) end
    hud:SetMovable(true); hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", hud.StartMoving)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        db.hud.point, db.hud.x, db.hud.y = p, x, y
    end)
    hud:SetClampedToScreen(true)
    if hud.SetBackdrop then
        hud:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        hud:SetBackdropColor(0, 0, 0, 0.7)
    end

    hud.line1 = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal");        hud.line1:SetPoint("TOP", 0, -6)
    hud.line2 = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hud.line2:SetPoint("TOP", hud.line1, "BOTTOM", 0, -3)
    hud.line3 = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hud.line3:SetPoint("TOP", hud.line2, "BOTTOM", 0, -2)
    hud.line4 = hud:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");   hud.line4:SetPoint("TOP", hud.line3, "BOTTOM", 0, -2)

    hud.elapsed = 0
    hud:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1 then self.elapsed = 0; KillTracker_RefreshHUD() end
    end)
    hud:Hide()
    return hud
end

function KillTracker_RefreshHUD()
    local hud = KillTracker_HUD
    if not hud then return end
    local _, kph, _, _, _, gph = RecentRates()
    hud.line1:SetText("Session: |cffffd100" .. session.count .. "|r")
    hud.line2:SetText(string.format("|cff00ff00%.0f|r KPH   %s", kph, FormatTime(SessionElapsed())))
    local xs = XPStats()
    if xs then
        hud.line3:SetText(string.format("|cff66ccff%s|r xp/hr  TTL |cff66ccff%s|r",
            CommaNum(xs.xph), xs.ttl and FormatTime(xs.ttl) or "--"))
    else
        hud.line3:SetText("|cff808080max level|r")
    end
    hud.line4:SetText(Money(gph) .. "/hr")
end

function KillTracker_ToggleHUD()
    BuildHUD()
    local db = EnsureDB()
    if KillTracker_HUD:IsShown() then KillTracker_HUD:Hide(); db.hud.shown = false
    else KillTracker_RefreshHUD(); KillTracker_HUD:Show(); db.hud.shown = true end
end

-- ---------------------------------------------------------------------------
-- Minimap button / broker (LibDataBroker + LibDBIcon for ecosystem interop:
-- the LDB object also shows up in Titan Panel, Bazooka, ChocolateBar, etc.)
-- ---------------------------------------------------------------------------
local LDB     = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)

local function SetupBroker()
    if not LDB or KillTracker_Broker then return end
    KillTracker_Broker = LDB:NewDataObject("KillTracker", {
        type  = "launcher",
        label = "Kill Tracker",
        icon  = "Interface\\Icons\\Ability_Rogue_Eviscerate",
        OnClick = function(_, button)
            if button == "RightButton" then KillTracker_ToggleHUD() else ToggleUI() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Kill Tracker")
            tt:AddDoubleLine("Total kills:", EnsureDB().total, 1,1,1, 1,0.82,0)
            local _, kph = RecentRates()
            tt:AddDoubleLine("Session:", string.format("%d  (%.0f KPH)", session.count, kph), 1,1,1, 1,0.82,0)
            local xs = XPStats()
            if xs then tt:AddDoubleLine("To level:", xs.ttl and FormatTime(xs.ttl) or "--", 1,1,1, 0.4,0.8,1) end
            tt:AddLine(" ")
            tt:AddLine("|cffeda55fLeft-click|r open window", 0.6,0.6,0.6)
            tt:AddLine("|cffeda55fRight-click|r toggle HUD", 0.6,0.6,0.6)
        end,
    })
    if LDBIcon then LDBIcon:Register("KillTracker", KillTracker_Broker, EnsureDB().minimap) end
end

function KillTracker_ToggleMinimap()
    local db = EnsureDB()
    db.minimap.hide = not db.minimap.hide
    if LDBIcon then
        if db.minimap.hide then LDBIcon:Hide("KillTracker") else LDBIcon:Show("KillTracker") end
    else
        print("|cff33ff99Kill Tracker|r minimap library not loaded.")
    end
end

-- ---------------------------------------------------------------------------
-- Session history + reset + popup
-- ---------------------------------------------------------------------------
-- Save the current session to history (newest first) if it had any activity.
local function SaveSession()
    if not session.start then return end
    if session.count == 0 and session.xp == 0 then return end
    local db = EnsureDB()
    table.insert(db.history, 1, {
        when    = date("%m/%d %H:%M"),
        dur     = SessionElapsed(),
        kills   = session.count,
        xp      = session.xp,
        gold    = session.gold + session.loot,
        rep     = session.rep,
        deaths  = session.deaths,
    })
    while #db.history > MAX_HISTORY do table.remove(db.history) end
end

function KillTracker_ResetSession()
    SaveSession()
    session.count, session.start, session.xp, session.gold, session.loot = 0, nil, 0, 0, 0
    session.levelStart, session.levelKills, session.deaths, session.rep = nil, 0, 0, 0
    wipe(xpLog); wipe(killLog); wipe(repLog); wipe(goldLog)
    if KillTracker_History and KillTracker_History:IsShown() then KillTracker_RefreshHistory() end
    RefreshAll()
    print("|cff33ff99Kill Tracker|r session saved to history and reset.")
end

StaticPopupDialogs["KILLTRACKER_RESET"] = {
    text = "Reset ALL Kill Tracker data for this character?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        KillTrackerDB = nil; EnsureDB()
        -- clear the runtime session WITHOUT saving into the freshly-wiped history
        session.count, session.start, session.xp, session.gold, session.loot = 0, nil, 0, 0, 0
        session.levelStart, session.levelKills, session.deaths, session.rep = nil, 0, 0, 0
        wipe(xpLog); wipe(killLog); wipe(repLog); wipe(goldLog)
        wipe(typeCache); wipe(classCache); wipe(nameCache); cacheCount = 0
        if KillTracker_Drops then KillTracker_Drops:Hide() end
        if KillTracker_History then KillTracker_History:Hide() end
        RefreshAll()
        print("|cff33ff99Kill Tracker|r all data reset.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local function PrintTop(n)
    local list, db = GetSorted(), EnsureDB()
    print("|cff33ff99Kill Tracker|r  total |cffffd100" .. db.total .. "|r  | session |cffffd100" ..
        session.count .. "|r (" .. string.format("%.0f", PerHour(session.count)) .. " KPH)")
    local xs = XPStats()
    if xs then print(string.format("  XP %s/hr | to level %s | %s mobs | %s/hr",
        CommaNum(xs.xph), xs.ttl and FormatTime(xs.ttl) or "--", xs.mobs or "--",
        Money(PerHour(session.gold + session.loot)))) end
    for i = 1, math.min(n, #list) do
        local d = list[i]
        local t = d.ctype ~= UNKNOWN and (" |cff808080(" .. d.ctype .. ")|r") or ""
        print(string.format("  %2d. %s%s  x|cffffd100%d|r", i, d.name, t, d.count))
    end
    if #list == 0 then print("  No kills recorded yet.") end
end

SLASH_KILLTRACKER1 = "/kt"
SLASH_KILLTRACKER2 = "/killtracker"
SlashCmdList["KILLTRACKER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then ToggleUI()
    elseif msg == "show" or msg == "top" then PrintTop(10)
    elseif msg == "hud" then KillTracker_ToggleHUD()
    elseif msg == "minimap" then KillTracker_ToggleMinimap()
    elseif msg == "history" or msg == "hist" then KillTracker_ShowHistory()
    elseif msg == "session" then KillTracker_ResetSession()
    elseif msg == "reset" then StaticPopup_Show("KILLTRACKER_RESET")
    elseif msg:find("^window") then
        local n = tonumber(msg:match("(%d+)"))
        if n and n >= 1 then
            RATE_WINDOW = n * 60
            EnsureDB().window = RATE_WINDOW
            RefreshAll()
            print("|cff33ff99Kill Tracker|r pace window set to |cffffd100" .. n .. "|r min.")
        else
            print("|cff33ff99Kill Tracker|r usage: |cffffff00/kt window <minutes>|r (current " .. (RATE_WINDOW / 60) .. " min)")
        end
    else
        print("|cff33ff99Kill Tracker|r commands:")
        print("  |cffffff00/kt|r          - toggle the window")
        print("  |cffffff00/kt hud|r      - toggle the live session HUD")
        print("  |cffffff00/kt minimap|r  - show/hide the minimap button")
        print("  |cffffff00/kt history|r  - open saved session history")
        print("  |cffffff00/kt window N|r - set the pace window for XP/hr & ETA (minutes)")
        print("  |cffffff00/kt show|r     - print top 10 + rates to chat")
        print("  |cffffff00/kt session|r  - save & reset session (kills/XP/gold/rep)")
        print("  |cffffff00/kt reset|r    - wipe all data (confirm)")
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "COMBAT_LOG_EVENT_UNFILTERED",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "PLAYER_XP_UPDATE", "PLAYER_MONEY", "PLAYER_LEVEL_UP",
    "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_DEAD",
    "UPDATE_FACTION", "PLAYER_LOGOUT",
}) do f:RegisterEvent(e) end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then HandleCombatLog()
    elseif event == "PLAYER_TARGET_CHANGED" then CacheUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then CacheUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then CacheUnit(arg1)
    elseif event == "PLAYER_XP_UPDATE" then HandleXP()
    elseif event == "PLAYER_MONEY" then HandleMoney()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then HandleLootOpened()
    elseif event == "LOOT_CLOSED" then lootProcessed = false
    elseif event == "PLAYER_DEAD" then HandleDeath()
    elseif event == "UPDATE_FACTION" then HandleFaction()
    elseif event == "PLAYER_LOGOUT" then SaveSession()
    elseif event == "PLAYER_LEVEL_UP" then
        local secs = session.levelStart and (GetTime() - session.levelStart) or 0
        print(string.format("|cff33ff99Kill Tracker|r Level |cffffd100%s|r! %d kills in %s this level.",
            tostring(arg1), session.levelKills, FormatTime(secs)))
        session.levelStart, session.levelKills = GetTime(), 0
        RefreshAll()
    elseif event == "PLAYER_ENTERING_WORLD" then
        lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
        lastMoney = GetMoney()
        if GetWatchedFactionInfo then
            local n, _, _, _, v = GetWatchedFactionInfo()
            lastWatchedName, lastWatchedRep = n, v
        end
    elseif event == "PLAYER_LOGIN" then
        MigrateDB()
        local db = EnsureDB()
        RATE_WINDOW = db.window or 600
        HookTooltips()
        SetupBroker()
        if db.hud.shown then BuildHUD(); KillTracker_RefreshHUD(); KillTracker_HUD:Show() end
        print("|cff33ff99Kill Tracker|r loaded. |cffffff00/kt|r window · |cffffff00/kt hud|r HUD · |cffffff00/kt help|r commands.")
    end
end)

-- ---------------------------------------------------------------------------
-- Internal API export (for the WoWUnit test suite in KillTracker_Tests.lua)
-- ---------------------------------------------------------------------------
KillTracker = KillTracker or {}
local KT = KillTracker
KT.FormatTime    = FormatTime
KT.CommaNum      = CommaNum
KT.SpecialBucket = SpecialBucket
KT.EnsureDB      = EnsureDB
KT.RecordKill    = RecordKill
KT.RecordDrop    = RecordDrop
KT.ResolveLootMob = ResolveLootMob
KT.MobAvgXP      = MobAvgXP
KT.SaveSession   = SaveSession

-- snapshot/restore runtime session state so tests are non-destructive
function KT._snapSession()
    local s = {};  for k, v in pairs(session) do s[k] = v end
    local xl = {}; for i, v in ipairs(xpLog)   do xl[i] = v end
    local kl = {}; for i, v in ipairs(killLog) do kl[i] = v end
    local rl = {}; for i, v in ipairs(repLog)  do rl[i] = v end
    local gl = {}; for i, v in ipairs(goldLog) do gl[i] = v end
    return { s = s, xl = xl, kl = kl, rl = rl, gl = gl }
end
function KT._restoreSession(snap)
    wipe(session); for k, v in pairs(snap.s)  do session[k] = v end
    wipe(xpLog);   for i, v in ipairs(snap.xl) do xpLog[i] = v end
    wipe(killLog); for i, v in ipairs(snap.kl) do killLog[i] = v end
    wipe(repLog);  for i, v in ipairs(snap.rl) do repLog[i] = v end
    wipe(goldLog); for i, v in ipairs(snap.gl) do goldLog[i] = v end
end
