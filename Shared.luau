-- Server script modificado
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local MonsterSummon = ReplicatedStorage.Remotes:WaitForChild("MonsterSummon")
local GenerateMonster = ReplicatedStorage.Remotes:WaitForChild("GenerateMonster")
local Races = require(ReplicatedStorage.Modules.Races)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spinResult = remotes:WaitForChild("TrainingSpinResult")
local EvolutionRequest = remotes:WaitForChild("EvolutionRequest")
local EvolutionEffect = remotes:WaitForChild("EvolutionEffect")
local EvolutionComplete = remotes:WaitForChild("EvolutionComplete")

--local EvolutionVFX = require(ReplicatedStorage.Modules["Effects&SFX"]:WaitForChild("EvolutionVFX"))



local BASE_GAIN = {
	Strength = 2, Defense = 2, Speed = 3, Wisdom = 2
}

local module = {}

local TestEvolutionTemplate = remotes:WaitForChild("TestEvolutionTemplate")
TestEvolutionTemplate.OnServerEvent:Connect(function(player)
	local templates = ReplicatedStorage.Assets.Templates
	local cosmicWeaver = templates:FindFirstChild("CosmicWeaver")

	if cosmicWeaver then
		print("✓ CosmicWeaver template found")
		local model = cosmicWeaver:FindFirstChild("Model")
		if model then
			print("✓ CosmicWeaver model found")
		else
			print("✗ CosmicWeaver model NOT found")
		end
	else
		print("✗ CosmicWeaver template NOT found")
	end

	-- Also check RealitySeed for comparison
	local realitySeed = templates:FindFirstChild("RealitySeed")
	if realitySeed then
		print("✓ RealitySeed template found")
	else
		print("✗ RealitySeed template NOT found")
	end
end)

-- Rastreia monstros por dono
-- Map: UserId -> { Instance = monsterInstance, Data = monsterData }
local playerMonster = {}

-- Rastreia monstros sem dono (spawnados pelo servidor)
-- Map: mobId (GUID) -> { Instance = monsterInstance, Data = monsterData }
local serverMonsters = {}

-- Bloqueio de spawn para jogadores para evitar race conditions
local spawnLocks = {}

-- Função principal para construir monstros. Pode ser chamada de qualquer lugar no servidor.
-- @param data: Dados para construir o monstro (passado para _G.MONSTERGENERATOR.BuildMonster)
-- @param playerId (opcional): O UserId do jogador dono. Se nil, o monstro é do servidor.
-- @param opts (opcional): Tabela de opções, ex: { force = false }

function module.GetPlayerMonster(player)
	local playerId
	if typeof(player) == "number" then
		playerId = tostring(player)
	else
		playerId = tostring(player.UserId)
	end

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
			if ownerId and tonumber(ownerId) == tonumber(playerId) then
				return obj
			end
		end
	end

	-- Method 3: Find closest following monster (only if player is instance)
	if typeof(player) == "Instance" and player:IsA("Player") then
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
	end

	return nil
end

function module.BuildMonster(data, playerId, opts)
	opts = opts or {}

	-- Se um playerId for fornecido, lida com a lógica específica do jogador
	if playerId then
		-- Adquire o bloqueio para este jogador
		if spawnLocks[playerId] then
			return false, "spawn in progress"
		end
		spawnLocks[playerId] = true

		-- Verifica se o jogador já tem um monstro
		local existing = playerMonster[playerId] and playerMonster[playerId].Instance
		if existing and existing.Parent then
			if not opts.force then
				spawnLocks[playerId] = nil
				return false, "player already has a monster"
			else
				-- Destroi o monstro existente antes de criar um novo
				pcall(function() existing:Destroy() end)
				playerMonster[playerId] = nil
			end
		end
	end

	-- Chama BuildMonster de forma segura. Espera que retorne (instance, data) ou apenas instance.
	local ok, ret1, ret2 = pcall(function()
		return _G.MONSTERGENERATOR.BuildMonster(data, playerId) -- AGORA PASSA OS DADOS E O ID
	end)

	-- Libera o bloqueio do jogador se houver um
	if playerId then
		spawnLocks[playerId] = nil
	end

	if not ok then
		return false, ("BuildMonster error: %s"):format(tostring(ret1))
	end

	-- Interpreta os valores retornados
	local monsterInstance, monsterData
	if typeof(ret1) == "Instance" then
		monsterInstance = ret1
		monsterData = ret2
	else
		-- Se BuildMonster não retornou uma instância, não podemos rastreá-la.
		-- Retornamos sucesso, mas com um aviso.
		return true, { Instance = nil, Data = ret1 }
	end

	if monsterInstance then
		if playerId then
			-- Rastreia a instância para o jogador
			playerMonster[playerId] = { Instance = monsterInstance, Data = monsterData }
			print("Registered monster in local table: " .. monsterInstance.Name)

			-- Limpa a tabela quando o monstro for destruído
			monsterInstance.Destroying:Connect(function()
				print("Monster destroyed: " .. monsterInstance.Name)
				if playerMonster[playerId] and playerMonster[playerId].Instance == monsterInstance then
					playerMonster[playerId] = nil
					print("Removed from local table: " .. monsterInstance.Name)
				end
			end)

			return true, { Instance = monsterInstance, Data = monsterData }
		else
			-- É um monstro do servidor, rastreia com um ID único
			local mobId = HttpService:GenerateGUID()
			serverMonsters[mobId] = { Instance = monsterInstance, Data = monsterData }

			-- Limpa a tabela quando o monstro for destruído
			monsterInstance.Destroying:Connect(function()
				if serverMonsters[mobId] then
					serverMonsters[mobId] = nil
				end
			end)

			return true, { Instance = monsterInstance, Data = monsterData, MobId = mobId }
		end
	end

	return false, "BuildMonster did not return a valid instance."
end


-- Handler para MonsterSummon: invoca um monstro para o jogador, sem forçar a substituição.
MonsterSummon.OnServerEvent:Connect(function(player)
	local playerData = _G.DATA:Get(player.UserId)
	if not playerData then return end

	local success, result = module.BuildMonster(playerData, player.UserId, { force = false })

	if not success then
		warn(("Could not spawn for %s: %s"):format(player.Name, tostring(result)))
	else
		print(("Spawned monster for %s"):format(player.Name))
	end
end)

-- Handler para GenerateMonster: gera um novo monstro e força a substituição do antigo.
GenerateMonster.OnServerEvent:Connect(function(player)
	local playerData = _G.DATA:Get(player.UserId)
	if not playerData then return end

	-- RollMonster retorna os dados para construir um novo monstro
	local ok, rolledData = pcall(function() return _G.MONSTERGENERATOR.RollMonster(playerData, player.UserId) end)
	if not ok then
		warn(("RollMonster error for %s: %s"):format(player.Name, tostring(rolledData)))
		return
	end
	
	playerData = rolledData
	rolledData.Int = 40
	rolledData.INT = 40
	rolledData.SPD = 40
	rolledData.Speed = 40
	rolledData.HP = 500
	-- Força a substituição do monstro existente para evitar duplicatas
	local success, result = module.BuildMonster(rolledData, player.UserId, { force = true })
	

	if not success then
		warn(("Could not generate monster for %s: %s"):format(player.Name, tostring(result)))
	else
		print(("Generated and spawned new monster for %s"):format(player.Name))
	end
end)

spinResult.OnServerEvent:Connect(function(player, result)
	-- result = { name = "Good", multiplier = 1.5 }
	-- TODO: obter o monstro do player e o stat alvo (ex: via atributo, UI, ou último treino selecionado)
	local targetStat = "Strength" -- exemplo
	local gain = math.floor((BASE_GAIN[targetStat] or 2) * (result.multiplier or 1))
	-- aplique no seu data structure:
	-- local monsterData = _G.DATA:GetMonsterForPlayer(player.UserId)
	-- monsterData.Stats.Strength += gain
	print(("Player %s: %s +%d"):format(player.Name, targetStat, gain))
end)

local function UpdateMonsterMoves(monsterModel, moves)
	if not monsterModel or not moves then return end

	-- Clear existing move attributes
	for i = 1, 10 do
		monsterModel:SetAttribute("Move" .. i, nil)
	end

	-- Set new moves
	local moveCount = 0
	for i, moveInfo in ipairs(moves) do
		if moveInfo and (moveInfo.move or moveInfo.id or moveInfo.name) then
			local moveId = moveInfo.move and (moveInfo.move.id or moveInfo.move.name) or moveInfo.id or moveInfo.name
			if moveId then
				monsterModel:SetAttribute("Move" .. i, moveId)
				moveCount = moveCount + 1
			end
		elseif type(moveInfo) == "string" then
			-- Handle simple string move names
			monsterModel:SetAttribute("Move" .. i, moveInfo)
			moveCount = moveCount + 1
		end
	end

	-- Update move count attribute
	monsterModel:SetAttribute("MoveCount", moveCount)

	print("Updated " .. moveCount .. " moves for " .. monsterModel.Name)
	return moveCount
end

-- In Shared.lua, update the EvolutionRequest handler
EvolutionRequest.OnServerEvent:Connect(function(player)
	local playerId = player.UserId
	local playerData = _G.DATA:Get(playerId)

	if not playerData then
		return
	end

	-- Get current monster BEFORE evolution
	local currentMonster = module.GetPlayerMonster(player)
	local currentRace = playerData.Race
	local currentMoves = playerData.Moves or {}

	-- Start evolution process
	local success, result = _G.EVOLUTION.StartEvolution(player, playerData)

	if success then
		-- Update moves after successful evolution
		local newRace = playerData.Race
		if newRace ~= currentRace then
			-- Get new moves for the evolved race
			local EvolutionDefs = require(game.ReplicatedStorage.Modules.EvolutionDefs)
			local ctx = {
				personality = playerData.Personality,
				previousMoves = currentMoves,
				stats = playerData.Stats or {}
			}

			local newMoves = EvolutionDefs:GetMovesForRace(newRace, ctx)
			playerData.Moves = newMoves

			print("Updated moves for evolved " .. newRace .. ": " .. #newMoves .. " moves")

			-- CRITICAL: Update the monster model with new moves
			if currentMonster and currentMonster.Parent then
				UpdateMonsterMoves(currentMonster, newMoves)
				print("Updated monster model moves for " .. player.Name)
			else
				-- If monster doesn't exist, rebuild it
				module.BuildMonster(playerData, player.UserId, { force = true })
				print("Rebuilt monster after evolution for " .. player.Name)
			end
		end

		print("Evolution completed for " .. player.Name .. "'s " .. currentRace .. " -> " .. playerData.Race)
	else
		warn("Evolution failed for " .. player.Name .. ": " .. tostring(result))
	end
end)




return module