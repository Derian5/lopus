extends SceneTree


const COMBAT_SCENE := preload("res://combat/combat.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var combat = COMBAT_SCENE.instantiate()
	combat.battle_started = true
	root.add_child(combat)
	combat.set_process(false)
	combat.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	combat.size = Vector2(1200, 720)
	var allies := combat.get_node("%PlayerStatistics") as CombatStatisticsPanel
	var enemies := combat.get_node("%EnemyStatistics") as CombatStatisticsPanel
	var statistics := CombatStatistics.new()
	statistics.register_unit(_unit("ally", CombatUnitSnapshot.Team.PLAYER))
	statistics.register_unit(_unit("enemy", CombatUnitSnapshot.Team.ENEMY))
	statistics.unit_stats["ally"]["damage_dealt"] = 120.0
	statistics.unit_stats["ally"]["damage_tanked"] = 33.0
	statistics.unit_stats["enemy"]["damage_dealt"] = 80.0
	allies.set_statistics(statistics)
	enemies.set_statistics(statistics)
	await _layout()
	var background := allies.get_theme_stylebox("panel") as StyleBoxFlat
	_check(background != null and background.bg_color.a > 0.7 and background.bg_color.a < 0.85 and allies.modulate.a == 1.0, "Only the panel background is translucent; text and controls retain full opacity.")
	_check(allies.get_node("%Title").text.contains("120") and enemies.get_node("%Title").text.contains("80"), "Both headers show their own totals.")
	var original_rect := allies.get_global_rect()
	var arena: Control = combat.get_node("Page/VBox/BattleArea/Arena")
	var arena_size := arena.size
	var enemy_height := enemies.size.y
	allies.get_node("%TankTab").pressed.emit()
	allies.get_node("%CollapseButton").toggled.emit(true)
	await _layout()
	_check(allies.collapsed and not allies.get_node("%Tabs").visible and not allies.get_node("%Scroll").visible, "Collapse hides the metric tabs and ranking list.")
	_check(allies.size.y < 75.0 and allies.size.y < original_rect.size.y * 0.5, "The panel really shrinks to a compact header.")
	_check(is_equal_approx(allies.size.x, original_rect.size.x) and allies.get_global_rect().position.is_equal_approx(original_rect.position), "Collapse preserves panel width and top position: before %s, after %s." % [original_rect, allies.get_global_rect()])
	_check(not allies.get_global_rect().has_point(original_rect.position + Vector2(20, original_rect.size.y - 10)), "The released area no longer belongs to the panel's mouse-catching rectangle.")
	_check(arena.size.is_equal_approx(arena_size) and not enemies.collapsed and is_equal_approx(enemies.size.y, enemy_height), "Collapsing one side neither resizes the arena nor affects the other side.")
	_check(allies.get_node("%CollapseButton").text == "+" and allies.get_node("%Title").is_visible_in_tree(), "The total and expand button remain visible.")
	statistics.unit_stats["ally"]["damage_tanked"] = 77.0
	allies.refresh()
	_check(allies.selected_metric_index == 1 and allies.get_node("%Title").text.contains("77"), "Collapsed headers keep updating the currently selected metric.")
	combat.size.y = 960
	await _layout()
	_check(allies.size.y < 75.0, "Resizing the window keeps the collapsed header compact.")
	allies.get_node("%CollapseButton").toggled.emit(false)
	await _layout()
	_check(not allies.collapsed and allies.get_node("%Tabs").visible and allies.get_node("%Scroll").visible, "Expand restores the tabs and rows.")
	_check(is_equal_approx(allies.size.y, combat.size.y / 3.0) and is_equal_approx(enemies.size.y, combat.size.y / 3.0), "Expansion restores the original viewport-relative height after a window resize.")
	_check(allies.selected_metric_index == 1 and allies.get_node("%TankTab").button_pressed and allies.get_node("%Rows").get_child_count() == 1, "The selected metric and data survive collapse and expansion.")
	var requests: Array[String] = []
	allies.unit_requested.connect(func(id: String) -> void: requests.append(id))
	allies.get_node("%Rows").get_child(0).pressed.emit()
	_check(requests == ["ally"], "Ranking rows still request unit inspection after expansion.")
	enemies.get_node("%CollapseButton").toggled.emit(true)
	await _layout()
	_check(enemies.collapsed and not allies.collapsed and enemies.size.y < 75.0, "Enemy statistics have their own independent collapse button.")
	combat.free()
	if failures == 0:
		print("Combat statistics panel tests passed: translucent background, independent collapse, live totals, resize and expansion.")
		quit()
	else:
		quit(1)


func _layout() -> void:
	await process_frame
	await process_frame


func _unit(id: String, team: int) -> CombatUnitSnapshot:
	var unit := CombatUnitSnapshot.new()
	unit.runtime_id = id
	unit.display_name = id
	unit.team = team
	unit.definition_id = &"job.militia" if team == CombatUnitSnapshot.Team.PLAYER else &"enemy.raider"
	unit.job_id = &"job.militia" if team == CombatUnitSnapshot.Team.PLAYER else &""
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
