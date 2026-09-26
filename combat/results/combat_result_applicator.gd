class_name CombatResultApplicator
extends RefCounted


const PROGRESSION_ID := &"progression.demo"


static func apply(result: CombatResult, run_state: RunState, registry: Node) -> bool:
	if result == null or result.result_id.is_empty() or run_state.applied_combat_result_ids.has(result.result_id):
		return false
	if run_state.run_phase != &"combat" or result.winner not in [&"player", &"enemy"]:
		return false
	if String(run_state.selected_encounter_id).is_empty() or result.encounter_id != run_state.selected_encounter_id:
		return false
	if not run_state.available_encounter_ids.has(result.encounter_id):
		return false
	var encounter := registry.get_definition(result.encounter_id, false) as EncounterDefinition
	if encounter == null:
		return false
	result.gold_reward = encounter.gold_reward if result.winner == &"player" else 0
	var progression := registry.get_definition(PROGRESSION_ID) as ProgressionDefinition
	if progression == null:
		return false
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	if route == null:
		return false
	var is_boss_wave: bool = run_state.current_act == 1 and run_state.encounter_index == route.act_one_boss_index()
	if encounter.is_boss != is_boss_wave:
		return false
	var summary := {
		"gold": result.gold_reward,
		"hero_changes": [],
		"soldier_changes": [],
		"contribution_changes": [],
		"deaths": [],
		"replacements": [],
		"returned_items": [],
		"permanent_stat_gains": [],
	}
	if encounter.is_boss and result.winner == &"player":
		run_state.pending_execution_contributions.clear()
	if result.winner == &"player":
		run_state.gold += result.gold_reward

	for hero in run_state.heroes:
		var data := result.get_unit_statistics(hero.unique_id)
		if data.is_empty():
			if encounter.is_boss and result.winner == &"player" and hero.life_state != HeroState.EXECUTED:
				run_state.pending_execution_contributions[hero.unique_id] = _empty_contribution(hero.unique_id)
			continue
		var old_level := hero.level
		var contribution := _get_contribution(data, progression)
		var gained_xp := int(contribution.total_xp)
		hero.xp += gained_xp
		hero.level = progression.hero_level_for_xp(hero.xp)
		var died := not bool(data.alive)
		if died and hero.life_state == HeroState.ALIVE:
			hero.life_state = HeroState.DEAD
			hero.current_hp = 0.0
		var change := {
			"runtime_id": hero.unique_id,
			"display_name": data.display_name,
			"xp": gained_xp,
			"old_level": old_level,
			"new_level": hero.level,
			"unit_kind": CombatUnitSnapshot.UnitKind.HERO,
			"lost": false,
			"died": died,
			"contribution": contribution,
		}
		summary.hero_changes.append(change)
		summary.contribution_changes.append(change)
		if encounter.is_boss and result.winner == &"player":
			run_state.pending_execution_contributions[hero.unique_id] = {
				"runtime_id": hero.unique_id,
				"display_name": String(data.get("display_name", hero.unique_id)),
				"participated": true,
				"alive": bool(data.alive),
				"contribution": contribution.duplicate(true),
			}

	_apply_permanent_stat_gains(result, run_state, summary.permanent_stat_gains)

	var dead_ids: Array[String] = []
	for soldier in run_state.soldiers:
		var data := result.get_unit_statistics(soldier.unique_id)
		if data.is_empty():
			continue
		_update_lifetime_statistics(soldier, data)
		var contribution := _get_contribution(data, progression)
		if not bool(data.alive):
			dead_ids.append(soldier.unique_id)
			var death_change := {
				"runtime_id": soldier.unique_id,
				"display_name": soldier.generated_name,
				"job_id": String(soldier.current_job_id),
				"xp": 0,
				"potential_xp": int(contribution.total_xp),
				"unit_kind": CombatUnitSnapshot.UnitKind.SOLDIER,
				"lost": true,
				"contribution": contribution,
			}
			summary.deaths.append(death_change)
			summary.contribution_changes.append(death_change)
			_return_equipment(soldier, run_state, summary.returned_items)
			continue
		var old_level := soldier.veterancy_level
		var gained_xp := int(contribution.total_xp)
		soldier.veterancy_xp += gained_xp
		soldier.veterancy_level = progression.veterancy_level_for_xp(soldier.veterancy_xp)
		var change := {
			"runtime_id": soldier.unique_id,
			"display_name": soldier.generated_name,
			"xp": gained_xp,
			"old_level": old_level,
			"new_level": soldier.veterancy_level,
			"unit_kind": CombatUnitSnapshot.UnitKind.SOLDIER,
			"lost": false,
			"contribution": contribution,
		}
		summary.soldier_changes.append(change)
		summary.contribution_changes.append(change)

	for index in range(run_state.soldiers.size() - 1, -1, -1):
		if dead_ids.has(run_state.soldiers[index].unique_id):
			run_state.soldiers.remove_at(index)
	if result.winner == &"player":
		for replacement_index in dead_ids.size():
			var replacement := _create_replacement(result.result_id, replacement_index, run_state)
			run_state.soldiers.append(replacement)
			summary.replacements.append({
				"runtime_id": replacement.unique_id,
				"display_name": replacement.generated_name,
			})

	if result.winner != &"player":
		run_state.run_status = RunState.STATUS_DEFEAT
	else:
		if run_state.current_act == 1 and encounter.is_boss:
			run_state.run_phase = &"execution"
		else:
			run_state.encounter_index += 1
		if run_state.current_act == 2 and run_state.encounter_index >= route.act_two_battle_count:
			run_state.run_status = RunState.STATUS_DEMO_COMPLETE
	_consume_runtime_modifiers(run_state)
	run_state.applied_combat_result_ids.append(result.result_id)
	result.application_summary = summary
	return true


static func _empty_contribution(hero_id: String) -> Dictionary:
	return {
		"runtime_id": hero_id,
		"display_name": hero_id,
		"participated": false,
		"alive": false,
		"contribution": {
			"damage_dealt": 0.0,
			"effective_healing": 0.0,
			"damage_tanked": 0.0,
			"damage_xp": 0,
			"healing_xp": 0,
			"tanking_xp": 0,
			"total_xp": 0,
		},
	}


static func _update_lifetime_statistics(soldier: SoldierState, data: Dictionary) -> void:
	for metric in [&"damage_dealt", &"damage_taken", &"damage_tanked", &"healing", &"effective_healing", &"kills", &"deaths", &"ability_uses", &"battles_survived"]:
		soldier.lifetime_statistics[metric] = soldier.lifetime_statistics.get(metric, 0) + data.get(metric, 0)


static func _get_contribution(data: Dictionary, progression: ProgressionDefinition) -> Dictionary:
	var contribution: Dictionary = data.get("contribution", {})
	if contribution.is_empty():
		contribution = progression.contribution_breakdown(data)
		data["contribution"] = contribution
	return contribution.duplicate(true)


static func _return_equipment(
	soldier: SoldierState,
	run_state: RunState,
	returned_items: Array
) -> void:
	for instance_id in soldier.item_ids:
		var item := run_state.inventory.get_item(instance_id)
		if not item.is_empty():
			returned_items.append(item.duplicate(true))
	soldier.item_ids.clear()


static func _consume_runtime_modifiers(run_state: RunState) -> void:
	for hero in run_state.heroes:
		_consume_modifier_array(hero.stat_modifiers)
	for soldier in run_state.soldiers:
		_consume_modifier_array(soldier.stat_modifiers)
	for build in run_state.job_builds:
		_consume_modifier_array(build.stat_modifiers)


static func _apply_permanent_stat_gains(result: CombatResult, run_state: RunState, summary: Array) -> void:
	for gain_index in result.permanent_stat_gains.size():
		var gain: Dictionary = result.permanent_stat_gains[gain_index]
		var hero := _find_hero(run_state, String(gain.get("target_runtime_id", "")))
		if hero == null:
			continue
		var stats: Dictionary = gain.get("stats", {})
		for stat in [&"max_hp", &"damage", &"armor"]:
			var value := maxf(float(stats.get(String(stat), 0.0)), 0.0)
			if value <= 0.0:
				continue
			var modifier := RuntimeStatModifier.new()
			modifier.instance_id = "%s-pride-gain-%d-%s" % [result.result_id, gain_index, stat]
			modifier.source_id = StringName(gain.get("ability_id", ""))
			modifier.stat = String(stat)
			modifier.operation = StatModifier.Operation.ADD
			modifier.value = value
			modifier.battles_remaining = -1
			hero.stat_modifiers.append(modifier)
		summary.append(gain.duplicate(true))


static func _find_hero(run_state: RunState, runtime_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == runtime_id:
			return hero
	return null


static func _consume_modifier_array(modifiers: Array[RuntimeStatModifier]) -> void:
	for index in range(modifiers.size() - 1, -1, -1):
		if modifiers[index].battles_remaining < 0:
			continue
		modifiers[index].battles_remaining -= 1
		if modifiers[index].battles_remaining <= 0:
			modifiers.remove_at(index)


static func _create_replacement(result_id: String, index: int, run_state: RunState) -> SoldierState:
	var replacement := SoldierState.new()
	var serial := run_state.soldiers.size() + index + 1
	replacement.unique_id = "%s-militia-%02d" % [result_id, serial]
	replacement.generated_name = "Militia Replacement %d" % serial
	replacement.definition_id = &"job.militia"
	replacement.current_job_id = &"job.militia"
	return replacement
