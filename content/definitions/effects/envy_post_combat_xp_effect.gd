class_name EnvyPostCombatXpEffect
extends AbilityEffect


@export_range(0.0, 1000.0, 1.0, "or_greater") var bonus_percent := 15.0


func apply(_source, _target, _ability: AbilityDefinition) -> void:
	# The snapshot carries this passive into CombatResult so application remains idempotent.
	pass
