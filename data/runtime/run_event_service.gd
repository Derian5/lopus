class_name RunEventService
extends RefCounted


const UINT32_RANGE := 4294967296.0


static func prepare_event(run_state: RunState, registry: Node) -> Dictionary:
	if run_state == null or run_state.run_status != RunState.STATUS_ACTIVE or not run_state.pending_event.is_empty():
		return {"ok": true, "error": ""}
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	if route == null:
		return {"ok": false, "error": "Demo route definition is missing."}
	var scripted_event_id := route.post_battle_event_id(run_state.current_act, run_state.encounter_index)
	if not String(scripted_event_id).is_empty():
		return prepare_specific_event(run_state, scripted_event_id, registry)
	var staged_stream := RngStreamState.from_dictionary(run_state.event_rng.to_dictionary())
	var candidates: Array[RunEventDefinition] = []
	for definition in registry.definitions.values():
		if not definition is RunEventDefinition:
			continue
		var event := definition as RunEventDefinition
		if event.weight <= 0.0 or (event.one_time and run_state.triggered_event_ids.has(event.id)):
			continue
		if not _conditions_met(event.conditions, run_state, [], registry):
			continue
		if _eligible_soldiers(run_state, event).size() < event.soldier_target_count:
			continue
		candidates.append(event)
	candidates.sort_custom(func(a: RunEventDefinition, b: RunEventDefinition) -> bool: return a.id < b.id)
	if candidates.is_empty():
		return {"ok": true, "error": ""}
	var absence_roll := (float(staged_stream.next_u32()) / UINT32_RANGE) * 100.0
	if absence_roll < route.event_absence_percent:
		run_state.event_rng = staged_stream
		return {"ok": true, "error": ""}
	var total_weight := 0.0
	for event in candidates:
		total_weight += event.weight
	if total_weight <= 0.0:
		return {"ok": true, "error": ""}
	var roll := (float(staged_stream.next_u32()) / UINT32_RANGE) * total_weight
	var selected: RunEventDefinition
	for event in candidates:
		if roll < event.weight:
			selected = event
			break
		roll -= event.weight
	if selected == null:
		run_state.event_rng = staged_stream
		return {"ok": true, "error": ""}
	var eligible := _eligible_soldiers(run_state, selected)
	var target_ids: Array[String] = []
	for index in selected.soldier_target_count:
		var selected_index := int(staged_stream.next_u32() % eligible.size())
		target_ids.append(eligible[selected_index].unique_id)
		eligible.remove_at(selected_index)
	run_state.event_rng = staged_stream
	run_state.pending_event.event_id = selected.id
	run_state.pending_event.node_id = selected.entry_node_id
	run_state.pending_event.target_ids = target_ids
	if selected.one_time and not run_state.triggered_event_ids.has(selected.id):
		run_state.triggered_event_ids.append(selected.id)
	return {"ok": true, "error": ""}


static func prepare_specific_event(run_state: RunState, event_id: StringName, registry: Node) -> Dictionary:
	if run_state == null or run_state.run_status != RunState.STATUS_ACTIVE or not run_state.pending_event.is_empty():
		return {"ok": true, "error": ""}
	var event := registry.get_definition(event_id, false) as RunEventDefinition
	if event == null:
		return {"ok": false, "error": "Scripted Run Event %s is missing." % event_id}
	if event.one_time and run_state.triggered_event_ids.has(event.id):
		return {"ok": true, "error": ""}
	if not _conditions_met(event.conditions, run_state, [], registry):
		return {"ok": false, "error": "Scripted Run Event %s does not meet its conditions." % event.id}
	var eligible := _eligible_soldiers(run_state, event)
	if eligible.size() < event.soldier_target_count:
		return {"ok": false, "error": "Scripted Run Event %s has too few eligible Soldier targets." % event.id}
	var staged_stream := RngStreamState.from_dictionary(run_state.event_rng.to_dictionary())
	var target_ids: Array[String] = []
	for index in event.soldier_target_count:
		var selected_index := int(staged_stream.next_u32() % eligible.size())
		target_ids.append(eligible[selected_index].unique_id)
		eligible.remove_at(selected_index)
	run_state.event_rng = staged_stream
	run_state.pending_event.event_id = event.id
	run_state.pending_event.node_id = event.entry_node_id
	run_state.pending_event.target_ids = target_ids
	if event.one_time:
		run_state.triggered_event_ids.append(event.id)
	return {"ok": true, "error": ""}


static func choose(run_state: RunState, choice_id: StringName, registry: Node) -> Dictionary:
	if run_state == null or run_state.pending_event.is_empty():
		return {"ok": false, "error": "There is no pending event."}
	var event := registry.get_definition(run_state.pending_event.event_id, false) as RunEventDefinition
	var node := event.get_node_definition(run_state.pending_event.node_id) if event != null else null
	if node == null:
		return {"ok": false, "error": "The pending event node is missing."}
	var choice: RunEventChoice
	for candidate in node.choices:
		if candidate != null and candidate.choice_id == choice_id:
			choice = candidate
			break
	if choice == null:
		return {"ok": false, "error": "The selected event choice is missing."}
	var staged := RunState.from_dictionary(run_state.to_dictionary())
	var status := _apply_choice(staged, choice, registry)
	if not status.ok:
		return status
	var reward_status := HeroAbilityRewardService.prepare_reward(staged, registry)
	if not reward_status.ok:
		return reward_status
	if String(choice.next_node_id).is_empty():
		staged.pending_event.clear()
	else:
		staged.pending_event.node_id = choice.next_node_id
	return {"ok": true, "error": "", "run_state": staged}


static func choice_status(run_state: RunState, choice: RunEventChoice, registry: Node) -> Dictionary:
	if choice == null:
		return {"ok": false, "error": "Choice is missing."}
	var staged := RunState.from_dictionary(run_state.to_dictionary())
	return _apply_choice(staged, choice, registry)


static func _apply_choice(run_state: RunState, choice: RunEventChoice, registry: Node) -> Dictionary:
	var target_ids := run_state.pending_event.target_ids
	if not _conditions_met(choice.conditions, run_state, target_ids, registry):
		return {"ok": false, "error": "Requirements are not met."}
	for effect in choice.effects:
		var result := _apply_effect(run_state, target_ids, effect, registry)
		if not result.ok:
			return result
	return {"ok": true, "error": ""}


static func _apply_effect(run_state: RunState, target_ids: Array[String], effect: RunEventEffect, registry: Node) -> Dictionary:
	if effect == null:
		return {"ok": false, "error": "Event effect is missing."}
	match effect.effect_type:
		RunEventEffect.EffectType.GRANT_ITEM:
			if not registry.get_definition(effect.content_id, false) is ItemDefinition:
				return _failure("Item reward is missing.")
			run_state.inventory.create_item(effect.content_id)
		RunEventEffect.EffectType.GRANT_HERO_ABILITY:
			var hero := _find_hero_by_definition(run_state, effect.hero_definition_id)
			var ability := registry.get_definition(effect.content_id, false) as AbilityDefinition
			if hero == null or ability == null or not ability.is_allowed_for_hero(hero.definition_id):
				return _failure("Hero ability reward has no valid recipient.")
			if hero.owned_ability_ids.has(ability.id):
				if not hero.upgrade_ability(ability.id):
					return _failure("The Hero ability is already at maximum level.")
			else:
				if hero.ability_ids.size() >= HeroState.MAX_ABILITY_SLOTS:
					return _failure("The Hero has no free ability slot.")
				hero.unlock_ability(ability.id)
				if not hero.equip_ability(ability.id):
					return _failure("The Hero ability could not be equipped.")
		RunEventEffect.EffectType.GRANT_JOB_ABILITY:
			var job := registry.get_definition(effect.job_id, false) as JobDefinition
			var ability := registry.get_definition(effect.content_id, false) as AbilityDefinition
			if job == null or ability == null or not run_state.unlocked_job_ids.has(job.id) or not job.available_ability_ids.has(ability.id):
				return _failure("Job ability reward has no valid recipient.")
			var build := _find_job_build(run_state, job.id)
			if build == null:
				build = JobBuildState.new()
				build.job_id = job.id
				run_state.job_builds.append(build)
			if build.owned_ability_ids.has(ability.id):
				return _failure("The Job already owns this ability.")
			if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
				if not String(build.active_ability_id).is_empty():
					return _failure("The Job has no free active ability slot.")
				build.set_active_ability(ability.id)
			else:
				if build.passive_ability_ids.size() >= 3 or not build.add_passive_ability(ability.id):
					return _failure("The Job has no free passive ability slot.")
		RunEventEffect.EffectType.STAT_MODIFIER:
			if effect.battles_remaining == 0 or effect.battles_remaining < -1 or effect.stat not in ContentRegistry.MODIFIABLE_STATS:
				return _failure("Stat modifier configuration is invalid.")
			var targets := _modifier_targets(run_state, target_ids, effect)
			if targets.is_empty():
				return _failure("Stat modifier has no valid target.")
			for target in targets:
				var modifier := RuntimeStatModifier.new()
				modifier.instance_id = "event-modifier-%08d" % run_state.next_modifier_serial
				run_state.next_modifier_serial += 1
				modifier.source_id = effect.effect_id
				modifier.stat = effect.stat
				modifier.operation = effect.modifier_operation
				modifier.value = effect.modifier_value
				modifier.battles_remaining = effect.battles_remaining
				target.stat_modifiers.append(modifier)
		RunEventEffect.EffectType.HERO_LEVEL_DELTA:
			var hero := _find_hero_by_definition(run_state, effect.hero_definition_id)
			var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
			if hero == null or progression == null or effect.amount == 0:
				return _failure("Hero level change has no valid recipient.")
			var old_level := hero.level
			var target_level := clampi(hero.level + effect.amount, 1, progression.hero_level_xp_thresholds.size())
			if target_level == hero.level:
				return _failure("Hero level cannot change further.")
			hero.xp = progression.hero_level_xp_thresholds[target_level - 1]
			hero.level = progression.hero_level_for_xp(hero.xp)
			if hero.level > old_level:
				run_state.pending_hero_ability_reward.queue_level_ups(hero.unique_id, hero.level - old_level)
		RunEventEffect.EffectType.SOLDIER_VETERANCY_DELTA:
			var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
			var soldiers := _target_soldiers(run_state, target_ids, effect)
			if progression == null or soldiers.is_empty() or effect.amount == 0:
				return _failure("Veterancy change has no valid recipient.")
			for soldier in soldiers:
				var target_level := clampi(soldier.veterancy_level + effect.amount, 0, progression.veterancy_xp_thresholds.size() - 1)
				if target_level == soldier.veterancy_level:
					return _failure("Soldier Veterancy cannot change further.")
				soldier.veterancy_xp = progression.veterancy_xp_thresholds[target_level]
				soldier.veterancy_level = progression.veterancy_level_for_xp(soldier.veterancy_xp)
		RunEventEffect.EffectType.JOB_CAPACITY_DELTA:
			var job := registry.get_definition(effect.job_id, false) as JobDefinition
			if effect.job_id == &"job.militia" or job == null:
				return _failure("Job capacity reward has no valid Job.")
			var is_unlocked := run_state.unlocked_job_ids.has(effect.job_id)
			if not is_unlocked and effect.amount < 0:
				return _failure("Job capacity reward cannot reduce a locked Job.")
			var old_capacity := int(run_state.job_capacities.get(String(effect.job_id), 0))
			var new_capacity := old_capacity + effect.amount
			var assigned := 0
			for soldier in run_state.soldiers:
				if soldier.current_job_id == effect.job_id:
					assigned += 1
			if new_capacity < assigned or new_capacity < 0 or new_capacity > run_state.soldiers.size():
				return _failure("Job capacity cannot be changed by that amount.")
			if not is_unlocked:
				run_state.unlocked_job_ids.append(effect.job_id)
				var build := JobBuildState.new()
				build.job_id = effect.job_id
				run_state.job_builds.append(build)
				_convert_market_unlock_to_capacity(run_state, job)
			run_state.job_capacities[String(effect.job_id)] = new_capacity
		RunEventEffect.EffectType.GOLD_DELTA:
			if effect.amount == 0 or run_state.gold + effect.amount < 0:
				return _failure("Gold reward cannot be applied.")
			run_state.gold += effect.amount
		RunEventEffect.EffectType.HERO_XP_DELTA:
			var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
			var heroes := _available_heroes(run_state)
			if progression == null or heroes.is_empty() or effect.amount == 0:
				return _failure("Hero XP reward has no valid recipient.")
			for hero in heroes:
				var old_level := hero.level
				hero.xp = maxi(0, hero.xp + effect.amount)
				hero.level = progression.hero_level_for_xp(hero.xp)
				if hero.level > old_level:
					run_state.pending_hero_ability_reward.queue_level_ups(hero.unique_id, hero.level - old_level)
		RunEventEffect.EffectType.GRANT_RANDOM_HERO_ITEM:
			var heroes := _available_heroes(run_state)
			var items: Array[ItemDefinition] = []
			for definition in registry.definitions.values():
				if not definition is ItemDefinition:
					continue
				for hero in heroes:
					var hero_definition := registry.get_definition(hero.definition_id, false) as HeroDefinition
					if definition.is_compatible_with_hero(hero_definition):
						items.append(definition)
						break
			items.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.id < b.id)
			if heroes.is_empty() or items.is_empty():
				return _failure("Random Hero item reward has no valid recipient or item.")
			var item := items[int(run_state.event_rng.next_u32() % items.size())]
			run_state.inventory.create_item(item.id)
	return {"ok": true, "error": ""}


static func _convert_market_unlock_to_capacity(run_state: RunState, job: JobDefinition) -> void:
	for offer in run_state.market.offers:
		if offer.offer_type == &"job_unlock" and offer.content_id == job.id:
			offer.offer_type = &"job_capacity"
			offer.price = job.capacity_price


static func _conditions_met(conditions: Array[RunEventCondition], run_state: RunState, target_ids: Array[String], registry: Node) -> bool:
	for condition in conditions:
		if condition == null or not condition.is_met(run_state, target_ids, registry):
			return false
	return true


static func _eligible_soldiers(run_state: RunState, event: RunEventDefinition) -> Array[SoldierState]:
	var result: Array[SoldierState] = []
	for soldier in run_state.soldiers:
		if soldier.veterancy_level < event.target_min_veterancy_level:
			continue
		if not event.target_allowed_job_ids.is_empty() and not event.target_allowed_job_ids.has(soldier.current_job_id):
			continue
		result.append(soldier)
	result.sort_custom(func(a: SoldierState, b: SoldierState) -> bool: return a.unique_id < b.unique_id)
	return result


static func _modifier_targets(run_state: RunState, target_ids: Array[String], effect: RunEventEffect) -> Array:
	match effect.target_scope:
		RunEventEffect.TargetScope.HERO:
			var hero := _find_hero_by_definition(run_state, effect.hero_definition_id)
			return [hero] if hero != null else []
		RunEventEffect.TargetScope.JOB:
			var build := _find_job_build(run_state, effect.job_id)
			return [build] if build != null else []
		_:
			return _target_soldiers(run_state, target_ids, effect)


static func _target_soldiers(run_state: RunState, target_ids: Array[String], effect: RunEventEffect) -> Array[SoldierState]:
	var result: Array[SoldierState] = []
	var ids: Array[String] = []
	if effect.all_soldier_targets:
		ids = target_ids.duplicate()
	elif effect.target_index >= 0 and effect.target_index < target_ids.size():
		ids.append(target_ids[effect.target_index])
	for target_id in ids:
		for soldier in run_state.soldiers:
			if soldier.unique_id == target_id:
				result.append(soldier)
				break
	return result


static func _find_hero_by_definition(run_state: RunState, definition_id: StringName) -> HeroState:
	for hero in run_state.heroes:
		if hero.definition_id == definition_id and hero.life_state != HeroState.EXECUTED:
			return hero
	return null


static func _available_heroes(run_state: RunState) -> Array[HeroState]:
	var result: Array[HeroState] = []
	for hero in run_state.heroes:
		if hero.life_state != HeroState.EXECUTED:
			result.append(hero)
	result.sort_custom(func(a: HeroState, b: HeroState) -> bool: return a.unique_id < b.unique_id)
	return result


static func _find_job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	return null


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
