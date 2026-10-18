class_name HeroAttackVfx
extends RefCounted


const IMPACT_CONFIGS := {
	&"hero.ashen_duelist": {
		"texture": preload("res://graphics/effects/attacks/wrath_attack_impact.png"),
		"fps": 16.0,
		"orient": true,
	},
	&"hero.test_vanguard": {
		"texture": preload("res://graphics/effects/attacks/greed_attack_impact.png"),
		"fps": 13.79,
	},
	&"hero.glass_arcanist": {
		"texture": preload("res://graphics/effects/attacks/lust_attack_impact.png"),
		"fps": 12.9,
	},
	&"hero.thorn_warden": {
		"texture": preload("res://graphics/effects/attacks/gluttony_attack_impact.png"),
		"fps": 12.12,
	},
	&"hero.army_support": {
		"texture": preload("res://graphics/effects/attacks/envy_attack_impact.png"),
		"fps": 14.29,
	},
	&"hero.iron_oracle": {
		"texture": preload("res://graphics/effects/attacks/despair_attack_impact.png"),
		"fps": 11.76,
	},
	&"hero.control_savant": {
		"texture": preload("res://graphics/effects/attacks/pride_attack_impact.png"),
		"fps": 13.33,
	},
}
const PROJECTILE_CONFIGS := {
	&"hero.army_support": {
		"texture": preload("res://graphics/effects/attacks/envy_venom_dart.png"),
		"frame_size": Vector2i(64, 32),
		"fps": 10.0,
	},
	&"hero.iron_oracle": {
		"texture": preload("res://graphics/effects/attacks/despair_gloom_orb.png"),
		"frame_size": Vector2i(48, 48),
		"fps": 8.89,
	},
	&"hero.control_savant": {
		"texture": preload("res://graphics/effects/projectiles/pride_arcane_bolt.png"),
		"frame_size": Vector2i(64, 32),
		"fps": 10.0,
	},
}
const FRAME_COUNT := 8
const ATLAS_COLUMNS := 4

static var impact_frame_cache: Dictionary = {}
static var projectile_frame_cache: Dictionary = {}


static func has_projectile(hero_id: StringName) -> bool:
	return PROJECTILE_CONFIGS.has(hero_id)


static func get_projectile_frames(hero_id: StringName) -> SpriteFrames:
	if not PROJECTILE_CONFIGS.has(hero_id):
		return null
	if not projectile_frame_cache.has(hero_id):
		var config: Dictionary = PROJECTILE_CONFIGS[hero_id]
		projectile_frame_cache[hero_id] = _build_frames(
			config["texture"],
			config["frame_size"],
			float(config["fps"]),
			&"fly",
			true
		)
	return projectile_frame_cache[hero_id]


static func spawn_impact(parent: Node, hero_id: StringName, world_position: Vector2, direction: Vector2) -> AnimatedSprite2D:
	if not IMPACT_CONFIGS.has(hero_id):
		return null
	if not impact_frame_cache.has(hero_id):
		var config: Dictionary = IMPACT_CONFIGS[hero_id]
		impact_frame_cache[hero_id] = _build_frames(
			config["texture"],
			Vector2i(64, 64),
			float(config["fps"]),
			&"impact",
			false
		)
	var config: Dictionary = IMPACT_CONFIGS[hero_id]
	var effect := AnimatedSprite2D.new()
	effect.name = "HeroAttackImpact"
	effect.sprite_frames = impact_frame_cache[hero_id]
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	effect.z_index = 35
	if bool(config.get("orient", false)) and not direction.is_zero_approx():
		effect.rotation = direction.angle()
	parent.add_child(effect)
	effect.position = world_position
	effect.animation_finished.connect(effect.queue_free)
	effect.play(&"impact")
	return effect


static func _build_frames(
	atlas: Texture2D,
	frame_size: Vector2i,
	fps: float,
	animation_name: StringName,
	loop: bool
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, loop)
	frames.set_animation_speed(animation_name, fps)
	for frame_index in FRAME_COUNT:
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2i(
			(frame_index % ATLAS_COLUMNS) * frame_size.x,
			floori(float(frame_index) / ATLAS_COLUMNS) * frame_size.y,
			frame_size.x,
			frame_size.y
		)
		frames.add_frame(animation_name, frame)
	return frames
