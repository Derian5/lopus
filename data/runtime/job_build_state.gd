class_name JobBuildState
extends RefCounted


var job_id: StringName
var active_ability_id: StringName
var passive_ability_ids: Array[StringName] = []


func set_active_ability(ability_id: StringName) -> void:
	active_ability_id = ability_id


func add_passive_ability(ability_id: StringName) -> bool:
	if String(ability_id).is_empty() or passive_ability_ids.has(ability_id) or passive_ability_ids.size() >= 3:
		return false
	passive_ability_ids.append(ability_id)
	return true


func is_valid() -> bool:
	return passive_ability_ids.size() <= 3 and not passive_ability_ids.has(active_ability_id)


func to_dictionary() -> Dictionary:
	return {
		"job_id": String(job_id),
		"active_ability_id": String(active_ability_id),
		"passive_ability_ids": StateSerialization.names_to_strings(passive_ability_ids),
	}


func set_passives(ability_ids: Array[StringName]) -> void:
	passive_ability_ids.clear()
	for ability_id in ability_ids:
		add_passive_ability(ability_id)


static func from_dictionary(data: Dictionary) -> JobBuildState:
	var state := JobBuildState.new()
	state.job_id = StringName(data.get("job_id", ""))
	state.active_ability_id = StringName(data.get("active_ability_id", ""))
	state.passive_ability_ids = StateSerialization.strings_to_names(data.get("passive_ability_ids", []))
	if state.passive_ability_ids.size() > 3:
		state.passive_ability_ids.resize(3)
	return state
