extends Control


signal new_game_requested
signal continue_requested
signal quit_requested

var save_exists := false


func _ready() -> void:
	%DebugBadge.visible = get_node("/root/DevMode").enabled
	if %ContinueButton.disabled:
		%NewGameButton.grab_focus()
	else:
		%ContinueButton.grab_focus()


func setup(save_probe: Dictionary) -> void:
	save_exists = bool(save_probe.get("exists", false))
	%ContinueButton.disabled = not bool(save_probe.get("ok", false))
	%StatusLabel.text = String(save_probe.get("status_override", "" if not save_exists else save_probe.get("message", "")))
	if not bool(save_probe.get("ok", false)) and save_exists:
		%StatusLabel.text = "%s\nStart a New Game to replace this save." % save_probe.get("status_override", save_probe.get("message", "Save cannot be loaded."))
	if not %ContinueButton.disabled:
		%ContinueButton.grab_focus()


func _on_new_game_button_pressed() -> void:
	if save_exists:
		%OverwriteConfirmation.popup_centered()
	else:
		new_game_requested.emit()


func _on_continue_button_pressed() -> void:
	continue_requested.emit()


func _on_overwrite_confirmed() -> void:
	new_game_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
