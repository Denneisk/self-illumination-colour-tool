--[[ 
    This program has been designed to alter the tint of self illuminating materials. It will not make a material magically glow, it needs to have the $selfillum parameter set to 1.
	However, most models that have this option enabled are the target market, those being mainly lights.
	You can change the colour of a light/illuminating surface with this tool.

	UPDATE LOG:
	- 15 JULY 2022 @ 10:34 (GMT +02:00)
	-- Additional checks to fix errors and stuff

	- 24 NOVEMBER 2024 @ 21:58 (GMT +02:00)
	-- Fixed error warning that would appear in Multiplayer
	-- Updated tool so that it would automatically select the first material when selecting a new prop
]]--
local INT_BITCOUNT = 32

--AddCSLuaFile('autorun/cl_illumtool.lua')

TOOL.Category = "Render"
TOOL.Name = "Self Illumination Color Tool"

-- Setting up the description of the tool
if CLIENT then
	print("Welcome to the illumination tool")
	language.Add( "tool.illumination_tool_main.name", "Self Illumination Color Tool" )
	language.Add( "tool.illumination_tool_main.desc", "Allows you to change the color of your illuminating material." )
		
	TOOL.Information = {

	{ name = "info", stage = 1 },
	{ name = "info2", stage = 2 },
	
	{ name = "left", stage = 1 },
	{ name = "left_use", icon2 = "gui/e.png", stage = 1 },
	
	{ name = "right" },
	{ name = "right_use", icon2 = "gui/e.png"},
	
	{ name = "reload", stage = 1 },
	{ name = "reload_use", icon2 = "gui/e.png", stage = 1},

	}

	language.Add( "tool.illumination_tool_main.1", "Make sure to select the material first before applying the tint" )
	language.Add( "tool.illumination_tool_main.info2", "No $selfillum parameter detected on the materials of this entity" )
	
	language.Add( "tool.illumination_tool_main.left", "Apply tint" )
	language.Add( "tool.illumination_tool_main.left_use", "Apply tint to playermodel" )
	
	language.Add( "tool.illumination_tool_main.right", "Select an entity" )
	language.Add( "tool.illumination_tool_main.right_use", "Select your playermodel" )
	
	language.Add( "tool.illumination_tool_main.reload", "Remove illumination from selected entity" )
	language.Add( "tool.illumination_tool_main.reload_use", "Remove illumination from yourself" )
	
end

TOOL.ClientConVar[ "r" ] = 255
TOOL.ClientConVar[ "g" ] = 255
TOOL.ClientConVar[ "b" ] = 255
TOOL.ClientConVar[ "a" ] = 255
TOOL.ClientConVar[ "selected_material_index" ] = 0, true, true
TOOL.ClientConVar[ "selected_material" ] = "models/editor/lua_run", true, true
TOOL.ClientConVar[ "selected_material_name" ] = "models/editor/lua_run", true, true

local n = 0
local TintColour = Vector( 1, 1, 1, 1 )		-- Creates our default vector, pure white
local PaintableMaterials = {}				-- Empty temporary materials list
local PaintableMaterialsNames = {}			-- Empty original names list
local UpdateControlPanel = false			-- We should not be updating the control panel yet
local HasSelectedEntity = false				-- We should not be displaying the colour tools yet
local ResetEntityMaterials = false			-- We do not need to reset the materials yet
local ContainsIllumMaterials = false		-- A check to see if the model has any illum materials


--[[
	I'll be honest: this is very messy. Since I am very new to LUA, I am not 100% sure of what I am doing, and documentation and tutorials are few and far between.
	This bit of code is used to force the Tool to update the content panel, and to send some additional data that would usually be delayed by the Server.
	Basically, the Materials and the Materials Names tables are only sent later by the client to the server, too late to be updated by the context panel. As such, I update them here instead.
]]--

local function RefreshContentPanel(msgLength)
	UpdateControlPanel = net.ReadBool()
	HasSelectedEntity = net.ReadBool()
	ContainsIllumMaterials = net.ReadBool()

	PaintableMaterials = net.ReadTable()
	PaintableMaterialsNames = net.ReadTable()
end

local function UpdateMaterialsTable(msgLength)
	-- Because we can't send through the temp materials, we send through their names instead, and update the lists on this side of the code.
	-- We send through the names of the temp, each which have a matching index to one of the pre-existing materials
	local index = net.ReadUInt(INT_BITCOUNT)
	local newMaterial = net.ReadString()
	local name = net.ReadString()

	table.insert( PaintableMaterials, index, newMaterial)
	table.insert( PaintableMaterialsNames, index, name )
end

local function SendInfoToClient( tempname, name, shader, params, index, currentPlayer )
	-- Send all of the data we need to the Client side for execution
	net.Start('SendInfoToClient')
	net.WriteString(tempname)
	net.WriteString(name)
	net.WriteString(shader)
	net.WriteTable(params)
	net.WriteUInt(index, INT_BITCOUNT)
	net.Send(currentPlayer)
end

local function buildEntMaterials(ply, ent)
	local PaintableMaterials = {}
	local PaintableMaterialsNames = {}
	local ContainsIllumMaterials = false
	-- Gets us the materials of the current selected entity
	local entMaterials = ent:GetMaterials()
	local SELFILLUM = 64 -- value of the $selfillum parameter
	
	local selfIllum = ent.SelfIllum
	if selfIllum then
		if selfIllum.HasSelfIllum then
			local aliases = selfIllum.Aliases
			local stupidNameTable = {}
			for i in pairs(aliases) do
				i = i + 1 -- i LOVE mixing 1 indexed and 0 indexed
				stupidNameTable[i] = entMaterials[i]
			end
			return aliases, stupidNameTable, true
		else
			return selfIllum.Aliases, {}, false
		end
	end
	
	local aliases = {}
	selfIllum = { Tints = {}, Aliases = aliases }
	ent.SelfIllum = selfIllum
	
	for i = 1, #entMaterials do
		local newMat = Material( entMaterials[i] )
		
		-- Checking to see if the current material has $selfillum enabled
		if bit.band(newMat:GetInt("$flags"), SELFILLUM) ~= 0 then
			ContainsIllumMaterials = true
			-- Here we get the information we need from the current material
			local TempMatName = "temp_illumtool_mat" .. n
			local TempMatShader = newMat:GetShader()
			local TempMatParams = { ["$basetexture"] = newMat:GetString("$basetexture"), ["$selfillum"] = 1 }

			local matName = newMat:GetName()

			PaintableMaterials[i] = "!"..TempMatName
			PaintableMaterialsNames[i] = matName
			aliases[i - 1] = TempMatName

			-- Sending all of the data to be made into a new temporary material
			if SERVER then
				SendInfoToClient(TempMatName, matName, TempMatShader, TempMatParams, i, ply)
			end
			n = n + 1
		end
	end
	selfIllum.HasSelfIllum = ContainsIllumMaterials
	return PaintableMaterials, PaintableMaterialsNames, ContainsIllumMaterials
end

--[[
	Creating the tint colouring function
--]]
local function SetIllumTint(ply, ent, material, index, colour)
	if SERVER then
		buildEntMaterials(ply, ent)
		-- This is a standard test to check if we can use OverrideMaterials in a server or not. Apparantly it's to stop people from using exploits
		-- if ( !game.SinglePlayer() && !list.Contains( "OverrideMaterials", Data.MaterialOverride ) && Data.MaterialOverride != "" ) then return end
		
		-- This allows us to reset the material
		if ResetEntityMaterials == true then 
			ent:SetSubMaterial()
			ResetEntityMaterials = false
			return true 
		end
		-- Applying the temporary material over our entity at the correct material index
		ent:SetSubMaterial(index , "!" .. tostring(material:GetName()))

		-- Applying the colour tint
		material:SetVector("$selfillumtint", colour)
		
		local tints = ent.SelfIllum.Tints
		tints[index] = colour
		
		duplicator.StoreEntityModifier(ent, "illuminationtint", tints)
	end
end

local function tintFromTable(ply, ent, tints)
	local ent_tints = ent.SelfIllum.Tints
	
	for i, tint in pairs(tints) do
		local mat_name = ent.SelfIllum.Aliases[i]
		
		if not mat_name then continue end
		
		local mat_name_ref = "!" .. mat_name
		local material = Material(mat_name_ref)
	
		-- Applying the temporary material over our entity at the correct material index
		ent:SetSubMaterial(i, mat_name_ref)

		-- Applying the colour tint
		material:SetVector("$selfillumtint", tint)
		
		ent_tints[i] = tint
	end
end

local function illuminationOnDupe(ply, ent, tints)
	ent.SelfIllum = nil
	if #tints == 0 then return end
	
	buildEntMaterials(ply, ent)
	
	local selfIllum = ent.SelfIllum
	if not selfIllum.HasSelfIllum then return end
	local aliases = selfIllum.Aliases
	local firstAlias = aliases[next(aliases)]
	if not firstAlias then return end
	
	local test_mat_name = "!" .. firstAlias
	
	local timer_name = "selfillum_dupe_" .. ent:EntIndex()
	timer.Create("selfillum_dupe_" .. ent:EntIndex(), 0.2, 10, function() -- Wait for the client to build the materials I guess ugh
		if not ent:IsValid() then timer.Remove(timer_name) end
		
		local test_mat = Material(test_mat_name)
		if not test_mat:IsError() then
			tintFromTable(ply, ent, tints) -- This can still fail because why not lol. Works enough for me, ship it.
			timer.Remove(timer_name)
			return
		elseif timer.RepsLeft(timer_name) <= 0 then
			ErrorNoHalt("Self Illumination Colour Tool: Couldn't find the desired material for: " .. tostring(ent) .. " (looking for " .. test_mat_name .. ")" ..
				"\nThis error can usually be fixed by reloading the dupe/save.")
		end
	end)
end

duplicator.RegisterEntityModifier("illuminationtint", illuminationOnDupe)

--[[
	The Left Click tells the game to apply our temporary material over our model and to colour that material with our Illumination colour
--]]
function TOOL:LeftClick( trace )
	-- A quick check to see if we have selected a material beforehand
	--if HasSelectedEntity == false then return false end
	
	local ent = !self:GetOwner():KeyDown( IN_USE ) && trace.Entity || self:GetOwner()

	-- Getting our temporary material, so we can apply it
	local TintingMat = Material(self:GetClientInfo( "selected_material" ))

	-- Getting the index of the original material on the model
	local TintingMatIndex = tonumber(self:GetClientInfo("selected_material_index"))

	if ( IsValid( ent.AttachedEntity ) ) then ent = ent.AttachedEntity end
	if ( !IsValid( ent ) ) then return false end
	
	-- I have to divide all of the RGB values by 255 because the $selfillumtint parameter runs numbers between 0 and 1, and having them in the 255 format would make the materials too bright
	local r = self:GetClientNumber( "r", 0 ) / 255
	local g = self:GetClientNumber( "g", 0 ) / 255
	local b = self:GetClientNumber( "b", 0 ) / 255
	local a = self:GetClientNumber( "a", 0 ) / 255
	
	-- Creating the colour vector
	TintColour = Vector( r, g, b, a ) -- WHAT DO YOU MEAN Vector(r, g, b, a) DO YOU EVEN READ THE DOCUMENTATION?!?! ANSWER: NO
	
	-- We combine the Material and the index into a table since we want the game to store that information, and the duplicator function only takes 3 values, of which the "Data" value has to be a table
	SetIllumTint(self:GetOwner(), ent, TintingMat, TintingMatIndex, TintColour)
	return true
end

--[[
	The Right Click of the tool selects your model, as we need to determine whether or not the entity has materials we can play around with or not.
--]]
function TOOL:RightClick( trace )
	-- If we are holding down the USE key (default = E) then we select ourselves as the target model
	local ent = !self:GetOwner():KeyDown( IN_USE ) && trace.Entity || self:GetOwner()

	local ply = self:GetOwner()

	-- Checks to make sure we have a proper entity selected
	if ( IsValid( ent.AttachedEntity ) ) then ent = ent.AttachedEntity end
	if ( !IsValid( ent ) ) then return false end
	
	-- Resetting the temporary material list so we don't end up overriding another materials' colour
	-- We also reset the ContainsIllumMaterials, because we assume a model has none until proven otherwise

	PaintableMaterials, PaintableMaterialsNames, ContainsIllumMaterials = buildEntMaterials(ply, ent)
	
	self:SetStage(ContainsIllumMaterials and 1 or 2)
	-- This is a very messy fix, but it is to force the tool to update the context panel. We also need to send through some additional variables and tables that are required to function.
	-- It ain't pretty but it works (so far)

	if SERVER then
		net.Start("RefreshContentTable")
		net.WriteBool(true)
		net.WriteBool(true)
		net.WriteBool(ContainsIllumMaterials)
		net.WriteTable( PaintableMaterials )
		net.WriteTable( PaintableMaterialsNames )
		net.Send(ply)
	end
	
	return true
end


-- Reload resets the materials on the model, effectively removing the illumination tint
function TOOL:Reload( trace )
	local ent = !self:GetOwner():KeyDown( IN_USE ) && trace.Entity || self:GetOwner()
	if ( IsValid( ent.AttachedEntity ) ) then ent = ent.AttachedEntity end
	if ( !IsValid( ent ) ) then return false end -- The entity is valid and isn't worldspawn
	
	ResetEntityMaterials = true
	SetIllumTint(self:GetOwner(), ent, nil, nil)
	return true

end
--Updates the tool when it is deployed
function TOOL:Think( trace )
	if (CLIENT) then
		if UpdateControlPanel == true then 
			self:UpdateIlluminationControlPanel()
			UpdateControlPanel = false
		end

	end
end

-- Function to update the control panel when we select a new entity
function TOOL:UpdateIlluminationControlPanel( index )

	local CPanel = controlpanel.Get( "illumination_tool_main" )
	if ( !CPanel ) then Msg( "Couldn't find Illumination Tool panel!\n" ) return end

	CPanel:ClearControls()
	self.BuildCPanel( CPanel )
end

-- Creating the UI

function TOOL.BuildCPanel( CPanel )
	if HasSelectedEntity == true then
		CPanel:AddControl("Label", { Text = "A tool that allows you to change the colour of Self Illuminating materials. Requires a model to have $selfillum set to 1" })
		local listbox = CPanel:AddControl( "ListBox", { Label = "Colourable materials", Height = 17 + table.Count( PaintableMaterialsNames ) * 17 } )

		-- If our entity contains Self illuminating materials, then we add them to the list
			if ContainsIllumMaterials == true then
				for k, mat in pairs( PaintableMaterialsNames ) do
					local line = listbox:AddLine( mat )
					-- The line data needs three values: the name of the temp texture, its corresponding orignial texture name and the index of the material. Each are applied to their corresponding Client variables
					line.data = { illumination_tool_main_selected_material = PaintableMaterials[k], 
					illumination_tool_main_selected_material_index = k-1, 
					illumination_tool_main_selected_material_name = PaintableMaterialsNames[k] }
					end
				
				-- Adding the colour picker, which displays the RGB colour window, like the Colour Tool
				CPanel:ColorPicker( "Tint Colour", "illumination_tool_main_r", "illumination_tool_main_g", "illumination_tool_main_b", "illumination_tool_main_a" )
			else CPanel:AddControl("Label", { Text = "No materials with $selfillum detected" }) end

		listbox:SelectFirstItem() -- Selects the first index point in the list

	else
		CPanel:AddControl("Label", { Text = "A tool that allows you to change the colour of Self Illuminating materials. Requires a model to have $selfillum set to 1" })
		CPanel:AddControl("Header", { Description = "Please select an entity" })
	end

end



if SERVER then
	
	util.AddNetworkString("RequestMaterialTable")
	util.AddNetworkString("UpdateMaterialTables")
	util.AddNetworkString("RefreshContentTable")
	util.AddNetworkString("SendInfoToClient")
end

net.Receive("UpdateMaterialTables", UpdateMaterialsTable)
net.Receive("RefreshContentTable", RefreshContentPanel)