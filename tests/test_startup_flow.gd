extends SceneTree

var failures := 0
var loading_was_visible := false
var progress_was_presented := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var assets = root.get_node("StartupAssets")
	assets.progress_changed.connect(_on_progress)
	var error := change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	_check(error == OK, "The configured startup scene opens.")
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not assets.error_message.is_empty():
			push_error(assets.error_message)
			break
		if current_scene != null and current_scene.scene_file_path == "res://main.tscn":
			break
	_check(assets.prepared, "Startup preparation finishes before entering the application.")
	_check(loading_was_visible and progress_was_presented, "Loading progress is presented by the real startup screen.")
	if current_scene == null or current_scene.scene_file_path != "res://main.tscn":
		_check(false, "The loading scene transitions to the main scene.")
		quit(1)
		return
	var app = current_scene
	_check(app.active_run == null, "Asset preparation does not start a run.")
	_check(app.current_screen.has_signal("new_game_requested"), "The main menu is ready after preparation.")
	await process_frame
	app.current_screen.new_game_requested.emit()
	await process_frame
	_check(app.current_screen.has_signal("selection_confirmed"), "New Game opens Hero selection from the prepared menu.")
	app.current_screen.back_requested.emit()
	await process_frame
	_check(app.current_screen.has_signal("new_game_requested") and assets.prepared, "Returning to the menu preserves the startup cache.")
	print("Startup flow checked: loading screen -> prepared menu -> Hero selection -> menu; cache report: ", assets.report)
	unload_current_scene()
	await process_frame
	quit(1 if failures else 0)

func _on_progress(fraction: float, _message: String) -> void:
	if current_scene == null or current_scene.scene_file_path != "res://ui/loading/startup.tscn":
		return
	loading_was_visible = current_scene.is_visible_in_tree()
	var bar := current_scene.get_node("Center/Content/Progress") as ProgressBar
	# Connected before the screen's callback: observe the previously presented value.
	progress_was_presented = progress_was_presented or (fraction > 0.0 and bar.value > 0.0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
