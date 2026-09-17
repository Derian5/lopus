class_name HeroState
extends RefCounted


const ALIVE := &"alive"
const DEAD := &"dead"
const EXECUTED := &"executed"
const MAX_ABILITY_SLOTS := 4
const MAX_ITEM_SLOTS := 6

var unique_id := ""
var definition_id: StringName
var level := 1
var xp := 0
var life_state: StringName = ALIVE
var current_hp := 0.0
var ability_ids: Array[StringName] = []
var item_ids: Array[StringName] = []
var ability_priority: Array[StringName] = []
var cooldowns: Dictionary = {}
var statuses: Array[Dictionary] = []


func equip_ability(ability_id: StringName) -> bool:
	if String(ability_id).is_empty() or ability_ids.has(ability_id) or ability_ids.size() >= MAX_ABILITY_SLOTS:
		return false
	ability_ids.append(ability_id)
	ability_priority.append(ability_id)
	return true


func equip_item(item_id: StringName) -> bool:
	if String(item_id).is_empty() or item_ids.size() >= MAX_ITEM_SLOTS:
		return false
	item_ids.append(item_id)
	return true


func set_ability_priority(priority: Array[StringName]) -> void:
	ability_priority.clear()
	for ability_id in priority:
		if ability_ids.has(ability_id) and not ability_priority.has(ability_id):
			ability_priority.append(ability_id)
	for ability_id in ability_ids:
		if not ability_priority.has(ability_id):
			ability_priority.append(ability_id)


func to_dictionary() -> Dictionary:
	return {
		"unique_id": unique_id,
		"definition_id": String(definition_id),
		"level": level,
		"xp": xp,
		"life_state": String(life_state),
		"current_hp": current_hp,
		"ability_ids": StateSerialization.names_to_strings(ability_ids),
		"item_ids": StateSerialization.names_to_strings(item_ids),
		"ability_priority": StateSerialization.names_to_strings(ability_priority),
		"cooldowns": cooldowns.duplicate(true),
		"statuses": StateSerialization.dictionaries_to_data(statuses),
	}


static func from_dictionary(data: Dictionary) -> HeroState:
	var state := HeroState.new()
	state.unique_id = String(data.get("unique_id", ""))
	state.definition_id = StringName(data.get("definition_id", ""))
	state.level = int(data.get("level", 1))
	state.xp = int(data.get("xp", 0))
	state.life_state = StringName(data.get("life_state", ALIVE))
	state.current_hp = float(data.get("current_hp", 0.0))
	state.ability_ids = StateSerialization.strings_to_names(data.get("ability_ids", []))
	state.item_ids = StateSerialization.strings_to_names(data.get("item_ids", []))
	state.ability_priority = StateSerialization.strings_to_names(data.get("ability_priority", []))
	state.ability_ids.resize(mini(state.ability_ids.size(), MAX_ABILITY_SLOTS))
	state.item_ids.resize(mini(state.item_ids.size(), MAX_ITEM_SLOTS))
	state.set_ability_priority(state.ability_priority.duplicate())
	state.cooldowns = Dictionary(data.get("cooldowns", {})).duplicate(true)
	state.statuses = StateSerialization.data_to_dictionaries(data.get("statuses", []))
	return state
