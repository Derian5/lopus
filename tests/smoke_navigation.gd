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
	root.add_child(main)
	await process_frame

	if main.current_screen.name != "MainMenu":
		_fail("Main menu was not shown on startup.")
		return

	main.show_management()
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

	print("Navigation smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
