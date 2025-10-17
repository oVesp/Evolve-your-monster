-- CombatArena.lua (Updated with better boundary enforcement)
local CombatArena = {}

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Configuration
local ARENA_RADIUS = 25
local ARENA_HEIGHT = 30
local ARENA_CHECK_INTERVAL = 0.5

-- Store active arenas
local activeArenas = {}
local SHOW_ARENA_VISUALS = true

-- Function to check if arena already exists for combat
local function arenaExists(combatId)
	return activeArenas[combatId] ~= nil
end

local function constrainAllCombatantsToArena(arenaData)
	for _, combatant in pairs(arenaData.combatants) do
		if not combatant or not combatant.Parent then continue end

		local humanoid = combatant:FindFirstChildOfClass("Humanoid")
		if not humanoid then continue end

		local position = combatant.PrimaryPart.Position

		if not CombatArena.IsInArenaBounds(position, arenaData.center, arenaData.radius, arenaData.height) then
			local correctedPosition = CombatArena.GetCorrectedPosition(position, arenaData.center, arenaData.radius, arenaData.height)

			-- Stop current movement and reposition
			humanoid:MoveTo(combatant.PrimaryPart.Position) -- Cancel movement
			combatant:SetPrimaryPartCFrame(CFrame.new(correctedPosition))

			-- NEW: Handle movement systems for both player and enemy monsters
			if _G.MOVEMENT then
				local guideData = _G.MOVEMENT.GetGuideData(combatant)
				if guideData and guideData.part then
					-- Adjust guide position for player monsters
					local targetPos = guideData.part.Position
					if not CombatArena.IsInArenaBounds(targetPos, arenaData.center, arenaData.radius, arenaData.height) then
						local correctedTarget = CombatArena.GetCorrectedPosition(targetPos, arenaData.center, arenaData.radius, arenaData.height)
						guideData.part.Position = correctedTarget
					end
				else
					-- For enemy monsters without guide data, adjust their movement target
					local combatManager = _G.COMBATMANAGER
					if combatManager and combatManager.GetCombatantData then
						-- This would require exposing combatant data in CombatManager
					end
				end
			end

			print(combatant.Name .. " was constrained to arena bounds")
		end
	end
end

-- NEW: Helper function to check if position is in arena bounds
function CombatArena.IsInArenaBounds(position, center, radius, height)
	local horizontalDistance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
	local verticalDistance = math.abs(position.Y - center.Y)
	return horizontalDistance <= radius and verticalDistance <= height / 2
end

-- NEW: Helper function to get corrected position
function CombatArena.GetCorrectedPosition(position, center, radius, height)
	local corrected = position
	local horizontalVec = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local horizontalDist = horizontalVec.Magnitude

	if horizontalDist > radius then
		local direction = horizontalVec.Unit
		corrected = Vector3.new(center.X + direction.X * radius * 0.9, corrected.Y, center.Z + direction.Z * radius * 0.9)
	end

	local verticalLimit = height / 2
	if math.abs(corrected.Y - center.Y) > verticalLimit then
		corrected = Vector3.new(corrected.X, center.Y + (corrected.Y > center.Y and verticalLimit or -verticalLimit), corrected.Z)
	end

	return corrected
end



-- Function to position combatants on opposite sides
function CombatArena.PositionCombatantsOpposite(combatants, center)
	if #combatants < 2 then return end

	-- Separate by team if possible
	local team1 = {}
	local team2 = {}

	for _, combatant in pairs(combatants) do
		local team = combatant:GetAttribute("Team") or 1
		if team == 1 then
			table.insert(team1, combatant)
		else
			table.insert(team2, combatant)
		end
	end

	-- If no teams defined, split evenly
	if #team1 == 0 and #team2 == 0 then
		for i, combatant in pairs(combatants) do
			if i % 2 == 0 then
				table.insert(team1, combatant)
			else
				table.insert(team2, combatant)
			end
		end
	end

	-- Position team1 on one side, team2 on opposite side
	local offsetDistance = ARENA_RADIUS * 0.7 -- 70% of arena radius

	-- Team 1 positions
	for i, combatant in pairs(team1) do
		local angle = math.rad((i - 1) * (360 / #team1))
		local offset = Vector3.new(
			math.cos(angle) * offsetDistance,
			0,
			math.sin(angle) * offsetDistance
		)
		if combatant and combatant.PrimaryPart then
			combatant:SetPrimaryPartCFrame(CFrame.new(center + offset))
			print("Positioned " .. combatant.Name .. " on team 1 side")
		end
	end

	-- Team 2 positions (opposite side)
	for i, combatant in pairs(team2) do
		local angle = math.rad((i - 1) * (360 / #team2) + 180) -- +180 for opposite side
		local offset = Vector3.new(
			math.cos(angle) * offsetDistance,
			0,
			math.sin(angle) * offsetDistance
		)
		if combatant and combatant.PrimaryPart then
			combatant:SetPrimaryPartCFrame(CFrame.new(center + offset))
			print("Positioned " .. combatant.Name .. " on team 2 side")
		end
	end
end

-- Function to create visual arena boundary
function CombatArena.CreateArenaVisual(center, radius, height, combatId)
	if not SHOW_ARENA_VISUALS then
		return nil
	end

	-- Check if arena visual already exists
	local existingArena = workspace:FindFirstChild("Arena_" .. combatId)
	if existingArena then
		existingArena:Destroy()
	end

	local arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arena_" .. combatId
	arenaFolder.Parent = workspace

	-- Create cylinder for visual representation
	local cylinder = Instance.new("Part")
	cylinder.Name = "ArenaBoundary"
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Size = Vector3.new(height, radius * 2, radius * 2)
	cylinder.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	cylinder.Material = Enum.Material.ForceField
	cylinder.BrickColor = BrickColor.new("Bright yellow")
	cylinder.Transparency = 0.8
	cylinder.CanCollide = false
	cylinder.Anchored = true
	cylinder.Parent = arenaFolder

	-- Add top and bottom discs
	local topDisc = Instance.new("Part")
	topDisc.Name = "ArenaTop"
	topDisc.Shape = Enum.PartType.Cylinder
	topDisc.Size = Vector3.new(1, radius * 2, radius * 2)
	topDisc.CFrame = CFrame.new(center + Vector3.new(0, height/2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	topDisc.Material = Enum.Material.ForceField
	topDisc.BrickColor = BrickColor.new("Bright yellow")
	topDisc.Transparency = 0.9
	topDisc.CanCollide = false
	topDisc.Anchored = true
	topDisc.Parent = arenaFolder

	local bottomDisc = Instance.new("Part")
	bottomDisc.Name = "ArenaBottom"
	bottomDisc.Shape = Enum.PartType.Cylinder
	bottomDisc.Size = Vector3.new(1, radius * 2, radius * 2)
	bottomDisc.CFrame = CFrame.new(center - Vector3.new(0, height/2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	bottomDisc.Material = Enum.Material.ForceField
	bottomDisc.BrickColor = BrickColor.new("Bright yellow")
	bottomDisc.Transparency = 0.9
	bottomDisc.CanCollide = false
	bottomDisc.Anchored = true
	bottomDisc.Parent = arenaFolder

	-- Billboard with combat info
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 300, 0, 100)
	billboard.StudsOffset = Vector3.new(0, height/2 + 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = cylinder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "COMBAT ARENA\nRadius: " .. radius .. " studs"
	label.TextColor3 = Color3.new(1, 1, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	return arenaFolder
end

-- Function to check if a position is within arena bounds
local function isInArenaBounds(position, center, radius, height)
	local horizontalDistance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
	local verticalDistance = math.abs(position.Y - center.Y)

	return horizontalDistance <= radius and verticalDistance <= height/2
end

-- Function to get corrected position within arena
local function getCorrectedPosition(position, center, radius, height)
	local corrected = position

	-- Calculate horizontal vector from center to position
	local horizontalVec = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local horizontalDist = horizontalVec.Magnitude

	-- If outside horizontal bounds, pull back to edge
	if horizontalDist > radius then
		local direction = horizontalVec.Unit
		corrected = Vector3.new(
			center.X + direction.X * radius * 0.9, -- 90% of radius to keep them slightly inside
			corrected.Y,
			center.Z + direction.Z * radius * 0.9
		)
	end

	-- Check vertical bounds
	local verticalLimit = height / 2
	if math.abs(corrected.Y - center.Y) > verticalLimit then
		corrected = Vector3.new(
			corrected.X,
			center.Y + (corrected.Y > center.Y and verticalLimit or -verticalLimit),
			corrected.Z
		)
	end

	return corrected
end

-- Function to constrain combatant to arena
local function constrainCombatantToArena(combatant, arenaData)
	if not combatant or not combatant.PrimaryPart then return end

	local humanoid = combatant:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local position = combatant.PrimaryPart.Position

	if not isInArenaBounds(position, arenaData.center, arenaData.radius, arenaData.height) then
		local correctedPosition = getCorrectedPosition(position, arenaData.center, arenaData.radius, arenaData.height)

		-- Stop current movement
		humanoid:MoveTo(combatant.PrimaryPart.Position)

		-- Teleport combatant back to arena
		combatant:SetPrimaryPartCFrame(CFrame.new(correctedPosition))

		-- Optional: Add visual feedback
		if _G.EFFECTS and _G.EFFECTS.PlaySound then
			_G.EFFECTS.PlaySound("Error", {Where = combatant})
		end

		print(combatant.Name .. " was pulled back into arena bounds")

		-- If using Movement system, update the guide part position
		if _G.MOVEMENT and _G.MOVEMENT.GetGuideData then
			local guideData = _G.MOVEMENT.GetGuideData(combatant)
			if guideData and guideData.part then
				-- Update guide part to be within arena bounds
				local targetPos = guideData.part.Position
				if not isInArenaBounds(targetPos, arenaData.center, arenaData.radius, arenaData.height) then
					local correctedTarget = getCorrectedPosition(targetPos, arenaData.center, arenaData.radius, arenaData.height)
					guideData.part.Position = correctedTarget
				end
			end
		end
	end
end
-- Function to calculate arena center from combatants
function CombatArena.CalculateArenaCenter(combatants)
	local totalPosition = Vector3.new(0, 0, 0)
	local validCombatants = 0

	for _, combatant in pairs(combatants) do
		if combatant and combatant.PrimaryPart then
			totalPosition = totalPosition + combatant.PrimaryPart.Position
			validCombatants = validCombatants + 1
		end
	end

	if validCombatants > 0 then
		return totalPosition / validCombatants
	end

	return Vector3.new(0, 0, 0)
end
-- Main function to create combat arena
function CombatArena.CreateArena(combatants, combatId)
	if CombatArena.ArenaExists(combatId) then
		return activeArenas[combatId]
	end

	local center = CombatArena.CalculateArenaCenter(combatants)
	local arenaData = {
		id = combatId,
		center = center,
		radius = ARENA_RADIUS,
		height = ARENA_HEIGHT,
		combatants = {},
		visual = nil,
		connection = nil
	}

	for _, combatant in pairs(combatants) do
		if combatant and combatant.PrimaryPart then
			table.insert(arenaData.combatants, combatant)
			combatant:SetAttribute("InArena", combatId)
		end
	end

	CombatArena.PositionCombatantsOpposite(combatants, center)
	arenaData.visual = CombatArena.CreateArenaVisual(center, ARENA_RADIUS, ARENA_HEIGHT, combatId)

	-- NEW: Universal constraint loop
	arenaData.connection = RunService.Heartbeat:Connect(function()
		constrainAllCombatantsToArena(arenaData)
	end)

	activeArenas[combatId] = arenaData
	return arenaData
end

-- Function to remove arena
function CombatArena.RemoveArena(combatId)
	local arenaData = activeArenas[combatId]
	if not arenaData then 
		print("No arena found to remove for combat: " .. combatId)
		return 
	end

	-- Disconnect constraint loop
	if arenaData.connection then
		arenaData.connection:Disconnect()
	end

	-- Remove visual
	if arenaData.visual then
		arenaData.visual:Destroy()
	end

	-- Clear combatant attributes
	for _, combatant in pairs(arenaData.combatants) do
		if combatant and combatant.Parent then
			combatant:SetAttribute("InArena", nil)
		end
	end

	-- Remove from active arenas
	activeArenas[combatId] = nil

	print("Combat arena removed for combat " .. combatId)
end

-- Function to update arena center (if needed for dynamic arenas)
function CombatArena.UpdateArenaCenter(combatId, newCenter)
	local arenaData = activeArenas[combatId]
	if not arenaData then return end

	arenaData.center = newCenter

	-- Update visual if it exists
	if arenaData.visual then
		local cylinder = arenaData.visual:FindFirstChild("ArenaBoundary")
		local topDisc = arenaData.visual:FindFirstChild("ArenaTop")
		local bottomDisc = arenaData.visual:FindFirstChild("ArenaBottom")

		if cylinder then
			cylinder.CFrame = CFrame.new(newCenter) * CFrame.Angles(0, 0, math.rad(90))
		end
		if topDisc then
			topDisc.CFrame = CFrame.new(newCenter + Vector3.new(0, ARENA_HEIGHT/2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
		if bottomDisc then
			bottomDisc.CFrame = CFrame.new(newCenter - Vector3.new(0, ARENA_HEIGHT/2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

-- Function to get arena data
function CombatArena.GetArena(combatId)
	return activeArenas[combatId]
end

-- Function to check if arena exists
function CombatArena.ArenaExists(combatId)
	return arenaExists(combatId)
end

return CombatArena