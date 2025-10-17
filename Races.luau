-- Races.luau
-- Define estágios, metadados de raças (inclui "baseRaceFamily"), e regras de evolução estilo Digimon.
-- Compatível com Summon restrito a Fledgeling para o MVP.

local Races = {}
Races.__index = Races

-- Ordem de estágios (para validação de progressão)
local STAGE = {
	Fledgeling = 1,
	Rookie     = 2,
	Champion   = 3,
	Elder      = 4,
	Unique     = 5, -- "final"/especial
}

Races.STAGE = STAGE

-- No MVP: apenas Fledgeling pode ser invocado
Races.SUMMONABLE_STAGES = {
	Fledgeling = true,
}

-- Utilitário: clamp e helpers de normalização
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function normStat(v, minV, maxV) 
	if maxV == minV then return 0 end
	return clamp((v - minV) / (maxV - minV), 0, 1) 
end

---------------------------------------------------------------------
-- DEFINIÇÃO DE RAÇAS
-- Cada entrada descreve: estágio, família base (quando aplicável),
-- se é summonável, e possíveis evoluções com gates + weights.
---------------------------------------------------------------------
local DEFINITIONS: {[string]: any} = {
	-----------------------------------------------------------------
	-- PROGENITOR FAMILY (Reality Seed caminho completo)
	-----------------------------------------------------------------
	RealitySeed = {
		displayName = "Reality Seed",
		stage = "Fledgeling",
		baseRaceFamily = "Progenitor",  -- <- usado para gates de caminhos que exigem Progenitor
		isSummonable = true,            -- MVP: este e outros Fledgelings podem ser invocados
		evolutions = {                  -- Fledgeling -> Rookie
			{
				target = "CosmicWeaver",
				requiredStage = "Rookie",
				-- Gates duros: garantem elegibilidade mínima
				gates = {
					minStats = {INT = 1},  -- exemplo simples de gate
					baseRaceFamily = "Progenitor",
				},
				-- Weights: influências probabilísticas (0~1) ponderadas
				weights = function(ctx)
					-- ctx: {stats, bond, wins, sessionTime, careMistakes, history, personality, baseRaceFamily, cameFrom}
					-- Fix: Use ctx.stats.INT instead of ctx.statsINT
					local intStat = ctx.stats.INT or ctx.stats.Intelligence or 0
					local INT = normStat(intStat, 0, 50)
					local wBond = normStat(ctx.bond or 0, 0, 100)
					-- Fledgeling → Rookie não tem afinidade de caminho ainda
					return 0.5 * INT + 0.3 * wBond + 0.2
				end,
			},
		}
	},

	CosmicWeaver = {
		displayName = "Cosmic Weaver",
		stage = "Rookie",
		baseRaceFamily = "Progenitor",
		isSummonable = false,
		evolutions = { -- Rookie -> Champion
			{
				target = "VoidWalker",
				requiredStage = "Champion",
				gates = {
					minStats = { INT = 1, SPD = 1 },  -- Very low requirements for testing
					baseRaceFamily = "Progenitor",
				},
				weights = function(ctx)
					-- Fix: Use correct stat access and handle nil values
					local intStat = ctx.stats.INT or ctx.stats.Intelligence or 0
					local spdStat = ctx.stats.SPD or ctx.stats.Speed or 0
					local INT = normStat(intStat, 0, 80)
					local wSpd = normStat(spdStat, 0, 80)
					local wBond = normStat(ctx.bond or 0, 0, 100)
					-- Afinidade por vir da forma anterior do caminho
					local pathBonus = (ctx.cameFrom == "CosmicWeaver") and 0.1 or 0
					return 0.45 * INT + 0.35 * wSpd + 0.2 * wBond + pathBonus
				end,
			},
		}
	},

	VoidWalker = {
		displayName = "Void Walker",
		stage = "Champion",
		baseRaceFamily = "Progenitor",
		isSummonable = false,
		evolutions = { -- Champion -> Elder
			{
				target = "Architect",
				requiredStage = "Elder",
				gates = {
					minStats = {INT = 40, SPD = 25 },
					minWins  = 5, -- exemplo de requisito de batalha
					baseRaceFamily = "Progenitor",
				},
				weights = function(ctx)
					-- Fix: Use ctx.stats.INT instead of ctx.statsINT
					local intStat = ctx.stats.INT or ctx.stats.Intelligence or 0
					local spdStat = ctx.stats.SPD or ctx.stats.Speed or 0
					local INT = normStat(intStat, 0, 120)
					local wSpd = normStat(spdStat, 0, 120)
					local wWins = normStat(ctx.wins or 0, 0, 20)
					local pathBonus = (ctx.cameFrom == "VoidWalker") and 0.15 or 0
					return 0.4 * INT + 0.3 * wSpd + 0.3 * wWins + pathBonus
				end,
			},
			-- (Ex.: aqui você pode adicionar ramificações alternativas de Elder, se quiser)
		}
	},

	Architect = {
		displayName = "Architect",
		stage = "Elder",
		baseRaceFamily = "Progenitor",
		isSummonable = false,
		evolutions = { -- Elder -> Unique (final)
			{
				target = "PrimeConcept",
				requiredStage = "Unique",
				gates = {
					minStats = {INT = 60, SPD = 40 },
					minBond  = 60,
					baseRaceFamily = "Progenitor",
				},
				weights = function(ctx)
					-- Fix: Use ctx.stats.INT instead of ctx.statsINT
					local intStat = ctx.stats.INT or ctx.stats.Intelligence or 0
					local spdStat = ctx.stats.SPD or ctx.stats.Speed or 0
					local INT  = normStat(intStat, 0, 160)
					local wSpd  = normStat(spdStat, 0, 160)
					local wBond = normStat(ctx.bond or 0, 0, 100)
					-- Bônus forte se vier de Architect (o passo imediatamente anterior)
					local pathBonus = (ctx.cameFrom == "Architect") and 0.25 or 0
					return 0.38 * INT + 0.32 * wSpd + 0.30 * wBond + pathBonus
				end,
			},
		}
	},

	PrimeConcept = {
		displayName = "Prime Concept",
		stage = "Unique",
		baseRaceFamily = "Progenitor",
		isSummonable = false,
		evolutions = {}, -- final
	},

	-----------------------------------------------------------------
	-- OUTROS FLEDGELINGS EXEMPLO (somente invocáveis no MVP)
	-----------------------------------------------------------------
	Core = {                   -- ex.: futuro caminho de "Construct/Golem"
		displayName = "Core",
		stage = "Fledgeling",
		baseRaceFamily = "Construct",
		isSummonable = true,
		evolutions = {}, -- preencher conforme necessário
	},

	Hopling = {                 -- ex.: futuro caminho Dino/Beast/Dragon
		displayName = "Hopling",
		stage = "Fledgeling",
		baseRaceFamily = "Beast",
		isSummonable = true,
		evolutions = {},
	},
}

---------------------------------------------------------------------
-- API PÚBLICA (retrocompatível)
---------------------------------------------------------------------
function Races:Get(name: string)
	return DEFINITIONS[name]
end

function Races:Exists(name: string): boolean
	return DEFINITIONS[name] ~= nil
end

function Races:GetStage(name: string): string?
	local def = DEFINITIONS[name]
	return def and def.stage or nil
end

function Races:IsSummonable(name: string): boolean
	local def = DEFINITIONS[name]
	if not def then return false end
	-- Mantém compat: respeita flag específica e fallback por estágio
	if def.isSummonable ~= nil then
		return def.isSummonable
	end
	return Races.SUMMONABLE_STAGES[def.stage] == true
end

function Races:GetBaseRaceFamily(name: string): string?
	local def = DEFINITIONS[name]
	return def and def.baseRaceFamily or nil
end

function Races:GetEvolutions(name: string): {any}
	local def = DEFINITIONS[name]
	return (def and def.evolutions) or {}
end

-- Lista de todas as raças válidas por estágio (útil para Summon/roll)
function Races:ListByStage(stage: string): {string}
	local out = {}
	for k, v in pairs(DEFINITIONS) do
		if v.stage == stage then
			table.insert(out, k)
		end
	end
	return out
end

-- Lista de raças summonáveis (MVP: apenas Fledgeling + flags)
function Races:ListSummonable(): {string}
	local out = {}
	for k, v in pairs(DEFINITIONS) do
		if self:IsSummonable(k) then
			table.insert(out, k)
		end
	end
	return out
end

-- Helper function to validate evolution requirements
function Races:ValidateEvolution(evolution, currentRace, targetRace)
	if not evolution then return false, "Evolution not found" end

	-- Check if target race exists
	local targetDef = DEFINITIONS[targetRace]
	if not targetDef then
		return false, "Target race does not exist: " .. tostring(targetRace)
	end

	-- Check if required stage matches target's actual stage
	if evolution.requiredStage and evolution.requiredStage ~= targetDef.stage then
		return false, string.format("Evolution stage mismatch: required %s but target is %s", 
			evolution.requiredStage, targetDef.stage)
	end

	return true
end

return setmetatable({}, Races)