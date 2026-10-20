extends Control


signal execution_completed(run_state: RunState)
signal menu_requested

const COMBATANT_SCENE := preload("res://combat/combatant.tscn")

var run_state: RunState
var selected_hero_id := ""
var favorite_hero_id := ""
var cutscene_delay_scale := 1.0
var cutscene_actors: Dictionary = {}
var execution_in_progress := false


func setup(new_run_state: RunState) -> void:
	run_state = new_run_state
	if is_node_ready():
		_refresh()


func _ready() -> void:
	%ConfirmationPanel.add_theme_stylebox_override("panel", UiStyle.chamfer_box(
		Color(0.045, 0.025, 0.022), UiStyle.BRONZE_DARK, 1, 10,
		Color(0, 0, 0, 0.7), 24, Vector4(40, 32, 40, 32)
	))
	UiStyle.add_frame(%ConfirmationPanel, UiStyle.GOLD_DIM, 0.15, 4.0, false)
	call_deferred("_ensure_setup")


func _ensure_setup() -> void:
	if run_state == null:
		return
	_refresh()


func _refresh() -> void:
	favorite_hero_id = ExecutionService.strongest_hero_id(run_state, _registry())
	_clear(%HeroCards)
	for hero in run_state.heroes:
		if hero.life_state not in [HeroState.ALIVE, HeroState.DEAD]:
			continue
		var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
		%HeroCards.add_child(_build_card(hero, definition))
	%ExecuteButton.disabled = selected_hero_id.is_empty()


func _build_card(hero: HeroState, definition: HeroDefinition) -> Control:
	var condemned := selected_hero_id == hero.unique_id
	var is_favorite := hero.unique_id == favorite_hero_id
	var accent := definition.placeholder_color
	var card := PanelContainer.new()
	card.name = "Card_%s" % hero.unique_id
	card.custom_minimum_size = Vector2(380, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := UiStyle.accent_panel(UiStyle.RED if condemned else accent, condemned, 20)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(_on_card_input.bind(hero.unique_id))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	var portrait := TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size = Vector2(0, 300)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _portrait_top(definition.portrait)
	if hero.life_state == HeroState.DEAD:
		portrait.modulate = Color(0.55, 0.55, 0.6)
	if condemned:
		portrait.modulate = Color(1.0, 0.62, 0.58)
	column.add_child(portrait)

	var name_label := Label.new()
	name_label.text = definition.display_name.to_upper()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", (UiStyle.RED if condemned else accent).lightened(0.35))
	column.add_child(name_label)
	var state_label := Label.new()
	state_label.text = "%s  /  LEVEL %d" % [String(hero.life_state).to_upper(), hero.level]
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.add_theme_color_override("font_color", accent.lightened(0.15))
	state_label.add_theme_font_size_override("font_size", 15)
	column.add_child(state_label)
	var role_label := Label.new()
	role_label.text = "TOO CLOSE TO THE CROWN" if is_favorite else "AN ALLY. FOR NOW."
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", 13)
	role_label.add_theme_color_override("font_color", UiStyle.RED.lightened(0.25) if is_favorite else Color(0.62, 0.58, 0.64))
	column.add_child(role_label)
	var build_label := Label.new()
	build_label.text = "ABILITIES / EQUIPMENT"
	build_label.add_theme_font_size_override("font_size", 13)
	column.add_child(build_label)
	var build_icons := HFlowContainer.new()
	build_icons.name = "BuildIcons"
	build_icons.add_theme_constant_override("h_separation", 6)
	build_icons.add_theme_constant_override("v_separation", 6)
	column.add_child(build_icons)
	for ability_id in hero.ability_ids:
		var ability := _registry().get_definition(ability_id, false) as AbilityDefinition
		if ability == null:
			continue
		var level := hero.ability_level(ability_id)
		var ability_icon := ContentIconButton.new()
		ability_icon.configure(ability, &"ability", "LV %d" % level, false, ContentButton.describe_ability_definition(ability, level))
		build_icons.add_child(ability_icon)
	for instance_id in hero.item_ids:
		var item := _registry().get_definition(run_state.inventory.get_definition_id(instance_id), false) as ItemDefinition
		if item == null:
			continue
		var item_icon := ContentIconButton.new()
		item_icon.configure(item, &"item")
		build_icons.add_child(item_icon)

	var details_panel := PanelContainer.new()
	details_panel.theme_type_variation = &"InsetPanel"
	details_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(details_panel)
	var details := Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 15)
	details.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	details.text = _hero_details(hero)
	details_panel.add_child(details)

	var frame := UiStyle.add_frame(card, UiStyle.RED if condemned else accent, 1.0 if condemned else 0.0, -10.0)
	frame.crest_width = 100.0
	frame.side_notches = condemned
	if not condemned:
		card.mouse_entered.connect(func() -> void: _set_card_glow(frame, true))
		card.mouse_exited.connect(func() -> void: _set_card_glow(frame, false))
	return card


func _on_card_input(event: InputEvent, hero_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_hero(hero_id)


func _set_card_glow(frame: OrnateFrame, enabled: bool) -> void:
	if not is_instance_valid(frame):
		return
	frame.pulse = enabled
	frame.create_tween().tween_property(frame, "glow", 0.6 if enabled else 0.0, 0.18)


func _portrait_top(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var source := texture.get_size()
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2(0, 0, source.x, minf(source.y, source.x * 0.8))
	return crop


func _select_hero(hero_id: String) -> void:
	if execution_in_progress:
		return
	var hero := _find_hero(hero_id)
	if hero == null:
		return
	if hero_id != favorite_hero_id:
		var conspirator := _hero_name(hero)
		var favorite := _find_hero(favorite_hero_id)
		_set_feedback("%s plotted against %s. This is not their sentence to bear." % [conspirator, _hero_name(favorite)], true)
		return
	selected_hero_id = hero_id
	_refresh()
	_set_feedback("%s grew too powerful. The other two have already made their choice." % _hero_name(hero), false)


func _on_execute_pressed() -> void:
	if execution_in_progress:
		return
	var hero := _find_hero(selected_hero_id)
	if hero == null:
		_set_feedback("Choose a Hero first.", true)
		return
	var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
	%CondemnedName.text = definition.display_name.to_upper()
	%ConfirmationBody.text = "%s will be permanently executed.\nTheir abilities and equipment cannot be recovered.\n\nTwo Heroes will enter Act II with ten soldiers." % definition.display_name
	ContentButton._hide_active_tooltip()
	%ConfirmationOverlay.show()
	%AcceptPriceButton.grab_focus()


func _on_execution_confirmed() -> void:
	if execution_in_progress:
		return
	var result := ExecutionService.execute(run_state, selected_hero_id, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	execution_in_progress = true
	get_viewport().gui_release_focus()
	%ExecuteButton.disabled = true
	%ConfirmationOverlay.hide()
	_set_feedback("The conspiracy is revealed...", false)
	await _play_execution_cutscene(_find_hero(selected_hero_id))
	execution_completed.emit(result.run_state)
	# A failed checkpoint save leaves this screen in place and must allow a retry.
	if not is_queued_for_deletion():
		execution_in_progress = false
		%CutsceneOverlay.hide()
		%ExecuteButton.disabled = false


func _play_execution_cutscene(favorite: HeroState) -> void:
	%CutsceneOverlay.visible = true
	%CutsceneCurtain.modulate.a = 0.0
	%CutsceneTitle.text = "THE PRICE OF VICTORY"
	%CutsceneSpeaker.text = ""
	%CutsceneCaption.text = "The battle is won. The crown is still unclaimed."
	_clear(%CutsceneStage)
	cutscene_actors.clear()
	var conspirators: Array[HeroState] = []
	for hero in run_state.heroes:
		if hero.unique_id != favorite.unique_id and hero.life_state in [HeroState.ALIVE, HeroState.DEAD]:
			conspirators.append(hero)
	_layout_cutscene_stage()
	var light := Polygon2D.new()
	light.polygon = PackedVector2Array([Vector2(540, 110), Vector2(740, 110), Vector2(940, 530), Vector2(340, 530)])
	light.color = Color(0.35, 0.22, 0.16, 0.13)
	%CutsceneStage.add_child(light)
	var left := _add_cutscene_actor(conspirators[0], Vector2(420, 445), false)
	var favorite_actor := _add_cutscene_actor(favorite, Vector2(640, 420), true)
	var right := _add_cutscene_actor(conspirators[1], Vector2(860, 445), false)
	_face_actor(left, false)
	_face_actor(favorite_actor, false)
	_face_actor(right, false)
	await _cutscene_pause(1.2)

	_face_actor(right, true)
	%CutsceneTitle.text = "A VICTORY SHARED. A CROWN FOR ONE."
	_cutscene_line(conspirators[0], "If we go on together, we already know who wins.")
	await _cutscene_pause(2.5)
	_face_actor(favorite_actor, true)
	_cutscene_line(conspirators[1], "Then we do not go on together.")
	await _cutscene_pause(2.1)

	%CutsceneSpeaker.text = ""
	%CutsceneCaption.text = ""
	%CutsceneTitle.text = "THE BETRAYAL"
	var approach := create_tween().set_parallel(true)
	approach.tween_property(left.get_parent(), "position:x", 485.0, _cutscene_seconds(0.45))
	approach.tween_property(right.get_parent(), "position:x", 795.0, _cutscene_seconds(0.45))
	_play_actor_animation(left, &"attack", 0.85)
	_play_actor_animation(right, &"attack", 0.85)
	await _cutscene_pause(0.45)
	_add_betrayal_strike(Vector2(485, 375), Vector2(672, 448))
	_add_betrayal_strike(Vector2(795, 375), Vector2(608, 448))
	var flash := favorite_actor.unit_sprite.material as ShaderMaterial
	flash.set_shader_parameter("flash_color", Color(1.0, 0.25, 0.18))
	flash.set_shader_parameter("flash_amount", 1.0)
	create_tween().tween_property(flash, "shader_parameter/flash_amount", 0.0, _cutscene_seconds(0.3))
	favorite_actor.state = Combatant.State.DEAD
	_play_actor_animation(favorite_actor, &"death")
	await favorite_actor.unit_sprite.animation_finished
	_play_actor_animation(left, &"move")
	left.unit_sprite.pause()
	_play_actor_animation(right, &"move")
	right.unit_sprite.pause()
	await _cutscene_pause(1.0)

	# The alliance ends where the next rivalry begins.
	_face_actor(left, false)
	_face_actor(right, true)
	var aftermath := create_tween().set_parallel(true)
	aftermath.tween_property(left.get_parent(), "position:y", 415.0, _cutscene_seconds(0.5))
	aftermath.tween_property(right.get_parent(), "position:y", 415.0, _cutscene_seconds(0.5))
	%CutsceneTitle.text = "TWO REMAIN"
	%CutsceneCaption.text = "Neither looks away first."
	await _cutscene_pause(1.8)
	var fade := create_tween()
	fade.tween_property(%CutsceneCurtain, "modulate:a", 1.0, _cutscene_seconds(0.7))
	await fade.finished
	%CutsceneTitle.text = "ACT II"
	%CutsceneCaption.text = "There can be only one."
	await _cutscene_pause(1.3)


func _cutscene_seconds(seconds: float) -> float:
	return maxf(seconds * cutscene_delay_scale, 0.001)


func _cutscene_pause(seconds: float) -> void:
	await get_tree().create_timer(_cutscene_seconds(seconds)).timeout


func _layout_cutscene_stage() -> void:
	var viewport_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	var stage_scale := minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	%CutsceneStage.scale = Vector2.ONE * stage_scale
	%CutsceneStage.position = (viewport_size - Vector2(1280, 720) * stage_scale) * 0.5


func _cutscene_line(speaker: HeroState, text: String) -> void:
	%CutsceneSpeaker.text = _hero_name(speaker).to_upper()
	var definition := _registry().get_definition(speaker.definition_id) as HeroDefinition
	%CutsceneSpeaker.modulate = definition.placeholder_color.lightened(0.3)
	%CutsceneCaption.text = "“%s”" % text


func _face_actor(actor: Combatant, face_left: bool) -> void:
	actor.unit_sprite.flip_h = face_left
	actor._update_unit_sprite_offset()


func _play_actor_animation(actor: Combatant, animation: StringName, duration := 0.0) -> void:
	var sprite := actor.unit_sprite
	var animation_scale := float(actor.unit_sprite_animation_scales.get(animation, 1.0))
	sprite.scale = Vector2.ONE * actor.unit_sprite_base_scale * float(actor.get_meta("stage_scale")) * animation_scale
	var authored_duration := float(sprite.sprite_frames.get_frame_count(animation)) / sprite.sprite_frames.get_animation_speed(animation)
	sprite.speed_scale = authored_duration / _cutscene_seconds(duration if duration > 0.0 else authored_duration)
	sprite.play(animation)
	actor._update_unit_sprite_offset()


func _add_betrayal_strike(from: Vector2, to: Vector2) -> void:
	var slash := Line2D.new()
	slash.points = PackedVector2Array([from, to])
	slash.width = 4.0
	slash.default_color = Color(1.0, 0.66, 0.52)
	slash.z_index = 4
	%CutsceneStage.add_child(slash)
	var tween := create_tween()
	tween.tween_property(slash, "modulate:a", 0.0, _cutscene_seconds(0.28))
	tween.tween_callback(slash.queue_free)


func _add_cutscene_actor(hero: HeroState, actor_position: Vector2, is_favorite: bool) -> Combatant:
	var holder := Node2D.new()
	holder.position = actor_position
	%CutsceneStage.add_child(holder)
	var actor: Combatant = COMBATANT_SCENE.instantiate()
	holder.add_child(actor)
	var snapshot := CombatSnapshotBuilder.build_hero(hero, run_state.inventory, _registry())
	snapshot.abilities.clear()
	snapshot.equipped_item_instance_ids.clear()
	snapshot.equipped_item_definition_ids.clear()
	actor.setup(snapshot, null, Rect2())
	actor.set_simulation_active(false)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.set_meta("stage_scale", 1.65 if is_favorite else 1.35)
	# Keep the combat sprite's authored frames and anchor callbacks, without HUD or AI.
	actor.unit_sprite.reparent(holder)
	actor.unit_sprite.show_behind_parent = false
	actor.hide()
	holder.z_index = 2 if is_favorite else 1
	_play_actor_animation(actor, &"move")
	actor.unit_sprite.pause()
	var name_label := Label.new()
	name_label.position = Vector2(-120, 105)
	name_label.size = Vector2(240, 40)
	name_label.text = _hero_name(hero).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18 if is_favorite else 15)
	name_label.add_theme_color_override("font_color", UiStyle.RED.lightened(0.35) if is_favorite else Color(0.75, 0.72, 0.8))
	holder.add_child(name_label)
	cutscene_actors[hero.unique_id] = actor
	return actor


func _hero_details(hero: HeroState) -> String:
	var battle: Dictionary = run_state.pending_execution_contributions.get(hero.unique_id, {})
	var contribution: Dictionary = battle.get("contribution", {})
	return "MAIN SCORE  %.0f\nXP  %d\n\nBOSS CONTRIBUTION\nDamage %.0f  Healing %.0f  Tanking %.0f\nContribution XP %d%s" % [
		MarketGenerator.hero_main_score(run_state, hero, _registry()),
		hero.xp,
		float(contribution.get("damage_dealt", 0.0)),
		float(contribution.get("effective_healing", 0.0)),
		float(contribution.get("damage_tanked", 0.0)),
		int(contribution.get("total_xp", 0)),
		"\nDid not participate in the Boss battle." if not bool(battle.get("participated", false)) else "",
	]


func _find_hero(hero_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == hero_id:
			return hero
	return null


func _hero_name(hero: HeroState) -> String:
	if hero == null:
		return "Unknown Hero"
	var definition := _registry().get_definition(hero.definition_id, false) as HeroDefinition
	return definition.display_name if definition != null else String(hero.definition_id)


func _set_feedback(message: String, is_error: bool) -> void:
	%FeedbackLabel.text = message
	%FeedbackLabel.modulate = Color(1.0, 0.42, 0.34) if is_error else Color(0.9, 0.67, 0.32)


func _on_menu_pressed() -> void:
	if not execution_in_progress:
		menu_requested.emit()


func _clear(container: Node) -> void:
	for child in container.get_children():
		# A card may still be emitting gui_input when selection rebuilds the list.
		container.remove_child(child)
		child.queue_free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
