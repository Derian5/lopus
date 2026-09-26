class_name RouteDefinition
extends ContentDefinition


@export_range(2, 100, 1, "or_greater") var act_one_boss_wave := 5
@export_range(1, 100, 1, "or_greater") var act_two_battle_count := 3
@export_range(0.0, 100.0, 1.0) var event_absence_percent := 50.0
@export_range(0.0, 1000000.0, 0.1, "or_greater") var new_hero_ability_weight := 3.0
@export_range(0.0, 1000000.0, 0.1, "or_greater") var hero_ability_upgrade_weight := 1.0


func act_one_boss_index() -> int:
	return act_one_boss_wave - 1


func final_encounter_index(act: int) -> int:
	return act_one_boss_index() if act == 1 else act_two_battle_count - 1
