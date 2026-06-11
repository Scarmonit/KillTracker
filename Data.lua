-- Data.lua — saved variables, runtime session state, the kill/loot/xp/money/
-- faction/death recorders, and the events that feed them. This is the only
-- module that mutates the database and session tables.

local _, ns = ...
local Print = ns.Print

local DB_VERSION  = 1     -- bump when the saved schema changes (see MigrateDB)
local MAX_HISTORY = 50

-- ---------------------------------------------------------------------------
-- Saved variables (per character)
-- ---------------------------------------------------------------------------
local function EnsureDB()
    KillTrackerDB = KillTrackerDB or {}
    local db = KillTrackerDB
    db.total   = db.total   or 0
    db.byName  = db.byName  or {}   -- name -> { count, ctype, cls, drops, xpTotal, xpKills }
    db.byType  = db.byType  or {}   -- creature type -> count
    db.special = db.special or { rare = 0, elite = 0, boss = 0 }
    db.history = db.history or {}    -- saved sessions, newest first
    db.window  = db.window  or 600   -- sliding rate window, seconds
    db.deaths  = db.deaths  or 0
    db.announceLevel = (db.announceLevel == nil) and true or db.announceLevel
    db.hud     = db.hud     or {}
    if db.hud.shown  == nil then db.hud.shown  = false end
    if db.hud.locked == nil then db.hud.locked = false end
    db.minimap = db.minimap or { hide = false }
    return db
end
ns.EnsureDB = EnsureDB
ns.api.EnsureDB = EnsureDB

-- Run once at login. Add `if db.version < N then ... end` blocks here and bump
-- DB_VERSION to migrate old saved data without wiping it.
local function MigrateDB()
    local db = EnsureDB()
    db.version = db.version or DB_VERSION
    -- (no migrations yet)
    db.version = DB_VERSION
end

-- ---------------------------------------------------------------------------
-- Runtime session state (never saved directly; summarized into history)
-- ---------------------------------------------------------------------------
local session = { count = 0, start = nil, xp = 0, gold = 0, loot = 0,
                  levelStart = nil, levelKills = 0, deaths = 0, rep = 0 }
ns.session = session

-- timestamped samples for the sliding-window rates (see Stats.lua)
local xpLog, killLog, repLog, goldLog = {}, {}, {}, {}
ns.logs = { xp = xpLog, kill = killLog, rep = repLog, gold = goldLog }

local pendingXPMob, pendingXPTime   -- attribute the next XP gain to this mob

local function StartSession()
    local now = GetTime()
    if not session.start then session.start = now end
    if not session.levelStart then session.levelStart = now end
end
ns.StartSession = StartSession

-- ---------------------------------------------------------------------------
-- Creature caches: the combat log gives a GUID + name but not type/rarity, so
-- we sniff those from units we see and key them by GUID until the mob dies.
-- ---------------------------------------------------------------------------
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
    local cls = UnitClassification(unit)   -- normal/rare/elite/rareelite/worldboss
    if cls and cls ~= "normal" then classCache[guid] = cls end
    nameCache[guid] = UnitName(unit)
end
ns.CacheUnit = CacheUnit

-- ---------------------------------------------------------------------------
-- Kill recording
-- ---------------------------------------------------------------------------
local UNKNOWN = ns.UNKNOWN

local function SpecialBucket(cls)
    if cls == "worldboss" then return "boss"
    elseif cls == "rare" or cls == "rareelite" then return "rare"
    elseif cls == "elite" then return "elite" end
    return nil
end
ns.SpecialBucket = SpecialBucket
ns.api.SpecialBucket = SpecialBucket

local function RecordKill(name, ctype, cls)
    local db = EnsureDB()
    name, ctype = name or UNKNOWN, ctype or UNKNOWN
    local entry = db.byName[name]
    if not entry then entry = { count = 0, ctype = ctype }; db.byName[name] = entry end
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
    pendingXPMob, pendingXPTime = name, GetTime()
end
ns.RecordKill = RecordKill
ns.api.RecordKill = RecordKill

-- Record one looted item against a mob's drop table. Returns false if the mob
-- has no kill entry yet. Separated out so it can be unit-tested directly.
local function RecordDrop(mob, itemName, qty, link, quality)
    local entry = EnsureDB().byName[mob]
    if not entry then return false end
    entry.drops = entry.drops or {}
    local d = entry.drops[itemName]
    if not d then d = { n = 0, q = 0 }; entry.drops[itemName] = d end
    d.n = d.n + 1
    d.q = d.q + (qty or 1)
    d.link, d.quality = link, quality
    return true
end
ns.RecordDrop = RecordDrop
ns.api.RecordDrop = RecordDrop

-- ---------------------------------------------------------------------------
-- Combat log: count only creatures killed with credit to me/my pet/minions.
-- ---------------------------------------------------------------------------
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

local function HandleCombatLog()
    local _, subevent, _, _, _, sourceFlags, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if subevent ~= "PARTY_KILL" then return end
    if bit.band(sourceFlags or 0, MINE) == 0 then return end
    local kind = destGUID and strsplit("-", destGUID)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    RecordKill(destName, typeCache[destGUID], classCache[destGUID])
    nameCache[destGUID] = destName    -- keep name for loot attribution
    lastKillName = destName
    ns.lastKillName = destName         -- read by Stats.XPStats for the per-mob estimate
    typeCache[destGUID] = nil
    classCache[destGUID] = nil
    ns.Refresh()
end

-- ---------------------------------------------------------------------------
-- XP, money, reputation
-- ---------------------------------------------------------------------------
local lastXP, lastXPMax, lastMoney, lastWatchedRep, lastWatchedName

local function HandleXP()
    local cur = UnitXP("player") or 0
    if lastXP == nil then lastXP, lastXPMax = cur, UnitXPMax("player"); return end
    local gained
    if cur >= lastXP then gained = cur - lastXP
    else gained = (lastXPMax - lastXP) + cur end   -- leveled within one update
    if gained > 0 then
        StartSession()
        session.xp = session.xp + gained
        xpLog[#xpLog + 1] = { t = GetTime(), amt = gained }
        -- attribute to the mob just killed; quest turn-ins (no recent kill) are skipped
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
    ns.Refresh()
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
        ns.Refresh()
    end
end

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
            ns.Refresh()
        end
    end
    lastWatchedName, lastWatchedRep = name, barValue
end

-- ---------------------------------------------------------------------------
-- Loot: attribute items to the creature that dropped them and accumulate value.
-- ---------------------------------------------------------------------------
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
ns.ResolveLootMob = ResolveLootMob
ns.api.ResolveLootMob = ResolveLootMob

local lootProcessed = false

local function HandleLootOpened()
    if lootProcessed or not GetNumLootItems then return end
    local num = GetNumLootItems()
    if num == 0 then return end
    local ITEM = (type(LOOT_SLOT_ITEM) == "number") and LOOT_SLOT_ITEM or 1

    for slot = 1, num do
        local link = GetLootSlotLink(slot)
        local slotType = GetLootSlotType and GetLootSlotType(slot)
        if link and (slotType == nil or slotType == ITEM) then
            local _, itemName, slotQty, _, quality = GetLootSlotInfo(slot)
            if itemName then
                local mob, q = ResolveLootMob(slot)
                q = q or slotQty or 1
                if mob then RecordDrop(mob, itemName, q, link, quality) end
                local sell = select(11, GetItemInfo(link))   -- locale-independent value
                if sell and sell > 0 then
                    StartSession()
                    session.loot = session.loot + sell * q
                    goldLog[#goldLog + 1] = { t = GetTime(), amt = sell * q }
                end
            end
        end
    end
    lootProcessed = true
    ns.Refresh()
end

local function HandleDeath()
    local db = EnsureDB()
    db.deaths = db.deaths + 1
    session.deaths = session.deaths + 1
    ns.Refresh()
end

-- ---------------------------------------------------------------------------
-- Session save / reset / full wipe
-- ---------------------------------------------------------------------------
local function SaveSession()
    if not session.start then return end
    if session.count == 0 and session.xp == 0 then return end
    local db = EnsureDB()
    table.insert(db.history, 1, {
        when   = date("%m/%d %H:%M"),
        dur    = ns.SessionElapsed(),
        kills  = session.count,
        xp     = session.xp,
        gold   = session.gold + session.loot,
        rep    = session.rep,
        deaths = session.deaths,
    })
    while #db.history > MAX_HISTORY do table.remove(db.history) end
end
ns.SaveSession = SaveSession
ns.api.SaveSession = SaveSession

local function clearSession()
    session.count, session.start, session.xp, session.gold, session.loot = 0, nil, 0, 0, 0
    session.levelStart, session.levelKills, session.deaths, session.rep = nil, 0, 0, 0
    wipe(xpLog); wipe(killLog); wipe(repLog); wipe(goldLog)
end

function ns.ResetSession()
    SaveSession()
    clearSession()
    ns.Refresh()
    Print("session saved to history and reset.")
end

function ns.WipeAll()
    KillTrackerDB = nil
    EnsureDB()
    clearSession()
    wipe(typeCache); wipe(classCache); wipe(nameCache); cacheCount = 0
    ns.RunWipeHandlers()
    ns.Refresh()
    Print("all data reset.")
end

StaticPopupDialogs["KILLTRACKER_RESET"] = {
    text = "Reset ALL Kill Tracker data for this character?",
    button1 = YES, button2 = NO,
    OnAccept = function() ns.WipeAll() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Test-only helpers: snapshot/restore so the wowUnit suite is non-destructive.
-- ---------------------------------------------------------------------------
function ns.api._snapSession()
    local s = {};  for k, v in pairs(session) do s[k] = v end
    local xl = {}; for i, v in ipairs(xpLog)   do xl[i] = v end
    local kl = {}; for i, v in ipairs(killLog) do kl[i] = v end
    local rl = {}; for i, v in ipairs(repLog)  do rl[i] = v end
    local gl = {}; for i, v in ipairs(goldLog) do gl[i] = v end
    return { s = s, xl = xl, kl = kl, rl = rl, gl = gl }
end
function ns.api._restoreSession(snap)
    wipe(session); for k, v in pairs(snap.s)  do session[k] = v end
    wipe(xpLog);   for i, v in ipairs(snap.xl) do xpLog[i] = v end
    wipe(killLog); for i, v in ipairs(snap.kl) do killLog[i] = v end
    wipe(repLog);  for i, v in ipairs(snap.rl) do repLog[i] = v end
    wipe(goldLog); for i, v in ipairs(snap.gl) do goldLog[i] = v end
end

-- ---------------------------------------------------------------------------
-- Event wiring
-- ---------------------------------------------------------------------------
ns.On("COMBAT_LOG_EVENT_UNFILTERED", HandleCombatLog)
ns.On("PLAYER_TARGET_CHANGED", function() CacheUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() CacheUnit("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) CacheUnit(unit) end)
ns.On("PLAYER_XP_UPDATE", HandleXP)
ns.On("PLAYER_MONEY", HandleMoney)
ns.On("UPDATE_FACTION", HandleFaction)
ns.On({ "LOOT_READY", "LOOT_OPENED" }, HandleLootOpened)
ns.On("LOOT_CLOSED", function() lootProcessed = false end)
ns.On("PLAYER_DEAD", HandleDeath)
ns.On("PLAYER_LOGOUT", SaveSession)

ns.On("PLAYER_LEVEL_UP", function(level)
    if EnsureDB().announceLevel then
        local secs = session.levelStart and (GetTime() - session.levelStart) or 0
        Print(string.format("Level |cffffd100%s|r! %d kills in %s this level.",
            tostring(level), session.levelKills, ns.FormatTime(secs)))
    end
    session.levelStart, session.levelKills = GetTime(), 0
    ns.Refresh()
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    lastMoney = GetMoney()
    if GetWatchedFactionInfo then
        local n, _, _, _, v = GetWatchedFactionInfo()
        lastWatchedName, lastWatchedRep = n, v
    end
end)

ns.On("PLAYER_LOGIN", function()
    MigrateDB()
    ns.RATE_WINDOW = EnsureDB().window or 600
end)
