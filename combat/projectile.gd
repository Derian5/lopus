class_name CombatProjectile
extends Node2D


var source: Combatant
var target: Combatant
var damage := 0.0
var speed := 650.0
var lifetime := 5.0
var color := Color.WHITE
var ability: AbilityDefinition


func setup(
	projectile_source: Combatant,
	projectile_target: Combatant,
	projectile_damage: float,
	projectile_color: Color
) -> void:
	source = projectile_source
	target = projectile_target
	damage = projectile_damage
	color = projectile_color
	position = source.position
	queue_redraw()


func setup_ability(
	projectile_source: Combatant,
	projectile_target: Combatant,
	ability_definition: AbilityDefinition,
	projectile_color: Color
) -> void:
	source = projectile_source
	target = projectile_target
	ability = ability_definition
	color = projectile_color
	position = source.position
	queue_redraw()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0 or not is_instance_valid(target) or not target.is_alive():
		queue_free()
		return

	var offset := target.position - position
	var travel_distance := speed * delta
	if offset.length() <= travel_distance + target.body_radius:
		if ability != null:
			source.session._apply_ability_effects(source, target, ability)
		else:
			target.take_damage(damage, source)
		queue_free()
		return

	position += offset.normalized() * travel_distance


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, color)
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
