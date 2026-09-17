class_name CombatUnitSnapshot
extends RefCounted


enum Team {
	PLAYER,
	ENEMY,
}

enum UnitKind {
	HERO,
	SOLDIER,
	ENEMY,
}

var runtime_id := ""
var definition_id: StringName
var display_name := ""
var team := Team.PLAYER
var unit_kind := UnitKind.SOLDIER
var job_id: StringName
var attack_type: StringName = &"melee"
var stats := CombatStats.new()
var placeholder_color := Color.WHITE
var abilities: Array[AbilityDefinition] = []


func duplicate_snapshot() -> CombatUnitSnapshot:
	var copy := CombatUnitSnapshot.new()
	copy.runtime_id = runtime_id
	copy.definition_id = definition_id
	copy.display_name = display_name
	copy.team = team
	copy.unit_kind = unit_kind
	copy.job_id = job_id
	copy.attack_type = attack_type
	copy.stats = stats.duplicate_stats()
	copy.placeholder_color = placeholder_color
	copy.abilities = abilities.duplicate()
	return copy
