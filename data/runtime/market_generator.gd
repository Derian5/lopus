class_name MarketGenerator
extends RefCounted


const MIN_OFFERS := 5
const MAX_OFFERS := 7
static func generate_offers(
	run_state: RunState,
	registry: Node,
	stream: RngStreamState,
	first_serial: int,
	minimum_count: int = MIN_OFFERS
) -> Dictionary:
	var candidates := _collect_candidates(run_state, registry)
	minimum_count = clampi(minimum_count, MIN_OFFERS, MAX_OFFERS)
	if candidates.size() < minimum_count:
		return {"ok": false, "error": "Not enough eligible Market content."}
	var desired_count := MIN_OFFERS + int(stream.next_u32() % (MAX_OFFERS - MIN_OFFERS + 1))
	desired_count = maxi(desired_count, minimum_count)
	desired_count = mini(desired_count, candidates.size())
	var selected: Array[Dictionary] = []
	_pick_from_group(candidates, selected, stream, true)
	_pick_from_group(candidates, selected, stream, false)
	while selected.size() < desired_count and not candidates.is_empty():
		var index := _weighted_index(candidates, stream)
		selected.append(candidates[index])
		candidates.remove_at(index)

	var offers: Array[MarketOffer] = []
	var serial := first_serial
	for candidate in selected:
		var offer := MarketOffer.new()
		offer.offer_id = "market-%08d" % serial
		offer.offer_type = candidate.offer_type
		offer.content_id = candidate.content_id
		offer.price = candidate.price
		offer.target_type = candidate.target_type
		offer.target_id = candidate.target_id
		offer.allowed_job_ids = candidate.allowed_job_ids.duplicate()
		offers.append(offer)
		serial += 1
	return {
		"ok": true,
		"error": "",
		"offers": offers,
		"next_offer_serial": serial,
	}


static func hero_main_score(run_state: RunState, hero: HeroState, registry: Node) -> float:
	var score := float(hero.level * 100)
	for ability_id in hero.owned_ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		if ability != null:
			score += float(30 * hero.ability_level(ability_id))
	for instance_id in hero.item_ids:
		var item_id := run_state.inventory.get_definition_id(instance_id)
		var item := registry.get_definition(item_id, false) as ItemDefinition
		if item != null:
			score += float(item.price)
	return score


static func hero_bias_multiplier(run_state: RunState, hero: HeroState, registry: Node) -> float:
	var living: Array[HeroState] = []
	for candidate in run_state.heroes:
		if candidate.life_state != HeroState.EXECUTED:
			living.append(candidate)
	if living.size() < 2:
		return 1.0
	var minimum := INF
	var maximum := -INF
	for candidate in living:
		var score := hero_main_score(run_state, candidate, registry)
		minimum = minf(minimum, score)
		maximum = maxf(maximum, score)
	if is_equal_approx(minimum, maximum):
		return 1.0
	var neglect := (maximum - hero_main_score(run_state, hero, registry)) / (maximum - minimum)
	return 1.0 + neglect * 0.35


static func _collect_candidates(run_state: RunState, registry: Node) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var items := _definitions(registry, ItemDefinition)
	var jobs := _definitions(registry, JobDefinition)
	for item_definition in items:
		var item := item_definition as ItemDefinition
		for hero in run_state.heroes:
			var hero_definition := registry.get_definition(hero.definition_id, false) as HeroDefinition
			if hero.life_state == HeroState.EXECUTED or not item.is_compatible_with_hero(hero_definition):
				continue
			# Multiple stock copies preserve Market density without binding any copy to this Hero.
			var candidate := _candidate(
				&"hero_item", item.id, item.price,
				&"hero", "", [],
				100.0 * hero_bias_multiplier(run_state, hero, registry), true
			)
			candidate["stock_key"] = hero.unique_id
			candidates.append(candidate)

	for job_definition in jobs:
		var job := job_definition as JobDefinition
		if not run_state.unlocked_job_ids.has(job.id):
			candidates.append(_candidate(
				&"job_unlock", job.id, job.unlock_price,
				&"job", String(job.id), [job.id], 48.0, false
			))
			continue
		var capacity := int(run_state.job_capacities.get(String(job.id), 0))
		if job.id != &"job.militia" and capacity < run_state.soldiers.size():
			candidates.append(_candidate(
				&"job_capacity", job.id, job.capacity_price,
				&"job", String(job.id), [job.id], 85.0, false
			))
		var build := _find_job_build(run_state, job.id)
		if build == null:
			build = JobBuildState.new()
		for ability_id in job.available_ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			if ability == null or not build.can_purchase(ability, registry):
				continue
			candidates.append(_candidate(
				&"job_ability", ability.id, ability.price,
				&"job", String(job.id), [job.id], 100.0, false
			))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _candidate_key(a) < _candidate_key(b)
	)
	return candidates


static func _candidate(
	offer_type: StringName,
	content_id: StringName,
	price: int,
	target_type: StringName,
	target_id: String,
	allowed_job_ids: Array,
	weight: float,
	is_hero_offer: bool
) -> Dictionary:
	var restrictions: Array[StringName] = []
	for job_id in allowed_job_ids:
		restrictions.append(StringName(job_id))
	return {
		"offer_type": offer_type,
		"content_id": content_id,
		"price": price,
		"target_type": target_type,
		"target_id": target_id,
		"allowed_job_ids": restrictions,
		"weight": weight,
		"is_hero_offer": is_hero_offer,
	}


static func _pick_from_group(
	candidates: Array[Dictionary],
	selected: Array[Dictionary],
	stream: RngStreamState,
	hero_group: bool
) -> void:
	var group: Array[Dictionary] = []
	for candidate in candidates:
		if bool(candidate.is_hero_offer) == hero_group:
			group.append(candidate)
	if group.is_empty():
		return
	var picked := group[_weighted_index(group, stream)]
	selected.append(picked)
	for index in candidates.size():
		if _candidate_key(candidates[index]) == _candidate_key(picked):
			candidates.remove_at(index)
			return


static func _weighted_index(candidates: Array[Dictionary], stream: RngStreamState) -> int:
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(candidate.weight))
	if total <= 0.0:
		return int(stream.next_u32() % candidates.size())
	var roll := (float(stream.next_u32()) / 4294967296.0) * total
	for index in candidates.size():
		roll -= maxf(0.0, float(candidates[index].weight))
		if roll < 0.0:
			return index
	return candidates.size() - 1


static func _candidate_key(candidate: Dictionary) -> String:
	return "%s|%s|%s|%s" % [candidate.offer_type, candidate.content_id, candidate.target_id, candidate.get("stock_key", "")]


static func _definitions(registry: Node, script_type: Variant) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	for definition in registry.definitions.values():
		if is_instance_of(definition, script_type):
			result.append(definition)
	result.sort_custom(func(a: ContentDefinition, b: ContentDefinition) -> bool: return String(a.id) < String(b.id))
	return result


static func _find_job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	return null
