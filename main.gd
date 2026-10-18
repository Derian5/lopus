extends Node


const MAIN_MENU_SCENE := preload("res://ui/main_menu/main_menu.tscn")
const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")
const GAME_MENU_SCENE := preload("res://ui/game_menu/game_menu.tscn")
const RUN_OUTCOME_SCENE := preload("res://ui/run_outcome/run_outcome.tscn")
const EXECUTION_SCENE := preload("res://ui/execution/execution.tscn")
const ENCOUNTER_CHOICE_SCENE := preload("res://ui/encounter_choice/encounter_choice.tscn")
const HERO_SELECTION_SCENE := preload("res://ui/hero_selection/hero_selection.tscn")

@onready var screen_root: Control = $ScreenRoot
@onready var overlay_layer: CanvasLayer = $OverlayLayer

var current_screen: Control
var game_menu: Control
var can_open_game_menu := false
var active_run: RunState
var save_manager: SaveManager
var post_combat_prepared := false


func _ready() -> void:
	if save_manager == null:
		save_manager = SaveManager.new()
	show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if can_open_game_menu and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(game_menu):
			close_game_menu()
		else:
			open_game_menu()


func show_main_menu(status_message := "") -> void:
	close_game_menu()
	can_open_game_menu = false
	active_run = null
	var screen = _replace_screen(MAIN_MENU_SCENE)
	screen.new_game_requested.connect(_start_new_game)
	screen.continue_requested.connect(_continue_game)
	screen.quit_requested.connect(get_tree().quit)
	var probe := save_manager.probe(get_node("/root/ContentRegistry"))
	if not status_message.is_empty():
		probe["status_override"] = status_message
	screen.setup(probe)


func show_management() -> void:
	if active_run == null:
		show_main_menu("No active run. Start a New Game or Continue.")
		return
	if active_run.run_status != RunState.STATUS_ACTIVE:
		show_run_outcome()
		return
	if active_run.run_phase == &"execution":
		show_execution()
		return
	close_game_menu()
	can_open_game_menu = true
	active_run.run_phase = &"management"
	var screen = _replace_screen(MANAGEMENT_SCENE)
	screen.setup(active_run)
	screen.combat_requested.connect(_request_combat)
	screen.menu_requested.connect(open_game_menu)
	screen.run_state_changed.connect(_on_run_state_changed)
	screen.run_event_choice_requested.connect(_on_run_event_choice_requested)
	screen.hero_ability_reward_requested.connect(_on_hero_ability_reward_requested)


func show_encounter_choice() -> void:
	if active_run == null:
		show_main_menu("No active run. Start a New Game or Continue.")
		return
	if active_run.run_status != RunState.STATUS_ACTIVE:
		show_run_outcome()
		return
	if active_run.run_phase == &"execution":
		show_execution()
		return
	if not String(active_run.selected_encounter_id).is_empty():
		show_management()
		return
	close_game_menu()
	can_open_game_menu = true
	active_run.run_phase = &"management"
	var screen = _replace_screen(ENCOUNTER_CHOICE_SCENE)
	screen.set_run_state(active_run)
	screen.encounter_selected.connect(_on_encounter_selected)


func show_hero_selection() -> void:
	close_game_menu()
	can_open_game_menu = false
	active_run = null
	var screen = _replace_screen(HERO_SELECTION_SCENE)
	screen.selection_confirmed.connect(_begin_new_game)
	screen.back_requested.connect(show_main_menu)


func _on_encounter_selected(encounter_id: StringName) -> void:
	var result := EncounterService.select_encounter(active_run, encounter_id)
	if not result.ok:
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback(result.error, true)
		return
	var save_result := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
	if not save_result.ok:
		active_run.selected_encounter_id = &""
		active_run.encounter_committed = false
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Encounter was not saved: %s" % save_result.message, true)
		return
	show_management()


func show_combat() -> void:
	_request_combat()


func _request_combat() -> void:
	if active_run == null:
		show_main_menu("No active run is available for combat.")
		return
	if active_run.run_status != RunState.STATUS_ACTIVE:
		show_run_outcome()
		return
	if active_run.run_phase != &"management":
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Complete the current mandatory phase before starting combat.", true)
		return
	if not active_run.pending_hero_ability_reward.is_empty():
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Choose a Hero ability reward before starting combat.", true)
		return
	if String(active_run.selected_encounter_id).is_empty() or not active_run.available_encounter_ids.has(active_run.selected_encounter_id):
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Choose an Encounter Card before committing to battle.", true)
		return
	active_run.run_phase = &"management"
	var was_committed := active_run.encounter_committed
	active_run.encounter_committed = true
	var save_result := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
	if not save_result.ok:
		active_run.encounter_committed = was_committed
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Cannot start combat: %s" % save_result.message, true)
		return
	var battle_seed := active_run.combat_rng.next_seed()
	active_run.run_phase = &"combat"
	post_combat_prepared = false
	close_game_menu()
	can_open_game_menu = true
	var screen = _replace_screen(COMBAT_SCENE)
	screen.setup_run(active_run, battle_seed)
	screen.management_requested.connect(_return_from_combat)
	screen.menu_requested.connect(open_game_menu)
	screen.battle_resolved.connect(_on_battle_resolved)
	screen.run_event_choice_requested.connect(_on_run_event_choice_requested)


func _return_from_combat() -> void:
	if active_run == null:
		show_main_menu("The active run was lost.")
		return
	if active_run.run_phase == &"execution":
		show_execution()
		return
	active_run.run_phase = &"management"
	if active_run.run_status != RunState.STATUS_ACTIVE:
		show_run_outcome()
		return
	if not post_combat_prepared:
		var cycle_result := RunCycleService.prepare_next_choice(active_run, get_node("/root/ContentRegistry"))
		if not cycle_result.ok:
			show_management()
			current_screen._set_feedback("Next cycle failed: %s" % cycle_result.error, true)
			return
	show_encounter_choice()
	var result := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
	if not result.ok and is_instance_valid(current_screen):
		current_screen._set_feedback("Autosave failed: %s" % result.message, true)


func _on_battle_resolved(_result: CombatResult) -> void:
	if active_run == null:
		return
	if active_run.run_phase == &"execution":
		post_combat_prepared = false
		var execution_save := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
		if not execution_save.ok and is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Execution checkpoint autosave failed: %s" % execution_save.message, true)
		return
	active_run.run_phase = &"management"
	var cycle_result := RunCycleService.prepare_next_choice(active_run, get_node("/root/ContentRegistry"))
	if not cycle_result.ok:
		post_combat_prepared = false
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Next cycle failed: %s" % cycle_result.error, true)
		return
	post_combat_prepared = true
	var save_result := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
	if not save_result.ok and is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
		current_screen._set_feedback("Autosave failed: %s" % save_result.message, true)


func open_game_menu() -> void:
	if not can_open_game_menu or is_instance_valid(game_menu):
		return

	game_menu = GAME_MENU_SCENE.instantiate()
	overlay_layer.add_child(game_menu)
	game_menu.resume_requested.connect(close_game_menu)
	game_menu.main_menu_requested.connect(show_main_menu)
	game_menu.quit_requested.connect(get_tree().quit)
	get_tree().paused = true


func close_game_menu() -> void:
	get_tree().paused = false
	if is_instance_valid(game_menu):
		game_menu.queue_free()
	game_menu = null


func show_run_outcome() -> void:
	if active_run == null:
		show_main_menu()
		return
	close_game_menu()
	can_open_game_menu = false
	active_run.run_phase = &"management"
	var screen = _replace_screen(RUN_OUTCOME_SCENE)
	screen.setup(active_run.run_status, active_run.current_act, active_run.encounter_index)
	screen.new_run_requested.connect(_start_new_game)
	screen.main_menu_requested.connect(show_main_menu)


func show_execution() -> void:
	if active_run == null or active_run.run_phase != &"execution":
		show_management()
		return
	close_game_menu()
	can_open_game_menu = true
	var screen = _replace_screen(EXECUTION_SCENE)
	screen.setup(active_run)
	screen.execution_completed.connect(_on_execution_completed)
	screen.menu_requested.connect(open_game_menu)


func _on_execution_completed(staged_run: RunState) -> void:
	var save_result := save_manager.save_run(staged_run, get_node("/root/ContentRegistry"))
	if not save_result.ok:
		if is_instance_valid(current_screen) and current_screen.has_method("_set_feedback"):
			current_screen._set_feedback("Execution was not committed: %s" % save_result.message, true)
		return
	active_run = staged_run
	post_combat_prepared = true
	show_encounter_choice()


func _replace_screen(scene: PackedScene):
	if is_instance_valid(current_screen):
		current_screen.queue_free()

	current_screen = scene.instantiate()
	screen_root.add_child(current_screen)
	_fade_in(current_screen)
	return current_screen


## Short fade so screen changes read as deliberate transitions rather than cuts.
func _fade_in(screen: CanvasItem) -> void:
	screen.modulate.a = 0.0
	var tween := screen.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "modulate:a", 1.0, 0.22)


func _start_new_game() -> void:
	show_hero_selection()


func _begin_new_game(selected_hero_ids: Array[StringName]) -> void:
	var unique_ids: Dictionary = {}
	for hero_id in selected_hero_ids:
		var definition := get_node("/root/ContentRegistry").get_definition(hero_id, false) as HeroDefinition
		if definition == null or not definition.available_in_new_game or unique_ids.has(hero_id):
			if is_instance_valid(current_screen) and current_screen.has_method("set_feedback"):
				current_screen.set_feedback("The selected Hero roster is invalid.")
			return
		unique_ids[hero_id] = true
	if selected_hero_ids.size() != HeroSelection.REQUIRED_HEROES:
		if is_instance_valid(current_screen) and current_screen.has_method("set_feedback"):
			current_screen.set_feedback("Choose exactly three Heroes.")
		return
	var seed := int(Time.get_unix_time_from_system() * 1000000.0) ^ Time.get_ticks_usec()
	active_run = DemoRunFactory.create_starting_run(seed, selected_hero_ids)
	active_run.run_phase = &"management"
	var route := get_node("/root/ContentRegistry").get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	if route == null:
		show_main_menu("Could not prepare the opening event: demo route is missing.")
		return
	var event_result := RunEventService.prepare_specific_event(active_run, route.opening_event_id, get_node("/root/ContentRegistry"))
	if not event_result.ok:
		show_main_menu("Could not prepare the opening event: %s" % event_result.error)
		return
	var result := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
	if not result.ok:
		show_main_menu("Could not create the run save: %s" % result.message)
		return
	_request_combat()


func _continue_game() -> void:
	var result := save_manager.load_run(get_node("/root/ContentRegistry"))
	if not result.ok:
		show_main_menu(result.message)
		return
	active_run = result.run_state
	if active_run.run_status == RunState.STATUS_ACTIVE:
		if active_run.run_phase == &"execution":
			show_execution()
		elif String(active_run.selected_encounter_id).is_empty() and not active_run.available_encounter_ids.is_empty():
			show_encounter_choice()
		else:
			show_management()
	else:
		show_run_outcome()


func _on_run_state_changed(_action: StringName) -> void:
	if active_run == null or active_run.run_phase != &"management":
		return
	var result := save_manager.save_run(active_run, get_node("/root/ContentRegistry"))
	if not result.ok and is_instance_valid(current_screen):
		current_screen._set_feedback("Autosave failed: %s" % result.message, true)


func _on_run_event_choice_requested(choice_id: StringName) -> void:
	var result := RunEventService.choose(active_run, choice_id, get_node("/root/ContentRegistry"))
	if not result.ok:
		current_screen.get_node("%RunEventPopup").set_feedback(result.error)
		return
	var staged: RunState = result.run_state
	var runtime_phase := staged.run_phase
	if is_instance_valid(current_screen) and current_screen.has_method("refresh_run_event") and runtime_phase == &"combat":
		staged.run_phase = &"management"
	var save_result := save_manager.save_run(staged, get_node("/root/ContentRegistry"))
	if not save_result.ok:
		current_screen.get_node("%RunEventPopup").set_feedback("Event choice was not saved: %s" % save_result.message)
		return
	active_run = staged
	if current_screen.has_method("refresh_run_event"):
		active_run.run_phase = runtime_phase
		current_screen.refresh_run_event(active_run)
	else:
		current_screen.setup(active_run)


func _on_hero_ability_reward_requested(offer_id: String) -> void:
	var result := HeroAbilityRewardService.choose(active_run, offer_id, get_node("/root/ContentRegistry"))
	if not result.ok:
		current_screen.get_node("%HeroAbilityRewardPopup").set_feedback(result.error)
		return
	var staged: RunState = result.run_state
	var save_result := save_manager.save_run(staged, get_node("/root/ContentRegistry"))
	if not save_result.ok:
		current_screen.get_node("%HeroAbilityRewardPopup").set_feedback("Ability reward was not saved: %s" % save_result.message)
		return
	active_run = staged
	if String(active_run.selected_encounter_id).is_empty():
		show_encounter_choice()
	else:
		current_screen.setup(active_run)
