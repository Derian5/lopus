class_name SummonMergeEffect
extends AbilityEffect


@export var merged_unit: EnemyDefinition
@export_range(0.0, 10.0, 0.1, "or_greater") var stat_multiplier := 1.0
@export_range(0.0, 10.0, 0.01, "or_greater") var attack_speed_bonus_per_summon := 0.2
@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 10.0
@export_range(2, 100, 1, "or_greater") var minimum_summons := 2
@export_range(0.0, 100.0, 1.0) var summoner_contribution_percent := 25.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.can_merge_owned_summons(source, minimum_summons)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source) and merged_unit != null:
		source.session.merge_owned_summons(
			source,
			merged_unit,
			stat_multiplier,
			attack_speed_bonus_per_summon,
			duration,
			minimum_summons,
			summoner_contribution_percent,
			ability.id,
			effect_id
		)
