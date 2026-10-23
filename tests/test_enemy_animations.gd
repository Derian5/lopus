extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const IDS: Array[StringName] = [&"enemy.raider", &"enemy.troll_berserker", &"enemy.ogre_bonebreaker", &"enemy.summoner", &"enemy.troll_priest", &"enemy.bog_spawn", &"enemy.iron_warden", &"enemy.bog_king"]
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var army: Array[CombatUnitSnapshot] = []
	for id in IDS:
		army.append(CombatSnapshotBuilder.build_enemy(registry.get_definition(id), String(id), String(id), registry))
	var dummy := CombatUnitSnapshot.new()
	dummy.runtime_id = "target"
	dummy.stats.max_hp = 100000.0
	var session: CombatSession = SESSION.instantiate()
	session.vfx_enabled = false
	root.add_child(session)
	session.setup([dummy], army, 97101)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	var target := session.get_combatant_by_runtime_id("target")
	for id in IDS:
		var unit := session.get_combatant_by_runtime_id(String(id))
		_check_frames(unit)
		_check_attack(unit, target)
	var warden := session.get_combatant_by_runtime_id("enemy.iron_warden")
	warden.current_hp = warden.get_effective_stat(&"max_hp") * 0.3
	warden.velocity = Vector2(100, 0)
	warden.state = Combatant.State.ATTACK_RECOVERY
	warden._try_threshold_guard()
	warden._process(0.0)
	_check(not warden.shields.is_empty() and warden.queued_reactive_skill and warden.unit_sprite.animation == &"move", "Iron Resolve applies its shield while moving and queues only the visual, rather than making the boss slide in a cast pose.")
	warden.velocity = Vector2.ZERO
	warden._process(0.0)
	_check(not warden.shields.is_empty() and warden.unit_sprite.animation == &"skill", "Iron Resolve applies its shield immediately and plays the authored spell, even during basic recovery.")
	for unit in session.combatants:
		if unit == target:
			continue
		unit.unit_sprite.flip_h = true
		unit.force_die(null, &"test.enemy_death")
		unit._process(0.0)
		_check(unit.unit_sprite.animation == &"death" and unit.unit_sprite.is_playing(), "%s starts its death animation." % unit.snapshot.definition_id)
		var death_position := unit.unit_sprite.position
		unit.unit_sprite.frame = 29
		unit._update_unit_sprite_offset()
		_check(unit.unit_sprite.position.is_equal_approx(death_position), "Death retains its original origin instead of re-centring the falling body.")
		target.position.x = unit.position.x + 200
		unit._process(0.0)
		_check(unit.unit_sprite.flip_h and not unit.overhead.visible, "A corpse preserves its facing and hides overhead indicators.")
	session.free()
	if failures == 0:
		print("Enemy animation tests passed: all 8 enemies, 750 frames, visible sizes, mirrored anchors, impact timing, late presentation, reactive spell and falling corpses.")
	quit(1 if failures else 0)

func _check_frames(unit: Combatant) -> void:
	var sprite := unit.unit_sprite
	_check(sprite.visible and unit.placeholder_medallion == null and not unit.unit_sprite_uses_chroma_key, "%s uses transparent animated art instead of a placeholder." % unit.snapshot.definition_id)
	var heights: Array[float] = []
	for frame in 30:
		var image := sprite.sprite_frames.get_frame_texture(&"move", frame).get_image()
		heights.append(_opaque_height(image) * unit.unit_sprite_base_scale)
	heights.sort()
	var definition := root.get_node("ContentRegistry").get_definition(unit.snapshot.definition_id) as EnemyDefinition
	var expected_height := 192.0 if definition.tags.has(&"ogre") else 128.0
	_check(absf(heights[15] - expected_height) < 4.0, "%s has %.1fpx visible walking height, expected %.1f." % [unit.snapshot.definition_id, heights[15], expected_height])
	for animation in sprite.sprite_frames.get_animation_names():
		_check(sprite.sprite_frames.get_frame_count(animation) == 30, "%s has all 30 %s frames." % [unit.snapshot.definition_id, animation])
		_check(sprite.sprite_frames.get_animation_loop(animation) == (animation == &"move"), "Only walking loops.")
		sprite.animation = animation
		for frame in 30:
			sprite.frame = frame
			for left in [false, true]:
				sprite.flip_h = left
				unit._update_unit_sprite_offset()
				_check(unit.body_anchor_offset().is_equal_approx(unit.unit_sprite_ground_offset), "%s / %s / %d keeps its body anchor planted in either facing." % [unit.snapshot.definition_id, animation, frame])
	_check(unit.unit_sprite_frame_offsets[&"attack"][0] != unit.unit_sprite_frame_offsets[&"attack"][16], "Attack correction follows the body inside the animation, rather than using one fixed offset.")

func _check_attack(unit: Combatant, target: Combatant) -> void:
	unit.position = Vector2(500, 400)
	target.position = Vector2(560, 400)
	unit.target = target
	unit.state = Combatant.State.ACQUIRE_TARGET
	unit.velocity = Vector2.ZERO
	unit._start_attack()
	unit._process(0.0)
	var sprite := unit.unit_sprite
	var fps := sprite.sprite_frames.get_animation_speed(&"attack")
	var windup := float(unit.unit_sprite_attack_impact_frame + 1) / (fps * sprite.speed_scale)
	_check(unit.attack_committed and sprite.animation == &"attack" and is_equal_approx(windup, unit.windup_duration), "%s impact fitted to windup: state=%s, animation=%s, impact=%d, duration=%f/%f, committed=%s." % [unit.snapshot.definition_id, unit.state, sprite.animation, unit.unit_sprite_attack_impact_frame, windup, unit.windup_duration, unit.attack_committed])
	var rng_before: int = unit.session.combat_rng.state
	unit._process(0.037)
	_check(unit.session.combat_rng.state == rng_before and unit.attack_committed, "Presentation neither consumes seeded combat RNG nor delivers the attack.")
	unit._update_attack_windup(unit.windup_duration + 0.001)
	unit._process(0.0)
	_check(sprite.frame == unit.unit_sprite_attack_impact_frame and unit.state == Combatant.State.ATTACK_RECOVERY, "Recovery begins at the impact pose without restarting the windup.")
	unit.presented_attack_serial = -1
	unit._process(0.0)
	_check(sprite.frame == unit.unit_sprite_attack_impact_frame, "A missed presentation windup still shows the correct impact/recovery pose.")
	unit.velocity = Vector2(-100, 0)
	unit._process(0.0)
	_check(sprite.animation == &"move" and sprite.flip_h, "A moving enemy walks and faces its travel direction.")
	unit.velocity = Vector2.ZERO

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _opaque_height(image: Image) -> float:
	var top := image.get_height()
	var bottom := -1
	var bounds := image.get_used_rect()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x, 2):
			if image.get_pixel(x, y).a >= 0.5:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				break
	return float(maxi(0, bottom - top + 1))
