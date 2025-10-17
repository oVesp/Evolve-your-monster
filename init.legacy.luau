_G.DATA = require(script.Data)
_G.STATES = require(script.States)
_G.MOVEMENT = require(game.ReplicatedStorage.Modules.Movement)
_G.FUNCTIONS = require(script.Functions)
_G.UTILS = require(script.Utils)
_G.EFFECTS = require(game.ReplicatedStorage.Modules["Effects&SFX"])
_G.MONSTERGENERATOR = require(script.MonsterGenerator)
_G.COMBAT_ARENA = require(script.CombatArena)
_G.TRAINING_SYSTEM = require(script.TrainingSystem.Main)
_G.EVOLUTION = require(script.EvolutionManager)
--_G.DEBUGARENA = requir e(script.DebugArenaServer)
--_G.ARENA_SERVICE = require(game.ServerScriptService.Main.Game:WaitForChild("ArenaService"))
_G.COMBATMANAGER = require(script.CombatManager) -- Adiciona o novo módulo ao escopo global
--_G.COMBAT_TESTER = require(script.CombatTester)

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	player.AttributeChanged:Connect(function(attr)
		if player:GetAttribute("DataLoaded") then
			_G.GAME = require(script.Game)
			_G.NPCEventTrigger = require(script.NPCEventTrigger)
			wait(1)
			_G.NPCEventTrigger.Initialize()
			
			
		end
	end)
end)

-- ServerScriptService/Main/DebugArenaServer.lua
-- Handler dos botões do DebugUI: Arena1v1, Arena2v2, Arena4v4, ArenaFFA
-- Aggro = só spawna quando o evento é disparado

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Remotes            = ReplicatedStorage:WaitForChild("Remotes")
local CreateArenaRE      = Remotes:WaitForChild("CreateArena") -- RemoteEvent

-- Dependências do projeto
local STATES             = _G.STATES
local MONSTERGEN         = _G.MONSTERGENERATOR
local COMBATMANAGER      = _G.COMBATMANAGER
local EFFECTS            = _G.EFFECTS

-- Util: achar monstro do player (mesma estratégia do NPCEventTrigger)
local function getPlayerMonster(player: Player)
	-- 1) tabela PlayerMonsters do MONSTERGENERATOR
	if MONSTERGEN and MONSTERGEN.PlayerMonsters then
		local t = MONSTERGEN.PlayerMonsters[tostring(player.UserId)]
		if t and t.Model and t.Model.Parent then return t.Model end
	end
	-- 2) procurar por OwnerId no workspace
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerId") == player.UserId then
			return m
		end
	end
	-- 3) fallback: monstro Following mais próximo
	if player.Character and player.Character.PrimaryPart then
		local closest, best = nil, math.huge
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m ~= player.Character and m.PrimaryPart then
				local hum = m:FindFirstChildOfClass("Humanoid")
				if hum then
					local d = (m.PrimaryPart.Position - player.Character.PrimaryPart.Position).Magnitude
					if d < best and STATES and STATES:IsInState(m, "Following") then
						best, closest = d, m
					end
				end
			end
		end
		return closest
	end
	return nil
end

-- Util: forçar build de 1 NPC (sem ownerId): retorna Model
local function spawnNPC(raceDataOrNil, name)
	if not MONSTERGEN or not MONSTERGEN.BuildMonster then
		warn("[DebugArena] MONSTERGENERATOR indisponível")
		return nil
	end
	-- BuildMonster(data, playerId?) -> sem ownerId = NPC
	local ok, result = pcall(function()
		return MONSTERGEN.BuildMonster(raceDataOrNil, nil, { force = true })
	end)
	if not ok then
		warn("[DebugArena] BuildMonster NPC falhou:", result)
		return nil
	end

	local instance
	if type(result) == "table" and result.Instance then
		instance = result.Instance
	elseif typeof(ok) == "Instance" then
		instance = ok
	end
	if not instance then
		-- alguns wrappers retornam (true, {Instance=..})
		local s2, r2 = pcall(function()
			local i1, d1 = MONSTERGEN.BuildMonster(raceDataOrNil, nil)
			return i1 or (d1 and d1.Instance)
		end)
		instance = s2 and r2 or instance
	end
	if not instance then return nil end

	instance:SetAttribute("Team", 2) -- NPCs default: time inimigo
	if name then instance.Name = name; instance:SetAttribute("Name", name) end
	-- Estado inicial
	if STATES then STATES:SetState(instance, "Idle") end
	return instance
end

-- Util: posiciona um conjunto de modelos ao redor de um centro
local function radialPlace(models: {Model}, center: Vector3, radius: number)
	radius = radius or 18
	local n = #models
	for i, m in ipairs(models) do
		if m and m.PrimaryPart then
			local ang = math.rad((i-1) * (360 / n))
			local pos = center + Vector3.new(math.cos(ang)*radius, 0, math.sin(ang)*radius)
			m:SetPrimaryPartCFrame(CFrame.new(pos))
		end
	end
end

-- Build dos times conforme o modo
local function buildTeamsForMode(player: Player, mode: string)
	mode = string.upper(tostring(mode or "1V1"))

	local playerMon = getPlayerMonster(player)
	if not playerMon then
		warn("[DebugArena] Player sem monstro. Use Summon/Generate antes.")
		return nil
	end
	playerMon:SetAttribute("Team", 1)

	local team1 = { playerMon }
	local team2 = {}

	if mode == "1V1" then
		table.insert(team2, spawnNPC(nil, "Enemy_1"))
	elseif mode == "2V2" then
		-- aliado do player + 2 inimigos
		table.insert(team1, spawnNPC(nil, "Ally_1"))            -- Team será sobrescrito p/ 1
		table.insert(team2, spawnNPC(nil, "Enemy_1"))
		table.insert(team2, spawnNPC(nil, "Enemy_2"))
	elseif mode == "4V4" then
		-- 3 aliados + 4 inimigos
		for i=1,3 do table.insert(team1, spawnNPC(nil, ("Ally_%d"):format(i))) end
		for i=1,4 do table.insert(team2, spawnNPC(nil, ("Enemy_%d"):format(i))) end
	elseif mode == "FFA" then
		-- todos contra todos: player + 3 NPCs
		local ffa = { playerMon }
		for i=1,3 do table.insert(ffa, spawnNPC(nil, ("FFA_%d"):format(i))) end
		-- times distintos (um por cabeça)
		for i, m in ipairs(ffa) do if m then m:SetAttribute("Team", i) end end
		return ffa -- lista plana para o StartCombat
	else
		-- default: 1v1
		table.insert(team2, spawnNPC(nil, "Enemy_1"))
	end

	-- limpar nulos
	local function compact(t)
		local r = {}
		for _,v in ipairs(t) do if v then table.insert(r, v) end end
		return r
	end
	team1 = compact(team1)
	team2 = compact(team2)

	-- garantir times corretos
	for _, m in ipairs(team1) do if m then m:SetAttribute("Team", 1) end end
	for _, m in ipairs(team2) do if m then m:SetAttribute("Team", 2) end end

	-- retorno em lista plana ou 2 grupos
	return team1, team2
end

-- Handler principal
CreateArenaRE.OnServerEvent:Connect(function(player, payload)
	-- payload = { mode = "1v1"/"2v2"/"4v4"/"FFA", autoStart = true }
	local mode       = payload and payload.mode or "1v1"
	local autoStart  = (payload and payload.autoStart) ~= false

	-- Centro = perto do player (ou do monstro do player)
	local center = (player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position)
		or Vector3.new(0, 5, 0)

	local participants = {}

	local team1, team2 = buildTeamsForMode(player, mode)

	if mode:upper() == "FFA" then
		participants = team1 -- aqui team1 é a lista plana de FFA
	else
		for _,m in ipairs(team1 or {}) do table.insert(participants, m) end
		for _,m in ipairs(team2 or {}) do table.insert(participants, m) end
	end

	-- posicionamento radial inicial antes de iniciar combate
	radialPlace(participants, center, 18)

	-- feedback visual/sonoro leve (opcional)
	if EFFECTS and EFFECTS.PlaySound then
		EFFECTS.PlaySound("DefaultImpact", { Where = participants[1] or workspace }) -- SFX genérico
	end

	-- marca InCombat (o próprio StartCombat também força estado)
	for _, m in ipairs(participants) do
		if STATES then STATES:SetState(m, "InCombat") end
	end
	-- start!
	if autoStart and COMBATMANAGER and COMBATMANAGER.StartCombat then
		COMBATMANAGER.StartCombat(participants)
	end
end)
