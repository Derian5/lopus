extends SceneTree


const COMBAT_SESSION_SCENE := preload("res://combat/combat_session.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")
const EXECUTION_SCENE := preload("res://ui/execution/execution.tscn")
const MAIN_SCENE := preload("res://main.tscn")
const SAVE_DIRECTORY := "user://stage14-test-save"

var failures := 0
var registry: Node
var route: RouteDefinition


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	route = registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	await _test_boss_framework()
	await _test_boss_battle()
	var checkpoint := _create_execution_checkpoint(14002)
	_test_execution_transaction(checkpoint)
	await _test_execution_ui(checkpoint)
	await _test_checkpoint_and_autosave(checkpoint)
	if failures == 0:
		print("Stage 14 Boss and Execution tests passed.")
		quit()
	else:
		push_error("Stage 14 tests failed: %d" % failures)
		quit(1)


func _test_boss_framework() -> void:
	var definition := registry.get_definition(&"enemy.iron_warden") as BossDefinition
	var snapshot := CombatSnapshotBuilder.build_enemy(definition, "boss-test", definition.display_name, registry)
	_check(snapshot.is_boss and snapshot.boss_phase_count == 2 and snapshot.boss_phase_health_thresholds == PackedFloat32Array([0.5]), "Iron Warden uses the shared snapshot framework with two data-driven phases.")
	_check(snapshot.stats.armor >= 14.0 and snapshot.abilities.size() >= 2, "Boss tests damage output through armor and formation through control/area abilities.")
	_check(not snapshot.boss_phase_telegraph_text.is_empty() and snapshot.boss_telegraph_color.a > 0.0, "Boss phase and attack telegraphs have placeholder presentation data.")

	var player := CombatUnitSnapshot.new()
	player.runtime_id = "boss-test-player"
	player.display_name = "Boss Tester"
	player.team = CombatUnitSnapshot.Team.PLAYER
	player.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	player.stats.max_hp = 1000.0
	player.stats.damage = 10.0
	player.stats.attack_speed = 1.0
	player.stats.movement_speed = 100.0
	player.stats.attack_range = 50.0
	var session: CombatSession = COMBAT_SESSION_SCENE.instantiate()
	root.add_child(session)
	session.setup([player], [snapshot], 14001)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var player_unit: Combatant = session.combatants[0]
	var boss_unit: Combatant = session.combatants[1]
	var phase_one_damage := boss_unit.get_effective_stat(&"damage")
	var threshold_damage := snapshot.stats.max_hp * 0.55 * (100.0 + snapshot.stats.armor) / 100.0
	boss_unit.take_damage(threshold_damage, player_unit)
	_check(boss_unit.boss_phase == 2 and session.statistics.get_event_count(CombatEvent.BOSS_PHASE_CHANGED) == 1, "Crossing the health threshold emits a readable Boss phase transition.")
	_check(boss_unit.get_effective_stat(&"damage") > phase_one_damage, "The second phase strengthens the same combat pipeline without a separate Boss system.")
	boss_unit.target = player_unit
	boss_unit._start_attack()
	_check(boss_unit.windup_duration >= 0.6, "Boss attacks expose an extended telegraph window.")
	session.free()


func _test_boss_battle() -> void:
	Engine.time_scale = 20.0
	var run := DemoRunFactory.create_starting_run(14010)
	run.current_act = 1
	run.encounter_index = route.act_one_boss_index()
	EncounterService.begin_choice(run, registry)
	EncounterService.select_encounter(run, run.available_encounter_ids[0])
	run.run_phase = &"combat"
	var combat = COMBAT_SCENE.instantiate()
	root.add_child(combat)
	combat.setup_run(run, 14010)
	Engine.time_scale = 20.0
	var start := Time.get_ticks_msec()
	while run.applied_combat_result_ids.is_empty():
		await process_frame
		if Time.get_ticks_msec() - start > 15000:
			_check(false, "Act I Boss battle exceeded watchdog.")
			break
	_check(combat.last_result != null and combat.last_result.winner == &"player", "The Act I Boss is beatable on the existing combat framework.")
	_check(run.run_phase == &"execution", "A real Boss battle enters the Execution checkpoint after Victory.")
	combat.free()
	Engine.time_scale = 1.0


func _test_execution_transaction(run: RunState) -> void:
	var dead_hero := run.heroes[1]
	var item_instance := dead_hero.item_ids[0]
	var original := run.to_dictionary()
	var invalid := ExecutionService.execute(run, "missing-hero", registry)
	_check(not invalid.ok and run.to_dictionary() == original, "Invalid Execution leaves the checkpoint unchanged.")
	var incomplete_checkpoint := RunState.from_dictionary(run.to_dictionary())
	incomplete_checkpoint.pending_execution_contributions.erase(incomplete_checkpoint.heroes[2].unique_id)
	_check(not ExecutionService.execute(incomplete_checkpoint, incomplete_checkpoint.heroes[0].unique_id, registry).ok, "Execution rejects incomplete three-Hero contribution data.")
	var empty_contribution := RunState.from_dictionary(run.to_dictionary())
	empty_contribution.pending_execution_contributions[empty_contribution.heroes[0].unique_id] = {"participated": true, "alive": true, "contribution": {}}
	_check(not ExecutionService.execute(empty_contribution, empty_contribution.heroes[0].unique_id, registry).ok, "Execution rejects contribution entries without required metrics.")
	var bypassed_phase := RunState.from_dictionary(run.to_dictionary())
	bypassed_phase.run_phase = &"management"
	_check(not SaveManager.new(SAVE_DIRECTORY)._validate_run(bypassed_phase, registry).is_empty(), "Save validation prevents bypassing Execution by changing only run_phase.")
	var short_roster := RunState.from_dictionary(run.to_dictionary())
	short_roster.soldiers.remove_at(0)
	_check(not ExecutionService.execute(short_roster, short_roster.heroes[0].unique_id, registry).ok, "Execution rejects a checkpoint that cannot produce ten Act II soldiers.")
	var result := ExecutionService.execute(run, dead_hero.unique_id, registry)
	_check(result.ok and run.to_dictionary() == original, "Execution is staged atomically without mutating its source checkpoint.")
	if not result.ok:
		return
	var executed: RunState = result.run_state
	var hero := executed.heroes[1]
	var snapshot: ExecutionSnapshot = result.snapshot
	_check(hero.life_state == HeroState.EXECUTED and hero.ability_ids.is_empty() and hero.owned_ability_ids.is_empty() and hero.item_ids.is_empty(), "Executed Hero build is permanently removed from active use.")
	_check(snapshot.hero_unique_id == dead_hero.unique_id and snapshot.life_state_at_execution == HeroState.DEAD and not snapshot.ability_ids.is_empty() and snapshot.ability_levels.size() == snapshot.owned_ability_ids.size(), "ExecutionSnapshot captures the ability build and levels before an Alive or Dead Hero is removed.")
	_check(snapshot.item_ids.has(item_instance) and not executed.inventory.has_instance(item_instance), "Executed equipment is sealed in history and unavailable to the active roster.")
	var remaining_item := StringName(executed.inventory.items[0].instance_id)
	_check(not EquipmentService.equip_or_swap(executed, &"hero", 1, 0, remaining_item, registry).ok, "EquipmentService rejects Executed Heroes even when called outside the UI.")
	_check(executed.execution_snapshots.size() == 1 and executed.soldiers.size() == 10, "Execution history is recorded and one new Militia fills the slot.")
	_check(_active_hero_count(executed) == 2 and executed.current_act == 2 and executed.encounter_index == 0, "Act II starts with two active Heroes and ten soldiers.")
	_check(executed.run_phase == &"management" and executed.pending_execution_contributions.is_empty(), "Execution completes the checkpoint and clears transient comparison data.")
	_check(executed.pending_hero_ability_reward.offers.size() == 3, "Boss ability reward is generated only after Execution completes.")
	for reward_offer in executed.pending_hero_ability_reward.offers:
		_check(reward_offer.hero_unique_id != dead_hero.unique_id, "Post-Execution ability reward excludes the Executed Hero.")
	for offer in executed.market.offers:
		_check(offer.target_id != dead_hero.unique_id, "Act II Market eligibility excludes the Executed Hero.")
	_check(not ExecutionService.execute(executed, dead_hero.unique_id, registry).ok, "Execution cannot be applied twice.")
	var forged_checkpoint := RunState.from_dictionary(executed.to_dictionary())
	forged_checkpoint.run_phase = &"execution"
	forged_checkpoint.current_act = 1
	forged_checkpoint.encounter_index = route.act_one_boss_index()
	forged_checkpoint.pending_execution_contributions[forged_checkpoint.heroes[0].unique_id] = {"participated": true}
	_check(not ExecutionService.execute(forged_checkpoint, forged_checkpoint.heroes[0].unique_id, registry).ok, "An existing history entry prevents a second Hero Execution.")
	var malformed_history := RunState.from_dictionary(executed.to_dictionary())
	malformed_history.execution_snapshots[0].item_definition_ids.clear()
	_check(not SaveManager.new(SAVE_DIRECTORY)._validate_run(malformed_history, registry).is_empty(), "Save validation rejects mismatched archived item instances and definitions.")
	var missing_history := RunState.from_dictionary(executed.to_dictionary())
	missing_history.heroes[1].life_state = HeroState.DEAD
	missing_history.execution_snapshots.clear()
	_check(not SaveManager.new(SAVE_DIRECTORY)._validate_run(missing_history, registry).is_empty(), "Save validation rejects Act II without its Act I Execution history.")


func _test_execution_ui(run: RunState) -> void:
	var screen = EXECUTION_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	var completed: Array[RunState] = []
	screen.execution_completed.connect(func(staged: RunState) -> void: completed.append(staged))
	await process_frame
	await process_frame
	_check(screen.get_node("%HeroCards").get_child_count() == 3, "Execution screen compares all three Alive or Dead Heroes.")
	screen._select_hero(run.heroes[1].unique_id)
	screen._on_execute_pressed()
	_check(screen.get_node("%ConfirmationDialog").dialog_text.contains("permanently") and screen.get_node("%ConfirmationDialog").dialog_text.contains("cannot be recovered"), "Execution uses a separate irreversible confirmation with explicit losses.")
	screen._on_execution_confirmed()
	_check(completed.size() == 1 and completed[0].heroes[1].life_state == HeroState.EXECUTED, "Confirmed placeholder Execution emits the completed transaction.")
	screen.free()


func _test_checkpoint_and_autosave(run: RunState) -> void:
	var manager := SaveManager.new(SAVE_DIRECTORY)
	manager.delete_save()
	_check(manager.save_run(run, registry).ok, "The mandatory Execution checkpoint saves immediately after Boss victory.")
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main._continue_game()
	await process_frame
	await process_frame
	_check(main.current_screen.name == "Execution", "Continue restores the mandatory Execution screen instead of bypassing it.")
	var checkpoint_before: Dictionary = main.active_run.to_dictionary()
	main._request_combat()
	_check(main.current_screen.name == "Execution" and main.active_run.to_dictionary() == checkpoint_before, "Combat entry cannot bypass the mandatory Execution phase.")
	main.current_screen._select_hero(run.heroes[0].unique_id)
	main.current_screen._on_execution_confirmed()
	await process_frame
	await process_frame
	_check(main.current_screen.name == "EncounterChoice" and main.active_run.current_act == 2, "Successful Execution opens the first Act II Encounter choice before the deferred Boss ability reward.")
	main._on_encounter_selected(main.active_run.available_encounter_ids[0])
	await process_frame
	_check(main.current_screen.name == "Management" and main.current_screen.get_node("%HeroAbilityRewardPopup").visible, "Choosing the first Act II battle opens Management with the deferred Boss ability reward.")
	main._on_hero_ability_reward_requested(main.active_run.pending_hero_ability_reward.offers[0].offer_id)
	await process_frame
	_check(main.current_screen.name == "Management", "Claiming the deferred Boss reward returns to Act II preparation.")
	_check(main.current_screen.selected_kind == "hero" and main.current_screen.selected_index == 1, "Management selects the first active Hero instead of the hidden Executed Hero.")
	var loaded := manager.load_run(registry)
	_check(loaded.ok and loaded.run_state.heroes[0].life_state == HeroState.EXECUTED and loaded.run_state.execution_snapshots.size() == 1, "Execution autosave remains irreversible through Save/Load.")
	main.free()
	manager.delete_save()


func _create_execution_checkpoint(seed: int) -> RunState:
	var run := DemoRunFactory.create_starting_run(seed)
	run.current_act = 1
	run.encounter_index = route.act_one_boss_index()
	EncounterService.begin_choice(run, registry)
	var boss_id := run.available_encounter_ids[0]
	EncounterService.select_encounter(run, boss_id)
	run.heroes[1].unlock_ability(&"ability.mending_light")
	run.heroes[1].equip_ability(&"ability.mending_light")
	var hero_item := StringName(run.inventory.items[0].instance_id)
	var equipped := EquipmentService.equip_or_swap(run, &"hero", 1, 0, hero_item, registry)
	_check(equipped.ok, "Stage 14 setup equips a Hero item for snapshot locking.")
	run.run_phase = &"combat"
	var result := CombatResult.new()
	result.result_id = "stage14-boss-%d" % seed
	result.winner = &"player"
	result.encounter_id = boss_id
	for index in run.heroes.size():
		result.unit_statistics.append(_hero_statistics(run.heroes[index], index != 1, index))
	_check(CombatResultApplicator.apply(result, run, registry), "Boss victory applies before Execution.")
	_check(run.run_phase == &"execution" and run.current_act == 1 and run.encounter_index == route.act_one_boss_index(), "Boss victory enters Execution before advancing the Act.")
	_check(run.pending_execution_contributions.size() == 3 and run.heroes[1].life_state == HeroState.DEAD, "Execution checkpoint stores contribution for all Heroes and permits a Dead candidate.")
	return run


func _hero_statistics(hero: HeroState, alive: bool, index: int) -> Dictionary:
	return {
		"runtime_id": hero.unique_id,
		"display_name": String(hero.definition_id),
		"team": CombatUnitSnapshot.Team.PLAYER,
		"unit_kind": CombatUnitSnapshot.UnitKind.HERO,
		"alive": alive,
		"damage_dealt": 100.0 + index * 25.0,
		"damage_taken": 50.0,
		"damage_tanked": 40.0,
		"healing": 20.0,
		"effective_healing": 20.0,
		"kills": 0,
		"deaths": 0 if alive else 1,
		"ability_uses": 2,
		"battles_survived": 0,
	}


func _active_hero_count(run: RunState) -> int:
	var count := 0
	for hero in run.heroes:
		if hero.life_state != HeroState.EXECUTED:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
