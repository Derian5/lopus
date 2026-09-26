extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")
const ENEMY_COUNTS: Array[int] = [5, 6, 8, 10, 12, 14, 16, 18, 20, 12]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	_test_damage_formula()
	_test_ranged_attack_rhythm()
	_test_reinforcement_waves()
	await _test_reinforcement_encounter_integration()
	Engine.time_scale = 20.0

	var representative_duration := 0.0
	for battle_index in ENEMY_COUNTS.size():
		var enemy_count := ENEMY_COUNTS[battle_index]
		var ranged_count := enemy_count / 3
		var melee_count := enemy_count - ranged_count
		var session: CombatSession = SESSION_SCENE.instantiate()
		session.set_anchors_preset(Control.PRESET_TOP_LEFT)
		session.size = Vector2(1600.0, 800.0)
		root.add_child(session)
		session.setup(
			CombatDemoFactory.create_player_army(3, 9),
			CombatDemoFactory.create_enemy_army(melee_count, ranged_count),
			1000 + battle_index
		)
		await _wait_for_battle(session, battle_index)
		_check(not session.last_battle_timed_out, "Battle %d did not reach the simulation time limit." % battle_index)
		_check(session.last_winner in [&"player", &"enemy"], "Battle %d produced a valid winner." % battle_index)
		_check(session.elapsed_time > 0.0 and session.elapsed_time <= 120.0, "Battle %d has a valid duration." % battle_index)
		_validate_event_statistics(session, battle_index)

		if enemy_count == 12 and representative_duration == 0.0:
			representative_duration = session.elapsed_time
			session.restart_battle()
			await _wait_for_battle(session, 100 + battle_index)
			_check(not session.last_battle_timed_out, "Restarted battle completed without timeout.")

		print("Battle %02d: 12 vs %02d, winner=%s, duration=%.1f" % [
			battle_index + 1,
			enemy_count,
			session.last_winner,
			session.elapsed_time,
		])
		session.free()

	_check(
		representative_duration >= 30.0 and representative_duration <= 90.0,
		"Representative 12 vs 12 battle lasts 30-90 seconds (actual %.1f)." % representative_duration
	)

	Engine.time_scale = 1.0
	if failures == 0:
		print("Combat Gate 1 tests passed.")
		quit()
	else:
		push_error("Combat Gate 1 tests failed: %d" % failures)
		quit(1)


func _wait_for_battle(session: CombatSession, battle_index: int) -> void:
	var real_start := Time.get_ticks_msec()
	while session.battle_active:
		await process_frame
		if Time.get_ticks_msec() - real_start > 15000:
			_fail("Battle %d exceeded the watchdog at simulation time %.1f." % [battle_index, session.elapsed_time])
			return


func _test_damage_formula() -> void:
	_check(is_equal_approx(CombatRules.calculate_damage(100.0, 0.0), 100.0), "Zero armor preserves damage.")
	_check(is_equal_approx(CombatRules.calculate_damage(100.0, 100.0), 50.0), "100 armor halves damage.")
	_check(is_equal_approx(CombatRules.calculate_damage(-10.0, 0.0), 0.0), "Negative raw damage is clamped.")


func _test_ranged_attack_rhythm() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var ranged := _unit_snapshot("ranged-test", CombatUnitSnapshot.Team.PLAYER, &"ranged")
	ranged.stats.attack_speed = 2.0
	ranged.stats.attack_range = 300.0
	ranged.stats.movement_speed = 120.0
	var melee := _unit_snapshot("melee-test", CombatUnitSnapshot.Team.ENEMY, &"melee")
	session.setup([ranged], [melee], 1234)
	var attacker := session.combatants[0]
	var target := session.combatants[1]
	attacker.position = Vector2(500.0, 300.0)
	target.position = Vector2(560.0, 300.0)
	target.set_simulation_active(false)
	attacker.target = target
	attacker.state = Combatant.State.MOVE_INTO_RANGE
	attacker._move_toward_target(0.016)
	_check(attacker.state == Combatant.State.ATTACK_WINDUP and is_equal_approx(attacker.windup_duration, 0.1), "Ranged units stop for exactly 0.1 seconds when an attack is ready.")
	attacker._update_attack_windup(0.1)
	_check(attacker.state == Combatant.State.ATTACK_RECOVERY and is_equal_approx(attacker.state_timer, 0.4), "Ranged recovery preserves the attack-speed interval after the 0.1 second pause.")
	attacker._update_attack_recovery(0.05)
	_check(attacker.velocity.dot(target.position - attacker.position) < 0.0, "A ranged unit resumes retreating while its attack recovers.")
	session.free()


func _test_reinforcement_waves() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var player := _unit_snapshot("reinforcement-player", CombatUnitSnapshot.Team.PLAYER, &"melee")
	var initial := _unit_snapshot("reinforcement-initial", CombatUnitSnapshot.Team.ENEMY, &"melee")
	var reinforcements: Array[CombatUnitSnapshot] = []
	for index in 4:
		reinforcements.append(_unit_snapshot("reinforcement-%d" % index, CombatUnitSnapshot.Team.ENEMY, &"melee"))
	session.setup(
		[player],
		[initial],
		4321,
		reinforcements,
		0,
		EncounterDefinition.ReinforcementEntryDirection.ALL_SIDES
	)
	var player_unit := session.get_combatant_by_runtime_id(player.runtime_id)
	player_unit.set_simulation_active(false)
	_check(not session.statistics.unit_stats.has("reinforcement-0"), "Pending reinforcements are absent from combat statistics.")
	session.get_combatant_by_runtime_id(initial.runtime_id).take_damage(20000.0, player_unit)
	session._check_battle_end()
	_check(session.battle_active and session.reinforcements_spawned, "Threshold zero spawns reinforcements before the initial enemy group can end the battle.")
	_check(session.statistics.get_event_count(CombatEvent.REINFORCEMENTS_SPAWNED) == 1, "A reinforcement group emits exactly one spawn event.")
	_check(session.statistics.get_event_count(CombatEvent.BATTLE_FINISHED) == 0, "The first enemy group does not emit a premature battle finish.")
	var bounds := session.get_arena_bounds()
	var entered_sides: Dictionary = {}
	for index in 4:
		var reinforcement := session.get_combatant_by_runtime_id("reinforcement-%d" % index)
		reinforcement.set_simulation_active(false)
		if is_equal_approx(reinforcement.position.x, bounds.end.x - CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["right"] = true
		if is_equal_approx(reinforcement.position.y, bounds.end.y - CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["bottom"] = true
		if is_equal_approx(reinforcement.position.x, bounds.position.x + CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["left"] = true
		if is_equal_approx(reinforcement.position.y, bounds.position.y + CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["top"] = true
	_check(entered_sides.size() == 4, "All-sides reinforcements are distributed across every arena edge.")
	for index in 4:
		session.get_combatant_by_runtime_id("reinforcement-%d" % index).take_damage(20000.0, player_unit)
	session._check_battle_end()
	_check(not session.battle_active and session.last_winner == &"player", "The battle ends only after the reinforcement group is defeated.")
	_check(session.statistics.get_event_count(CombatEvent.BATTLE_FINISHED) == 1, "The complete reinforcement battle emits one finish event.")
	session.restart_battle()
	_check(not session.reinforcements_spawned and session.combatants.size() == 2, "Restart removes reinforcements and rearms their trigger.")
	session.free()

	var right_session: CombatSession = SESSION_SCENE.instantiate()
	right_session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	right_session.size = Vector2(1200.0, 600.0)
	root.add_child(right_session)
	var initial_group: Array[CombatUnitSnapshot] = []
	for index in 3:
		initial_group.append(_unit_snapshot("right-initial-%d" % index, CombatUnitSnapshot.Team.ENEMY, &"melee"))
	var right_reinforcements: Array[CombatUnitSnapshot] = [
		_unit_snapshot("right-reinforcement-0", CombatUnitSnapshot.Team.ENEMY, &"melee"),
		_unit_snapshot("right-reinforcement-1", CombatUnitSnapshot.Team.ENEMY, &"melee"),
	]
	right_session.setup(
		[player],
		initial_group,
		4322,
		right_reinforcements,
		2,
		EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE
	)
	var right_player := right_session.get_combatant_by_runtime_id(player.runtime_id)
	right_player.set_simulation_active(false)
	right_session.get_combatant_by_runtime_id("right-initial-0").take_damage(20000.0, right_player)
	right_session._check_battle_end()
	var right_x := right_session.get_arena_bounds().end.x - CombatSession.REINFORCEMENT_EDGE_INSET
	_check(right_session.reinforcements_spawned, "Threshold two spawns reinforcements when two initial enemies remain.")
	_check(
		is_equal_approx(right_session.get_combatant_by_runtime_id("right-reinforcement-0").position.x, right_x)
		and is_equal_approx(right_session.get_combatant_by_runtime_id("right-reinforcement-1").position.x, right_x),
		"Right-side reinforcements enter only from the right arena edge."
	)
	right_session.free()


func _test_reinforcement_encounter_integration() -> void:
	var run := DemoRunFactory.create_starting_run(4330)
	run.current_act = 1
	run.encounter_index = 1
	run.available_encounter_ids = [&"encounter.reinforced_assault"]
	EncounterService.select_encounter(run, &"encounter.reinforced_assault")
	run.run_phase = &"combat"
	var combat = COMBAT_SCENE.instantiate()
	combat.setup_run(run, 4330)
	root.add_child(combat)
	await process_frame
	await process_frame
	var definition := root.get_node("ContentRegistry").get_definition(&"encounter.reinforced_assault") as EncounterDefinition
	_check(combat.current_encounter == definition and definition.has_reinforcements(), "Combat recognizes reinforcement settings on a standard Encounter definition.")
	_check(
		combat.combat_session.reinforcement_snapshots.size() == definition.reinforcement_enemy_ids.size()
		and combat.combat_session.reinforcement_alive_threshold == definition.reinforcement_alive_threshold
		and combat.combat_session.reinforcement_entry_direction == definition.reinforcement_entry_direction,
		"Combat passes reinforcement content settings into the runtime session."
	)
	combat.free()


func _unit_snapshot(runtime_id: String, team: CombatUnitSnapshot.Team, attack_type: StringName) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.attack_type = attack_type
	snapshot.stats.max_hp = 10000.0
	snapshot.stats.damage = 1.0
	return snapshot


func _validate_event_statistics(session: CombatSession, battle_index: int) -> void:
	_check(session.statistics.get_event_count(CombatEvent.ATTACK_STARTED) > 0, "Battle %d records attacks." % battle_index)
	_check(session.statistics.get_event_count(CombatEvent.DAMAGE_APPLIED) > 0, "Battle %d records damage." % battle_index)
	_check(session.statistics.get_event_count(CombatEvent.UNIT_DIED) > 0, "Battle %d records deaths." % battle_index)
	_check(session.statistics.get_event_count(CombatEvent.BATTLE_FINISHED) == 1, "Battle %d records one finish event." % battle_index)

	var damage_from_events := 0.0
	var contribution_damage_from_events := 0.0
	var alive: Dictionary = {}
	var teams: Dictionary = {}
	for runtime_id in session.statistics.unit_stats:
		alive[runtime_id] = true
		teams[runtime_id] = int(session.statistics.unit_stats[runtime_id].team)
	for event in session.events:
		if event.event_type == CombatEvent.DAMAGE_APPLIED:
			damage_from_events += maxf(0.0, event.value)
			if alive.get(event.source_id, false) and teams.has(event.source_id) and teams.has(event.target_id) and teams[event.source_id] != teams[event.target_id]:
				contribution_damage_from_events += maxf(0.0, event.value)
		elif event.event_type == CombatEvent.UNIT_DIED:
			_check(not event.source_id.is_empty(), "Battle %d death has a killer." % battle_index)
			_check(not String(event.effect_id).is_empty(), "Battle %d death has a last effect." % battle_index)
			alive[event.target_id] = false

	var damage_from_statistics := 0.0
	var damage_taken_from_statistics := 0.0
	for data: Dictionary in session.statistics.unit_stats.values():
		damage_from_statistics += float(data.damage_dealt)
		damage_taken_from_statistics += float(data.damage_taken)
	_check(
		is_equal_approx(contribution_damage_from_events, damage_from_statistics),
		"Battle %d contribution damage matches eligible combat events." % battle_index
	)
	_check(
		is_equal_approx(damage_from_events, damage_taken_from_statistics),
		"Battle %d diagnostic damage taken matches all damage events." % battle_index
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
