class_name DespairGrowthEffect
extends AbilityEffect


@export_range(0.0, 100.0, 0.1) var max_hp_percent_per_second := 2.0
@export_range(0.0, 100.0, 0.1) var damage_percent_per_second := 2.0
@export_range(0.0, 100.0, 0.1) var armor_percent_per_second := 2.0
@export_range(0.0, 100.0, 0.1) var movement_speed_percent_per_second := 2.0
@export_range(0.0, 100.0, 0.1) var attack_speed_percent_per_second := 1.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_bonus_percent := 200.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var interval := 1.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_despair_growth(
			max_hp_percent_per_second,
			damage_percent_per_second,
			armor_percent_per_second,
			movement_speed_percent_per_second,
			attack_speed_percent_per_second,
			maximum_bonus_percent,
			interval,
			ability.id,
			effect_id
		)
