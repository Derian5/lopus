extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	_test_slot_limits()
	_test_starting_army_and_snapshots()
	_test_hero_stat_growth()
	_test_veterancy_stat_growth()
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
	_check(not hero.equip_ability(&"ability.unowned"), "Hero cannot equip an ability before purchasing it.")
	for index in HeroState.MAX_ABILITY_SLOTS:
		var ability_id := StringName("ability.%d" % index)
		hero.unlock_ability(ability_id)
		_check(hero.equip_ability(ability_id), "Hero ability slot %d is available after ownership." % index)
	hero.unlock_ability(&"ability.overflow")
	_check(not hero.equip_ability(&"ability.overflow"), "Hero rejects a fifth ability.")
	_check(HeroState.MAX_ITEM_SLOTS == 6, "Hero has six item slots.")
	_check(not SoldierState.new().to_dictionary().has("item_ids"), "Soldiers have no equipment state.")


func _test_starting_army_and_snapshots() -> void:
	var registry := root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(6006)
	_check(run.heroes.size() == 3 and run.soldiers.size() == 9, "Starting army contains 3 heroes and 9 Militia.")
	var hero_ids: Array[StringName] = []
	for hero in run.heroes:
		hero_ids.append(hero.definition_id)
		_check(hero.ability_ids.is_empty() and hero.owned_ability_ids.is_empty(), "Each starting Hero must buy abilities before equipping them.")
	_check(hero_ids == DemoRunFactory.HERO_IDS, "Starting heroes cover carry, support, and control roles.")

	var builds := {
		&"job.warrior": _build(&"job.warrior", &"", []),
		&"job.archer": _build(&"job.archer", &"", []),
		&"job.priest": _build(&"job.priest", &"", []),
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
	_check(priest.abilities.size() == 1 and priest.abilities[0].id == &"ability.priest_heal", "Three Priests have innate Heal but receive no unpurchased skill from their assignment count.")
	var summoner_soldier := SoldierState.new()
	summoner_soldier.unique_id = "summoner-test"
	summoner_soldier.generated_name = "Summoner Test"
	summoner_soldier.current_job_id = &"job.summoner"
	var summoner := CombatSnapshotBuilder.build_soldier(summoner_soldier, null, registry)
	_check(summoner.abilities.size() == 1 and summoner.abilities[0].id == &"ability.summoner_job_summon", "Summoner Job receives its innate summon without a Job build or ability slot.")


func _test_definition_driven_extension() -> void:
	var registry := root.get_node("ContentRegistry")
	var enemy := EnemyDefinition.new()
	enemy.id = &"enemy.runtime_test"
	enemy.display_name = "Runtime Test Enemy"
	enemy.base_stats = StatBlock.new()
	enemy.attack_type = &"ranged"
	enemy.ability_ids = [&"ability.enemy_summon"]
	var snapshot := CombatSnapshotBuilder.build_enemy(enemy, "runtime-enemy", enemy.display_name, registry)
	_check(snapshot.attack_type == &"ranged" and snapshot.abilities[0].id == &"ability.enemy_summon", "A new enemy uses definitions and shared combat mechanisms.")
	var ability := AbilityDefinition.new()
	ability.id = &"ability.runtime_test"
	var damage := DamageEffect.new()
	damage.effect_id = &"effect.runtime_test"
	ability.effects = [damage]
	_check(ability.effects[0] is DamageEffect, "A basic ability is assembled from Resources without core code.")


func _test_veterancy_stat_growth() -> void:
	var registry := root.get_node("ContentRegistry")
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	var original := [
		progression.veterancy_max_hp_growth_per_level,
		progression.veterancy_damage_growth_per_level,
		progression.veterancy_attack_speed_growth_per_level,
		progression.veterancy_movement_speed_growth_per_level,
		progression.veterancy_attack_range_growth_per_level,
		progression.veterancy_armor_growth_per_level,
	]
	progression.veterancy_max_hp_growth_per_level = 0.01
	progression.veterancy_damage_growth_per_level = 0.02
	progression.veterancy_attack_speed_growth_per_level = 0.03
	progression.veterancy_movement_speed_growth_per_level = 0.04
	progression.veterancy_attack_range_growth_per_level = 0.05
	progression.veterancy_armor_growth_per_level = 0.06
	var run := DemoRunFactory.create_starting_run(6010)
	var soldier := run.soldiers[0]
	var recruit := CombatSnapshotBuilder.build_soldier(soldier, null, registry)
	soldier.veterancy_level = 2
	var veteran := CombatSnapshotBuilder.build_soldier(soldier, null, registry)
	_check(is_equal_approx(veteran.stats.max_hp, recruit.stats.max_hp * 1.02), "Veterancy applies independent max HP growth.")
	_check(is_equal_approx(veteran.stats.damage, recruit.stats.damage * 1.04), "Veterancy applies independent damage growth.")
	_check(is_equal_approx(veteran.stats.attack_speed, recruit.stats.attack_speed * 1.06), "Veterancy applies independent attack speed growth.")
	_check(is_equal_approx(veteran.stats.movement_speed, recruit.stats.movement_speed * 1.08), "Veterancy applies independent movement speed growth.")
	_check(is_equal_approx(veteran.stats.attack_range, recruit.stats.attack_range * 1.10), "Veterancy applies independent attack range growth.")
	_check(is_equal_approx(veteran.stats.armor, recruit.stats.armor * 1.12), "Veterancy applies independent armor growth.")
	progression.veterancy_max_hp_growth_per_level = original[0]
	progression.veterancy_damage_growth_per_level = original[1]
	progression.veterancy_attack_speed_growth_per_level = original[2]
	progression.veterancy_movement_speed_growth_per_level = original[3]
	progression.veterancy_attack_range_growth_per_level = original[4]
	progression.veterancy_armor_growth_per_level = original[5]


func _test_hero_stat_growth() -> void:
	var registry := root.get_node("ContentRegistry")
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	var original := [
		progression.hero_max_hp_growth_per_level,
		progression.hero_damage_growth_per_level,
		progression.hero_attack_speed_growth_per_level,
		progression.hero_movement_speed_growth_per_level,
		progression.hero_attack_range_growth_per_level,
		progression.hero_armor_growth_per_level,
	]
	progression.hero_max_hp_growth_per_level = 0.01
	progression.hero_damage_growth_per_level = 0.02
	progression.hero_attack_speed_growth_per_level = 0.03
	progression.hero_movement_speed_growth_per_level = 0.04
	progression.hero_attack_range_growth_per_level = 0.05
	progression.hero_armor_growth_per_level = 0.06
	var run := DemoRunFactory.create_starting_run(6011)
	var hero := run.heroes[0]
	var level_one := CombatSnapshotBuilder.build_hero(hero, run.inventory, registry)
	hero.level = 3
	var level_three := CombatSnapshotBuilder.build_hero(hero, run.inventory, registry)
	_check(is_equal_approx(level_three.stats.max_hp, level_one.stats.max_hp * 1.02), "Hero levels apply independent max HP growth.")
	_check(is_equal_approx(level_three.stats.damage, level_one.stats.damage * 1.04), "Hero levels apply independent damage growth.")
	_check(is_equal_approx(level_three.stats.attack_speed, level_one.stats.attack_speed * 1.06), "Hero levels apply independent attack speed growth.")
	_check(is_equal_approx(level_three.stats.movement_speed, level_one.stats.movement_speed * 1.08), "Hero levels apply independent movement speed growth.")
	_check(is_equal_approx(level_three.stats.attack_range, level_one.stats.attack_range * 1.10), "Hero levels apply independent attack range growth.")
	_check(is_equal_approx(level_three.stats.armor, level_one.stats.armor * 1.12), "Hero levels apply independent armor growth.")
	progression.hero_max_hp_growth_per_level = original[0]
	progression.hero_damage_growth_per_level = original[1]
	progression.hero_attack_speed_growth_per_level = original[2]
	progression.hero_movement_speed_growth_per_level = original[3]
	progression.hero_attack_range_growth_per_level = original[4]
	progression.hero_armor_growth_per_level = original[5]


func _test_distinct_builds() -> void:
	var warrior_result := await _run_build_battle(&"job.warrior", &"")
	var archer_result := await _run_build_battle(&"job.archer", &"")
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
	run.job_builds.append(_build(job_id, active_id, []))
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
