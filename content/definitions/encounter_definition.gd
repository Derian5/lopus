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
## Relative strength of every enemy in this encounter (initial wave and reinforcements),
## combined with the route's power curve. Power p gives p^0.85 Max HP and p^1.15 Damage.
@export_range(0.1, 10.0, 0.05, "or_greater") var enemy_power := 1.0
@export var arena_id: StringName = &"arena.default"
@export_range(1, 2, 1) var act := 1
@export_range(0, 100, 1, "or_greater") var min_encounter_index := 0
@export_range(0, 100, 1, "or_greater") var max_encounter_index := 100
@export_enum("Low", "Moderate", "High", "Elite", "Boss") var difficulty_hint := "Moderate"
@export var key_properties: Array[String] = []
@export var is_unknown := false
@export var is_boss := false


## Relative chance of this encounter appearing as a card at the given battle index.
## Easier fights dominate the opening battles and harder ones the end of the act.
func selection_weight(encounter_index: int, final_index: int) -> float:
	var progress := clampf(float(encounter_index) / float(maxi(final_index, 1)), 0.0, 1.0)
	match difficulty_hint:
		"Low":
			return lerpf(3.0, 0.15, progress)
		"Moderate":
			return 0.6 + 2.2 * (1.0 - absf(progress - 0.45) * 2.0)
		"High":
			return lerpf(0.25, 3.0, progress)
		"Elite":
			return lerpf(0.0, 3.4, progress)
	return 1.0


func has_reinforcements() -> bool:
	return not reinforcement_enemy_ids.is_empty()
