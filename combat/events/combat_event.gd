class_name CombatEvent
extends RefCounted


const ATTACK_STARTED := &"attack_started"
const DAMAGE_APPLIED := &"damage_applied"
const HEALING_APPLIED := &"healing_applied"
const ABILITY_USED := &"ability_used"
const STATUS_APPLIED := &"status_applied"
const UNIT_DIED := &"unit_died"
const BATTLE_FINISHED := &"battle_finished"

var timestamp := 0.0
var event_type: StringName
var source_id := ""
var target_id := ""
var ability_id: StringName
var effect_id: StringName
var value := 0.0


func _init(
	new_timestamp := 0.0,
	new_event_type: StringName = &"",
	new_source_id := "",
	new_target_id := "",
	new_ability_id: StringName = &"",
	new_effect_id: StringName = &"",
	new_value := 0.0
) -> void:
	timestamp = new_timestamp
	event_type = new_event_type
	source_id = new_source_id
	target_id = new_target_id
	ability_id = new_ability_id
	effect_id = new_effect_id
	value = new_value
