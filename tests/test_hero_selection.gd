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
	var project_theme := ThemeDB.get_project_theme()
	var interface_font := project_theme.default_font as FontVariation
	_check(interface_font != null and interface_font.base_font.resource_path == "res://graphics/fonts/Lora-Variable.ttf" and int(interface_font.opentype_features.get("lnum", 0)) == 1, "The global interface uses the Lora book serif with full-height lining numerals.")
	_check(screen.get_node("%Title") is Label and screen.get_node("%Title").text == "CHOOSE THREE HEROES", "The Hero Selection title is live text rather than atlas artwork.")
	_check(screen.heroes.size() == 7, "New Game carousel loads exactly seven selectable Heroes from content.")
	var expected_names := ["Pride", "Greed", "Wrath", "Envy", "Lust", "Gluttony", "Despair"]
	var expected_ranged := [true, false, false, true, true, false, true]
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
		_check(hero.portrait != null, "%s uses its authored portrait." % hero.display_name)
		_check(not orders.has(hero.selection_order), "Selectable Hero ordering values are unique.")
		_check(hero.display_name == expected_names[index], "Hero %d uses the authored sin name." % (index + 1))
		_check(hero.tags.has(&"ranged") == expected_ranged[index], "%s uses the authored melee/ranged attack type." % hero.display_name)
		_check(hero.placeholder_color.is_equal_approx(expected_colors[index]), "%s uses the authored identity color." % hero.display_name)
		orders[hero.selection_order] = true
	_check(screen.center_card.hero_name.text == screen.heroes[0].display_name.to_upper(), "The first authored Hero appears on the central card.")
	_check(screen.center_card.get_node("%Description").get_theme_font_size("font_size") == 18, "Hero descriptions use the enlarged readable card font.")
	_check(screen.center_card.get_node("%HpValue").text == "%d" % int(screen.heroes[0].base_stats.max_hp), "Hero card displays base characteristics.")
	var stats_center: CenterContainer = screen.center_card.get_node("VisualRoot/StatsCenter")
	var stats_grid: GridContainer = stats_center.get_node("Stats")
	_check(screen.center_card.get_node("%HpIcon").custom_minimum_size == Vector2(34, 34) and screen.center_card.get_node("%HpValue").get_theme_font_size("font_size") == 20, "Hero card uses enlarged stat icons and values.")
	_check(is_equal_approx(stats_grid.position.x + stats_grid.size.x * 0.5, stats_center.size.x * 0.5), "Hero stats are centered within the card.")
	_check(screen.center_card.portrait.visible and not screen.center_card.initials.visible, "An illustrated Hero displays its portrait instead of fallback initials.")
	_check(is_zero_approx(screen.center_card.portrait.position.y) and screen.center_card.portrait.size.y >= screen.center_card.get_node("%PortraitClip").size.y, "Hero portraits are cover-scaled and anchored to the top edge so faces remain visible.")
	_check(screen.previous_card.hero == screen.heroes[6] and screen.next_card.hero == screen.heroes[1], "The three-card carousel previews the previous and next Heroes around the active Hero.")
	_check(screen.center_card.get_node("%Backdrop").texture is AtlasTexture and screen.center_card.get_node("%Badge").texture is AtlasTexture, "Hero cards use cropped regions from the UI atlas.")
	var ornament_frame := screen.center_card.get_node("%OrnamentFrame") as Control
	_check(ornament_frame != null and ornament_frame.mouse_filter == Control.MOUSE_FILTER_IGNORE and not ornament_frame.clip_contents, "Hero cards use a non-blocking transparent ornament layer around their artwork.")
	_check(screen.center_card.find_child("SelectButton", true, false) == null, "Hero cards no longer contain a separate Select button.")
	_check(screen.center_card.button_motion.hover_scale > screen.previous_card.button_motion.hover_scale and screen.previous_card.button_motion.hover_scale > 1.0 and screen.next_card.button_motion.hover_scale > 1.0, "All Hero cards react to hover while the central selection keeps the strongest effect.")
	screen.center_card.button_motion.set_process(false)
	screen.center_card.card_hitbox.mouse_entered.emit()
	screen.center_card.card_hitbox.button_down.emit()
	screen.center_card.card_hitbox.mouse_exited.emit()
	screen.center_card.button_motion._process(0.0)
	await create_timer(0.15).timeout
	_check(not screen.center_card.card_hitbox.has_focus() and screen.center_card.get_node("%VisualRoot").scale.is_equal_approx(Vector2.ONE), "Releasing a Hero card outside its bounds clears pointer focus plus hover and pressed scaling.")
	screen.center_card.card_hitbox.mouse_entered.emit()
	await create_timer(0.15).timeout
	_check(screen.center_card.get_node("%VisualRoot").scale.is_equal_approx(Vector2.ONE * screen.center_card.button_motion.hover_scale), "Hover recovers after a press is released outside the Hero card.")
	screen.center_card.card_hitbox.mouse_exited.emit()
	screen.previous_card.card_hitbox.pressed.emit()
	_check(screen.current_index == 6 and screen.selected_hero_ids.is_empty(), "Clicking the left preview navigates like the left arrow without selecting its Hero.")
	screen.next_card.card_hitbox.pressed.emit()
	_check(screen.current_index == 0 and screen.selected_hero_ids.is_empty(), "Clicking the right preview navigates like the right arrow without selecting its Hero.")
	screen.center_card.card_hitbox.pressed.emit()
	_check(screen.selected_hero_ids == [screen.heroes[0].id], "Clicking the full active card selects its Hero.")
	screen.center_card.card_hitbox.pressed.emit()
	_check(screen.selected_hero_ids.is_empty(), "Clicking a selected card removes its Hero from the roster.")
	screen._on_previous_pressed()
	_check(screen.current_index == 6, "Left arrow wraps from the first Hero to the seventh.")
	_check(screen.center_card.portrait.visible and not screen.center_card.initials.visible, "The seventh Hero displays its portrait.")
	var despair_portrait: Texture2D = screen.heroes[6].portrait
	screen.heroes[6].portrait = null
	screen._refresh()
	_check(not screen.center_card.portrait.visible and screen.center_card.initials.visible, "A Hero without artwork displays fallback initials.")
	screen.heroes[6].portrait = despair_portrait
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
	_check(screen.center_card.selected_order == 1 and screen.center_card.ornament_frame.selected and screen.center_card.ornament_frame.selected_order == 1, "Selected Hero card frame displays its roster order with two crown gems.")
	_check(not screen.next_card.ornament_frame.selected or screen.selected_hero_ids.has(screen.next_card.hero.id), "Only selected Heroes use the selected card frame.")
	var roster_slots: Array[Dictionary] = screen.roster_slots
	_check(roster_slots.size() == 3, "Hero Selection shows three roster slots instead of a text summary.")
	_check(roster_slots[1]["hero_id"] == expected_order[1] and roster_slots[1]["badge"].visible and not roster_slots[1]["gem"].visible, "A filled roster slot shows the selected Hero badge in selection order.")
	screen.current_index = 0
	screen._on_roster_slot_pressed(2)
	_check(screen.current_index == 2 and screen.selected_hero_ids.size() == 3, "Clicking a roster slot focuses its Hero without changing the selection.")
	screen.current_index = 1
	screen._refresh()
	screen._on_select_pressed()
	_check(screen.selected_hero_ids == [expected_order[0], expected_order[2]] and screen.get_node("%StartButton").disabled, "REMOVE cancels a selection before the run starts.")
	_check(not screen.center_card.ornament_frame.selected and screen.roster_slots[2]["gem"].visible and not screen.roster_slots[2]["badge"].visible, "Removing a Hero clears its card frame and empties the last roster slot.")
	screen.current_index = 3
	screen._refresh()
	screen._on_select_pressed()
	var final_order: Array[StringName] = [expected_order[0], expected_order[2], screen.heroes[3].id]
	_check(screen.selected_hero_ids == final_order, "A replacement Hero is appended in the new selection order.")
	var emitted: Array[Array] = []
	screen.selection_confirmed.connect(func(hero_ids: Array[StringName]) -> void: emitted.append(hero_ids))
	screen._on_start_pressed()
	_check(emitted.size() == 1 and emitted[0] == final_order, "START RUN emits exactly the ordered three-Hero roster.")
	screen.size = Vector2(1280.0, 720.0)
	screen._apply_design_scale()
	_check(is_equal_approx(screen.get_node("%DesignRoot").scale.x, 2.0 / 3.0), "Hero Selection scales its 1920x1080 composition down to 1280x720.")
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
	_check(main.current_screen.name == "Combat" and manager.has_any_save(), "Confirming three Heroes creates the initial run and opens the battlefield.")
	_check(main.active_run.pending_event.event_id == &"event.opening_march" and main.current_screen.get_node("%RunEventPopup").visible, "The opening story event appears over the battlefield before combat starts.")
	_check(main.current_screen.get_node("%CombatSession").combatants.is_empty(), "The first battle waits for the opening story event.")
	var opening_steps := 0
	while not main.active_run.pending_event.is_empty() and opening_steps < 4:
		var event := registry.get_definition(main.active_run.pending_event.event_id) as RunEventDefinition
		var node := event.get_node_definition(main.active_run.pending_event.node_id)
		_check(node.choices.size() == 1, "Every opening story node has exactly one linear choice.")
		main._on_run_event_choice_requested(node.choices[0].choice_id)
		opening_steps += 1
	_check(main.active_run.pending_event.is_empty(), "The fourth opening choice completes the linear story.")
	_check(main.current_screen.get_node("%CombatSession").combatants.size() == 14, "Completing the story starts the selected Heroes and Soldiers against two ogres.")
	main.active_run.encounter_index = 1
	main.active_run.selected_encounter_id = &""
	main.active_run.available_encounter_ids.clear()
	main.active_run.encounter_committed = false
	main._on_battle_resolved(CombatResult.new())
	_check(main.active_run.pending_event.event_id == &"event.strategy_disagreement" and not main.current_screen.get_node("%RunEventPopup").visible, "Strategy Disagreement is prepared after the first battle without opening over the battlefield.")
	main.show_encounter_choice()
	await process_frame
	main._on_encounter_selected(main.active_run.available_encounter_ids[0])
	await process_frame
	_check(main.current_screen.name == "Management" and main.current_screen.get_node("%RunEventPopup").visible, "Strategy Disagreement appears in Management after the next Encounter is selected.")
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
