class_name EnvyStrongestAllyDamageEffect
extends AbilityEffect


@export_range(0.0, 1000.0, 1.0, "or_greater") var bonus_percent := 15.0


func apply(_source, target, _ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.envy_strongest_ally_damage_percent = bonus_percent
