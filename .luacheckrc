-- Luacheck configuration for the Kill Tracker addon.
-- Declares the WoW Lua 5.1 environment + the addon's own globals so the linter
-- reports real problems (typos, unused vars, undefined locals) instead of every
-- WoW API call. Run:  luacheck .

std = "lua51"
max_line_length = false
codes = true
self = false

exclude_files = { ".luarocks", "**/Libs/**" }

-- Globals the addon itself defines (read + write)
globals = {
    "KillTrackerDB",
    "KillTracker",
    "KillTracker_Tests",
    "SLASH_KILLTRACKER1", "SLASH_KILLTRACKER2",
    "KillTracker_UI", "KillTracker_HUD", "KillTracker_Drops", "KillTracker_MinimapBtn",
    "KillTracker_Scroll", "KillTracker_DropScroll", "KillTracker_Search",
    "KillTracker_History", "KillTracker_HistScroll",
    "KillTracker_RefreshUI", "KillTracker_RefreshHUD", "KillTracker_RefreshDrops",
    "KillTracker_RefreshHistory", "KillTracker_ShowHistory",
    "KillTracker_ToggleHUD", "KillTracker_ToggleMinimap", "KillTracker_ResetSession",
    "KillTracker_ShowDrops", "KillTracker_SetSort",
    "SlashCmdList", "StaticPopupDialogs",
    "KillTracker_Broker",
}

-- WoW API + FrameXML + globals the addon only reads
read_globals = {
    -- core utility globals WoW adds on top of Lua 5.1
    "bit", "wipe", "strsplit", "CopyTable", "C_Timer", "LibStub",
    -- frames / UI
    "CreateFrame", "UIParent", "GameTooltip", "Minimap",
    "UIPanelButtonTemplate", "UIPanelCloseButton",
    "FauxScrollFrame_OnVerticalScroll", "FauxScrollFrame_GetOffset", "FauxScrollFrame_Update",
    "StaticPopup_Show", "GetCursorPosition",
    "TooltipDataProcessor", "Enum", "ITEM_QUALITY_COLORS",
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

-- The event handler intentionally takes (_, event, arg1); don't warn on unused.
ignore = {
    "212",  -- unused argument
    "542",  -- empty if branch (defensive nil-guards)
}
