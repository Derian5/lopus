extends Control


signal management_requested
signal menu_requested
signal battle_resolved(result: CombatResult)

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

@onready var combat_session: CombatSession = %CombatSession
@onready var player_statistics = %PlayerStatistics
@onready var enemy_statistics = %EnemyStatistics
@onready var selected_unit_panel = %SelectedUnitPanel

var speed_index := 0
var inspected_combatant: Combatant
var run_state: RunState
var current_encounter: EncounterDefinition
var battle_result_id := ""
var last_result: CombatResult
var battle_seed := 0
var statistics_refresh_timer := 0.0
var statistics_dirty := true


func _ready() -> void:
	combat_session.battle_finished.connect(_on_battle_finished)
	combat_session.combat_event_emitted.connect(_on_combat_event_emitted)
	combat_session.combatant_selected.connect(_on_combatant_selected)
	%PostBattlePanel.continue_requested.connect(_on_management_button_pressed)
	player_statistics.setup("ALLIES", CombatUnitSnapshot.Team.PLAYER)
	enemy_statistics.setup("ENEMIES", CombatUnitSnapshot.Team.ENEMY)
	player_statistics.unit_requested.connect(_on_statistics_unit_requested)
	enemy_statistics.unit_requested.connect(_on_statistics_unit_requested)
	tree_exiting.connect(_reset_time_scale)
	_set_speed(0)
	call_deferred("_start_demo_battle")


func _process(delta: float) -> void:
	statistics_refresh_timer += delta
	if statistics_refresh_timer < 0.1:
		return
	statistics_refresh_timer = 0.0
	if statistics_dirty and player_statistics.visible:
		_refresh_statistics()
	if selected_unit_panel.visible:
		selected_unit_panel.refresh()


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
	var reinforcements: Array[CombatUnitSnapshot] = []
	var reinforcement_threshold := -1
	var reinforcement_direction := EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE
	if not String(run.selected_encounter_id).is_empty():
		current_encounter = get_node("/root/ContentRegistry").get_definition(run.selected_encounter_id) as EncounterDefinition
		enemies = CombatDemoFactory.create_enemy_army_from_encounter(current_encounter)
		if current_encounter.has_reinforcements():
			reinforcements = CombatDemoFactory.create_reinforcement_army_from_encounter(current_encounter)
			reinforcement_threshold = current_encounter.reinforcement_alive_threshold
			reinforcement_direction = current_encounter.reinforcement_entry_direction
	battle_result_id = "combat-%d-%d-%d" % [run.run_seed, run.current_act, run.encounter_index]
	$Page/VBox/Footer/RestartButton.disabled = false
	combat_session.setup(
		CombatSnapshotBuilder.build_player_army(run, get_node("/root/ContentRegistry")),
		enemies,
		battle_seed if battle_seed != 0 else run.run_seed,
		reinforcements,
		reinforcement_threshold,
		reinforcement_direction
	)
	player_statistics.set_statistics(combat_session.statistics)
	enemy_statistics.set_statistics(combat_session.statistics)
	statistics_dirty = true


func setup_run(new_run_state: RunState, new_battle_seed := 0) -> void:
	run_state = new_run_state
	battle_seed = new_battle_seed


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
	statistics_dirty = true


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
		battle_resolved.emit(result)
	elif last_result != null:
		result = last_result
	%PostBattlePanel.show_result(result)
	_refresh_statistics()
	%ManagementButton.disabled = false
	$Page/VBox/Footer/RestartButton.disabled = true


func _on_combatant_selected(combatant: Combatant) -> void:
	inspected_combatant = combatant
	selected_unit_panel.show_combatant(combatant)


func _clear_inspector() -> void:
	inspected_combatant = null
	selected_unit_panel.clear()


func _on_combat_event_emitted(_event: CombatEvent) -> void:
	statistics_dirty = true


func _on_statistics_unit_requested(runtime_id: String) -> void:
	combat_session.select_combatant_by_runtime_id(runtime_id)


func _refresh_statistics() -> void:
	player_statistics.refresh()
	enemy_statistics.refresh()
	statistics_dirty = false


func _reset_time_scale() -> void:
	Engine.time_scale = 1.0
