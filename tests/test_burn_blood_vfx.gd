extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const VFX := preload("res://combat/vfx/combat_vfx.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _count(layer: Node, prefix: String) -> int:
	var result := 0
	for child in layer.get_children():
		if String(child.name).begins_with(prefix):
			result += 1
	return result

func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	for id in [&"burn_loop", &"burn_smoke", &"fire_burst", &"blood_spurt", &"blood_burst", &"bleeding_drips"]:
		var frames := VFX.get_frames(id)
		_check(frames != null and frames.get_frame_count(&"play") == int(VFX.ATLASES[id].frames), "The exported Arcada atlas is registered: %s." % id)
	var source_snapshot := CombatUnitSnapshot.new()
	source_snapshot.runtime_id = "blood-source"
	source_snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	source_snapshot.stats.max_hp = 10000
	source_snapshot.abilities.append(registry.get_definition(&"ability.item_butcher_cleaver"))
	var enemy := CombatSnapshotBuilder.build_enemy(registry.get_definition(&"enemy.raider"), "blood-target", "Ogre", registry)
	enemy.stats.max_hp = 10000
	enemy.stats.armor = 0
	var session: CombatSession = SESSION.instantiate()
	session.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1400, 800)
	root.add_child(session)
	session.setup([source_snapshot], [enemy], 98101)
	_check(session.combatants.size() == 2, "The burn/blood fixture builds both units.")
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	var source := session.get_combatant_by_runtime_id("blood-source")
	var target := session.get_combatant_by_runtime_id("blood-target")
	source.position = Vector2(450, 400)
	target.position = Vector2(700, 400)
	var effects := session.get_node("Effects")
	var before := _count(effects, "BloodHit")
	target.take_damage(25, source)
	target.take_damage(25, source)
	_check(_count(effects, "BloodHit") == before + 2, "Every damaging hit creates its own blood spray, even within one simulation frame.")
	var spray := effects.get_node("BloodHit") as AnimatedSprite2D
	_check(spray.sprite_frames == VFX.get_frames(&"blood_spurt") and (spray.material == null or (spray.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_MIX), "Blood is a normal-blended spray of drops rather than an additive red glow.")
	await process_frame
	await create_timer(0.4).timeout
	_check(session.decal_layer.get_child_count() >= 2, "Blood that lands leaves stains on the ground.")
	var fragile := enemy.duplicate_snapshot()
	fragile.runtime_id = "lethal-blood-target"
	fragile.stats.max_hp = 30
	var victim := session._spawn_combatant(fragile, Vector2(950, 400), session.get_arena_bounds())
	before = _count(effects, "BloodHit")
	victim.take_damage(100, source)
	_check(not victim.is_alive() and _count(effects, "BloodHit") == before + 1, "A lethal hit also emits blood before the target enters its death animation.")
	before = _count(effects, "BloodHit")
	target.add_shield(100, 5, source, &"test.shield", &"test.shield")
	target.take_damage(20, source)
	target.take_damage(0, source)
	_check(_count(effects, "BloodHit") == before, "Zero HP damage and fully absorbed hits do not spray blood.")
	target.shields.clear()
	before = _count(effects, "BloodHit")
	session.spawn_projectile(source, target, 25.0)
	var projectile := session.get_node("Projectiles").get_child(-1) as CombatProjectile
	projectile.position = target.position
	projectile._physics_process(0.01)
	_check(_count(effects, "BloodHit") == before + 1, "A real ranged projectile impact emits blood through the shared damage event.")
	for hit in 3:
		var damage := target.take_damage(20, source)
		source.record_successful_basic_hit(target, damage)
	_check(target.status_stacks(&"status.item_bleed") == 3, "The real Butcher's Cleaver still stacks bleeding.")
	target.status_vfx._process(0.2)
	_check(target.status_vfx.active_styles.has(&"bleed") and not target.status_vfx.active_styles.has(&"poison"), "Bleeding has a dedicated blood profile, not the poison fallback.")
	_check(target.status_vfx.bleed_sprite != null and target.status_vfx.bleed_sprite.sprite_frames == VFX.get_frames(&"bleeding_drips"), "Bleeding plays the Arcada wound-drip loop on the body.")
	before = _count(effects, "BleedPulse")
	var hp := target.current_hp
	session.elapsed_time = 1.0
	target._update_runtime(1.0)
	_check(is_equal_approx(hp - target.current_hp, 45.0), "Blood presentation does not alter three 15-damage bleeding stacks.")
	_check(_count(effects, "BleedPulse") == before + 1, "Three simultaneous bleed ticks produce one stronger pulse rather than three overlapping copies.")
	session.elapsed_time = 2.0
	target._update_runtime(1.0)
	_check(_count(effects, "BleedPulse") == before + 2, "The next real bleeding tick produces its next blood pulse.")
	var rng := session.combat_rng.state
	hp = target.current_hp
	var remaining := target.statuses[0].remaining_duration
	for frame in 5:
		target.status_vfx._process(0.1)
	_check(target.current_hp == hp and target.statuses[0].remaining_duration == remaining and session.combat_rng.state == rng, "Drip animation never advances damage, status duration or seeded randomness.")
	target.remove_status(&"status.item_bleed")
	target.status_vfx.refresh()
	target.status_vfx._process(0.3)
	_check(not target.status_vfx.bleed_sprite.visible and not target.status_vfx.bleed_sprite.is_playing(), "Cleansing bleeding fades and pauses the attached blood loop.")
	var fire := registry.get_definition(&"ability.archer_professionalism_fire_arrow_tier_2") as AbilityDefinition
	target.apply_status((fire.effects[1] as ApplyStatusEffect).status, source, fire.id)
	target.status_vfx._process(0.2)
	var burn := target.status_vfx.burn_sprite as AnimatedSprite2D
	_check(burn != null and burn.sprite_frames == VFX.get_frames(&"burn_loop") and is_zero_approx(burn.rotation), "Burning plays the Arcada flame loop on the body, not rotated projectile sprites.")
	_check(burn.material == VFX.material_for(&"burn_loop") and target.status_vfx.burn_back != null and target.status_vfx.burn_back.get_parent() == target and target.status_vfx.burn_back.get_index() == 0, "Flames glow additively, with a second fire drawn behind the unit sprite.")
	_check(target.condition_burn > 0.0, "A burning unit's sprite takes the scorched, flickering look.")
	var hits := _count(effects, "BloodHit")
	var pulses := _count(effects, "BleedPulse")
	session.elapsed_time = 3.0
	target._update_runtime(1.0)
	_check(_count(effects, "BloodHit") == hits and _count(effects, "BleedPulse") == pulses, "Ordinary burn ticks are not mistaken for physical impacts or bleeding.")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
	target._update_runtime(5.0)
	target.status_vfx.refresh()
	target.status_vfx._process(0.3)
	_check(not burn.visible and not burn.is_playing() and not target.status_vfx.burn_back.visible and target.status_vfx.burn_light == null, "Burn expiry stops the flame loops and releases their light.")
	session.vfx_enabled = false
	before = effects.get_child_count()
	target.take_damage(20, source)
	_check(effects.get_child_count() == before, "The headless simulator can suppress blood rendering without suppressing damage.")
	session.free()
	await process_frame
	_check(VFX.status_lights == 0, "Combat teardown releases burn light slots.")
	if failures == 0:
		print("Arcada burn/blood tests passed: exported atlases, every hit, shields, bleed stacks/ticks, read-only loops, cleanup and VFX opt-out.")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
