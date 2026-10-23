class_name CombatProjectile
extends Node2D

## Preloaded rather than used by class name, so headless runs work before the editor scans new classes.
const VFX := preload("res://combat/vfx/combat_vfx.gd")
const TRAIL := preload("res://combat/vfx/projectile_trail.gd")


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
	position = source.basic_projectile_origin(target)
	last_target_position = target.position
	var effect_id := ability_definition.projectile_vfx if not ability_definition.projectile_vfx.is_empty() else VFX.projectile_for(source.snapshot.definition_id, source.snapshot.job_id)
	_start_visual(effect_id, projectile_color.lerp(Color.WHITE, 0.1))


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
	position = source.basic_projectile_origin(target)
	last_target_position = target.position
	_start_visual(&"venom_bolt")


func _start_visual(effect_id: StringName, tint := Color.WHITE) -> void:
	vfx_id = effect_id
	vfx_tint = VFX.PROJECTILE_COLORS.get(effect_id, Color.WHITE) if tint.is_equal_approx(Color.WHITE) else tint
	_update_travel_direction()
	var session = source.session if is_instance_valid(source) else null
	if session == null or not session.vfx_enabled:
		return
	var sprite_scale := 0.8 if effect_id == &"arrow" else (0.85 if effect_id == &"venom_bolt" else (1.05 if effect_id == &"fire_arrow" else 0.8))
	var sprite_tint := Color.WHITE if effect_id in [&"arrow", &"fire_arrow"] else vfx_tint
	vfx_sprite = VFX.make_projectile_sprite(effect_id, sprite_tint, sprite_scale)
	if vfx_sprite != null:
		add_child(vfx_sprite)
		vfx_sprite.rotation = travel_direction.angle()
		if effect_id == &"fire_arrow":
			# The blazing head, flame tail and embers, drawn additively over the arrow.
			var glow := VFX.make_projectile_sprite(&"fire_arrow_glow", Color.WHITE, sprite_scale)
			if glow != null:
				glow.name = "FireGlow"
				glow.frame = vfx_sprite.frame
				vfx_sprite.add_child(glow)
				# The fire burns bigger than the arrow it rides on.
				glow.scale = Vector2.ONE * 1.3
				glow.position = Vector2.ZERO
		if VFX.SHOT_LIGHTS.has(effect_id):
			var light_config: Array = VFX.SHOT_LIGHTS[effect_id]
			add_child(VFX.make_light(Color(light_config[0]), float(light_config[1]), float(light_config[2])))
		var effects: Node = session.get_node("Effects")
		if effects.get_child_count() < VFX.MAX_ACTIVE:
			var trail := TRAIL.new()
			trail.name = "ShotTrail_%s" % effect_id
			trail.projectile = self
			trail.effect_id = effect_id
			trail.tint = vfx_tint
			trail.z_index = 19
			effects.add_child(trail)
		# Launch flash at the weapon (arrows and bolts just fly).
		if effect_id == &"fire_arrow":
			# The arrow catches fire on the bowstring: a puff of flame and firelight.
			VFX.spawn(session.get_node("Effects"), &"fire_burst", position - Vector2(0.0, 18.0), 0.3, Color.WHITE, 0.0, VFX.IMPACT_Z, true)
			VFX.flash_light(session.light_layer, position, VFX.FIRE_LIGHT, 1.2, 0.9, 0.3)
		elif effect_id not in [&"arrow", &"venom_bolt"]:
			VFX.spawn(session.get_node("Effects"), &"magic_burst", position, 0.18, vfx_tint, 0.0, VFX.IMPACT_Z, true)
			VFX.flash_light(session.light_layer, position, vfx_tint, 0.65, 0.75, 0.16)


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
