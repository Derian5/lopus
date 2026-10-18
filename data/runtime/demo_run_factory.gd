class_name DemoRunFactory
extends RefCounted


const HERO_IDS: Array[StringName] = [
	&"hero.test_vanguard",
	&"hero.army_support",
	&"hero.control_savant",
]
const FIRST_ENCOUNTER_ID := &"encounter.tutorial_volley"


static func create_starting_run(seed := 1, selected_hero_ids: Array[StringName] = []) -> RunState:
	var run := RunState.new()
	run.run_seed = seed
	run.initialize_rng_streams(seed)
	run.gold = 300
	run.unlocked_job_ids = [&"job.militia"]
	var hero_ids := HERO_IDS.duplicate() if selected_hero_ids.is_empty() else selected_hero_ids.duplicate()
	var valid_hero_ids := hero_ids.size() == HERO_IDS.size()
	var seen_hero_ids: Dictionary = {}
	for hero_id in hero_ids:
		var definition := _registry().get_definition(hero_id, false) as HeroDefinition
		if definition == null or not definition.available_in_new_game or seen_hero_ids.has(hero_id):
			valid_hero_ids = false
		seen_hero_ids[hero_id] = true
	if not valid_hero_ids:
		push_error("Starting run requires exactly three unique selectable Hero IDs; using the default trio.")
		hero_ids = HERO_IDS.duplicate()
	for index in hero_ids.size():
		var hero := HeroState.new()
		hero.unique_id = "hero-%02d" % index
		hero.definition_id = hero_ids[index]
		run.heroes.append(hero)
	for index in 9:
		var soldier := SoldierState.new()
		soldier.unique_id = "soldier-%02d" % index
		SoldierNameGenerator.assign_name(soldier, "Militia", run.run_seed, run.soldiers)
		run.soldiers.append(soldier)
	var generated := MarketGenerator.generate_offers(run, _registry(), run.market_rng, run.market.next_offer_serial)
	if generated.ok:
		for offer in generated.offers:
			run.market.offers.append(offer)
		run.market.next_offer_serial = generated.next_offer_serial
	else:
		push_error(generated.error)
	run.available_encounter_ids = [FIRST_ENCOUNTER_ID]
	var encounter_result := EncounterService.select_encounter(run, FIRST_ENCOUNTER_ID)
	if not encounter_result.ok:
		push_error(encounter_result.error)
	return run


static func _registry() -> Node:
	return Engine.get_main_loop().root.get_node("ContentRegistry")
