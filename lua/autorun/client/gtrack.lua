GTrack = {}
GTrack.status = 0 -- 0 disabled, 1 connecting, 2 connected
GTrack.data = {}

local port = CreateClientConVar("gtrack_port", "4243", true, false, "Port to listen for opentrack packets on", 1024, 65535)
local onlyInVehicles = CreateClientConVar("gtrack_onlyvehicles", "1", true, false, "Only enable head tracking when in a vehicle", 0, 1)
local angSmoothing = CreateClientConVar("gtrack_angsmoothing", "0", true, false, "Amount to smooth angular movement", 0, 1)
local posSmoothing = CreateClientConVar("gtrack_possmoothing", "0", true, false, "Amount to smooth positional movement", 0, 1)

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
        if fraction == 0 then return pow(-1,sign) * math.huge end

        -- NaN
        if fraction == pow2to52-1 then return 0 / 0 end
    end

    -- Combine the values and return the result
    if exponent == 0 then
        -- Handle subnormal numbers
        return pow(-1,sign) * pow(2,exponent-1023) * (fraction / pow2to52)
    else
        -- Handle normal numbers
        return pow(-1,sign) * pow(2,exponent-1023) * (fraction / pow2to52 + 1)
    end
end

function GTrack.Connect()
    GTrack.status = 1
    GTrack.dataPanel.status:SetText("Status: Connecting...")
    GTrack.portButton:SetEnabled(false)

    timer.Create("GTrack_Connect", 0.25, 0, function()
        local sock = socket.udp4()
        sock:settimeout(0.01)
        sock:setsockname("127.0.0.1", port:GetInt())
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
    sock:setsockname("127.0.0.1", port:GetInt())
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
    if onlyInVehicles:GetBool() and not LocalPlayer():InVehicle() then return end

    local data = GTrack.data

    if #data > 0 then
        local dt = RealFrameTime()

        local rawAng = Angle(-data[5], -data[4], -data[6])
        local rawPos = Vector(-data[3], data[1], data[2])
        rawPos:Rotate(angles)

        local focus = hasFocus() -- When tabbed out funky things happen with smoothing and may crash the game if enabled

        local angSmoothingValue = angSmoothing:GetFloat()
        local posSmoothingValue = posSmoothing:GetFloat()

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

    GTrack.portButton = settings:CreateRow("Settings", "Port")
    GTrack.portButton:Setup("Int", {min = 1024, max = 65535})
    GTrack.portButton:SetValue(port:GetInt())
    function GTrack.portButton:DataChanged(value)
        port:SetInt(value)
    end

    GTrack.angSmoothingButton = settings:CreateRow("Settings", "Angle Smoothing")
    GTrack.angSmoothingButton:Setup("Float", {min = 0, max = 1})
    GTrack.angSmoothingButton:SetValue(angSmoothing:GetFloat())
    function GTrack.angSmoothingButton:DataChanged(value)
        angSmoothing:SetFloat(value)
    end

    GTrack.posSmoothingButton = settings:CreateRow("Settings", "Position Smoothing")
    GTrack.posSmoothingButton:Setup("Float", {min = 0, max = 1})
    GTrack.posSmoothingButton:SetValue(angSmoothing:GetFloat())
    function GTrack.posSmoothingButton:DataChanged(value)
        posSmoothing:SetFloat(value)
    end

    GTrack.onlyInVehiclesButton = settings:CreateRow("Settings", "Only in vehicles")
    GTrack.onlyInVehiclesButton:Setup("Boolean")
    GTrack.onlyInVehiclesButton:SetValue(onlyInVehicles:GetBool())
    function GTrack.onlyInVehiclesButton:DataChanged(value)
        onlyInVehicles:SetBool(value == 1)
    end

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

hook.Add("PopulateToolMenu", "GTrack_CreateMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Player", "gtrack", "GTrack", nil, nil, GTrack.buildMenu)
end)

hook.Add("Tick", "GTrack_Think", GTrack.Think)
hook.Add("CalcView", "GTrack_CalcView", GTrack.CalcView)

RunConsoleCommand("spawnmenu_reload")