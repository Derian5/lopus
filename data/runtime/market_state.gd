class_name MarketState
extends RefCounted


var offers: Array[MarketOffer] = []
var reroll_count := 0
var next_offer_serial := 1


func to_dictionary() -> Dictionary:
	var offer_data: Array = []
	for offer in offers:
		offer_data.append(offer.to_dictionary())
	return {
		"offers": offer_data,
		"reroll_count": reroll_count,
		"next_offer_serial": next_offer_serial,
	}


static func from_dictionary(data: Dictionary) -> MarketState:
	var state := MarketState.new()
	for offer_data in data.get("offers", []):
		if offer_data is Dictionary:
			state.offers.append(MarketOffer.from_dictionary(offer_data))
	state.reroll_count = int(data.get("reroll_count", 0))
	state.next_offer_serial = maxi(1, int(data.get("next_offer_serial", 1)))
	return state
