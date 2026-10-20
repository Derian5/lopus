class_name CombatProjectile
extends Node2D

## Preloaded rather than used by class name, so headless runs work before the editor scans new classes.
const VFX := preload("res://combat/vfx/combat_vfx.gd")


var source: Combatant
var target: Combatant
var damage := 0.0
var speed := 650.0
var lifetime := 5.0
var color := Color.WHITE
var ability: AbilityDefinition
var dart_damage := 0.0
var dart_slow_percent := 0.0
var dart_ability_id: StringName
var dart_effect_id: StringName
var travel_direction := Vector2.RIGHT
## Where the projectile is heading once its target can no longer be hit (it died,
## vanished or turned untargetable): it finishes its flight there and fizzles.
var target_lost := false
var last_target_position := Vector2.ZERO
## Effect id of the flying sprite (CombatVfx) and the sprite itself; none while the
## session has visual effects turned off.
var vfx_id: StringName
var vfx_tint := Color.WHITE
var vfx_sprite: AnimatedSprite2D


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
	position = source.basic_projectile_origin(target)
	_start_visual(VFX.projectile_for(source.snapshot.definition_id, source.snapshot.job_id))


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
	last_target_position = target.position
	_start_visual(&"magic_orb", projectile_color.lerp(Color.WHITE, 0.2))


func setup_envy_dart(
	projectile_source: Combatant,
	projectile_target: Combatant,
	projectile_damage: float,
	slow_percent: float,
	ability_id: StringName,
	effect_id: StringName,
	projectile_color: Color
) -> void:
	source = projectile_source
	target = projectile_target
	dart_damage = projectile_damage
	dart_slow_percent = slow_percent
	dart_ability_id = ability_id
	dart_effect_id = effect_id
	color = projectile_color
	position = source.position
	last_target_position = target.position
	_start_visual(&"venom_bolt")


func _start_visual(effect_id: StringName, tint := Color.WHITE) -> void:
	vfx_id = effect_id
	vfx_tint = tint
	_update_travel_direction()
	var session = source.session if is_instance_valid(source) else null
	if session == null or not session.vfx_enabled:
		return
	var sprite_scale := 0.8 if effect_id == &"arrow" else (0.85 if effect_id == &"venom_bolt" else 1.0)
	vfx_sprite = VFX.make_projectile_sprite(effect_id, tint, sprite_scale)
	if vfx_sprite != null:
		add_child(vfx_sprite)
		vfx_sprite.rotation = travel_direction.angle()
		if VFX.SHOT_LIGHTS.has(effect_id):
			var light_config: Array = VFX.SHOT_LIGHTS[effect_id]
			add_child(VFX.make_light(Color(light_config[0]) * tint, float(light_config[1]), float(light_config[2])))
		# Launch flash at the weapon (arrows and bolts just fly).
		if effect_id != &"arrow" and effect_id != &"venom_bolt":
			var flash_color: Color = VFX.PROJECTILE_COLORS.get(effect_id, Color.WHITE) * tint
			VFX.spawn(session.get_node("Effects"), &"magic_burst", position, 0.4, flash_color, 0.0, VFX.IMPACT_Z, true)
			VFX.flash_light(session.light_layer, position, flash_color, 1.2, 1.4, 0.25)


func _spawn_hit_visual(at: Vector2) -> void:
	if is_instance_valid(source) and source.session != null:
		source.session.spawn_projectile_hit_vfx(vfx_id, at, travel_direction, vfx_tint)


func _update_travel_direction() -> void:
	var offset := _destination() - position
	if not offset.is_zero_approx():
		travel_direction = offset.normalized()
	if vfx_sprite != null:
		vfx_sprite.rotation = travel_direction.angle()


func _destination() -> Vector2:
	if is_instance_valid(target):
		last_target_position = target.position
	return last_target_position


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if not target_lost and (not is_instance_valid(target) or not is_instance_valid(source) or not target.can_be_targeted_by(source)):
		target_lost = true
	if target_lost:
		_fly_to_lost_target(delta)
		return

	var offset := target.position - position
	_update_travel_direction()
	var travel_distance := speed * delta
	if offset.length() <= travel_distance + target.body_radius:
		_spawn_hit_visual(target.position)
		if not dart_ability_id.is_empty():
			target.apply_envy_dart_poison(dart_damage, dart_slow_percent, source, dart_ability_id, dart_effect_id)
		elif ability != null:
			source.session.apply_projectile_impact(source, target, ability, target.position)
		else:
			var damage_dealt := target.take_damage(damage, source)
			source.apply_basic_attack_lifesteal(damage_dealt)
			source.record_successful_basic_hit(target, damage_dealt)
		queue_free()
		return

	position += offset.normalized() * travel_distance


## Visual only: the shot keeps flying to where its target was (or its corpse is),
## shows the impact there and disappears without dealing damage.
func _fly_to_lost_target(delta: float) -> void:
	var destination := _destination()
	var offset := destination - position
	_update_travel_direction()
	var travel_distance := speed * delta
	if offset.length() <= travel_distance + 6.0:
		_spawn_hit_visual(destination)
		queue_free()
		return
	position += offset.normalized() * travel_distance
