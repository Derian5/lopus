class_name SummonEffect
extends AbilityEffect


@export var summoned_unit: EnemyDefinition
@export_range(1, 100, 1, "or_greater") var max_active_summons := 1
@export_range(0.0, 100.0, 1.0) var summoner_contribution_percent := 100.0


func can_apply(source, _target, ability: AbilityDefinition) -> bool:
	return (
		is_instance_valid(source)
		and source.session.can_spawn_summon(source, ability.id, effect_id, max_active_summons)
	)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source) and summoned_unit != null:
		source.session.spawn_summon(
			source,
			summoned_unit,
			ability.id,
			effect_id,
			max_active_summons,
			summoner_contribution_percent
		)
