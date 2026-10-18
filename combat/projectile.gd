class_name CombatProjectile
extends Node2D


const PRIDE_CAST_SPARKS_ATLAS := preload("res://graphics/effects/projectiles/pride_bolt_cast_sparks.png")
const PRIDE_ID := &"hero.control_savant"
const PRIDE_CAST_FRAME_SIZE := Vector2i(64, 64)
const PRIDE_CAST_FRAME_COUNT := 8
const PRIDE_CAST_ATLAS_COLUMNS := 4

static var pride_cast_sprite_frames: SpriteFrames

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
var uses_hero_visual := false
var uses_pride_visual := false
var pride_effect: AnimatedSprite2D
var pride_cast_sparks: AnimatedSprite2D


func _ready() -> void:
	pride_effect = AnimatedSprite2D.new()
	pride_effect.name = "HeroProjectileEffect"
	pride_effect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pride_effect.visible = false
	add_child(pride_effect)
	pride_cast_sparks = AnimatedSprite2D.new()
	pride_cast_sparks.name = "PrideCastSparks"
	pride_cast_sparks.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pride_cast_sparks.top_level = true
	pride_cast_sparks.visible = false
	add_child(pride_cast_sparks)
	if pride_cast_sprite_frames == null:
		pride_cast_sprite_frames = _build_pride_cast_sprite_frames()
	pride_cast_sparks.sprite_frames = pride_cast_sprite_frames
	pride_cast_sparks.animation_finished.connect(_hide_pride_cast_sparks)


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
	uses_hero_visual = HeroAttackVfx.has_projectile(source.snapshot.definition_id)
	uses_pride_visual = source.snapshot.definition_id == PRIDE_ID
	position = source.basic_projectile_origin(target) if uses_hero_visual else source.position
	_update_travel_direction()
	if uses_hero_visual:
		pride_effect.sprite_frames = HeroAttackVfx.get_projectile_frames(source.snapshot.definition_id)
		pride_effect.visible = true
		pride_effect.play(&"fly")
	if uses_pride_visual:
		pride_cast_sparks.global_position = global_position
		pride_cast_sparks.visible = true
		pride_cast_sparks.play(&"burst")
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
	last_target_position = target.position
	queue_redraw()


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
	queue_redraw()


func _build_pride_cast_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"burst")
	frames.set_animation_loop(&"burst", false)
	frames.set_animation_speed(&"burst", 16.67)
	for frame_index in PRIDE_CAST_FRAME_COUNT:
		var frame := AtlasTexture.new()
		frame.atlas = PRIDE_CAST_SPARKS_ATLAS
		frame.region = Rect2i(
			(frame_index % PRIDE_CAST_ATLAS_COLUMNS) * PRIDE_CAST_FRAME_SIZE.x,
			floori(float(frame_index) / PRIDE_CAST_ATLAS_COLUMNS) * PRIDE_CAST_FRAME_SIZE.y,
			PRIDE_CAST_FRAME_SIZE.x,
			PRIDE_CAST_FRAME_SIZE.y
		)
		frames.add_frame(&"burst", frame)
	return frames


func _hide_pride_cast_sparks() -> void:
	pride_cast_sparks.visible = false


func _update_travel_direction() -> void:
	var offset := _destination() - position
	if not offset.is_zero_approx():
		travel_direction = offset.normalized()
	if uses_hero_visual:
		pride_effect.rotation = travel_direction.angle()


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
		if ability == null and dart_ability_id.is_empty():
			source.session.spawn_hero_attack_impact(source, target.position, travel_direction)
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
	queue_redraw()


## Visual only: the shot keeps flying to where its target was (or its corpse is),
## shows the impact there and disappears without dealing damage.
func _fly_to_lost_target(delta: float) -> void:
	var destination := _destination()
	var offset := destination - position
	_update_travel_direction()
	var travel_distance := speed * delta
	if offset.length() <= travel_distance + 6.0:
		if ability == null and dart_ability_id.is_empty() and is_instance_valid(source) and source.session != null:
			source.session.spawn_hero_attack_impact(source, destination, travel_direction)
		queue_free()
		return
	position += offset.normalized() * travel_distance
	queue_redraw()


func _draw() -> void:
	if uses_hero_visual:
		return
	draw_line(-travel_direction * 16.0, -travel_direction * 5.0, Color(color, 0.45), 5.0, true)
	draw_circle(Vector2.ZERO, 8.0, color.darkened(0.35))
	draw_circle(Vector2.ZERO, 6.0, color)
	draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
