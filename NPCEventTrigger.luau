-- NPCEventTrigger.lua (Fixed with Better Debugging)
local NPCEventTrigger = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- Configuration
local SPAWN_LOCATIONS = {
	Vector3.new(20, 0, 0),
	Vector3.new(-20, 0, 20),
	Vector3.new(0, 0, -20),
	Vector3.new(30, 0, 30),
}

local TRIGGER_RADIUS = 15
local MOB_COUNT = 2

-- Debug variables
local DEBUG_MODE = false
local enemyMobs = {}

-- Debug print function
local function debugPrint(message)
	if DEBUG_MODE then
		print("[NPCEventTrigger] " .. message)
	end
end
local function getPlayerMonster(player)
	local playerId = tostring(player.UserId)

	-- Method 1: PlayerMonsters table
	if _G.MONSTERGENERATOR and _G.MONSTERGENERATOR.PlayerMonsters then
		local monsterData = _G.MONSTERGENERATOR.PlayerMonsters[playerId]
		if monsterData and monsterData.Model and monsterData.Model.Parent then
			return monsterData.Model
		end
	end

	-- Method 2: Search by OwnerId
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") then
			local ownerId = obj:GetAttribute("OwnerId")
			if ownerId and tonumber(ownerId) == player.UserId then
				return obj
			end
		end
	end

	-- Method 3: Find closest following monster
	local character = player.Character
	if character and character.PrimaryPart then
		local closestMonster = nil
		local closestDistance = math.huge

		for _, obj in pairs(workspace:GetChildren()) do
			if obj:IsA("Model") and obj ~= character then
				local humanoid = obj:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local distance = (obj.PrimaryPart.Position - character.PrimaryPart.Position).Magnitude
					if distance < 50 and (_G.STATES and _G.STATES:IsInState(obj, "Following") or distance < closestDistance) then
						closestDistance = distance
						closestMonster = obj
					end
				end
			end
		end

		return closestMonster
	end

	return nil
end


-- Add function to respawn enemy mobs
local function respawnEnemyMob(mobData)
	if not mobData.position then return end

	debugPrint("Respawning enemy mob: " .. mobData.model.Name)

	-- Clean up old model
	if mobData.model then
		mobData.model:Destroy()
	end

	-- Spawn new enemy
	local newEnemyModel, newEnemyData = _G.MONSTERGENERATOR.BuildMonster()
	if newEnemyModel then
		newEnemyModel.Name = mobData.model.Name
		newEnemyModel:SetAttribute("Name", newEnemyModel.Name)
		newEnemyModel:SetAttribute("Team", 2)

		-- Position at original spawn point
		if newEnemyModel.PrimaryPart then
			newEnemyModel:SetPrimaryPartCFrame(CFrame.new(mobData.position))
		else
			local rootPart = newEnemyModel:FindFirstChild("HumanoidRootPart") or newEnemyModel:FindFirstChild("Torso")
			if rootPart then
				rootPart.Position = mobData.position
			end
		end

		newEnemyModel.Parent = workspace

		-- Update mob data
		mobData.model = newEnemyModel
		mobData.inCombat = false

		-- Set to idle state
		if _G.STATES then
			_G.STATES:SetState(newEnemyModel, "Idle")
		end

		debugPrint("Enemy respawned: " .. newEnemyModel.Name)
	end
end

local function startPlayerCombat(player, mobData)
	if mobData.inCombat then 
		debugPrint(mobData.model.Name .. " already in combat")
		return 
	end

	local playerMonster = getPlayerMonster(player)
	if not playerMonster then
		debugPrint("No monster found for player: " .. player.Name)
		return
	end

	debugPrint("Starting combat: " .. playerMonster.Name .. " vs " .. mobData.model.Name)

	mobData.inCombat = true

	-- Set teams
	playerMonster:SetAttribute("Team", 1)
	mobData.model:SetAttribute("Team", 2)

	-- Visual feedback
	mobData.trigger.BrickColor = BrickColor.new("Bright blue")
	mobData.trigger.Transparency = 0.99

	-- Start combat
	if _G.COMBATMANAGER then
		local combatId = _G.COMBATMANAGER.StartCombat({playerMonster, mobData.model})

		-- Listen for combat end to reset mob
		local connection
		connection = RunService.Heartbeat:Connect(function()
			if not mobData.model or not mobData.model.Parent then
				if connection then connection:Disconnect() end
				mobData.inCombat = false
				return
			end

			local isInCombat = _G.STATES and _G.STATES:IsInCombat(mobData.model)
			local isDead = _G.STATES and _G.STATES:IsDead(mobData.model)

			if not isInCombat and not isDead then
				mobData.inCombat = false
				mobData.trigger.BrickColor = BrickColor.new("Bright red")
				mobData.trigger.Transparency = 0.99

				-- If enemy died, respawn it after a delay
				if isDead then
					debugPrint("Enemy died, respawning in 10 seconds: " .. mobData.model.Name)
					task.delay(10, function()
						if mobData and mobData.model and not mobData.model.Parent then
							respawnEnemyMob(mobData)
						end
					end)
				end

				if connection then connection:Disconnect() end
				debugPrint("Combat ended, mob reset: " .. mobData.model.Name)
			end
		end)

		debugPrint("Combat started successfully with ID: " .. combatId)
	else
		warn("COMBATMANAGER not available")
	end
end
-- Function to create a trigger part
local function createTriggerPart(position, radius, mobName)
	local triggerPart = Instance.new("Part")
	triggerPart.Name = "CombatTrigger_" .. mobName
	triggerPart.Size = Vector3.new(radius * 2, 10, radius * 2)
	triggerPart.Position = position + Vector3.new(0, 5, 0)
	triggerPart.Transparency = 0.99
	triggerPart.BrickColor = BrickColor.new("Bright red")
	triggerPart.Material = Enum.Material.Neon
	triggerPart.CanCollide = false
	triggerPart.Anchored = true

	-- Add click detector for manual testing
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Parent = triggerPart
	clickDetector.MouseClick:Connect(function()
		debugPrint("Manual trigger clicked for: " .. mobName)
		-- Find nearest player and force combat
		local nearestPlayer = nil
		local nearestDistance = math.huge

		for _, player in pairs(Players:GetPlayers()) do
			if player.Character and player.Character.PrimaryPart then
				local distance = (player.Character.PrimaryPart.Position - triggerPart.Position).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearestPlayer = player
				end
			end
		end

		if nearestPlayer then
			for _, mobData in pairs(enemyMobs) do
				if mobData.trigger == triggerPart then
					startPlayerCombat(nearestPlayer, mobData)
					break
				end
			end
		end
	end)

	-- Visual indicator
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = triggerPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = mobName .. "\nRadius: " .. radius
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = billboard

	triggerPart.Parent = workspace

	return triggerPart
end

-- Function to check if player has a monster (multiple methods)
local function playerHasMonster(player)
	if not player or not player.Character then
		return false
	end

	local playerId = tostring(player.UserId)

	-- Method 1: Check PlayerMonsters table
	if _G.MONSTERGENERATOR and _G.MONSTERGENERATOR.PlayerMonsters then
		local monsterData = _G.MONSTERGENERATOR.PlayerMonsters[playerId]
		if monsterData and monsterData.Model and monsterData.Model.Parent then
			debugPrint("Found monster in PlayerMonsters for " .. player.Name)
			return true
		end
	end

	-- Method 2: Search workspace for models with player's OwnerId
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") then
			local ownerId = obj:GetAttribute("OwnerId")
			if ownerId and tonumber(ownerId) == player.UserId then
				debugPrint("Found monster by OwnerId for " .. player.Name)
				return true
			end
		end
	end

	-- Method 3: Look for following monsters near player
	local character = player.Character
	if character and character.PrimaryPart then
		for _, obj in pairs(workspace:GetChildren()) do
			if obj:IsA("Model") and obj ~= character then
				local humanoid = obj:FindFirstChildOfClass("Humanoid")
				if humanoid and (obj.PrimaryPart.Position - character.PrimaryPart.Position).Magnitude < 50 then
					if _G.STATES and _G.STATES:IsInState(obj, "Following") then
						debugPrint("Found following monster near " .. player.Name)
						return true
					end
				end
			end
		end
	end

	debugPrint("No monster found for " .. player.Name)
	return false
end

-- Function to get player's monster


-- Function to spawn enemy mob
local function spawnEnemyMob(position, index)
	if not _G.MONSTERGENERATOR then
		warn("MONSTERGENERATOR not available")
		return nil
	end

	debugPrint("Spawning enemy mob " .. index .. " at " .. tostring(position))

	local enemyModel, enemyData = _G.MONSTERGENERATOR.BuildMonster()
	if not enemyModel then 
		warn("Failed to build enemy monster")
		return nil 
	end

	enemyModel.Name = "EnemyMob_" .. index
	enemyModel:SetAttribute("Name", enemyModel.Name)
	enemyModel:SetAttribute("Team", 2)

	-- Ensure PrimaryPart
	if not enemyModel.PrimaryPart then
		local humanoidRootPart = enemyModel:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			enemyModel.PrimaryPart = humanoidRootPart
		else
			-- Find any base part
			for _, part in pairs(enemyModel:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "Handle" then
					enemyModel.PrimaryPart = part
					break
				end
			end
		end
	end

	-- Position enemy
	if enemyModel.PrimaryPart then
		enemyModel:SetPrimaryPartCFrame(CFrame.new(position))
	else
		-- Last resort: move the whole model
		local rootPart = enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")
		if rootPart then
			rootPart.Position = position
		end
	end

	enemyModel.Parent = workspace

	-- Create trigger
	local triggerPart = createTriggerPart(position, TRIGGER_RADIUS, enemyModel.Name)

	local mobData = {
		model = enemyModel,
		trigger = triggerPart,
		position = position,
		inCombat = false,
		index = index
	}

	-- Set to Idle state
	if _G.STATES then
		_G.STATES:SetState(enemyModel, "Idle")
	end

	debugPrint("Successfully spawned enemy mob: " .. enemyModel.Name)
	return mobData
end

-- Function to check distance
local function checkPlayerInRange(player, triggerPart)
	if not player or not player.Character or not player.Character.PrimaryPart then 
		return false 
	end

	local distance = (player.Character.PrimaryPart.Position - triggerPart.Position).Magnitude
	return distance <= TRIGGER_RADIUS
end

-- Main initialization
function NPCEventTrigger.Initialize()
	debugPrint("Initializing NPC Event Triggers...")

	-- Clear any existing mobs
	for _, mobData in pairs(enemyMobs) do
		if mobData.model then mobData.model:Destroy() end
		if mobData.trigger then mobData.trigger:Destroy() end
	end
	enemyMobs = {}

	-- Spawn enemy mobs
	for i = 1, MOB_COUNT do
		local spawnPos = SPAWN_LOCATIONS[i] or SPAWN_LOCATIONS[1] + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
		local mobData = spawnEnemyMob(spawnPos, i)
		if mobData then
			table.insert(enemyMobs, mobData)
		else
			warn("Failed to spawn enemy mob " .. i)
		end
	end

	debugPrint("Spawned " .. #enemyMobs .. " enemy mobs")

	-- Proximity detection
	local proximityCheckConnection
	proximityCheckConnection = RunService.Heartbeat:Connect(function()
		for _, player in pairs(Players:GetPlayers()) do
			if playerHasMonster(player) then
				for _, mobData in pairs(enemyMobs) do
					if mobData.model and mobData.model.Parent and mobData.trigger and mobData.trigger.Parent then
						if not mobData.inCombat then
							if checkPlayerInRange(player, mobData.trigger) then
								debugPrint("Player " .. player.Name .. " in range of " .. mobData.model.Name)
								startPlayerCombat(player, mobData)
							end
						end
					end
				end
			end
		end
	end)

	-- Cleanup
	Players.PlayerRemoving:Connect(function(player)
		if #Players:GetPlayers() == 0 then
			if proximityCheckConnection then
				proximityCheckConnection:Disconnect()
			end
		end
	end)

	debugPrint("NPC Event Triggers initialized successfully!")
end

-- Test function to manually trigger combat
function NPCEventTrigger.TestCombat(player)
	if not player then
		player = Players:GetPlayers()[1]
	end

	if not player then
		warn("No player found for test")
		return
	end

	debugPrint("Manual combat test for: " .. player.Name)

	for _, mobData in pairs(enemyMobs) do
		if not mobData.inCombat then
			startPlayerCombat(player, mobData)
			break
		end
	end
end

-- Auto-initialize
task.spawn(function()
	local maxWait = 10
	local startTime = tick()

	while tick() - startTime < maxWait do
		if _G.MONSTERGENERATOR and _G.COMBATMANAGER and _G.STATES then
			task.wait(2) -- Extra delay to ensure everything is loaded
			NPCEventTrigger.Initialize()

			-- Add test command to chat
			game:GetService("Chat"):RegisterChatCallback(Enum.ChatCallbackType.OnMessagePosted, function(message, speaker)
				if message == "/testcombat" then
					NPCEventTrigger.TestCombat(speaker)
				end
			end)

			return
		end
		task.wait(1)
	end

	warn("NPC Event Trigger: Required modules not loaded within " .. maxWait .. " seconds")
end)

return NPCEventTrigger