class_name CombatStatistics
extends RefCounted


var unit_stats: Dictionary = {}
var hero_stats: Dictionary = {}
var job_stats: Dictionary = {}
var ability_stats: Dictionary = {}
var event_counts: Dictionary = {}
var permanent_stat_gains: Array[Dictionary] = []
var bonus_gold := 0
var winner: StringName
var duration := 0.0


func reset() -> void:
	unit_stats.clear()
	hero_stats.clear()
	job_stats.clear()
	ability_stats.clear()
	event_counts.clear()
	permanent_stat_gains.clear()
	bonus_gold = 0
	winner = &""
	duration = 0.0


func register_unit(snapshot: CombatUnitSnapshot) -> void:
	unit_stats[snapshot.runtime_id] = {
		"runtime_id": snapshot.runtime_id,
		"display_name": snapshot.display_name,
		"definition_id": String(snapshot.definition_id),
		"team": snapshot.team,
		"unit_kind": snapshot.unit_kind,
		"job_id": String(snapshot.job_id),
		"veterancy_level": snapshot.veterancy_level,
		"summoner_runtime_id": snapshot.summoner_runtime_id,
		"summoner_contribution_percent": snapshot.summoner_contribution_percent,
		"post_combat_xp_bonus_percent": snapshot.post_combat_xp_bonus_percent,
		"damage_dealt": 0.0,
		"damage_taken": 0.0,
		"damage_tanked": 0.0,
		"healing": 0.0,
		"effective_healing": 0.0,
		"kills": 0,
		"deaths": 0,
		"ability_uses": 0,
		"battles_survived": 0,
		"alive": true,
		"killer_id": "",
		"last_effect_id": "",
	}

	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
		_ensure_group(hero_stats, String(snapshot.definition_id), snapshot.display_name, snapshot.team)
	elif snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SOLDIER and not String(snapshot.job_id).is_empty():
		_ensure_group(job_stats, String(snapshot.job_id), String(snapshot.job_id), snapshot.team)


func consume(event: CombatEvent) -> void:
	event_counts[event.event_type] = int(event_counts.get(event.event_type, 0)) + 1

	match event.event_type:
		CombatEvent.DAMAGE_APPLIED:
			_record_damage(event)
		CombatEvent.HEALING_APPLIED:
			_record_healing(event)
		CombatEvent.ABILITY_USED:
			_add_unit_metric(event.source_id, "ability_uses", 1)
			_add_group_metric(event.source_id, "ability_uses", 1)
			_add_ability_metric(event.ability_id, "uses", 1)
		CombatEvent.STATUS_APPLIED:
			_add_ability_metric(event.ability_id, "statuses_applied", 1)
		CombatEvent.UNIT_DIED:
			_record_death(event)
		CombatEvent.BATTLE_FINISHED:
			winner = StringName(event.source_id)
			duration = event.value
			_record_survivors()


func get_top_unit(metric: StringName, team := -1) -> Dictionary:
	var top: Dictionary = {}
	var top_value := -1.0
	for data: Dictionary in unit_stats.values():
		if team >= 0 and int(data.team) != team:
			continue
		var value := float(data.get(metric, 0.0))
		if value > top_value:
			top = data
			top_value = value
	return top.duplicate(true)


func get_deaths(team := -1) -> Array[Dictionary]:
	var deaths: Array[Dictionary] = []
	for data: Dictionary in unit_stats.values():
		if int(data.deaths) <= 0:
			continue
		if team >= 0 and int(data.team) != team:
			continue
		deaths.append(data.duplicate(true))
	deaths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.runtime_id < b.runtime_id)
	return deaths


func get_event_count(event_type: StringName) -> int:
	return int(event_counts.get(event_type, 0))


func record_permanent_stat_gain(
	target_runtime_id: String,
	source_runtime_id: String,
	ability_id: StringName,
	stats: Dictionary
) -> void:
	permanent_stat_gains.append({
		"target_runtime_id": target_runtime_id,
		"source_runtime_id": source_runtime_id,
		"ability_id": String(ability_id),
		"stats": stats.duplicate(true),
	})


func _record_damage(event: CombatEvent) -> void:
	var value := maxf(0.0, event.value)
	if value <= 0.0 or not unit_stats.has(event.target_id):
		return
	_add_unit_metric(event.target_id, "damage_taken", value)
	_add_group_metric(event.target_id, "damage_taken", value)
	_add_ability_metric(event.ability_id, "damage", value)
	if not _is_hostile_event(event):
		return
	var target: Dictionary = unit_stats[event.target_id]
	if not bool(target.alive):
		return
	var tanking_attribution := _contribution_attribution(event.target_id)
	var attributed_tanking := value * float(tanking_attribution.multiplier)
	_add_unit_metric(tanking_attribution.runtime_id, "damage_tanked", attributed_tanking)
	_add_group_metric(tanking_attribution.runtime_id, "damage_tanked", attributed_tanking)
	var source: Dictionary = unit_stats[event.source_id]
	if not bool(source.alive):
		return
	var damage_attribution := _contribution_attribution(event.source_id)
	var attributed_damage := value * float(damage_attribution.multiplier)
	_add_unit_metric(damage_attribution.runtime_id, "damage_dealt", attributed_damage)
	_add_group_metric(damage_attribution.runtime_id, "damage_dealt", attributed_damage)


func _record_healing(event: CombatEvent) -> void:
	var value := maxf(0.0, event.value)
	if value <= 0.0 or not unit_stats.has(event.source_id) or not unit_stats.has(event.target_id):
		return
	var source: Dictionary = unit_stats[event.source_id]
	var target: Dictionary = unit_stats[event.target_id]
	if int(source.team) != int(target.team) or not bool(source.alive) or not bool(target.alive):
		return
	var healing_attribution := _contribution_attribution(event.source_id)
	var attributed_healing := value * float(healing_attribution.multiplier)
	_add_unit_metric(healing_attribution.runtime_id, "healing", attributed_healing)
	_add_unit_metric(healing_attribution.runtime_id, "effective_healing", attributed_healing)
	_add_group_metric(healing_attribution.runtime_id, "healing", attributed_healing)
	_add_group_metric(healing_attribution.runtime_id, "effective_healing", attributed_healing)
	_add_ability_metric(event.ability_id, "healing", value)


func _is_hostile_event(event: CombatEvent) -> bool:
	if event.source_id.is_empty() or event.source_id == event.target_id:
		return false
	if not unit_stats.has(event.source_id) or not unit_stats.has(event.target_id):
		return false
	return int(unit_stats[event.source_id].team) != int(unit_stats[event.target_id].team)


func _record_death(event: CombatEvent) -> void:
	if unit_stats.has(event.target_id):
		var victim: Dictionary = unit_stats[event.target_id]
		victim.deaths = int(victim.deaths) + 1
		victim.alive = false
		victim.killer_id = event.source_id
		victim.last_effect_id = String(event.effect_id)
		_add_group_metric(event.target_id, "deaths", 1)

	if _is_hostile_event(event):
		_add_unit_metric(event.source_id, "kills", 1)
		_add_group_metric(event.source_id, "kills", 1)


func _record_survivors() -> void:
	for data: Dictionary in unit_stats.values():
		if data.alive and int(data.unit_kind) == CombatUnitSnapshot.UnitKind.SOLDIER:
			data.battles_survived = int(data.battles_survived) + 1


func _contribution_attribution(runtime_id: String) -> Dictionary:
	if runtime_id.is_empty() or not unit_stats.has(runtime_id):
		return {"runtime_id": runtime_id, "multiplier": 1.0}
	var data: Dictionary = unit_stats[runtime_id]
	var owner_id := String(data.get("summoner_runtime_id", ""))
	if not unit_stats.has(owner_id):
		return {"runtime_id": runtime_id, "multiplier": 1.0}
	var percent := clampf(float(data.get("summoner_contribution_percent", 100.0)), 0.0, 100.0)
	return {"runtime_id": owner_id, "multiplier": percent / 100.0}


func _add_unit_metric(runtime_id: String, metric: StringName, value: Variant) -> void:
	if runtime_id.is_empty() or not unit_stats.has(runtime_id):
		return
	var data: Dictionary = unit_stats[runtime_id]
	data[metric] = data.get(metric, 0) + value


func _add_group_metric(runtime_id: String, metric: StringName, value: Variant) -> void:
	if runtime_id.is_empty() or not unit_stats.has(runtime_id):
		return
	var unit: Dictionary = unit_stats[runtime_id]
	if int(unit.unit_kind) == CombatUnitSnapshot.UnitKind.HERO:
		_add_metric(hero_stats, String(unit.definition_id), metric, value)
	elif int(unit.unit_kind) == CombatUnitSnapshot.UnitKind.SOLDIER and not String(unit.job_id).is_empty():
		_add_metric(job_stats, String(unit.job_id), metric, value)


func _add_ability_metric(ability_id: StringName, metric: StringName, value: Variant) -> void:
	if String(ability_id).is_empty():
		return
	var key := String(ability_id)
	if not ability_stats.has(key):
		ability_stats[key] = {
			"ability_id": key,
			"damage": 0.0,
			"healing": 0.0,
			"uses": 0,
			"statuses_applied": 0,
		}
	var data: Dictionary = ability_stats[key]
	data[metric] = data.get(metric, 0) + value


func _ensure_group(target: Dictionary, key: String, display_name: String, team: int) -> void:
	if key.is_empty() or target.has(key):
		return
	target[key] = {
		"id": key,
		"display_name": display_name,
		"team": team,
		"damage_dealt": 0.0,
		"damage_taken": 0.0,
		"damage_tanked": 0.0,
		"healing": 0.0,
		"effective_healing": 0.0,
		"kills": 0,
		"deaths": 0,
		"ability_uses": 0,
	}


func _add_metric(target: Dictionary, key: String, metric: StringName, value: Variant) -> void:
	if key.is_empty() or not target.has(key):
		return
	var data: Dictionary = target[key]
	data[metric] = data.get(metric, 0) + value
