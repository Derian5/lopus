extends SceneTree


const MAIN_SCENE := preload("res://main.tscn")
const ENCOUNTER_CHOICE_SCENE := preload("res://ui/encounter_choice/encounter_choice.tscn")

var failures := 0
var registry: Node
var route: RouteDefinition


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	route = registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	_test_deterministic_generation()
	_test_act_structure_and_unknown_limit()
	_test_save_state_validation()
	_test_selection_and_progression()
	await _test_management_cards()
	await _test_outcome_flow()
	if failures == 0:
		print("Stage 12 Encounter Card and run-cycle tests passed.")
		quit()
	else:
		push_error("Stage 12 tests failed: %d" % failures)
		quit(1)


func _test_deterministic_generation() -> void:
	var first := DemoRunFactory.create_starting_run(12001)
	var second := DemoRunFactory.create_starting_run(12001)
	_check(first.available_encounter_ids == second.available_encounter_ids, "Equal run seeds generate identical Encounter Cards.")
	_check(first.run_rng.to_dictionary() == second.run_rng.to_dictionary(), "Encounter generation consumes the persisted Run RNG deterministically.")
	_check(first.available_encounter_ids == [&"encounter.tutorial_volley"], "New Game uses the fixed tutorial Encounter.")
	_check(first.selected_encounter_id == &"encounter.tutorial_volley", "New Game automatically selects the tutorial Encounter.")

	var restored := RunState.from_dictionary(first.to_dictionary())
	first.current_act = 1
	first.encounter_index = 1
	restored.current_act = 1
	restored.encounter_index = 1
	var generated := EncounterService.begin_choice(first, registry)
	var restored_generated := EncounterService.begin_choice(restored, registry)
	_check(generated.ok and restored_generated.ok, "Encounter Cards generate after restoring a run.")
	_check(first.available_encounter_ids == restored.available_encounter_ids and first.run_rng.to_dictionary() == restored.run_rng.to_dictionary(), "The next Encounter choice after Load is identical.")

	var impossible := DemoRunFactory.create_starting_run(12002)
	impossible.current_act = 2
	impossible.encounter_index = 99
	var before := impossible.to_dictionary()
	var failed := EncounterService.begin_choice(impossible, registry)
	_check(not failed.ok and impossible.to_dictionary() == before, "Failed generation commits neither card state nor Run RNG draws.")
	var cycle_before := impossible.to_dictionary()
	var failed_cycle := RunCycleService.prepare_next_choice(impossible, registry)
	_check(not failed_cycle.ok and impossible.to_dictionary() == cycle_before, "Post-battle Market and Encounter generation roll back as one transaction.")


func _test_act_structure_and_unknown_limit() -> void:
	var run := DemoRunFactory.create_starting_run(12003)
	var reinforcement := registry.get_definition(&"encounter.reinforced_assault") as EncounterDefinition
	_check(
		reinforcement.has_reinforcements()
		and reinforcement.reinforcement_alive_threshold in [0, 1, 2]
		and reinforcement.reinforcement_entry_direction in [EncounterDefinition.ReinforcementEntryDirection.ALL_SIDES, EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE],
		"The reinforcement encounter exposes its trigger, entry direction, and second enemy group as content data."
	)
	var initial_snapshots := CombatDemoFactory.create_enemy_army_from_encounter(reinforcement)
	var reinforcement_snapshots := CombatDemoFactory.create_reinforcement_army_from_encounter(reinforcement)
	var scaled := CombatDemoFactory.create_enemy_army_from_encounter(reinforcement, 2.0, 6)
	var hp_steps := scaled[0].stats.breakdown_for(&"max_hp")
	var hp_text := StatBreakdownFormatter.format(&"max_hp", scaled[0].stats.max_hp, hp_steps)
	_check(
		hp_steps.size() == 3
		and hp_text.contains("Act threat (battle 6)")
		and hp_text.contains("Encounter strength: %s" % reinforcement.display_name)
		and is_equal_approx(float(hp_steps[-1].after), scaled[0].stats.max_hp),
		"Enemy stat breakdowns explain the act threat and encounter strength multipliers."
	)
	_check(initial_snapshots.size() == reinforcement.enemy_ids.size() and reinforcement_snapshots.size() == reinforcement.reinforcement_enemy_ids.size(), "Initial and reinforcement groups build independently from the encounter resource.")
	_check(initial_snapshots[0].runtime_id != reinforcement_snapshots[0].runtime_id, "Reinforcement runtime IDs cannot overwrite initial enemy statistics.")
	var invalid_reinforcement := EncounterDefinition.new()
	invalid_reinforcement.id = &"encounter.invalid_reinforcement"
	invalid_reinforcement.enemy_ids = [&"enemy.raider", &"enemy.raider", &"enemy.raider"]
	invalid_reinforcement.reinforcement_enemy_ids = [&"enemy.raider"]
	invalid_reinforcement.reinforcement_alive_threshold = 3
	_check(not registry._validate_encounter(invalid_reinforcement, false), "Content validation rejects a reinforcement threshold outside 0..2.")
	var reinforced_boss := EncounterDefinition.new()
	reinforced_boss.id = &"encounter.test_reinforced_boss"
	reinforced_boss.enemy_ids = [&"enemy.iron_warden"]
	reinforced_boss.reinforcement_enemy_ids = [&"enemy.raider"]
	reinforced_boss.reinforcement_alive_threshold = 0
	reinforced_boss.difficulty_hint = "Boss"
	reinforced_boss.key_properties = ["Test reinforced Boss"]
	reinforced_boss.is_boss = true
	_check(registry._validate_encounter(reinforced_boss, false), "Boss Encounters support the same reinforcement settings as every other Encounter.")
	for battle_index in range(1, route.act_one_boss_index()):
		run.current_act = 1
		run.encounter_index = battle_index
		var generated := EncounterService.begin_choice(run, registry)
		_check(generated.ok and run.available_encounter_ids.size() == 2, "Act I battle %d generates exactly two cards." % (battle_index + 1))
		_check(_unknown_count(run.available_encounter_ids) <= 1, "A card set contains at most one Unknown Encounter.")

	run.current_act = 1
	run.encounter_index = route.act_one_boss_index()
	var boss_generation := EncounterService.begin_choice(run, registry)
	_check(boss_generation.ok and run.available_encounter_ids.size() == 2, "The configured Act I Boss wave has two boss routes.")
	for encounter_id in run.available_encounter_ids:
		var encounter := registry.get_definition(encounter_id) as EncounterDefinition
		_check(encounter.is_boss, "Every final Act I route is a Boss Encounter.")
	var original_boss_wave := route.act_one_boss_wave
	route.act_one_boss_wave = 4
	run.encounter_index = route.act_one_boss_index()
	var configured_boss_generation := EncounterService.begin_choice(run, registry)
	_check(configured_boss_generation.ok, "Changing the route resource moves Boss card generation to the configured wave.")
	for encounter_id in run.available_encounter_ids:
		_check((registry.get_definition(encounter_id) as EncounterDefinition).is_boss, "Boss card ranges do not hardcode the Boss wave.")
	route.act_one_boss_wave = original_boss_wave

	for battle_index in route.act_two_battle_count:
		run.current_act = 2
		run.encounter_index = battle_index
		var generated := EncounterService.begin_choice(run, registry)
		_check(generated.ok and run.available_encounter_ids.size() == 2, "Act II battle %d generates exactly two cards." % (battle_index + 1))
		_check(_unknown_count(run.available_encounter_ids) <= 1, "Act II also limits Unknown Encounters to one card.")

	var act1_unknown := registry.get_definition(&"encounter.unknown_ambush") as EncounterDefinition
	var richest_known := 0
	for encounter_id in [&"encounter.raider_line", &"encounter.crossfire", &"encounter.warband", &"encounter.bolt_screen"]:
		richest_known = maxi(richest_known, (registry.get_definition(encounter_id) as EncounterDefinition).gold_reward)
	_check(act1_unknown.gold_reward > richest_known, "Unknown Encounter pays more than every normal Act I card.")


func _test_save_state_validation() -> void:
	var manager := SaveManager.new("user://tests/stage12-validation")
	var wrong_act := DemoRunFactory.create_starting_run(12030)
	wrong_act.available_encounter_ids = [&"encounter.act2_pressure", &"encounter.act2_crossbows"]
	_check(not manager._validate_run(wrong_act, registry).is_empty(), "Save validation rejects cards from the wrong Act.")
	var duplicates := DemoRunFactory.create_starting_run(12031)
	duplicates.available_encounter_ids = [&"encounter.tutorial_volley", &"encounter.tutorial_volley"]
	_check(not manager._validate_run(duplicates, registry).is_empty(), "Save validation rejects duplicate Encounter Cards.")
	var final_layer := DemoRunFactory.create_starting_run(12032)
	final_layer.encounter_index = route.act_one_boss_index()
	final_layer.available_encounter_ids = [&"encounter.raider_line", &"encounter.warden_guard"]
	_check(not manager._validate_run(final_layer, registry).is_empty(), "Save validation rejects a non-boss route in the final Act I layer.")
	var invalid_end := DemoRunFactory.create_starting_run(12033)
	invalid_end.run_status = RunState.STATUS_DEMO_COMPLETE
	invalid_end.current_act = 2
	invalid_end.encounter_index = route.act_two_battle_count - 1
	_check(not manager._validate_run(invalid_end, registry).is_empty(), "Save validation rejects an inconsistent Demo End position.")


func _test_selection_and_progression() -> void:
	var run := DemoRunFactory.create_starting_run(12004)
	run.encounter_index = 1
	_check(EncounterService.begin_choice(run, registry).ok, "A post-tutorial Encounter choice is generated.")
	var first_id := run.available_encounter_ids[0]
	var second_id := run.available_encounter_ids[1]
	_check(EncounterService.select_encounter(run, first_id).ok and run.selected_encounter_id == first_id, "A displayed Encounter Card can be selected.")
	run.encounter_committed = true
	var persisted_lock := EncounterService.select_encounter(run, second_id)
	_check(not persisted_lock.ok and run.selected_encounter_id == first_id, "A persisted pre-combat commitment prevents route switching after rollback.")
	run.encounter_committed = false
	run.run_phase = &"combat"
	var locked := EncounterService.select_encounter(run, second_id)
	_check(not locked.ok and run.selected_encounter_id == first_id, "Encounter selection is locked after combat begins.")
	run.run_phase = &"management"
	var mismatch := _victory("stage12-mismatch", second_id)
	run.run_phase = &"combat"
	var mismatch_before := run.to_dictionary()
	_check(not CombatResultApplicator.apply(mismatch, run, registry) and run.to_dictionary() == mismatch_before, "A result for anything except the locked encounter is rejected atomically.")
	run.run_phase = &"management"

	var reward_run := DemoRunFactory.create_starting_run(12040)
	var reward_id := reward_run.available_encounter_ids[0]
	EncounterService.select_encounter(reward_run, reward_id)
	reward_run.run_phase = &"combat"
	var reward_result := _victory("stage12-reward", reward_id)
	reward_result.gold_reward = 999999
	var reward_before := reward_run.gold
	var reward_definition := registry.get_definition(reward_id) as EncounterDefinition
	_check(CombatResultApplicator.apply(reward_result, reward_run, registry), "A valid locked result applies.")
	_check(reward_run.gold == reward_before + reward_definition.gold_reward, "Victory reward is derived from EncounterDefinition rather than trusted result data.")

	run.current_act = 1
	run.encounter_index = route.act_one_boss_index()
	EncounterService.begin_choice(run, registry)
	var boss_id := run.available_encounter_ids[0]
	EncounterService.select_encounter(run, boss_id)
	run.run_phase = &"combat"
	var boss_result := _victory("stage12-boss", boss_id)
	_check(CombatResultApplicator.apply(boss_result, run, registry), "Boss victory applies to the run.")
	_check(run.current_act == 1 and run.encounter_index == route.act_one_boss_index() and run.run_phase == &"execution", "Boss victory pauses the route at the mandatory Execution checkpoint.")
	var execution := ExecutionService.execute(run, run.heroes[0].unique_id, registry)
	_check(execution.ok, "Completing Execution unlocks the Act II transition.")
	if execution.ok:
		run = execution.run_state
	_check(run.current_act == 2 and run.encounter_index == 0 and run.run_status == RunState.STATUS_ACTIVE, "Execution guarantees the transition from Act I to Act II.")

	for battle_index in route.act_two_battle_count:
		run.run_phase = &"management"
		EncounterService.begin_choice(run, registry)
		var encounter_id := run.available_encounter_ids[0]
		EncounterService.select_encounter(run, encounter_id)
		run.run_phase = &"combat"
		_check(CombatResultApplicator.apply(_victory("stage12-act2-%d" % battle_index, encounter_id), run, registry), "Act II victory %d applies." % (battle_index + 1))
	_check(run.run_status == RunState.STATUS_DEMO_COMPLETE and run.encounter_index == route.act_two_battle_count, "The configured final Act II victory reaches Demo End.")

	var full_act := DemoRunFactory.create_starting_run(12041)
	for battle_index in route.act_one_boss_wave:
		var encounter_id := full_act.available_encounter_ids[0]
		EncounterService.select_encounter(full_act, encounter_id)
		full_act.run_phase = &"combat"
		_check(CombatResultApplicator.apply(_victory("stage12-full-act1-%d" % battle_index, encounter_id), full_act, registry), "Act I route battle %d applies." % (battle_index + 1))
		if full_act.run_phase == &"execution":
			var full_execution := ExecutionService.execute(full_act, full_act.heroes[0].unique_id, registry)
			_check(full_execution.ok, "The full Act I route completes its mandatory Execution.")
			if full_execution.ok:
				full_act = full_execution.run_state
		elif full_act.current_act == 1:
			full_act.run_phase = &"management"
			_check(RunCycleService.prepare_next_choice(full_act, registry).ok, "Act I route advances to its next choice.")
	_check(full_act.current_act == 2 and full_act.encounter_index == 0, "A complete Act I route always reaches Act II through its configured Boss wave.")

	var defeated := DemoRunFactory.create_starting_run(12005)
	EncounterService.select_encounter(defeated, defeated.available_encounter_ids[0])
	defeated.run_phase = &"combat"
	var defeat := CombatResult.new()
	defeat.result_id = "stage12-defeat"
	defeat.winner = &"enemy"
	defeat.encounter_id = defeated.selected_encounter_id
	var old_index := defeated.encounter_index
	_check(CombatResultApplicator.apply(defeat, defeated, registry), "A defeat result applies once.")
	_check(defeated.run_status == RunState.STATUS_DEFEAT and defeated.encounter_index == old_index, "Defeat ends the run without advancing its route.")


func _test_management_cards() -> void:
	var run := DemoRunFactory.create_starting_run(12006)
	run.current_act = 1
	run.encounter_index = 1
	run.available_encounter_ids = [&"encounter.raider_line", &"encounter.unknown_ambush"]
	run.selected_encounter_id = &""
	var screen = ENCOUNTER_CHOICE_SCENE.instantiate()
	root.add_child(screen)
	screen.set_run_state(run)
	await process_frame
	await process_frame
	_check(screen.get_node("%Cards").get_child_count() == 2, "The standalone Encounter screen displays exactly two route cards.")
	var page_text := _descendant_text(screen)
	var raider_line := registry.get_definition(&"encounter.raider_line") as EncounterDefinition
	_check(page_text.contains(raider_line.key_properties[0]) and page_text.contains("REWARD") and page_text.contains(str(raider_line.gold_reward)) and page_text.contains("Ogre Brute"), "Encounter cards expose route properties, enemy forces and rewards.")
	var selected_ids: Array[StringName] = []
	screen.encounter_selected.connect(func(encounter_id: StringName) -> void: selected_ids.append(encounter_id))
	var first_card := screen.get_node("%Cards").get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(first_card as Control).gui_input.emit(click)
	_check(selected_ids == [&"encounter.raider_line"], "Clicking a route card emits its Encounter ID for Main routing.")
	screen.free()

	var reinforcement_run := DemoRunFactory.create_starting_run(12008)
	reinforcement_run.encounter_index = 1
	reinforcement_run.available_encounter_ids = [&"encounter.reinforced_assault"]
	reinforcement_run.selected_encounter_id = &""
	var reinforcement_screen = ENCOUNTER_CHOICE_SCENE.instantiate()
	root.add_child(reinforcement_screen)
	reinforcement_screen.set_run_state(reinforcement_run)
	await process_frame
	await process_frame
	var reinforcement_text := _descendant_text(reinforcement_screen).to_lower()
	var reinforcement_definition := registry.get_definition(&"encounter.reinforced_assault") as EncounterDefinition
	var threshold_word := "enemy" if reinforcement_definition.reinforcement_alive_threshold == 1 else "enemies"
	var direction_text := "right side" if reinforcement_definition.reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE else "all sides"
	_check(
		reinforcement_text.contains("when %d %s remain" % [reinforcement_definition.reinforcement_alive_threshold, threshold_word])
		and reinforcement_text.contains(direction_text)
		and reinforcement_text.contains("ogre bonebreaker"),
		"Encounter cards reveal the reinforcement trigger, direction, and configured composition."
	)
	reinforcement_screen.free()


func _test_outcome_flow() -> void:
	var save_directory := "user://tests/stage12-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(save_directory)
	manager.delete_save()
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main.active_run = DemoRunFactory.create_starting_run(12007)
	var defeated_id: StringName = main.active_run.available_encounter_ids[0]
	EncounterService.select_encounter(main.active_run, defeated_id)
	main.active_run.run_phase = &"combat"
	var defeat := CombatResult.new()
	defeat.result_id = "stage12-outcome-defeat"
	defeat.winner = &"enemy"
	defeat.encounter_id = defeated_id
	CombatResultApplicator.apply(defeat, main.active_run, registry)
	main._on_battle_resolved(defeat)
	main.show_main_menu()
	await process_frame
	main._continue_game()
	await process_frame
	_check(main.current_screen.name == "RunOutcome" and main.current_screen.get_node("%Title").text == "RUN DEFEAT", "A resolved defeat cannot be discarded through Main Menu and Continue.")
	main.current_screen._on_new_run_pressed()
	await process_frame
	_check(main.current_screen.name == "HeroSelection" and main.active_run == null, "Run Defeat starts the current Hero Selection flow.")
	var selected_heroes: Array[StringName] = [&"hero.control_savant", &"hero.test_vanguard", &"hero.army_support"]
	main._begin_new_game(selected_heroes)
	await process_frame
	_check(main.current_screen.name == "Combat" and main.active_run.pending_event.event_id == &"event.opening_march" and main.active_run.heroes.size() == 3 and main.active_run.soldiers.size() == 9, "Selecting three Heroes after Run Defeat starts a fresh run with the opening event and nine Militia.")

	main.active_run.run_status = RunState.STATUS_DEMO_COMPLETE
	main.show_run_outcome()
	await process_frame
	_check(main.current_screen.get_node("%Eyebrow").text == "STEAM DEMO COMPLETE", "Completing the configured Act II route opens Demo End.")
	main.free()
	manager.delete_save()


func _victory(result_id: String, encounter_id: StringName) -> CombatResult:
	var result := CombatResult.new()
	result.result_id = result_id
	result.winner = &"player"
	result.encounter_id = encounter_id
	return result


func _unknown_count(encounter_ids: Array[StringName]) -> int:
	var count := 0
	for encounter_id in encounter_ids:
		var encounter := registry.get_definition(encounter_id) as EncounterDefinition
		if encounter.is_unknown:
			count += 1
	return count


func _descendant_text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children():
		result += _descendant_text(child)
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
