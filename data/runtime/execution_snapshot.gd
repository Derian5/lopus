class_name ExecutionSnapshot
extends RefCounted


var hero_definition_id: StringName
var level := 1
var xp := 0
var ability_ids: Array[StringName] = []
var item_ids: Array[StringName] = []


func to_dictionary() -> Dictionary:
	return {
		"hero_definition_id": String(hero_definition_id),
		"level": level,
		"xp": xp,
		"ability_ids": StateSerialization.names_to_strings(ability_ids),
		"item_ids": StateSerialization.names_to_strings(item_ids),
	}


static func from_dictionary(data: Dictionary) -> ExecutionSnapshot:
	var state := ExecutionSnapshot.new()
	state.hero_definition_id = StringName(data.get("hero_definition_id", ""))
	state.level = int(data.get("level", 1))
	state.xp = int(data.get("xp", 0))
	state.ability_ids = StateSerialization.strings_to_names(data.get("ability_ids", []))
	state.item_ids = StateSerialization.strings_to_names(data.get("item_ids", []))
	return state
