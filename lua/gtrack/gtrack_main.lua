GTrack = {}
GTrack.status = 0 -- 0 disabled, 1 waiting for data, 2 connected
GTrack.data = {}

local portCvar = CreateClientConVar("gtrack_port", "4243", true, false, "Port to listen for opentrack packets on", 1024, 65535)
local onlyInVehiclesCvar = CreateClientConVar("gtrack_onlyvehicles", "1", true, false, "Only enable head tracking when in a vehicle", 0, 1)
local angSmoothingCvar = CreateClientConVar("gtrack_angsmoothing", "0", true, false, "Amount to smooth angular movement", 0, 1)
local posSmoothingCvar = CreateClientConVar("gtrack_possmoothing", "0", true, false, "Amount to smooth positional movement", 0, 1)

local substr = string.sub
local floor, round, max = math.floor, math.Round, math.max
local fmt = string.format
local hasFocus = system.HasFocus

local function decodeDouble(str)
    assert(#str == 8, "Double decoding error: invalid input length")

    local b1, b2, b3, b4, b5, b6, b7, b8 = str:byte(1, 8)

    local sign = (b8 > 127) and -1 or 1
    local exponent = ((b8 % 128) * 16) + floor(b7 / 16)
    local mantissa = ((b7 % 16) * 2^48) + (b6 * 2^40) + (b5 * 2^32) + (b4 * 2^24) + (b3 * 2^16) + (b2 * 2^8) + b1

    if exponent == 0 then
        if mantissa == 0 then
            return sign * 0.0
        else
            return sign * mantissa * 2^(-1022 - 52)
        end
    elseif exponent == 0x7FF then
        if mantissa == 0 then
            return sign * (1 / 0)  -- Infinity
        else
            return 0 / 0  -- NaN
        end
    else
        return sign * (1 + mantissa / 2^52) * 2^(exponent - 1023)
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
            local startByte = i * 8 + 1
            local endByte = (i + 1) * 8

            data[i + 1] = decodeDouble(substr(udpData, startByte, endByte))
        end

        dataPanel.x:SetText("XPos: " .. fmt("%.1f", data[1]) .. "cm")
        dataPanel.y:SetText("YPos: " .. fmt("%.1f", data[2]) .. "cm")
        dataPanel.z:SetText("ZPos: " .. fmt("%.1f", data[3]) .. "cm")

        dataPanel.pitch:SetText("Pitch: " .. round(data[5]) .. "°")
        dataPanel.yaw:SetText("Yaw: " .. round(data[4]) .. "°")
        dataPanel.roll:SetText("Roll: " .. round(data[6]) .. "°")
    else
        GTrack.Connect()
    end

    sock:close()
end

local offsetPos = Vector()
local offsetAng = Angle()
local vehicleAngOffset = Angle(0, 90, 0)

function GTrack.CalcView(_, origin, angles)
    if GTrack.status ~= 2 then return end
    local veh = LocalPlayer():GetVehicle()
    local validVeh = IsValid(veh)
    if onlyInVehiclesCvar:GetBool() and not validVeh then return end

    local data = GTrack.data

    if #data > 0 then
        local dt = RealFrameTime()

        local inPitch = data[5]
        local inYaw = data[4]
        local inRoll = data[6]

        local inX = data[1]
        local inY = data[2]
        local inZ = data[3]

        local vehAngles = validVeh and veh:LocalToWorldAngles(vehicleAngOffset)
        local posAngleOffset = vehAngles or angles
        local rawAng = Angle(-inPitch, -inYaw, -inRoll)
        local rawPos = Vector(-inZ, inX, inY)
        rawPos:Rotate(posAngleOffset)

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

        local outPos = origin + offsetPos
        local outAng = validVeh and veh:LocalToWorldAngles(vehicleAngOffset + offsetAng) or (angles + offsetAng)

        local view = {
            origin = outPos,
            angles = outAng
        }

        return view
    end
end

hook.Add("Tick", "GTrack_Think", GTrack.Think)
hook.Add("CalcView", "GTrack_CalcView", GTrack.CalcView)
