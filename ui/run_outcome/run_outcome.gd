extends Control


signal new_run_requested
signal main_menu_requested


func setup(run_status: StringName, act: int, encounter_index: int) -> void:
	if run_status == RunState.STATUS_DEFEAT:
		%Eyebrow.text = "THE ARMY HAS FALLEN"
		%Title.text = "RUN DEFEAT"
		%Body.text = "The campaign ended in Act %d after %d completed battles in this act.\nThe next run begins with a fresh army, market, and route." % [act, encounter_index]
	else:
		%Eyebrow.text = "STEAM DEMO COMPLETE"
		%Title.text = "THE WAR CONTINUES"
		%Body.text = "You survived Act I and completed all three battles of Act II.\nThank you for playing Can Be Only One Hero."
	var victory := run_status != RunState.STATUS_DEFEAT
	var ornament := $Center/Panel/Ornament as OrnateFrame
	ornament.accent_color = UiStyle.GOLD if victory else Color(0.86, 0.3, 0.24)
	ornament.corner_gem = &"gold" if victory else &"red"
	%Eyebrow.add_theme_color_override("font_color", Color(0.98, 0.84, 0.5) if victory else Color(0.95, 0.55, 0.45))
	%NewRunButton.grab_focus()


func set_status(message: String) -> void:
	%StatusLabel.text = message


func _on_new_run_pressed() -> void:
	new_run_requested.emit()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()
