-- ReplicatedStorage/Modules/EvolutionDefs.lua
-- Digimon-like branching + convergence. Races decidem moves (com exceções opcionais).

local EvolutionDefs = {}

-- ===== Estágios =====
EvolutionDefs.StageOrder = { "Fledgeling","Rookie","Champion","Elder","Unique" }
EvolutionDefs.RaceStage = {
	-- Raptor line
	Raptor="Fledgeling", Dino="Rookie", Beast="Champion", Dragon="Elder", Behemoth="Elder",

	-- Construct / Core line
	Core="Fledgeling", Golem="Rookie", Titan="Champion", Colossus="Elder", PrimordialConstruct="Unique",

	-- Demonic line
	Imp="Fledgeling", Devil="Rookie", Archdemon="Champion", AbyssLord="Elder",

	-- Progenitor / Reality line
	RealitySeed="Fledgeling", CosmicWeaver="Champion", VoidWalker="Elder", Architect="Elder", PrimeConcept="Unique",

	-- Boxer / Lagomorph line
	Hopling="Fledgeling", Pugilhare="Rookie", Strikeron="Champion", Monarchare="Elder",

	-- Convergências / extras
	SteelBoxer="Elder", IronColoss="Unique", DreadBeast="Elder", SkyBehemoth="Elder",
	NetherDragon="Unique", OrderArchitect="Unique", EntropicVoid="Unique",
}

-- ===== Defaults por Path (aplica quando o edge não define prioridade/gates) =====
EvolutionDefs.DefaultPathMeta = {
	Natural     = { priority = 5 },
	Power       = { priority = 7, gates = { minWins = 3 } },
	Wisdom      = { priority = 7, gates = { minStats = { Intelligence = 15 } } },
	Friendship  = { priority = 8, gates = { minBond = 25, maxCareMistakes = 3 } },
	Corrupted   = { priority = 6, gates = { maxCareMistakes = 999 } },
}

-- ===== Ferramentas internas =====
local function meetsGates(ctx, gates)
	if not gates then return true end
	if gates.minBond and (ctx.bond or 0) < gates.minBond then return false end
	if gates.minWins and (ctx.wins or 0) < gates.minWins then return false end
	if gates.maxCareMistakes and (ctx.careMistakes or 0) > gates.maxCareMistakes then return false end
	if gates.minStats then
		for stat, minV in pairs(gates.minStats) do
			if (ctx.stats[stat] or 0) < minV then return false end
		end
	end
	if gates.personalityAnyOf and #gates.personalityAnyOf > 0 then
		local p = tostring(ctx.personality or "")
		local ok = false
		for _, name in ipairs(gates.personalityAnyOf) do
			if name == p then ok = true break end
		end
		if not ok then return false end
	end
	return true
end

local function normalizeEdges(list)
	local out = {}
	for _, v in ipairs(list or {}) do
		if typeof(v) == "string" then
			table.insert(out, { target = v })
		else
			table.insert(out, {
				target   = v.target,
				path     = v.path,
				priority = v.priority,
				gates    = v.gates,
			})
		end
	end
	return out
end

-- ===== Grafo de Evoluções (branching + convergência) =====
EvolutionDefs.EvolutionGraph = {
	-- === Raptor branch ===
	Raptor = {
		{ target="Dino", path="Natural", priority=6, gates={ minStats={ Strength=15, Speed=10 } } },
		{ target="Beast", path="Power", gates={ minWins=4, minStats={ Strength=20, Defense=12 } } },
		{ target="Dragon", path="Wisdom", gates={ minStats={ Intelligence=18, Skill=14, Speed=14 } } },
		{ target="Behemoth", path="Natural", gates={ minStats={ Defense=18, Hp=110 } } },
	},
	Dino = {
		{ target="Dragon", path="Power", priority=9, gates={ minWins=8, minStats={ Strength=35, Speed=25, Skill=20 } } },
		{ target="Behemoth", path="Natural", priority=7, gates={ minStats={ Defense=30, Hp=140 } } },
		{ target="Beast", path="Power", gates={ minWins=6, minStats={ Strength=28, Skill=18 } } },
	},
	Beast = {
		{ target="Dragon", path="Power", gates={ minWins=12, minStats={ Strength=45, Skill=30, Speed=30 } } },
		{ target="Behemoth", path="Natural", gates={ minStats={ Defense=45, Hp=180 } } },
		{ target="DreadBeast", path="Corrupted", priority=8, gates={ maxCareMistakes=999, minWins=0, minStats={ Strength=40 } } },
	},
	Dragon = {
		{ target="NetherDragon", path="Wisdom", priority=11, gates={ minBond=35, minStats={ Intelligence=50, Skill=32 } } },
	},
	Behemoth = {
		{ target="SkyBehemoth", path="Wisdom", priority=9, gates={ minStats={ Intelligence=38, Speed=34 } } },
	},

	-- === Construct / Core branch ===
	Core = {
		{ target="Golem", path="Natural", gates={ minStats={ Defense=15 } } },
		{ target="Titan", path="Power", gates={ minWins=5, minStats={ Strength=22, Defense=18 } } },
		{ target="Colossus", path="Friendship", gates={ minBond=28, minStats={ Defense=22, Hp=130 } } },
		{ target="PrimordialConstruct", path="Wisdom", priority=10, gates={ minStats={ Intelligence=30, Defense=24 } } },
	},
	Golem = {
		{ target="Titan", path="Power", priority=8, gates={ minWins=8, minStats={ Strength=34, Defense=28 } } },
		{ target="Colossus", path="Natural", gates={ minStats={ Defense=36, Hp=160 } } },
	},
	Titan = {
		{ target="Colossus", path="Natural", gates={ minStats={ Defense=44, Hp=200 } } },
		-- convergência para SteelBoxer (tema “boxe metálico”)
		{ target="SteelBoxer", path="Power", priority=8, gates={ minWins=12, minStats={ Strength=45, Defense=40, Skill=26 } } },
	},
	Colossus = {
		{ target="IronColoss", path="Friendship", priority=11, gates={ minBond=55, maxCareMistakes=2, minStats={ Defense=60, Hp=260 } } },
	},
	PrimordialConstruct = {
		-- Unique (sem evoluir por padrão)
	},

	-- === Demonic branch ===
	Imp = {
		{ target="Devil", path="Natural", gates={ minStats={ Skill=12 } } },
		{ target="Archdemon", path="Power", priority=8, gates={ minWins=6, minStats={ Strength=26, Intelligence=18 } } },
		{ target="AbyssLord", path="Corrupted", priority=9, gates={ maxCareMistakes=999, minWins=0, minStats={ Strength=24 } } },
	},
	Devil = {
		{ target="Archdemon", path="Power", gates={ minWins=10, minStats={ Strength=34, Skill=24 } } },
		{ target="AbyssLord", path="Corrupted", gates={ maxCareMistakes=999, minStats={ Strength=30, Defense=24 } } },
	},
	Archdemon = {
		{ target="AbyssLord", path="Power", priority=9, gates={ minWins=14, minStats={ Strength=44, Intelligence=30 } } },
	},
	AbyssLord = {
		-- Elder/Unique “fim de linha”
	},

	-- === Progenitor / Reality branch ===
	RealitySeed = {
		{ target="CosmicWeaver", path="Wisdom", priority=10, gates={ minBond=0, minWins=0, maxCareMistakes=3, minStats={ Intelligence=1 } } },
		{ target="VoidWalker", path="Power", gates={ minWins=5, minStats={ Strength=28, Skill=22 } } },
		{ target="Architect", path="Friendship", priority=9, gates={ minBond=30, minStats={ Intelligence=25, Defense=20 } } },
		{ target="PrimeConcept", path="Wisdom", priority=12, gates={ minBond=40, minWins=6, minStats={ Intelligence=40, Defense=28 } } },
	},
	CosmicWeaver = {
		{ target="Architect", path="Wisdom", priority=10, gates={ minBond=25, minStats={ Intelligence=50, Skill=35 } } },
		{ target="VoidWalker", path="Power", gates={ minWins=10, minStats={ Strength=45, Speed=30 } } },
		{ target="PrimeConcept", path="Friendship", priority=12, gates={ minBond=60, minWins=8, maxCareMistakes=2, minStats={ Intelligence=60, Defense=45 } } },
	},
	VoidWalker = {
		{ target="EntropicVoid", path="Corrupted", priority=11, gates={ maxCareMistakes=999, minStats={ Strength=55, Intelligence=40 } } },
	},
	Architect = {
		{ target="OrderArchitect", path="Friendship", priority=11, gates={ minBond=65, minStats={ Intelligence=62, Skill=40 } } },
	},
	PrimeConcept = {
		-- Unique
	},

	-- === Boxer / Lagomorph branch ===
	Hopling = {
		{ target="Pugilhare", path="Natural", gates={ minStats={ Skill=14, Speed=12 } } },
		{ target="Strikeron", path="Power", gates={ minWins=4, minStats={ Strength=18, Speed=14 } } },
		{ target="Monarchare", path="Friendship", gates={ minBond=26, minStats={ Skill=14, Intelligence=12 } } },
	},
	Pugilhare = {
		{ target="Strikeron", path="Power", priority=8, gates={ minWins=6, minStats={ Strength=26, Skill=22, Speed=20 } } },
		{ target="Monarchare", path="Friendship", priority=8, gates={ minBond=35, minStats={ Skill=24, Speed=20 } } },
		-- convergência para SteelBoxer
		{ target="SteelBoxer", path="Power", priority=9, gates={ minWins=10, minStats={ Strength=40, Skill=32, Speed=28 } } },
	},
	Strikeron = {
		{ target="Monarchare", path="Natural", gates={ minStats={ Skill=32, Speed=28 } } },
		{ target="SteelBoxer", path="Power", priority=9, gates={ minWins=12, minStats={ Strength=42, Skill=34, Speed=30 } } },
	},
	Monarchare = {
		{ target="SteelBoxer", path="Power", priority=8, gates={ minWins=14, minStats={ Strength=44, Skill=36 } } },
	},
	SteelBoxer = {
		-- Elder (pode convergir de múltiplos pais). Se quiser Unique final, adicione:
		-- { target="MythicPugilist", path="Friendship", priority=12, gates={ minBond=60, maxCareMistakes=2, minStats={ Skill=46, Speed=40 } } },
	},
}

-- ===== API =====
function EvolutionDefs:GetStage(race)
	return self.RaceStage[race] or "Fledgeling"
end

function EvolutionDefs:GetCandidates(currentRace, ctx)
	local raw = self.EvolutionGraph[currentRace]
	if not raw then return {} end
	local edges = normalizeEdges(raw)
	local candidates = {}

	for _, edge in ipairs(edges) do
		local path = edge.path or "Natural"
		local defaults = self.DefaultPathMeta[path] or {}
		local priority = edge.priority or defaults.priority or 0

		local mergedGates
		if defaults.gates or edge.gates then
			mergedGates = {}
			if defaults.gates then for k,v in pairs(defaults.gates) do mergedGates[k]=v end end
			if edge.gates   then for k,v in pairs(edge.gates)   do mergedGates[k]=v end end
		end

		if meetsGates(ctx or {}, mergedGates) then
			table.insert(candidates, { target=edge.target, path=path, priority=priority, gates=mergedGates })
		end
	end

	table.sort(candidates, function(a,b)
		if (a.priority or 0) == (b.priority or 0) then
			return (a.target or "") < (b.target or "")
		end
		return (a.priority or 0) > (b.priority or 0)
	end)

	return candidates
end

-- Critério padrão: maior priority; empate → alfabética. (Troque por ponderado se quiser)
function EvolutionDefs:PickEvolution(currentRace, ctx)
	local cands = self:GetCandidates(currentRace, ctx)
	return cands[1] and cands[1].target or nil
end

-- ===== Moves por Raça (raça decide por padrão) =====
EvolutionDefs.MovesByRace = {
	-- Raptor
	Raptor = { "Tackle", "Bite" },
	Dino = { "Crush", "Roar", "TailSwipe" },
	Beast = { "Pounce", "SavageClaw", "Intimidate" },
	Dragon = { "FlameBreath", "WingBuffet", "Roar" },
	Behemoth = { "Quake", "GuardBreak", "Rend" },
	NetherDragon = { "NetherFlame", "VoidWing", "AbyssRoar" },
	DreadBeast = { "Frenzy", "Ravage", "Howl" },
	SkyBehemoth = { "JetRush", "SkyQuake", "AerialGuard" },

	-- Construct
	Core = { "PebbleShot", "Harden" },
	Golem = { "RockFist", "Fortify" },
	Titan = { "Earthshatter", "Bulwark" },
	Colossus = { "SeismicSlam", "StoneWall" },
	PrimordialConstruct = { "PrimeStrike", "AegisMatrix" },
	IronColoss = { "IronDread", "MagnaWall", "CataclysmicSlam" },

	-- Demonic
	Imp = { "ImpFire", "Taunt" },
	Devil = { "HellClaw", "DarkPulse" },
	Archdemon = { "AbyssalHowl", "SoulDrain" },
	AbyssLord = { "Cataclysm", "OblivionMark" },

	-- Progenitor / Reality
	RealitySeed = { "CosmicThread", "PhaseShift" },
	CosmicWeaver = { "Singularity", "WarpLance" },
	VoidWalker = { "VoidStep", "NullSlash" },
	Architect = { "Blueprint", "Construct" },
	PrimeConcept = { "PrimeLaw", "Rewrite" },
	EntropicVoid = { "EntropyWave", "NullVortex", "Erase" },
	OrderArchitect = { "PrimeEdict", "AxiomWall", "Reconstruct" },

	-- Boxer / Lagomorph
	Hopling = { "Jab", "Feint" },
	Pugilhare = { "QuickHook", "Counter" },
	Strikeron = { "PowerStraight", "Weave" },
	Monarchare = { "RoyalGuard", "StarUpper" },
	SteelBoxer = { "MetalKnuckle", "SteelGuard", "DempseyRoll" },
}

-- Exceções de moves (opcionais)
function EvolutionDefs.ExceptionMovesForRace(race, ctx)
	-- Ex.: estrategista ganha "Feint" extra no ramo boxer
	if (race == "Pugilhare" or race == "Strikeron") and ctx.personality == "Strategist" then
		local base = EvolutionDefs.MovesByRace[race] or {}
		local out = { table.unpack(base) }
		local hasFeint = false
		for _,m in ipairs(out) do if m=="Feint" then hasFeint=true break end end
		if not hasFeint then table.insert(out, "Feint") end
		return out
	end
	-- Ex.: SteelBoxer mantém 1 move do estágio anterior (se houver)
	if race == "SteelBoxer" and ctx.previousMoves and ctx.previousMoves[1] then
		local out = { table.unpack(EvolutionDefs.MovesByRace[race] or {}) }
		table.insert(out, 1, ctx.previousMoves[1])
		return out
	end
	return nil
end

function EvolutionDefs:GetMovesForRace(race, ctx)
	local custom = self.ExceptionMovesForRace(race, ctx or {})
	if custom then return custom end
	local base = self.MovesByRace[race]
	if base and #base > 0 then return table.clone(base) end

	-- Fallback: tenta pegar do módulo Moves, se existir
	local ok, Moves = pcall(function() return require(game.ReplicatedStorage.Modules.Moves) end)
	if ok and Moves and Moves.GetStarterMoves then
		return Moves:GetStarterMoves(race)
	end
	return {}
end

-- ===== Utilidades de edição =====
function EvolutionDefs:Register(fromRace, edgeOrTarget)
	self.EvolutionGraph[fromRace] = self.EvolutionGraph[fromRace] or {}
	table.insert(self.EvolutionGraph[fromRace], edgeOrTarget)
end

function EvolutionDefs:Override(fromRace, list)
	self.EvolutionGraph[fromRace] = list or {}
end

function EvolutionDefs:SetStage(race, stage)
	self.RaceStage[race] = stage
end

function EvolutionDefs:Validate()
	local ok, errs = true, {}
	for from, list in pairs(self.EvolutionGraph) do
		for i, edge in ipairs(normalizeEdges(list)) do
			if type(edge.target) ~= "string" then
				ok = false; table.insert(errs, string.format("Edge inválida em %s[%d]: target ausente", from, i))
			end
		end
	end
	return ok, errs
end

return EvolutionDefs
