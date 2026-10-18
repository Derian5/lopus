class_name HeroAbilityRewardService
extends RefCounted


const OFFER_COUNT := 2
const UINT32_RANGE := 4294967296.0


static func prepare_reward(run_state: RunState, registry: Node) -> Dictionary:
	if run_state == null or run_state.run_status != RunState.STATUS_ACTIVE or run_state.pending_hero_ability_reward.has_active_choice():
		return {"ok": true, "error": ""}
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	if route == null:
		return _failure("Demo route definition is missing.")
	var stream := RngStreamState.from_dictionary(run_state.hero_ability_reward_rng.to_dictionary())
	while not run_state.pending_hero_ability_reward.hero_level_up_queue.is_empty():
		var hero_unique_id := run_state.pending_hero_ability_reward.hero_level_up_queue[0]
		var hero := _find_hero(run_state, hero_unique_id)
		var candidates := _candidates(hero, registry, route)
		if candidates.is_empty():
			run_state.pending_hero_ability_reward.hero_level_up_queue.pop_front()
			continue
		var offers: Array[HeroAbilityRewardOffer] = []
		var pool := candidates.duplicate()
		while offers.size() < OFFER_COUNT and not pool.is_empty():
			var selected_index := _weighted_index(pool, stream)
			var selected: Dictionary = pool[selected_index]
			pool.remove_at(selected_index)
			var offer := HeroAbilityRewardOffer.new()
			offer.offer_id = "hero-level-up-%d" % offers.size()
			offer.hero_unique_id = hero_unique_id
			offer.ability_id = selected.ability_id
			offers.append(offer)
		run_state.hero_ability_reward_rng = stream
		run_state.pending_hero_ability_reward.offers = offers
		break
	return {"ok": true, "error": ""}


static func choose(run_state: RunState, offer_id: String, registry: Node) -> Dictionary:
	if run_state == null or run_state.pending_hero_ability_reward.is_empty():
		return _failure("There is no pending Hero ability reward.")
	var selected: HeroAbilityRewardOffer
	for offer in run_state.pending_hero_ability_reward.offers:
		if offer.offer_id == offer_id:
			selected = offer
			break
	if selected == null:
		return _failure("The selected Hero ability reward is missing.")
	if run_state.pending_hero_ability_reward.hero_level_up_queue.is_empty() or run_state.pending_hero_ability_reward.hero_level_up_queue[0] != selected.hero_unique_id:
		return _failure("The selected Hero ability reward is outside the level-up queue.")
	var staged := RunState.from_dictionary(run_state.to_dictionary())
	var hero := _find_hero(staged, selected.hero_unique_id)
	var ability := registry.get_definition(selected.ability_id, false) as AbilityDefinition
	if hero == null or hero.life_state == HeroState.EXECUTED or ability == null or not ability.is_allowed_for_hero(hero.definition_id):
		return _failure("The selected Hero or ability is no longer eligible.")
	if hero.owned_ability_ids.has(ability.id):
		if not hero.upgrade_ability(ability.id):
			return _failure("That ability is already at maximum level.")
	else:
		if hero.ability_ids.size() >= HeroState.MAX_ABILITY_SLOTS:
			return _failure("That Hero has no free ability slot.")
		if not hero.unlock_ability(ability.id) or not hero.equip_ability(ability.id):
			return _failure("The new ability could not be equipped.")
	staged.pending_hero_ability_reward.offers.clear()
	staged.pending_hero_ability_reward.hero_level_up_queue.pop_front()
	var next_result := prepare_reward(staged, registry)
	if not next_result.ok:
		return next_result
	return {"ok": true, "error": "", "run_state": staged}


static func offer_level(run_state: RunState, offer: HeroAbilityRewardOffer) -> int:
	var hero := _find_hero(run_state, offer.hero_unique_id)
	if hero == null:
		return 0
	return mini(hero.ability_level(offer.ability_id) + 1, AbilityDefinition.MAX_HERO_ABILITY_LEVEL)


static func _candidates(hero: HeroState, registry: Node, route: RouteDefinition) -> Array[Dictionary]:
	if hero == null or hero.life_state == HeroState.EXECUTED:
		return []
	var abilities: Array[AbilityDefinition] = []
	for definition in registry.definitions.values():
		if definition is AbilityDefinition and definition.available_to_heroes:
			abilities.append(definition)
	abilities.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool: return a.id < b.id)
	var result: Array[Dictionary] = []
	for ability in abilities:
		if not ability.is_allowed_for_hero(hero.definition_id):
			continue
		var owned := hero.owned_ability_ids.has(ability.id)
		var current_level := hero.ability_level(ability.id)
		if owned and current_level >= AbilityDefinition.MAX_HERO_ABILITY_LEVEL:
			continue
		if not owned and hero.ability_ids.size() >= HeroState.MAX_ABILITY_SLOTS:
			continue
		var weight := route.new_hero_ability_weight
		if owned:
			weight = route.hero_ability_upgrade_weight / pow(float(current_level), route.hero_ability_upgrade_level_penalty)
		result.append({
			"ability_id": ability.id,
			"weight": weight,
		})
	return result


static func _weighted_index(candidates: Array[Dictionary], stream: RngStreamState) -> int:
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(candidate.weight))
	if total <= 0.0:
		return int(stream.next_u32() % candidates.size())
	var roll := (float(stream.next_u32()) / UINT32_RANGE) * total
	for index in candidates.size():
		roll -= maxf(0.0, float(candidates[index].weight))
		if roll < 0.0:
			return index
	return candidates.size() - 1


static func _find_hero(run_state: RunState, unique_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
