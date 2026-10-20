extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")
const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_service_and_serialization()
	_test_first_battle_spawns()
	await _test_battlefield_preview()
	if failures == 0:
		print("Formation tests passed.")
		quit()
	else:
		push_error("Formation tests failed: %d" % failures)
		quit(1)


func _test_service_and_serialization() -> void:
	var run := DemoRunFactory.create_starting_run(31001)
	var snapshots := CombatSnapshotBuilder.build_player_army(run, registry)
	_check(snapshots.all(func(snapshot: CombatUnitSnapshot) -> bool: return not FormationService.has_custom(snapshot.formation_position)), "A new run uses the automatic formation.")

	var bounds := Rect2(Vector2(48, 48), Vector2(1600, 800))
	var automatic := FormationService.automatic_positions(snapshots, bounds, true)
	var spawn := FormationService.spawn_positions(snapshots, bounds, true)
	_check(automatic == spawn, "Without custom positions the spawn layout equals the original automatic formation.")

	var hero_id := run.heroes[0].unique_id
	var soldier_id := run.soldiers[0].unique_id
	var positions := FormationService.normalized_positions(snapshots, true)
	positions[hero_id] = Vector2(0.3, 0.2)
	positions[soldier_id] = Vector2(0.9, 1.5)
	FormationService.store_formation(run, positions)
	_check(run.formation_positions.size() == snapshots.size(), "Storing a formation freezes every current unit.")
	_check(Vector2(run.formation_positions[soldier_id]).is_equal_approx(FormationService.clamp_to_zone(Vector2(0.9, 1.5))), "Positions are clamped into the deployment zone.")

	snapshots = CombatSnapshotBuilder.build_player_army(run, registry)
	var hero_snapshot: CombatUnitSnapshot
	for snapshot in snapshots:
		if snapshot.runtime_id == hero_id:
			hero_snapshot = snapshot
	_check(hero_snapshot != null and hero_snapshot.formation_position.is_equal_approx(Vector2(0.3, 0.2)), "Combat snapshots carry the stored starting position.")
	_check(hero_snapshot.duplicate_snapshot().formation_position.is_equal_approx(Vector2(0.3, 0.2)), "Snapshot copies keep the starting position.")
	spawn = FormationService.spawn_positions(snapshots, bounds, true)
	var hero_index := snapshots.find(hero_snapshot)
	_check(spawn[hero_index].is_equal_approx(bounds.position + Vector2(0.3, 0.2) * bounds.size), "Combat spawns a unit at its custom normalized position.")
	var enemy_spawn := FormationService.spawn_positions(snapshots, bounds, false)
	_check(enemy_spawn == FormationService.automatic_positions(snapshots, bounds, false), "Enemy teams ignore player formation data.")

	var restored := RunState.from_dictionary(JSON.parse_string(JSON.stringify(run.to_dictionary())))
	_check(restored.formation_positions.size() == run.formation_positions.size() and Vector2(restored.formation_positions[hero_id]).is_equal_approx(Vector2(0.3, 0.2)), "Formation positions survive Save/Load serialization.")
	var legacy := run.to_dictionary()
	legacy.erase("formation_positions")
	_check(RunState.from_dictionary(legacy).formation_positions.is_empty(), "Saves without formation data load with the automatic formation.")

	run.formation_positions["missing-unit"] = Vector2(0.1, 0.1)
	FormationService.prune(run)
	_check(not run.formation_positions.has("missing-unit"), "Positions of units that left the army are pruned.")
	FormationService.reset(run)
	_check(run.formation_positions.is_empty(), "Reset restores the automatic formation.")


func _test_first_battle_spawns() -> void:
	var trios: Array[Array] = [[], [&"hero.ashen_duelist", &"hero.test_vanguard", &"hero.thorn_warden"]]
	for trio in trios:
		var hero_ids: Array[StringName] = []
		hero_ids.assign(trio)
		var run := DemoRunFactory.create_starting_run(31003, hero_ids)
		var army := CombatSnapshotBuilder.build_player_army(run, registry)
		var enemy := CombatUnitSnapshot.new()
		enemy.runtime_id = "formation-enemy"
		enemy.team = CombatUnitSnapshot.Team.ENEMY
		var session: CombatSession = SESSION_SCENE.instantiate()
		root.add_child(session)
		session.setup(army, [enemy], 31003)
		var expected := FormationService.spawn_positions(army, session.get_arena_bounds(), true)
		var rearmost_militia_x := INF
		for soldier in run.soldiers:
			rearmost_militia_x = minf(rearmost_militia_x, session.get_combatant_by_runtime_id(soldier.unique_id).position.x)
		for hero in run.heroes:
			_check(session.get_combatant_by_runtime_id(hero.unique_id).position.x < rearmost_militia_x, "Every starting Hero, including melee Heroes, spawns behind all nine Militia.")
		for index in army.size():
			_check(session.get_combatant_by_runtime_id(army[index].runtime_id).position.is_equal_approx(expected[index]), "Actual battle deployment matches the formation service used by the preview.")
		var custom_position := Vector2(0.4, 0.25)
		run.formation_positions[run.heroes[0].unique_id] = custom_position
		session.setup(CombatSnapshotBuilder.build_player_army(run, registry), [enemy], 31003)
		var bounds := session.get_arena_bounds()
		_check(session.get_combatant_by_runtime_id(run.heroes[0].unique_id).position.is_equal_approx(bounds.position + custom_position * bounds.size), "Manual placement still overrides automatic formation at battle start.")
		session.free()


func _test_battlefield_preview() -> void:
	var run := DemoRunFactory.create_starting_run(31002)
	run.encounter_index = 1
	run.available_encounter_ids = [&"encounter.reinforced_assault"]
	run.selected_encounter_id = &"encounter.reinforced_assault"
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	await process_frame
	await process_frame
	var saved_actions: Array[StringName] = []
	screen.run_state_changed.connect(func(action: StringName) -> void: saved_actions.append(action))
	screen.set_field_view(true)
	await process_frame
	_check(screen.get_node("%BattlefieldCard").visible and not screen.get_node("Page/Layout/ColumnsScroll/Columns/InspectorCard").visible, "The Battlefield tab replaces the inspector and market with the preview.")
	_check(screen.get_node("%FightButton").is_visible_in_tree(), "Commit to Battle stays available in the Battlefield view.")
	var preview: BattlefieldPreview = screen.get_node("%BattlefieldPreview")
	var players := preview.tokens.filter(func(token: Dictionary) -> bool: return token.team == "player")
	var enemies := preview.tokens.filter(func(token: Dictionary) -> bool: return token.team == "enemy")
	_check(players.size() == CombatSnapshotBuilder.build_player_army(run, registry).size(), "The preview shows every unit of the army.")
	_check(not enemies.is_empty(), "The preview shows the selected encounter's enemy line.")

	var first: Dictionary = players[0]
	var second: Dictionary = players[1]
	var first_start: Vector2 = first.pos
	var second_start: Vector2 = second.pos
	_check(preview.move_unit(first.id, second_start), "A player unit can be moved.")
	_check(Vector2(first.pos).is_equal_approx(FormationService.snap(second_start)) and Vector2(second.pos).is_equal_approx(first_start), "Dropping a unit onto another swaps their places.")
	_check(run.formation_positions.size() == players.size() and saved_actions.has(&"formation_changed"), "Moving a unit stores the formation and triggers an autosave.")
	_check(not preview.move_unit(String(enemies[0].id), Vector2(0.2, 0.2)), "Enemy units cannot be moved.")
	preview.move_unit(first.id, Vector2(0.95, 0.5))
	_check(Vector2(first.pos).x <= FormationService.DEPLOY_ZONE.end.x + 0.001, "Units cannot leave the deployment zone.")

	screen.get_node("%ResetFormationButton").pressed.emit()
	_check(run.formation_positions.is_empty(), "Auto Formation clears custom positions.")
	screen.get_node("%ArmyViewTab").pressed.emit()
	_check(not screen.get_node("%BattlefieldCard").visible and screen.get_node("Page/Layout/ColumnsScroll/Columns/InspectorCard").visible, "The Army tab restores the build view.")
	screen.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
