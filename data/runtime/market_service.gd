class_name MarketService
extends RefCounted


const BASE_REROLL_PRICE := 50
const REROLL_PRICE_STEP := 25


static func reroll_price(market: MarketState) -> int:
	return BASE_REROLL_PRICE + market.reroll_count * REROLL_PRICE_STEP


static func begin_visit(run_state: RunState, registry: Node) -> Dictionary:
	var staged_stream := RngStreamState.from_dictionary(run_state.market_rng.to_dictionary())
	var generated := MarketGenerator.generate_offers(
		run_state, registry, staged_stream, run_state.market.next_offer_serial
	)
	if not generated.ok:
		return _failure(generated.error)
	var staged_offers: Array[MarketOffer] = []
	for offer in generated.offers:
		staged_offers.append(offer)
	run_state.market_rng = staged_stream
	run_state.market.offers = staged_offers
	run_state.market.next_offer_serial = generated.next_offer_serial
	run_state.market.reroll_count = 0
	return {"ok": true, "error": ""}


static func buy_offer(run_state: RunState, offer_id: String, registry: Node) -> Dictionary:
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
			run_state.inventory.create_item(offer.content_id, offer.target_id)
		&"soldier_item":
			run_state.inventory.create_item(offer.content_id)
		&"job_unlock":
			run_state.unlocked_job_ids.append(offer.content_id)
			run_state.job_capacities[String(offer.content_id)] = 1
			_ensure_job_build(run_state, offer.content_id)
		&"job_capacity":
			var key := String(offer.content_id)
			run_state.job_capacities[key] = int(run_state.job_capacities.get(key, 0)) + 1
		&"job_ability":
			_ensure_job_build(run_state, StringName(offer.target_id)).unlock_ability(offer.content_id)

	run_state.gold -= offer.price
	run_state.market.offers.remove_at(offer_index)
	return {"ok": true, "error": "", "offer": offer}


static func reroll(run_state: RunState, registry: Node) -> Dictionary:
	var price := reroll_price(run_state.market)
	if run_state.gold < price:
		return _failure("Reroll blocked: need %d Gold, have %d." % [price, run_state.gold])
	var staged_stream := RngStreamState.from_dictionary(run_state.market_rng.to_dictionary())
	var generated := MarketGenerator.generate_offers(
		run_state, registry, staged_stream, run_state.market.next_offer_serial
	)
	if not generated.ok:
		return _failure(generated.error)
	var staged_offers: Array[MarketOffer] = []
	for offer in generated.offers:
		staged_offers.append(offer)

	run_state.gold -= price
	run_state.market_rng = staged_stream
	run_state.market.offers = staged_offers
	run_state.market.next_offer_serial = generated.next_offer_serial
	run_state.market.reroll_count += 1
	return {"ok": true, "error": "", "price": price}


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
			var hero := _find_hero(run_state, offer.target_id)
			if hero == null or hero.life_state == HeroState.EXECUTED:
				return _failure("That Hero is not eligible for Market offers.")
		&"job_unlock":
			if run_state.unlocked_job_ids.has(offer.content_id):
				return _failure("That Job is already unlocked.")
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
			if build != null and build.owned_ability_ids.has(offer.content_id):
				return _failure("That Job already owns this ability.")
	return {"ok": true, "error": ""}


static func validate_offer_schema(run_state: RunState, offer: MarketOffer, registry: Node) -> Dictionary:
	if offer == null or not offer.is_valid():
		return _failure("Market offer data is invalid.")
	var definition: ContentDefinition = registry.get_definition(offer.content_id, false)
	if definition == null:
		return _failure("Market content is missing.")
	match offer.offer_type:
		&"hero_item":
			if not definition is ItemDefinition or definition.allowed_target_type != &"hero" or _find_hero(run_state, offer.target_id) == null:
				return _failure("Hero item offer restrictions are invalid.")
			if not _same_job_ids(offer.allowed_job_ids, definition.allowed_job_ids):
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
		&"soldier_item":
			if not definition is ItemDefinition or definition.allowed_target_type != &"soldier" or not offer.target_id.is_empty():
				return _failure("Soldier item offer restrictions are invalid.")
			if not _same_job_ids(offer.allowed_job_ids, definition.allowed_job_ids):
				return _failure("Soldier item offer restrictions do not match its content.")
	return {"ok": true, "error": "", "definition": definition}


static func _find_hero(run_state: RunState, unique_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


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


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
