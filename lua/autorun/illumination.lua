--[[
    Autorun code for the self illumination tool


--]]

if SERVER then
    AddCSLuaFile("illumination.lua")
    AddCSLuaFile("cl_illumtool.lua")
else
    include("cl_illumtool.lua")
end