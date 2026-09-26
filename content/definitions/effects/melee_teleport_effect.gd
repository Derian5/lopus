class_name MeleeTeleportEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var distance := 100.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var cooldown_seconds := 15.0


func apply(_source, target, _ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.melee_teleport_distance = maxf(target.melee_teleport_distance, distance)
		target.melee_teleport_cooldown = cooldown_seconds
