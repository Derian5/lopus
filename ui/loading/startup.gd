extends Control

func _ready() -> void:
	%QuitButton.pressed.connect(get_tree().quit)
	call_deferred("_prepare_game")

func _prepare_game() -> void:
	var assets = get_node("/root/StartupAssets")
	assets.progress_changed.connect(_on_progress)
	# Present the loading screen before any heavy initialization starts.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var success: bool = await assets.prepare()
	if not success:
		%Status.text = "Loading failed: %s" % assets.error_message
		%QuitButton.show()
		return
	await get_tree().process_frame
	get_tree().change_scene_to_packed(assets.main_scene)

func _on_progress(fraction: float, message: String) -> void:
	%Progress.value = fraction * 100.0
	%Status.text = message
