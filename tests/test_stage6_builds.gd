extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	_test_slot_limits()
	_test_starting_army_and_snapshots()
	_test_definition_driven_extension()
	await _test_distinct_builds()
	Engine.time_scale = 1.0
	if failures == 0:
		print("Stage 6 build and Gate 2 tests passed.")
		quit()
	else:
		push_error("Stage 6 build tests failed: %d" % failures)
		quit(1)


func _test_slot_limits() -> void:
	var hero := HeroState.new()
	for index in HeroState.MAX_ABILITY_SLOTS:
		_check(hero.equip_ability(StringName("ability.%d" % index)), "Hero ability slot %d is available." % index)
	_check(not hero.equip_ability(&"ability.overflow"), "Hero rejects a fifth ability.")
	for index in HeroState.MAX_ITEM_SLOTS:
		_check(hero.equip_item(StringName("item.%d" % index)), "Hero item slot %d is available." % index)
	_check(not hero.equip_item(&"item.overflow"), "Hero rejects a seventh item.")
	var soldier := SoldierState.new()
	_check(soldier.equip_item(&"item.one") and soldier.equip_item(&"item.two"), "Soldier has two item slots.")
	_check(not soldier.equip_item(&"item.three"), "Soldier rejects a third item.")


func _test_starting_army_and_snapshots() -> void:
	var registry := root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(6006)
	_check(run.heroes.size() == 3 and run.soldiers.size() == 9, "Starting army contains 3 heroes and 9 Militia.")
	var hero_ids: Array[StringName] = []
	for hero in run.heroes:
		hero_ids.append(hero.definition_id)
		_check(hero.ability_ids.size() == 4, "Each starting hero fills four ability slots.")
	_check(hero_ids == DemoRunFactory.HERO_IDS, "Starting heroes cover carry, support, and control roles.")

	var builds := {
		&"job.warrior": _build(&"job.warrior", &"ability.stunning_blow", [&"ability.battle_fury"]),
		&"job.archer": _build(&"job.archer", &"ability.fire_bolt", [&"ability.battle_fury"]),
		&"job.priest": _build(&"job.priest", &"ability.mending_light", []),
	}
	run.job_builds.assign(builds.values())
	for index in run.soldiers.size():
		var job_ids: Array[StringName] = [&"job.warrior", &"job.archer", &"job.priest"]
		run.soldiers[index].current_job_id = job_ids[index / 3]
	var snapshots := CombatSnapshotBuilder.build_player_army(run, registry)
	_check(snapshots.size() == 12, "Shared builder creates all 12 combat snapshots.")
	var warrior := snapshots[3]
	var archer := snapshots[6]
	var priest := snapshots[9]
	_check(warrior.job_id == &"job.warrior" and warrior.stats.armor > archer.stats.armor, "Warrior snapshot is a durable frontline build.")
	_check(archer.attack_type == &"ranged" and archer.stats.attack_range > warrior.stats.attack_range, "Archer snapshot has ranged behavior.")
	_check(priest.abilities[0].id == &"ability.mending_light", "Priest snapshot receives its selected support ability.")


func _test_definition_driven_extension() -> void:
	var registry := root.get_node("ContentRegistry")
	var enemy := EnemyDefinition.new()
	enemy.id = &"enemy.runtime_test"
	enemy.display_name = "Runtime Test Enemy"
	enemy.base_stats = StatBlock.new()
	enemy.attack_type = &"ranged"
	enemy.ability_ids = [&"ability.fire_bolt"]
	var snapshot := CombatSnapshotBuilder.build_enemy(enemy, "runtime-enemy", enemy.display_name, registry)
	_check(snapshot.attack_type == &"ranged" and snapshot.abilities[0].id == &"ability.fire_bolt", "A new enemy uses definitions and shared combat mechanisms.")
	var ability := AbilityDefinition.new()
	ability.id = &"ability.runtime_test"
	var damage := DamageEffect.new()
	damage.effect_id = &"effect.runtime_test"
	ability.effects = [damage]
	_check(ability.effects[0] is DamageEffect, "A basic ability is assembled from Resources without core code.")


func _test_distinct_builds() -> void:
	var warrior_result := await _run_build_battle(&"job.warrior", &"ability.stunning_blow")
	var archer_result := await _run_build_battle(&"job.archer", &"ability.fire_bolt")
	var duration_delta := absf(float(warrior_result.duration) - float(archer_result.duration))
	var damage_delta := absf(float(warrior_result.damage) - float(archer_result.damage))
	var baseline := maxf(minf(float(warrior_result.damage), float(archer_result.damage)), 1.0)
	_check(
		warrior_result.winner != archer_result.winner
		or abs(int(warrior_result.deaths) - int(archer_result.deaths)) >= 2
		or duration_delta >= 4.0
		or damage_delta / baseline >= 0.15,
		"Warrior and Archer builds materially change a fixed matchup."
	)
	print("Gate 2 builds: warrior=%s/%.1fs/%d losses, archer=%s/%.1fs/%d losses" % [
		warrior_result.winner, warrior_result.duration, warrior_result.deaths,
		archer_result.winner, archer_result.duration, archer_result.deaths,
	])


func _run_build_battle(job_id: StringName, active_id: StringName) -> Dictionary:
	var registry := root.get_node("ContentRegistry")
	var run := RunState.new()
	var passives: Array[StringName] = []
	if job_id != &"job.priest":
		passives.append(&"ability.battle_fury")
	run.job_builds.append(_build(job_id, active_id, passives))
	for index in 9:
		var soldier := SoldierState.new()
		soldier.unique_id = "build-soldier-%02d" % index
		soldier.generated_name = "Build Soldier %d" % index
		soldier.current_job_id = job_id
		run.soldiers.append(soldier)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1600.0, 800.0)
	root.add_child(session)
	session.setup(
		CombatSnapshotBuilder.build_player_army(run, registry),
		CombatDemoFactory.create_enemy_army(8, 4),
		6060
	)
	var real_start := Time.get_ticks_msec()
	while session.battle_active:
		await process_frame
		if Time.get_ticks_msec() - real_start > 15000:
			_fail("Gate 2 battle exceeded watchdog.")
			break
	var damage := 0.0
	var deaths := 0
	for data: Dictionary in session.statistics.unit_stats.values():
		if int(data.team) == CombatUnitSnapshot.Team.PLAYER:
			damage += float(data.damage_dealt)
			deaths += int(data.deaths)
	var result := {"winner": session.last_winner, "duration": session.elapsed_time, "damage": damage, "deaths": deaths}
	session.free()
	return result


func _build(job_id: StringName, active_id: StringName, passives: Array[StringName]) -> JobBuildState:
	var build := JobBuildState.new()
	build.job_id = job_id
	build.set_active_ability(active_id)
	build.set_passives(passives)
	return build


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
