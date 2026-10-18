class_name Combatant
extends CharacterBody2D


enum State {
	IDLE,
	ACQUIRE_TARGET,
	MOVE_INTO_RANGE,
	ATTACK_WINDUP,
	ATTACK_RECOVERY,
	DEAD,
}

const HERO_VISUAL_RADIUS := 28.8
const UNIT_VISUAL_RADIUS := 28.8
const BOSS_VISUAL_RADIUS := 45.6
const COLLISION_SCALE := 0.7
const HERO_RADIUS := HERO_VISUAL_RADIUS * COLLISION_SCALE
const UNIT_RADIUS := UNIT_VISUAL_RADIUS * COLLISION_SCALE
const BOSS_RADIUS := BOSS_VISUAL_RADIUS * COLLISION_SCALE
const UNIT_SPRITE_SCALE := 1.68
const STUCK_TIMEOUT := 3.0
const RANGED_ATTACK_PAUSE := 0.1
const FRENZY_ACTIVATION_DELAY := 3.0
const FRENZY_DIRECTION_INTERVAL := 0.75
const HEALING_FLASH_PRIORITY := 1
const DAMAGE_FLASH_PRIORITY := 2
const ARCHER_ATLAS := preload("res://graphics/units/player/units/archer/archer.png")
const PRIEST_ATLAS := preload("res://graphics/units/player/units/priest/priest.png")
const SUMMONER_ATLAS := preload("res://graphics/units/player/units/summoner/summoner.png")
const CHROMA_KEY_SHADER := preload("res://combat/unit_chroma_key.gdshader")
const HERO_PROJECTILE_TIPS := {
	&"hero.army_support": Vector2(323.0, -100.0),
	&"hero.iron_oracle": Vector2(168.0, -174.0),
	&"hero.control_savant": Vector2(125.0, -58.0),
}
const UNIT_ANIMATION_CONFIGS := {
	&"job.militia": {
		"frame_directory": "res://graphics/units/player/units/militia",
		"move_frames": 16,
		"attack_frames": 16,
		"death_frames": 16,
		"move_speed": 12.0,
		"attack_speed": 16.0,
		"death_speed": 12.0,
		"scale": 0.16,
		"chroma_key": true,
		"health_bar_offset": 72.0,
	},
	&"job.archer": {"atlas": ARCHER_ATLAS, "columns": 8, "move_frames": 8, "attack_frames": 8, "scale": 0.25},
	&"job.priest": {"atlas": PRIEST_ATLAS, "columns": 8, "move_frames": 8, "attack_frames": 8, "scale": 0.225},
	&"job.summoner": {"atlas": SUMMONER_ATLAS, "columns": 8, "move_frames": 8, "attack_frames": 6, "scale": 0.245},
	&"hero.iron_oracle": {"frame_directory": "res://graphics/units/player/hero/Despair", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.17, "chroma_key": true, "health_bar_offset": 78.0},
	&"hero.army_support": {"frame_directory": "res://graphics/units/player/hero/Envy", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.15, "chroma_key": true, "health_bar_offset": 78.0},
	&"hero.thorn_warden": {"frame_directory": "res://graphics/units/player/hero/gluttony", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.15, "animation_scales": {&"attack": 2.0}, "chroma_key": true, "crop_green_canvas": true, "health_bar_offset": 78.0},
	&"hero.test_vanguard": {"frame_directory": "res://graphics/units/player/hero/greed", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.095, "chroma_key": true, "reverse_attack_recovery": true, "health_bar_offset": 78.0},
	&"hero.glass_arcanist": {"frame_directory": "res://graphics/units/player/hero/lust", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.078, "animation_scales": {&"attack": 3.8}, "chroma_key": true, "health_bar_offset": 78.0},
	&"hero.control_savant": {"frame_directory": "res://graphics/units/player/hero/Pride", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.22, "chroma_key": true, "health_bar_offset": 78.0},
	&"hero.ashen_duelist": {"frame_directory": "res://graphics/units/player/hero/Wrath", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.125, "chroma_key": true, "crop_green_canvas": true, "health_bar_offset": 78.0},
}

## Per-frame body-anchor offsets generated from the source frames
## (see combat/unit_frame_offsets.json). They keep each unit's torso and feet
## planted while it walks and attacks, removing sprite jitter.
const FACING_DEAD_ZONE := 6.0
const FACING_MIN_SPEED := 8.0
const FRAME_OFFSETS_PATH := "res://combat/unit_frame_offsets.json"
static var unit_sprite_frames: Dictionary = {}
static var authored_frame_offsets: Dictionary = {}
static var authored_frame_offsets_loaded := false
static var chroma_frame_offsets: Dictionary = {}

@export var damage_flash_color := Color.WHITE
@export_range(0.0, 10.0, 0.01, "or_greater") var damage_flash_duration := 0.1
## Knockback for a hit worth damage_knockback_reference_percent of Max HP; it scales
## linearly with the hit's share of Max HP and is capped at damage_knockback_max_distance.
@export_range(0.0, 1000.0, 0.1, "or_greater") var damage_knockback_distance := 10.0
@export_range(0.1, 100.0, 0.1) var damage_knockback_reference_percent := 5.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var damage_knockback_max_distance := 36.0
@export var healing_flash_color := Color(1.0, 0.9, 0.2, 1.0)
@export_range(0.0, 10.0, 0.01, "or_greater") var healing_flash_duration := 0.1

var snapshot: CombatUnitSnapshot
var session
var arena_bounds := Rect2()
var state := State.IDLE
var target: Combatant
var current_hp := 0.0
var body_radius := UNIT_RADIUS
var base_body_radius := UNIT_RADIUS
var visual_radius := UNIT_VISUAL_RADIUS
var base_visual_radius := UNIT_VISUAL_RADIUS
var state_timer := 0.0
var windup_duration := 0.0
var attack_animation_duration := 0.0
var stuck_time := 0.0
var last_movement_position := Vector2.ZERO
var simulation_active := false
var temporarily_removed := false
var selected := false
var last_damage_source_id := ""
var last_effect_id: StringName
var last_damage_taken_time := -1.0
var ability_cooldowns: Dictionary = {}
var statuses: Array[StatusInstance] = []
var temporary_modifiers: Array[Dictionary] = []
var basic_attack_empowerments: Array[Dictionary] = []
var shields: Array[Dictionary] = []
var pending_ability: AbilityDefinition
var boss_phase := 1
var phase_banner_timer := 0.0
var last_stand_aura_duration := 0.0
var last_stand_remaining := 0.0
var basic_attack_range_bonus := 0.0
var passive_basic_lifesteal_percent := 0.0
var passive_basic_lifesteal_ability_id: StringName
var passive_basic_lifesteal_effect_id: StringName
## [{"status": StatusDefinition, "ability_id": StringName}] applied by every successful basic hit.
var on_hit_statuses: Array[Dictionary] = []
var nearby_ally_bonus_stat: StringName
var nearby_ally_bonus_value := 0.0
var nearby_ally_bonus_radius := 0.0
var nearby_ally_bonus_max := 0
var nearby_ally_bonus_ability_id: StringName
var targets_farthest_enemy := false
var prefers_farthest_enemy := false
var melee_teleport_distance := 0.0
var melee_teleport_cooldown := 0.0
var melee_teleport_cooldown_remaining := 0.0
var enemy_attack_speed_aura_radius := 0.0
var enemy_attack_speed_aura_multiplier := 1.0
var stealth_remaining := 0.0
var stealth_ability_id: StringName
var stealth_effect_id: StringName
var kill_gold_reward := 0
var kill_permanent_damage := 0.0
var kill_reward_ability_id: StringName
var kill_reward_effect_id: StringName
var melee_retaliation_radius := 0.0
var melee_retaliation_multiplier := 0.0
var melee_retaliation_ability_id: StringName
var melee_retaliation_effect_id: StringName
var attack_reflect_percent := 0.0
var attack_reflect_ability_id: StringName
var attack_reflect_effect_id: StringName
var focused_damage_per_stack := 0.0
var focused_stack_duration := 0.0
var focused_damage_stacks: Dictionary = {}
var frenzy_remaining := 0.0
var frenzy_attack_speed_multiplier := 1.0
var frenzy_ability_id: StringName
var frenzy_effect_id: StringName
var frenzy_destination := Vector2.ZERO
var frenzy_direction_timer := 0.0
var first_enemy_damage_time := -1.0
var threshold_guard_health_ratio := 0.0
var threshold_guard_shield_multiplier := 0.0
var threshold_guard_armor_multiplier := 1.0
var threshold_guard_duration := 0.0
var threshold_guard_cooldown := 0.0
var threshold_guard_cooldown_remaining := 0.0
var threshold_guard_ability_id: StringName
var threshold_guard_effect_id: StringName
var ground_slam_damage_multiplier := 0.0
var ground_slam_radius := 0.0
var ground_slam_ability_id: StringName
var ground_slam_effect_id: StringName
var melee_retreat_remaining := 0.0
var melee_retreat_source: Combatant
var melee_retreat_direction := Vector2.ZERO
var melee_retreat_counterattack_pending := false
var envy_strongest_ally_damage_percent := 0.0
var envy_dart_slow_applied := false
var runtime_status_metadata: Array[Dictionary] = []
var forced_basic_target: Combatant
var forced_basic_target_remaining := 0.0
var lust_death_scaling_percent := 0.0
var lust_death_scaling_ability_id: StringName
var lust_target_slow_percent := 0.0
var lust_target_slow_ability_id: StringName
var lust_bond_pending := false
var lust_bond_partner: Combatant
var lust_bond_lifesteal_percent := 0.0
var lust_bond_attack_speed_multiplier := 1.0
var lust_bond_ability_id: StringName
var lust_bond_effect_id: StringName
var lust_basic_hits_required := 0
var lust_basic_hit_count := 0
var lust_basic_knockback_distance := 0.0
var lust_basic_stun_duration := 0.0
var lust_basic_ability_id: StringName
var lust_basic_effect_id: StringName
var basic_attack_target_active := false
var gluttony_lifesteal_aura_radius := 0.0
var gluttony_lifesteal_percent := 0.0
var gluttony_lifesteal_ability_id: StringName
var gluttony_lifesteal_effect_id: StringName
var gluttony_regeneration_max_stacks := 0
var gluttony_regeneration_stacks := 0
var gluttony_regeneration_percent_per_stack := 0.0
var gluttony_regeneration_tick_remaining := 1.0
var gluttony_regeneration_ability_id: StringName
var gluttony_regeneration_effect_id: StringName
var gluttony_damage_aura_radius := 0.0
var gluttony_damage_aura_damage := 0.0
var gluttony_damage_aura_interval := 0.0
var gluttony_damage_aura_tick_remaining := 0.0
var gluttony_damage_aura_ability_id: StringName
var gluttony_damage_aura_effect_id: StringName
var gluttony_death_explosion_radius := 0.0
var gluttony_death_explosion_damage := 0.0
var gluttony_death_explosion_triggered := false
var gluttony_death_explosion_ability_id: StringName
var gluttony_death_explosion_effect_id: StringName
var gluttony_grease_miss_percent := 0.0
var despair_team_proc_chance_percent := 0.0
var despair_team_proc_total_damage_percent := 0.0
var despair_team_proc_ability_id: StringName
var despair_team_proc_effect_id: StringName
var despair_attack_slow_max_stacks := 0
var despair_attack_slow_percent_per_stack := 0.0
var despair_attack_slow_maximum_percent := 0.0
var despair_slow_ability_id: StringName
var despair_slow_effect_id: StringName
var despair_slow_max_stacks := 0
var despair_slow_percent_per_stack := 0.0
var despair_slow_maximum_percent := 0.0
var despair_slow_stacks := 0
var despair_slow_applied_percent := 0.0
var despair_sanctuary_remaining := 0.0
var despair_sanctuary_heal_percent := 0.0
var despair_sanctuary_interval := 0.0
var despair_sanctuary_tick_remaining := 0.0
var despair_sanctuary_source: Combatant
var despair_sanctuary_ability_id: StringName
var despair_sanctuary_effect_id: StringName
var despair_growth_rates: Dictionary = {}
var despair_growth_bonus_percent: Dictionary = {}
var despair_growth_maximum_percent := 0.0
var despair_growth_interval := 0.0
var despair_growth_tick_remaining := 0.0
var despair_growth_ability_id: StringName
var despair_growth_effect_id: StringName
var flash_remaining := 0.0
var flash_color := Color.TRANSPARENT
var flash_priority := 0
var sprite_was_attacking := false
var sprite_was_attack_recovery := false
var unit_sprite_frame_offsets: Dictionary = {}
## Offsets the sprites used before authored body anchors; kept for gameplay-facing
## positions (projectile origins) so combat timing stays identical.
var unit_sprite_legacy_offsets: Dictionary = {}
var unit_sprite_legacy_position := Vector2.ZERO
var unit_sprite_uses_chroma_key := false
var unit_sprite_reverses_attack_recovery := false
var unit_sprite_base_scale := 1.0
var unit_sprite_animation_scales: Dictionary = {}
var health_bar_offset := 0.0
var initial_walk_delay_frames := 0
var initial_walk_delay_remaining := 0.0

@onready var unit_sprite: AnimatedSprite2D = $UnitSprite


func setup(unit_snapshot: CombatUnitSnapshot, combat_session, bounds: Rect2, walk_delay_frames: int = 0) -> void:
	snapshot = unit_snapshot.duplicate_snapshot()
	session = combat_session
	arena_bounds = bounds
	initial_walk_delay_frames = clampi(walk_delay_frames, 0, 9)
	current_hp = snapshot.stats.max_hp
	prefers_farthest_enemy = snapshot.targeting_mode == &"farthest"
	base_body_radius = BOSS_RADIUS if snapshot.is_boss else (HERO_RADIUS if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else UNIT_RADIUS)
	body_radius = base_body_radius
	base_visual_radius = BOSS_VISUAL_RADIUS if snapshot.is_boss else (HERO_VISUAL_RADIUS if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else UNIT_VISUAL_RADIUS)
	visual_radius = base_visual_radius
	var collision_shape := CircleShape2D.new()
	collision_shape.radius = body_radius
	$CollisionShape2D.shape = collision_shape
	# Soft separation is predictable and avoids crowd deadlocks.
	collision_layer = 0
	collision_mask = 0
	last_movement_position = position
	state = State.ACQUIRE_TARGET
	simulation_active = true
	_setup_unit_sprite()
	_apply_passive_abilities()
	for ability in snapshot.abilities:
		if ability.kind == AbilityDefinition.AbilityKind.ACTIVE and ability.initial_cooldown_seconds > 0.0:
			ability_cooldowns[ability.id] = ability.initial_cooldown_seconds
	queue_redraw()


func _physics_process(delta: float) -> void:
	_update_flash(delta)
	if not simulation_active or state == State.DEAD:
		velocity = Vector2.ZERO
		return
	_update_runtime(delta)
	if not is_alive():
		return
	if is_stunned():
		velocity = Vector2.ZERO
		return
	if frenzy_remaining > 0.0:
		_update_frenzy(delta)
		return
	if melee_retreat_remaining > 0.0:
		_update_melee_retreat(delta)
		return
	if _try_use_priority_summon():
		return

	match state:
		State.IDLE:
			state = State.ACQUIRE_TARGET
		State.ACQUIRE_TARGET:
			_acquire_target()
		State.MOVE_INTO_RANGE:
			_move_toward_target(delta)
		State.ATTACK_WINDUP:
			_update_attack_windup(delta)
		State.ATTACK_RECOVERY:
			_update_attack_recovery(delta)


func _process(delta: float) -> void:
	initial_walk_delay_remaining = maxf(0.0, initial_walk_delay_remaining - delta)
	if unit_sprite.visible:
		_update_unit_sprite()


func _setup_unit_sprite() -> void:
	var animation_id := snapshot.job_id if UNIT_ANIMATION_CONFIGS.has(snapshot.job_id) else snapshot.definition_id
	unit_sprite.visible = UNIT_ANIMATION_CONFIGS.has(animation_id)
	if not unit_sprite.visible:
		return
	var config: Dictionary = UNIT_ANIMATION_CONFIGS[animation_id]
	if not unit_sprite_frames.has(animation_id):
		unit_sprite_frames[animation_id] = _build_unit_sprite_frames(config)
	unit_sprite.sprite_frames = unit_sprite_frames[animation_id]
	unit_sprite_base_scale = float(config["scale"]) * UNIT_SPRITE_SCALE
	unit_sprite_animation_scales = config.get("animation_scales", {})
	unit_sprite.scale = Vector2.ONE * unit_sprite_base_scale
	health_bar_offset = float(config.get("health_bar_offset", 0.0))
	unit_sprite_uses_chroma_key = bool(config.get("chroma_key", false))
	unit_sprite_reverses_attack_recovery = bool(config.get("reverse_attack_recovery", false))
	if unit_sprite_uses_chroma_key:
		var chroma_material := ShaderMaterial.new()
		chroma_material.shader = CHROMA_KEY_SHADER
		unit_sprite.material = chroma_material
	unit_sprite_legacy_offsets = config.get("frame_offsets", {})
	unit_sprite_frame_offsets = config.get("frame_offsets", _authored_offsets(String(config.get("frame_directory", ""))))
	unit_sprite.frame_changed.connect(_update_unit_sprite_offset)
	unit_sprite.animation = &"move"
	unit_sprite.frame = 0
	unit_sprite.pause()
	if initial_walk_delay_frames > 0:
		var move_fps := unit_sprite.sprite_frames.get_animation_speed(&"move")
		initial_walk_delay_remaining = float(initial_walk_delay_frames) / move_fps
	_update_unit_sprite_offset()


func _build_unit_sprite_frames(config: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var animation_names: Array[StringName] = [&"move", &"attack"]
	if int(config.get("death_frames", 0)) > 0:
		animation_names.append(&"death")
	for row in animation_names.size():
		var animation_name := animation_names[row]
		var frame_count := int(config["%s_frames" % animation_name])
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, animation_name == &"move")
		frames.set_animation_speed(animation_name, float(config.get("%s_speed" % animation_name, 10.0 if animation_name == &"move" else 12.0)))
		for column in frame_count:
			if config.has("frame_directory"):
				var path := "%s/%s/frame_%04d.png" % [config["frame_directory"], animation_name if animation_name != &"move" else &"walk", column]
				var texture := load(path) as Texture2D
				if bool(config.get("crop_green_canvas", false)):
					texture = _crop_to_green_canvas(texture)
				frames.add_frame(animation_name, texture)
			else:
				var atlas := config["atlas"] as Texture2D
				var columns := int(config["columns"])
				var top := roundi(float(row) * atlas.get_height() / 2.0)
				var bottom := roundi(float(row + 1) * atlas.get_height() / 2.0)
				var left := roundi(float(column) * atlas.get_width() / columns)
				var right := roundi(float(column + 1) * atlas.get_width() / columns)
				var frame := AtlasTexture.new()
				frame.atlas = atlas
				frame.region = Rect2(left, top, right - left, bottom - top)
				frames.add_frame(animation_name, frame)
	return frames


func _update_unit_sprite() -> void:
	var is_attacking := state == State.ATTACK_WINDUP or state == State.ATTACK_RECOVERY
	var is_moving := state != State.DEAD and velocity.length_squared() > 1.0
	if state == State.DEAD and unit_sprite.sprite_frames.has_animation(&"death"):
		if unit_sprite.animation != &"death":
			unit_sprite.speed_scale = 1.0
			unit_sprite.play(&"death")
	elif is_attacking:
		if unit_sprite_reverses_attack_recovery:
			if state == State.ATTACK_WINDUP and not sprite_was_attacking:
				unit_sprite.speed_scale = _attack_animation_speed_scale(windup_duration)
				unit_sprite.play(&"attack")
			elif state == State.ATTACK_RECOVERY and not sprite_was_attack_recovery:
				unit_sprite.speed_scale = _attack_animation_speed_scale(state_timer)
				unit_sprite.play(&"attack", -1.0, true)
		elif not sprite_was_attacking:
			unit_sprite.speed_scale = _attack_animation_speed_scale(attack_animation_duration)
			unit_sprite.play(&"attack")
	elif is_moving:
		if initial_walk_delay_remaining <= 0.0 and (unit_sprite.animation != &"move" or not unit_sprite.is_playing()):
			unit_sprite.speed_scale = 1.0
			unit_sprite.play(&"move")
	else:
		unit_sprite.speed_scale = 1.0
		unit_sprite.animation = &"move"
		unit_sprite.frame = 0
		unit_sprite.pause()
	unit_sprite.scale = Vector2.ONE * unit_sprite_base_scale * float(unit_sprite_animation_scales.get(unit_sprite.animation, 1.0))

	_update_sprite_facing(is_attacking)

	var sprite_color := Color.WHITE
	if stealth_remaining > 0.0:
		sprite_color.a = 0.35
	if state == State.DEAD:
		sprite_color = sprite_color.darkened(0.25 if unit_sprite.sprite_frames.has_animation(&"death") else 0.65)
	if flash_remaining > 0.0 and not unit_sprite_uses_chroma_key:
		sprite_color = flash_color
	if unit_sprite_uses_chroma_key:
		var chroma_material := unit_sprite.material as ShaderMaterial
		chroma_material.set_shader_parameter("flash_color", flash_color)
		chroma_material.set_shader_parameter("flash_amount", 1.0 if flash_remaining > 0.0 else 0.0)
	unit_sprite.modulate = sprite_color
	sprite_was_attacking = is_attacking
	sprite_was_attack_recovery = state == State.ATTACK_RECOVERY
	_update_unit_sprite_offset()


## Units face whatever they are fighting: attacking and kiting ranged units keep
## looking at their target, and a unit backing away from a melee attacker keeps
## looking at it. Free movement faces the walking direction. A small dead zone
## stops the sprite from flickering when the enemy is almost straight above or below.
func _update_sprite_facing(is_attacking: bool) -> void:
	if state == State.DEAD:
		return
	var threat: Combatant = null
	if melee_retreat_remaining > 0.0 and is_instance_valid(melee_retreat_source):
		threat = melee_retreat_source
	elif is_attacking and is_instance_valid(target):
		threat = target
	if threat != null:
		var dx := threat.position.x - position.x
		if absf(dx) > FACING_DEAD_ZONE:
			unit_sprite.flip_h = dx < 0.0
		return
	if absf(velocity.x) > FACING_MIN_SPEED:
		unit_sprite.flip_h = velocity.x < 0.0
	elif is_instance_valid(target) and absf(target.position.x - position.x) > FACING_DEAD_ZONE:
		unit_sprite.flip_h = target.position.x < position.x


func _update_unit_sprite_offset() -> void:
	var offset := _sprite_offset_from(unit_sprite_frame_offsets)
	var legacy_offset := _sprite_offset_from(unit_sprite_legacy_offsets) if unit_sprite_legacy_offsets != unit_sprite_frame_offsets else offset
	if unit_sprite.flip_h:
		offset.x = -offset.x
		legacy_offset.x = -legacy_offset.x
	unit_sprite.position = offset * unit_sprite.scale
	unit_sprite_legacy_position = legacy_offset * unit_sprite.scale


func _sprite_offset_from(offset_table: Dictionary) -> Vector2:
	var offsets: Array = offset_table.get(unit_sprite.animation, [])
	if unit_sprite.frame < offsets.size():
		return offsets[unit_sprite.frame]
	if unit_sprite_uses_chroma_key:
		var offset_frame := 0 if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO and unit_sprite.animation == &"attack" else unit_sprite.frame
		var texture := unit_sprite.sprite_frames.get_frame_texture(unit_sprite.animation, offset_frame)
		return _chroma_frame_offset(texture)
	return Vector2.ZERO


static func _authored_offsets(frame_directory: String) -> Dictionary:
	if frame_directory.is_empty():
		return {}
	if not authored_frame_offsets_loaded:
		authored_frame_offsets_loaded = true
		var file := FileAccess.open(FRAME_OFFSETS_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				for directory in parsed:
					var animations := {}
					for animation_name in parsed[directory]:
						var offsets: Array[Vector2] = []
						for pair in parsed[directory][animation_name]:
							offsets.append(Vector2(float(pair[0]), float(pair[1])))
						animations[StringName(animation_name)] = offsets
					authored_frame_offsets[String(directory)] = animations
	return authored_frame_offsets.get(frame_directory, {})


## Screen-space position of the body anchor for the current frame, relative to the unit.
## Used by tests to verify that walking and attacking keep the body planted.
func body_anchor_offset() -> Vector2:
	var directory := String(UNIT_ANIMATION_CONFIGS.get(snapshot.definition_id, UNIT_ANIMATION_CONFIGS.get(snapshot.job_id, {})).get("frame_directory", ""))
	var offsets: Array = unit_sprite_frame_offsets.get(unit_sprite.animation, [])
	if directory.is_empty() or unit_sprite.frame >= offsets.size():
		return unit_sprite.position
	var anchors: Array = unit_sprite_frame_offsets.get(StringName(String(unit_sprite.animation) + "_anchor"), [])
	if unit_sprite.frame >= anchors.size():
		return unit_sprite.position
	var texture := unit_sprite.sprite_frames.get_frame_texture(unit_sprite.animation, unit_sprite.frame)
	var half := texture.get_size() * 0.5
	return (Vector2(anchors[unit_sprite.frame]) - half) * unit_sprite.scale + unit_sprite.position


func _chroma_frame_offset(texture: Texture2D) -> Vector2:
	var cache_key: Variant = texture.resource_path if not texture.resource_path.is_empty() else texture.get_instance_id()
	if chroma_frame_offsets.has(cache_key):
		return chroma_frame_offsets[cache_key]
	var image := texture.get_image()
	var weighted_position := Vector2.ZERO
	var sample_count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.g - maxf(color.r, color.b) < 0.08:
				weighted_position += Vector2(x, y)
				sample_count += 1
	var visual_center := weighted_position / sample_count if sample_count > 0 else Vector2(image.get_size()) * 0.5
	var offset := Vector2(image.get_size()) * 0.5 - visual_center
	chroma_frame_offsets[cache_key] = offset
	return offset


func _crop_to_green_canvas(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	var width := image.get_width()
	var height := image.get_height()
	var top := 0
	var bottom := height - 1
	var required_green_samples := ceili(float(width) / 8.0)
	for y in range(0, height, 2):
		var green_samples := 0
		for x in range(0, width, 4):
			var color := image.get_pixel(x, y)
			if color.g - maxf(color.r, color.b) >= 0.08:
				green_samples += 1
		if green_samples >= required_green_samples:
			top = y
			break
	for y in range(height - 1, -1, -2):
		var green_samples := 0
		for x in range(0, width, 4):
			var color := image.get_pixel(x, y)
			if color.g - maxf(color.r, color.b) >= 0.08:
				green_samples += 1
		if green_samples >= required_green_samples:
			bottom = y
			break
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(0.0, float(top), float(width), float(bottom - top + 1))
	return cropped


func _acquire_target() -> void:
	if _has_forced_basic_target():
		target = forced_basic_target
		basic_attack_target_active = true
		pending_ability = null
		velocity = Vector2.ZERO
		state = State.MOVE_INTO_RANGE
		return
	if _try_use_ability():
		return
	target = session.find_basic_attack_target(self)
	basic_attack_target_active = is_instance_valid(target)
	velocity = Vector2.ZERO
	state = State.MOVE_INTO_RANGE if is_instance_valid(target) else State.IDLE


func _move_toward_target(delta: float) -> void:
	if not _has_valid_target():
		pending_ability = null
		state = State.ACQUIRE_TARGET
		return

	var offset := target.position - position
	var distance := offset.length()
	var attack_range := basic_attack_reach(target)
	if pending_ability != null and pending_ability.cast_range > 0.0:
		attack_range = pending_ability.cast_range + body_radius + target.body_radius

	var direction := offset.normalized()
	if distance <= attack_range:
		if pending_ability == null and targets_farthest_enemy:
			target = session.find_basic_attack_target(self)
		velocity = Vector2.ZERO
		if pending_ability != null:
			_start_ability_windup()
		else:
			_start_attack()
		return
	if is_rooted():
		velocity = Vector2.ZERO
		return

	var separation: Vector2 = session.get_separation_vector(self)
	var desired_direction: Vector2 = (direction + separation * 0.8).normalized()
	velocity = desired_direction * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	_update_stuck_state(delta)


func _start_attack() -> void:
	basic_attack_target_active = true
	pending_ability = _ready_basic_replacement()
	state = State.ATTACK_WINDUP
	if snapshot.attack_type == &"ranged" and not snapshot.is_boss:
		windup_duration = RANGED_ATTACK_PAUSE
	else:
		windup_duration = 0.65 if snapshot.is_boss else minf(0.35, 0.25 / maxf(get_effective_stat(&"attack_speed"), 0.01))
	state_timer = windup_duration
	attack_animation_duration = _current_attack_cycle_duration()
	queue_redraw()
	session.record_event(
		CombatEvent.ATTACK_STARTED,
		snapshot.runtime_id,
		target.snapshot.runtime_id,
		pending_ability.id if pending_ability != null else &"attack.basic",
		pending_ability.id if pending_ability != null else &"attack.basic"
	)


func _start_ability_windup() -> void:
	state = State.ATTACK_WINDUP
	windup_duration = 0.55 if snapshot.is_boss else 0.2
	state_timer = windup_duration
	attack_animation_duration = _current_attack_cycle_duration()
	queue_redraw()


func _current_attack_cycle_duration() -> float:
	var attack_interval := 1.0 / maxf(get_effective_stat(&"attack_speed"), 0.01)
	var minimum_recovery := 0.0 if snapshot.attack_type == &"ranged" else 0.05
	return windup_duration + maxf(minimum_recovery, attack_interval - windup_duration)


func _attack_animation_speed_scale(playback_duration: float) -> float:
	if snapshot.unit_kind != CombatUnitSnapshot.UnitKind.HERO or playback_duration <= 0.0:
		return 1.0
	var frame_count := unit_sprite.sprite_frames.get_frame_count(&"attack")
	var authored_fps := unit_sprite.sprite_frames.get_animation_speed(&"attack")
	var authored_duration := float(frame_count) / maxf(authored_fps, 0.01)
	return authored_duration / playback_duration


func basic_attack_reach(other: Combatant) -> float:
	if not is_instance_valid(other):
		return get_effective_stat(&"attack_range") + body_radius
	return get_effective_stat(&"attack_range") + body_radius + other.body_radius


func basic_projectile_origin(projectile_target: Combatant) -> Vector2:
	if not HERO_PROJECTILE_TIPS.has(snapshot.definition_id) or not unit_sprite.visible:
		return position
	var faces_left := projectile_target.position.x < position.x
	var sprite_anchor := Vector2(absf(unit_sprite_legacy_position.x) * (-1.0 if faces_left else 1.0), unit_sprite_legacy_position.y)
	var local_tip: Vector2 = HERO_PROJECTILE_TIPS[snapshot.definition_id] * unit_sprite.scale
	if faces_left:
		local_tip.x = -local_tip.x
	return position + sprite_anchor + local_tip


func _update_attack_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	if snapshot.is_boss:
		queue_redraw()
	if not _has_valid_target():
		pending_ability = null
		state = State.ACQUIRE_TARGET
		return

	if pending_ability != null and pending_ability.cast_range > 0.0:
		var allowed_distance := pending_ability.cast_range + body_radius + target.body_radius
		if position.distance_to(target.position) > allowed_distance * 1.25:
			state = State.MOVE_INTO_RANGE
			return
	elif snapshot.attack_type == &"melee":
		if position.distance_to(target.position) > basic_attack_reach(target) + 0.01:
			state = State.MOVE_INTO_RANGE
			return

	state_timer -= delta
	if state_timer > 0.0:
		return

	if pending_ability != null:
		var used_ability := pending_ability
		pending_ability = null
		ability_cooldowns[used_ability.id] = used_ability.cooldown_seconds
		session.deliver_ability(self, target, used_ability)
		if used_ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
			prefers_farthest_enemy = false
	elif snapshot.attack_type == &"ranged":
		session.spawn_projectile(self, target, get_effective_stat(&"damage"))
		prefers_farthest_enemy = false
	else:
		var attack_target := target
		var raw_damage := get_effective_stat(&"damage") + _focused_damage_bonus(attack_target)
		session.spawn_hero_attack_impact(self, attack_target.position, (attack_target.position - position).normalized())
		var damage_dealt := attack_target.take_damage(raw_damage, self, &"attack.basic", &"attack.basic", true)
		prefers_farthest_enemy = false
		_add_focused_damage_stack(attack_target)
		apply_basic_attack_lifesteal(damage_dealt)
		record_successful_basic_hit(attack_target, damage_dealt)
		if ground_slam_damage_multiplier > 0.0:
			session.apply_ground_slam(
				self,
				attack_target.position,
				get_effective_stat(&"damage") * ground_slam_damage_multiplier,
				ground_slam_radius,
				ground_slam_ability_id,
				ground_slam_effect_id
			)
			ground_slam_damage_multiplier = 0.0
			ground_slam_radius = 0.0

	if state == State.DEAD:
		return
	state = State.ATTACK_RECOVERY
	var attack_interval := 1.0 / maxf(get_effective_stat(&"attack_speed"), 0.01)
	state_timer = maxf(0.0 if snapshot.attack_type == &"ranged" else 0.05, attack_interval - windup_duration)
	queue_redraw()


func _update_attack_recovery(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		velocity = Vector2.ZERO
		state = State.ACQUIRE_TARGET
		return
	if snapshot.attack_type == &"ranged" and snapshot.avoids_damage:
		_move_ranged_during_recovery(delta)
	else:
		velocity = Vector2.ZERO


func _move_ranged_during_recovery(delta: float) -> void:
	if is_rooted():
		velocity = Vector2.ZERO
		return
	if not _has_valid_target():
		velocity = Vector2.ZERO
		state = State.ACQUIRE_TARGET
		return
	var offset := target.position - position
	var distance := offset.length()
	var direction := offset.normalized()
	var attack_range := get_effective_stat(&"attack_range")
	var can_retreat := distance < attack_range * 0.55 and _can_retreat_from(direction)
	if can_retreat:
		direction = -direction
	elif distance <= attack_range:
		velocity = Vector2.ZERO
		return
	var separation: Vector2 = session.get_separation_vector(self)
	velocity = (direction + separation * 0.8).normalized() * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	_update_stuck_state(delta)


func take_damage(
	raw_damage: float,
	source: Combatant,
	ability_id: StringName = &"attack.basic",
	effect_id: StringName = &"attack.basic",
	is_melee := false,
	allow_source_lifesteal := true
) -> float:
	if not is_targetable():
		return 0.0
	if despair_sanctuary_remaining > 0.0 and is_instance_valid(source) and source.snapshot.team != snapshot.team:
		return 0.0
	if session.should_dodge(self, ability_id == &"attack.basic"):
		return 0.0
	if ability_id == &"attack.basic" and is_instance_valid(source):
		raw_damage = session.get_basic_attack_damage(source, raw_damage)

	var applied_damage := CombatRules.calculate_damage(raw_damage, get_effective_stat(&"armor"))
	var absorbed_damage := 0.0
	for shield in shields:
		if applied_damage <= 0.0:
			break
		var absorbed := minf(applied_damage, float(shield.amount))
		shield.amount = float(shield.amount) - absorbed
		applied_damage -= absorbed
		absorbed_damage += absorbed
	shields = shields.filter(func(shield: Dictionary) -> bool: return float(shield.amount) > 0.0)
	applied_damage = minf(applied_damage, current_hp)
	current_hp = maxf(0.0, current_hp - applied_damage)
	if absorbed_damage + applied_damage > 0.0:
		last_damage_taken_time = session.elapsed_time
		_trigger_flash(damage_flash_color, damage_flash_duration, DAMAGE_FLASH_PRIORITY)
		_apply_damage_knockback(source, absorbed_damage + applied_damage)
	if applied_damage > 0.0:
		_remove_hp_damage_break_statuses()
	last_damage_source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	last_effect_id = effect_id
	session.record_event(
		CombatEvent.DAMAGE_APPLIED,
		last_damage_source_id,
		snapshot.runtime_id,
		ability_id,
		effect_id,
		applied_damage
	)
	if applied_damage > 0.0 and is_instance_valid(source) and source != self:
		if allow_source_lifesteal:
			source.apply_all_damage_lifesteal(applied_damage)
		if source.snapshot.team != snapshot.team:
			source.record_enemy_damage_dealt()
			if ability_id == &"attack.basic":
				_gain_gluttony_regeneration_stack()
				_reflect_basic_attack_damage(source, applied_damage)
	queue_redraw()
	if applied_damage > 0.0 and is_melee and is_instance_valid(source) and source.snapshot.team != snapshot.team:
		_try_melee_teleport(source)
		if melee_retaliation_multiplier > 0.0:
			session.trigger_melee_retaliation(self, source, melee_retaliation_radius, melee_retaliation_multiplier, melee_retaliation_ability_id, melee_retaliation_effect_id)
		if source.is_targetable() and snapshot.avoids_damage and snapshot.attack_type == &"melee" and source.snapshot.attack_type == &"melee":
			_start_melee_retreat(source)
	if applied_damage > 0.0 and current_hp > 0.0:
		_try_threshold_guard()
	if current_hp > 0.0:
		_update_boss_phase()
	if current_hp <= 0.0:
		var duration: float = session.get_last_stand_duration(self)
		if duration > 0.0:
			last_stand_remaining = duration
			target = null
			state = State.ACQUIRE_TARGET
		else:
			_die(source)
	return applied_damage


func receive_healing(
	amount: float,
	source: Combatant,
	ability_id: StringName,
	effect_id: StringName
) -> float:
	if not is_targetable():
		return 0.0
	var missing_health := maxf(0.0, get_effective_stat(&"max_hp") - current_hp)
	var applied_healing := minf(maxf(amount, 0.0), missing_health)
	current_hp += applied_healing
	if applied_healing > 0.0:
		_trigger_flash(healing_flash_color, healing_flash_duration, HEALING_FLASH_PRIORITY)
	session.record_event(
		CombatEvent.HEALING_APPLIED,
		source.snapshot.runtime_id if is_instance_valid(source) else "",
		snapshot.runtime_id,
		ability_id,
		effect_id,
		applied_healing
	)
	queue_redraw()
	return applied_healing


func _trigger_flash(color: Color, duration: float, priority: int) -> void:
	var requested_duration := maxf(duration, 0.0)
	if requested_duration <= 0.0 or (flash_remaining > 0.0 and priority < flash_priority):
		return
	flash_color = color
	flash_color.a = 1.0
	flash_remaining = requested_duration
	flash_priority = priority
	queue_redraw()


func _update_flash(delta: float) -> void:
	if flash_remaining <= 0.0:
		return
	flash_remaining = maxf(0.0, flash_remaining - delta)
	if flash_remaining <= 0.0:
		flash_priority = 0
	queue_redraw()


## Distance a hit of the given size pushes this unit: heavy blows relative to the
## unit's Max HP shove it far, chip damage barely moves it.
func damage_knockback_for(damage: float) -> float:
	var max_hp := maxf(get_effective_stat(&"max_hp"), 1.0)
	var share_percent := maxf(damage, 0.0) / max_hp * 100.0
	return minf(damage_knockback_distance * share_percent / damage_knockback_reference_percent, damage_knockback_max_distance)


func _apply_damage_knockback(source: Combatant, damage: float) -> void:
	if damage_knockback_distance <= 0.0 or not is_instance_valid(source) or source == self:
		return
	var distance := damage_knockback_for(damage)
	if distance < 0.5:
		return
	var direction := (position - source.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT if snapshot.runtime_id > source.snapshot.runtime_id else Vector2.LEFT
	position += direction * distance
	var bounds := arena_bounds.grow(-body_radius)
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)


func is_alive() -> bool:
	return not temporarily_removed and state != State.DEAD and (current_hp > 0.0 or last_stand_remaining > 0.0)


func is_targetable() -> bool:
	return not temporarily_removed and state != State.DEAD and current_hp > 0.0


func can_be_targeted_by(requester: Combatant) -> bool:
	if not is_targetable():
		return false
	if despair_sanctuary_remaining > 0.0 and is_instance_valid(requester) and requester.snapshot.team != snapshot.team:
		return false
	return stealth_remaining <= 0.0 or not is_instance_valid(requester) or requester.snapshot.team == snapshot.team


func can_receive_effect_from(source: Combatant) -> bool:
	return is_targetable() and not (despair_sanctuary_remaining > 0.0 and is_instance_valid(source) and source.snapshot.team != snapshot.team)


func apply_stealth(duration: float, ability_id: StringName = &"", effect_id: StringName = &"") -> void:
	stealth_remaining = maxf(stealth_remaining, duration)
	stealth_ability_id = ability_id
	stealth_effect_id = effect_id
	target = null
	queue_redraw()


func set_simulation_active(value: bool) -> void:
	simulation_active = value and not temporarily_removed
	if not value:
		velocity = Vector2.ZERO


func set_temporarily_removed(value: bool) -> void:
	temporarily_removed = value
	visible = not value
	velocity = Vector2.ZERO
	target = null
	pending_ability = null
	basic_attack_target_active = false
	state_timer = 0.0
	if value:
		simulation_active = false
	else:
		state = State.ACQUIRE_TARGET
		simulation_active = session != null and session.battle_active


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func get_effective_stat(stat: StringName) -> float:
	return _calculate_effective_stat(stat)


func get_stat_breakdown(stat: StringName) -> Dictionary:
	var entries := snapshot.stats.breakdown_for(stat)
	var snapshot_value := float(snapshot.stats.get(stat))
	if entries.is_empty():
		entries.append({"source": "Snapshot base", "operation": &"base", "operand": snapshot_value, "before": 0.0, "after": snapshot_value})
	elif not is_equal_approx(float(entries[-1].after), snapshot_value):
		entries.append({"source": "Combat stat changes", "operation": &"set", "operand": snapshot_value, "before": float(entries[-1].after), "after": snapshot_value})
	return {"value": _calculate_effective_stat(stat, entries), "entries": entries}


func _calculate_effective_stat(stat: StringName, entries = null) -> float:
	var value := float(snapshot.stats.get(stat))
	if stat == &"attack_range":
		var before := value
		value += basic_attack_range_bonus
		_record_stat_step(entries, "Ability: attack range bonus", &"add", basic_attack_range_bonus, before, value)
	for status in statuses:
		for modifier in status.definition.stat_modifiers:
			if StringName(modifier.stat) == stat:
				var before := value
				value = _apply_modifier(value, modifier, status.stacks)
				var operand := pow(modifier.value, status.stacks) if modifier.operation == StatModifier.Operation.MULTIPLY else modifier.value * status.stacks
				_record_stat_step(entries, "Status: %s%s" % [status.definition.display_name, " x%d" % status.stacks if status.stacks > 1 else ""], &"multiply" if modifier.operation == StatModifier.Operation.MULTIPLY else &"add", operand, before, value)
	for entry in temporary_modifiers:
		if StringName(entry.modifier.stat) == stat:
			var before := value
			value = _apply_modifier(value, entry.modifier, 1)
			_record_stat_step(entries, _ability_source_name(entry.ability_id, "Temporary modifier"), &"multiply" if entry.modifier.operation == StatModifier.Operation.MULTIPLY else &"add", entry.modifier.value, before, value)
	if snapshot.is_boss and boss_phase > 1:
		if stat == &"damage":
			var multiplier := pow(snapshot.boss_phase_damage_multiplier, boss_phase - 1)
			var before := value
			value *= multiplier
			_record_stat_step(entries, "Boss phase %d" % boss_phase, &"multiply", multiplier, before, value)
		elif stat == &"attack_speed":
			var multiplier := pow(snapshot.boss_phase_attack_speed_multiplier, boss_phase - 1)
			var before := value
			value *= multiplier
			_record_stat_step(entries, "Boss phase %d" % boss_phase, &"multiply", multiplier, before, value)
	if stat == &"attack_speed" and session != null:
		var multiplier: float = session.get_enemy_attack_speed_aura_multiplier(self)
		var before := value
		value *= multiplier
		_record_stat_step(entries, "Enemy attack-speed aura", &"multiply", multiplier, before, value)
		multiplier = session.get_lust_target_attack_speed_multiplier(self)
		before = value
		value *= multiplier
		_record_stat_step(entries, "Ability: Beguiling Presence", &"multiply", multiplier, before, value)
		if frenzy_remaining > 0.0:
			before = value
			value *= frenzy_attack_speed_multiplier
			_record_stat_step(entries, _ability_source_name(frenzy_ability_id, "Frenzy"), &"multiply", frenzy_attack_speed_multiplier, before, value)
		if despair_slow_stacks > 0:
			multiplier = 1.0 - despair_slow_applied_percent / 100.0
			before = value
			value *= multiplier
			_record_stat_step(entries, _ability_source_name(despair_slow_ability_id, "Despair slow"), &"multiply", multiplier, before, value)
	if stat == &"damage" and envy_strongest_ally_damage_percent > 0.0 and session != null:
		var bonus: float = session.get_strongest_non_hero_ally_damage(self) * envy_strongest_ally_damage_percent / 100.0
		var before := value
		value += bonus
		_record_stat_step(entries, "Ability: Borrowed Might", &"add", bonus, before, value)
	if stat in [&"max_hp", &"damage", &"armor"] and lust_death_scaling_percent > 0.0 and session != null:
		var multiplier: float = 1.0 + session.get_lust_allied_death_count(self) * lust_death_scaling_percent / 100.0
		var before := value
		value *= multiplier
		_record_stat_step(entries, _ability_source_name(lust_death_scaling_ability_id, "Fallen Devotion"), &"multiply", multiplier, before, value)
	if stat == &"attack_speed" and is_instance_valid(lust_bond_partner):
		var before := value
		value *= lust_bond_attack_speed_multiplier
		_record_stat_step(entries, _ability_source_name(lust_bond_ability_id, "Fatal Bond"), &"multiply", lust_bond_attack_speed_multiplier, before, value)
	if stat == nearby_ally_bonus_stat and nearby_ally_bonus_value > 0.0:
		var allies := nearby_same_job_allies()
		if allies > 0:
			var before := value
			value += nearby_ally_bonus_value * allies
			_record_stat_step(entries, "%s (%d nearby)" % [_ability_source_name(nearby_ally_bonus_ability_id, "Nearby allies"), allies], &"add", nearby_ally_bonus_value * allies, before, value)
	if despair_growth_bonus_percent.has(stat):
		var multiplier := 1.0 + float(despair_growth_bonus_percent[stat]) / 100.0
		var before := value
		value *= multiplier
		_record_stat_step(entries, _ability_source_name(despair_growth_ability_id, "Endless Descent"), &"multiply", multiplier, before, value)
	return maxf(value, 0.0)


func _record_stat_step(entries, source: String, operation: StringName, operand: float, before: float, after: float) -> void:
	if entries == null or is_equal_approx(before, after):
		return
	entries.append({"source": source, "operation": operation, "operand": operand, "before": before, "after": after})


func _ability_source_name(ability_id: StringName, fallback: String) -> String:
	if not String(ability_id).is_empty() and session != null:
		var ability: AbilityDefinition = session.get_ability_definition(ability_id)
		if ability != null:
			return "Ability: %s" % ability.display_name
	return fallback


func get_damage_multiplier() -> float:
	return get_effective_stat(&"damage") / maxf(snapshot.stats.damage, 0.01)


func add_temporary_modifier(
	modifier: StatModifier,
	duration: float,
	source,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	temporary_modifiers.append({
		"modifier": modifier,
		"remaining": duration if duration > 0.0 else -1.0,
		"source_id": source.snapshot.runtime_id if is_instance_valid(source) else "",
		"ability_id": ability_id,
		"effect_id": effect_id,
	})
	_clamp_current_hp_to_max()


func _clamp_current_hp_to_max() -> void:
	current_hp = minf(current_hp, get_effective_stat(&"max_hp"))
	queue_redraw()


func apply_envy_dart_slow(slow_percent: float, source: Combatant, ability_id: StringName, effect_id: StringName) -> void:
	if envy_dart_slow_applied:
		return
	var slow := StatModifier.new()
	slow.stat = "movement_speed"
	slow.operation = StatModifier.Operation.MULTIPLY
	slow.value = 1.0 - clampf(slow_percent, 0.0, 100.0) / 100.0
	add_temporary_modifier(slow, 0.0, source, ability_id, effect_id)
	envy_dart_slow_applied = true


func apply_envy_dart_poison(damage: float, slow_percent: float, source: Combatant, ability_id: StringName, effect_id: StringName) -> void:
	var poison := StatusDefinition.new()
	poison.id = &"status.envy_dart_poison"
	poison.display_name = "Jealous Poison"
	poison.description = "Deals %.1f damage every second until battle end." % damage
	poison.default_duration = 0.0
	poison.max_stacks = 1
	poison.stack_policy = StatusDefinition.StackPolicy.REFRESH_DURATION
	poison.periodic_interval = 1.0
	poison.polarity = StatusDefinition.Polarity.NEGATIVE
	var tick := DamageEffect.new()
	tick.effect_id = effect_id
	tick.amount = damage
	poison.periodic_effects.append(tick)
	apply_status(poison, source, ability_id)
	apply_envy_dart_slow(slow_percent, source, ability_id, effect_id)


func add_basic_attack_empowerment(
	lifesteal_percent: float,
	size_multiplier: float,
	duration: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	basic_attack_empowerments.append({
		"lifesteal_percent": maxf(lifesteal_percent, 0.0),
		"size_multiplier": maxf(size_multiplier, 0.01),
		"remaining": duration if duration > 0.0 else -1.0,
		"ability_id": ability_id,
		"effect_id": effect_id,
	})
	_refresh_body_radius()


func apply_basic_attack_lifesteal(damage_dealt: float) -> float:
	if damage_dealt <= 0.0:
		return 0.0
	var percent := 0.0
	for empowerment in basic_attack_empowerments:
		percent += float(empowerment.lifesteal_percent)
	var aura: Dictionary = session.get_gluttony_lifesteal_aura(self)
	percent += float(aura.get("percent", 0.0))
	percent += passive_basic_lifesteal_percent
	if percent <= 0.0:
		return 0.0
	var ability_id := StringName(aura.get("ability_id", &""))
	var effect_id := StringName(aura.get("effect_id", &""))
	if passive_basic_lifesteal_percent > 0.0 and String(ability_id).is_empty():
		ability_id = passive_basic_lifesteal_ability_id
		effect_id = passive_basic_lifesteal_effect_id
	if not basic_attack_empowerments.is_empty():
		ability_id = StringName(basic_attack_empowerments[0].ability_id)
		effect_id = StringName(basic_attack_empowerments[0].effect_id)
	return receive_healing(
		damage_dealt * percent / 100.0,
		self,
		ability_id,
		effect_id
	)


func set_gluttony_lifesteal_aura(radius: float, percent: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_lifesteal_aura_radius = radius
	gluttony_lifesteal_percent = percent
	gluttony_lifesteal_ability_id = ability_id
	gluttony_lifesteal_effect_id = effect_id


func set_gluttony_regeneration(max_stacks: int, percent_per_stack: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_regeneration_max_stacks = max_stacks
	gluttony_regeneration_percent_per_stack = percent_per_stack
	gluttony_regeneration_ability_id = ability_id
	gluttony_regeneration_effect_id = effect_id


func _gain_gluttony_regeneration_stack() -> void:
	if gluttony_regeneration_max_stacks <= 0 or gluttony_regeneration_stacks >= gluttony_regeneration_max_stacks:
		return
	if gluttony_regeneration_stacks == 0:
		gluttony_regeneration_tick_remaining = 1.0
	gluttony_regeneration_stacks += 1


func gluttony_regeneration_per_second() -> float:
	return get_effective_stat(&"max_hp") * gluttony_regeneration_percent_per_stack * gluttony_regeneration_stacks / 100.0


func set_gluttony_damage_aura(radius: float, damage: float, interval: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_damage_aura_radius = radius
	gluttony_damage_aura_damage = damage
	gluttony_damage_aura_interval = interval
	gluttony_damage_aura_tick_remaining = interval
	gluttony_damage_aura_ability_id = ability_id
	gluttony_damage_aura_effect_id = effect_id


func set_gluttony_death_explosion(radius: float, damage: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_death_explosion_radius = radius
	gluttony_death_explosion_damage = damage
	gluttony_death_explosion_ability_id = ability_id
	gluttony_death_explosion_effect_id = effect_id


func set_despair_team_proc(chance_percent: float, total_damage_percent: float, ability_id: StringName, effect_id: StringName) -> void:
	despair_team_proc_chance_percent = clampf(chance_percent, 0.0, 100.0)
	despair_team_proc_total_damage_percent = maxf(total_damage_percent, 100.0)
	despair_team_proc_ability_id = ability_id
	despair_team_proc_effect_id = effect_id


func set_despair_attack_slow(max_stacks: int, percent_per_stack: float, maximum_percent: float, ability_id: StringName, effect_id: StringName) -> void:
	despair_attack_slow_max_stacks = maxi(max_stacks, 1)
	despair_attack_slow_percent_per_stack = maxf(percent_per_stack, 0.0)
	despair_attack_slow_maximum_percent = clampf(maximum_percent, 0.0, 80.0)
	despair_slow_ability_id = ability_id
	despair_slow_effect_id = effect_id


func apply_despair_attack_slow(max_stacks: int, percent_per_stack: float, maximum_percent: float) -> void:
	despair_slow_max_stacks = maxi(despair_slow_max_stacks, max_stacks)
	despair_slow_percent_per_stack = maxf(despair_slow_percent_per_stack, percent_per_stack)
	despair_slow_maximum_percent = maxf(despair_slow_maximum_percent, clampf(maximum_percent, 0.0, 80.0))
	despair_slow_stacks = mini(despair_slow_stacks + 1, despair_slow_max_stacks)
	despair_slow_applied_percent = minf(despair_slow_stacks * despair_slow_percent_per_stack, despair_slow_maximum_percent)


func apply_despair_sanctuary(source: Combatant, heal_percent: float, duration: float, interval: float, ability_id: StringName, effect_id: StringName) -> void:
	despair_sanctuary_remaining = maxf(duration, 0.0)
	despair_sanctuary_heal_percent = maxf(heal_percent, 0.0)
	despair_sanctuary_interval = maxf(interval, 0.01)
	despair_sanctuary_tick_remaining = despair_sanctuary_interval
	despair_sanctuary_source = source
	despair_sanctuary_ability_id = ability_id
	despair_sanctuary_effect_id = effect_id
	clear_combat_action()


func set_despair_growth(
	max_hp_rate: float,
	damage_rate: float,
	armor_rate: float,
	movement_speed_rate: float,
	attack_speed_rate: float,
	maximum_percent: float,
	interval: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	despair_growth_rates = {
		&"max_hp": maxf(max_hp_rate, 0.0),
		&"damage": maxf(damage_rate, 0.0),
		&"armor": maxf(armor_rate, 0.0),
		&"movement_speed": maxf(movement_speed_rate, 0.0),
		&"attack_speed": maxf(attack_speed_rate, 0.0),
	}
	despair_growth_bonus_percent = {&"max_hp": 0.0, &"damage": 0.0, &"armor": 0.0, &"movement_speed": 0.0, &"attack_speed": 0.0}
	despair_growth_maximum_percent = maxf(maximum_percent, 0.0)
	despair_growth_interval = maxf(interval, 0.01)
	despair_growth_tick_remaining = despair_growth_interval
	despair_growth_ability_id = ability_id
	despair_growth_effect_id = effect_id


func apply_gluttony_grease(miss_percent: float, duration: float, source: Combatant, ability_id: StringName) -> void:
	gluttony_grease_miss_percent = clampf(miss_percent, 0.0, 100.0)
	var grease := StatusDefinition.new()
	grease.id = &"status.gluttony_grease"
	grease.display_name = "Greased"
	grease.description = "Basic attacks have a %.0f%% chance to miss." % gluttony_grease_miss_percent
	grease.default_duration = duration
	grease.max_stacks = 1
	grease.stack_policy = StatusDefinition.StackPolicy.REFRESH_DURATION
	grease.polarity = StatusDefinition.Polarity.NEGATIVE
	apply_status(grease, source, ability_id)


func get_gluttony_grease_miss_chance() -> float:
	return gluttony_grease_miss_percent / 100.0 if has_status(&"status.gluttony_grease") else 0.0


func apply_all_damage_lifesteal(damage_dealt: float) -> float:
	if damage_dealt <= 0.0 or lust_bond_lifesteal_percent <= 0.0 or not is_instance_valid(lust_bond_partner):
		return 0.0
	return receive_healing(damage_dealt * lust_bond_lifesteal_percent / 100.0, self, lust_bond_ability_id, lust_bond_effect_id)


func add_runtime_status(name: String, details: String, polarity: String, duration: float, ability_id: StringName = &"") -> void:
	runtime_status_metadata.append({
		"name": name,
		"details": details,
		"polarity": polarity,
		"remaining": duration if duration > 0.0 else -1.0,
		"ability_id": ability_id,
	})


func set_forced_basic_target(value: Combatant, duration: float, ability_id: StringName) -> void:
	forced_basic_target = value
	forced_basic_target_remaining = maxf(duration, 0.0)
	pending_ability = null
	target = value
	basic_attack_target_active = true
	state_timer = 0.0
	state = State.ACQUIRE_TARGET
	add_runtime_status("Taunted", "Basic attacks are forced toward %s." % value.snapshot.display_name, "DEBUFF", duration, ability_id)


func clear_combat_action() -> void:
	forced_basic_target = null
	forced_basic_target_remaining = 0.0
	_remove_runtime_status("Taunted")
	pending_ability = null
	target = null
	basic_attack_target_active = false
	velocity = Vector2.ZERO
	state_timer = 0.0
	state = State.ACQUIRE_TARGET


func _remove_runtime_status(status_name: String) -> void:
	for index in range(runtime_status_metadata.size() - 1, -1, -1):
		if String(runtime_status_metadata[index].name) == status_name:
			runtime_status_metadata.remove_at(index)


func set_lust_death_scaling(percent_per_death: float, ability_id: StringName) -> void:
	lust_death_scaling_percent = percent_per_death
	lust_death_scaling_ability_id = ability_id


func set_lust_target_slow(slow_percent: float, ability_id: StringName) -> void:
	lust_target_slow_percent = slow_percent
	lust_target_slow_ability_id = ability_id


func prepare_lust_bond(lifesteal_percent: float, attack_speed_multiplier: float, ability_id: StringName, effect_id: StringName) -> void:
	lust_bond_pending = true
	lust_bond_lifesteal_percent = lifesteal_percent
	lust_bond_attack_speed_multiplier = attack_speed_multiplier
	lust_bond_ability_id = ability_id
	lust_bond_effect_id = effect_id


func establish_lust_bond(partner: Combatant) -> void:
	if not is_instance_valid(partner) or partner == self:
		return
	lust_bond_pending = false
	lust_bond_partner = partner
	partner.lust_bond_partner = self
	partner.lust_bond_lifesteal_percent = lust_bond_lifesteal_percent
	partner.lust_bond_attack_speed_multiplier = lust_bond_attack_speed_multiplier
	partner.lust_bond_ability_id = lust_bond_ability_id
	partner.lust_bond_effect_id = lust_bond_effect_id


func set_lust_basic_knockback(hits_required: int, knockback_distance: float, stun_duration: float, ability_id: StringName, effect_id: StringName) -> void:
	lust_basic_hits_required = hits_required
	lust_basic_hit_count = 0
	lust_basic_knockback_distance = knockback_distance
	lust_basic_stun_duration = stun_duration
	lust_basic_ability_id = ability_id
	lust_basic_effect_id = effect_id


func add_passive_basic_lifesteal(percent: float, ability_id: StringName, effect_id: StringName) -> void:
	passive_basic_lifesteal_percent += percent
	passive_basic_lifesteal_ability_id = ability_id
	passive_basic_lifesteal_effect_id = effect_id


func add_on_hit_status(status: StatusDefinition, ability_id: StringName) -> void:
	on_hit_statuses.append({"status": status, "ability_id": ability_id})


func set_nearby_ally_stat_bonus(stat: StringName, value_per_ally: float, radius: float, max_allies: int, ability_id: StringName) -> void:
	nearby_ally_bonus_stat = stat
	nearby_ally_bonus_value = value_per_ally
	nearby_ally_bonus_radius = radius
	nearby_ally_bonus_max = max_allies
	nearby_ally_bonus_ability_id = ability_id


## Living allies of the same Job within the Strength in Numbers radius (capped).
func nearby_same_job_allies() -> int:
	if session == null or nearby_ally_bonus_max <= 0 or String(snapshot.job_id).is_empty():
		return 0
	var count := 0
	for other in session.combatants:
		if other == self or not other.is_alive() or other.snapshot.team != snapshot.team or other.snapshot.job_id != snapshot.job_id:
			continue
		if other.position.distance_to(position) <= nearby_ally_bonus_radius:
			count += 1
			if count >= nearby_ally_bonus_max:
				break
	return count


func record_successful_basic_hit(hit_target: Combatant, damage_dealt: float) -> void:
	if damage_dealt <= 0.0 or not is_instance_valid(hit_target):
		return
	for entry in on_hit_statuses:
		if hit_target.is_alive():
			hit_target.apply_status(entry.status, self, entry.ability_id)
	if despair_attack_slow_max_stacks > 0:
		hit_target.apply_despair_attack_slow(despair_attack_slow_max_stacks, despair_attack_slow_percent_per_stack, despair_attack_slow_maximum_percent)
	if lust_basic_hits_required <= 0:
		return
	lust_basic_hit_count += 1
	if lust_basic_hit_count < lust_basic_hits_required:
		return
	lust_basic_hit_count = 0
	session.apply_lust_basic_knockback(self, hit_target, lust_basic_knockback_distance, lust_basic_stun_duration, lust_basic_ability_id, lust_basic_effect_id)


func _has_forced_basic_target() -> bool:
	return forced_basic_target_remaining > 0.0 and is_instance_valid(forced_basic_target) and forced_basic_target.is_targetable() and forced_basic_target.snapshot.team != snapshot.team


func add_shield(
	amount: float,
	duration: float,
	source,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	if amount > 0.0:
		shields.append({
			"amount": amount,
			"remaining": duration if duration > 0.0 else -1.0,
			"source_id": source.snapshot.runtime_id if is_instance_valid(source) else "",
			"ability_id": ability_id,
			"effect_id": effect_id,
		})


func set_melee_retaliation(radius: float, multiplier: float, ability_id: StringName, effect_id: StringName) -> void:
	melee_retaliation_radius = maxf(radius, 0.0)
	melee_retaliation_multiplier = maxf(multiplier, 0.0)
	melee_retaliation_ability_id = ability_id
	melee_retaliation_effect_id = effect_id


func set_attack_reflection(percent: float, ability_id: StringName, effect_id: StringName) -> void:
	attack_reflect_percent = maxf(percent, 0.0)
	attack_reflect_ability_id = ability_id
	attack_reflect_effect_id = effect_id


func _reflect_basic_attack_damage(attacker: Combatant, applied_damage: float) -> void:
	if attack_reflect_percent <= 0.0 or applied_damage <= 0.0 or not attacker.is_targetable():
		return
	attacker.take_damage(
		applied_damage * attack_reflect_percent / 100.0,
		self,
		attack_reflect_ability_id,
		attack_reflect_effect_id,
		false,
		false
	)


func set_focused_damage(damage_per_stack: float, duration: float, _ability_id: StringName, _effect_id: StringName) -> void:
	focused_damage_per_stack = maxf(damage_per_stack, 0.0)
	focused_stack_duration = maxf(duration, 0.0)


func apply_frenzy(attack_speed_multiplier: float, duration: float, ability_id: StringName, effect_id: StringName) -> void:
	frenzy_attack_speed_multiplier = maxf(attack_speed_multiplier, 0.01)
	frenzy_remaining = maxf(frenzy_remaining, duration)
	frenzy_ability_id = ability_id
	frenzy_effect_id = effect_id
	frenzy_direction_timer = 0.0
	first_enemy_damage_time = -1.0
	target = null
	pending_ability = null
	state = State.ACQUIRE_TARGET


func record_enemy_damage_dealt() -> void:
	if first_enemy_damage_time < 0.0:
		first_enemy_damage_time = session.elapsed_time


func can_activate_frenzy() -> bool:
	return first_enemy_damage_time >= 0.0 and session.elapsed_time - first_enemy_damage_time >= FRENZY_ACTIVATION_DELAY


func set_threshold_guard(
	health_ratio: float,
	shield_multiplier: float,
	armor_multiplier: float,
	duration: float,
	cooldown: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	threshold_guard_health_ratio = clampf(health_ratio, 0.0, 1.0)
	threshold_guard_shield_multiplier = maxf(shield_multiplier, 0.0)
	threshold_guard_armor_multiplier = maxf(armor_multiplier, 0.01)
	threshold_guard_duration = maxf(duration, 0.0)
	threshold_guard_cooldown = maxf(cooldown, 0.0)
	threshold_guard_ability_id = ability_id
	threshold_guard_effect_id = effect_id


func prepare_ground_slam(multiplier: float, radius: float, ability_id: StringName, effect_id: StringName) -> void:
	ground_slam_damage_multiplier = maxf(multiplier, 0.0)
	ground_slam_radius = maxf(radius, 0.0)
	ground_slam_ability_id = ability_id
	ground_slam_effect_id = effect_id


func apply_status(definition: StatusDefinition, source: Combatant, ability_id: StringName) -> void:
	if definition.polarity == StatusDefinition.Polarity.NEGATIVE and has_negative_status_immunity():
		return
	for status in statuses:
		if status.definition.id == definition.id:
			status.refresh(source, ability_id)
			session.record_status_applied(source, self, ability_id, definition.id)
			return
	var instance := StatusInstance.new()
	instance.setup(definition, source, ability_id)
	statuses.append(instance)
	session.record_status_applied(source, self, ability_id, definition.id)


func _remove_hp_damage_break_statuses() -> void:
	for index in range(statuses.size() - 1, -1, -1):
		if statuses[index].definition != null and statuses[index].definition.breaks_on_hp_damage:
			statuses.remove_at(index)


func has_negative_status() -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.polarity == StatusDefinition.Polarity.NEGATIVE
	)


func has_negative_status_immunity() -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.grants_negative_status_immunity
	)


func has_status(status_id: StringName) -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.id == status_id
	)


func remove_random_negative_status(_source: Combatant, _ability_id: StringName, _effect_id: StringName) -> bool:
	var candidates: Array[int] = []
	for index in statuses.size():
		if statuses[index].definition != null and statuses[index].definition.polarity == StatusDefinition.Polarity.NEGATIVE:
			candidates.append(index)
	if candidates.is_empty():
		return false
	var selected_index := candidates[session.combat_rng.randi_range(0, candidates.size() - 1)]
	statuses.remove_at(selected_index)
	return true


func is_stunned() -> bool:
	if despair_sanctuary_remaining > 0.0:
		return true
	for status in statuses:
		if status.definition.prevents_actions:
			return true
	return false


func is_rooted() -> bool:
	for status in statuses:
		if status.definition != null and status.definition.prevents_movement:
			return true
	return false


func get_debug_text() -> String:
	var target_id := "none"
	if is_instance_valid(target):
		target_id = target.snapshot.runtime_id
	var cooldown := state_timer if state == State.ATTACK_RECOVERY else 0.0
	return "ID: %s\nTeam: %s\nState: %s\nTarget: %s\nHP: %.1f / %.1f\nCooldown: %.2f s\nStatuses: %d%s" % [
		snapshot.runtime_id,
		"PLAYER" if snapshot.team == CombatUnitSnapshot.Team.PLAYER else "ENEMY",
		State.keys()[state],
		target_id,
		current_hp,
		get_effective_stat(&"max_hp"),
		cooldown,
		statuses.size(),
		"\nBoss phase: %d / %d" % [boss_phase, snapshot.boss_phase_count] if snapshot.is_boss else "",
	]


func _die(source: Combatant) -> void:
	if state == State.DEAD:
		return
	last_stand_remaining = 0.0
	state = State.DEAD
	simulation_active = false
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	queue_redraw()
	if is_instance_valid(source) and source.snapshot.team != snapshot.team:
		session.grant_kill_reward(source)
	session.record_event(
		CombatEvent.UNIT_DIED,
		source.snapshot.runtime_id if is_instance_valid(source) else last_damage_source_id,
		snapshot.runtime_id,
		&"",
		last_effect_id
	)
	if not gluttony_death_explosion_triggered and gluttony_death_explosion_damage > 0.0:
		gluttony_death_explosion_triggered = true
		session.damage_enemies_in_radius(self, gluttony_death_explosion_radius, gluttony_death_explosion_damage, gluttony_death_explosion_ability_id, gluttony_death_explosion_effect_id, false)
	session.notify_combatant_died(self, source)


func force_die(source: Combatant, effect_id: StringName) -> void:
	last_effect_id = effect_id
	current_hp = 0.0
	_die(source)


func _has_valid_target() -> bool:
	if not is_instance_valid(target):
		return false
	if pending_ability != null and target.snapshot.team == snapshot.team:
		return target.is_targetable()
	if frenzy_remaining > 0.0:
		return target.is_targetable() and target != self
	return target.can_be_targeted_by(self) and target.snapshot.team != snapshot.team


func _try_use_ability() -> bool:
	for ability in snapshot.abilities:
		if ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
			continue
		if _try_activate_ability(ability, false):
			return true
	return false


func _try_use_priority_summon() -> bool:
	for ability in snapshot.abilities:
		if not _is_summon_ability(ability):
			continue
		if _try_activate_ability(ability, true):
			return true
	return false


func _try_activate_ability(ability: AbilityDefinition, interrupt_current_action: bool) -> bool:
	if ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
		return false
	if float(ability_cooldowns.get(ability.id, 0.0)) > 0.0:
		return false
	if ability.required_recent_damage_seconds > 0.0 and (
		last_damage_taken_time < 0.0
		or session.elapsed_time - last_damage_taken_time > ability.required_recent_damage_seconds
	):
		return false
	var ability_target: Combatant = session.resolve_ability_target(self, ability)
	if not is_instance_valid(ability_target) or not session.can_use_ability(self, ability_target, ability):
		return false
	basic_attack_target_active = false
	if interrupt_current_action:
		pending_ability = null
		target = null
		velocity = Vector2.ZERO
		state_timer = 0.0
		windup_duration = 0.0
		queue_redraw()
	var outside_cast_range := ability.cast_range > 0.0 and position.distance_to(ability_target.position) > ability.cast_range
	if outside_cast_range or ability.delivery_method == AbilityDefinition.DeliveryMethod.MELEE_HIT or (snapshot.is_boss and not _is_summon_ability(ability)):
		pending_ability = ability
		target = ability_target
		basic_attack_target_active = false
		state = State.MOVE_INTO_RANGE
	else:
		ability_cooldowns[ability.id] = ability.cooldown_seconds
		session.deliver_ability(self, ability_target, ability)
		state = State.ACQUIRE_TARGET
	return true


func _ready_basic_replacement() -> AbilityDefinition:
	for ability in snapshot.abilities:
		if (
			ability.kind == AbilityDefinition.AbilityKind.ACTIVE
			and ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK
			and float(ability_cooldowns.get(ability.id, 0.0)) <= 0.0
			and session.can_use_ability(self, target, ability)
		):
			return ability
	return null


func _is_summon_ability(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect is SummonEffect or effect is SummonMergeEffect:
			return true
	return false


func _apply_passive_abilities() -> void:
	for ability in snapshot.abilities:
		if ability.kind != AbilityDefinition.AbilityKind.PASSIVE:
			continue
		for effect in ability.effects:
			effect.apply(self, self, ability)


func _update_runtime(delta: float) -> void:
	if forced_basic_target_remaining > 0.0:
		forced_basic_target_remaining = maxf(0.0, forced_basic_target_remaining - delta)
		if not _has_forced_basic_target():
			forced_basic_target = null
			_remove_runtime_status("Taunted")
			target = null
			basic_attack_target_active = false
			pending_ability = null
			state = State.ACQUIRE_TARGET
	for index in range(runtime_status_metadata.size() - 1, -1, -1):
		if float(runtime_status_metadata[index].remaining) < 0.0:
			continue
		runtime_status_metadata[index].remaining = float(runtime_status_metadata[index].remaining) - delta
		if float(runtime_status_metadata[index].remaining) <= 0.0:
			runtime_status_metadata.remove_at(index)
	if frenzy_remaining > 0.0:
		frenzy_remaining = maxf(0.0, frenzy_remaining - delta)
		if frenzy_remaining <= 0.0:
			target = null
			state = State.ACQUIRE_TARGET
	if stealth_remaining > 0.0:
		stealth_remaining = maxf(0.0, stealth_remaining - delta)
		if stealth_remaining <= 0.0:
			queue_redraw()
	if last_stand_remaining > 0.0:
		last_stand_remaining = maxf(0.0, last_stand_remaining - delta)
		if last_stand_remaining <= 0.0:
			_die(null)
			return
	if melee_teleport_cooldown_remaining > 0.0:
		melee_teleport_cooldown_remaining = maxf(0.0, melee_teleport_cooldown_remaining - delta)
	if threshold_guard_cooldown_remaining > 0.0:
		threshold_guard_cooldown_remaining = maxf(0.0, threshold_guard_cooldown_remaining - delta)
	if phase_banner_timer > 0.0:
		phase_banner_timer = maxf(0.0, phase_banner_timer - delta)
		queue_redraw()
	for ability_id in ability_cooldowns:
		ability_cooldowns[ability_id] = maxf(0.0, float(ability_cooldowns[ability_id]) - delta)
	for index in range(statuses.size() - 1, -1, -1):
		if statuses[index].update(delta, self):
			statuses.remove_at(index)
	for index in range(temporary_modifiers.size() - 1, -1, -1):
		if float(temporary_modifiers[index].remaining) < 0.0:
			continue
		temporary_modifiers[index].remaining = float(temporary_modifiers[index].remaining) - delta
		if float(temporary_modifiers[index].remaining) <= 0.0:
			temporary_modifiers.remove_at(index)
			_clamp_current_hp_to_max()
	var body_radius_changed := false
	for index in range(basic_attack_empowerments.size() - 1, -1, -1):
		if float(basic_attack_empowerments[index].remaining) < 0.0:
			continue
		basic_attack_empowerments[index].remaining = float(basic_attack_empowerments[index].remaining) - delta
		if float(basic_attack_empowerments[index].remaining) <= 0.0:
			basic_attack_empowerments.remove_at(index)
			body_radius_changed = true
	if body_radius_changed:
		_refresh_body_radius()
	for index in range(shields.size() - 1, -1, -1):
		if float(shields[index].remaining) < 0.0:
			continue
		shields[index].remaining = float(shields[index].remaining) - delta
		if float(shields[index].remaining) <= 0.0:
			shields.remove_at(index)
	if gluttony_regeneration_stacks > 0 and is_alive():
		gluttony_regeneration_tick_remaining -= delta
		while gluttony_regeneration_tick_remaining <= 0.000001:
			gluttony_regeneration_tick_remaining += 1.0
			receive_healing(gluttony_regeneration_per_second(), self, gluttony_regeneration_ability_id, gluttony_regeneration_effect_id)
	if gluttony_damage_aura_interval > 0.0 and is_alive():
		gluttony_damage_aura_tick_remaining -= delta
		while gluttony_damage_aura_tick_remaining <= 0.000001:
			gluttony_damage_aura_tick_remaining += gluttony_damage_aura_interval
			session.damage_enemies_in_radius(self, gluttony_damage_aura_radius, gluttony_damage_aura_damage, gluttony_damage_aura_ability_id, gluttony_damage_aura_effect_id)
	if despair_sanctuary_remaining > 0.0:
		var sanctuary_delta := minf(delta, despair_sanctuary_remaining)
		despair_sanctuary_remaining = maxf(0.0, despair_sanctuary_remaining - delta)
		despair_sanctuary_tick_remaining -= sanctuary_delta
		while despair_sanctuary_tick_remaining <= 0.000001:
			despair_sanctuary_tick_remaining += despair_sanctuary_interval
			receive_healing(get_effective_stat(&"max_hp") * despair_sanctuary_heal_percent / 100.0, despair_sanctuary_source, despair_sanctuary_ability_id, despair_sanctuary_effect_id)
	if despair_growth_interval > 0.0 and is_alive():
		despair_growth_tick_remaining -= delta
		while despair_growth_tick_remaining <= 0.000001:
			despair_growth_tick_remaining += despair_growth_interval
			_apply_despair_growth_tick()
	_update_focused_damage_stacks(delta)


func _apply_despair_growth_tick() -> void:
	var old_max_hp := get_effective_stat(&"max_hp")
	var health_ratio := current_hp / maxf(old_max_hp, 0.01)
	for stat in despair_growth_rates:
		despair_growth_bonus_percent[stat] = minf(
			float(despair_growth_bonus_percent.get(stat, 0.0)) + float(despair_growth_rates[stat]) * despair_growth_interval,
			despair_growth_maximum_percent
		)
	current_hp = get_effective_stat(&"max_hp") * health_ratio
	queue_redraw()


func _start_melee_retreat(attacker: Combatant) -> void:
	var counterattack_in_progress := melee_retreat_remaining > 0.0 and state == State.ATTACK_WINDUP and pending_ability == null
	var attack_ready := state != State.ATTACK_WINDUP and (state != State.ATTACK_RECOVERY or state_timer <= 0.0)
	melee_retreat_remaining = 0.2
	melee_retreat_source = attacker
	melee_retreat_direction = (position - attacker.position).normalized()
	if melee_retreat_direction.is_zero_approx():
		melee_retreat_direction = Vector2.LEFT if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	if counterattack_in_progress:
		return
	pending_ability = null
	if state == State.ATTACK_WINDUP:
		state = State.ACQUIRE_TARGET
		state_timer = 0.0
	melee_retreat_counterattack_pending = melee_retreat_counterattack_pending or attack_ready


func _update_melee_retreat(delta: float) -> void:
	if state == State.ATTACK_WINDUP:
		_update_attack_windup(delta)
		return
	if state == State.ATTACK_RECOVERY:
		state_timer = maxf(0.0, state_timer - delta)
	if melee_retreat_counterattack_pending and is_instance_valid(melee_retreat_source) and melee_retreat_source.is_targetable():
		if position.distance_to(melee_retreat_source.position) <= basic_attack_reach(melee_retreat_source):
			target = melee_retreat_source
			melee_retreat_counterattack_pending = false
			_start_attack()
			return

	melee_retreat_remaining = maxf(0.0, melee_retreat_remaining - delta)
	if is_rooted():
		velocity = Vector2.ZERO
		return
	if is_instance_valid(melee_retreat_source):
		var away := (position - melee_retreat_source.position).normalized()
		if not away.is_zero_approx():
			melee_retreat_direction = away
	velocity = melee_retreat_direction * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	if melee_retreat_remaining > 0.0:
		return
	velocity = Vector2.ZERO
	melee_retreat_source = null
	melee_retreat_counterattack_pending = false
	target = null
	if state != State.ATTACK_RECOVERY or state_timer <= 0.0:
		state = State.ACQUIRE_TARGET


func _update_frenzy(delta: float) -> void:
	if state == State.ATTACK_WINDUP:
		_update_attack_windup(delta)
		return
	if state == State.ATTACK_RECOVERY:
		state_timer -= delta
		if state_timer > 0.0:
			velocity = Vector2.ZERO
			return
		state = State.ACQUIRE_TARGET

	var attack_target: Combatant = session.find_frenzy_attack_target(self)
	if is_instance_valid(attack_target):
		target = attack_target
		velocity = Vector2.ZERO
		_start_attack()
		return
	if is_rooted():
		velocity = Vector2.ZERO
		return

	frenzy_direction_timer -= delta
	if frenzy_direction_timer <= 0.0 or position.distance_to(frenzy_destination) <= body_radius:
		frenzy_destination = session.random_arena_point(self)
		frenzy_direction_timer = FRENZY_DIRECTION_INTERVAL
	var direction := (frenzy_destination - position).normalized()
	velocity = direction * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)


func _focused_damage_bonus(attack_target: Combatant) -> float:
	if focused_damage_per_stack <= 0.0 or not is_instance_valid(attack_target) or attack_target.snapshot.team == snapshot.team:
		return 0.0
	return focused_damage_per_stack * (focused_damage_stacks.get(attack_target.snapshot.runtime_id, []) as Array).size()


func _add_focused_damage_stack(attack_target: Combatant) -> void:
	if focused_damage_per_stack <= 0.0 or focused_stack_duration <= 0.0 or not is_instance_valid(attack_target) or attack_target.snapshot.team == snapshot.team:
		return
	var runtime_id := attack_target.snapshot.runtime_id
	var stacks: Array = focused_damage_stacks.get(runtime_id, [])
	stacks.append(focused_stack_duration)
	focused_damage_stacks[runtime_id] = stacks


func _update_focused_damage_stacks(delta: float) -> void:
	for runtime_id in focused_damage_stacks.keys():
		var stacks: Array = focused_damage_stacks[runtime_id]
		for index in range(stacks.size() - 1, -1, -1):
			stacks[index] = float(stacks[index]) - delta
			if float(stacks[index]) <= 0.0:
				stacks.remove_at(index)
		if stacks.is_empty():
			focused_damage_stacks.erase(runtime_id)
		else:
			focused_damage_stacks[runtime_id] = stacks


func _try_threshold_guard() -> void:
	if threshold_guard_health_ratio <= 0.0 or threshold_guard_cooldown_remaining > 0.0:
		return
	if current_hp / maxf(get_effective_stat(&"max_hp"), 1.0) > threshold_guard_health_ratio:
		return
	add_shield(get_effective_stat(&"max_hp") * threshold_guard_shield_multiplier, threshold_guard_duration, self, threshold_guard_ability_id, threshold_guard_effect_id)
	var armor_modifier := StatModifier.new()
	armor_modifier.stat = "armor"
	armor_modifier.operation = StatModifier.Operation.MULTIPLY
	armor_modifier.value = threshold_guard_armor_multiplier
	add_temporary_modifier(armor_modifier, threshold_guard_duration, self, threshold_guard_ability_id, threshold_guard_effect_id)
	threshold_guard_cooldown_remaining = threshold_guard_cooldown


func _try_melee_teleport(attacker: Combatant) -> void:
	if melee_teleport_distance <= 0.0 or melee_teleport_cooldown_remaining > 0.0:
		return
	var direction := (position - attacker.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.LEFT if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	var destination := position + direction * melee_teleport_distance
	var inset_bounds := arena_bounds.grow(-body_radius)
	position = Vector2(
		clampf(destination.x, inset_bounds.position.x, inset_bounds.end.x),
		clampf(destination.y, inset_bounds.position.y, inset_bounds.end.y)
	)
	melee_teleport_cooldown_remaining = melee_teleport_cooldown
	pending_ability = null
	target = null
	state = State.ACQUIRE_TARGET


func _refresh_body_radius() -> void:
	var multiplier := 1.0
	for empowerment in basic_attack_empowerments:
		multiplier *= float(empowerment.size_multiplier)
	body_radius = base_body_radius * multiplier
	visual_radius = base_visual_radius * multiplier
	var collision_shape := $CollisionShape2D.shape as CircleShape2D
	if collision_shape != null:
		collision_shape.radius = body_radius
	var inset_bounds := arena_bounds.grow(-body_radius)
	position = Vector2(
		clampf(position.x, inset_bounds.position.x, inset_bounds.end.x),
		clampf(position.y, inset_bounds.position.y, inset_bounds.end.y)
	)
	queue_redraw()


func _apply_modifier(base_value: float, modifier: StatModifier, stack_count: int) -> float:
	if modifier == null:
		return base_value
	return modifier.apply_to(base_value, stack_count)


func _update_stuck_state(delta: float) -> void:
	if position.distance_squared_to(last_movement_position) < 0.25:
		stuck_time += delta
	else:
		stuck_time = 0.0
		last_movement_position = position

	if stuck_time < STUCK_TIMEOUT:
		return

	stuck_time = 0.0
	target = null
	state = State.ACQUIRE_TARGET


func _can_retreat_from(direction_to_target: Vector2) -> bool:
	var retreat_position := position - direction_to_target * 48.0
	return arena_bounds.grow(-body_radius).has_point(retreat_position)


func _update_boss_phase() -> void:
	if not snapshot.is_boss or boss_phase >= snapshot.boss_phase_count:
		return
	var health_ratio := current_hp / maxf(snapshot.stats.max_hp, 1.0)
	while boss_phase < snapshot.boss_phase_count:
		var threshold_index := boss_phase - 1
		if threshold_index >= snapshot.boss_phase_health_thresholds.size() or health_ratio > snapshot.boss_phase_health_thresholds[threshold_index]:
			break
		boss_phase += 1
		phase_banner_timer = 1.5
		ability_cooldowns.clear()
		session.record_event(
			CombatEvent.BOSS_PHASE_CHANGED,
			snapshot.runtime_id,
			"",
			&"",
			&"boss.phase",
			float(boss_phase)
		)
	queue_redraw()


func _draw() -> void:
	var color := snapshot.placeholder_color
	if stealth_remaining > 0.0:
		color.a = 0.35
	if state == State.DEAD:
		color = color.darkened(0.65)
	if flash_remaining > 0.0:
		color = flash_color

	if not unit_sprite.visible:
		if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
			draw_circle(Vector2.ZERO, visual_radius, color)
			draw_arc(Vector2.ZERO, visual_radius, 0.0, TAU, 32, Color.WHITE, 2.0)
		else:
			draw_rect(Rect2(Vector2(-visual_radius, -visual_radius), Vector2.ONE * visual_radius * 2.0), color)
	if snapshot.is_boss:
		draw_arc(Vector2.ZERO, visual_radius + 5.0, 0.0, TAU, 40, snapshot.boss_telegraph_color, 3.0)
		for phase_ring in range(1, boss_phase):
			draw_arc(Vector2.ZERO, visual_radius + 5.0 + phase_ring * 4.0, 0.0, TAU, 40, snapshot.boss_telegraph_color.lightened(0.2), 2.0)
	if selected:
		draw_arc(Vector2.ZERO, visual_radius + 7.0, 0.0, TAU, 32, Color(1.0, 0.86, 0.35), 3.0)

	if state == State.DEAD:
		if not unit_sprite.visible or not unit_sprite.sprite_frames.has_animation(&"death"):
			draw_line(Vector2(-10, -10), Vector2(10, 10), Color.WHITE, 3.0)
			draw_line(Vector2(10, -10), Vector2(-10, 10), Color.WHITE, 3.0)
		return
	if snapshot.is_boss and state == State.ATTACK_WINDUP:
		var progress := 1.0 - state_timer / maxf(windup_duration, 0.01)
		draw_arc(Vector2.ZERO, visual_radius + 13.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, snapshot.boss_telegraph_color, 5.0)
		var warning := pending_ability.presentation_text if pending_ability != null and not pending_ability.presentation_text.is_empty() else "INCOMING ATTACK"
		draw_string(ThemeDB.get_project_theme().default_font, Vector2(-visual_radius * 2.0, -visual_radius - 28.0), warning, HORIZONTAL_ALIGNMENT_CENTER, visual_radius * 4.0, 12, snapshot.boss_telegraph_color)
	if snapshot.is_boss and phase_banner_timer > 0.0:
		draw_string(ThemeDB.get_project_theme().default_font, Vector2(-visual_radius * 3.0, visual_radius + 30.0), snapshot.boss_phase_telegraph_text, HORIZONTAL_ALIGNMENT_CENTER, visual_radius * 6.0, 13, snapshot.boss_telegraph_color)

	var health_ratio := current_hp / maxf(get_effective_stat(&"max_hp"), 1.0)
	var bar_y := -health_bar_offset if health_bar_offset > 0.0 else -visual_radius - 11.0
	var bar_rect := Rect2(Vector2(-visual_radius, bar_y), Vector2(visual_radius * 2.0, 5.0))
	draw_rect(bar_rect, Color(0.08, 0.08, 0.08, 0.9))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_ratio, bar_rect.size.y)), Color(0.28, 0.86, 0.38))
	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SOLDIER and snapshot.veterancy_level >= 0:
		# Rank chevrons just left of the health bar, readable without selecting the unit.
		VeterancyInsignia.draw_insignia(self, Vector2(bar_rect.position.x - 9.0, bar_rect.get_center().y), snapshot.veterancy_level, 13.0)
