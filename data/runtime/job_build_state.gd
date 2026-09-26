class_name JobBuildState
extends RefCounted


var job_id: StringName
var active_ability_id: StringName
var passive_ability_ids: Array[StringName] = []
var owned_ability_ids: Array[StringName] = []
var stat_modifiers: Array[RuntimeStatModifier] = []


func set_active_ability(ability_id: StringName) -> void:
	active_ability_id = ability_id
	unlock_ability(ability_id)


func add_passive_ability(ability_id: StringName) -> bool:
	if String(ability_id).is_empty() or passive_ability_ids.has(ability_id) or passive_ability_ids.size() >= 3:
		return false
	passive_ability_ids.append(ability_id)
	unlock_ability(ability_id)
	return true


func unlock_ability(ability_id: StringName) -> bool:
	if String(ability_id).is_empty() or owned_ability_ids.has(ability_id):
		return false
	owned_ability_ids.append(ability_id)
	return true


func is_valid() -> bool:
	return passive_ability_ids.size() <= 3 and not passive_ability_ids.has(active_ability_id)


func to_dictionary() -> Dictionary:
	var modifier_data: Array = []
	for modifier in stat_modifiers:
		modifier_data.append(modifier.to_dictionary())
	return {
		"job_id": String(job_id),
		"active_ability_id": String(active_ability_id),
		"passive_ability_ids": StateSerialization.names_to_strings(passive_ability_ids),
		"owned_ability_ids": StateSerialization.names_to_strings(owned_ability_ids),
		"stat_modifiers": modifier_data,
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
	state.owned_ability_ids = StateSerialization.strings_to_names(data.get("owned_ability_ids", []))
	if not String(state.active_ability_id).is_empty() and not state.owned_ability_ids.has(state.active_ability_id):
		state.owned_ability_ids.append(state.active_ability_id)
	for ability_id in state.passive_ability_ids:
		if not state.owned_ability_ids.has(ability_id):
			state.owned_ability_ids.append(ability_id)
	if state.passive_ability_ids.size() > 3:
		state.passive_ability_ids.resize(3)
	for modifier_data in data.get("stat_modifiers", []):
		if modifier_data is Dictionary:
			state.stat_modifiers.append(RuntimeStatModifier.from_dictionary(modifier_data))
	return state
