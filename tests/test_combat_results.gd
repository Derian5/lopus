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
	EncounterService.select_encounter(run, &"encounter.training_skirmish")
	run.run_phase = &"combat"
	run.soldiers[0].current_job_id = &"job.warrior"
	run.soldiers[0].veterancy_xp = 30
	run.soldiers[1].current_job_id = &"job.archer"
	run.soldiers[1].veterancy_xp = 95
	run.soldiers[1].veterancy_level = 1
	var returned_instance_ids: Array[StringName] = [
		StringName(run.inventory.items[0].instance_id),
		StringName(run.inventory.items[1].instance_id),
	]
	run.soldiers[1].item_ids = returned_instance_ids.duplicate()
	var original_inventory_size := run.inventory.items.size()
	var original_dead_id := run.soldiers[1].unique_id

	var statistics := CombatStatistics.new()
	var player_snapshots := CombatSnapshotBuilder.build_player_army(run, registry)
	for snapshot in player_snapshots:
		statistics.register_unit(snapshot)
	var enemy := CombatDemoFactory.create_enemy_army(1, 0)[0]
	statistics.register_unit(enemy)
	var temporary_summon := CombatUnitSnapshot.new()
	temporary_summon.runtime_id = "temporary-summon"
	temporary_summon.definition_id = &"enemy.summoned_brawler"
	temporary_summon.display_name = "Temporary Summon"
	temporary_summon.team = CombatUnitSnapshot.Team.PLAYER
	temporary_summon.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
	temporary_summon.summoner_runtime_id = run.soldiers[0].unique_id
	statistics.register_unit(temporary_summon)
	statistics.consume(CombatEvent.new(1.0, CombatEvent.DAMAGE_APPLIED, "hero-00", enemy.runtime_id, &"ability.fire_bolt", &"effect.damage", 100.0))
	statistics.consume(CombatEvent.new(1.2, CombatEvent.HEALING_APPLIED, "hero-00", "soldier-00", &"ability.mending_light", &"effect.heal", 20.0))
	statistics.consume(CombatEvent.new(1.3, CombatEvent.ABILITY_USED, "hero-00", enemy.runtime_id, &"ability.fire_bolt"))
	statistics.consume(CombatEvent.new(1.4, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, "soldier-00", &"attack.basic", &"attack.basic", 100.0))
	statistics.consume(CombatEvent.new(1.5, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, original_dead_id, &"attack.basic", &"attack.basic", 30.0))
	statistics.consume(CombatEvent.new(1.51, CombatEvent.DAMAGE_APPLIED, temporary_summon.runtime_id, enemy.runtime_id, &"attack.basic", &"attack.basic", 20.0))
	statistics.consume(CombatEvent.new(1.52, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, temporary_summon.runtime_id, &"attack.basic", &"attack.basic", 15.0))
	statistics.consume(CombatEvent.new(1.53, CombatEvent.HEALING_APPLIED, temporary_summon.runtime_id, "soldier-00", &"ability.test_heal", &"effect.heal", 10.0))
	statistics.consume(CombatEvent.new(1.6, CombatEvent.UNIT_DIED, enemy.runtime_id, original_dead_id, &"", &"attack.basic"))
	statistics.consume(CombatEvent.new(1.7, CombatEvent.UNIT_DIED, enemy.runtime_id, temporary_summon.runtime_id, &"", &"attack.basic"))
	statistics.consume(CombatEvent.new(2.0, CombatEvent.UNIT_DIED, "hero-00", enemy.runtime_id, &"", &"effect.damage"))
	statistics.consume(CombatEvent.new(3.0, CombatEvent.BATTLE_FINISHED, "player", "", &"", &"", 33.0))
	var encounter := registry.get_definition(&"encounter.training_skirmish") as EncounterDefinition
	var result := CombatResult.from_statistics("result-stage8-test", statistics, encounter, false, progression)
	_check(result.get_player_deaths().size() == 1, "Temporary summons are excluded from permanent player losses.")
	var old_gold := run.gold
	var hero_contribution: Dictionary = result.get_unit_statistics("hero-00").contribution
	var expected_hero_contribution := progression.contribution_breakdown({
		"damage_dealt": 100.0,
		"effective_healing": 20.0,
		"damage_tanked": 0.0,
	})
	_check(
		int(hero_contribution.damage_xp) == int(expected_hero_contribution.damage_xp)
		and int(hero_contribution.healing_xp) == int(expected_hero_contribution.healing_xp)
		and int(hero_contribution.tanking_xp) == int(expected_hero_contribution.tanking_xp),
		"CombatResult stores XP for every contribution metric."
	)
	_check(int(hero_contribution.total_xp) == int(expected_hero_contribution.total_xp), "CombatResult stores the explainable total contribution XP.")

	_check(CombatResultApplicator.apply(result, run, registry), "A fresh CombatResult applies successfully.")
	_check(run.gold == old_gold + encounter.gold_reward, "Victory Gold is added once.")
	_check(run.heroes[0].xp == int(expected_hero_contribution.total_xp), "Hero XP is derived from damage, effective healing, and tanking contribution.")
	var expected_soldier_contribution := progression.contribution_breakdown({"damage_dealt": 20.0, "effective_healing": 10.0, "damage_tanked": 115.0})
	var expected_soldier_xp := 30 + int(expected_soldier_contribution.total_xp)
	_check(run.soldiers[0].veterancy_xp == expected_soldier_xp and run.soldiers[0].veterancy_level == progression.veterancy_level_for_xp(expected_soldier_xp), "A surviving soldier gains contribution XP and a veterancy level.")
	_check(
		is_equal_approx(float(run.soldiers[0].lifetime_statistics.damage_dealt), 20.0)
		and is_equal_approx(float(run.soldiers[0].lifetime_statistics.damage_tanked), 115.0)
		and is_equal_approx(float(run.soldiers[0].lifetime_statistics.effective_healing), 10.0),
		"Summon contribution grants its Soldier Summoner veterancy XP and lifetime statistics."
	)
	_check(not _has_soldier(run, original_dead_id), "A dead soldier is permanently removed.")
	_check(run.soldiers.size() == 9, "Victory refills each dead soldier slot with Militia.")
	var replacement := run.soldiers[-1]
	_check(replacement.unique_id != original_dead_id, "Replacement Militia receives a new unique ID.")
	_check(replacement.current_job_id == &"job.militia" and replacement.veterancy_xp == 0 and replacement.item_ids.is_empty(), "Replacement does not inherit Job, veterancy, or equipment.")
	_check(run.inventory.items.size() == original_inventory_size, "Death return does not create duplicate item instances.")
	_check(result.application_summary.returned_items.size() == 2, "Dead soldier equipment returns to Inventory.")
	_check(StringName(result.application_summary.returned_items[0].instance_id) == returned_instance_ids[0] and StringName(result.application_summary.returned_items[1].instance_id) == returned_instance_ids[1], "Death return preserves stable item instance IDs.")
	_check(result.application_summary.deaths.size() == 1 and result.application_summary.replacements.size() == 1, "CombatResult records death and refill consequences.")
	_check(int(result.application_summary.deaths[0].potential_xp) == int(progression.contribution_breakdown({"damage_tanked": 30.0}).total_xp), "A dead Soldier reports contribution XP lost to permanent death.")
	_check(not CombatResultApplicator.apply(result, run, registry), "The same CombatResult cannot apply twice.")
	_check(run.gold == old_gold + encounter.gold_reward and run.heroes[0].xp == int(expected_hero_contribution.total_xp), "Rejected reapplication changes no rewards or XP.")

	var restored := RunState.from_dictionary(run.to_dictionary())
	_check(restored.applied_combat_result_ids.has(result.result_id), "Applied result IDs survive serialization.")
	_check(is_equal_approx(float(restored.soldiers[0].lifetime_statistics.damage_tanked), 115.0), "Expanded Soldier lifetime contribution survives serialization.")
	_check(not CombatResultApplicator.apply(result, restored, registry), "A loaded run also rejects an already applied result.")

	var hero_snapshot := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	run.heroes[0].level += 1
	var leveled_snapshot := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	_check(leveled_snapshot.stats.max_hp > hero_snapshot.stats.max_hp and leveled_snapshot.stats.damage > hero_snapshot.stats.damage, "Hero level grants fixed stat growth.")
	var veteran_snapshot := CombatSnapshotBuilder.build_soldier(run.soldiers[0], run.job_builds[0], run.inventory, registry)
	run.soldiers[0].veterancy_level = 0
	var recruit_snapshot := CombatSnapshotBuilder.build_soldier(run.soldiers[0], run.job_builds[0], run.inventory, registry)
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
	EncounterService.select_encounter(run, run.available_encounter_ids[0])
	run.run_phase = &"combat"
	var dead_id := run.soldiers[0].unique_id
	var result := CombatResult.new()
	result.result_id = "result-defeat-test"
	result.winner = &"enemy"
	result.encounter_id = run.selected_encounter_id
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
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	_check(int(result.application_summary.deaths[0].potential_xp) == int(progression.contribution_breakdown({"damage_tanked": 10.0}).total_xp), "Defeat still calculates the dead Soldier contribution.")


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
	EncounterService.select_encounter(run, run.available_encounter_ids[0])
	run.run_phase = &"combat"
	var old_gold := run.gold
	var combat = COMBAT_SCENE.instantiate()
	root.add_child(combat)
	combat.setup_run(run)
	var post_battle_panel: Control = combat.get_node("%PostBattlePanel")
	_check(not post_battle_panel.visible and post_battle_panel.get_parent() == combat, "A hidden Post Battle panel cannot intercept live combat controls or unit selection.")
	var menu_requests: Array[bool] = []
	combat.menu_requested.connect(func() -> void: menu_requests.append(true))
	combat.get_node("Page/VBox/Header/MenuButton").pressed.emit()
	_check(not menu_requests.is_empty(), "The Menu button remains available during live combat.")
	combat.get_node("Page/VBox/Header/SpeedUpButton").pressed.emit()
	_check(combat.speed_index == 1, "The speed controls remain available during live combat.")
	await process_frame
	var player_statistics: Control = combat.get_node("%PlayerStatistics")
	var enemy_statistics: Control = combat.get_node("%EnemyStatistics")
	var arena: Control = combat.get_node("Page/VBox/BattleArea/Arena")
	var arena_size := arena.size
	_check(player_statistics.visible and enemy_statistics.visible, "Allied and enemy statistics remain open throughout live combat.")
	_check(player_statistics.get_node("%Rows").get_child_count() == 12, "The allied statistics panel lists every Hero and soldier.")
	_check(enemy_statistics.get_node("%Rows").get_child_count() > 0, "The enemy statistics panel lists every enemy.")
	player_statistics.get_node("%TankTab").pressed.emit()
	_check(player_statistics.selected_metric_index == 1, "Statistics tabs switch between Damage, Tank, and Heal metrics.")
	var first_enemy_row: Button = enemy_statistics.get_node("%Rows").get_child(0)
	first_enemy_row.pressed.emit()
	_check(combat.inspected_combatant != null and combat.inspected_combatant.snapshot.team == CombatUnitSnapshot.Team.ENEMY, "A statistics row selects the matching combat unit.")
	await process_frame
	_check(arena.size == arena_size, "Statistics and selected-unit overlays never resize the battle arena.")
	if not combat.combat_session.combatants.is_empty():
		combat.combat_session.combatant_selected.emit(combat.combat_session.combatants[0])
	var selected_panel: Control = combat.get_node("%SelectedUnitPanel")
	_check(combat.inspected_combatant != null and selected_panel.visible, "Selecting an arena unit opens its lower gameplay-information panel.")
	_check(selected_panel.get_node("%Stats").text.contains("HP") and selected_panel.get_node("%Stats").text.contains("DAMAGE") and selected_panel.get_node("%Stats").text.contains("ARMOR"), "Selected-unit details show current HP, damage, and armor.")
	_check(selected_panel.get_node("%Abilities").text.contains("ABILITIES") and selected_panel.get_node("%Equipment").text.contains("WEAPONS"), "Selected-unit details show abilities and equipment or basic weapon.")
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
	combat.size = Vector2(800, 600)
	await process_frame
	_check(is_equal_approx(player_statistics.size.y, combat.size.y / 3.0) and is_equal_approx(enemy_statistics.size.y, combat.size.y / 3.0), "Statistics panels occupy one third of the viewport height.")
	var continue_button: Button = combat.get_node("%PostBattlePanel/Margin/VBox/ContinueButton")
	_check(combat.get_global_rect().encloses(continue_button.get_global_rect()), "Post Battle Continue remains fully visible in a short viewport.")
	_check(is_equal_approx(post_battle_panel.get_global_rect().get_center().x, combat.get_global_rect().get_center().x), "Post Battle panel and Continue stay centered instead of shifting horizontally.")
	var management_requests: Array[bool] = []
	combat.management_requested.connect(func() -> void: management_requests.append(true))
	continue_button.pressed.emit()
	_check(not management_requests.is_empty(), "The in-panel Continue action returns to Management.")
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
