extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const VFX := preload("res://combat/vfx/combat_vfx.gd")
const RANGED: Array[StringName] = [&"job.archer", &"job.priest", &"job.summoner", &"enemy.summoned_shooter", &"hero.control_savant", &"hero.army_support", &"hero.iron_oracle", &"enemy.summoner", &"enemy.troll_priest"]
var registry: Node
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_emission_points()
	await _test_fire_lifecycle()
	var plain := _replay(false)
	var rendered := _replay(true)
	_check(plain == rendered, "Real ranged Heroes replay identically with and without presentation ticks.")
	if failures == 0:
		print("Combat VFX tests passed: 9 calibrated emitters, firing poses, mirrored/renderer-independent origins, fire arrows, burn lifecycle/light budget, VFX opt-out and seeded replay.")
	quit(1 if failures else 0)

func _snapshot(id: StringName, runtime_id: String) -> CombatUnitSnapshot:
	if String(id).begins_with("job."):
		var soldier := SoldierState.new()
		soldier.unique_id = runtime_id
		soldier.current_job_id = id
		return CombatSnapshotBuilder.build_soldier(soldier, null, registry)
	if String(id).begins_with("hero."):
		var hero := HeroState.new()
		hero.unique_id = runtime_id
		hero.definition_id = id
		return CombatSnapshotBuilder.build_hero(hero, InventoryState.new(), registry)
	return CombatSnapshotBuilder.build_enemy(registry.get_definition(id), runtime_id, String(id), registry)

func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot], visual: bool) -> CombatSession:
	var session: CombatSession = SESSION.instantiate()
	session.vfx_enabled = visual
	session.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1400, 800)
	root.add_child(session)
	session.setup(players, enemies, 97921)
	_check(session.combatants.size() == players.size() + enemies.size(), "The VFX fixture builds every combatant successfully.")
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	return session

func _test_emission_points() -> void:
	var army: Array[CombatUnitSnapshot] = []
	for id in RANGED:
		army.append(_snapshot(id, String(id)))
	var session := _session(army, [_snapshot(&"enemy.raider", "target")], false)
	var target := session.get_combatant_by_runtime_id("target")
	for id in RANGED:
		var source := session.get_combatant_by_runtime_id(String(id))
		source.position = Vector2(400, 400)
		target.position = Vector2(1000, 400)
		var config: Dictionary = Combatant.UNIT_ANIMATION_CONFIGS[id]
		var frame := int(config.get("projectile_frame", config.get("attack_impact_frame", 0)))
		var sprite := source.unit_sprite
		sprite.animation = &"attack"
		sprite.frame = frame
		sprite.flip_h = false
		source._update_unit_sprite_offset()
		var texture := sprite.sprite_frames.get_frame_texture(&"attack", frame)
		var drawn_tip: Vector2 = source.position + sprite.position + (Vector2(config.projectile_tip) - texture.get_size() * 0.5) * sprite.scale
		var origin := source.basic_projectile_origin(target)
		_check(origin.distance_to(drawn_tip) < 0.05, "%s launches at the weapon/hand/mouth of its authored release frame." % id)
		for pose in [&"move", &"attack"]:
			sprite.animation = pose
			sprite.frame = 0
			sprite.flip_h = true
			source._update_unit_sprite_offset()
			_check(source.basic_projectile_origin(target).is_equal_approx(origin), "Emission must not depend on renderer frame, animation or facing.")
		sprite.hide()
		_check(source.basic_projectile_origin(target).is_equal_approx(origin), "Hiding a rendered sprite does not change its gameplay emission point.")
		sprite.show()
		target.position = Vector2(-200, 400)
		var mirrored := source.basic_projectile_origin(target)
		_check(is_equal_approx(mirrored.y, origin.y) and is_equal_approx(mirrored.x - source.position.x, -(origin.x - source.position.x)), "Emission mirrors exactly when shooting left.")
		target.position = source.position + Vector2(35, 0)
		_check((source.basic_projectile_origin(target) - source.position).x <= 35.0, "A nearby target cannot make the projectile launch behind it and fly backwards.")
		_check(source.status_vfx == null, "The Balance Lab does not create persistent VFX nodes.")
	session.free()

func _test_fire_lifecycle() -> void:
	var archer := _snapshot(&"job.archer", "archer")
	var fire := registry.get_definition(&"ability.archer_professionalism_fire_arrow_tier_2") as AbilityDefinition
	archer.abilities.append(fire)
	var enemy := _snapshot(&"enemy.raider", "burn-target")
	enemy.stats.max_hp = 10000.0
	var session := _session([archer], [enemy], true)
	var source := session.get_combatant_by_runtime_id("archer")
	var target := session.get_combatant_by_runtime_id("burn-target")
	source.position = Vector2(400, 400)
	target.position = Vector2(900, 400)
	source.target = target
	source._start_attack()
	source._update_attack_windup(source.windup_duration + 0.001)
	source._process(0.0)
	var shot := session.get_node("Projectiles").get_child(0) as CombatProjectile
	_check(shot.vfx_id == &"fire_arrow" and shot.vfx_sprite != null and shot.get_child_count() >= 2, "Fire Arrow is a real arrow with an attached light rather than a generic magic orb.")
	_check(shot.position.is_equal_approx(source.basic_projectile_origin(target)) and source.unit_sprite.frame == source.unit_sprite_attack_impact_frame, "The arrow launches from the release pose when damage delivery begins.")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
	shot.position = target.position
	shot._physics_process(0.01)
	_check(target.has_status(&"status.archer_professionalism_burn"), "The styled arrow still applies the real burn mechanic.")
	target.status_vfx._process(0.2)
	_check(target.status_vfx.active_styles.has(&"fire") and target.status_vfx.burn_light != null and target.status_vfx.fire_strength > 0.0, "Burning enemies have persistent flames and a warm point light.")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
	var hp := target.current_hp
	var duration := target.statuses[0].remaining_duration
	var rng := session.combat_rng.state
	for index in 5:
		target.status_vfx._process(0.1)
	_check(target.current_hp == hp and target.statuses[0].remaining_duration == duration and session.combat_rng.state == rng, "Flames and flicker never tick damage, advance status duration or draw gameplay RNG.")
	var burn := (fire.effects[1] as ApplyStatusEffect).status
	for index in 10:
		var copy := enemy.duplicate_snapshot()
		copy.runtime_id = "extra-burn-%d" % index
		var extra := session._spawn_combatant(copy, Vector2(950, 400), session.get_arena_bounds())
		extra.set_simulation_active(false)
		extra.apply_status(burn, source, fire.id)
		extra.status_vfx._process(0.2)
	_check(VFX.status_lights <= VFX.MAX_STATUS_LIGHTS, "Mass ignition respects the persistent-light budget.")
	target.remove_status(burn.id)
	target.status_vfx.refresh()
	target.status_vfx._process(0.3)
	_check(not target.status_vfx.active_styles.has(&"fire") and target.status_vfx.burn_light == null, "Cleansing a burn fades its flames and removes its light.")
	target.apply_status(burn, source, fire.id)
	target._update_runtime(5.0)
	target.status_vfx.refresh()
	target.status_vfx._process(0.3)
	_check(not target.has_status(burn.id) and target.status_vfx.burn_light == null, "Natural burn expiry also clears presentation.")
	session.vfx_enabled = false
	var effects_before := session.get_node("Effects").get_child_count()
	session.spawn_ability_projectile(source, target, fire)
	var invisible := session.get_node("Projectiles").get_child(-1) as CombatProjectile
	_check(invisible.vfx_sprite == null and session.get_node("Effects").get_child_count() == effects_before, "Disabling VFX keeps projectiles functional without creating visual effects.")
	session.free()
	await process_frame
	_check(VFX.status_lights == 0, "Leaving/restarting combat releases all persistent light slots.")

func _replay(render_ticks: bool) -> Array:
	var heroes: Array[CombatUnitSnapshot] = []
	for id in [&"hero.control_savant", &"hero.army_support", &"hero.iron_oracle"]:
		heroes.append(_snapshot(id, String(id)))
	var enemies: Array[CombatUnitSnapshot] = []
	for index in 2:
		var enemy := _snapshot(&"enemy.raider", "replay-enemy-%d" % index)
		enemy.stats.max_hp = 180
		enemy.stats.damage = 4
		enemy.abilities.clear()
		enemies.append(enemy)
	var session := _session(heroes, enemies, false)
	for unit in session.combatants:
		unit.set_simulation_active(true)
	var simulator := RunSimulator.new(self)
	simulator._take_manual_control(session)
	for step in 7200:
		if not session.battle_active:
			break
		simulator._step(session)
		if render_ticks:
			for unit in session.combatants:
				unit._process(0.023)
	_check(not session.battle_active and not session.last_battle_timed_out, "The calibrated ranged battle completes.")
	var result: Array = [session.last_winner, session.elapsed_time]
	for event in session.events:
		result.append([event.timestamp, event.event_type, event.source_id, event.target_id, event.ability_id, event.value])
	session.free()
	return result

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
