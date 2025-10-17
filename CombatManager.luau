--[[
	@ Módulo CombatManager
	@ Autor: Gemini
	@ Data: 12/10/2025
	
	Este módulo centraliza toda a lógica de gerenciamento de batalhas.
	Ele é responsável por:
	1. Iniciar e terminar sessőes de combate.
	2. Manter uma lista de todos os participantes e seus dados relevantes.
	3. Executar um loop de combate para processar as açőes de cada monstro.
	4. Determinar o vencedor e encerrar a batalha.
--]]

local CombatManager = {}
CombatManager.__index = CombatManager

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local UIRemotes = RS.Remotes:WaitForChild("CombatUI")
local HealthUpdate = UIRemotes:WaitForChild("HealthUpdate")
local TargetUpdate = UIRemotes:WaitForChild("TargetUpdate")
local AttackBanner = UIRemotes:WaitForChild("AttackBanner")


-- Módulos do jogo
local MOVES_MODULE = require(game.ReplicatedStorage.Modules.Moves)
local PERSONALITIES_MODULE = require(game.ReplicatedStorage.Modules.Personalities)
local MOVEMENT_MODULE = require(game.ReplicatedStorage.Modules.Movement) -- Adicionado
local COMBAT_ARENA = require(script.Parent:WaitForChild("CombatArena"))
local AnimationManager = require(game.ReplicatedStorage.Modules.AnimationManager)
local AnimationHandler = require(script.Parent.AnimationHandler)

--AnimationHandler:PreloadAll()


-- Tabelas para gerenciar o estado do combate
local activeCombats = {} -- Armazena todas as batalhas que estăo acontecendo
local combatParticipants = {} -- Mapeia um monstro a seu ID de combate para acesso rápido

local combatLoopConnection = nil -- Conexăo com o Heartbeat para o loop de combate

-------------------------------------------------
-- INICIALIZAÇĂO E FINALIZAÇĂO DO COMBATE --
-------------------------------------------------
local function getMonsterMoves(monsterInstance)
	local moves = {}
	local race = monsterInstance:GetAttribute("Race")

	-- Get moves from monster data if available
	local monsterData = _G.MONSTERGENERATOR and _G.MONSTERGENERATOR.GetPlayerMonsterData(monsterInstance:GetAttribute("OwnerId"))
	if monsterData and monsterData.Data and monsterData.Data.Moves then
		for _, moveInfo in ipairs(monsterData.Data.Moves) do
			if moveInfo and moveInfo.move then
				local moveData = MOVES_MODULE:GetMove(race, moveInfo.move.id)
				if moveData then
					table.insert(moves, moveData)
				end
			end
		end
	else
		-- Fallback: Get moves from attributes
		local moveCount = monsterInstance:GetAttribute("MoveCount") or 0
		for i = 1, moveCount do
			local moveId = monsterInstance:GetAttribute("Move" .. i)
			if moveId then
				local moveData = MOVES_MODULE:GetMove(race, moveId)
				if moveData then
					table.insert(moves, moveData)
				end
			end
		end
	end

	-- Always ensure basic attack is available
	local basicAttack = MOVES_MODULE:GetMove(race, "BasicAttack")
	if basicAttack and not table.find(moves, function(m) return m.id == "BasicAttack" end) then
		table.insert(moves, 1, basicAttack)
	end

	return moves
end

-- Funçăo para iniciar uma nova sessăo de combate
function CombatManager.StartCombat(participants)
	local combatId = HttpService:GenerateGUID(false)
	print("Starting combat with ID:", combatId)

	local combatData = {
		id = combatId,
		participants = {},
		teams = {},
		startTime = tick(),
		arena = nil
	}

	for _, monsterInstance in ipairs(participants) do
		if not monsterInstance or not monsterInstance.Parent then continue end

		local participantId = monsterInstance:GetAttribute("OwnerId") or monsterInstance.Name
		local race = monsterInstance:GetAttribute("Race") or "DefaultRace"
		local team = monsterInstance:GetAttribute("Team") or 1

		local combatantProfile = {
			id = participantId,
			instance = monsterInstance,
			team = team,
			stats = {
				Hp = monsterInstance:GetAttribute("Hp") or 100,
				Mp = monsterInstance:GetAttribute("Mp") or 100,
				Strength = monsterInstance:GetAttribute("Strength") or monsterInstance:GetAttribute("STR") or 10,
				Defense = monsterInstance:GetAttribute("Defense") or monsterInstance:GetAttribute("DEF") or 10,
				Skill = monsterInstance:GetAttribute("Skill") or monsterInstance:GetAttribute("SKL") or 10,
				Speed = monsterInstance:GetAttribute("Speed") or monsterInstance:GetAttribute("SPD") or 10,
				Intelligence = monsterInstance:GetAttribute("Intelligence") or monsterInstance:GetAttribute("INT") or 10,
			},
			currentHp = monsterInstance:GetAttribute("Hp") or 100,
			moves = getMonsterMoves(monsterInstance),
			personality = PERSONALITIES_MODULE.Personalities[monsterInstance:GetAttribute("Personality")] or PERSONALITIES_MODULE.Personalities.Unpredictable,
			target = nil,
			cooldowns = {},
			lastActionTime = 0,
		}

		-- Initialize cooldowns
		for _, move in ipairs(combatantProfile.moves) do
			combatantProfile.cooldowns[move.id] = 0
		end

		combatData.participants[participantId] = combatantProfile
		combatParticipants[monsterInstance] = combatId

		if not combatData.teams[team] then
			combatData.teams[team] = {}
		end
		table.insert(combatData.teams[team], combatantProfile)

		_G.STATES:SetState(monsterInstance, "InCombat")
		print("Added " .. monsterInstance.Name .. " to combat team " .. team)
	end

	-- Create arena
	local combatantInstances = {}
	for _, participant in pairs(combatData.participants) do
		table.insert(combatantInstances, participant.instance)
	end

	combatData.arena = _G.COMBAT_ARENA.CreateArena(combatantInstances, combatId)
	activeCombats[combatId] = combatData

	if not combatLoopConnection then
		combatLoopConnection = RunService.Heartbeat:Connect(CombatManager.CombatLoop)
	end

	return combatId
end

-- Funçăo para terminar uma sessăo de combate
function CombatManager.EndCombat(combatId, winningTeam)
	local combatData = activeCombats[combatId]
	if not combatData then return end

	print("Finalizando combate", combatId, "Time vencedor:", winningTeam or "Nenhum")

	-- Remove combat arena
	if combatData.arena then
		COMBAT_ARENA.RemoveArena(combatId)
	end

	print("Finalizando combate", combatId, "Time vencedor:", winningTeam or "Nenhum")

	for _, participant in pairs(combatData.participants) do
		if participant.instance and participant.instance.Parent then
			-- Remove o estado "InCombat", o que aciona a lógica de "Deactivated" no módulo States
			if _G.STATES:IsInState(participant.instance, "InCombat") then
				local st = _G.STATES:GetStorage(participant.instance)
				-- Adiciona verificaçăo para garantir que a chave existe antes de usar
				if st and st.InCombat and st.InCombat.self_key then
					_G.STATES:RemoveState(participant.instance, "InCombat", st.InCombat.self_key)
				end
			end

			-- Remove o mapeamento do participante
			combatParticipants[participant.instance] = nil
		end
	end

	-- Remove o combate da lista de combates ativos
	activeCombats[combatId] = nil

	-- Para o loop de combate se năo houver mais batalhas
	if not next(activeCombats) and combatLoopConnection then
		combatLoopConnection:Disconnect()
		combatLoopConnection = nil
		print("Todos os combates terminaram. Loop de combate parado.")
	end
end

---------------------------------------
-- LÓGICA E LOOP PRINCIPAL DO COMBATE --
---------------------------------------

function CombatManager.CombatLoop(dt)
	local currentTime = tick()
	for combatId, combatData in pairs(activeCombats) do
		-- Lógica de verificação de fim de combate - IMPROVED
		local teamsAlive = {}
		local teamMembers = {}

		-- Count alive members per team
		for teamId, teamMembersList in pairs(combatData.teams) do
			local aliveCount = 0
			teamMembers[teamId] = {}

			for _, member in ipairs(teamMembersList) do
				if member.currentHp > 0 and member.instance and member.instance.Parent then
					aliveCount = aliveCount + 1
					table.insert(teamMembers[teamId], member)
				end
			end

			if aliveCount > 0 then
				table.insert(teamsAlive, teamId)
			end
		end

		-- Check if combat should end
		if #teamsAlive <= 1 then
			local winningTeam = teamsAlive[1]
			print("Combat ended! Winning team: " .. tostring(winningTeam))

			-- Process combat results before ending
			CombatManager.ProcessCombatResults(combatData, winningTeam)

			CombatManager.EndCombat(combatId, winningTeam)
			continue
		end

		-- Process each participant's turn (existing code)
		for _, participant in pairs(combatData.participants) do
			if participant.currentHp <= 0 then continue end
			if _G.STATES:IsStunned(participant.instance) then continue end
			if (currentTime - participant.lastActionTime) < 0.3 then continue end

			CombatManager.ProcessTurn(participant, combatData)
			participant.lastActionTime = currentTime
		end
	end
end

function CombatManager.ProcessCombatResults(combatData, winningTeam)
	print("Processing combat results...")

	-- Find player monsters and enemy monsters
	local playerMonsters = {}
	local enemyMonsters = {}

	for _, participant in pairs(combatData.participants) do
		if participant.instance and participant.instance.Parent then
			local ownerId = participant.instance:GetAttribute("OwnerId")
			if ownerId then
				table.insert(playerMonsters, participant)
			else
				table.insert(enemyMonsters, participant)
			end
		end
	end

	-- Handle player monsters
	for _, playerMonster in pairs(playerMonsters) do
		local player = game.Players:GetPlayerByUserId(playerMonster.instance:GetAttribute("OwnerId"))

		if playerMonster.currentHp <= 0 then
			-- Player monster died, respawn it
			print("Respawning player monster: " .. playerMonster.instance.Name)
			if player then
				_G.STATES:RespawnPlayerMonster(player)
			end
		else
			-- Player monster survived, reset state to Following
			print("Player monster survived: " .. playerMonster.instance.Name)
			if _G.STATES:IsInState(playerMonster.instance, "InCombat") then
				local st = _G.STATES:GetStorage(playerMonster.instance)
				if st and st.InCombat and st.InCombat.self_key then
					_G.STATES:RemoveState(playerMonster.instance, "InCombat", st.InCombat.self_key)
				end
			end

			-- Heal a bit after combat
			local humanoid = playerMonster.instance:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local healAmount = playerMonster.stats.Hp * 0.3 -- 30% heal
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
				playerMonster.currentHp = humanoid.Health
			end

			_G.STATES:SetState(playerMonster.instance, "Following")
		end
	end

	-- Handle enemy monsters
	for _, enemyMonster in pairs(enemyMonsters) do
		if enemyMonster.currentHp <= 0 then
			-- Enemy died, destroy it
			print("Enemy monster died: " .. enemyMonster.instance.Name)
			enemyMonster.instance:Destroy()
		else
			-- Enemy survived, reset to idle or destroy
			print("Enemy monster survived: " .. enemyMonster.instance.Name)
			if _G.STATES:IsInState(enemyMonster.instance, "InCombat") then
				local st = _G.STATES:GetStorage(enemyMonster.instance)
				if st and st.InCombat and st.InCombat.self_key then
					_G.STATES:RemoveState(enemyMonster.instance, "InCombat", st.InCombat.self_key)
				end
			end
			_G.STATES:SetState(enemyMonster.instance, "Idle")

			-- Optional: Destroy enemy after combat ends
			-- enemyMonster.instance:Destroy()
		end
	end

	-- Award experience or other rewards here
	CombatManager.AwardCombatRewards(combatData, winningTeam)
end

-- Add function to award rewards
function CombatManager.AwardCombatRewards(combatData, winningTeam)
	-- TODO: Implement experience, items, etc.
	print("Awarding combat rewards to team " .. tostring(winningTeam))
end

-- NEW: Improved turn processing with better move selection
function CombatManager.ProcessTurn(participant, combatData)
	if not participant.target or participant.target.currentHp <= 0 then
		CombatManager.SelectNewTarget(participant, combatData)
		if not participant.target then return end
	end

	local decision = _G.FUNCTIONS:Decision(participant.personality.weights)
	local my = participant.instance
	local target = participant.target.instance
	if not (my and target and my.Parent and target.Parent) then return end

	-- Mantém dentro da arena (clamp do destino final acontece abaixo)
	local arena = combatData.arena

	-- Escolhe o melhor move disponível
	local chosenMove = CombatManager.SelectBestMove(participant, target)
	local minR = chosenMove and chosenMove.minRange or 0
	local maxR = chosenMove and chosenMove.maxRange or 8

	-- Distância atual
	local hrpA = my:FindFirstChild("HumanoidRootPart")
	local hrpT = target:FindFirstChild("HumanoidRootPart")
	if not (hrpA and hrpT) then return end
	local dist = (hrpT.Position - hrpA.Position).Magnitude

	local function clampToArena(vec3)
		if arena and _G.COMBAT_ARENA and _G.COMBAT_ARENA.IsInArenaBounds and _G.COMBAT_ARENA.GetCorrectedPosition then
			if not _G.COMBAT_ARENA.IsInArenaBounds(vec3, arena.center, arena.radius, arena.height) then
				return _G.COMBAT_ARENA.GetCorrectedPosition(vec3, arena.center, arena.radius, arena.height)
			end
		end
		return vec3
	end

	-- Helper: mover usando MOVEMENT mas respeitando arena
	local function moveChase(desired)
		_G.MOVEMENT.StartCombatChase(my, target, desired)
	end
	local function moveRetreat(by)
		_G.MOVEMENT.RetreatFrom(my, target, by)
	end
	local function moveStrafe(rad)
		_G.MOVEMENT.StrafeAround(my, target, rad)
	end

	-- === Decisão por personalidade ===
	if decision == "attack" then
		if chosenMove and dist >= minR and dist <= maxR then
			CombatManager.ExecuteMove(participant, participant.target, chosenMove)
		else
			moveChase(math.clamp(maxR * 0.9, 4, 14))
		end

	elseif decision == "engage" then
		moveChase(math.clamp(maxR * 0.8, 5, 12))

	elseif decision == "retreat" then
		moveRetreat(15)

	elseif decision == "reposition" then
		moveStrafe(10)

	elseif decision == "defend" then
		-- Mantém posição e prioriza buffs/defense se houver
		if chosenMove and chosenMove.effects and table.find(chosenMove.effects, "Shield") then
			CombatManager.ExecuteMove(participant, participant.target, chosenMove)
		else
			_G.MOVEMENT.StopCombatMovement(my)
		end

	elseif decision == "retarget" then
		CombatManager.SelectNewTarget(participant, combatData)
		moveStrafe(9)

	elseif decision == "buffSelf" or decision == "buff" then
		-- Tenta encontrar um move de buff, senão reposiciona
		local buff = CombatManager.SelectMoveByEffect(participant, {"BuffSelf","Shield","HealSelf"})
		if buff then
			CombatManager.ExecuteMove(participant, participant.target, buff)
		else
			moveStrafe(8)
		end

	elseif decision == "debuff" then
		local deb = CombatManager.SelectMoveByEffect(participant, {"Debuff","Fear","Silence"})
		if deb and dist <= (deb.maxRange or 12) then
			CombatManager.ExecuteMove(participant, participant.target, deb)
		else
			moveChase((deb and deb.maxRange) or 10)
		end

	else
		-- Fallback: perseguir
		moveChase(math.clamp(maxR * 0.9, 5, 12))
	end

	-- Se um MoveTo direto for usado em outros pontos, prenda à arena
	local hum = my:FindFirstChildOfClass("Humanoid")
	if hum and hum.WalkToPoint and hum.WalkToPoint ~= Vector3.zero then
		hum:MoveTo(clampToArena(hum.WalkToPoint))
	end
end



-- NEW: Smart move selection
function CombatManager.SelectBestMove(participant, targetInstance)
	local availableMoves = {}
	local currentTime = tick()

	for _, move in ipairs(participant.moves) do
		local lastUsed = participant.cooldowns[move.id] or 0
		if (currentTime - lastUsed) > move.cooldown then
			table.insert(availableMoves, move)
		end
	end

	if #availableMoves == 0 then return nil end

	-- Prioritize moves that are in range
	local targetDist = (targetInstance.HumanoidRootPart.Position - participant.instance.HumanoidRootPart.Position).magnitude
	local inRangeMoves = {}

	for _, move in ipairs(availableMoves) do
		if targetDist >= move.minRange and targetDist <= move.maxRange then
			table.insert(inRangeMoves, move)
		end
	end

	if #inRangeMoves > 0 then
		-- Choose randomly from in-range moves
		return inRangeMoves[math.random(1, #inRangeMoves)]
	else
		-- Choose the move with closest range to current distance
		local closestMove = nil
		local closestDiff = math.huge

		for _, move in ipairs(availableMoves) do
			local rangeDiff = math.abs((move.minRange + move.maxRange) / 2 - targetDist)
			if rangeDiff < closestDiff then
				closestDiff = rangeDiff
				closestMove = move
			end
		end

		return closestMove
	end
end

-- NEW: Improved target selection
function CombatManager.SelectNewTarget(participant, combatData)
	local myTeam = participant.team
	local best = nil
	local bestHp = math.huge
	for teamId, members in pairs(combatData.teams) do
		if teamId ~= myTeam then
			for _, m in ipairs(members) do
				if m.currentHp > 0 and m.instance and m.instance.Parent then
					-- heuristic: menor HP atual
					if m.currentHp < bestHp then
						bestHp = m.currentHp
						best = m
					end
				end
			end
		end
	end
	participant.target = best
	-- Notifica o dono (se houver) sobre o novo alvo
	local ownerId = participant.instance:GetAttribute("OwnerId")
	if ownerId then
		local plr = game.Players:GetPlayerByUserId(tonumber(ownerId))
		if plr then
			TargetUpdate:FireClient(plr, participant.instance, best and best.instance or nil)
		end
	end
end


-- Seleciona qualquer move que tenha algum dos efeitos pedidos
function CombatManager.SelectMoveByEffect(participant, effectList: {string})
	for _, mv in ipairs(participant.moves) do
		if mv.effects then
			for _, e in ipairs(mv.effects) do
				for _, wanted in ipairs(effectList) do
					if e == wanted then return mv end
				end
			end
		end
	end
	return nil
end

function CombatManager.ExecuteMove(attacker, target, move)
	-- NÃO spawnar múltiplos casts se já estiver atacando
	if AnimationHandler:IsCasting(attacker.instance) then
		return -- já tem um cast em andamento; evita spam
	end

	task.spawn(function()
		if not attacker.instance or not target.instance then return end

		-- estado e lock de movimento
		local hum = attacker.instance:FindFirstChildOfClass("Humanoid")
		local originalSpeed
		if hum and move.lockMovement then
			originalSpeed = hum.WalkSpeed
			hum.WalkSpeed = 0
		end
		_G.STATES:SetState(attacker.instance, "Attacking", 2.0) -- duração aproximada; será corrigida após medir

		-- pega a animação de cast da raça
		local race = attacker.instance:GetAttribute("Race") or "Default"
		local animData = AnimationManager:GetCastAnimation(race)

		local animData = AnimationManager:GetCastAnimation(race)
		local castLen = move.castTime or 0.8

		if _G.MOVEMENT and _G.MOVEMENT.FaceTargetDuring then
			_G.MOVEMENT.FaceTargetDuring(attacker.instance, target.instance, move.castTime or 0.6)
		end

		if animData and animData.AnimationId ~= "" then
			-- speed opcional: move.castSpeed (ex: 1.2)
			local realLen = AnimationHandler:PlayCastOnce(attacker.instance, animData.AnimationId, {
				fallback = castLen,
				speed = move.castSpeed or 1.0,
				tail = 0.06,
			})
			if realLen and realLen > 0 then castLen = realLen end
		else
			task.wait(castLen)
		end

		-- aplica o dano/efeito AO FINAL do cast
		if attacker.instance and target.instance and target.currentHp > 0 then
			local damage = move.power * (attacker.stats.Strength / math.max(1, target.stats.Defense))
			target.currentHp = math.max(0, target.currentHp - damage)
			local targetHumanoid = target.instance:FindFirstChildOfClass("Humanoid")
			if targetHumanoid then
				targetHumanoid:TakeDamage(damage)
			end
			
			-- Ao aplicar dano (dentro de ExecuteMove, logo depois de calcular e aplicar):
			if targetHumanoid then
				targetHumanoid:TakeDamage(damage)
			end
			-- Atualiza cache e notifica UIs relevantes
			attacker.cooldowns[move.id] = tick()

			-- Notifica hp do alvo para todos donos/observadores simples:
			local tgtOwnerId = target.instance:GetAttribute("OwnerId")
			if tgtOwnerId then
				local tgtPlr = game.Players:GetPlayerByUserId(tonumber(tgtOwnerId))
				if tgtPlr then
					HealthUpdate:FireClient(tgtPlr, target.instance, target.currentHp, target.stats.Hp)
				end
			end
			local atkOwnerId = attacker.instance:GetAttribute("OwnerId")
			if atkOwnerId then
				local atkPlr = game.Players:GetPlayerByUserId(tonumber(atkOwnerId))
				if atkPlr then
					-- também atualiza a barra local do atacante (caso tenha sofrido recoil, etc.)
					HealthUpdate:FireClient(atkPlr, attacker.instance, attacker.currentHp, attacker.stats.Hp)
				end
			end

			-- Ao iniciar o cast, antes de esperar o tempo/cast:
			local atkOwnerId2 = attacker.instance:GetAttribute("OwnerId")
			if atkOwnerId2 then
				local plr2 = game.Players:GetPlayerByUserId(tonumber(atkOwnerId2))
				if plr2 then
					AttackBanner:FireClient(plr2, attacker.instance, move.displayName or move.id, move.sfx or "DefaultImpact")
				end
			end
			
			attacker.cooldowns[move.id] = tick()

			local hitAnchor = target.instance:FindFirstChild("HumanoidRootPart")
				or target.instance.PrimaryPart
				or target.instance

			-- SFX (sempre que houver dano aplicado)
			if _G.EFFECTS and _G.EFFECTS.PlaySound and hitAnchor then
				_G.EFFECTS.PlaySound("DefaultImpact", {
					Where = hitAnchor,     -- onde tocar
					RandomPitch = true,    -- um pouco de variedade
					Volume = 0.9,          -- ajuste fino do volume
					Duration = 0.4,        -- duração mínima antes do fade
					FadeOutTime = 0.25,    -- fade curto
				})
			end

			-- (Opcional) brilho rápido de acerto para feedback visual
			if _G.EFFECTS and _G.EFFECTS.HitGlow then
				_G.EFFECTS.HitGlow({
					Where = target.instance,
					GlowDuration = 0.2,
					Type = "Outline",
				})
			end

			-- (Opcional) partícula de impacto, se você tiver um emissor "DefaultImpact"
			if _G.EFFECTS and _G.EFFECTS.EmitterEffect and hitAnchor then
				_G.EFFECTS.EmitterEffect({
					Name = "DefaultImpact",
					Position = hitAnchor,  -- aceita Part/HRP/Model (ajusta no módulo)
					Duration = castLen,
					Weld = hitAnchor

				})
			end
		end

		-- libera movimento/estado
		if hum and move.lockMovement and hum.Parent then
			hum.WalkSpeed = originalSpeed or hum.WalkSpeed
		end
		_G.STATES:SetState(attacker.instance, "InCombat") -- volta ao estado de combate padrão
	end)
end

function CombatManager.PlayCastAnimationOnClient(monster, animData)
	-- You'll need to implement this with a RemoteEvent
	-- Example structure:
	if animData and _G.AnimationRemote then
		_G.AnimationRemote:FireAllClients("PlayCastAnimation", monster, animData.AnimationId)
	end
end

function CombatManager.StartCombatMovement(monster, target)
	-- Inicia o movimento de combate usando o sistema de Guide Part
	_G.MOVEMENT.StartFollowing(monster, target, true)
end

function CombatManager.StopCombatMovement(monster)
	-- Para o movimento de combate
	_G.MOVEMENT.StopFollowing(monster)
end

function CombatManager.ChangeCombatTarget(monster, newTarget)
	-- Muda o alvo durante o combate
	_G.MOVEMENT.ChangeTarget(monster, newTarget, true)
end

function CombatManager.RegisterPlayerMonster(playerId, monsterModel, monsterData)
	if not CombatManager.PlayerMonsters then
		CombatManager.PlayerMonsters = {}
	end

	CombatManager.PlayerMonsters[tostring(playerId)] = {
		Model = monsterModel,
		Data = monsterData
	}

	print("Registered player monster for ID: " .. tostring(playerId) .. " - " .. monsterModel.Name)
end

-- Function to unregister a player's monster
function CombatManager.UnregisterPlayerMonster(playerId)
	if CombatManager.PlayerMonsters then
		local playerIdStr = tostring(playerId)
		if CombatManager.PlayerMonsters[playerIdStr] then
			print("Unregistered player monster for ID: " .. playerIdStr)
			CombatManager.PlayerMonsters[playerIdStr] = nil
		end
	end
end

function CombatManager.GetPlayerMonster(player)
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

function CombatManager.DebugCombatStatus()
	print("=== COMBAT DEBUG ===")
	print("Active combats: " .. tostring(next(activeCombats) and "Yes" or "No"))

	for combatId, combatData in pairs(activeCombats) do
		print("Combat ID: " .. combatId)
		for teamId, teamMembers in pairs(combatData.teams) do
			local aliveCount = 0
			for _, member in ipairs(teamMembers) do
				if member.currentHp > 0 then aliveCount = aliveCount + 1 end
			end
			print("  Team " .. teamId .. ": " .. aliveCount .. "/" .. #teamMembers .. " alive")
		end
	end
	print("===================")
end

-- Add chat command to check combat status
game:GetService("Chat"):RegisterChatCallback(Enum.ChatCallbackType.OnServerReceivingMessage, function(message, speaker)
	if message == "/combatstatus" then
		CombatManager.DebugCombatStatus()
	end
end)

return CombatManager