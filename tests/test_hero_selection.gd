extends SceneTree


const HERO_SELECTION_SCENE := preload("res://ui/hero_selection/hero_selection.tscn")
const MAIN_SCENE := preload("res://main.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	await _test_carousel_and_order()
	await _test_main_new_game_flow()
	if failures == 0:
		print("Hero selection tests passed.")
		quit()
	else:
		push_error("Hero selection tests failed: %d" % failures)
		quit(1)


func _test_carousel_and_order() -> void:
	var screen := HERO_SELECTION_SCENE.instantiate() as HeroSelection
	root.add_child(screen)
	await process_frame
	_check(screen.heroes.size() == 7, "New Game carousel loads exactly seven selectable Heroes from content.")
	var expected_names := ["Pride", "Greed", "Wrath", "Envy", "Lust", "Gluttony", "Despair"]
	var expected_ranged := [true, false, false, true, false, false, true]
	var expected_colors := [
		Color(0.58, 0.32, 0.86, 1),
		Color(0.95, 0.78, 0.2, 1),
		Color(0.86, 0.18, 0.16, 1),
		Color(0.24, 0.72, 0.3, 1),
		Color(0.92, 0.36, 0.66, 1),
		Color(0.95, 0.48, 0.14, 1),
		Color(0.24, 0.48, 0.88, 1),
	]
	var orders: Dictionary = {}
	for index in screen.heroes.size():
		var hero := screen.heroes[index]
		_check(hero.base_stats != null and not hero.display_name.is_empty() and not hero.description.is_empty(), "Every selectable Hero has card text and complete stats.")
		_check(not orders.has(hero.selection_order), "Selectable Hero ordering values are unique.")
		_check(hero.display_name == expected_names[index], "Hero %d uses the authored sin name." % (index + 1))
		_check(hero.tags.has(&"ranged") == expected_ranged[index], "%s uses the authored melee/ranged attack type." % hero.display_name)
		_check(hero.placeholder_color.is_equal_approx(expected_colors[index]), "%s uses the authored identity color." % hero.display_name)
		orders[hero.selection_order] = true
	_check(screen.get_node("%HeroName").text == screen.heroes[0].display_name.to_upper(), "The first authored Hero appears on the initial card.")
	_check(screen.get_node("%HpValue").text == "%d" % int(screen.heroes[0].base_stats.max_hp), "Hero card displays base characteristics.")
	screen._on_previous_pressed()
	_check(screen.current_index == 6, "Left arrow wraps from the first Hero to the seventh.")
	screen._on_next_pressed()
	_check(screen.current_index == 0, "Right arrow wraps back to the first Hero.")

	var expected_order: Array[StringName] = []
	for index in 3:
		screen.current_index = index
		screen._refresh()
		screen._on_select_pressed()
		expected_order.append(screen.heroes[index].id)
	_check(screen.selected_hero_ids == expected_order and not screen.get_node("%StartButton").disabled, "Selecting three Heroes preserves click order and enables START RUN.")
	screen.current_index = 1
	screen._refresh()
	_check(screen.get_node("%SelectedOverlay").visible and screen.get_node("%SelectedOverlay").text == "SELECTED  #2", "Selected Hero card displays its roster order overlay.")
	screen._on_select_pressed()
	_check(screen.selected_hero_ids == [expected_order[0], expected_order[2]] and screen.get_node("%StartButton").disabled, "REMOVE cancels a selection before the run starts.")
	screen.current_index = 3
	screen._refresh()
	screen._on_select_pressed()
	var final_order: Array[StringName] = [expected_order[0], expected_order[2], screen.heroes[3].id]
	_check(screen.selected_hero_ids == final_order, "A replacement Hero is appended in the new selection order.")
	var emitted: Array[Array] = []
	screen.selection_confirmed.connect(func(hero_ids: Array[StringName]) -> void: emitted.append(hero_ids))
	screen._on_start_pressed()
	_check(emitted.size() == 1 and emitted[0] == final_order, "START RUN emits exactly the ordered three-Hero roster.")
	screen.free()


func _test_main_new_game_flow() -> void:
	var directory := "user://tests/hero-selection-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(directory)
	manager.delete_save()
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame
	_check(main.current_screen.name == "HeroSelection" and main.active_run == null and not manager.has_any_save(), "NEW GAME opens Hero Selection before creating a run or save.")
	var invalid_selection: Array[StringName] = [&"hero.test_vanguard", &"hero.test_vanguard", &"hero.army_support"]
	main._begin_new_game(invalid_selection)
	_check(main.current_screen.name == "HeroSelection" and main.active_run == null and not manager.has_any_save(), "Invalid or duplicate Hero selections cannot create a run.")
	var selected: Array[StringName] = [&"hero.glass_arcanist", &"hero.test_vanguard", &"hero.thorn_warden"]
	main._begin_new_game(selected)
	await process_frame
	_check(main.current_screen.name == "Management" and manager.has_any_save(), "Confirming three Heroes creates the initial run and opens Management.")
	var actual: Array[StringName] = []
	for hero in main.active_run.heroes:
		actual.append(hero.definition_id)
	_check(actual == selected, "The starting roster preserves the player's Hero selection order.")
	var loaded := manager.load_run(registry)
	var loaded_ids: Array[StringName] = []
	if loaded.ok:
		for hero in loaded.run_state.heroes:
			loaded_ids.append(hero.definition_id)
	_check(loaded.ok and loaded_ids == selected, "The selected Hero roster is persisted in the first autosave.")
	main.free()
	manager.delete_save()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
