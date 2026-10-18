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
	result.bonus_gold_reward = maxi(result.bonus_gold_reward, 0) if result.winner == &"player" else 0
	result.gold_reward = (encounter.gold_reward + result.bonus_gold_reward) if result.winner == &"player" else 0
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
		"permanent_stat_gains": [],
		"xp_bonus_percent": _envy_xp_bonus_percent(result),
	}
	var xp_bonus_percent := float(summary.xp_bonus_percent)
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
		var base_xp := int(contribution.total_xp)
		var bonus_xp := _rounded_xp_bonus(base_xp, xp_bonus_percent)
		var gained_xp := base_xp + bonus_xp
		hero.xp += gained_xp
		hero.level = progression.hero_level_for_xp(hero.xp)
		if result.winner == &"player" and hero.level > old_level:
			run_state.pending_hero_ability_reward.queue_level_ups(hero.unique_id, hero.level - old_level)
		var died := not bool(data.alive)
		if died and hero.life_state == HeroState.ALIVE:
			hero.life_state = HeroState.DEAD
			hero.current_hp = 0.0
		var change := {
			"runtime_id": hero.unique_id,
			"display_name": data.display_name,
			"xp": gained_xp,
			"base_xp": base_xp,
			"bonus_xp": bonus_xp,
			"xp_bonus_percent": xp_bonus_percent,
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
				"display_name": _soldier_display_name(soldier, registry),
				"job_id": String(soldier.current_job_id),
				"xp": 0,
				"potential_xp": int(contribution.total_xp),
				"unit_kind": CombatUnitSnapshot.UnitKind.SOLDIER,
				"lost": true,
				"contribution": contribution,
			}
			summary.deaths.append(death_change)
			summary.contribution_changes.append(death_change)
			continue
		var old_level := soldier.veterancy_level
		var base_xp := int(contribution.total_xp)
		var bonus_xp := _rounded_xp_bonus(base_xp, xp_bonus_percent)
		var gained_xp := base_xp + bonus_xp
		soldier.veterancy_xp += gained_xp
		soldier.veterancy_level = progression.veterancy_level_for_xp(soldier.veterancy_xp)
		var change := {
			"runtime_id": soldier.unique_id,
			"display_name": _soldier_display_name(soldier, registry),
			"xp": gained_xp,
			"base_xp": base_xp,
			"bonus_xp": bonus_xp,
			"xp_bonus_percent": xp_bonus_percent,
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
			var replacement := _create_replacement(result.result_id, replacement_index, run_state, registry)
			run_state.soldiers.append(replacement)
			summary.replacements.append({
				"runtime_id": replacement.unique_id,
				"display_name": _soldier_display_name(replacement, registry),
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


static func _envy_xp_bonus_percent(result: CombatResult) -> float:
	var bonus := 0.0
	for data in result.unit_statistics:
		if (
			int(data.get("team", -1)) == CombatUnitSnapshot.Team.PLAYER
			and int(data.get("unit_kind", -1)) == CombatUnitSnapshot.UnitKind.HERO
			and StringName(data.get("definition_id", "")) == &"hero.army_support"
		):
			bonus = maxf(bonus, float(data.get("post_combat_xp_bonus_percent", 0.0)))
	return bonus


static func _rounded_xp_bonus(base_xp: int, bonus_percent: float) -> int:
	return int(floor(float(maxi(base_xp, 0)) * maxf(bonus_percent, 0.0) / 100.0 + 0.5))


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
			modifier.instance_id = "%s-permanent-gain-%d-%s" % [result.result_id, gain_index, stat]
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


static func _create_replacement(result_id: String, index: int, run_state: RunState, registry: Node) -> SoldierState:
	var replacement := SoldierState.new()
	var serial := run_state.soldiers.size() + index + 1
	replacement.unique_id = "%s-militia-%02d" % [result_id, serial]
	replacement.definition_id = &"job.militia"
	replacement.current_job_id = &"job.militia"
	var militia := registry.get_definition(&"job.militia") as JobDefinition
	SoldierNameGenerator.assign_name(replacement, militia.display_name, run_state.run_seed, run_state.soldiers)
	return replacement


static func _soldier_display_name(soldier: SoldierState, registry: Node) -> String:
	var job := registry.get_definition(soldier.current_job_id, false) as JobDefinition
	return soldier.display_name(job.display_name) if job != null else soldier.generated_name
