GTrack = {}
GTrack.status = 0 -- 0 disabled, 1 waiting for data, 2 connected
GTrack.data = {}

local portCvar = CreateClientConVar("gtrack_port", "4243", true, false, "Port to listen for opentrack packets on", 1024, 65535)
local onlyInVehiclesCvar = CreateClientConVar("gtrack_onlyvehicles", "1", true, false, "Only enable head tracking when in a vehicle", 0, 1)
local angSmoothingCvar = CreateClientConVar("gtrack_angsmoothing", "0", true, false, "Amount to smooth angular movement", 0, 1)
local posSmoothingCvar = CreateClientConVar("gtrack_possmoothing", "0", true, false, "Amount to smooth positional movement", 0, 1)

local byte = string.byte
local substr = string.sub
local socket = socket
local pow, floor, round, max = math.pow, math.floor, math.Round, math.max
local fmt = string.format
local hasFocus = system.HasFocus

-- https://stackoverflow.com/a/57443984
-- License conflict, need to change this later
function decodeDouble(str)
    -- Used to convert the fraction into a (very large) integer
    local pow2to52 = pow(2, 52)

    -- Used for bit-shifting
    local f08 = pow(2, 8)
    local f16 = pow(2, 16)
    local f24 = pow(2, 24)
    local f32 = pow(2, 32)
    local f40 = pow(2, 40)
    local f48 = pow(2, 48)

    -- Get bytes from the string
    local byte7 = byte(substr(str, 1, 1))
    local byte6 = byte(substr(str, 2, 2))
    local byte5 = byte(substr(str, 3, 3))
    local byte4 = byte(substr(str, 4, 4))
    local byte3 = byte(substr(str, 5, 5))
    local byte2 = byte(substr(str, 6, 6))
    local byte1 = byte(substr(str, 7, 7))
    local byte0 = byte(substr(str, 8, 8))

    -- Separate out the values
    local sign = byte0 >= 128 and 1 or 0
    local exponent = (byte0 % 128) * 16 + floor(byte1 / 16)
    local fraction = (byte1 % 16) * f48
                     + byte2 * f40 + byte3 * f32 + byte4 * f24
                     + byte5 * f16 + byte6 * f08 + byte7

    -- Handle special cases
    if exponent == 2047 then
        -- Infinities
        if fraction == 0 then return pow(-1, sign) * math.huge end

        -- NaN
        if fraction == pow2to52-1 then return 0 / 0 end
    end

    -- Combine the values and return the result
    if exponent == 0 then
        -- Handle subnormal numbers
        return pow(-1, sign) * pow(2, exponent - 1023) * (fraction / pow2to52)
    else
        -- Handle normal numbers
        return pow(-1, sign) * pow(2, exponent - 1023) * (fraction / pow2to52 + 1)
    end
end

function GTrack.Connect()
    GTrack.status = 1
    GTrack.dataPanel.status:SetText("Status: Waiting for data...")
    GTrack.portButton:SetEnabled(false)

    timer.Create("GTrack_Connect", 0.25, 0, function()
        local sock = socket.udp4()
        sock:settimeout(0.01)
        sock:setsockname("127.0.0.1", portCvar:GetInt())
        local _, err = sock:receive()
        sock:close()

        if not err then
            timer.Remove("GTrack_Connect")
            GTrack.dataPanel.status:SetText("Status: Connected")
            GTrack.status = 2
        end
    end)
end

function GTrack.Disconnect()
    GTrack.status = 0
    GTrack.dataPanel.status:SetText("Status: Disabled")
    GTrack.portButton:SetEnabled(true)

    timer.Remove("GTrack_Connect")

    GTrack.status = 0
end

function GTrack.Think()
    if GTrack.status ~= 2 then return end
    local data = GTrack.data
    local dataPanel = GTrack.dataPanel

    -- Need to recreate socket every tick, otherwise, when you tab out or the game lags, it falls behind - some kind of UDP buffer?
    -- Have to investigate this eventually, this works for now without any apparent problems or FPS drops
    local sock = socket.udp4()
    sock:settimeout(0.01)
    sock:setsockname("127.0.0.1", portCvar:GetInt())
    local udpData, err = sock:receive()

    if not err then
        for i = 0, 5 do
            local s = i * 8
            local e = (i + 1) * 8

            data[i + 1] = decodeDouble(substr(udpData, s + 1, e + 1))
        end

        dataPanel.x:SetText("XPos: " .. fmt("%.1f", data[1]) .. "cm")
        dataPanel.y:SetText("YPos: " .. fmt("%.1f", data[2]) .. "cm")
        dataPanel.z:SetText("ZPos: " .. fmt("%.1f", data[3]) .. "cm")

        dataPanel.pitch:SetText("Pitch: " .. round(data[4]) .. "°")
        dataPanel.yaw:SetText("Yaw: " .. round(data[5]) .. "°")
        dataPanel.roll:SetText("Roll: " .. round(data[6]) .. "°")
    else
        GTrack.Connect()
    end

    sock:close()
end

local offsetPos = Vector()
local offsetAng = Angle()

function GTrack.CalcView(_, origin, angles)
    if GTrack.status ~= 2 then return end
    if onlyInVehiclesCvar:GetBool() and not LocalPlayer():InVehicle() then return end

    local data = GTrack.data

    if #data > 0 then
        local dt = RealFrameTime()

        local rawAng = Angle(-data[5], -data[4], -data[6])
        local rawPos = Vector(-data[3], data[1], data[2])
        rawPos:Rotate(angles)

        local focus = hasFocus() -- When tabbed out funky things happen with smoothing and may crash the game if enabled

        local angSmoothingValue = angSmoothingCvar:GetFloat()
        local posSmoothingValue = posSmoothingCvar:GetFloat()

        if focus and angSmoothingValue > 0 then
            offsetAng = LerpAngle(max(1 - angSmoothingValue, 0.01) * 100 * dt, offsetAng, rawAng)
        else
            offsetAng = rawAng
        end

        if focus and posSmoothingValue > 0 then
            offsetPos = LerpVector(max(1 - posSmoothingValue, 0.01) * 100 * dt, offsetPos, rawPos)
        else
            offsetPos = rawPos
        end

        local view = {
            origin = origin + offsetPos,
            angles = angles + offsetAng
        }

        return view
    end
end

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

-- Apply a tooltip property to the panel, and every child it has
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

        draw.RoundedBox(4, x - 2, y - 2 - hOffset, xSize + 4, ySize + 4, Color(200, 200, 200, 200))
        draw.DrawText(text, "gtrack_hovertext", x, y - hOffset, Color(0, 0, 0))
    end
end)

hook.Add("PopulateToolMenu", "GTrack_CreateMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Player", "gtrack", "GTrack", nil, nil, GTrack.buildMenu)
end)

hook.Add("Tick", "GTrack_Think", GTrack.Think)
hook.Add("CalcView", "GTrack_CalcView", GTrack.CalcView)