-- Minimap.lua — LibDataBroker launcher + LibDBIcon minimap button. The broker
-- object also appears in Titan Panel, Bazooka, ChocolateBar, etc.

local _, ns = ...

local LDB     = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)

local function SetupBroker()
    if not LDB or ns.broker then return end
    ns.broker = LDB:NewDataObject("KillTracker", {
        type  = "launcher",
        label = "Kill Tracker",
        icon  = "Interface\\Icons\\Ability_Rogue_Eviscerate",
        OnClick = function(_, button)
            if button == "RightButton" then ns.ToggleHUD() else ns.ToggleUI() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Kill Tracker")
            tt:AddDoubleLine("Total kills:", ns.EnsureDB().total, 1, 1, 1, 1, 0.82, 0)
            local _, kph = ns.RecentRates()
            tt:AddDoubleLine("Session:", string.format("%d  (%.0f KPH)", ns.session.count, kph),
                1, 1, 1, 1, 0.82, 0)
            local xs = ns.XPStats()
            if xs then tt:AddDoubleLine("To level:", xs.ttl and ns.FormatTime(xs.ttl) or "--",
                1, 1, 1, 0.4, 0.8, 1) end
            tt:AddLine(" ")
            tt:AddLine("|cffeda55fLeft-click|r open window", 0.6, 0.6, 0.6)
            tt:AddLine("|cffeda55fRight-click|r toggle HUD", 0.6, 0.6, 0.6)
        end,
    })
    if LDBIcon then LDBIcon:Register("KillTracker", ns.broker, ns.EnsureDB().minimap) end
end

function ns.ToggleMinimap()
    local db = ns.EnsureDB()
    db.minimap.hide = not db.minimap.hide
    if LDBIcon then
        if db.minimap.hide then LDBIcon:Hide("KillTracker") else LDBIcon:Show("KillTracker") end
    else
        ns.Print("minimap library not loaded.")
    end
end

function ns.IsMinimapShown() return not ns.EnsureDB().minimap.hide end

ns.On("PLAYER_LOGIN", SetupBroker)
