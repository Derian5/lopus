class_name RadialEnemyDamageEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 200.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var damage := 70.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.damage_enemies_in_radius(source, radius, damage, ability.id, effect_id)


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_enemy_in_radius(source, radius)
