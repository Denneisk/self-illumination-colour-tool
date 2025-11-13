--[[
    This file contains the client-side functions of the self-illumination color tool.
--]]
if CLIENT then
    local INT_BITCOUNT = 32

    local PaintableMaterials = {}				-- Empty temporary materials list
    local PaintableMaterialsNames = {}			-- Empty original names list

    local function CreateTempMaterial(msgLength)

        local tempname = net.ReadString()
        local name = net.ReadString()
        local shader = net.ReadString()
        local params = net.ReadTable()
        local index = net.ReadUInt(INT_BITCOUNT)

        local newMaterial = CreateMaterial(tempname, shader, params)
        local newMaterialName = "!"..newMaterial:GetName()

        table.insert( PaintableMaterials, index, newMaterialName)
        table.insert( PaintableMaterialsNames, index, name )

        net.Start("UpdateMaterialTables")
        net.WriteUInt(index,INT_BITCOUNT)
        net.WriteString(newMaterialName)
        net.WriteString(name)
        net.SendToServer()

    end

    net.Receive('SendInfoToClient', CreateTempMaterial)
end