-- Luacheck configuration for the Kill Tracker addon.
-- Declares the WoW Lua 5.1 environment + the addon's own globals so the linter
-- reports real problems instead of every WoW API call. Run:  luacheck .

std = "lua51"
max_line_length = false
codes = true
self = false

-- Third-party embedded libraries are not ours to lint.
exclude_files = { ".luarocks", "Libs" }

-- Globals the addon itself defines (read + write)
globals = {
    "KillTrackerDB",
    "KillTracker",          -- test-export table (see Core.lua)
    "KillTracker_Tests",
    "SLASH_KILLTRACKER1", "SLASH_KILLTRACKER2",
    "SlashCmdList", "StaticPopupDialogs",
}

-- WoW API + FrameXML + globals the addon only reads
read_globals = {
    -- core utilities WoW adds on top of Lua 5.1
    "bit", "wipe", "strsplit", "CopyTable", "C_Timer", "LibStub",
    -- frames / UI
    "CreateFrame", "UIParent", "GameTooltip", "Minimap",
    "FauxScrollFrame_OnVerticalScroll", "FauxScrollFrame_GetOffset", "FauxScrollFrame_Update",
    "StaticPopup_Show", "GetCursorPosition",
    "TooltipDataProcessor", "Enum", "ITEM_QUALITY_COLORS",
    -- options system
    "Settings", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    -- unit / player info
    "UnitGUID", "UnitExists", "UnitIsPlayer", "UnitCreatureType", "UnitClassification",
    "UnitName", "UnitXP", "UnitXPMax", "UnitLevel", "UnitIsDead",
    "GetTime", "GetMoney", "GetItemInfo", "GetXPExhaustion",
    "IsXPUserDisabled", "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel",
    "GetCoinTextureString", "GetWatchedFactionInfo", "date",
    -- combat log + loot
    "CombatLogGetCurrentEventInfo", "COMBATLOG_OBJECT_AFFILIATION_MINE",
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSlotType",
    "GetLootSourceInfo", "LOOT_SLOT_ITEM",
    -- localized constants
    "YES", "NO",
    -- test framework (optional dependency)
    "wowUnit",
}

ignore = {
    "212",  -- unused argument (event handlers take args they may not use)
    "542",  -- empty if branch (defensive nil-guards)
}
