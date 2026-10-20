class_name MarketService
extends RefCounted


const BASE_REROLL_PRICE := 50
const REROLL_PRICE_STEP := 25


static func reroll_price(market: MarketState) -> int:
	return BASE_REROLL_PRICE + market.reroll_count * REROLL_PRICE_STEP


static func begin_visit(run_state: RunState, registry: Node) -> Dictionary:
	var staged_stream := RngStreamState.from_dictionary(run_state.market_rng.to_dictionary())
	var generated := _generate_refresh(run_state, registry, staged_stream)
	if not generated.ok:
		return _failure(generated.error)
	run_state.market_rng = staged_stream
	run_state.market.offers = generated.offers
	run_state.market.next_offer_serial = generated.next_offer_serial
	run_state.market.reroll_count = 0
	return {"ok": true, "error": ""}


static func buy_offer(run_state: RunState, offer_id: String, registry: Node, auto_equip := true) -> Dictionary:
	var offer_index := -1
	for index in run_state.market.offers.size():
		if run_state.market.offers[index].offer_id == offer_id:
			offer_index = index
			break
	if offer_index < 0:
		return _failure("That Market offer is no longer available.")
	var offer := run_state.market.offers[offer_index]
	var validation := _validate_purchase(run_state, offer, registry)
	if not validation.ok:
		return validation
	if run_state.gold < offer.price:
		return _failure("Purchase blocked: need %d Gold, have %d." % [offer.price, run_state.gold])

	match offer.offer_type:
		&"hero_item":
			run_state.inventory.create_item(offer.content_id)
		&"job_unlock":
			var key := String(offer.content_id)
			if run_state.unlocked_job_ids.has(offer.content_id):
				run_state.job_capacities[key] = int(run_state.job_capacities.get(key, 0)) + 1
			else:
				run_state.unlocked_job_ids.append(offer.content_id)
				run_state.job_capacities[key] = 1
				_ensure_job_build(run_state, offer.content_id)
		&"job_capacity":
			var key := String(offer.content_id)
			run_state.job_capacities[key] = int(run_state.job_capacities.get(key, 0)) + 1
		&"job_ability":
			var build := _ensure_job_build(run_state, StringName(offer.target_id))
			build.unlock_ability(offer.content_id)
			if auto_equip:
				build.equip_purchased_ability(registry.get_definition(offer.content_id) as AbilityDefinition)

	run_state.gold -= offer.price
	run_state.market.offers.remove_at(offer_index)
	# Older pinned/duplicate offers must not sell an already-owned or obsolete level.
	for index in range(run_state.market.offers.size() - 1, -1, -1):
		var remaining := run_state.market.offers[index]
		if remaining.offer_type == &"job_ability" and not _validate_purchase(run_state, remaining, registry).ok:
			run_state.market.offers.remove_at(index)
	return {"ok": true, "error": "", "offer": offer}


static func reroll(run_state: RunState, registry: Node) -> Dictionary:
	var price := reroll_price(run_state.market)
	if run_state.gold < price:
		return _failure("Reroll blocked: need %d Gold, have %d." % [price, run_state.gold])
	var staged_stream := RngStreamState.from_dictionary(run_state.market_rng.to_dictionary())
	var generated := _generate_refresh(run_state, registry, staged_stream)
	if not generated.ok:
		return _failure(generated.error)

	run_state.gold -= price
	run_state.market_rng = staged_stream
	run_state.market.offers = generated.offers
	run_state.market.next_offer_serial = generated.next_offer_serial
	run_state.market.reroll_count += 1
	return {"ok": true, "error": "", "price": price}


static func set_offer_pinned(run_state: RunState, offer_id: String, pinned: bool) -> Dictionary:
	for offer in run_state.market.offers:
		if offer.offer_id == offer_id:
			offer.is_pinned = pinned
			return {"ok": true, "error": "", "offer": offer}
	return _failure("That Market offer is no longer available.")


static func sell_item(run_state: RunState, instance_id: StringName, registry: Node) -> Dictionary:
	if String(instance_id).is_empty() or not run_state.inventory.has_instance(instance_id):
		return _failure("Select an owned item to sell.")
	if EquipmentService.is_instance_equipped(run_state, instance_id):
		return _failure("Unequip that item before selling it.")
	var definition_id := run_state.inventory.get_definition_id(instance_id)
	var item := registry.get_definition(definition_id, false) as ItemDefinition
	if item == null or item.sell_price <= 0:
		return _failure("That item cannot be sold.")
	if not run_state.inventory.remove_item(instance_id):
		return _failure("The selected item is no longer available.")
	run_state.gold += item.sell_price
	return {"ok": true, "error": "", "gold": item.sell_price, "item_id": definition_id}


static func _validate_purchase(run_state: RunState, offer: MarketOffer, registry: Node) -> Dictionary:
	var schema := validate_offer_schema(run_state, offer, registry)
	if not schema.ok:
		return schema
	var definition: ContentDefinition = schema.definition
	match offer.offer_type:
		&"hero_item":
			var item := definition as ItemDefinition
			if not _has_compatible_hero(run_state, item, registry):
				return _failure("No remaining Hero can equip that item.")
		&"job_unlock":
			if run_state.unlocked_job_ids.has(offer.content_id):
				if int(run_state.job_capacities.get(String(offer.content_id), 0)) >= run_state.soldiers.size():
					return _failure("That Job cannot use more capacity.")
		&"job_capacity":
			if not run_state.unlocked_job_ids.has(offer.content_id):
				return _failure("That Job is not unlocked.")
			if int(run_state.job_capacities.get(String(offer.content_id), 0)) >= run_state.soldiers.size():
				return _failure("That Job cannot use more capacity.")
		&"job_ability":
			var job_id := StringName(offer.target_id)
			var job := registry.get_definition(job_id, false) as JobDefinition
			var build := _find_job_build(run_state, job_id)
			if job == null or not run_state.unlocked_job_ids.has(job_id) or not job.available_ability_ids.has(offer.content_id):
				return _failure("This ability is not available to that Job.")
			if build == null:
				build = JobBuildState.new()
			if not build.can_purchase(definition as AbilityDefinition, registry):
				return _failure("Buy the preceding skill level first; owned or superseded levels cannot be bought again.")
	return {"ok": true, "error": ""}


static func validate_offer_schema(run_state: RunState, offer: MarketOffer, registry: Node) -> Dictionary:
	if offer == null or not offer.is_valid():
		return _failure("Market offer data is invalid.")
	var definition: ContentDefinition = registry.get_definition(offer.content_id, false)
	if definition == null:
		return _failure("Market content is missing.")
	match offer.offer_type:
		&"hero_item":
			if not definition is ItemDefinition or not offer.target_id.is_empty():
				return _failure("Hero item offer restrictions are invalid.")
			if not offer.allowed_job_ids.is_empty():
				return _failure("Hero item offer restrictions do not match its content.")
		&"job_unlock", &"job_capacity":
			if not definition is JobDefinition or offer.target_id != String(offer.content_id) or not _same_job_ids(offer.allowed_job_ids, [offer.content_id]):
				return _failure("Job offer restrictions are invalid.")
		&"job_ability":
			var job_id := StringName(offer.target_id)
			var job := registry.get_definition(job_id, false) as JobDefinition
			if not definition is AbilityDefinition or job == null or not job.available_ability_ids.has(offer.content_id):
				return _failure("Job Ability offer restrictions are invalid.")
			if not _same_job_ids(offer.allowed_job_ids, [job_id]):
				return _failure("Job Ability restrictions do not match its target.")
	return {"ok": true, "error": "", "definition": definition}


static func _find_hero(run_state: RunState, unique_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


static func _has_compatible_hero(run_state: RunState, item: ItemDefinition, registry: Node) -> bool:
	for hero in run_state.heroes:
		var definition := registry.get_definition(hero.definition_id, false) as HeroDefinition
		if hero.life_state != HeroState.EXECUTED and item.is_compatible_with_hero(definition):
			return true
	return false


static func _find_job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	return null


static func _ensure_job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	var build := _find_job_build(run_state, job_id)
	if build != null:
		return build
	build = JobBuildState.new()
	build.job_id = job_id
	run_state.job_builds.append(build)
	return build


static func _same_job_ids(first: Array[StringName], second: Array) -> bool:
	if first.size() != second.size():
		return false
	for job_id in first:
		if not second.has(job_id):
			return false
	return true


static func _generate_refresh(run_state: RunState, registry: Node, stream: RngStreamState) -> Dictionary:
	var minimum_count := MarketGenerator.MIN_OFFERS
	for index in run_state.market.offers.size():
		if _keep_pinned_offer(run_state, run_state.market.offers[index], registry):
			minimum_count = maxi(minimum_count, index + 1)
	var generated := MarketGenerator.generate_offers(
		run_state, registry, stream, run_state.market.next_offer_serial, minimum_count
	)
	if not generated.ok:
		return generated
	var refreshed: Array[MarketOffer] = []
	for offer in generated.offers:
		refreshed.append(offer)
	for index in run_state.market.offers.size():
		var pinned_offer := run_state.market.offers[index]
		if _keep_pinned_offer(run_state, pinned_offer, registry):
			refreshed[index] = pinned_offer
	generated["offers"] = refreshed
	return generated


static func _keep_pinned_offer(run_state: RunState, offer: MarketOffer, registry: Node) -> bool:
	return offer.is_pinned and (offer.offer_type != &"job_ability" or _validate_purchase(run_state, offer, registry).ok)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
