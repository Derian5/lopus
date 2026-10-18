extends SceneTree

## Balance simulator: plays encounters against synthetic stage armies.
## Usage: godot --headless --fixed-fps 60 --script res://tools/balance/balance_sim.gd -- <stage> <encounter_ids_csv|all> <trio_index> [seed]

const COMBAT_SCENE := preload("res://combat/combat.tscn")
const HEROES: Array[StringName] = [&"hero.glass_arcanist", &"hero.test_vanguard", &"hero.thorn_warden", &"hero.iron_oracle", &"hero.army_support", &"hero.control_savant", &"hero.ashen_duelist"]
const TRIOS := [[0, 1, 2], [3, 4, 5], [6, 0, 3], [1, 4, 6], [2, 5, 0], [6, 3, 1]]
## stage: [hero level, soldier veterancy, job list for the 9 soldiers]
const STAGES := {
	"s0": [1, 0, []],
	"s1": [3, 1, ["job.warrior", "job.archer"]],
	"s2": [4, 2, ["job.warrior", "job.warrior", "job.archer", "job.archer", "job.priest"]],
	"s3": [5, 3, ["job.warrior", "job.warrior", "job.shieldbearer", "job.archer", "job.archer", "job.priest", "job.archer"]],
	"s4": [6, 3, ["job.warrior", "job.warrior", "job.shieldbearer", "job.shieldbearer", "job.archer", "job.archer", "job.archer", "job.priest", "job.priest"]],
	"s5": [7, 4, ["job.warrior", "job.warrior", "job.shieldbearer", "job.shieldbearer", "job.archer", "job.archer", "job.archer", "job.priest", "job.priest"]],
}

var registry: Node
var out_index := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	var args := OS.get_cmdline_user_args()
	var stage := String(args[0]) if args.size() > 0 else "s0"
	var encounter_arg := String(args[1]) if args.size() > 1 else "all"
	var trio_index := int(args[2]) if args.size() > 2 else 0
	var seed := int(args[3]) if args.size() > 3 else 7
	var encounter_ids: Array[StringName] = []
	if encounter_arg == "all":
		for definition in registry.definitions.values():
			if definition is EncounterDefinition and definition.act == 1:
				encounter_ids.append(definition.id)
		encounter_ids.sort()
	else:
		for part in encounter_arg.split(","):
			encounter_ids.append(StringName(part if part.begins_with("encounter.") else "encounter." + part))
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 8
	for encounter_id in encounter_ids:
		var battle_stage := stage
		if stage == "auto":
			battle_stage = _stage_for_index(_index_for(registry.get_definition(encounter_id) as EncounterDefinition))
		var result := await _play(battle_stage, encounter_id, trio_index, seed)
		print("SIM ", JSON.stringify(result))
	quit()


const STAGE_BY_INDEX := ["s0", "s1", "s2", "s2", "s3", "s3", "s3", "s4", "s4", "s4", "s5", "s5", "s5"]


func _stage_for_index(index: int) -> String:
	return STAGE_BY_INDEX[clampi(index, 0, STAGE_BY_INDEX.size() - 1)]


func _index_for(encounter: EncounterDefinition) -> int:
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	if encounter.is_boss:
		return route.act_one_boss_index()
	var index := (encounter.min_encounter_index + encounter.max_encounter_index) / 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("idx="):
			var value := String(arg.trim_prefix("idx="))
			if value == "min":
				index = encounter.min_encounter_index
			elif value == "max":
				index = encounter.max_encounter_index
			elif value != "mid":
				index = int(value)
	if OS.get_cmdline_user_args().has("free"):
		return clampi(index, 0, route.act_one_boss_index() - 1)
	return clampi(index, encounter.min_encounter_index, mini(encounter.max_encounter_index, route.act_one_boss_index() - 1))


func _build_run(stage: String, trio_index: int, seed: int) -> RunState:
	var trio: Array[StringName] = []
	for index in TRIOS[trio_index % TRIOS.size()]:
		trio.append(HEROES[index])
	var run := DemoRunFactory.create_starting_run(seed, trio)
	var config: Array = STAGES[stage]
	var level := int(config[0])
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	for hero in run.heroes:
		hero.level = level
		hero.xp = progression.hero_level_xp_thresholds[level - 1]
		run.pending_hero_ability_reward.queue_level_ups(hero.unique_id, level - 1)
	var guard := 0
	while not run.pending_hero_ability_reward.hero_level_up_queue.is_empty() and guard < 40:
		HeroAbilityRewardService.prepare_reward(run, registry)
		if run.pending_hero_ability_reward.offers.is_empty():
			break
		var offers := run.pending_hero_ability_reward.offers
		HeroAbilityRewardService.choose(run, offers[guard % offers.size()].offer_id, registry)
		guard += 1
	var jobs: Array = config[2]
	for index in run.soldiers.size():
		var soldier := run.soldiers[index]
		soldier.veterancy_level = int(config[1])
		soldier.veterancy_xp = progression.veterancy_xp_thresholds[int(config[1])]
		if index < jobs.size():
			soldier.current_job_id = StringName(jobs[index])
	return run


func _play(stage: String, encounter_id: StringName, trio_index: int, seed: int) -> Dictionary:
	var run := _build_run(stage, trio_index, seed)
	var encounter := registry.get_definition(encounter_id) as EncounterDefinition
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	run.encounter_index = _index_for(encounter)
	out_index = run.encounter_index
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("power="):
			encounter.enemy_power = float(arg.trim_prefix("power="))
		elif arg.begins_with("rp="):
			if route.act_one_enemy_power_curve.size() <= run.encounter_index:
				route.act_one_enemy_power_curve.resize(run.encounter_index + 1)
			route.act_one_enemy_power_curve[run.encounter_index] = float(arg.trim_prefix("rp="))
	run.available_encounter_ids = [encounter_id]
	run.selected_encounter_id = encounter_id
	run.encounter_committed = false
	run.run_phase = &"combat"
	run.pending_event.clear()
	var combat = COMBAT_SCENE.instantiate()
	root.add_child(combat)
	combat.setup_run(run, seed)
	var frames := 0
	while run.applied_combat_result_ids.is_empty() and frames < 20000:
		await process_frame
		frames += 1
	var result: CombatResult = combat.last_result
	var out := {"idx": out_index, "stage": stage, "enc": String(encounter_id).trim_prefix("encounter."), "trio": trio_index}
	if result == null:
		out["error"] = "no result"
	else:
		var heroes_dead := 0
		var soldiers_dead := 0
		var player_hp := 0.0
		var player_max := 0.0
		for data: Dictionary in result.unit_statistics:
			if not (str(data.get("team", "")) in ["player", str(CombatUnitSnapshot.Team.PLAYER)]):
				continue
			if not bool(data.get("alive", true)):
				if int(data.get("unit_kind", -1)) == CombatUnitSnapshot.UnitKind.HERO:
					heroes_dead += 1
				elif int(data.get("unit_kind", -1)) == CombatUnitSnapshot.UnitKind.SOLDIER:
					soldiers_dead += 1
		out["win"] = result.winner == &"player"
		out["t"] = snappedf(result.duration, 0.1)
		var abilities := {}
		for event in combat.combat_session.events:
			var ability_name := String(event.ability_id)
			if ability_name.begins_with("ability.") and String(event.source_id).begins_with("enemy"):
				var key := ability_name.trim_prefix("ability.")
				abilities[key] = int(abilities.get(key, 0)) + 1
		if OS.get_cmdline_user_args().has("abilities"):
			out["ab"] = abilities
		out["hd"] = heroes_dead
		out["sd"] = soldiers_dead
	combat.free()
	await process_frame
	return out
