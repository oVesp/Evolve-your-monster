-- ReplicatedStorage/Modules/Moves.luau
-- Recreated to align with the new Races module (Digimon-like branching; Fledgeling MVP)
-- API kept backward-compatible with existing callers (MonsterGenerator, CombatManager)

local Moves = {}
Moves.__index = Moves

---------------------------------------------------------------------
-- Rarity tiers and selection weights (cosmic convention retained)
---------------------------------------------------------------------
local RARITY = {
	Amateur    = "C",
	Advanced   = "B",
	Specialist = "A",
	Ascended   = "S",
	Primordial = "SSS",
}

local DEFAULT_RARITY_WEIGHTS = {
	Amateur    = 500,
	Advanced   = 300,
	Specialist = 150,
	Ascended   = 40,
	Primordial = 1,
}

local ORDERED_RARITIES = { "Amateur", "Advanced", "Specialist", "Ascended", "Primordial" }

local function normalizeWeights(t)
	local sum = 0
	for _, v in pairs(t) do sum += math.max(v, 0) end
	if sum == 0 then return t end
	for k, v in pairs(t) do t[k] = v / sum end
	return t
end

local function clampToMinimum(minTier, weights)
	-- Zero-out tiers below minTier
	local seen = false
	for _, r in ipairs(ORDERED_RARITIES) do
		if r == minTier then seen = true end
		if not seen then weights[r] = 0 end
	end
	return weights
end

local function resolveWeights(minRarity: string?, override: {[string]: number}?)
	local w = table.clone(DEFAULT_RARITY_WEIGHTS)
	if minRarity then clampToMinimum(minRarity, w) end
	if override then
		for k, v in pairs(override) do w[k] = v end
	end
	return normalizeWeights(w)
end

---------------------------------------------------------------------
-- Move database schema
-- Each move:
--   id, name, rarity, power, cooldown, minRange, maxRange,
--   castTime, castSpeed?, lockMovement?, effects {"Debuff"/"BuffSelf"/"Shield"/"HealSelf"/...}
--   tags {"Melee","Ranged","Magic","Progenitor","Construct","Beast"}
---------------------------------------------------------------------
local MOVES: {[string]: any} = {
	-- Universal basic
	BasicAttack = {
		id = "BasicAttack", name = "Basic Attack", rarity = "Amateur",
		power = 10, cooldown = 1.2, minRange = 0, maxRange = 6,
		castTime = 0.4, castSpeed = 1.0, lockMovement = true,
		effects = { }, tags = {"Melee", "Universal"},
	},

	-- PROGENITOR / RealitySeed line thematics
	WeavePulse = {
		id = "WeavePulse", name = "Weave Pulse", rarity = "Amateur",
		power = 14, cooldown = 2.0, minRange = 2, maxRange = 12,
		castTime = 0.6, effects = { }, tags = {"Magic","Progenitor","Ranged"},
	},
	CosmicThread = {
		id = "CosmicThread", name = "Cosmic Thread", rarity = "Advanced",
		power = 20, cooldown = 3.0, minRange = 4, maxRange = 14,
		castTime = 0.75, effects = {"Slow"}, tags = {"Magic","Progenitor","Ranged"},
	},
	VoidRay = {
		id = "VoidRay", name = "Void Ray", rarity = "Specialist",
		power = 30, cooldown = 4.0, minRange = 6, maxRange = 18,
		castTime = 0.9, effects = {"Debuff"}, tags = {"Magic","Progenitor","Ranged"},
	},
	ArchitectShield = {
		id = "ArchitectShield", name = "Architect's Shield", rarity = "Advanced",
		power = 0, cooldown = 6.0, minRange = 0, maxRange = 0,
		castTime = 0.6, effects = {"Shield","BuffSelf"}, tags = {"Progenitor","Defensive"},
	},
	PrimeConceptOverload = {
		id = "PrimeConceptOverload", name = "Prime Overload", rarity = "Ascended",
		power = 42, cooldown = 7.0, minRange = 4, maxRange = 16,
		castTime = 1.1, effects = {"Silence"}, tags = {"Magic","Progenitor"},
	},

	-- CONSTRUCT / Core thematics
	CoreBash = {
		id = "CoreBash", name = "Core Bash", rarity = "Amateur",
		power = 16, cooldown = 1.8, minRange = 0, maxRange = 5,
		castTime = 0.55, lockMovement = true, effects = {}, tags = {"Melee","Construct"},
	},
	KineticSlam = {
		id = "KineticSlam", name = "Kinetic Slam", rarity = "Advanced",
		power = 26, cooldown = 3.5, minRange = 0, maxRange = 7,
		castTime = 0.8, lockMovement = true, effects = {"Knockdown"}, tags = {"Melee","Construct"},
	},
	Overcrank = {
		id = "Overcrank", name = "Overcrank", rarity = "Specialist",
		power = 0, cooldown = 8.0, minRange = 0, maxRange = 0,
		castTime = 0.6, effects = {"BuffSelf"}, tags = {"Construct"},
	},

	-- BEAST / Hopling (boxer theme)
	PhotonJab = {
		id = "PhotonJab", name = "Photon Jab", rarity = "Amateur",
		power = 15, cooldown = 1.4, minRange = 0, maxRange = 4,
		castTime = 0.4, lockMovement = true, effects = { }, tags = {"Melee","Beast"},
	},
	FeintDash = {
		id = "FeintDash", name = "Feint Dash", rarity = "Advanced",
		power = 18, cooldown = 2.2, minRange = 0, maxRange = 10,
		castTime = 0.5, effects = {"Reposition"}, tags = {"Melee","GapClose","Beast"},
	},
	StarUppercut = {
		id = "StarUppercut", name = "Star Uppercut", rarity = "Specialist",
		power = 28, cooldown = 3.0, minRange = 0, maxRange = 5,
		castTime = 0.7, lockMovement = true, effects = {"Stun"}, tags = {"Melee","Beast"},
	},
	GuardUp = {
		id = "GuardUp", name = "Guard Up", rarity = "Amateur",
		power = 0, cooldown = 5.0, minRange = 0, maxRange = 0,
		castTime = 0.4, effects = {"BuffSelf","Shield"}, tags = {"Defensive","Beast"},
	},
}

---------------------------------------------------------------------
-- Race -> Starter pool mapping (by BaseRaceFamily)
---------------------------------------------------------------------
local STARTERS_BY_FAMILY = {
	Progenitor = {
		"BasicAttack", "WeavePulse", "CosmicThread", -- early thematic options
	},
	Construct = {
		"BasicAttack", "CoreBash",
	},
	Beast = {
		"BasicAttack", "PhotonJab", "FeintDash", "GuardUp",
	},
}

-- Fallback starters if family missing
local DEFAULT_STARTERS = { "BasicAttack" }

-- Race-specific exclusions/inclusions (extend as needed)
local FAMILY_TAG_FOR_RACE = {
	RealitySeed = "Progenitor",
	CosmicWeaver = "Progenitor",
	VoidWalker = "Progenitor",
	Architect = "Progenitor",
	PrimeConcept = "Progenitor",
	Core = "Construct",
	Hopling = "Beast",
}

---------------------------------------------------------------------
-- Pool building helpers
---------------------------------------------------------------------
local function buildPoolForFamily(family: string)
	local pool = {}
	for id, m in pairs(MOVES) do
		if table.find(m.tags, family) or table.find(m.tags, "Universal") then
			pool[id] = m
		end
	end
	-- Always ensure BasicAttack
	pool.BasicAttack = MOVES.BasicAttack
	return pool
end

local function getFamilyForRace(race: string)
	-- Prefer explicit mapping, otherwise try Races module for baseRaceFamily
	local fam = FAMILY_TAG_FOR_RACE[race]
	if fam then return fam end
	local ok, Races = pcall(function()
		return require(game.ReplicatedStorage.Modules.Races)
	end)
	if ok and Races and typeof(Races.GetBaseRaceFamily) == "function" then
		return Races:GetBaseRaceFamily(race)
	end
	return nil
end

function Moves:GetPoolForRace(race: string)
	local family = getFamilyForRace(race)
	if not family then
		-- Unknown race: allow universal + everything as a safe fallback
		local pool = {}
		for id, m in pairs(MOVES) do pool[id] = m end
		pool.BasicAttack = MOVES.BasicAttack
		return pool
	end
	return buildPoolForFamily(family)
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
function Moves:GetMove(raceOrNil: string?, id: string)
	-- race is ignored for now; kept for compatibility (future: race-tuned variants)
	return MOVES[id]
end

function Moves:GetStarterMoves(race: string)
	local family = getFamilyForRace(race)
	local ids = (family and STARTERS_BY_FAMILY[family]) or DEFAULT_STARTERS
	local out = {}
	for _, id in ipairs(ids) do
		local m = MOVES[id]
		if m then table.insert(out, { move = m, rarity = m.rarity }) end
	end
	-- Ensure at least BasicAttack
	if #out == 0 then table.insert(out, { move = MOVES.BasicAttack, rarity = MOVES.BasicAttack.rarity }) end
	return out
end

function Moves:GetRandomMoves(race: string, count: number?, minRarity: string?, weightsOverride: {[string]: number}?)
	count = math.max(1, count or 1)
	local pool = self:GetPoolForRace(race)
	local weights = resolveWeights(minRarity, weightsOverride)

	-- Build rarity buckets
	local byRarity: {[string]: {any}} = {}
	for r in pairs(DEFAULT_RARITY_WEIGHTS) do byRarity[r] = {} end
	for _, m in pairs(pool) do
		byRarity[m.rarity] = byRarity[m.rarity] or {}
		table.insert(byRarity[m.rarity], m)
	end

	local picked = {}
	for i = 1, count do
		-- roulette across rarities, then pick inside that bucket uniformly
		local roll = math.random()
		local acc = 0
		local chosenRarity: string? = nil
		for _, r in ipairs(ORDERED_RARITIES) do
			acc += (weights[r] or 0)
			if roll <= acc then chosenRarity = r break end
		end
		chosenRarity = chosenRarity or ORDERED_RARITIES[#ORDERED_RARITIES]
		local bucket = byRarity[chosenRarity]
		if not bucket or #bucket == 0 then
			bucket = byRarity["Amateur"]
		end
		local mv = bucket[math.random(1, math.max(1, #bucket))] or MOVES.BasicAttack
		picked[i] = { move = mv, rarity = mv.rarity }
	end
	return picked
end

-- Optional: expose constants for external modules
Moves.RARITY = RARITY
Moves.DEFAULT_RARITY_WEIGHTS = table.clone(DEFAULT_RARITY_WEIGHTS)

return setmetatable({}, Moves)
