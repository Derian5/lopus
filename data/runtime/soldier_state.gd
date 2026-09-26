class_name SoldierState
extends RefCounted


const MAX_ITEM_SLOTS := 2

var unique_id := ""
var definition_id: StringName = &"job.militia"
var generated_name := ""
var current_job_id: StringName = &"job.militia"
var veterancy_xp := 0
var veterancy_level := 0
var item_ids: Array[StringName] = []
var lifetime_statistics: Dictionary = {}
var current_hp := 0.0
var cooldowns: Dictionary = {}
var statuses: Array[Dictionary] = []
var stat_modifiers: Array[RuntimeStatModifier] = []


func to_dictionary() -> Dictionary:
	var modifier_data: Array = []
	for modifier in stat_modifiers:
		modifier_data.append(modifier.to_dictionary())
	return {
		"unique_id": unique_id,
		"definition_id": String(definition_id),
		"generated_name": generated_name,
		"current_job_id": String(current_job_id),
		"veterancy_xp": veterancy_xp,
		"veterancy_level": veterancy_level,
		"item_ids": StateSerialization.names_to_strings(item_ids),
		"lifetime_statistics": lifetime_statistics.duplicate(true),
		"current_hp": current_hp,
		"cooldowns": cooldowns.duplicate(true),
		"statuses": StateSerialization.dictionaries_to_data(statuses),
		"stat_modifiers": modifier_data,
	}


static func from_dictionary(data: Dictionary) -> SoldierState:
	var state := SoldierState.new()
	state.unique_id = String(data.get("unique_id", ""))
	state.definition_id = StringName(data.get("definition_id", "job.militia"))
	state.generated_name = String(data.get("generated_name", ""))
	state.current_job_id = StringName(data.get("current_job_id", "job.militia"))
	state.veterancy_xp = int(data.get("veterancy_xp", 0))
	state.veterancy_level = int(data.get("veterancy_level", 0))
	state.item_ids = StateSerialization.strings_to_names(data.get("item_ids", []))
	state.item_ids.resize(mini(state.item_ids.size(), MAX_ITEM_SLOTS))
	state.lifetime_statistics = Dictionary(data.get("lifetime_statistics", {})).duplicate(true)
	state.current_hp = float(data.get("current_hp", 0.0))
	state.cooldowns = Dictionary(data.get("cooldowns", {})).duplicate(true)
	state.statuses = StateSerialization.data_to_dictionaries(data.get("statuses", []))
	for modifier_data in data.get("stat_modifiers", []):
		if modifier_data is Dictionary:
			state.stat_modifiers.append(RuntimeStatModifier.from_dictionary(modifier_data))
	return state
