class_name HeroAbilityRewardOffer
extends RefCounted


var offer_id := ""
var hero_unique_id := ""
var ability_id: StringName


func to_dictionary() -> Dictionary:
	return {
		"offer_id": offer_id,
		"hero_unique_id": hero_unique_id,
		"ability_id": String(ability_id),
	}


static func from_dictionary(data: Dictionary) -> HeroAbilityRewardOffer:
	var offer := HeroAbilityRewardOffer.new()
	offer.offer_id = String(data.get("offer_id", ""))
	offer.hero_unique_id = String(data.get("hero_unique_id", ""))
	offer.ability_id = StringName(data.get("ability_id", ""))
	return offer
