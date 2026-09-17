extends SceneTree


const POST_BATTLE_SCENE := preload("res://ui/post_battle/post_battle_panel.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	_test_contribution_formula()
	var run := DemoRunFactory.create_starting_run(8080)
	run.soldiers[0].current_job_id = &"job.warrior"
	run.soldiers[0].veterancy_xp = 30
	run.soldiers[1].current_job_id = &"job.archer"
	run.soldiers[1].veterancy_xp = 95
	run.soldiers[1].veterancy_level = 1
	run.soldiers[1].item_ids = [&"item.test_sword", &"item.test_charm"]
	var original_dead_id := run.soldiers[1].unique_id

	var statistics := CombatStatistics.new()
	var player_snapshots := CombatSnapshotBuilder.build_player_army(run, registry)
	for snapshot in player_snapshots:
		statistics.register_unit(snapshot)
	var enemy := CombatDemoFactory.create_enemy_army(1, 0)[0]
	statistics.register_unit(enemy)
	statistics.consume(CombatEvent.new(1.0, CombatEvent.DAMAGE_APPLIED, "hero-00", enemy.runtime_id, &"ability.fire_bolt", &"effect.damage", 100.0))
	statistics.consume(CombatEvent.new(1.2, CombatEvent.HEALING_APPLIED, "hero-00", "soldier-00", &"ability.mending_light", &"effect.heal", 20.0))
	statistics.consume(CombatEvent.new(1.3, CombatEvent.ABILITY_USED, "hero-00", enemy.runtime_id, &"ability.fire_bolt"))
	statistics.consume(CombatEvent.new(1.4, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, "soldier-00", &"attack.basic", &"attack.basic", 100.0))
	statistics.consume(CombatEvent.new(1.5, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, original_dead_id, &"attack.basic", &"attack.basic", 30.0))
	statistics.consume(CombatEvent.new(1.6, CombatEvent.UNIT_DIED, enemy.runtime_id, original_dead_id, &"", &"attack.basic"))
	statistics.consume(CombatEvent.new(2.0, CombatEvent.UNIT_DIED, "hero-00", enemy.runtime_id, &"", &"effect.damage"))
	statistics.consume(CombatEvent.new(3.0, CombatEvent.BATTLE_FINISHED, "player", "", &"", &"", 33.0))
	var encounter := registry.get_definition(&"encounter.training_skirmish") as EncounterDefinition
	var result := CombatResult.from_statistics("result-stage8-test", statistics, encounter, false, progression)
	var old_gold := run.gold
	var hero_contribution: Dictionary = result.get_unit_statistics("hero-00").contribution
	_check(int(hero_contribution.damage_xp) == 10 and int(hero_contribution.healing_xp) == 2 and int(hero_contribution.tanking_xp) == 0, "CombatResult stores XP for every contribution metric.")
	_check(int(hero_contribution.total_xp) == 12, "CombatResult stores the explainable total contribution XP.")

	_check(CombatResultApplicator.apply(result, run, registry), "A fresh CombatResult applies successfully.")
	_check(run.gold == old_gold + encounter.gold_reward, "Victory Gold is added once.")
	_check(run.heroes[0].xp == 12, "Hero XP is derived from damage, effective healing, and tanking contribution.")
	_check(run.soldiers[0].veterancy_xp == 40 and run.soldiers[0].veterancy_level == 1, "A surviving soldier gains contribution XP and a veterancy level.")
	_check(is_equal_approx(float(run.soldiers[0].lifetime_statistics.damage_tanked), 100.0), "Surviving Soldier lifetime statistics include tanking contribution.")
	_check(not _has_soldier(run, original_dead_id), "A dead soldier is permanently removed.")
	_check(run.soldiers.size() == 9, "Victory refills each dead soldier slot with Militia.")
	var replacement := run.soldiers[-1]
	_check(replacement.unique_id != original_dead_id, "Replacement Militia receives a new unique ID.")
	_check(replacement.current_job_id == &"job.militia" and replacement.veterancy_xp == 0 and replacement.item_ids.is_empty(), "Replacement does not inherit Job, veterancy, or equipment.")
	_check(run.inventory.items.size() == 2, "Dead soldier equipment returns to Inventory.")
	_check(result.application_summary.deaths.size() == 1 and result.application_summary.replacements.size() == 1, "CombatResult records death and refill consequences.")
	_check(int(result.application_summary.deaths[0].potential_xp) == 3, "A dead Soldier reports contribution XP lost to permanent death.")
	_check(not CombatResultApplicator.apply(result, run, registry), "The same CombatResult cannot apply twice.")
	_check(run.gold == old_gold + encounter.gold_reward and run.heroes[0].xp == 12, "Rejected reapplication changes no rewards or XP.")

	var restored := RunState.from_dictionary(run.to_dictionary())
	_check(restored.applied_combat_result_ids.has(result.result_id), "Applied result IDs survive serialization.")
	_check(is_equal_approx(float(restored.soldiers[0].lifetime_statistics.damage_tanked), 100.0), "Expanded Soldier lifetime contribution survives serialization.")
	_check(not CombatResultApplicator.apply(result, restored, registry), "A loaded run also rejects an already applied result.")

	var hero_snapshot := CombatSnapshotBuilder.build_hero(run.heroes[0], registry)
	run.heroes[0].level = 2
	var leveled_snapshot := CombatSnapshotBuilder.build_hero(run.heroes[0], registry)
	_check(leveled_snapshot.stats.max_hp > hero_snapshot.stats.max_hp and leveled_snapshot.stats.damage > hero_snapshot.stats.damage, "Hero level grants fixed stat growth.")
	var veteran_snapshot := CombatSnapshotBuilder.build_soldier(run.soldiers[0], run.job_builds[0], registry)
	run.soldiers[0].veterancy_level = 0
	var recruit_snapshot := CombatSnapshotBuilder.build_soldier(run.soldiers[0], run.job_builds[0], registry)
	_check(veteran_snapshot.stats.max_hp > recruit_snapshot.stats.max_hp, "Veterancy level grants a stat multiplier.")

	var panel = POST_BATTLE_SCENE.instantiate()
	root.add_child(panel)
	panel.show_result(result)
	_check(panel.get_node("%ResultTitle").text == "VICTORY", "Post Battle panel shows victory state.")
	_check(panel.get_node("%RewardLabel").text.contains("100"), "Post Battle panel shows Gold.")
	var progression_text: String = panel.get_node("%ProgressionValue").text
	_check(progression_text.contains("Hero XP") and progression_text.contains("Veterancy XP"), "Post Battle panel shows Hero XP and Veterancy XP.")
	_check(progression_text.contains("DMG") and progression_text.contains("HEAL") and progression_text.contains("TANK"), "Post Battle explains all three contribution components.")
	_check(progression_text.contains("XP LOST (DEAD)"), "Post Battle explains dead Soldier XP loss.")
	_check(panel.get_node("%DeathsValue").text.contains("Militia 2"), "Post Battle panel lists deaths.")
	panel.free()

	_test_defeat_without_refill(registry)
	await _test_combat_scene_integration()
	if failures == 0:
		print("Combat result and Stage 8A tests passed.")
		quit()
	else:
		push_error("Combat result tests failed: %d" % failures)
		quit(1)


func _test_defeat_without_refill(registry: Node) -> void:
	var run := DemoRunFactory.create_starting_run(8081)
	var dead_id := run.soldiers[0].unique_id
	var result := CombatResult.new()
	result.result_id = "result-defeat-test"
	result.winner = &"enemy"
	result.gold_reward = 0
	result.unit_statistics = [{
		"runtime_id": dead_id,
		"display_name": run.soldiers[0].generated_name,
		"team": CombatUnitSnapshot.Team.PLAYER,
		"unit_kind": CombatUnitSnapshot.UnitKind.SOLDIER,
		"alive": false,
		"damage_dealt": 0.0,
		"damage_taken": 10.0,
		"damage_tanked": 10.0,
		"healing": 0.0,
		"effective_healing": 0.0,
		"kills": 0,
		"deaths": 1,
		"ability_uses": 0,
		"battles_survived": 0,
	}]
	var old_gold := run.gold
	_check(CombatResultApplicator.apply(result, run, registry), "Defeat result applies.")
	_check(run.soldiers.size() == 8 and not _has_soldier(run, dead_id), "Defeat applies permanent death without Victory refill.")
	_check(run.gold == old_gold, "Defeat grants no Gold.")
	_check(int(result.application_summary.deaths[0].potential_xp) == 1, "Defeat still calculates the dead Soldier contribution.")


func _test_contribution_formula() -> void:
	var progression := ProgressionDefinition.new()
	progression.damage_xp_rate = 0.1
	progression.healing_xp_rate = 0.1
	progression.tanking_xp_rate = 0.1
	var statistics := {
		"damage_dealt": 19.0,
		"effective_healing": 9.0,
		"damage_tanked": 5.0,
	}
	var breakdown := progression.contribution_breakdown(statistics)
	_check(int(breakdown.total_xp) == 1, "Floor rounding is applied to each contribution component.")
	progression.xp_rounding_mode = ProgressionDefinition.XpRounding.ROUND
	breakdown = progression.contribution_breakdown(statistics)
	_check(int(breakdown.total_xp) == 4, "Contribution rounding mode is data-driven.")
	progression.max_contribution_xp = 2
	breakdown = progression.contribution_breakdown(statistics)
	_check(int(breakdown.total_xp) == 2 and bool(breakdown.was_capped), "Contribution XP cap is data-driven and reported.")
	var empty := progression.contribution_breakdown({})
	_check(int(empty.total_xp) == 0, "Zero contribution grants zero XP.")


func _test_combat_scene_integration() -> void:
	Engine.time_scale = 20.0
	var run := DemoRunFactory.create_starting_run(8082)
	var old_gold := run.gold
	var combat = COMBAT_SCENE.instantiate()
	root.add_child(combat)
	combat.setup_run(run)
	Engine.time_scale = 20.0
	var real_start := Time.get_ticks_msec()
	while run.applied_combat_result_ids.is_empty():
		await process_frame
		if Time.get_ticks_msec() - real_start > 15000:
			_fail("Combat scene result integration exceeded watchdog.")
			break
	_check(not run.applied_combat_result_ids.is_empty(), "Combat scene applies its result to the shared RunState.")
	_check(run.gold > old_gold, "Integrated victory applies encounter Gold.")
	_check(combat.get_node("%PostBattlePanel").visible, "Integrated combat opens the Post Battle panel.")
	_check(combat.get_node("Page/VBox/Footer/RestartButton").disabled, "Finished combat cannot be replayed for duplicate rewards.")
	combat.free()
	Engine.time_scale = 1.0


func _has_soldier(run: RunState, runtime_id: String) -> bool:
	for soldier in run.soldiers:
		if soldier.unique_id == runtime_id:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
