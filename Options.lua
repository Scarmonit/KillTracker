-- Options.lua — a settings panel registered in the Interface/AddOns options,
-- also openable with `/kt options`. Controls the HUD, minimap, announcements,
-- and the rate window.

local _, ns = ...

local panel = CreateFrame("Frame")
panel.name = "Kill Tracker"
ns.optionsPanel = panel

local controls = {}   -- refreshed from the DB whenever the panel is shown

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16); title:SetText("Kill Tracker")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
sub:SetText("Grinding analytics for WoW Classic.")

local function makeCheck(label, tooltip, y, get, set)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 18, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(label)
    cb.tooltipText = tooltip
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb._get = get
    controls[#controls + 1] = function() cb:SetChecked(get()) end
    return cb
end

-- ---------------------------------------------------------------------------
-- Checkboxes
-- ---------------------------------------------------------------------------
makeCheck("Show HUD", "Toggle the live grinding HUD.", -60,
    function() return ns.hud and ns.hud:IsShown() end,
    function(want)
        local shown = ns.hud and ns.hud:IsShown()
        if want ~= (shown and true or false) then ns.ToggleHUD() end
    end)

makeCheck("Lock HUD", "Prevent the HUD from being moved or resized (click-through).", -88,
    function() return ns.IsHUDLocked() end,
    function(want) ns.SetHUDLock(want) end)

makeCheck("Show minimap button", "Show the Kill Tracker minimap button.", -116,
    function() return ns.IsMinimapShown() end,
    function(want)
        if want ~= ns.IsMinimapShown() then ns.ToggleMinimap() end
    end)

makeCheck("Announce level-ups", "Print a kills/time summary in chat when you level.", -144,
    function() return ns.EnsureDB().announceLevel end,
    function(want) ns.EnsureDB().announceLevel = want end)

-- ---------------------------------------------------------------------------
-- Rate-window slider
-- ---------------------------------------------------------------------------
local slider = CreateFrame("Slider", "KillTrackerOptions_WindowSlider", panel, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", 22, -200)
slider:SetWidth(220)
slider:SetMinMaxValues(1, 30)
slider:SetValueStep(1)
if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

local sliderLabel = _G[slider:GetName() .. "Text"]
local sliderLow   = _G[slider:GetName() .. "Low"]
local sliderHigh  = _G[slider:GetName() .. "High"]
if sliderLow then sliderLow:SetText("1m") end
if sliderHigh then sliderHigh:SetText("30m") end

slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    if sliderLabel then sliderLabel:SetText("Pace window: " .. value .. " min") end
    local db = ns.EnsureDB()
    db.window = value * 60
    ns.RATE_WINDOW = db.window
end)
controls[#controls + 1] = function()
    slider:SetValue((ns.EnsureDB().window or 600) / 60)
end

-- ---------------------------------------------------------------------------
-- HUD scale slider
-- ---------------------------------------------------------------------------
local scaleSlider = CreateFrame("Slider", "KillTrackerOptions_ScaleSlider", panel, "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", 22, -252)
scaleSlider:SetWidth(220)
scaleSlider:SetMinMaxValues(0.5, 2.0)
scaleSlider:SetValueStep(0.05)
if scaleSlider.SetObeyStepOnDrag then scaleSlider:SetObeyStepOnDrag(true) end

local scaleLabel = _G[scaleSlider:GetName() .. "Text"]
local scaleLow   = _G[scaleSlider:GetName() .. "Low"]
local scaleHigh  = _G[scaleSlider:GetName() .. "High"]
if scaleLow then scaleLow:SetText("50%") end
if scaleHigh then scaleHigh:SetText("200%") end

scaleSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value * 20 + 0.5) / 20   -- snap to 0.05
    if scaleLabel then scaleLabel:SetText(string.format("HUD scale: %d%%", math.floor(value * 100 + 0.5))) end
    ns.SetHUDScale(value)
end)
controls[#controls + 1] = function() scaleSlider:SetValue(ns.GetHUDScale()) end

-- ---------------------------------------------------------------------------
-- Reset HUD position button
-- ---------------------------------------------------------------------------
local resetPos = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetPos:SetSize(160, 22)
resetPos:SetPoint("TOPLEFT", 24, -300)
resetPos:SetText("Reset HUD position")
resetPos:SetScript("OnClick", function() ns.ResetHUDPosition() end)

-- ---------------------------------------------------------------------------
-- Refresh control state when the panel is shown
-- ---------------------------------------------------------------------------
panel:SetScript("OnShow", function()
    for _, refresh in ipairs(controls) do refresh() end
end)

-- ---------------------------------------------------------------------------
-- Register with the options system (new Settings API, with legacy fallback)
-- ---------------------------------------------------------------------------
local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, "Kill Tracker")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.ShowOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)   -- call twice (Blizzard quirk)
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        ns.Print("options panel unavailable on this client.")
    end
end
