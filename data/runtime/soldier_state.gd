class_name SoldierState
extends RefCounted


const TARGET_CLOSEST := &"closest"
const TARGET_FARTHEST := &"farthest"

var unique_id := ""
var definition_id: StringName = &"job.militia"
var generated_name := ""
var personal_name := ""
var current_job_id: StringName = &"job.militia"
var veterancy_xp := 0
var veterancy_level := 0
var lifetime_statistics: Dictionary = {}
var current_hp := 0.0
var cooldowns: Dictionary = {}
var statuses: Array[Dictionary] = []
var stat_modifiers: Array[RuntimeStatModifier] = []
var targeting_mode: StringName = TARGET_CLOSEST
var damage_avoidance_override := -1


func display_name(job_display_name: String) -> String:
	if personal_name.is_empty():
		return generated_name
	return "%s %s" % [job_display_name, personal_name]


func to_dictionary() -> Dictionary:
	var modifier_data: Array = []
	for modifier in stat_modifiers:
		modifier_data.append(modifier.to_dictionary())
	return {
		"unique_id": unique_id,
		"definition_id": String(definition_id),
		"generated_name": generated_name,
		"personal_name": personal_name,
		"current_job_id": String(current_job_id),
		"veterancy_xp": veterancy_xp,
		"veterancy_level": veterancy_level,
		"lifetime_statistics": lifetime_statistics.duplicate(true),
		"current_hp": current_hp,
		"cooldowns": cooldowns.duplicate(true),
		"statuses": StateSerialization.dictionaries_to_data(statuses),
		"stat_modifiers": modifier_data,
		"targeting_mode": String(targeting_mode),
		"damage_avoidance_override": damage_avoidance_override,
	}


static func from_dictionary(data: Dictionary) -> SoldierState:
	var state := SoldierState.new()
	state.unique_id = String(data.get("unique_id", ""))
	state.definition_id = StringName(data.get("definition_id", "job.militia"))
	state.generated_name = String(data.get("generated_name", ""))
	state.personal_name = String(data.get("personal_name", ""))
	state.current_job_id = StringName(data.get("current_job_id", "job.militia"))
	state.veterancy_xp = int(data.get("veterancy_xp", 0))
	state.veterancy_level = int(data.get("veterancy_level", 0))
	state.lifetime_statistics = Dictionary(data.get("lifetime_statistics", {})).duplicate(true)
	state.current_hp = float(data.get("current_hp", 0.0))
	state.cooldowns = Dictionary(data.get("cooldowns", {})).duplicate(true)
	state.statuses = StateSerialization.data_to_dictionaries(data.get("statuses", []))
	state.targeting_mode = StringName(data.get("targeting_mode", TARGET_CLOSEST))
	if state.targeting_mode not in [TARGET_CLOSEST, TARGET_FARTHEST]:
		state.targeting_mode = TARGET_CLOSEST
	state.damage_avoidance_override = clampi(int(data.get("damage_avoidance_override", -1)), -1, 1)
	for modifier_data in data.get("stat_modifiers", []):
		if modifier_data is Dictionary:
			state.stat_modifiers.append(RuntimeStatModifier.from_dictionary(modifier_data))
	return state
