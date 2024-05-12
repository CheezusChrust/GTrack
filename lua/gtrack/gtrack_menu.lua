local portCvar = GetConVar("gtrack_port")
local onlyInVehiclesCvar = GetConVar("gtrack_onlyvehicles")
local angSmoothingCvar = GetConVar("gtrack_angsmoothing")
local posSmoothingCvar = GetConVar("gtrack_possmoothing")

surface.CreateFont("gtrack_bigtext", {
    font = "Roboto",
    size = 24,
    weight = 550
})

surface.CreateFont("gtrack_labeltext", {
    font = "Roboto",
    size = 17,
    weight = 550
})

surface.CreateFont("gtrack_hovertext", {
    font = "Roboto",
    size = 16,
    weight = 550
})

local function recursiveSetTooltip(panel, tooltip, owner)
    owner = owner or panel
    panel.tooltip = tooltip
    panel.tooltipOwner = owner

    for _, child in ipairs(panel:GetChildren()) do
        recursiveSetTooltip(child, tooltip, owner)
    end
end

function GTrack.buildMenu(panel)
    panel:SetName("GTrack Configuration")

    if not socket then
        local status = vgui.Create("DLabel", panel)
        status:SetFont("gtrack_bigtext")
        status:SetText("Socket library not found!\nWithout it, this addon won't\nwork.")
        status:SetColor(Color(200, 50, 0))
        status:Dock(TOP)
        status:SetHeight(70)
        status:DockMargin(10, 10, 10, 5)
        status:SetDark(true)

        return
    end

    local enable = vgui.Create("DCheckBoxLabel", panel)
    enable:SetText("Enable Head Tracking")
    enable:Dock(TOP)
    enable:DockMargin(10, 10, 10, 5)
    enable:SetHeight(15)
    enable.Label:SetFont("gtrack_labeltext")
    enable.Label:SetDark(true)
    function enable:OnChange(val)
        if val then
            GTrack.Connect()
        else
            GTrack.Disconnect()
        end
    end

    local settings = vgui.Create("DProperties", panel)
    settings:Dock(TOP)
    settings:DockMargin(10, 5, 10, 5)
    settings:SetHeight(110)
    PrintTable(settings:GetTable())

    GTrack.portButton = settings:CreateRow("Settings", "Port")
    GTrack.portButton:Setup("Int", {min = 1024, max = 65535})
    GTrack.portButton:SetValue(portCvar:GetInt())
    function GTrack.portButton:DataChanged(value)
        portCvar:SetInt(value)
    end

    aSmooth = settings:CreateRow("Settings", "Angle Smoothing")
    aSmooth:Setup("Float", {min = 0, max = 1})
    aSmooth:SetValue(angSmoothingCvar:GetFloat())
    function aSmooth:DataChanged(value)
        angSmoothingCvar:SetFloat(value)
    end
    recursiveSetTooltip(aSmooth, "Apply an exponential moving\naverage to angular motion")
    GTrack.angSmoothingButton = aSmooth

    pSmooth = settings:CreateRow("Settings", "Position Smoothing")
    pSmooth:Setup("Float", {min = 0, max = 1})
    pSmooth:SetValue(posSmoothingCvar:GetFloat())
    function pSmooth:DataChanged(value)
        posSmoothingCvar:SetFloat(value)
    end
    recursiveSetTooltip(pSmooth, "Apply an exponential moving\naverage to linear motion")
    GTrack.posSmoothingButton = pSmooth

    vehOnly = settings:CreateRow("Settings", "Only in vehicles")
    vehOnly:Setup("Boolean")
    vehOnly:SetValue(onlyInVehiclesCvar:GetBool())
    function vehOnly:DataChanged(value)
        onlyInVehiclesCvar:SetBool(value == 1)
    end
    recursiveSetTooltip(vehOnly, "Only enable head tracking\nwhile sitting in vehicles")
    GTrack.onlyInVehiclesButton = vehOnly

    GTrack.dataPanel = {}

    local status = vgui.Create("DLabel", panel)
    status:Dock(TOP)
    status:DockMargin(10, 5, 10, 5)
    status:SetFont("gtrack_labeltext")
    status:SetText("Status: Disabled")
    status:SetDark(true)

    GTrack.dataPanel.status = status

    local dataPanel = vgui.Create("DTree", panel)
    dataPanel:Dock(TOP)
    dataPanel:DockMargin(10, 5, 10, 5)
    dataPanel:SetHeight(145)

    GTrack.dataPanel.panel = dataPanel

    local posData = dataPanel:AddNode("Raw Position Data", "icon16/vector.png")
    posData.Label:SetFont("gtrack_labeltext")
    posData:SetExpanded(true)

    GTrack.dataPanel.x = posData:AddNode("XPos: 0cm", "icon16/database.png")
    GTrack.dataPanel.x.Label:SetFont("gtrack_labeltext")

    GTrack.dataPanel.y = posData:AddNode("YPos: 0cm", "icon16/database.png")
    GTrack.dataPanel.y.Label:SetFont("gtrack_labeltext")

    GTrack.dataPanel.z = posData:AddNode("ZPos: 0cm", "icon16/database.png")
    GTrack.dataPanel.z.Label:SetFont("gtrack_labeltext")

    local rotData = dataPanel:AddNode("Raw Rotation Data", "icon16/arrow_rotate_clockwise.png")
    rotData.Label:SetFont("gtrack_labeltext")
    rotData:SetExpanded(true)

    GTrack.dataPanel.pitch = rotData:AddNode("Pitch: 0°", "icon16/database.png")
    GTrack.dataPanel.pitch.Label:SetFont("gtrack_labeltext")

    GTrack.dataPanel.yaw = rotData:AddNode("Yaw: 0°", "icon16/database.png")
    GTrack.dataPanel.yaw.Label:SetFont("gtrack_labeltext")

    GTrack.dataPanel.roll = rotData:AddNode("Roll: 0°", "icon16/database.png")
    GTrack.dataPanel.roll.Label:SetFont("gtrack_labeltext")
end

-- Removing the callback before creating it prevents duplicate callbacks from stacking up when reloading the file
cvars.RemoveChangeCallback("gtrack_port", "cb")
cvars.AddChangeCallback("gtrack_port", function(_, _, value)
    if IsValid(GTrack.portButton) then
        GTrack.portButton:SetValue(value)
    end
end, "cb")

cvars.RemoveChangeCallback("gtrack_angsmoothing", "cb")
cvars.AddChangeCallback("gtrack_angsmoothing", function(_, _, value)
    if IsValid(GTrack.angSmoothingButton) then
        GTrack.angSmoothingButton:SetValue(value)
    end
end, "cb")

cvars.RemoveChangeCallback("gtrack_possmoothing", "cb")
cvars.AddChangeCallback("gtrack_possmoothing", function(_, _, value)
    if IsValid(GTrack.posSmoothingButton) then
        GTrack.posSmoothingButton:SetValue(value)
    end
end, "cb")

cvars.RemoveChangeCallback("gtrack_onlyvehicles", "cb")
cvars.AddChangeCallback("gtrack_onlyvehicles", function(_, _, value)
    if IsValid(GTrack.onlyInVehiclesButton) then
        GTrack.onlyInVehiclesButton:SetValue(value)
    end
end, "cb")

local hoverTime = 0
local lastText

hook.Add("PostRenderVGUI", "GTrack_ToolTips", function()
    local element = vgui.GetHoveredPanel()

    if not IsValid(element) then return end
    if element:GetName() == "GModBase" then return end

    local text = element.tooltip

    if not text or text ~= lastText then
        hoverTime = 0
        lastText = text

        return
    end

    hoverTime = hoverTime + RealFrameTime()

    if hoverTime > 0.5 then
        surface.SetFont("gtrack_hovertext")

        local x, y = element.tooltipOwner:LocalToScreen(0, -20)
        local xSize, ySize = surface.GetTextSize(text)
        local hOffset = ySize / 2

        draw.RoundedBox(4, x - 2, y - 2 - hOffset, xSize + 4, ySize + 4, Color(200, 200, 200))
        draw.DrawText(text, "gtrack_hovertext", x, y - hOffset, Color(0, 0, 0))
    end
end)

hook.Add("PopulateToolMenu", "GTrack_CreateMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Player", "gtrack", "GTrack", nil, nil, GTrack.buildMenu)
end)