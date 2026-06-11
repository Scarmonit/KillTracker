-- Commands.lua — the /kt (/killtracker) slash command dispatcher.

local _, ns = ...

local function PrintTop(n)
    local list, db = ns.GetSorted(), ns.EnsureDB()
    local _, kph = ns.RecentRates()
    ns.Print(string.format("total |cffffd100%d|r | session |cffffd100%d|r (%.0f KPH)",
        db.total, ns.session.count, kph))
    local xs = ns.XPStats()
    if xs then
        local _, _, _, _, _, gph = ns.RecentRates()
        print(string.format("  XP %s/hr | to level %s | %s mobs | %s/hr",
            ns.CommaNum(xs.xph), xs.ttl and ns.FormatTime(xs.ttl) or "--",
            xs.mobs or "--", ns.Money(gph)))
    end
    for i = 1, math.min(n, #list) do
        local d = list[i]
        local t = (d.ctype and d.ctype ~= ns.UNKNOWN) and (" |cff808080(" .. d.ctype .. ")|r") or ""
        print(string.format("  %2d. %s%s  x|cffffd100%d|r", i, d.name, t, d.count))
    end
    if #list == 0 then print("  No kills recorded yet.") end
end

local function ShowHelp()
    ns.Print("commands:")
    print("  |cffffff00/kt|r          - toggle the window")
    print("  |cffffff00/kt hud|r      - toggle the live HUD")
    print("  |cffffff00/kt lock|r     - lock/unlock the HUD")
    print("  |cffffff00/kt minimap|r  - show/hide the minimap button")
    print("  |cffffff00/kt options|r  - open the options panel")
    print("  |cffffff00/kt history|r  - open saved session history")
    print("  |cffffff00/kt window N|r - set the pace window (minutes)")
    print("  |cffffff00/kt show|r     - print top 10 + rates to chat")
    print("  |cffffff00/kt session|r  - save & reset the session")
    print("  |cffffff00/kt reset|r    - wipe all data (confirm)")
end

local dispatch = {
    [""]        = function() ns.ToggleUI() end,
    show        = function() PrintTop(10) end,
    top         = function() PrintTop(10) end,
    hud         = function() ns.ToggleHUD() end,
    lock        = function() ns.ToggleHUDLock() end,
    minimap     = function() ns.ToggleMinimap() end,
    options     = function() ns.ShowOptions() end,
    config      = function() ns.ShowOptions() end,
    history     = function() ns.ShowHistory() end,
    hist        = function() ns.ShowHistory() end,
    session     = function() ns.ResetSession() end,
    reset       = function() StaticPopup_Show("KILLTRACKER_RESET") end,
    help        = ShowHelp,
}

SLASH_KILLTRACKER1 = "/kt"
SLASH_KILLTRACKER2 = "/killtracker"
SlashCmdList["KILLTRACKER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    local handler = dispatch[msg]
    if handler then return handler() end

    if msg:find("^window") then
        local n = tonumber(msg:match("(%d+)"))
        if n and n >= 1 then
            ns.RATE_WINDOW = n * 60
            ns.EnsureDB().window = ns.RATE_WINDOW
            ns.Refresh()
            ns.Print("pace window set to |cffffd100" .. n .. "|r min.")
        else
            ns.Print("usage: |cffffff00/kt window <minutes>|r (current "
                .. ((ns.RATE_WINDOW or 600) / 60) .. " min)")
        end
        return
    end

    ShowHelp()
end
