class_name PendingHeroAbilityReward
extends RefCounted


var offers: Array[HeroAbilityRewardOffer] = []
var hero_level_up_queue: Array[String] = []


func is_empty() -> bool:
	return offers.is_empty() and hero_level_up_queue.is_empty()


func has_active_choice() -> bool:
	return not offers.is_empty()


func queue_level_ups(hero_unique_id: String, count: int) -> void:
	for _index in maxi(count, 0):
		hero_level_up_queue.append(hero_unique_id)


func clear() -> void:
	offers.clear()
	hero_level_up_queue.clear()


func to_dictionary() -> Dictionary:
	var offer_data: Array = []
	for offer in offers:
		offer_data.append(offer.to_dictionary())
	return {
		"offers": offer_data,
		"hero_level_up_queue": hero_level_up_queue.duplicate(),
	}


static func from_dictionary(data: Dictionary) -> PendingHeroAbilityReward:
	var reward := PendingHeroAbilityReward.new()
	for offer_data in data.get("offers", []):
		if offer_data is Dictionary:
			reward.offers.append(HeroAbilityRewardOffer.from_dictionary(offer_data))
	for hero_unique_id in data.get("hero_level_up_queue", []):
		reward.hero_level_up_queue.append(String(hero_unique_id))
	# Version 8 saves stored a single encounter reward without a level-up queue.
	if reward.hero_level_up_queue.is_empty() and not reward.offers.is_empty():
		var hero_unique_id := reward.offers[0].hero_unique_id
		reward.hero_level_up_queue.append(hero_unique_id)
		reward.offers = reward.offers.filter(func(offer: HeroAbilityRewardOffer) -> bool: return offer.hero_unique_id == hero_unique_id)
		if reward.offers.size() > HeroAbilityRewardService.OFFER_COUNT:
			reward.offers.resize(HeroAbilityRewardService.OFFER_COUNT)
	return reward
