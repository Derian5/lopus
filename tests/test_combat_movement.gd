extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_formation_spacing()
	_test_personal_space()
	_test_melee_approach_positions()
	_test_side_attack_start()
	_test_deliberate_small_pursuit()
	_test_arrival_still_requires_attack_reach()
	_test_rooted_fighter_can_attack()
	_test_ranged_retreat_hysteresis()
	_test_target_commitment()
	var first := _replay(false)
	var repeated := _replay(false)
	var with_render_ticks := _replay(true)
	_check(first == repeated and first == with_render_ticks, "Movement replays identically with the same seed, including when presentation ticks differ.")
	if failures == 0:
		print("Combat movement tests passed: spacing, soft avoidance, reserved approaches, settling, retreat hysteresis, target commitment and deterministic simulation.")
		quit()
	else:
		quit(1)


func _test_formation_spacing() -> void:
	var army: Array[CombatUnitSnapshot] = []
	for index in 9:
		army.append(_unit("soldier-%d" % index))
	var large := FormationService.automatic_positions(army, Rect2(0, 0, 1748, 798), true)
	_check(is_equal_approx(large[0].distance_to(large[1]), 96.0) and is_equal_approx(absf(large[6].x - large[0].x), 96.0), "Automatic deployment uses 96px rows and columns where the arena permits it.")
	var bounds := Rect2(20, 30, 280, 240)
	for point in FormationService.automatic_positions(army, bounds, true):
		_check(bounds.has_point(point), "Automatic spacing contracts to fit a small arena.")


func _test_personal_space() -> void:
	var summon := _unit("small")
	summon.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
	var session := _session([_unit("a"), _unit("b"), summon], [_unit("enemy", CombatUnitSnapshot.Team.ENEMY)])
	var a := session.get_combatant_by_runtime_id("a")
	var b := session.get_combatant_by_runtime_id("b")
	a.position = Vector2(300, 300)
	b.position = Vector2(360, 300)
	session.get_combatant_by_runtime_id("small").position = Vector2(1000, 500)
	session.get_combatant_by_runtime_id("enemy").position = Vector2(900, 300)
	_check(a.body_radius + b.body_radius < a.position.distance_to(b.position) and session.get_separation_vector(a).x < 0.0, "Soft ally spacing starts before physical overlap.")
	_check(is_equal_approx((a.get_node("CollisionShape2D").shape as CircleShape2D).radius, 20.16), "Personal space does not enlarge collision shapes.")
	_check(session.get_combatant_by_runtime_id("small").personal_space_radius() < a.personal_space_radius(), "Small summons use a smaller soft spacing radius.")
	a.state = Combatant.State.ATTACK_WINDUP
	b.state = Combatant.State.ATTACK_RECOVERY
	var positions := [a.position, b.position]
	session._physics_process(0.1)
	_check(a.position == positions[0] and b.position == positions[1], "Soft spacing does not continually push stationary fighters around.")
	a._move_to_navigation_point(Vector2(700, 300), 0.1)
	_check(absf(a.position.y - 300.0) > 0.1, "A moving unit sidesteps an ally directly ahead rather than marching into its back.")
	b.force_die(null, &"effect.test")
	a.position = Vector2(300, 300)
	_check(session.get_separation_vector(a).is_zero_approx(), "Corpses do not reserve soft personal space.")
	session.free()


func _test_melee_approach_positions() -> void:
	var army: Array[CombatUnitSnapshot] = []
	for index in 4:
		army.append(_unit("melee-%d" % index))
	var session := _session(army, [_unit("target", CombatUnitSnapshot.Team.ENEMY)])
	var target := session.get_combatant_by_runtime_id("target")
	target.position = Vector2(700, 300)
	var fighters: Array[Combatant] = []
	var slots := {}
	var rng_state := session.combat_rng.state
	for index in army.size():
		var unit := session.get_combatant_by_runtime_id(army[index].runtime_id)
		unit.position = Vector2(300, 260 + index * 30)
		unit.target = target
		unit.state = Combatant.State.MOVE_INTO_RANGE
		unit._move_toward_target(0.0)
		_check(unit.approach_slot_index >= 0 and not slots.has(unit.approach_slot_index), "Melee allies reserve separate approach sectors.")
		slots[unit.approach_slot_index] = true
		_check(unit.approach_goal.distance_to(target.position) <= unit.basic_attack_reach(target), "An approach point never extends authored attack reach.")
		_check(unit.is_basic_attack_side_position(target, unit.approach_goal), "Every reserved melee approach lies to the left or right of its target.")
		fighters.append(unit)
	_check(session.combat_rng.state == rng_state, "Approach allocation does not consume combat RNG.")
	var saved_goal := fighters[0].approach_goal
	target.position += Vector2(1, 1)
	fighters[0]._move_toward_target(0.0)
	_check(fighters[0].approach_goal == saved_goal, "Small target movements do not reshuffle a committed approach.")
	for unit in fighters:
		unit.set_simulation_active(true)
	for step in 600:
		for unit in fighters:
			unit._physics_process(1.0 / 60.0)
		session._physics_process(1.0 / 60.0)
		if fighters.all(func(unit: Combatant) -> bool: return unit.attack_serial > 0):
			break
	for unit in fighters:
		_check(unit.attack_serial > 0, "A reserved approach reaches an attack position: %s at %s, goal %s." % [unit.snapshot.runtime_id, unit.position, unit.approach_goal])
	# Fighters assigned to the opposite flank need time to circle the target.
	for step in 360:
		for unit in fighters:
			unit._physics_process(1.0 / 60.0)
		session._physics_process(1.0 / 60.0)
	var settled: Array[Vector2] = []
	for unit in fighters:
		settled.append(unit.position)
	for step in 60:
		for unit in fighters:
			unit._physics_process(1.0 / 60.0)
		session._physics_process(1.0 / 60.0)
	for index in fighters.size():
		_check(fighters[index].position.distance_to(settled[index]) < 0.25, "A settled melee group does not keep drifting from soft repulsion: %s, %s -> %s." % [fighters[index].snapshot.runtime_id, settled[index], fighters[index].position])
	session.free()


func _test_side_attack_start() -> void:
	var fighter := _unit("fighter")
	fighter.stats.damage = 10.0
	var session := _session([fighter], [_unit("target", CombatUnitSnapshot.Team.ENEMY)])
	var unit := session.get_combatant_by_runtime_id("fighter")
	var target := session.get_combatant_by_runtime_id("target")
	target.position = Vector2(600, 400)
	unit.target = target
	for offset in [Vector2(0, -60), Vector2(0, 60), Vector2(30, 55)]:
		unit.position = target.position + offset
		unit._start_attack()
		_check(not unit.attack_committed, "Melee cannot start a swing above or below its target.")
		unit._move_toward_target(0.0)
		_check(unit.is_basic_attack_side_position(target, unit.approach_goal), "A vertically aligned melee fighter plans a lateral approach.")
	unit.melee_retreat_source = target
	unit.melee_retreat_counterattack_pending = true
	unit._update_melee_retreat(0.0)
	_check(not unit.attack_committed, "A retreat counterattack cannot bypass the lateral restriction.")
	unit._update_frenzy(0.0)
	_check(not unit.attack_committed, "Frenzy cannot start a vertical melee swing.")
	unit.position = target.position + Vector2(-60, 0)
	unit._start_attack()
	_check(unit.attack_committed, "Melee can commit a swing from the side.")
	target.position = unit.position + Vector2(0, 200)
	var hp := target.current_hp
	unit._update_attack_windup(1.0)
	_check(target.current_hp < hp, "A committed lateral swing still hits after the target moves vertically out of range.")
	unit.snapshot.attack_type = &"ranged"
	unit._start_attack()
	_check(unit.attack_committed, "Ranged attacks remain free to start vertically.")
	session.free()


func _test_deliberate_small_pursuit() -> void:
	var session := _session([_unit("pursuer")], [_unit("target", CombatUnitSnapshot.Team.ENEMY)])
	var unit := session.get_combatant_by_runtime_id("pursuer")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(300, 300)
	target.position = Vector2(392, 300)
	unit.target = target
	unit.state = Combatant.State.MOVE_INTO_RANGE
	unit._move_toward_target(0.16)
	_check(unit.position.x - 300.0 >= 8.0 and unit.position.distance_to(target.position) < unit.basic_attack_reach(target) - 5.0, "A short pursuit commits to a useful position inside reach rather than repeatedly stepping onto the exact boundary.")
	unit._move_toward_target(0.0)
	var settled := unit.position
	for shift in [2.0, -2.0, 1.0]:
		target.position.x = 392.0 + shift
		unit._acquire_target()
		unit._move_toward_target(0.0)
		_check(unit.position == settled and unit.state == Combatant.State.ATTACK_WINDUP, "An in-range target's small movements do not provoke microsteps.")
	session.free()


func _test_arrival_still_requires_attack_reach() -> void:
	var session := _session([_unit("arrival-fighter")], [_unit("arrival-target", CombatUnitSnapshot.Team.ENEMY)])
	var unit := session.get_combatant_by_runtime_id("arrival-fighter")
	var target := session.get_combatant_by_runtime_id("arrival-target")
	target.position = Vector2(600, 400)
	var reach := unit.basic_attack_reach(target)
	unit.position = target.position + Vector2(reach + 1.0, 0)
	unit.target = target
	unit.state = Combatant.State.MOVE_INTO_RANGE
	unit.approach_target = target
	unit.approach_target_position = target.position
	unit.approach_reach = reach
	unit.approach_goal = target.position + Vector2(reach - 6.0, 0)
	unit.approach_slot_index = 0
	unit.approach_committed = true
	var before := unit.position
	for step in 120:
		unit._move_toward_target(1.0 / 60.0)
		if unit.attack_committed:
			break
	_check(unit.position.distance_to(before) > 0.5 and unit.attack_committed, "A melee fighter within arrival tolerance but outside attack reach closes the remaining gap instead of standing idle forever.")
	session.free()


func _test_rooted_fighter_can_attack() -> void:
	var session := _session([_unit("rooted")], [_unit("target", CombatUnitSnapshot.Team.ENEMY)])
	var unit := session.get_combatant_by_runtime_id("rooted")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(300, 300)
	target.position = Vector2(392, 300)
	unit.target = target
	unit.state = Combatant.State.MOVE_INTO_RANGE
	unit._move_toward_target(0.0)
	var root_status := StatusDefinition.new()
	root_status.id = &"status.test_movement_root"
	root_status.prevents_movement = true
	root_status.default_duration = 5.0
	unit.apply_status(root_status, unit, &"ability.test_root")
	target.position = Vector2(380, 300)
	unit._move_toward_target(0.0)
	_check(unit.state == Combatant.State.ATTACK_WINDUP and unit.position == Vector2(300, 300), "A rooted fighter attacks an enemy in reach instead of waiting for an unreachable reserved point.")
	session.free()


func _test_ranged_retreat_hysteresis() -> void:
	var ranged := _unit("ranged")
	ranged.attack_type = &"ranged"
	ranged.stats.attack_range = 300.0
	var session := _session([ranged], [_unit("target", CombatUnitSnapshot.Team.ENEMY)])
	var unit := session.get_combatant_by_runtime_id("ranged")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(500, 300)
	target.position = Vector2(640, 300)
	unit.target = target
	unit.state = Combatant.State.ATTACK_RECOVERY
	unit._move_ranged_during_recovery(0.1)
	var destination := unit.ranged_retreat_destination
	var before := unit.position.x
	target.position = unit.position + Vector2(175, 2)
	unit._move_ranged_during_recovery(0.1)
	_check(unit.ranged_retreat_active and unit.position.x < before and unit.ranged_retreat_destination == destination, "Crossing the entry threshold does not cancel or redirect an unfinished retreat.")
	target.position = unit.position + Vector2(245, 0)
	unit._move_ranged_during_recovery(0.1)
	_check(not unit.ranged_retreat_active and unit.velocity == Vector2.ZERO, "A ranged unit settles after reaching the larger exit distance.")
	var settled := unit.position
	for distance in [175.0, 180.0, 169.0]:
		target.position = unit.position + Vector2(distance, 0)
		unit._move_ranged_during_recovery(0.2)
		_check(unit.position == settled, "The distance band between retreat thresholds does not cause back-and-forth movement.")
	unit.position.x = unit.arena_bounds.position.x + unit.body_radius
	unit.position.y = unit.arena_bounds.get_center().y
	target.position = unit.position + Vector2(130, 0)
	unit.ranged_retreat_retry_remaining = 0.0
	unit._move_ranged_during_recovery(0.1)
	_check(not unit.ranged_retreat_active and unit.velocity == Vector2.ZERO, "A blocked retreat at the arena edge does not create fake walking or a forward lunge.")
	unit._acquire_target()
	unit._move_toward_target(0.0)
	_check(unit.state == Combatant.State.ATTACK_WINDUP, "A ranged unit can still fire when it cannot retreat.")
	session.free()


func _test_target_commitment() -> void:
	var session := _session([_unit("unit")], [_unit("current", CombatUnitSnapshot.Team.ENEMY), _unit("other", CombatUnitSnapshot.Team.ENEMY)])
	var unit := session.get_combatant_by_runtime_id("unit")
	var current := session.get_combatant_by_runtime_id("current")
	var other := session.get_combatant_by_runtime_id("other")
	unit.position = Vector2(200, 300)
	current.position = Vector2(400, 300)
	other.position = Vector2(395, 300)
	unit.target = current
	_check(session.find_basic_attack_target(unit) == current, "A tiny distance advantage does not switch a valid target.")
	other.position.x = 250
	_check(session.find_basic_attack_target(unit) == other, "A substantially better target still causes a switch.")
	unit.forced_basic_target = current
	unit.forced_basic_target_remaining = 1.0
	_check(session.find_basic_attack_target(unit) == current, "Forced targets still override normal commitment.")
	unit.forced_basic_target_remaining = 0.0
	unit.snapshot.targeting_mode = &"back_line"
	other.snapshot.attack_type = &"ranged"
	_check(session.find_basic_attack_target(unit) == other, "Back-line hunters do not stick to a frontline target when a ranged target exists.")
	session.free()


func _replay(render_ticks: bool) -> Dictionary:
	var players: Array[CombatUnitSnapshot] = []
	var enemies: Array[CombatUnitSnapshot] = []
	for index in 5:
		var unit := _unit("replay-player-%d" % index)
		unit.stats.max_hp = 250.0
		unit.stats.damage = 20.0
		if index >= 3:
			unit.attack_type = &"ranged"
			unit.stats.attack_range = 250.0
		players.append(unit)
	for index in 3:
		var unit := _unit("replay-enemy-%d" % index, CombatUnitSnapshot.Team.ENEMY)
		unit.stats.max_hp = 300.0
		unit.stats.damage = 22.0
		enemies.append(unit)
	var session := _session(players, enemies)
	var simulator := RunSimulator.new(self)
	for unit in session.combatants:
		unit.set_simulation_active(true)
	simulator._take_manual_control(session)
	for step in 3600:
		if not session.battle_active:
			break
		simulator._step(session)
		if render_ticks:
			for unit in session.combatants:
				unit._process(0.023)
	_check(not session.battle_active and not session.last_battle_timed_out, "A manually stepped battle with the new navigation completes without deadlocking.")
	var report := {"winner": String(session.last_winner), "duration": session.elapsed_time, "units": [], "events": []}
	for unit in session.combatants:
		report.units.append([unit.snapshot.runtime_id, unit.position.x, unit.position.y, unit.current_hp, unit.state])
	for event in session.events:
		report.events.append([event.timestamp, String(event.event_type), event.source_id, event.target_id, String(event.ability_id), String(event.effect_id), event.value])
	session.free()
	return report


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot]) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.vfx_enabled = false
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200, 700)
	root.add_child(session)
	session.setup(players, enemies, 77091)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	return session


func _unit(id: String, team := CombatUnitSnapshot.Team.PLAYER) -> CombatUnitSnapshot:
	var unit := CombatUnitSnapshot.new()
	unit.runtime_id = id
	unit.display_name = id
	unit.team = team
	unit.stats.max_hp = 1000.0
	unit.stats.damage = 0.0
	unit.stats.movement_speed = 100.0
	unit.stats.attack_range = 50.0
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
