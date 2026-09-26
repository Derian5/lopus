extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if ProjectSettings.get_setting("rendering/renderer/rendering_method") != "gl_compatibility":
		_fail("Compatibility renderer is not enabled.")
		return

	for bus_name in [&"Master", &"Music", &"SFX", &"UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			_fail("Missing audio bus: %s" % bus_name)
			return

	var main_scene: PackedScene = load("res://main.tscn")
	var main = main_scene.instantiate()
	var save_directory := "user://tests/navigation-%d" % Time.get_ticks_usec()
	main.save_manager = SaveManager.new(save_directory)
	root.add_child(main)
	await process_frame

	if main.current_screen.name != "MainMenu":
		_fail("Main menu was not shown on startup.")
		return

	main._start_new_game()
	await process_frame
	if main.current_screen.name != "HeroSelection":
		_fail("New Game did not open Hero Selection.")
		return
	main._begin_new_game(DemoRunFactory.HERO_IDS)
	await process_frame
	if main.current_screen.name != "Management":
		_fail("Management screen transition failed.")
		return

	main.open_game_menu()
	if not paused or not is_instance_valid(main.game_menu):
		_fail("Game menu did not pause the management screen.")
		return

	main.close_game_menu()
	await process_frame
	if paused:
		_fail("Closing the game menu did not resume the tree.")
		return

	main.active_run.encounter_index = 1
	if not EncounterService.begin_choice(main.active_run, root.get_node("ContentRegistry")).ok:
		_fail("Could not prepare a post-battle Encounter choice.")
		return
	main.show_encounter_choice()
	await process_frame
	if main.current_screen.name != "EncounterChoice":
		_fail("Standalone Encounter choice transition failed.")
		return
	main._on_encounter_selected(main.active_run.available_encounter_ids[0])
	await process_frame
	if main.current_screen.name != "Management":
		_fail("Encounter selection did not continue to Management.")
		return
	main.show_combat()
	await process_frame
	if main.current_screen.name != "Combat":
		_fail("Combat screen transition failed.")
		return

	main.open_game_menu()
	if not paused or not is_instance_valid(main.game_menu):
		_fail("Game menu did not pause the combat screen.")
		return

	main.show_main_menu()
	await process_frame
	if paused or main.current_screen.name != "MainMenu":
		_fail("Returning to the main menu failed.")
		return

	main.save_manager.delete_save()
	print("Navigation smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
