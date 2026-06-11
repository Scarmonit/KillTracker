-- Stats.lua — read-only computation over the data layer: sliding-window rates,
-- XP/reputation projections, per-mob averages, and the sorted/filtered list the
-- main window renders. Nothing here mutates the database.

local _, ns = ...
local logs = ns.logs

-- ---------------------------------------------------------------------------
-- Sliding-window rates
-- ---------------------------------------------------------------------------
local function PruneLog(log, now, window)
    local cutoff = now - window
    while log[1] and log[1].t < cutoff do table.remove(log, 1) end
end

local function SumLog(log)
    local s = 0
    for _, e in ipairs(log) do s = s + e.amt end
    return s
end

function ns.SessionElapsed()
    local s = ns.session.start
    return s and (GetTime() - s) or 0
end
ns.api.SessionElapsed = ns.SessionElapsed

-- Whole-session average for a raw amount (used by chat summaries).
function ns.PerHour(amount)
    local e = ns.SessionElapsed()
    if e < 1 then return 0 end
    return amount / (e / 3600)
end

-- Returns xph, kph, avgXP, reph, avgRep, gph over the recent window. Using a
-- recent window (default 10m) keeps rates from being diluted by travel/AFK and
-- self-corrects for rested XP as it depletes.
function ns.RecentRates()
    local now = GetTime()
    local window = ns.RATE_WINDOW or 600
    PruneLog(logs.xp, now, window); PruneLog(logs.kill, now, window)
    PruneLog(logs.rep, now, window); PruneLog(logs.gold, now, window)

    local span = ns.session.start and math.min(window, now - ns.session.start) or 0
    if span < 1 then return 0, 0, 0, 0, 0, 0 end
    local hours = span / 3600
    local xpSum, repSum, goldSum, kills =
        SumLog(logs.xp), SumLog(logs.rep), SumLog(logs.gold), #logs.kill
    return xpSum / hours,
           kills / hours,
           (kills > 0) and (xpSum / kills) or 0,
           repSum / hours,
           (kills > 0) and (repSum / kills) or 0,
           goldSum / hours
end

-- ---------------------------------------------------------------------------
-- Projections
-- ---------------------------------------------------------------------------
function ns.MobAvgXP(name)
    local e = name and ns.EnsureDB().byName[name]
    if e and e.xpKills and e.xpKills > 0 then return e.xpTotal / e.xpKills end
    return nil
end
ns.api.MobAvgXP = ns.MobAvgXP

-- XP-to-level projection, or nil at max level / XP disabled.
function ns.XPStats()
    if ns.IsMaxLevel() then return nil end
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local remaining = max - cur
    local xph, _, avg = ns.RecentRates()
    local ttl = (xph > 0) and (remaining / xph * 3600) or nil
    -- prefer the per-mob average of the mob currently being farmed (set in Data)
    local useAvg = ns.MobAvgXP(ns.lastKillName) or avg
    local mobs = (useAvg > 0) and math.ceil(remaining / useAvg) or nil
    return { remaining = remaining, xph = xph, ttl = ttl, mobs = mobs,
             rested = (GetXPExhaustion and GetXPExhaustion()) or 0 }
end

-- Reputation projection for the watched faction, or nil if none watched.
function ns.RepStats()
    if not GetWatchedFactionInfo then return nil end
    local name, standingID, _, barMax, barValue = GetWatchedFactionInfo()
    if not name or name == "" then return nil end
    local remaining = barMax - barValue
    local _, _, _, reph, avgRep = ns.RecentRates()
    local ttl   = (reph > 0) and (remaining / reph * 3600) or nil
    local kills = (avgRep > 0) and math.ceil(remaining / avgRep) or nil
    local standing = _G["FACTION_STANDING_LABEL" .. (standingID or 0)] or ""
    return { name = name, standing = standing, remaining = remaining,
             reph = reph, ttl = ttl, kills = kills }
end

-- ---------------------------------------------------------------------------
-- Sorting / filtering for the main list
-- ---------------------------------------------------------------------------
ns.searchText = ""
local sortKey, sortDir = "count", -1   -- column + direction (1 asc, -1 desc)

function ns.GetSorted()
    local db = ns.EnsureDB()
    local q = ns.searchText
    local list = {}
    for name, entry in pairs(db.byName) do
        if q == "" or name:lower():find(q, 1, true) then
            list[#list + 1] = { name = name, count = entry.count, ctype = entry.ctype,
                                cls = entry.cls }
        end
    end
    table.sort(list, function(a, b)
        local av, bv
        if sortKey == "name" then av, bv = a.name, b.name
        elseif sortKey == "ctype" then av, bv = (a.ctype or ""), (b.ctype or "")
        else av, bv = a.count, b.count end
        if av == bv then return a.name < b.name end
        if sortDir == 1 then return av < bv else return av > bv end
    end)
    return list
end

function ns.GetSort() return sortKey, sortDir end

-- Toggle direction on the active column, else switch column (counts default to
-- descending, text columns ascending).
function ns.SetSort(key)
    if key == sortKey then sortDir = -sortDir
    else sortKey, sortDir = key, (key == "count") and -1 or 1 end
    if ns.RefreshUI then ns.RefreshUI() end
end
