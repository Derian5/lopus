class_name RouteDefinition
extends ContentDefinition


@export_range(2, 100, 1, "or_greater") var act_one_boss_wave := 5
@export_range(1, 100, 1, "or_greater") var act_two_battle_count := 3
@export_range(0.0, 100.0, 1.0) var event_absence_percent := 50.0
@export_range(0.0, 1000000.0, 0.1, "or_greater") var new_hero_ability_weight := 3.0
@export_range(0.0, 1000000.0, 0.1, "or_greater") var hero_ability_upgrade_weight := 1.0
@export_range(0.0, 10.0, 0.1, "or_greater") var hero_ability_upgrade_level_penalty := 1.0
## Act I enemy power by battle index (multiplies enemy Max HP and Damage on top of
## each encounter's own enemy_power). The wasteland grows harder as the army does.
@export var act_one_enemy_power_curve := PackedFloat32Array()
## Act II enemy power by battle index (Act II continues from where Act I ended).
@export var act_two_enemy_power_curve := PackedFloat32Array()
@export var opening_event_id: StringName
@export var act_one_post_battle_event_ids: Array[StringName] = []


func act_one_boss_index() -> int:
	return act_one_boss_wave - 1


func final_encounter_index(act: int) -> int:
	return act_one_boss_index() if act == 1 else act_two_battle_count - 1


func post_battle_event_id(act: int, completed_battles: int) -> StringName:
	if act != 1 or completed_battles <= 0 or completed_battles > act_one_post_battle_event_ids.size():
		return &""
	return act_one_post_battle_event_ids[completed_battles - 1]


## Combined enemy Max HP / Damage multiplier for an encounter fought at encounter_index.
func enemy_power_for(act: int, encounter_index: int) -> float:
	var curve := act_one_enemy_power_curve if act == 1 else (act_two_enemy_power_curve if act == 2 else PackedFloat32Array())
	if curve.is_empty():
		return 1.0
	return curve[clampi(encounter_index, 0, curve.size() - 1)]
