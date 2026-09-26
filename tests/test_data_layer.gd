extends SceneTree


var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry()
	_test_runtime_isolation()
	_test_state_round_trips()

	if failures == 0:
		print("Data layer tests passed.")
		quit()
	else:
		push_error("Data layer tests failed: %d" % failures)
		quit(1)


func _test_registry() -> void:
	var registry = root.get_node("ContentRegistry")
	_check(registry.validation_errors.is_empty(), "Registry loaded content without validation errors.")
	_check(registry.get_definition_count() >= 28, "Registry loaded gameplay, progression, and item definitions.")

	for content_id in [
		&"hero.test_vanguard",
		&"hero.army_support",
		&"hero.control_savant",
		&"job.militia",
		&"job.warrior",
		&"job.archer",
		&"job.priest",
		&"job.summoner",
		&"enemy.raider",
		&"enemy.crossbowman",
		&"enemy.summoner",
		&"enemy.summoned_brawler",
		&"enemy.summoned_shooter",
		&"encounter.training_skirmish",
		&"ability.fire_bolt",
		&"ability.hero_summon",
		&"ability.summoner_job_summon",
		&"ability.enemy_summon",
		&"status.burn",
		&"item.hero.vanguard_blade",
		&"item.hero.titan_seal",
		&"route.demo",
	]:
		_check(registry.get_definition(content_id, false) != null, "Definition resolves by ID: %s" % content_id)

	_check(registry.get_definition(&"missing.content", false) == null, "Missing definitions return null.")
	var route := registry.get_definition(&"route.demo") as RouteDefinition
	_check(route.act_one_boss_wave == 12 and route.act_one_boss_index() == 11 and route.act_two_battle_count == 12, "Demo route exposes battle count and the one-based Boss wave as content data.")

	var registry_script: Script = load("res://autoload/content_registry.gd")
	var isolated_registry = registry_script.new()
	var hero: HeroDefinition = load("res://content/demo/heroes/Greed.tres")
	_check(isolated_registry.register_definition(hero, false), "A valid definition can be registered.")
	_check(not isolated_registry.register_definition(hero.duplicate(true), false), "Duplicate IDs are rejected.")
	isolated_registry.free()


func _test_runtime_isolation() -> void:
	var first := HeroState.new()
	first.definition_id = &"hero.test_vanguard"
	first.current_hp = 100.0
	first.cooldowns[&"ability.test"] = 3.0
	first.statuses.append({"id": "status.test", "duration": 2.0})

	var second := HeroState.new()
	second.definition_id = first.definition_id
	second.current_hp = 240.0

	_check(first.current_hp != second.current_hp, "Runtime HP is isolated between units.")
	_check(second.cooldowns.is_empty(), "Runtime cooldowns are isolated between units.")
	_check(second.statuses.is_empty(), "Runtime statuses are isolated between units.")


func _test_state_round_trips() -> void:
	var hero := HeroState.new()
	hero.unique_id = "hero-1"
	hero.definition_id = &"hero.test_vanguard"
	hero.level = 3
	hero.xp = 125
	hero.current_hp = 180.0
	hero.unlock_ability(&"ability.one")
	hero.unlock_ability(&"ability.two")
	hero.equip_ability(&"ability.one")
	hero.equip_ability(&"ability.two")
	hero.item_ids = [&"item-00000001"]
	hero.ability_priority = [&"ability.two", &"ability.one"]
	hero.cooldowns = {"ability.one": 1.25}
	hero.statuses = [{"id": "status.burn", "duration": 2.5, "stacks": 2}]
	_assert_round_trip(hero.to_dictionary(), HeroState.from_dictionary(hero.to_dictionary()).to_dictionary(), "HeroState")

	var soldier := SoldierState.new()
	soldier.unique_id = "soldier-1"
	soldier.generated_name = "Alden"
	soldier.current_job_id = &"job.militia"
	soldier.veterancy_xp = 20
	soldier.veterancy_level = 1
	soldier.current_hp = 75.0
	soldier.item_ids = [&"item-00000002"]
	soldier.lifetime_statistics = {"kills": 2, "battles_survived": 3}
	soldier.cooldowns = {"ability.job.test": 0.5}
	soldier.statuses = [{"id": "status.armor", "duration": 4.0}]
	_assert_round_trip(soldier.to_dictionary(), SoldierState.from_dictionary(soldier.to_dictionary()).to_dictionary(), "SoldierState")

	var job_build := JobBuildState.new()
	job_build.job_id = &"job.militia"
	job_build.set_active_ability(&"ability.job.active")
	job_build.add_passive_ability(&"ability.job.passive")
	_assert_round_trip(job_build.to_dictionary(), JobBuildState.from_dictionary(job_build.to_dictionary()).to_dictionary(), "JobBuildState")

	var inventory := InventoryState.new()
	inventory.add_item(&"item-00000001", &"item.hero.vanguard_blade")
	inventory.add_item(&"item-00000002", &"item.hero.titan_seal")
	inventory.next_instance_serial = 3
	_assert_round_trip(inventory.to_dictionary(), InventoryState.from_dictionary(inventory.to_dictionary()).to_dictionary(), "InventoryState")

	var market := MarketState.new()
	var offer := MarketOffer.new()
	offer.offer_id = "offer-1"
	offer.offer_type = &"hero_item"
	offer.content_id = &"item.hero.vanguard_blade"
	offer.rarity = "common"
	offer.price = 50
	offer.target_type = &"hero"
	offer.target_id = "hero-01"
	market.offers = [offer]
	market.reroll_count = 2
	_assert_round_trip(market.to_dictionary(), MarketState.from_dictionary(market.to_dictionary()).to_dictionary(), "MarketState")

	var snapshot := ExecutionSnapshot.new()
	snapshot.hero_definition_id = &"hero.test_vanguard"
	snapshot.level = 3
	snapshot.xp = 125
	snapshot.ability_ids = hero.ability_ids
	snapshot.item_ids = hero.item_ids
	_assert_round_trip(snapshot.to_dictionary(), ExecutionSnapshot.from_dictionary(snapshot.to_dictionary()).to_dictionary(), "ExecutionSnapshot")

	var run := RunState.new()
	run.run_seed = 9876
	run.run_phase = &"management"
	run.current_act = 2
	run.encounter_index = 1
	run.gold = 350
	run.heroes.append(hero)
	run.soldiers.append(soldier)
	run.job_builds.append(job_build)
	run.job_capacities = {"job.militia": 9}
	run.unlocked_job_ids = [&"job.militia"]
	run.inventory = inventory
	run.market = market
	run.available_encounter_ids = [&"encounter.act2_pressure", &"encounter.act2_crossbows"]
	run.selected_encounter_id = &"encounter.act2_pressure"
	run.execution_snapshots.append(snapshot)
	run.tutorial_flags = {"market_seen": true}
	run.initialize_rng_streams(9876)
	run.run_rng.next_u32()
	run.market_rng.next_u32()
	run.combat_rng.next_u32()
	run.applied_combat_result_ids = ["result-1"]
	_assert_round_trip(run.to_dictionary(), RunState.from_dictionary(run.to_dictionary()).to_dictionary(), "RunState")


func _assert_round_trip(expected: Dictionary, actual: Dictionary, state_name: String) -> void:
	_check(actual == expected, "%s survives a dictionary round-trip." % state_name)
	_check(JSON.parse_string(JSON.stringify(expected)) is Dictionary, "%s dictionary is JSON-compatible." % state_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
