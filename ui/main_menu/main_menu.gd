extends Control


signal new_game_requested
signal quit_requested


func _ready() -> void:
	%DebugBadge.visible = DevMode.enabled
	%NewGameButton.grab_focus()


func _on_new_game_button_pressed() -> void:
	new_game_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
