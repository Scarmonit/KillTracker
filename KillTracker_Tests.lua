-- In-game test suite for Kill Tracker, written for the wowUnit framework
-- (https://github.com/Mirroar/wowUnit). Install wowUnit, then run in-game:
--     /wu KillTracker_Tests        (aliases: /test, /wowunit, /unittest)
--
-- The "Recording" tests snapshot and restore your saved data + session, so
-- running them does not corrupt your real kill counts.

local KT = KillTracker   -- internal API exported by KillTracker.lua

KillTracker_Tests = {
    title = "Kill Tracker",
    tests = {

        ["Formatting"] = {
            ["FormatTime under an hour"] = function()
                wowUnit:assertEquals(KT.FormatTime(95), "1m 35s")
            end,
            ["FormatTime over an hour"] = function()
                wowUnit:assertEquals(KT.FormatTime(3725), "1h 02m")
            end,
            ["CommaNum groups thousands"] = function()
                wowUnit:assertEquals(KT.CommaNum(1234567), "1,234,567")
                wowUnit:assertEquals(KT.CommaNum(950), "950")
            end,
        },

        ["Classification"] = {
            ["worldboss maps to boss"] = function()
                wowUnit:assertEquals(KT.SpecialBucket("worldboss"), "boss")
            end,
            ["rare and rareelite map to rare"] = function()
                wowUnit:assertEquals(KT.SpecialBucket("rare"), "rare")
                wowUnit:assertEquals(KT.SpecialBucket("rareelite"), "rare")
            end,
            ["elite maps to elite"] = function()
                wowUnit:assertEquals(KT.SpecialBucket("elite"), "elite")
            end,
            ["normal maps to nothing"] = function()
                wowUnit:assert(KT.SpecialBucket("normal") == nil, "normal should not bucket")
            end,
        },

        ["Recording"] = {
            setup = function()
                KT._snap = { db = KillTrackerDB, sess = KT._snapSession() }
                KillTrackerDB = nil
                KT.EnsureDB()
            end,
            teardown = function()
                KillTrackerDB = KT._snap.db
                KT._restoreSession(KT._snap.sess)
                KT._snap = nil
            end,

            ["RecordKill bumps total, per-mob count and type"] = function()
                KT.RecordKill("Test Wolf", "Beast", nil)
                KT.RecordKill("Test Wolf", "Beast", nil)
                local db = KT.EnsureDB()
                wowUnit:assertEquals(db.total, 2)
                wowUnit:assertEquals(db.byName["Test Wolf"].count, 2)
                wowUnit:assertEquals(db.byName["Test Wolf"].ctype, "Beast")
            end,

            ["RecordKill counts rare/elite/boss buckets"] = function()
                KT.RecordKill("Rare Croc", "Beast", "rare")
                KT.RecordKill("Big Boss", "Dragonkin", "worldboss")
                local db = KT.EnsureDB()
                wowUnit:assertEquals(db.special.rare, 1)
                wowUnit:assertEquals(db.special.boss, 1)
                wowUnit:assertEquals(db.byName["Rare Croc"].cls, "rare")
            end,

            ["RecordDrop tracks occurrences and quantity"] = function()
                KT.RecordKill("Loot Mob", "Humanoid", nil)
                KT.RecordDrop("Loot Mob", "Linen Cloth", 2, "link", 1)
                KT.RecordDrop("Loot Mob", "Linen Cloth", 3, "link", 1)
                local d = KT.EnsureDB().byName["Loot Mob"].drops["Linen Cloth"]
                wowUnit:assertEquals(d.n, 2)   -- two corpses dropped it
                wowUnit:assertEquals(d.q, 5)   -- five total looted
            end,

            ["drop rate is occurrences over kills"] = function()
                for _ = 1, 10 do KT.RecordKill("Farm Mob", "Beast", nil) end
                KT.RecordDrop("Farm Mob", "Rare Pelt", 1, "link", 2)
                KT.RecordDrop("Farm Mob", "Rare Pelt", 1, "link", 2)
                local entry = KT.EnsureDB().byName["Farm Mob"]
                local rate = entry.drops["Rare Pelt"].n / entry.count * 100
                wowUnit:assertEquals(rate, 20)  -- 2 drops / 10 kills
            end,

            ["RecordDrop on an unknown mob is a no-op"] = function()
                wowUnit:assert(KT.RecordDrop("Never Killed", "X", 1) == false,
                    "should return false for unknown mob")
            end,

            ["MobAvgXP averages per-mob experience"] = function()
                KT.RecordKill("XP Mob", "Beast", nil)
                local e = KT.EnsureDB().byName["XP Mob"]
                e.xpTotal, e.xpKills = 300, 3          -- simulate attributed XP
                wowUnit:assertEquals(KT.MobAvgXP("XP Mob"), 100)
                wowUnit:assert(KT.MobAvgXP("Unknown Mob") == nil, "nil when no data")
            end,

            ["SaveSession appends a history entry"] = function()
                KT.RecordKill("Hist Mob", "Beast", nil)
                KT.RecordKill("Hist Mob", "Beast", nil)
                local before = #KT.EnsureDB().history
                KT.SaveSession()
                local h = KT.EnsureDB().history
                wowUnit:assertEquals(#h, before + 1)
                wowUnit:assertEquals(h[1].kills, 2)   -- newest first
            end,
        },
    },
}
