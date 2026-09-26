class_name PendingHeroAbilityReward
extends RefCounted


var offers: Array[HeroAbilityRewardOffer] = []


func is_empty() -> bool:
	return offers.is_empty()


func clear() -> void:
	offers.clear()


func to_dictionary() -> Dictionary:
	var offer_data: Array = []
	for offer in offers:
		offer_data.append(offer.to_dictionary())
	return {"offers": offer_data}


static func from_dictionary(data: Dictionary) -> PendingHeroAbilityReward:
	var reward := PendingHeroAbilityReward.new()
	for offer_data in data.get("offers", []):
		if offer_data is Dictionary:
			reward.offers.append(HeroAbilityRewardOffer.from_dictionary(offer_data))
	return reward
