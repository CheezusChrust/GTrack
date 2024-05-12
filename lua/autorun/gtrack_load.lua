AddCSLuaFile("gtrack/gtrack_main.lua")
AddCSLuaFile("gtrack/gtrack_menu.lua")

if CLIENT then
    include("gtrack/gtrack_main.lua")
    include("gtrack/gtrack_menu.lua")
end