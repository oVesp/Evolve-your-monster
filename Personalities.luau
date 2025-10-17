local module = {}

module.Personalities = {
	Aggressive = {
		weights = {
			engage = 20,
			retreat = 5,
			attack = 40,
			reposition = 5,
			defend = 10,
			retarget = 10,
			buffSelf = 0,   
			debuff = 1,     
			taunt = 1,
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 1.3,
			Speed = 1.1,
			Intelligence = 0.8,
			Defense = 1.2,
			Luck = 0.9,
			Skill = 1.0}
	},
	Unpredictable = {
		weights = {
			engage = 10,
			retreat = 10,
			attack = 50,
			reposition = 10,
			defend = 10,
			retarget = 10,
			buffSelf = 10,
			debuff = 10,
			taunt = 10,
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 1.0,
			Speed = 1.4,
			Intelligence = 1.1,
			Defense = 0.9,
			Luck = 0.8,
			Skill = 1.0}
	},

	-- Prefers safe positioning and defense, but occasional overconfidence leads to taunts
	Defensive = {
		weights = {
			engage = 5,
			retreat = 15,
			attack = 15,
			reposition = 20,
			defend = 30,
			retarget = 10,
			buffSelf = 3,
			debuff = 0,
			taunt = 2,  -- Rare defensive boasting after surviving big hits
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 0.9,
			Speed = 1.0,
			Intelligence = 1.1,
			Defense = 1.4,
			Luck = 1.3,
			Skill = 1.0}
	},
	-- Focuses on setup but gets carried away with showboating
	Strategist = {
		weights = {
			engage = 10,
			retreat = 15,
			attack = 5,
			reposition = 15,
			defend = 10,
			retarget = 5,
			buffSelf = 25,
			debuff = 10,
			taunt = 5,  -- Gets cocky after successful buffs/debuffs
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 0.8,
			Speed = 0.9,
			Intelligence = 1.5,
			Defense = 1.0,
			Luck = 1.2,
			Skill = 1.0}
	},
	-- High-risk personality that often backfires
	Reckless = {
		weights = {
			engage = 25,
			retreat = 0,
			attack = 35,
			reposition = 15,
			defend = 0,
			retarget = 15,
			buffSelf = 0,
			debuff = 5,
			taunt = 5,  -- Constant provocation leads to dangerous situations
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 1.4,
			Speed = 1.3,
			Intelligence = 0.7,
			Defense = 0.8,
			Luck = 0.6,
			Skill = 1.0}
	},
	-- Team player that sometimes takes jokes too far
	Supportive = {
		weights = {
			engage = 5,
			retreat = 20,
			attack = 5,
			reposition = 10,
			defend = 25,
			retarget = 5,
			buffSelf = 15,
			debuff = 10,
			taunt = 5,  -- Well-meaning but poorly timed encouragement
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 0.9,
			Speed = 1.0,
			Intelligence = 1.3,
			Defense = 1.2,
			Luck = 1.4,
			Skill = 1.0}
	},
	-- Master of disruption who can't resist rubbing it in
	Trickster = {
		weights = {
			engage = 5,
			retreat = 15,
			attack = 10,
			reposition = 25,
			defend = 5,
			retarget = 20,
			buffSelf = 5,
			debuff = 10,
			taunt = 5,  -- Mocking enemies after successful repositioning/debuffs
			-- Training stat multipliers

		},
		trainingMultipliers = {
			Strength = 0.8,
			Speed = 1.5,
			Intelligence = 1.2,
			Defense = 0.9,
			Luck = 1.0,
			Skill = 1.0}
	}
}

function module:RollPersonality()
	local personalities = {}
	for name, data in pairs(module.Personalities) do
		table.insert(personalities, {name = name, data = data})
	end
	return personalities[math.random(1, #personalities)]
end

function module.GetDefault()
	return module.Personalities.Cautious
end

return module