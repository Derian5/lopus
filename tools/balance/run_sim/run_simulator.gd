class_name RunSimulator
extends RefCounted


## Plays one complete run (Act I, Boss, Execution, Act II) through the real game
## services with a scripted bot, stepping combat by hand at a fixed 60 FPS. Nothing is
## rendered and no save is written, so a run takes seconds.
##
## var sim := RunSimulator.new(tree)
## var report: Dictionary = await sim.simulate_run({"style": "heroes", "seed": 7})

const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const STEP := 1.0 / 60.0
const MAX_BATTLE_STEPS := 60 * 130
const MAX_LOOP_GUARD := 80

var tree: SceneTree
var registry: Node
var route: RouteDefinition
var progression: ProgressionDefinition
## Engine frames are yielded every this many combat steps (0 = never, fastest for the CLI).
var yield_every_steps := 0


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	registry = tree.root.get_node("ContentRegistry")
	route = registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	progression = registry.get_definition(&"progression.demo") as ProgressionDefinition


## config keys: style, seed, heroes (Array of 3 hero ids), job_a, job_b, focus_hero
## (index 0..2), encounter_pick ("easiest", "random", "hardest"), resurrect (bool),
## max_rerolls (int per Market visit).
func simulate_run(config: Dictionary) -> Dictionary:
	var seed := int(config.get("seed", 1))
	var hero_ids: Array[StringName] = []
	for hero_id in config.get("heroes", []):
		hero_ids.append(StringName(hero_id))
	var run := DemoRunFactory.create_starting_run(seed, hero_ids)
	var bot := SimBot.new(config, registry, seed)
	var report := _new_report(config, run)
	run.run_phase = &"management"
	RunEventService.prepare_specific_event(run, route.opening_event_id, registry)
	var guard := 0
	while run.run_status == RunState.STATUS_ACTIVE and guard < MAX_LOOP_GUARD:
		guard += 1
		run = bot.resolve_pending(run)
		if run.run_phase == &"execution":
			var victim := bot.execution_target(run)
			report.executed_hero = _hero_definition_id(run, victim)
			var execution := ExecutionService.execute(run, victim, registry)
			if not execution.ok:
				report.error = "Execution failed: %s" % execution.error
				break
			run = execution.run_state
			continue
		if int(report.battles.size()) > 0:
			bot.manage(run, report)
		var encounter_id := bot.pick_encounter(run)
		if String(encounter_id).is_empty() or not EncounterService.select_encounter(run, encounter_id).ok:
			report.error = "No Encounter could be selected."
			break
		run.encounter_committed = true
		var battle := await _play_battle(run, report)
		if battle.is_empty():
			break
		report.battles.append(battle)
		if not bool(battle.win):
			break
		if run.run_phase != &"execution" and run.run_status == RunState.STATUS_ACTIVE:
			run.run_phase = &"management"
			var cycle := RunCycleService.prepare_next_choice(run, registry)
			if not cycle.ok:
				report.error = "Next cycle failed: %s" % cycle.error
				break
	_finish_report(report, run)
	return report


# --- combat --------------------------------------------------------------------

func _play_battle(run: RunState, report: Dictionary) -> Dictionary:
	var encounter := registry.get_definition(run.selected_encounter_id) as EncounterDefinition
	var route_power := CombatDemoFactory.route_enemy_power(run)
	var battle_number := run.encounter_index + 1
	var enemies := CombatDemoFactory.create_enemy_army_from_encounter(encounter, route_power, battle_number)
	var reinforcements: Array[CombatUnitSnapshot] = []
	if encounter.has_reinforcements():
		reinforcements = CombatDemoFactory.create_reinforcement_army_from_encounter(encounter, route_power, battle_number)
	var gold_before := run.gold
	var levels_before := {}
	for hero in run.heroes:
		levels_before[hero.unique_id] = hero.level
	var army := {}
	for soldier in run.soldiers:
		var job := String(soldier.current_job_id).trim_prefix("job.")
		army[job] = int(army.get(job, 0)) + 1
	var items_equipped := 0
	for hero in run.heroes:
		if hero.life_state != HeroState.EXECUTED:
			items_equipped += hero.item_ids.size()
	run.run_phase = &"combat"
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_process(false)
	session.set_physics_process(false)
	session.visible = false
	session.vfx_enabled = false
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = FormationService.REFERENCE_ARENA
	tree.root.add_child(session)
	var finished := {"done": false, "timed_out": false}
	session.battle_finished.connect(func(_winner: StringName, _duration: float, timed_out: bool) -> void:
		finished.done = true
		finished.timed_out = timed_out
	)
	session.setup(
		CombatSnapshotBuilder.build_player_army(run, registry),
		enemies,
		run.combat_rng.next_seed(),
		reinforcements,
		encounter.reinforcement_alive_threshold if encounter.has_reinforcements() else -1,
		encounter.reinforcement_entry_direction
	)
	# Units spawned later (summons, reinforcements) are caught at the end of each step.
	_take_manual_control(session)
	var steps := 0
	while not bool(finished.done) and steps < MAX_BATTLE_STEPS:
		_step(session)
		steps += 1
		if yield_every_steps > 0 and steps % yield_every_steps == 0:
			await tree.process_frame
	if not bool(finished.done):
		session._finish_battle(session._get_timeout_winner(), true)
	var result := CombatResult.from_statistics(
		"sim-%d-%d-%d" % [run.run_seed, run.current_act, run.encounter_index],
		session.statistics,
		encounter,
		bool(finished.timed_out),
		progression
	)
	var applied := CombatResultApplicator.apply(result, run, registry)
	var battle := _battle_report(run, encounter, result, gold_before, levels_before, report)
	battle.army = army
	battle.items = items_equipped
	if not applied:
		battle.error = "Combat result was not applied."
	session.free()
	return battle


func _step(session: CombatSession) -> void:
	for combatant in session.combatants.duplicate():
		if not is_instance_valid(combatant):
			continue
		combatant.initial_walk_delay_remaining = maxf(0.0, combatant.initial_walk_delay_remaining - STEP)
		combatant._physics_process(STEP)
		if not session.battle_active:
			return
	for projectile in session.get_node("Projectiles").get_children():
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			projectile._physics_process(STEP)
	session._process(STEP)
	if session.battle_active:
		session._physics_process(STEP)
	session._check_battle_end()
	_take_manual_control(session)


## Units and projectiles are driven by hand: the engine must not tick them again.
func _take_manual_control(session: CombatSession) -> void:
	for combatant in session.combatants:
		if is_instance_valid(combatant) and combatant.is_physics_processing():
			combatant.set_physics_process(false)
			combatant.set_process(false)
			# Sprite animation feeds projectile origins; freezing it keeps runs reproducible.
			combatant.unit_sprite.process_mode = Node.PROCESS_MODE_DISABLED
	for projectile in session.get_node("Projectiles").get_children():
		if projectile.is_physics_processing():
			projectile.set_physics_process(false)


# --- reporting -----------------------------------------------------------------

func _new_report(config: Dictionary, run: RunState) -> Dictionary:
	var heroes: Array[String] = []
	for hero in run.heroes:
		heroes.append(String(hero.definition_id))
	return {
		"style": String(config.get("style", "nothing")),
		"jobs": [String(config.get("job_a", ""))] if String(config.get("style", "")) == "one_job" else ([String(config.get("job_a", "")), String(config.get("job_b", ""))] if String(config.get("style", "")) == "two_jobs" else []),
		"seed": run.run_seed,
		"heroes": heroes,
		"result": "",
		"battles": [],
		"executed_hero": "",
		"hero_stats": {},
		"spent": {"hero_items": 0, "job_unlock": 0, "job_capacity": 0, "job_ability": 0, "reroll": 0, "resurrection": 0},
		"error": "",
	}


func _battle_report(run: RunState, encounter: EncounterDefinition, result: CombatResult, gold_before: int, levels_before: Dictionary, report: Dictionary) -> Dictionary:
	var soldiers_lost := 0
	var lost_melee := 0
	var lost_ranged := 0
	var ranged_fielded := 0
	var heroes_died := 0
	var hero_damage := 0.0
	var army_damage := 0.0
	var hero_rows: Array[Dictionary] = []
	for data in result.unit_statistics:
		if int(data.get("team", -1)) != CombatUnitSnapshot.Team.PLAYER:
			continue
		var kind := int(data.get("unit_kind", -1))
		var dead := not bool(data.get("alive", true))
		if kind == CombatUnitSnapshot.UnitKind.HERO:
			hero_damage += float(data.get("damage_dealt", 0.0))
			if dead:
				heroes_died += 1
			var hero_id := _hero_definition_id(run, String(data.get("runtime_id", "")))
			if not hero_id.is_empty():
				var stats: Dictionary = report.hero_stats.get(hero_id, {"damage": 0.0, "tanked": 0.0, "healing": 0.0, "kills": 0, "deaths": 0, "battles": 0})
				stats.damage = float(stats.damage) + float(data.get("damage_dealt", 0.0))
				stats.tanked = float(stats.tanked) + float(data.get("damage_tanked", 0.0))
				stats.healing = float(stats.healing) + float(data.get("effective_healing", 0.0))
				stats.kills = int(stats.kills) + int(data.get("kills", 0))
				stats.deaths = int(stats.deaths) + (1 if dead else 0)
				stats.battles = int(stats.battles) + 1
				report.hero_stats[hero_id] = stats
				var unique_id := String(data.get("runtime_id", ""))
				hero_rows.append({
					"id": hero_id,
					"level_before": int(levels_before.get(unique_id, 0)),
					"level": _hero_level(run, unique_id),
					"damage": roundf(float(data.get("damage_dealt", 0.0))),
					"tanked": roundf(float(data.get("damage_tanked", 0.0))),
					"healing": roundf(float(data.get("effective_healing", 0.0))),
					"kills": int(data.get("kills", 0)),
					"died": dead,
				})
		else:
			army_damage += float(data.get("damage_dealt", 0.0))
			if kind == CombatUnitSnapshot.UnitKind.SOLDIER:
				var job := registry.get_definition(StringName(data.get("job_id", "")), false) as JobDefinition
				var ranged := job != null and job.attack_type == &"ranged"
				ranged_fielded += 1 if ranged else 0
				if dead:
					soldiers_lost += 1
					if ranged:
						lost_ranged += 1
					else:
						lost_melee += 1
	var levels: Array[int] = []
	for hero in run.heroes:
		levels.append(hero.level)
	return {
		"number": report.battles.size() + 1,
		"act": encounter.act,
		"encounter": String(encounter.id).trim_prefix("encounter."),
		"encounter_name": encounter.display_name,
		"boss": encounter.is_boss,
		"win": result.winner == &"player",
		"timed_out": result.timed_out,
		"duration": snappedf(result.duration, 0.1),
		"soldiers_lost": soldiers_lost,
		"lost_melee": lost_melee,
		"lost_ranged": lost_ranged,
		"ranged_fielded": ranged_fielded,
		"heroes_died": heroes_died,
		"hero_damage": roundf(hero_damage),
		"army_damage": roundf(army_damage),
		"gold_before": gold_before,
		"gold_after": run.gold,
		"hero_levels": levels,
		"heroes": hero_rows,
		"error": "",
	}


func _finish_report(report: Dictionary, run: RunState) -> void:
	match run.run_status:
		RunState.STATUS_DEMO_COMPLETE:
			report.result = "win"
		RunState.STATUS_DEFEAT:
			report.result = "defeat"
		_:
			report.result = "stuck" if report.error.is_empty() else "error"
	report.battles_won = report.battles.filter(func(b: Dictionary) -> bool: return bool(b.win)).size()
	var last: Dictionary = report.battles[-1] if not report.battles.is_empty() else {}
	report.died_at = "" if report.result == "win" or last.is_empty() else "%d: %s" % [int(last.number), String(last.encounter_name)]
	report.final_gold = run.gold
	var levels: Array[int] = []
	for hero in run.heroes:
		levels.append(hero.level)
	report.final_levels = levels
	var soldiers := 0
	var veterancy := 0
	for soldier in run.soldiers:
		soldiers += 1
		veterancy += soldier.veterancy_level
	report.final_soldiers = soldiers
	report.average_veterancy = snappedf(float(veterancy) / maxf(soldiers, 1), 0.01)
	var jobs := {}
	for soldier in run.soldiers:
		jobs[String(soldier.current_job_id).trim_prefix("job.")] = int(jobs.get(String(soldier.current_job_id).trim_prefix("job."), 0)) + 1
	report.final_jobs = jobs


func _hero_level(run: RunState, unique_id: String) -> int:
	for hero in run.heroes:
		if hero.unique_id == unique_id:
			return hero.level
	return 0


func _hero_definition_id(run: RunState, unique_id: String) -> String:
	for hero in run.heroes:
		if hero.unique_id == unique_id:
			return String(hero.definition_id)
	return ""
