extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const ENEMY_COUNTS: Array[int] = [5, 6, 8, 10, 12, 14, 16, 18, 20, 12]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	_test_damage_formula()

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
