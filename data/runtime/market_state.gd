class_name MarketState
extends RefCounted


var offers: Array[Dictionary] = []
var reroll_count := 0
var rng_state := 0


func to_dictionary() -> Dictionary:
	return {
		"offers": StateSerialization.dictionaries_to_data(offers),
		"reroll_count": reroll_count,
		"rng_state": rng_state,
	}


static func from_dictionary(data: Dictionary) -> MarketState:
	var state := MarketState.new()
	state.offers = StateSerialization.data_to_dictionaries(data.get("offers", []))
	state.reroll_count = int(data.get("reroll_count", 0))
	state.rng_state = int(data.get("rng_state", 0))
	return state
