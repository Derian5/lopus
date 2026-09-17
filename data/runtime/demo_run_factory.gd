class_name DemoRunFactory
extends RefCounted


const HERO_IDS: Array[StringName] = [
	&"hero.test_vanguard",
	&"hero.army_support",
	&"hero.control_savant",
]


static func create_starting_run(seed := 1) -> RunState:
	var run := RunState.new()
	run.run_seed = seed
	run.gold = 300
	run.available_encounter_ids = [&"encounter.training_skirmish"]
	run.job_capacities = {
		"job.warrior": 3,
		"job.archer": 3,
		"job.priest": 3,
	}
	for index in HERO_IDS.size():
		var hero := HeroState.new()
		hero.unique_id = "hero-%02d" % index
		hero.definition_id = HERO_IDS[index]
		var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
		for ability_id in definition.starting_ability_ids:
			hero.equip_ability(ability_id)
		run.heroes.append(hero)
	for index in 9:
		var soldier := SoldierState.new()
		soldier.unique_id = "soldier-%02d" % index
		soldier.generated_name = "Militia %d" % (index + 1)
		run.soldiers.append(soldier)
	run.job_builds.append(_job_build(&"job.warrior", &"ability.stunning_blow", [&"ability.battle_fury"]))
	run.job_builds.append(_job_build(&"job.archer", &"ability.fire_bolt", [&"ability.battle_fury"]))
	run.job_builds.append(_job_build(&"job.priest", &"ability.mending_light", []))
	return run


static func _job_build(job_id: StringName, active_id: StringName, passive_ids: Array[StringName]) -> JobBuildState:
	var build := JobBuildState.new()
	build.job_id = job_id
	build.set_active_ability(active_id)
	build.set_passives(passive_ids)
	return build


static func _registry() -> Node:
	return Engine.get_main_loop().root.get_node("ContentRegistry")
