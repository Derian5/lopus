class_name EncounterDefinition
extends ContentDefinition


enum ReinforcementEntryDirection {
	ALL_SIDES,
	RIGHT_SIDE,
}


@export var enemy_ids: Array[StringName] = []
@export_group("Reinforcements")
@export var reinforcement_enemy_ids: Array[StringName] = []
@export_range(0, 2, 1) var reinforcement_alive_threshold := 0
@export_enum("All Sides", "Right Side") var reinforcement_entry_direction: int = ReinforcementEntryDirection.ALL_SIDES
@export_group("")
@export_range(0, 1000000, 1, "or_greater") var gold_reward := 0
@export var arena_id: StringName = &"arena.default"
@export_range(1, 2, 1) var act := 1
@export_range(0, 100, 1, "or_greater") var min_encounter_index := 0
@export_range(0, 100, 1, "or_greater") var max_encounter_index := 100
@export_enum("Low", "Moderate", "High", "Boss") var difficulty_hint := "Moderate"
@export var key_properties: Array[String] = []
@export var is_unknown := false
@export var is_boss := false


func has_reinforcements() -> bool:
	return not reinforcement_enemy_ids.is_empty()
