class_name CombatVfx
extends RefCounted


## Combat visual effects made with Arcaidia Effector (sources: "Arcada Effector_1.0 (1)/
## library/CBO *.json", generator gen_cbo.py there). Every atlas lives in
## graphics/effects/vfx/<id>.png. Effects are presentation only: nothing here touches
## combat state, and the Balance Lab turns them off (CombatSession.vfx_enabled).

const FOLDER := "res://graphics/effects/vfx/"
const SPELL_SHAPE := preload("res://combat/vfx/spell_shape_vfx.gd")
## Frame layout of every atlas, as exported by the editor.
const ATLASES := {
	&"arcane_lance": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"arrow": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	# Fire Arrow: the solid arrow and smoke (normal) + the fire itself (additive), played together.
	&"fire_arrow": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"fire_arrow_glow": {"size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
	&"witch_orb": {"texture": "magic_orb", "size": Vector2i(192, 96), "cols": 4, "frames": 8, "fps": 20.0},
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
	&"veterancy_blessing": {"size": Vector2i(192, 336), "cols": 4, "frames": 16, "fps": 12.5},
	&"bleeding_drips": {"size": Vector2i(128, 160), "cols": 6, "frames": 24, "fps": 20.0},
	# Fire and blood (gen_cbo.py): burning body loop + smoke, fire flare, blood sprays.
	&"burn_loop": {"size": Vector2i(192, 240), "cols": 4, "frames": 16, "fps": 16.0},
	&"burn_smoke": {"size": Vector2i(192, 240), "cols": 4, "frames": 16, "fps": 16.0},
	&"fire_burst": {"size": Vector2i(192, 192), "cols": 4, "frames": 12, "fps": 15.79},
	&"blood_spurt": {"size": Vector2i(192, 144), "cols": 4, "frames": 12, "fps": 20.69},
	&"blood_burst": {"size": Vector2i(192, 144), "cols": 4, "frames": 12, "fps": 20.69},
}
## Projectile atlases loop; everything else plays once and frees itself.
## Drawn additively (light, fire, magic). Smoke, dust and the solid parts of the arrow,
## gloom orb and hex orb use normal blending.
const ADDITIVE := [&"fire_arrow_glow", &"burn_loop", &"fire_burst", &"witch_orb", &"veterancy_blessing", &"spear_sparks", &"hit_slash", &"hit_heavy", &"magic_burst", &"slam_ring", &"cast_sigil", &"heal_sparkle", &"death_soul", &"summon_portal", &"holy_bolt", &"spirit_wisp", &"arcane_lance", &"magic_orb"]
const LOOPING := [&"burn_loop", &"burn_smoke", &"bleeding_drips", &"arcane_lance", &"arrow", &"fire_arrow", &"fire_arrow_glow", &"witch_orb", &"ember_bolt", &"gloom_orb", &"hex_orb", &"holy_bolt", &"magic_orb", &"spirit_wisp", &"venom_bolt"]
const NORMAL_UNSHADED := [&"bleeding_drips"]

## Basic ranged shot of each shooter (Hero, Job or enemy id). Others use magic_orb.
const PROJECTILES := {
	&"hero.army_support": &"venom_bolt",
	&"hero.control_savant": &"arcane_lance",
	&"hero.iron_oracle": &"gloom_orb",
	&"job.archer": &"arrow",
	&"job.priest": &"holy_bolt",
	&"job.summoner": &"spirit_wisp",
	&"enemy.summoned_shooter": &"spirit_wisp",
	&"enemy.summoner": &"hex_orb",
	&"enemy.troll_priest": &"witch_orb",
}
## Colour of the burst where each kind of shot lands (and of its launch flash).
const PROJECTILE_COLORS := {
	&"arrow": Color(1.0, 0.86, 0.62),
	&"fire_arrow": Color(1.0, 0.48, 0.09),
	&"witch_orb": Color(0.82, 0.32, 1.0),
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
	&"fire_arrow": [Color(1.0, 0.46, 0.12), 2.0, 1.6],
	&"witch_orb": [Color(0.8, 0.3, 1.0), 0.95, 1.15],
	&"holy_bolt": [Color(1.0, 0.8, 0.45), 0.85, 1.05],
	&"spirit_wisp": [Color(0.45, 0.95, 0.95), 0.75, 1.0],
	&"arcane_lance": [Color(0.72, 0.45, 1.0), 1.05, 1.25],
	&"gloom_orb": [Color(0.42, 0.52, 1.0), 0.8, 1.15],
	&"hex_orb": [Color(0.6, 1.0, 0.35), 0.75, 1.0],
	&"ember_bolt": [Color(1.0, 0.55, 0.22), 1.0, 1.15],
	&"magic_orb": [Color(1.0, 1.0, 1.0), 0.7, 1.0],
}
## At most this many short light flashes at once (they are cheap but not free).
const MAX_FLASH_LIGHTS := 24
## Spear wielders strike with a flurry of sparks instead of the blade arc.
const SPEAR_JOBS := [&"job.militia", &"job.shieldbearer"]
## Big enemies hit with the heavy impact.
const HEAVY_HITTERS := [&"enemy.raider", &"enemy.ogre_bonebreaker", &"enemy.troll_berserker", &"enemy.iron_warden", &"enemy.summoned_amalgam"]
const IMPACT_Z := 30
const GROUND_Z := 1
## Effects layer never holds more than this many effects; extra low-priority ones are skipped.
const MAX_ACTIVE := 140
## Additive atlases overlap in large armies. Preserve the colour instead of
## accumulating their white cores into an opaque patch over the combatants.
const OPACITY := {
	&"cast_sigil": 0.55, &"heal_sparkle": 0.6, &"summon_portal": 0.65,
	&"magic_burst": 0.7, &"spear_sparks": 0.75, &"slam_ring": 0.75,
	&"hit_heavy": 0.65, &"hit_slash": 0.7,
	&"burn_loop": 0.62, &"fire_burst": 0.62, &"burn_smoke": 0.8, &"blood_spurt": 0.85, &"blood_burst": 0.85,
}

static var frame_cache: Dictionary = {}
static var additive_material: CanvasItemMaterial
static var normal_unshaded_material: CanvasItemMaterial
static var light_texture: GradientTexture2D
static var shadow_texture: ImageTexture
static var vignette_texture: GradientTexture2D
static var flash_lights := 0
static var status_lights := 0
const MAX_STATUS_LIGHTS := 8
static var ground_light_texture: ImageTexture
static var drop_texture: ImageTexture
static var decal_texture: Texture2D
## Unit definition id -> whether it sheds blood (skeletons and spirits do not).
static var bleeding_units: Dictionary = {}
## Ground decals (blood, scorch marks) stay for the whole battle, up to this many.
const MAX_DECALS := 420
const DECALS_PATH := "res://graphics/effects/vfx/ground_decals.png"
## ground_decals.png (tools/vfx/gen_decals.py): 128 px cells, blood splats 0..7
## (rows 0-1), scorch marks 8..11 (row 2).
const DECAL_CELL := 128
const FIRE_LIGHT := Color(1.0, 0.5, 0.18)
const BLOODLESS_TAGS := [&"undead", &"spirit", &"construct", &"skeleton"]


static func material_for(effect_id: StringName) -> Material:
	if effect_id in NORMAL_UNSHADED:
		if normal_unshaded_material == null:
			normal_unshaded_material = CanvasItemMaterial.new()
			normal_unshaded_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		return normal_unshaded_material
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


static func ability_style(ability: AbilityDefinition) -> StringName:
	if ability == null:
		return &"arcane"
	if not ability.presentation_style.is_empty():
		return ability.presentation_style
	for effect in ability.effects:
		if effect is HealEffect:
			return &"holy"
		if effect is SummonEffect or effect is SummonMergeEffect:
			return &"summon"
		if effect is ApplyStatusEffect and effect.status != null:
			var style := status_style(effect.status, ability)
			if not style.is_empty():
				return style
	return &"physical" if ability.delivery_method == AbilityDefinition.DeliveryMethod.MELEE_HIT else &"arcane"


static func status_style(status: StatusDefinition, ability: AbilityDefinition = null) -> StringName:
	if status == null:
		return &""
	if not status.presentation_style.is_empty():
		return status.presentation_style
	if status.causes_fear:
		return &"fear"
	if status.prevents_actions:
		return &"sleep" if status.breaks_on_hp_damage or (ability != null and ability.presentation_style == &"sleep") else &"stun"
	if status.prevents_movement:
		return &"nature"
	if status.grants_invulnerability:
		return &"ward"
	for effect in status.periodic_effects:
		if effect is DamageEffect:
			return ability.presentation_style if ability != null and ability.presentation_style in [&"fire", &"poison", &"shadow"] else &"poison"
	return &""


static func spawn_spell(parent: Node, style: StringName, at: Vector2, tint: Color, radius := 36.0, duration := 0.55) -> Node2D:
	if parent == null or parent.get_child_count() >= MAX_ACTIVE:
		return null
	if style == &"fire":
		# A flare of flame tongues and embers (fire_burst: its ground ring sits 60 px
		# below the cell centre) and a scorch mark that stays on the ground.
		var fire_scale := clampf(radius / 60.0, 0.4, 2.2)
		var session = parent.get_parent()
		if session != null and session.has_method("add_ground_decal"):
			session.add_ground_decal(at, &"scorch", radius * 1.4, 0.05, 0.2)
		return spawn(parent, &"fire_burst", at - Vector2(0.0, 60.0 * fire_scale), fire_scale, Color.WHITE)
	var effect := SPELL_SHAPE.new()
	effect.name = "Spell_%s" % style
	effect.style = style
	effect.tint = tint
	effect.radius = clampf(radius, 12.0, 200.0)
	effect.duration = duration
	effect.z_index = IMPACT_Z
	effect.material = material_for(&"magic_burst")
	if style == &"smoke":
		effect.material = null
		effect.puff_texture = get_light_texture()
	parent.add_child(effect)
	effect.position = at
	return effect


## One blood spray per damaging hit: drops thrown away from the attacker (blood_spurt,
## flipped toward the blow, never rotated so they always fall down) or, for bleeding
## ticks, splashing out to both sides (blood_burst). Where the drops land, stains stay
## on the ground for the whole battle. Blood is normal-blended liquid, never a glow.
static func spawn_blood(parent: Node, at: Vector2, feet: Vector2, direction: Vector2, height: float, severity := 1.0, bleed_tick := false, variation := 0) -> AnimatedSprite2D:
	var size := clampf(height / 128.0, 0.55, 2.0)
	var scale := size * clampf(0.32 + 0.3 * severity, 0.45, 0.8) * (0.9 if bleed_tick else 1.0)
	scale *= 0.94 + float((variation >> 8) & 255) / 255.0 * 0.12
	var side := -1.0 if direction.x < 0.0 else 1.0
	var spray: AnimatedSprite2D
	if bleed_tick:
		spray = spawn(parent, &"blood_burst", at + Vector2(0.0, 15.0 * scale), scale, Color.WHITE, 0.0, IMPACT_Z + 1)
	else:
		# The spray starts 37 px left of and 15 px above the cell centre.
		spray = spawn(parent, &"blood_spurt", at + Vector2(37.0 * scale * side, 15.0 * scale), scale, Color.WHITE, 0.0, IMPACT_Z + 1)
		if spray != null:
			spray.flip_h = side < 0.0
	if spray != null:
		spray.name = "BleedPulse" if bleed_tick else "BloodHit"
	var session = parent.get_parent() if parent != null else null
	if session != null and session.has_method("add_ground_decal"):
		var splats := 1 + int(severity > 1.0) + int(severity > 1.3)
		for index in splats:
			var reach := randf_range(-30.0, 30.0) if bleed_tick else randf_range(10.0, 70.0) * side
			session.add_ground_decal(feet + Vector2(reach * scale, randf_range(-8.0, 8.0)), &"blood", randf_range(16.0, 30.0) * (0.5 + 0.4 * severity) * size, randf_range(0.18, 0.32))
	return spray


static func get_frames(effect_id: StringName) -> SpriteFrames:
	if frame_cache.has(effect_id):
		return frame_cache[effect_id]
	if not ATLASES.has(effect_id):
		return null
	var texture := load(FOLDER + String(ATLASES[effect_id].get("texture", effect_id)) + ".png") as Texture2D
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
	effect.modulate.a *= float(OPACITY.get(effect_id, 1.0))
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
		gradient.add_point(0.22, Color(1, 1, 1, 0.72))
		gradient.add_point(0.45, Color(1, 1, 1, 0.34))
		gradient.add_point(0.7, Color(1, 1, 1, 0.1))
		light_texture = GradientTexture2D.new()
		light_texture.gradient = gradient
		light_texture.fill = GradientTexture2D.FILL_RADIAL
		light_texture.fill_from = Vector2(0.5, 0.5)
		light_texture.fill_to = Vector2(0.5, 0.0)
		light_texture.width = 256
		light_texture.height = 256
	return light_texture


## on_ground: an elliptical pool of light on the ground (flashes, burning units);
## otherwise a round glow (shots in the air).
static func make_light(color: Color, energy: float, radius_scale: float, on_ground := false) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = "VfxLight"
	light.texture = get_ground_light_texture() if on_ground else get_light_texture()
	light.color = color
	# Keep overlapping lights from washing the silhouettes and terrain to white.
	light.energy = energy * 0.55
	light.texture_scale = radius_scale
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	return light


static func make_status_light(parent: Node, color: Color, radius_scale: float) -> PointLight2D:
	if parent == null or status_lights >= MAX_STATUS_LIGHTS:
		return null
	var light := make_light(color, 0.65, radius_scale, true)
	light.name = "BurnLight"
	parent.add_child(light)
	status_lights += 1
	light.tree_exited.connect(func() -> void: status_lights = maxi(0, status_lights - 1))
	return light


## A short flash of light (hits, casts, deaths): fades out and frees itself.
static func flash_light(parent: Node, world_position: Vector2, color: Color, energy: float, radius_scale: float, duration: float) -> void:
	if parent == null or flash_lights >= MAX_FLASH_LIGHTS:
		return
	var light := make_light(color, energy, radius_scale, true)
	parent.add_child(light)
	light.position = world_position
	flash_lights += 1
	light.tree_exited.connect(func() -> void: flash_lights = maxi(0, flash_lights - 1))
	# A very short rise, then a long soft tail: a flash rather than a lamp switching off.
	var peak := light.energy
	light.energy = 0.0
	var tween := light.create_tween()
	tween.tween_property(light, "energy", peak, 0.035)
	tween.tween_property(light, "energy", 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
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


## Light lying on the ground: an ellipse (the arena is seen at an angle) with a soft
## quadratic falloff, so a flash reads as a warm pool on the ground.
static func get_ground_light_texture() -> ImageTexture:
	if ground_light_texture == null:
		var width := 320
		var height := 176
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		for y in height:
			for x in width:
				var d := Vector2((x + 0.5) / width * 2.0 - 1.0, (y + 0.5) / height * 2.0 - 1.0).length()
				var falloff := clampf(1.0 - d * d, 0.0, 1.0)
				image.set_pixel(x, y, Color(1, 1, 1, pow(falloff, 2.2)))
		ground_light_texture = ImageTexture.create_from_image(image)
	return ground_light_texture


## Flickering fire: base energy modulated by two out-of-phase waves.
static func fire_flicker(time: float, seed: float) -> float:
	return 0.78 + 0.14 * sin(time * 13.0 + seed) + 0.08 * sin(time * 31.0 + seed * 2.3) + 0.05 * sin(time * 5.0 + seed * 0.7)


## Whether a unit sheds blood (skeletons and spirits do not).
static func bleeds(unit) -> bool:
	if unit == null or unit.snapshot == null:
		return false
	var definition_id: StringName = unit.snapshot.definition_id
	if bleeding_units.has(definition_id):
		return bleeding_units[definition_id]
	var result := true
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("ContentRegistry")
	var definition = registry.get_definition(definition_id, false) if registry != null else null
	if definition != null and "tags" in definition:
		for tag in BLOODLESS_TAGS:
			if definition.tags.has(tag):
				result = false
	bleeding_units[definition_id] = result
	return result


## A falling drop of blood (small teardrop, pointing down).
static func get_drop_texture() -> ImageTexture:
	if drop_texture == null:
		var image := Image.create(8, 14, false, Image.FORMAT_RGBA8)
		for y in 14:
			for x in 8:
				var dx := (x + 0.5 - 4.0) / 4.0
				var dy := (y + 0.5 - 9.5) / 4.5
				var body := 1.0 - (dx * dx + dy * dy)
				if y < 9:
					# Tapering tail above the round bottom.
					body = 1.0 - absf(dx) / maxf(0.05, (y + 0.5) / 9.0) - 0.15
				var a := clampf(body * 2.5, 0.0, 1.0)
				image.set_pixel(x, y, Color(0.52, 0.03, 0.05, a))
		drop_texture = ImageTexture.create_from_image(image)
	return drop_texture


## A ground decal sprite: kind &"blood" (8 variants) or &"scorch" (4 variants).
static func make_decal(kind: StringName) -> Sprite2D:
	if decal_texture == null:
		decal_texture = load(DECALS_PATH) as Texture2D
	if decal_texture == null:
		return null
	var index := randi() % 8 if kind == &"blood" else 8 + randi() % 4
	var region := AtlasTexture.new()
	region.atlas = decal_texture
	region.region = Rect2((index % 4) * DECAL_CELL, floori(index / 4.0) * DECAL_CELL, DECAL_CELL, DECAL_CELL)
	var sprite := Sprite2D.new()
	sprite.name = "Decal"
	sprite.texture = region
	sprite.flip_h = randf() < 0.5
	sprite.flip_v = randf() < 0.5
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return sprite


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
		gradient.set_color(1, Color(0.02, 0.01, 0.0, 0.6))
		gradient.add_point(0.55, Color(0, 0, 0, 0.0))
		gradient.add_point(0.8, Color(0.02, 0.01, 0.0, 0.22))
		vignette_texture = GradientTexture2D.new()
		vignette_texture.gradient = gradient
		vignette_texture.fill = GradientTexture2D.FILL_RADIAL
		vignette_texture.fill_from = Vector2(0.5, 0.5)
		vignette_texture.fill_to = Vector2(1.0, 0.5)
		vignette_texture.width = 256
		vignette_texture.height = 256
	return vignette_texture
