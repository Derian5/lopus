extends SceneTree


const COMBAT_SCENE := preload("res://combat/combat.tscn")
const MAIN_SCENE := preload("res://main.tscn")
const SAVE_ROOT := "user://tests/stage15-vertical-slice"
const WATCHDOG_MSEC := 20000

var failures := 0
var registry: Node
var route: RouteDefinition


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	route = registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var dev_mode: Node = root.get_node("DevMode")
	var previous_dev_mode: bool = dev_mode.enabled
	dev_mode.enabled = false
	var reports: Array[Dictionary] = []
	for strategy in 3:
		reports.append(await _run_complete_slice(strategy))
	dev_mode.enabled = previous_dev_mode
	Engine.time_scale = 1.0
	if failures == 0:
		for report in reports:
			print("Stage 15 playthrough: %s" % JSON.stringify(report))
		print("Stage 15 vertical slice tests passed.")
		quit()
	else:
		push_error("Stage 15 tests failed: %d" % failures)
		quit(1)


func _run_complete_slice(strategy: int) -> Dictionary:
	var seed := 15001 + strategy * 100
	var manager := SaveManager.new("%s-%d" % [SAVE_ROOT, strategy])
	manager.delete_save()
	var run := DemoRunFactory.create_starting_run(seed)
	run.inventory.create_item(&"item.gravedigger_fang")
	run.inventory.create_item(&"item.bone_bell")
	_apply_strategy(run, strategy)
	var report := {
		"strategy": ["hero_investment", "frontline", "mixed_equipment"][strategy],
		"seed": seed,
		"battles": 0,
		"combat_seconds": 0.0,
		"soldier_deaths": 0,
		"hero_deaths": 0,
		"resurrections": 0,
		"market_purchases": 0,
		"starting_gold": run.gold,
		"ending_gold": 0,
	}

	while run.run_status == RunState.STATUS_ACTIVE:
		var checkpoint := _reload_checkpoint(run, manager, "management checkpoint before battle %d" % (int(report.battles) + 1))
		if checkpoint == null:
			break
		run = checkpoint
		run = _resolve_pending_ability_reward(run)
		if run == null:
			break
		run = _resolve_pending_event(run)
		if run == null:
			break
		if run.run_phase == &"execution":
			var execution := ExecutionService.execute(run, run.heroes[strategy].unique_id, registry)
			_check(execution.ok, "Playthrough %d completes mandatory Execution." % (strategy + 1))
			if not execution.ok:
				break
			run = execution.run_state
			checkpoint = _reload_checkpoint(run, manager, "post-Execution Act II checkpoint")
			if checkpoint == null:
				break
			run = checkpoint
			continue

		_resurrect_available_heroes(run, report)
		if int(report.battles) > 0 and int(report.market_purchases) == 0:
			_purchase_market_offer(run, strategy, report)
		var choice_index := (strategy + run.encounter_index) % run.available_encounter_ids.size()
		var encounter_id := run.available_encounter_ids[choice_index]
		var selected := EncounterService.select_encounter(run, encounter_id)
		_check(selected.ok, "Playthrough %d selects a displayed Encounter Card." % (strategy + 1))
		if not selected.ok:
			break
		run.encounter_committed = true
		_check(manager.save_run(run, registry).ok, "Committed pre-combat checkpoint saves.")
		var battle := await _run_real_battle(run, run.combat_rng.next_seed())
		if battle.is_empty():
			break
		report.battles = int(report.battles) + 1
		report.combat_seconds = float(report.combat_seconds) + float(battle.duration)
		report.soldier_deaths = int(report.soldier_deaths) + int(battle.soldier_deaths)
		report.hero_deaths = int(report.hero_deaths) + int(battle.hero_deaths)
		_check(battle.winner == &"player", "Playthrough %d wins battle %d without debug commands." % [strategy + 1, report.battles])
		if battle.winner != &"player":
			break
		if run.run_phase != &"execution":
			run.run_phase = &"management"
			_check(RunCycleService.prepare_next_choice(run, registry).ok, "Victory prepares the next Market and Encounter choice.")

	report.ending_gold = run.gold
	_check(run.run_status == RunState.STATUS_DEMO_COMPLETE, "Playthrough %d reaches the temporary Demo End." % (strategy + 1))
	_check(run.current_act == 2 and run.encounter_index == route.act_two_battle_count, "Demo End follows all configured Act II battles.")
	_check(int(report.battles) == route.act_one_boss_wave + route.act_two_battle_count, "The vertical slice contains every configured Act I and Act II battle.")
	var final_checkpoint := _reload_checkpoint(run, manager, "terminal Demo End checkpoint")
	_check(final_checkpoint != null and final_checkpoint.run_status == RunState.STATUS_DEMO_COMPLETE, "Continue restores the terminal Demo End state.")
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main._continue_game()
	await process_frame
	await process_frame
	_check(main.current_screen.name == "RunOutcome", "Continue opens the temporary End Screen after the completed slice.")
	main.free()
	manager.delete_save()
	return report


func _run_real_battle(run: RunState, battle_seed: int) -> Dictionary:
	run.run_phase = &"combat"
	var combat = COMBAT_SCENE.instantiate()
	root.add_child(combat)
	combat.setup_run(run, battle_seed)
	Engine.time_scale = 20.0
	var started := Time.get_ticks_msec()
	while combat.last_result == null:
		await process_frame
		if Time.get_ticks_msec() - started > WATCHDOG_MSEC:
			_check(false, "A vertical-slice battle exceeded the watchdog.")
			combat.free()
			Engine.time_scale = 1.0
			return {}
	var result: CombatResult = combat.last_result
	var soldier_deaths := 0
	var hero_deaths := 0
	for death in result.application_summary.get("deaths", []):
		if int(death.get("unit_kind", -1)) == CombatUnitSnapshot.UnitKind.SOLDIER:
			soldier_deaths += 1
	for change in result.application_summary.get("hero_changes", []):
		if bool(change.get("died", false)):
			hero_deaths += 1
	var battle := {
		"winner": result.winner,
		"duration": result.duration,
		"soldier_deaths": soldier_deaths,
		"hero_deaths": hero_deaths,
	}
	combat.free()
	Engine.time_scale = 1.0
	return battle


func _reload_checkpoint(run: RunState, manager: SaveManager, label: String) -> RunState:
	var saved := manager.save_run(run, registry)
	_check(saved.ok, "%s saves." % label.capitalize())
	if not saved.ok:
		return null
	var loaded := manager.load_run(registry)
	_check(loaded.ok, "%s survives close and Continue." % label.capitalize())
	return loaded.run_state if loaded.ok else null


func _resolve_pending_event(run: RunState) -> RunState:
	while not run.pending_event.is_empty():
		var event := registry.get_definition(run.pending_event.event_id, false) as RunEventDefinition
		var node := event.get_node_definition(run.pending_event.node_id) if event != null else null
		if node == null:
			_check(false, "Pending Run Event node remains valid during the vertical slice.")
			return null
		var chosen: RunEventChoice
		for choice in node.choices:
			if choice != null and RunEventService.choice_status(run, choice, registry).ok:
				chosen = choice
				break
		if chosen == null:
			_check(false, "Pending Run Event exposes at least one available choice.")
			return null
		var result := RunEventService.choose(run, chosen.choice_id, registry)
		_check(result.ok, "Vertical-slice Run Event choice applies.")
		if not result.ok:
			return null
		run = result.run_state
	return run


func _resolve_pending_ability_reward(run: RunState) -> RunState:
	while not run.pending_hero_ability_reward.is_empty():
		if run.pending_hero_ability_reward.offers.is_empty():
			var prepared := HeroAbilityRewardService.prepare_reward(run, registry)
			_check(prepared.ok, "Vertical-slice Hero level-up reward prepares.")
			if not prepared.ok or run.pending_hero_ability_reward.is_empty():
				break
		var offer := run.pending_hero_ability_reward.offers[0]
		var result := HeroAbilityRewardService.choose(run, offer.offer_id, registry)
		_check(result.ok, "Vertical-slice Hero ability reward applies.")
		if not result.ok:
			return null
		run = result.run_state
	return run


func _apply_strategy(run: RunState, strategy: int) -> void:
	if strategy in [1, 2]:
		var warrior_count := 3 if strategy == 1 else 2
		for index in warrior_count:
			run.soldiers[index].current_job_id = &"job.warrior"
			run.soldiers[index].definition_id = &"job.warrior"
	var hero_items: Array[StringName] = []
	for item in run.inventory.items:
		hero_items.append(StringName(item.instance_id))
	if strategy == 0:
		for slot in hero_items.size():
			EquipmentService.equip_or_swap(run, &"hero", 0, slot, hero_items[slot], registry)
	elif strategy == 1:
		for slot in hero_items.size():
			EquipmentService.equip_or_swap(run, &"hero", 1, slot, hero_items[slot], registry)
	else:
		for slot in hero_items.size():
			EquipmentService.equip_or_swap(run, &"hero", 2, slot, hero_items[slot], registry)


func _resurrect_available_heroes(run: RunState, report: Dictionary) -> void:
	for hero in run.heroes:
		if hero.life_state != HeroState.DEAD:
			continue
		var result := ResurrectionService.resurrect(run, hero.unique_id, registry)
		if result.ok:
			report.resurrections = int(report.resurrections) + 1


func _purchase_market_offer(run: RunState, strategy: int, report: Dictionary) -> void:
	var preferred_types: Array = [
		[&"hero_item"],
		[&"job_unlock", &"job_capacity", &"hero_item"],
		[&"job_ability", &"hero_item"],
	][strategy]
	for preferred_type in preferred_types:
		for offer in run.market.offers:
			if offer.offer_type != preferred_type or offer.price > run.gold:
				continue
			var result := MarketService.buy_offer(run, offer.offer_id, registry)
			if result.ok:
				report.market_purchases = int(report.market_purchases) + 1
				return
	for offer in run.market.offers:
		if offer.price <= run.gold and MarketService.buy_offer(run, offer.offer_id, registry).ok:
			report.market_purchases = int(report.market_purchases) + 1
			return
	_check(false, "A post-tutorial Market visit offers at least one affordable decision.")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
