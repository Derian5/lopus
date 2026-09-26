extends SceneTree


const COMBAT_SCENE := preload("res://combat/combat.tscn")
const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_death_and_transaction()
	await _test_management_ui()
	await _test_soldier_only_victory()
	if failures == 0:
		print("Stage 13 Resurrection tests passed.")
		quit()
	else:
		push_error("Stage 13 tests failed: %d" % failures)
		quit(1)


func _test_death_and_transaction() -> void:
	var run := DemoRunFactory.create_starting_run(13001)
	EncounterService.select_encounter(run, &"encounter.training_skirmish")
	run.run_phase = &"combat"
	var hero := run.heroes[0]
	hero.item_ids.append(StringName(run.inventory.items[0].instance_id))
	var retained_abilities := hero.ability_ids.duplicate()
	var retained_items := hero.item_ids.duplicate()
	var result := CombatResult.new()
	result.result_id = "stage13-hero-death"
	result.winner = &"player"
	result.encounter_id = run.selected_encounter_id
	result.unit_statistics = [_unit_data(hero.unique_id, "Fallen Hero", CombatUnitSnapshot.UnitKind.HERO, false)]
	_check(CombatResultApplicator.apply(result, run, registry), "A result containing a Hero death applies.")
	_check(hero.life_state == HeroState.DEAD and is_zero_approx(hero.current_hp), "A Hero death persists the Dead state and zero HP.")
	_check(hero.ability_ids == retained_abilities and hero.item_ids == retained_items and run.heroes.has(hero), "A Dead Hero retains its slot, build, and equipment.")
	var next_army := CombatSnapshotBuilder.build_player_army(run, registry)
	var includes_dead_hero := next_army.any(func(snapshot: CombatUnitSnapshot) -> bool: return snapshot.runtime_id == hero.unique_id)
	_check(not includes_dead_hero and next_army.size() == run.soldiers.size() + 2, "Dead Heroes are excluded from the next combat snapshot.")

	var restored := RunState.from_dictionary(run.to_dictionary())
	_check(restored.heroes[0].life_state == HeroState.DEAD and restored.heroes[0].item_ids == retained_items, "Dead Hero state and build survive serialization.")
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	_check(progression.resurrection_cost == 150, "The fixed Resurrection price comes from balance data.")
	restored.run_phase = &"management"
	restored.gold = progression.resurrection_cost - 1
	var before := restored.to_dictionary()
	var poor_result := ResurrectionService.resurrect(restored, restored.heroes[0].unique_id, registry)
	_check(not poor_result.ok and restored.to_dictionary() == before, "Insufficient Gold rejects Resurrection without partial mutation.")

	restored.heroes[0].life_state = HeroState.EXECUTED
	restored.gold = progression.resurrection_cost
	var executed_before := restored.to_dictionary()
	var executed_result := ResurrectionService.resurrect(restored, restored.heroes[0].unique_id, registry)
	_check(not executed_result.ok and restored.to_dictionary() == executed_before, "An Executed Hero cannot be resurrected.")

	restored.heroes[0].life_state = HeroState.DEAD
	var expected_hp := CombatSnapshotBuilder.build_hero(restored.heroes[0], restored.inventory, registry).stats.max_hp
	var gold_before := restored.gold
	var resurrected := ResurrectionService.resurrect(restored, restored.heroes[0].unique_id, registry)
	_check(resurrected.ok and restored.gold == gold_before - progression.resurrection_cost, "Resurrection atomically spends its Gold cost.")
	_check(restored.heroes[0].life_state == HeroState.ALIVE and is_equal_approx(restored.heroes[0].current_hp, expected_hp), "Resurrection restores Alive state and full HP.")
	var after_success := restored.to_dictionary()
	_check(not ResurrectionService.resurrect(restored, restored.heroes[0].unique_id, registry).ok and restored.to_dictionary() == after_success, "The same Hero cannot be resurrected twice.")


func _test_management_ui() -> void:
	var run := DemoRunFactory.create_starting_run(13002)
	run.heroes[0].life_state = HeroState.DEAD
	run.heroes[1].life_state = HeroState.EXECUTED
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	var actions: Array[StringName] = []
	screen.run_state_changed.connect(func(action: StringName) -> void: actions.append(action))
	await process_frame
	await process_frame
	_check(screen.get_node("%ResurrectionRows").get_child_count() == 1, "Resurrection UI lists Dead Heroes and excludes Executed Heroes.")
	screen._resurrect_hero(run.heroes[0].unique_id)
	_check(actions.has(&"hero_resurrected") and run.heroes[0].life_state == HeroState.ALIVE, "Management Resurrection requests autosave after success.")
	_check(screen.get_node("%ResurrectionRows").get_child_count() == 0, "A resurrected Hero immediately leaves the Resurrection list.")
	screen.free()


func _test_soldier_only_victory() -> void:
	Engine.time_scale = 20.0
	var run := DemoRunFactory.create_starting_run(13003)
	for hero in run.heroes:
		hero.life_state = HeroState.DEAD
		hero.current_hp = 0.0
	EncounterService.select_encounter(run, &"encounter.training_skirmish")
	run.run_phase = &"combat"
	var combat = COMBAT_SCENE.instantiate()
	root.add_child(combat)
	combat.setup_run(run, 13003)
	Engine.time_scale = 20.0
	var start := Time.get_ticks_msec()
	while run.applied_combat_result_ids.is_empty():
		await process_frame
		if Time.get_ticks_msec() - start > 15000:
			_fail("Soldier-only battle exceeded watchdog.")
			break
	_check(combat.last_result != null and combat.last_result.winner == &"player", "Soldiers can win a battle without any living Heroes.")
	combat.free()
	Engine.time_scale = 1.0


func _unit_data(runtime_id: String, display_name: String, unit_kind: int, alive: bool) -> Dictionary:
	return {
		"runtime_id": runtime_id,
		"display_name": display_name,
		"team": CombatUnitSnapshot.Team.PLAYER,
		"unit_kind": unit_kind,
		"alive": alive,
		"damage_dealt": 20.0,
		"damage_taken": 100.0,
		"damage_tanked": 100.0,
		"healing": 0.0,
		"effective_healing": 0.0,
		"kills": 0,
		"deaths": 0 if alive else 1,
		"ability_uses": 0,
		"battles_survived": 0,
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
