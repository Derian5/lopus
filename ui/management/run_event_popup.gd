class_name RunEventPopup
extends Control


signal choice_selected(choice_id: StringName)

var run_state: RunState
var _accent := Color(0.67, 0.49, 0.22)


func show_pending(new_run_state: RunState) -> void:
	run_state = new_run_state
	if run_state == null or run_state.pending_event.is_empty():
		visible = false
		return
	var event := _registry().get_definition(run_state.pending_event.event_id, false) as RunEventDefinition
	var node := event.get_node_definition(run_state.pending_event.node_id) if event != null else null
	if event == null or node == null:
		visible = false
		return
	_apply_event_theme(event)
	%EventTitle.text = node.title if not node.title.is_empty() else event.display_name
	%EventBody.text = _format_text(node.body)
	%Feedback.text = ""
	_clear_choices()
	for choice in node.choices:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 18)
		button.text = _format_text(choice.text)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var status := RunEventService.choice_status(run_state, choice, _registry())
		button.disabled = not status.ok
		button.tooltip_text = status.error if not status.ok else ""
		UiStyle.apply_accent_button(button, _accent)
		button.pressed.connect(_on_choice_pressed.bind(choice.choice_id))
		%Choices.add_child(button)
	visible = true
	get_viewport().gui_release_focus()


func set_feedback(message: String) -> void:
	%Feedback.text = message


func _on_choice_pressed(choice_id: StringName) -> void:
	choice_selected.emit(choice_id)


func _apply_event_theme(event: RunEventDefinition) -> void:
	var hero := _registry().get_definition(event.theme_hero_id, false) as HeroDefinition
	var accent := hero.placeholder_color if hero != null else Color(0.67, 0.49, 0.22)
	_accent = accent
	var panel_style := UiStyle.accent_panel(accent, true, 18)
	panel_style.content_margin_left = 18
	panel_style.content_margin_top = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_bottom = 18
	panel_style.modulate_color = accent.lightened(0.22)
	$Center/Panel.add_theme_stylebox_override("panel", panel_style)
	var ornament := $Center/Panel/Ornament as OrnateFrame
	ornament.accent_color = accent
	ornament.corner_gem = OrnateFrame.gem_for_color(accent)
	$Center/Panel/Margin/VBox/Eyebrow.text = "%s EVENT" % (hero.display_name.to_upper() if hero != null else "ROAD")
	$Center/Panel/Margin/VBox/Eyebrow.add_theme_color_override("font_color", accent.lightened(0.12))
	%EventTitle.add_theme_color_override("font_color", accent.lightened(0.34))


func _format_text(text: String) -> String:
	var result := text
	for index in run_state.pending_event.target_ids.size():
		var target_id := run_state.pending_event.target_ids[index]
		var target_name := target_id
		for soldier in run_state.soldiers:
			if soldier.unique_id == target_id:
				var job := _registry().get_definition(soldier.current_job_id, false) as JobDefinition
				target_name = soldier.display_name(job.display_name) if job != null else soldier.generated_name
				break
		result = result.replace("{soldier_%d}" % index, target_name)
	return result


func _clear_choices() -> void:
	for child in %Choices.get_children():
		child.visible = false
		child.queue_free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
