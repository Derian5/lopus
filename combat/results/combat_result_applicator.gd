class_name CombatResultApplicator
extends RefCounted


const PROGRESSION_ID := &"progression.demo"


static func apply(result: CombatResult, run_state: RunState, registry: Node) -> bool:
	if result == null or result.result_id.is_empty() or run_state.applied_combat_result_ids.has(result.result_id):
		return false
	var progression := registry.get_definition(PROGRESSION_ID) as ProgressionDefinition
	if progression == null:
		return false
	var summary := {
		"gold": result.gold_reward,
		"hero_changes": [],
		"soldier_changes": [],
		"contribution_changes": [],
		"deaths": [],
		"replacements": [],
		"returned_items": [],
	}
	if result.winner == &"player":
		run_state.gold += result.gold_reward

	for hero in run_state.heroes:
		var data := result.get_unit_statistics(hero.unique_id)
		if data.is_empty():
			continue
		var old_level := hero.level
		var contribution := _get_contribution(data, progression)
		var gained_xp := int(contribution.total_xp)
		hero.xp += gained_xp
		hero.level = progression.hero_level_for_xp(hero.xp)
		var change := {
			"runtime_id": hero.unique_id,
			"display_name": data.display_name,
			"xp": gained_xp,
			"old_level": old_level,
			"new_level": hero.level,
			"unit_kind": CombatUnitSnapshot.UnitKind.HERO,
			"lost": false,
			"contribution": contribution,
		}
		summary.hero_changes.append(change)
		summary.contribution_changes.append(change)

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
			_return_equipment(soldier, run_state, result.result_id, summary.returned_items)
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

	run_state.encounter_index += 1
	run_state.applied_combat_result_ids.append(result.result_id)
	result.application_summary = summary
	return true


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
	result_id: String,
	returned_items: Array
) -> void:
	for index in soldier.item_ids.size():
		var item_id := soldier.item_ids[index]
		var instance_id := "%s-returned-%s-%02d" % [result_id, soldier.unique_id, index]
		run_state.inventory.items.append({
			"instance_id": instance_id,
			"definition_id": String(item_id),
		})
		returned_items.append({"instance_id": instance_id, "definition_id": String(item_id)})


static func _create_replacement(result_id: String, index: int, run_state: RunState) -> SoldierState:
	var replacement := SoldierState.new()
	var serial := run_state.soldiers.size() + index + 1
	replacement.unique_id = "%s-militia-%02d" % [result_id, serial]
	replacement.generated_name = "Militia Replacement %d" % serial
	replacement.definition_id = &"job.militia"
	replacement.current_job_id = &"job.militia"
	return replacement
