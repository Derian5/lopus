class_name MarketOffer
extends RefCounted


const TYPES: Array[StringName] = [
	&"hero_item",
	&"job_unlock",
	&"job_capacity",
	&"job_ability",
]

var offer_id := ""
var offer_type: StringName
var content_id: StringName
var price := 0
var target_type: StringName
var target_id := ""
var allowed_job_ids: Array[StringName] = []
var is_pinned := false


func is_valid() -> bool:
	if not (
		not offer_id.is_empty()
		and TYPES.has(offer_type)
		and not String(content_id).is_empty()
		and price >= 0
	):
		return false
	if offer_type == &"hero_item":
		return target_type == &"hero" and target_id.is_empty()
	if offer_type in [&"job_unlock", &"job_capacity", &"job_ability"]:
		return target_type == &"job" and not target_id.is_empty()
	return false


func to_dictionary() -> Dictionary:
	return {
		"offer_id": offer_id,
		"offer_type": String(offer_type),
		"content_id": String(content_id),
		"price": price,
		"target_type": String(target_type),
		"target_id": target_id,
		"allowed_job_ids": StateSerialization.names_to_strings(allowed_job_ids),
		"is_pinned": is_pinned,
	}


static func from_dictionary(data: Dictionary) -> MarketOffer:
	var offer := MarketOffer.new()
	offer.offer_id = String(data.get("offer_id", ""))
	offer.offer_type = StringName(data.get("offer_type", ""))
	offer.content_id = StringName(data.get("content_id", ""))
	offer.price = int(data.get("price", 0))
	offer.target_type = StringName(data.get("target_type", ""))
	offer.target_id = String(data.get("target_id", ""))
	offer.allowed_job_ids = StateSerialization.strings_to_names(data.get("allowed_job_ids", []))
	offer.is_pinned = bool(data.get("is_pinned", false))
	return offer
