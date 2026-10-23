extends Node2D

const VFX := preload("res://combat/vfx/combat_vfx.gd")
const SHAPES := preload("res://combat/vfx/spell_shape_vfx.gd")
var unit  # Combatant; kept untyped to avoid a circular script dependency.
var active_styles := {}
var visual_time := 0.0
var scan_remaining := 0.0
var fire_strength := 0.0
var burn_light: PointLight2D
var burn_sprite: AnimatedSprite2D
var bleed_sprite: AnimatedSprite2D
var bleed_strength := 0.0
## Burning: burn_sprite (front flames, additive) + burn_smoke here, burn_back behind
## the unit sprite (a child of the unit, drawn before it), so the body stays readable.
var burn_back: AnimatedSprite2D
var burn_smoke: AnimatedSprite2D
## Badly hurt (below HURT_THRESHOLD of max HP) or bleeding units drip blood.
const HURT_THRESHOLD := 0.4
var hurt_strength := 0.0
var drip_timer := 0.0

func _ready() -> void:
	# Decorrelate neighbouring IDs: raw string hashes for enemy-00/enemy-01
	# are too close and would make every flame play almost the same phase.
	var phase_seed := int(String(unit.snapshot.runtime_id).hash())
	phase_seed = ((phase_seed ^ (phase_seed >> 16)) * 0x45d9f3b) & 0xffffffff
	phase_seed = ((phase_seed ^ (phase_seed >> 16)) * 0x45d9f3b) & 0xffffffff
	visual_time = float((phase_seed ^ (phase_seed >> 16)) % 8192) / 1024.0
	material = VFX.material_for(&"magic_burst")
	visible = false

func refresh() -> void:
	active_styles.clear()
	if not _can_show():
		return
	for status in unit.statuses:
		var ability := unit.session.get_ability_definition(status.source_ability_id) as AbilityDefinition
		var style := VFX.status_style(status.definition, ability)
		if not style.is_empty():
			active_styles[style] = maxi(int(active_styles.get(style, 0)), status.stacks) if style == &"bleed" else 1
	for shield in unit.shields:
		if float(shield.amount) > 0.0:
			active_styles[&"ward"] = true
	if unit.items.charm_remaining > 0.0:
		active_styles[&"charm"] = true
	scan_remaining = 0.08

func _can_show() -> bool:
	return is_instance_valid(unit) and unit.session != null and unit.session.vfx_enabled and unit.session.battle_active and unit.is_alive()

func _process(delta: float) -> void:
	if not _can_show():
		active_styles.clear()
		fire_strength = 0.0
		bleed_strength = 0.0
		hurt_strength = 0.0
		visible = false
		_write_condition()
		_release_light()
		_update_status_sprites()
		return
	visual_time += delta
	scan_remaining -= delta
	if scan_remaining <= 0.0:
		refresh()
	fire_strength = move_toward(fire_strength, 1.0 if active_styles.has(&"fire") else 0.0, delta * 6.0)
	bleed_strength = move_toward(bleed_strength, 1.0 if active_styles.has(&"bleed") else 0.0, delta * 7.0)
	var health := float(unit.current_hp) / maxf(unit.get_effective_stat(&"max_hp"), 1.0)
	hurt_strength = move_toward(hurt_strength, clampf((HURT_THRESHOLD - health) / HURT_THRESHOLD, 0.0, 1.0), delta * 2.0)
	_write_condition()
	_update_drips(delta)
	visible = not active_styles.is_empty() or fire_strength > 0.0 or bleed_strength > 0.0
	position = unit.feet_offset()
	_update_status_sprites()
	if fire_strength > 0.0:
		var height := _height()
		if not is_instance_valid(burn_light):
			burn_light = VFX.make_status_light(self, VFX.FIRE_LIGHT, 0.7 + height / 300.0)
		if is_instance_valid(burn_light):
			# A pool of flickering firelight on the ground around the burning unit.
			burn_light.position = Vector2(0, -height * 0.08)
			burn_light.energy = 0.62 * fire_strength * VFX.fire_flicker(visual_time, float(unit.snapshot.runtime_id.hash() % 97))
	else:
		_release_light()
	if visible:
		queue_redraw()

func _release_light() -> void:
	if is_instance_valid(burn_light):
		burn_light.queue_free()
		burn_light = null

func _new_status_sprite(effect_id: StringName) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = String(effect_id)
	sprite.sprite_frames = VFX.get_frames(effect_id)
	sprite.material = VFX.material_for(effect_id)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.animation = &"play"
	sprite.frame = int(visual_time * float(VFX.ATLASES[effect_id].fps)) % int(VFX.ATLASES[effect_id].frames)
	add_child(sprite)
	return sprite

## Hands the condition look (burning glow, hurt heartbeat) to the unit's sprite shader.
func _write_condition() -> void:
	if not is_instance_valid(unit):
		return
	unit.condition_burn = fire_strength
	unit.condition_hurt = hurt_strength
	unit.condition_phase = fposmod(visual_time * 0.37, 1.0) if unit.condition_phase == 0.0 else unit.condition_phase


## Drops of blood falling from a badly hurt or bleeding unit; the worse, the faster.
func _update_drips(delta: float) -> void:
	if (hurt_strength <= 0.05 and bleed_strength <= 0.0) or not VFX.bleeds(unit):
		return
	drip_timer -= delta
	if drip_timer > 0.0:
		return
	drip_timer = lerpf(1.1, 0.22, hurt_strength) * (0.7 + fposmod(visual_time * 7.31, 0.6))
	if bleed_strength > 0.0:
		drip_timer = minf(drip_timer, 0.18 + fposmod(visual_time * 3.7, 0.14))
	unit.session.spawn_blood_drip(unit)


func _update_status_sprites() -> void:
	if fire_strength > 0.0 and burn_sprite == null:
		burn_smoke = _new_status_sprite(&"burn_smoke")
		burn_sprite = _new_status_sprite(&"burn_loop")
		burn_back = _new_status_sprite(&"burn_loop")
		remove_child(burn_back)
		unit.add_child(burn_back)
		unit.move_child(burn_back, 0)
	if bleed_strength > 0.0 and bleed_sprite == null:
		bleed_sprite = _new_status_sprite(&"bleeding_drips")
	var height := _height() if is_instance_valid(unit) else 128.0
	var scale := height / 128.0
	if burn_sprite != null:
		# burn_loop: the feet sit 90 px below the cell centre (gen_cbo.py, CBO Burn Loop).
		var fire_size := clampf(height / 130.0, 0.7, 1.25)
		burn_sprite.position = Vector2(0, -78.0 * fire_size)
		burn_sprite.scale = Vector2.ONE * 0.85 * fire_size
		burn_sprite.modulate = Color(1, 1, 1, fire_strength * 0.55)
		burn_smoke.position = Vector2(0, -150.0 * fire_size)
		burn_smoke.scale = Vector2.ONE * fire_size
		burn_smoke.modulate = Color(1, 1, 1, fire_strength * 0.8)
		if is_instance_valid(burn_back):
			burn_back.position = position + Vector2(0, -105.0 * fire_size)
			burn_back.scale = Vector2(1.15, 1.1) * fire_size
			burn_back.modulate = Color(1, 1, 1, fire_strength * 0.75 * 0.62)
		for sprite in [burn_sprite, burn_smoke, burn_back]:
			if not is_instance_valid(sprite):
				continue
			sprite.visible = fire_strength > 0.0
			if fire_strength > 0.0:
				if not sprite.is_playing():
					sprite.play(&"play")
			else:
				sprite.pause()
	if bleed_sprite != null:
		bleed_sprite.visible = bleed_strength > 0.0
		var stacks := maxi(1, int(active_styles.get(&"bleed", 1)))
		bleed_sprite.position = Vector2(0, -height * 0.2)
		bleed_sprite.scale = Vector2(scale * (1.0 + (stacks - 1) * 0.12), scale)
		bleed_sprite.modulate = Color(1, 1, 1, bleed_strength * minf(0.65 + stacks * 0.1, 1.0))
		if bleed_strength > 0.0:
			if not bleed_sprite.is_playing():
				bleed_sprite.play(&"play")
		else:
			bleed_sprite.pause()

func _height() -> float:
	return maxf(float(unit.health_bar_offset) / 0.65, 48.0)

func _draw() -> void:
	if not is_instance_valid(unit):
		return
	var h := _height()
	var scale := h / 128.0
	var w := clampf(h * 0.17, 12.0, 38.0)
	if active_styles.has(&"poison") or active_styles.has(&"shadow"):
		var color := Color(0.4, 0.85, 0.2, 0.5) if active_styles.has(&"poison") else Color(0.5, 0.42, 0.95, 0.45)
		for index in 5:
			var rise := fposmod(visual_time * 15.0 + index * 23, h * 0.65)
			draw_circle(Vector2(sin(index * 2.2 + visual_time) * w, -rise), 1.8 * scale, Color(color, color.a * (1 - rise / h)))
	if active_styles.has(&"nature"):
		for index in 6:
			var x := lerpf(-w * 1.1, w * 1.1, index / 5.0)
			var root := PackedVector2Array([Vector2(x * 1.3, 3), Vector2(x, -h * 0.09), Vector2(x + sin(index + visual_time) * 3, -h * 0.21)])
			draw_polyline(root, Color(0.35, 0.7, 0.28, 0.65), 1.7 * scale, true)
	if active_styles.has(&"ward"):
		var outline := PackedVector2Array()
		for index in 41:
			var angle := TAU * index / 40.0
			outline.append(Vector2(cos(angle) * w * 1.5, sin(angle) * h * 0.4 - h * 0.43))
		draw_polyline(outline, Color(0.4, 0.7, 1, 0.25 + sin(visual_time * 3) * 0.05), 1.3 * scale, true)
		SHAPES.ellipse(self, Vector2.ZERO, w * 1.6, Color(0.5, 0.8, 1, 0.3), 1.0)
	if active_styles.has(&"sleep") or active_styles.has(&"stun") or active_styles.has(&"fear"):
		for index in 3:
			var angle := visual_time * 1.8 + index * TAU / 3
			var at := Vector2(cos(angle) * w, -h * 0.94 + sin(angle) * 5 * scale)
			if active_styles.has(&"sleep"):
				draw_arc(at, 3.0 * scale, -PI * 0.7, PI * 0.7, 12, Color(0.6, 0.72, 1.0, 0.65), 1.4, true)
			else:
				draw_line(at - Vector2(3, 0) * scale, at + Vector2(3, 0) * scale, Color(1, 0.8, 0.35, 0.8), 1.4, true)
				draw_line(at - Vector2(0, 3) * scale, at + Vector2(0, 3) * scale, Color(1, 0.8, 0.35, 0.8), 1.4, true)
	if active_styles.has(&"charm"):
		for index in 2:
			var rise := fposmod(visual_time * 18.0 + index * 27, h * 0.6)
			SHAPES.heart(self, Vector2(sin(visual_time + index * PI) * w, -h * 0.5 - rise), 3.5 * scale, Color(1, 0.3, 0.6, 0.5))
