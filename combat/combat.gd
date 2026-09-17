extends Control


signal management_requested
signal menu_requested

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

@onready var combat_session: CombatSession = %CombatSession

var speed_index := 0
var inspected_combatant: Combatant
var run_state: RunState
var current_encounter: EncounterDefinition
var battle_result_id := ""
var last_result: CombatResult


func _ready() -> void:
	combat_session.battle_finished.connect(_on_battle_finished)
	combat_session.combatant_selected.connect(_on_combatant_selected)
	tree_exiting.connect(_reset_time_scale)
	%DebugPanel.visible = get_node("/root/DevMode").enabled
	_set_speed(0)
	call_deferred("_start_demo_battle")


func _process(_delta: float) -> void:
	if %DebugPanel.visible and is_instance_valid(inspected_combatant):
		%DebugLabel.text = inspected_combatant.get_debug_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("speed_up"):
		_set_speed(speed_index + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_down"):
		_set_speed(speed_index - 1)
		get_viewport().set_input_as_handled()


func _start_demo_battle() -> void:
	%PostBattlePanel.hide_summary()
	_clear_inspector()
	%ManagementButton.disabled = true
	var run := run_state if run_state != null else DemoRunFactory.create_starting_run(1)
	run_state = run
	var enemies := CombatDemoFactory.create_enemy_army(8, 4)
	if not run.available_encounter_ids.is_empty():
		current_encounter = get_node("/root/ContentRegistry").get_definition(run.available_encounter_ids[0]) as EncounterDefinition
		enemies = CombatDemoFactory.create_enemy_army_from_encounter(current_encounter)
	battle_result_id = "combat-%d-%d-%d" % [run.run_seed, run.current_act, run.encounter_index]
	$Page/VBox/Footer/RestartButton.disabled = false
	combat_session.setup(
		CombatSnapshotBuilder.build_player_army(run, get_node("/root/ContentRegistry")),
		enemies,
		run.run_seed
	)


func setup_run(new_run_state: RunState) -> void:
	run_state = new_run_state


func _on_management_button_pressed() -> void:
	management_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()


func _on_restart_button_pressed() -> void:
	%PostBattlePanel.hide_summary()
	_clear_inspector()
	%ManagementButton.disabled = true
	$Page/VBox/Footer/RestartButton.disabled = false
	combat_session.restart_battle()


func _on_speed_down_button_pressed() -> void:
	_set_speed(speed_index - 1)


func _on_speed_up_button_pressed() -> void:
	_set_speed(speed_index + 1)


func _set_speed(new_index: int) -> void:
	speed_index = clampi(new_index, 0, SPEEDS.size() - 1)
	Engine.time_scale = SPEEDS[speed_index]
	%SpeedLabel.text = "SPEED  x%d" % int(SPEEDS[speed_index])


func _on_battle_finished(winner: StringName, duration: float, timed_out: bool) -> void:
	var progression := get_node("/root/ContentRegistry").get_definition(&"progression.demo") as ProgressionDefinition
	var result := CombatResult.from_statistics(
		battle_result_id,
		combat_session.statistics,
		current_encounter,
		timed_out,
		progression
	)
	if CombatResultApplicator.apply(result, run_state, get_node("/root/ContentRegistry")):
		last_result = result
	elif last_result != null:
		result = last_result
	%PostBattlePanel.show_result(result)
	%ManagementButton.disabled = false
	$Page/VBox/Footer/RestartButton.disabled = true


func _on_combatant_selected(combatant: Combatant) -> void:
	inspected_combatant = combatant
	if %DebugPanel.visible:
		%DebugLabel.text = combatant.get_debug_text() if is_instance_valid(combatant) else "Click a unit to inspect it."


func _clear_inspector() -> void:
	inspected_combatant = null
	%DebugLabel.text = "Click a unit to inspect it."


func _reset_time_scale() -> void:
	Engine.time_scale = 1.0
