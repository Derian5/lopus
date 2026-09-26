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
var owned_ability_ids: Array[StringName] = []
var ability_levels: Dictionary = {}
var item_ids: Array[StringName] = []
var ability_priority: Array[StringName] = []
var cooldowns: Dictionary = {}
var statuses: Array[Dictionary] = []
var stat_modifiers: Array[RuntimeStatModifier] = []


func equip_ability(ability_id: StringName) -> bool:
	if String(ability_id).is_empty() or not owned_ability_ids.has(ability_id) or ability_ids.has(ability_id) or ability_ids.size() >= MAX_ABILITY_SLOTS:
		return false
	ability_ids.append(ability_id)
	ability_priority.append(ability_id)
	return true


func unlock_ability(ability_id: StringName) -> bool:
	if String(ability_id).is_empty() or owned_ability_ids.has(ability_id):
		return false
	owned_ability_ids.append(ability_id)
	ability_levels[String(ability_id)] = 1
	return true


func ability_level(ability_id: StringName) -> int:
	return int(ability_levels.get(String(ability_id), 0))


func upgrade_ability(ability_id: StringName) -> bool:
	var current_level := ability_level(ability_id)
	if not owned_ability_ids.has(ability_id) or current_level < 1 or current_level >= AbilityDefinition.MAX_HERO_ABILITY_LEVEL:
		return false
	ability_levels[String(ability_id)] = current_level + 1
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
	var modifier_data: Array = []
	for modifier in stat_modifiers:
		modifier_data.append(modifier.to_dictionary())
	return {
		"unique_id": unique_id,
		"definition_id": String(definition_id),
		"level": level,
		"xp": xp,
		"life_state": String(life_state),
		"current_hp": current_hp,
		"ability_ids": StateSerialization.names_to_strings(ability_ids),
		"owned_ability_ids": StateSerialization.names_to_strings(owned_ability_ids),
		"ability_levels": ability_levels.duplicate(true),
		"item_ids": StateSerialization.names_to_strings(item_ids),
		"ability_priority": StateSerialization.names_to_strings(ability_priority),
		"cooldowns": cooldowns.duplicate(true),
		"statuses": StateSerialization.dictionaries_to_data(statuses),
		"stat_modifiers": modifier_data,
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
	state.owned_ability_ids = StateSerialization.strings_to_names(data.get("owned_ability_ids", []))
	for ability_id in Dictionary(data.get("ability_levels", {})):
		state.ability_levels[String(ability_id)] = int(data.ability_levels[ability_id])
	for ability_id in state.ability_ids:
		if not state.owned_ability_ids.has(ability_id):
			state.owned_ability_ids.append(ability_id)
	state.item_ids = StateSerialization.strings_to_names(data.get("item_ids", []))
	state.ability_priority = StateSerialization.strings_to_names(data.get("ability_priority", []))
	state.item_ids.resize(mini(state.item_ids.size(), MAX_ITEM_SLOTS))
	state.cooldowns = Dictionary(data.get("cooldowns", {})).duplicate(true)
	state.statuses = StateSerialization.data_to_dictionaries(data.get("statuses", []))
	for modifier_data in data.get("stat_modifiers", []):
		if modifier_data is Dictionary:
			state.stat_modifiers.append(RuntimeStatModifier.from_dictionary(modifier_data))
	return state
