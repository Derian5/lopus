class_name CombatVfx
extends RefCounted


## Combat visual effects made with Arcaidia Effector (sources: "Arcada Effector_1.0 (1)/
## library/CBO *.json", generator gen_cbo.py there). Every atlas lives in
## graphics/effects/vfx/<id>.png. Effects are presentation only: nothing here touches
## combat state, and the Balance Lab turns them off (CombatSession.vfx_enabled).

const FOLDER := "res://graphics/effects/vfx/"
## Frame layout of every atlas, as exported by the editor.
const ATLASES := {
	&"arcane_lance": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"arrow": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"cast_sigil": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 16.67},
	&"death_smoke": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 12.63},
	&"death_soul": {"size": Vector2i(192, 240), "cols": 4, "frames": 12, "fps": 12.63},
	&"ember_bolt": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"gloom_orb": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"heal_sparkle": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 15.38},
	&"hex_orb": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"hit_heavy": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 35.29},
	&"hit_slash": {"size": Vector2i(192, 192), "cols": 4, "frames": 8, "fps": 26.67},
	&"holy_bolt": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"magic_burst": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 36.36},
	&"magic_orb": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"slam_dust": {"size": Vector2i(288, 180), "cols": 4, "frames": 12, "fps": 14.12},
	&"slam_ring": {"size": Vector2i(288, 180), "cols": 4, "frames": 12, "fps": 20.0},
	&"spirit_wisp": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"summon_portal": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 16.67},
	&"venom_bolt": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"spear_sparks": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 28.57},
	&"walk_dust": {"size": Vector2i(96, 96), "cols": 4, "frames": 8, "fps": 14.29},
}
## Projectile atlases loop; everything else plays once and frees itself.
## Drawn additively (light, fire, magic). Smoke, dust and the solid parts of the arrow,
## gloom orb and hex orb use normal blending.
const ADDITIVE := [&"spear_sparks", &"hit_slash", &"hit_heavy", &"magic_burst", &"slam_ring", &"cast_sigil", &"heal_sparkle", &"death_soul", &"summon_portal", &"holy_bolt", &"spirit_wisp", &"arcane_lance", &"magic_orb"]
const LOOPING := [&"arcane_lance", &"arrow", &"ember_bolt", &"gloom_orb", &"hex_orb", &"holy_bolt", &"magic_orb", &"spirit_wisp", &"venom_bolt"]

## Basic ranged shot of each shooter (Hero, Job or enemy id). Others use magic_orb.
const PROJECTILES := {
	&"hero.army_support": &"venom_bolt",
	&"hero.control_savant": &"arcane_lance",
	&"hero.iron_oracle": &"gloom_orb",
	&"job.archer": &"arrow",
	&"job.priest": &"holy_bolt",
	&"job.summoner": &"spirit_wisp",
	&"enemy.summoned_shooter": &"spirit_wisp",
	&"enemy.troll_hexer": &"hex_orb",
	&"enemy.troll_witch_doctor": &"ember_bolt",
}
## Colour of the burst where each kind of shot lands (and of its launch flash).
const PROJECTILE_COLORS := {
	&"arrow": Color(1.0, 0.86, 0.62),
	&"holy_bolt": Color(1.0, 0.84, 0.45),
	&"spirit_wisp": Color(0.5, 0.95, 0.9),
	&"venom_bolt": Color(0.55, 1.0, 0.45),
	&"arcane_lance": Color(0.8, 0.52, 1.0),
	&"gloom_orb": Color(0.45, 0.52, 1.0),
	&"hex_orb": Color(0.62, 0.92, 0.32),
	&"ember_bolt": Color(1.0, 0.55, 0.25),
	&"magic_orb": Color.WHITE,
}
## Hero melee impacts take the colour of their sin.
const HERO_COLORS := {
	&"hero.ashen_duelist": Color(1.0, 0.58, 0.42),
	&"hero.test_vanguard": Color(1.0, 0.86, 0.45),
	&"hero.glass_arcanist": Color(1.0, 0.6, 0.86),
	&"hero.thorn_warden": Color(0.75, 1.0, 0.55),
	&"hero.army_support": Color(0.6, 1.0, 0.5),
	&"hero.iron_oracle": Color(0.6, 0.66, 1.0),
	&"hero.control_savant": Color(0.82, 0.62, 1.0),
}
## Magic shots carry a light that lights up the ground and the units they pass:
## colour, energy, radius (texture scale; 1 = a 256 px wide light).
const SHOT_LIGHTS := {
	&"holy_bolt": [Color(1.0, 0.8, 0.45), 1.5, 1.7],
	&"spirit_wisp": [Color(0.45, 0.95, 0.95), 1.4, 1.6],
	&"arcane_lance": [Color(0.72, 0.45, 1.0), 1.7, 2.0],
	&"gloom_orb": [Color(0.42, 0.52, 1.0), 1.5, 1.8],
	&"hex_orb": [Color(0.6, 1.0, 0.35), 1.2, 1.5],
	&"ember_bolt": [Color(1.0, 0.55, 0.22), 1.7, 1.8],
	&"magic_orb": [Color(1.0, 1.0, 1.0), 1.2, 1.5],
}
## At most this many short light flashes at once (they are cheap but not free).
const MAX_FLASH_LIGHTS := 24
## Spear wielders strike with a flurry of sparks instead of the blade arc.
const SPEAR_JOBS := [&"job.militia", &"job.shieldbearer"]
## Big enemies hit with the heavy impact.
const HEAVY_HITTERS := [&"enemy.ogre_brute", &"enemy.ogre_bonebreaker", &"enemy.troll_berserker", &"enemy.iron_warden", &"enemy.summoned_amalgam"]
const IMPACT_Z := 30
const GROUND_Z := 1
## Effects layer never holds more than this many effects; extra low-priority ones are skipped.
const MAX_ACTIVE := 140

static var frame_cache: Dictionary = {}
static var additive_material: CanvasItemMaterial
static var light_texture: GradientTexture2D
static var shadow_texture: ImageTexture
static var vignette_texture: GradientTexture2D
static var flash_lights := 0


static func material_for(effect_id: StringName) -> Material:
	if not effect_id in ADDITIVE:
		return null
	if additive_material == null:
		additive_material = CanvasItemMaterial.new()
		additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		# Glowing effects are light sources themselves: lights must not brighten them again.
		additive_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return additive_material


static func has_atlas(effect_id: StringName) -> bool:
	return ATLASES.has(effect_id)


static func projectile_for(shooter_id: StringName, job_id: StringName = &"") -> StringName:
	if PROJECTILES.has(shooter_id):
		return PROJECTILES[shooter_id]
	if PROJECTILES.has(job_id):
		return PROJECTILES[job_id]
	return &"magic_orb"


static func get_frames(effect_id: StringName) -> SpriteFrames:
	if frame_cache.has(effect_id):
		return frame_cache[effect_id]
	if not ATLASES.has(effect_id):
		return null
	var texture := load(FOLDER + String(effect_id) + ".png") as Texture2D
	if texture == null:
		return null
	var config: Dictionary = ATLASES[effect_id]
	var size: Vector2i = config.size
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"play")
	frames.set_animation_loop(&"play", effect_id in LOOPING)
	frames.set_animation_speed(&"play", float(config.fps))
	for index in int(config.frames):
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2i((index % int(config.cols)) * size.x, floori(float(index) / int(config.cols)) * size.y, size.x, size.y)
		frames.add_frame(&"play", frame)
	frame_cache[effect_id] = frames
	return frames


## Plays a one-shot effect at a position on the effects layer and frees it at the end.
## low_priority effects (dust, small sparkles) are skipped when the layer is crowded.
static func spawn(
	parent: Node,
	effect_id: StringName,
	world_position: Vector2,
	scale := 1.0,
	tint := Color.WHITE,
	rotation := 0.0,
	z_index := IMPACT_Z,
	low_priority := false
) -> AnimatedSprite2D:
	if parent == null or (low_priority and parent.get_child_count() >= MAX_ACTIVE * 0.6) or parent.get_child_count() >= MAX_ACTIVE:
		return null
	var frames := get_frames(effect_id)
	if frames == null:
		return null
	var effect := AnimatedSprite2D.new()
	effect.name = "Vfx_%s" % effect_id
	effect.sprite_frames = frames
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	effect.z_index = z_index
	effect.scale = Vector2.ONE * scale
	effect.rotation = rotation
	effect.modulate = tint
	effect.material = material_for(effect_id)
	parent.add_child(effect)
	effect.position = world_position
	effect.animation_finished.connect(effect.queue_free)
	effect.play(&"play")
	return effect


## A looping sprite for a flying shot (child of the projectile, pointing along +X).
static func make_projectile_sprite(effect_id: StringName, tint := Color.WHITE, scale := 0.92) -> AnimatedSprite2D:
	var frames := get_frames(effect_id)
	if frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.name = "ProjectileVfx"
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.modulate = tint
	sprite.material = material_for(effect_id)
	sprite.scale = Vector2.ONE * scale
	# The atlas draws the head at +64 px of a 256 px composition (cell = 0.75 of it):
	# shift it back so the head of the shot sits on the projectile position.
	sprite.offset = Vector2(-48.0, 0.0)
	sprite.play(&"play")
	return sprite


## Soft round light texture shared by every effect light.
static func get_light_texture() -> GradientTexture2D:
	if light_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.3, Color(1, 1, 1, 0.55))
		gradient.add_point(0.65, Color(1, 1, 1, 0.15))
		light_texture = GradientTexture2D.new()
		light_texture.gradient = gradient
		light_texture.fill = GradientTexture2D.FILL_RADIAL
		light_texture.fill_from = Vector2(0.5, 0.5)
		light_texture.fill_to = Vector2(0.5, 0.0)
		light_texture.width = 256
		light_texture.height = 256
	return light_texture


static func make_light(color: Color, energy: float, radius_scale: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = "VfxLight"
	light.texture = get_light_texture()
	light.color = color
	light.energy = energy
	light.texture_scale = radius_scale
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	return light


## A short flash of light (hits, casts, deaths): fades out and frees itself.
static func flash_light(parent: Node, world_position: Vector2, color: Color, energy: float, radius_scale: float, duration: float) -> void:
	if parent == null or flash_lights >= MAX_FLASH_LIGHTS:
		return
	var light := make_light(color, energy, radius_scale)
	parent.add_child(light)
	light.position = world_position
	flash_lights += 1
	light.tree_exited.connect(func() -> void: flash_lights = maxi(0, flash_lights - 1))
	var tween := light.create_tween()
	tween.tween_property(light, "energy", 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(light.queue_free)


## A few tiny lights flying off like sparks (with gravity), fading in a moment: hot
## sparks light the ground around them.
static func spark_lights(parent: Node, world_position: Vector2, direction: Vector2, color: Color, count := 3) -> void:
	if parent == null:
		return
	var base_angle := direction.angle() if not direction.is_zero_approx() else 0.0
	for index in count:
		if flash_lights >= MAX_FLASH_LIGHTS:
			return
		var light := make_light(color, 1.3, 0.32)
		parent.add_child(light)
		light.position = world_position
		flash_lights += 1
		light.tree_exited.connect(func() -> void: flash_lights = maxi(0, flash_lights - 1))
		var angle := base_angle + randf_range(-0.7, 0.7)
		var speed := randf_range(140.0, 260.0)
		var velocity := Vector2.from_angle(angle) * speed
		var duration := randf_range(0.22, 0.36)
		var start := world_position
		var tween := light.create_tween().set_parallel(true)
		# Ballistic path: p = start + v t + g t^2 / 2.
		tween.tween_method(func(time: float) -> void:
			if is_instance_valid(light):
				light.position = start + velocity * time + Vector2(0.0, 520.0) * time * time * 0.5,
			0.0, duration, duration)
		tween.tween_property(light, "energy", 0.0, duration).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(light.queue_free)


## Soft dark ellipse under a unit's feet.
static func get_shadow_texture() -> Texture2D:
	if shadow_texture == null:
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var d := Vector2(x - 63.5, y - 63.5).length() / 64.0
				var a := clampf((1.0 - d) * 1.5, 0.0, 1.0)
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * a * (3.0 - 2.0 * a) * 0.9))
		shadow_texture = ImageTexture.create_from_image(image)
	return shadow_texture


## Darkened arena edges and corners (drawn over the battlefield, under the foreground).
static func get_vignette_texture() -> GradientTexture2D:
	if vignette_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0))
		gradient.set_color(1, Color(0.02, 0.01, 0.0, 0.78))
		gradient.add_point(0.55, Color(0, 0, 0, 0.0))
		gradient.add_point(0.8, Color(0.02, 0.01, 0.0, 0.32))
		vignette_texture = GradientTexture2D.new()
		vignette_texture.gradient = gradient
		vignette_texture.fill = GradientTexture2D.FILL_RADIAL
		vignette_texture.fill_from = Vector2(0.5, 0.5)
		vignette_texture.fill_to = Vector2(1.0, 0.5)
		vignette_texture.width = 256
		vignette_texture.height = 256
	return vignette_texture
