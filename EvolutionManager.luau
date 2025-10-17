--[[
    EvolutionManager.lua
    Responsável por: checar requisitos, decidir evolução, aplicar boosts/moves,
    reconstruir o monstro, reposicionar e notificar o client.

    Dependências usadas no seu projeto:
      - _G.DATA                (sistema de dados com proxy)
      - _G.MONSTERGENERATOR    (BuildMonster / RollMonster)
      - ReplicatedStorage.Modules.Races (GetEvolutions / GetStage)
      - ReplicatedStorage.Modules.Moves (GetStarterMoves)
      - Remotes: EvolutionRequest (client->server), EvolutionEffect (server->client), EvolutionComplete (server->client)
]]

local EvolutionManager = {}
EvolutionManager.__index = EvolutionManager

-- Services
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- Remotes
local Remotes = RS:WaitForChild("Remotes")
local EvolutionRequest = Remotes:WaitForChild("EvolutionRequest")
local EvolutionEffect  = Remotes:WaitForChild("EvolutionEffect")
local EvolutionComplete = Remotes:WaitForChild("EvolutionComplete")

-- Modules
local Moves = require(RS.Modules.Moves)
local Races = require(RS.Modules.Races)
local EvoDef = require(RS.Modules.EvolutionDefs)

-- Config
local EFFECT_DURATION = 2.0 -- segundos antes de aplicar a evolução (tempo do VFX)

-- Multiplicadores por estágio (ajuste livre)
-- Multiplicadores por estágio
local EVOLUTION_BOOSTS = {
	Fledgeling = { Hp=1.10, Mp=1.10, Strength=1.05, Defense=1.05, Skill=1.05, Speed=1.05, Intelligence=1.05, Luck=1.05 },
	Rookie     = { Hp=1.12, Mp=1.12, Strength=1.08, Defense=1.08, Skill=1.06, Speed=1.06, Intelligence=1.08, Luck=1.06 },
	Champion   = { Hp=1.15, Mp=1.15, Strength=1.12, Defense=1.12, Skill=1.10, Speed=1.10, Intelligence=1.12, Luck=1.10 },
	Elder      = { Hp=1.18, Mp=1.18, Strength=1.16, Defense=1.16, Skill=1.12, Speed=1.12, Intelligence=1.16, Luck=1.12 },
	Unique     = { Hp=1.22, Mp=1.22, Strength=1.20, Defense=1.20, Skill=1.15, Speed=1.15, Intelligence=1.20, Luck=1.15 },
}

-- Bônus flat por estágio (ajuste fino por design)
local EVOLUTION_FLAT_ADDS = {
	Fledgeling = { Hp=0,  Mp=0 },
	Rookie     = { Hp=20, Mp=10 },
	Champion   = { Hp=35, Mp=15 },
	Elder      = { Hp=50, Mp=20 },
	Unique     = { Hp=80, Mp=30 },
}

-- ===== Utils =====

local function clampInt(n) return math.floor(math.max(1, n or 1)) end

local function aliasWrite(stats, key, value)
	stats[key] = value
	-- alias simples para compatibilidade
	if key == "Hp" or key == "HP" then stats.HP = value stats.Hp = value end
	if key == "Mp" or key == "MP" then stats.MP = value stats.Mp = value end
	return stats
end

function applyStatBoosts(statsTable, newStage)
	local stats = statsTable or {}
	-- defaults garantidos
	stats.Hp = stats.Hp or stats.HP or 100
	stats.Mp = stats.Mp or stats.MP or 50

	local mul = EVOLUTION_BOOSTS[newStage]
	local add = EVOLUTION_FLAT_ADDS[newStage]

	if mul then
		for k, v in pairs(mul) do
			local curr = stats[k] or stats[string.upper(k)] or stats[string.sub(k,1,1):upper()..string.sub(k,2)]
			if typeof(curr) == "number" then
				aliasWrite(stats, k, math.max(1, math.floor(curr * v)))
			end
		end
	end

	if add then
		for k, v in pairs(add) do
			local curr = stats[k] or stats[string.upper(k)] or stats[string.sub(k,1,1):upper()..string.sub(k,2)]
			if typeof(curr) == "number" then
				aliasWrite(stats, k, math.max(1, math.floor(curr + v)))
			end
		end
	end

	-- clamp simples para evitar zeros/negativos
	for _, key in ipairs({ "Hp","HP","Mp","MP","Strength","Defense","Skill","Speed","Intelligence","Luck","STR","DEF","SKL","SPD","INT","LCK" }) do
		if typeof(stats[key]) == "number" then
			stats[key] = math.max(1, math.floor(stats[key]))
		end
	end

	return stats
end

-- Procura o modelo do monstro do jogador por atributo "OwnerId" (fallback robusto).
function EvolutionManager.FindPlayerMonster(player: Player)
	local uid = player.UserId
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("OwnerId") == uid then
			return inst
		end
	end
	-- Se você tiver um cache próprio (ex.: _G.PlayerMonsters[uid]), pode usar aqui.
	return nil
end

local function meetsGates(ctx, gates)
	if not gates then return true end
	if gates.baseRaceFamily and gates.baseRaceFamily ~= ctx.baseRaceFamily then return false end
	if gates.minBond and (ctx.bond or 0) < gates.minBond then return false end
	if gates.minWins and (ctx.wins or 0) < gates.minWins then return false end
	if gates.maxCareMistakes and (ctx.careMistakes or 0) > gates.maxCareMistakes then return false end
	if gates.minStats then
		for stat, minV in pairs(gates.minStats) do
			if (ctx.stats[stat] or 0) < minV then return false end
		end
	end
	return true
end

-- ===== Core API =====

-- Decide a evolução com base em Races:GetEvolutions(race)
function EvolutionManager.TryEvolve(monsterData)
	local currentRace = monsterData and monsterData.Race
	if not currentRace then
		return false, "No current race on monsterData"
	end

	local options = Races:GetEvolutions(currentRace)
	if not options or #options == 0 then
		return false, ("No evolutions available for %s"):format(tostring(currentRace))
	end

	local ctx = {
		stats = monsterData.Stats or {},
		bond = monsterData.Bond or 0,
		wins = monsterData.Wins or 0,
		sessionTime = monsterData.SessionTime or 0,
		careMistakes = monsterData.CareMistakes or 0,
		personality = monsterData.Personality,
		baseRaceFamily = monsterData.BaseRaceFamily,
		cameFrom = currentRace,
		history = monsterData.History or {},
	}
	

	local eligible = {}
	for _, evo in ipairs(options) do
		if meetsGates(ctx, evo.gates) then
			table.insert(eligible, evo)
		end
	end
	if #eligible == 0 then
		return false, "Evolution requirements not met"
	end

	table.sort(eligible, function(a, b)
		return (a.priority or 0) > (b.priority or 0)
	end)

	return true, eligible[1].target
end

-- Inicia o processo de evolução (chamado via Remote ou server)
function EvolutionManager.StartEvolution(player: Player)
	if not player or not player.UserId then
		return false, "Invalid player"
	end

	local playerData = _G.DATA:Get(player.UserId)
	if not playerData then
		warn("[EvolutionManager] No playerData for", player)
		return false, "No player data"
	end

	-- Decide evolução
	local ok, targetOrReason = EvolutionManager.TryEvolve(playerData)
	if not ok then
		return false, targetOrReason -- <- AGORA RETORNA MOTIVO
	end

	-- Pega posição atual p/ o FX e reposicionamento
	local currentModel = EvolutionManager.FindPlayerMonster(player)
	local pivotCFrame = currentModel and currentModel:GetPivot()
		or (player.Character and player.Character:GetPivot())
		or CFrame.new()

	-- Dispara FX no cliente
	EvolutionEffect:FireClient(player, pivotCFrame.Position, targetOrReason)

	-- Agenda a aplicação real (continua assíncrono)
	task.delay(EFFECT_DURATION, function()
		EvolutionManager.CompleteEvolution(player, targetOrReason, pivotCFrame)
		local newRace = playerData.Race
		local EvolutionDefs = require(game.ReplicatedStorage.Modules.EvolutionDefs)

		local ctx = {
			personality = playerData.Personality,
			previousMoves = playerData.Moves or {},
			stats = playerData.Stats or {},
			bond = playerData.Bond or 0,
			wins = playerData.Wins or 0
		}

		playerData.Moves = EvolutionDefs:GetMovesForRace(newRace, ctx)
	end)

	return true, targetOrReason -- <- AGORA SINALIZA “começou” e qual alvo
end

-- ===== Moves Merge Config =====
local MAX_MOVES = 4

local RARITY_ORDER = { Amateur = 1, Advanced = 2, Specialist = 3, Ascended = 4, Primordial = 5 }
local function rarityScore(mv)
	return RARITY_ORDER[(mv and mv.rarity) or "Amateur"] or 1
end

local MAX_MOVES = 4

local function toMoveObj(entry)
	if not entry then return nil end
	if typeof(entry) == "string" then
		local mv = Moves:GetMove(nil, entry)
		return mv and { move = mv, rarity = mv.rarity } or nil
	elseif typeof(entry) == "table" then
		if entry.move and entry.move.id then return { move = entry.move, rarity = entry.rarity or entry.move.rarity } end
		if entry.id then return { move = entry, rarity = entry.rarity} end
	end
	return nil
end

local function dedupe(list)
	local seen, out = {}, {}
	for _, e in ipairs(list or {}) do
		local obj = toMoveObj(e)
		if obj and obj.move and obj.move.id and not seen[obj.move.id] then
			table.insert(out, obj); seen[obj.move.id] = true
		end
	end
	return out
end

local function ensureBasicAttack(list)
	for _, e in ipairs(list) do if e.move.id == "BasicAttack" then return end end
	local ba = Moves:GetMove(nil, "BasicAttack")
	if ba then table.insert(list, { move = ba, rarity = ba.rarity }) end
end

local function trimToMax(list, maxCount)
	if #list <= maxCount then return list end
	table.sort(list, function(a,b)
		if a.move.id == "BasicAttack" and b.move.id ~= "BasicAttack" then return true end
		if b.move.id == "BasicAttack" and a.move.id ~= "BasicAttack" then return false end
		return rarityScore(a) > rarityScore(b)
	end)
	local cut = {}
	for i=1, maxCount do cut[i] = list[i] end
	return dedupe(cut)
end

local function mergeMovesKeepingOld(prevMoves, startersAnyFormat, newRace)
	local merged = {}
	for _, e in ipairs(prevMoves or {}) do table.insert(merged, e) end
	for _, s in ipairs(startersAnyFormat or {}) do table.insert(merged, s) end

	-- se startersAnyFormat vier vazio (ou inválido), cai pro Moves:GetStarterMoves
	if not startersAnyFormat or #startersAnyFormat == 0 then
		local fallback = Moves:GetStarterMoves(newRace) or {}
		for _, s in ipairs(fallback) do table.insert(merged, s) end
	end

	merged = dedupe(merged)
	ensureBasicAttack(merged)
	return trimToMax(merged, MAX_MOVES)
end

-- Aplica a evolução de fato (atualiza dados, reconstrói, reposiciona, notifica)
function EvolutionManager.CompleteEvolution(player: Player, newRaceName: string, oldPivot: CFrame?)
	if not player then return end

	local playerData = _G.DATA:Get(player.UserId)
	if not playerData then
		warn("[EvolutionManager] No playerData on CompleteEvolution")
		return
	end

	-- Atualiza playerData
	playerData.Race = newRaceName
	playerData.Stage = Races:GetStage(newRaceName)
	playerData.Stats = applyStatBoosts(playerData.Stats or {}, playerData.Stage)
	
	local startersList = EvoDef:GetMovesForRace(newRaceName, {
		personality  = playerData.Personality,
		previousMoves= playerData.Moves,
		stats        = playerData.Stats,
	}) or {}

	playerData.Moves = mergeMovesKeepingOld(playerData.Moves, startersList, newRaceName)

	playerData.History = playerData.History or {}
	table.insert(playerData.History, newRaceName)

	-- Destroi o modelo atual (para evitar duplicatas)
	local currentModel = EvolutionManager.FindPlayerMonster(player)
	if currentModel then
		currentModel:Destroy()
	end

	-- Reconstrói com os dados atualizados
	local okBuild, res = true, nil
	if _G.MONSTERGENERATOR and _G.MONSTERGENERATOR.BuildMonster then
		okBuild, res = _G.MONSTERGENERATOR.BuildMonster(playerData, player.UserId, { force = true })
	else
		okBuild, res = false, "Missing _G.MONSTERGENERATOR.BuildMonster"
	end

	if not okBuild then
		warn("[EvolutionManager] Build after evolution failed:", res)
		return
	end

	-- Reposiciona no pivot antigo (se existir)
	task.wait(0.2)
	local newModel = EvolutionManager.FindPlayerMonster(player)
	if newModel and oldPivot then
		newModel:PivotTo(oldPivot)
	end

	-- Notifica conclusão
	EvolutionComplete:FireClient(player, newRaceName)
end

-- ===== Inicialização e binding de Remotes =====

function EvolutionManager.Init()
	-- Evita múltiplos binds (idempotente)
	if EvolutionManager._inited then return end
	EvolutionManager._inited = true

	-- Request vindo do client
	EvolutionRequest.OnServerEvent:Connect(function(player)
		EvolutionManager.StartEvolution(player)
	end)
end

return EvolutionManager
