class_name ExecutionSnapshot
extends RefCounted


var hero_definition_id: StringName
var hero_unique_id := ""
var life_state_at_execution: StringName
var level := 1
var xp := 0
var ability_ids: Array[StringName] = []
var owned_ability_ids: Array[StringName] = []
var ability_levels: Dictionary = {}
var item_ids: Array[StringName] = []
var item_definition_ids: Array[StringName] = []
var main_score := 0.0
var battle_contribution: Dictionary = {}
var act := 1
var encounter_index := 0


func to_dictionary() -> Dictionary:
	return {
		"hero_definition_id": String(hero_definition_id),
		"hero_unique_id": hero_unique_id,
		"life_state_at_execution": String(life_state_at_execution),
		"level": level,
		"xp": xp,
		"ability_ids": StateSerialization.names_to_strings(ability_ids),
		"owned_ability_ids": StateSerialization.names_to_strings(owned_ability_ids),
		"ability_levels": ability_levels.duplicate(true),
		"item_ids": StateSerialization.names_to_strings(item_ids),
		"item_definition_ids": StateSerialization.names_to_strings(item_definition_ids),
		"main_score": main_score,
		"battle_contribution": battle_contribution.duplicate(true),
		"act": act,
		"encounter_index": encounter_index,
	}


static func from_dictionary(data: Dictionary) -> ExecutionSnapshot:
	var state := ExecutionSnapshot.new()
	state.hero_definition_id = StringName(data.get("hero_definition_id", ""))
	state.hero_unique_id = String(data.get("hero_unique_id", ""))
	state.life_state_at_execution = StringName(data.get("life_state_at_execution", ""))
	state.level = int(data.get("level", 1))
	state.xp = int(data.get("xp", 0))
	state.ability_ids = StateSerialization.strings_to_names(data.get("ability_ids", []))
	state.owned_ability_ids = StateSerialization.strings_to_names(data.get("owned_ability_ids", []))
	for ability_id in Dictionary(data.get("ability_levels", {})):
		state.ability_levels[String(ability_id)] = int(data.ability_levels[ability_id])
	state.item_ids = StateSerialization.strings_to_names(data.get("item_ids", []))
	state.item_definition_ids = StateSerialization.strings_to_names(data.get("item_definition_ids", []))
	state.main_score = float(data.get("main_score", 0.0))
	state.battle_contribution = Dictionary(data.get("battle_contribution", {})).duplicate(true)
	state.act = int(data.get("act", 1))
	state.encounter_index = int(data.get("encounter_index", 0))
	return state
