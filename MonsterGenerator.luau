local module={}
module.__index=module
module.PlayerMonsters = {}

local RP=game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Moves=require(RP.Modules.Moves)
local Personalities=require(RP.Modules.Personalities)
local Races=require(RP.Modules.Races)
local template=require(RP.Prefabs.Default)
local models=RP.Assets.Templates
local AnimationManager = require(game.ReplicatedStorage.Modules.AnimationManager)

local EvolutionEffect = RP.Remotes:WaitForChild("EvolutionEffect")
local EvolutionComplete = RP.Remotes:WaitForChild("EvolutionComplete")



local DEFAULT_PERSONALITIES = {
	"Unpredictable","Aggressive","Defensive","Strategist","Calm","Hyper","Reckless","Stoic"
}

local function applyMultipliers(stats, mult)
	if not mult or type(mult) ~= "table" then return stats end

	local map = {
		Strength = {"Strength","STR"},
		Defense  = {"Defense","DEF"},
		Skill    = {"Skill","SKL"},
		Speed    = {"Speed","SPD"},
		Intelligence = {"Intelligence","INT"},
		Luck = {"Luck","LCK"},
	}

	for statName, aliases in pairs(map) do
		local long, short = aliases[1], aliases[2]
		local multiplier = mult[statName] or 1

		if multiplier ~= 1 then
			-- Apply to both alias forms if they exist
			if stats[long] then
				stats[long] = math.max(1, math.floor(stats[long] * multiplier))
			end
			if stats[short] then
				stats[short] = math.max(1, math.floor(stats[short] * multiplier))
			end
		end
	end
	return stats
end

local function rollStats(stage)
	-- Total points by stage
	local TOTAL_BY_STAGE = {
		Fledgeling = 60,
		Rookie     = 80,
		Champion   = 100,
		Elder      = 120,
		Unique     = 140,
	}
	local totalPoints = TOTAL_BY_STAGE[stage] or 60

	-- Stats to distribute
	local statsToDistribute = {"STR", "DEF", "SKL", "SPD", "INT", "LCK"}
	local distribution = {}

	-- Initialize all stats with minimum of 5
	for _, stat in ipairs(statsToDistribute) do
		distribution[stat] = 5
		totalPoints = totalPoints - 5
	end

	-- Distribute remaining points randomly
	while totalPoints > 0 do
		local randomStat = statsToDistribute[math.random(1, #statsToDistribute)]
		distribution[randomStat] = distribution[randomStat] + 1
		totalPoints = totalPoints - 1
	end

	-- Create the final stats table with proper aliases
	return {
		Hp = 100, 
		Mp = 100,
		STR = distribution.STR, 
		Strength = distribution.STR,
		DEF = distribution.DEF, 
		Defense = distribution.DEF,
		SKL = distribution.SKL, 
		Skill = distribution.SKL,
		SPD = distribution.SPD, 
		Speed = distribution.SPD,
		INT = distribution.INT, 
		Intelligence = distribution.INT,
		LCK = distribution.LCK, 
		Luck = distribution.LCK,
	}
end

local function getStarterMoves(race)
	-- Use the Moves module's GetStarterMoves function
	if type(Moves.GetStarterMoves) == "function" then
		local ok, result = pcall(function()
			return Moves:GetStarterMoves(race)
		end)
		if ok and result and #result > 0 then
			return result
		end
	end

	-- Fallback: get 3 random amateur moves
	if type(Moves.GetRandomMoves) == "function" then
		local ok, result = pcall(function()
			return Moves:GetRandomMoves(race, 3, "Amateur", {
				Advanced = 0,    -- No upgrades for starters
				Specialist = 0,
				Ascended = 0,
				Primordial = 0
			})
		end)
		if ok and result and #result > 0 then
			return result
		end
	end

	-- Ultimate fallback: just basic attack
	local basicAttack = Moves:GetMove(race, "BasicAttack")
	if basicAttack then
		return {{move = basicAttack, rarity = "Amateur"}}
	end

	return {}
end

-- In ServerScriptService>Main>MonsterGenerator

function module.RollMonster(playerData, ownerId)
	local pool = Races:ListSummonable()
	if #pool == 0 then
		error("No summonable races available")
	end

	local race = pool[math.random(1, #pool)]
	local stage = Races:GetStage(race)
	local family = Races:GetBaseRaceFamily(race)
	local personalityResult = Personalities:RollPersonality()
	local personalityName, personalityData

	if type(personalityResult) == "table" then
		personalityName = personalityResult.name
		personalityData = personalityResult.data
	else
		personalityName = personalityResult
		personalityData = {}
	end

	local starterMoves = getStarterMoves(race)
	local stats = rollStats(stage)

	if personalityData and personalityData.trainingMultipliers then
		stats = applyMultipliers(stats, personalityData.trainingMultipliers)
	end

	local data = {
		id = HttpService:GenerateGUID(false),
		Name = _G.UTILS.nameGenerator(), -- You might want to generate a name here
		Race = race,
		Stage = stage,
		BaseRaceFamily = family,
		OwnerId = ownerId,
		Personality = personalityName,
		Stats = stats,
		Moves = starterMoves,
		State = "Idle",
		Version = "1.0",
		LastUpdatePlayed = tostring(os.time()),
		History = {race},
		Info = {},
		Appearance = {},
		Alignment = "Neutral",
		Age = 0,
		Level = 1,
		Bond = 0,
		Wins = 0,
		SessionTime = 0,
		CareMistakes = 0,
		Element = "None"
	}

	-- AUTOMATICALLY SAVE TO PLAYER DATA
	if ownerId then
		local playerData = _G.DATA:Get(ownerId)
		if playerData then
			-- Update player's monster data with the new rolled monster
			for key, value in pairs(data) do
				playerData[key] = value
			end
			print("Automatically saved rolled monster to player data")
		else
			warn("Player data not found for ownerId: " .. tostring(ownerId))
		end
	end

	return data
end


function module.BuildMonster(monsterData, ownerId)
	monsterData = monsterData or module.RollMonster(nil, ownerId)
	
	local isPlayerOwned = ownerId ~= nil
	local uid = isPlayerOwned and tostring(ownerId) or nil
	
	if isPlayerOwned then
		local existing = module.PlayerMonsters[uid]
		if existing and existing.Instance and existing.Instance.Parent then
			pcall(function()
				existing.Instance:Destroy()
			end)
			module.PlayerMonsters[uid] = nil
		end
	end
	
	local template = models:FindFirstChild(monsterData.Race)

	if not template then
		warn("No template found for race: " .. tostring(monsterData.Race))
		return nil
	end
	
	

	local monsterModel = template:FindFirstChild("Model"):Clone()
	monsterModel.Parent = workspace
	monsterModel.Name = monsterData.Name or monsterData.Race

	-- Preload animation data for this race
	--local animData = AnimationManager:GetCastAnimation(monsterData.Race)
	--if animData then
	--	monsterModel:SetAttribute("CastAnimationId", animData.AnimationId)
	--	monsterModel:SetAttribute("CastAnimationDuration", animData.Duration)
	--	print("Loaded cast animation for " .. monsterData.Race .. ": " .. animData.Duration .. "s")
	--end

	local humanoid = monsterModel:FindFirstChildOfClass("Humanoid")

	-- Set attributes from Stats table
	local stats = monsterData.Stats or {}
	monsterModel:SetAttribute("Hp", stats.Hp or 100)
	monsterModel:SetAttribute("Mp", stats.Mp or 100)
	monsterModel:SetAttribute("Strength", stats.Strength or stats.STR or 10)
	monsterModel:SetAttribute("Defense", stats.Defense or stats.DEF or 10)
	monsterModel:SetAttribute("Skill", stats.Skill or stats.SKL or 10)
	monsterModel:SetAttribute("Speed", stats.Speed or stats.SPD or 10)
	monsterModel:SetAttribute("Intelligence", stats.Intelligence or stats.INT or 10)
	monsterModel:SetAttribute("Luck", stats.Luck or stats.LCK or 10)

	-- General attributes
	monsterModel:SetAttribute("Name", monsterData.Name or monsterData.Race)
	monsterModel:SetAttribute("Race", monsterData.Race)
	monsterModel:SetAttribute("Personality", tostring(monsterData.Personality))
	monsterModel:SetAttribute("Stage", monsterData.Stage)

	-- Owner
	local actualOwnerId = ownerId or monsterData.OwnerId
	if actualOwnerId then
		monsterModel:SetAttribute("OwnerId", tonumber(actualOwnerId))
		module.RegisterPlayerMonster(actualOwnerId, monsterModel, monsterData)
	end

	if isPlayerOwned then
		module.PlayerMonsters[uid] = {
			Instance = monsterModel,
			Data = monsterData,
		}
	end

	-- 🔹 Conecta destruição segura
	monsterModel.Destroying:Connect(function()
		if isPlayerOwned and module.PlayerMonsters[uid] and module.PlayerMonsters[uid].Instance == monsterModel then
			module.PlayerMonsters[uid] = nil
		end
	end)
	
	-- Moves
	if monsterData.Moves then
		local moveCount = 0
		for i, moveInfo in ipairs(monsterData.Moves) do
			local moveId = nil

			-- Handle different move data formats
			if type(moveInfo) == "table" then
				if moveInfo.move then
					moveId = moveInfo.move.id or moveInfo.move.name
				else
					moveId = moveInfo.id or moveInfo.name
				end
			elseif type(moveInfo) == "string" then
				moveId = moveInfo
			end

			if moveId then
				monsterModel:SetAttribute("Move" .. i, moveId)
				moveCount = moveCount + 1
				print("Set move " .. i .. ": " .. moveId)
			end
		end
		monsterModel:SetAttribute("MoveCount", moveCount)
		print("Total moves set: " .. moveCount)
	else
		warn("No moves data for monster: " .. monsterModel.Name)
		monsterModel:SetAttribute("MoveCount", 0)
	end

	-- Humanoid setup
	if humanoid then
		humanoid.MaxHealth = stats.Hp or 100
		humanoid.Health = humanoid.MaxHealth
	else
		warn("No humanoid found in monster model: " .. monsterModel.Name)
	end

	-- Set initial state if available
	if _G and _G.STATES and typeof(_G.STATES.SetState) == "function" then
		_G.STATES:SetState(monsterModel, "Following")
	end

	return monsterModel, monsterData
end

function module.GetPlayerMonsterData(playerId)
	if not module.PlayerMonsters then return nil end
	return module.PlayerMonsters[tostring(playerId)]
end

-- Player monster management functions
function module.RegisterPlayerMonster(playerId, monsterModel, monsterData)
	if not module.PlayerMonsters then
		module.PlayerMonsters = {}
	end

	module.PlayerMonsters[tostring(playerId)] = {
		Model = monsterModel,
		Data = monsterData
	}

	print("Registered player monster for ID: " .. tostring(playerId) .. " - " .. monsterModel.Name)
end

function module.UnregisterPlayerMonster(playerId)
	if module.PlayerMonsters then
		local playerIdStr = tostring(playerId)
		if module.PlayerMonsters[playerIdStr] then
			print("Unregistered player monster for ID: " .. playerIdStr)
			module.PlayerMonsters[playerIdStr] = nil
		end
	end
end

function module.GetPlayerMonster(playerId)
	if not module.PlayerMonsters then
		module.PlayerMonsters = {}
		return nil
	end

	local playerIdStr = tostring(playerId)
	local monsterData = module.PlayerMonsters[playerIdStr]

	if monsterData and monsterData.Model and monsterData.Model.Parent then
		return monsterData.Model
	end

	-- Clean up invalid entries
	if monsterData and (not monsterData.Model or not monsterData.Model.Parent) then
		module.PlayerMonsters[playerIdStr] = nil
	end

	return nil
end


return module