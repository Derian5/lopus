extends Control


signal combat_requested
signal menu_requested


func _ready() -> void:
	%FightButton.grab_focus()


func _on_fight_button_pressed() -> void:
	combat_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()
