class_name HeroSelection
extends Control



signal selection_confirmed(hero_ids: Array[StringName])
signal back_requested

const REQUIRED_HEROES := 3
const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const SLOT_SIZE := Vector2(190.0, 72.0)
const SLOT_BADGE_SIZE := Vector2(52.0, 64.0)
const SLOT_EMPTY_GEM_SIZE := 26.0

@onready var previous_card: HeroSelectionCard = %PreviousCard
@onready var center_card: HeroSelectionCard = %CenterCard
@onready var next_card: HeroSelectionCard = %NextCard

var heroes: Array[HeroDefinition] = []
var selected_hero_ids: Array[StringName] = []
var current_index := 0
## One entry per roster position: {button, visual, plaque, badge, gem, hero_id}.
var roster_slots: Array[Dictionary] = []


func _ready() -> void:
	_load_heroes()
	_build_roster_slots()
	previous_card.card_requested.connect(_on_card_requested.bind(previous_card))
	center_card.card_requested.connect(_on_card_requested.bind(center_card))
	next_card.card_requested.connect(_on_card_requested.bind(next_card))
	resized.connect(_apply_design_scale)
	_apply_design_scale()
	_refresh()
	center_card.grab_selection_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_on_previous_pressed()
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_on_next_pressed()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _load_heroes() -> void:
	heroes.clear()
	for definition in _registry().definitions.values():
		if definition is HeroDefinition and definition.available_in_new_game:
			heroes.append(definition)
	heroes.sort_custom(func(a: HeroDefinition, b: HeroDefinition) -> bool:
		if a.selection_order == b.selection_order:
			return String(a.id) < String(b.id)
		return a.selection_order < b.selection_order
	)


func _refresh() -> void:
	var has_heroes := not heroes.is_empty()
	%PreviousButton.disabled = not has_heroes
	%NextButton.disabled = not has_heroes
	%StartButton.disabled = selected_hero_ids.size() != REQUIRED_HEROES
	_refresh_roster_slots()
	if not has_heroes:
		previous_card.visible = false
		center_card.visible = false
		next_card.visible = false
		%CounterLabel.text = "NO SELECTABLE HEROES"
		set_feedback("Add selectable HeroDefinition resources.")
		return
	current_index = posmod(current_index, heroes.size())
	var previous := heroes[posmod(current_index - 1, heroes.size())]
	var current := heroes[current_index]
	var next := heroes[posmod(current_index + 1, heroes.size())]
	previous_card.setup(previous, selected_hero_ids.find(previous.id), false)
	center_card.setup(current, selected_hero_ids.find(current.id), true)
	next_card.setup(next, selected_hero_ids.find(next.id), false)
	%CounterLabel.text = "HERO %d / %d" % [current_index + 1, heroes.size()]
	var selection_full := selected_hero_ids.size() >= REQUIRED_HEROES
	previous_card.set_select_disabled(false)
	center_card.set_select_disabled(selection_full and not selected_hero_ids.has(current.id))
	next_card.set_select_disabled(false)
	var current_blocked := selection_full and not selected_hero_ids.has(current.id)
	set_feedback("Choose a selected Hero to remove first." if current_blocked else "")


func _on_previous_pressed() -> void:
	if heroes.is_empty():
		return
	current_index = posmod(current_index - 1, heroes.size())
	_refresh()


func _on_next_pressed() -> void:
	if heroes.is_empty():
		return
	current_index = posmod(current_index + 1, heroes.size())
	_refresh()


func _on_select_pressed() -> void:
	if heroes.is_empty():
		return
	_toggle_hero(heroes[current_index].id)


func _on_card_requested(card: HeroSelectionCard) -> void:
	if card == previous_card:
		_on_previous_pressed()
	elif card == next_card:
		_on_next_pressed()
	elif card == center_card and card.hero != null:
		_toggle_hero(card.hero.id)


func _toggle_hero(hero_id: StringName) -> void:
	var selected_index := selected_hero_ids.find(hero_id)
	if selected_index >= 0:
		selected_hero_ids.remove_at(selected_index)
	elif selected_hero_ids.size() < REQUIRED_HEROES:
		selected_hero_ids.append(hero_id)
	_refresh()


func _on_start_pressed() -> void:
	if selected_hero_ids.size() == REQUIRED_HEROES:
		selection_confirmed.emit(selected_hero_ids.duplicate())


func _on_back_pressed() -> void:
	back_requested.emit()


func set_feedback(message: String) -> void:
	%Feedback.text = message
	%Feedback.visible = not message.is_empty()


func _build_roster_slots() -> void:
	var container: HBoxContainer = %SelectedSlots
	for child in container.get_children():
		child.queue_free()
	roster_slots.clear()
	var empty_hitbox := StyleBoxEmpty.new()
	for index in REQUIRED_HEROES:
		var button := Button.new()
		button.name = "RosterSlot%d" % (index + 1)
		button.custom_minimum_size = SLOT_SIZE
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(style_name, empty_hitbox)
		container.add_child(button)

		var visual := Control.new()
		visual.name = "Visual"
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visual.pivot_offset = SLOT_SIZE * 0.5
		button.add_child(visual)

		var plaque := NinePatchRect.new()
		plaque.name = "Plaque"
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plaque.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plaque.texture = OrnateFrame.GOTHIC_ATLAS
		plaque.region_rect = UiStyle.SLOT_REGION
		plaque.patch_margin_left = 16
		plaque.patch_margin_right = 16
		plaque.patch_margin_top = 16
		plaque.patch_margin_bottom = 16
		visual.add_child(plaque)

		var gem := TextureRect.new()
		gem.name = "EmptyGem"
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gem.texture = OrnateFrame.gem_texture(&"bronze")
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.size = Vector2.ONE * SLOT_EMPTY_GEM_SIZE
		gem.position = (SLOT_SIZE - gem.size) * 0.5
		visual.add_child(gem)

		var badge := TextureRect.new()
		badge.name = "Badge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.size = SLOT_BADGE_SIZE
		badge.position = (SLOT_SIZE - SLOT_BADGE_SIZE) * 0.5
		visual.add_child(badge)

		var motion := ButtonMotion.new()
		motion.hover_scale = 1.06
		button.add_child(motion)
		button.pressed.connect(_on_roster_slot_pressed.bind(index))
		roster_slots.append({
			"button": button,
			"visual": visual,
			"plaque": plaque,
			"badge": badge,
			"gem": gem,
			"hero_id": &"",
		})


func _refresh_roster_slots() -> void:
	for index in roster_slots.size():
		var slot := roster_slots[index]
		var hero_id: StringName = selected_hero_ids[index] if index < selected_hero_ids.size() else &""
		var definition: HeroDefinition = null
		if hero_id != &"":
			definition = _registry().get_definition(hero_id, false) as HeroDefinition
		var filled := definition != null
		var button: Button = slot["button"]
		var plaque: NinePatchRect = slot["plaque"]
		var badge: TextureRect = slot["badge"]
		var gem: TextureRect = slot["gem"]
		var identity_index := HeroSelectionCard.identity_index_of(definition)
		plaque.modulate = Color.WHITE.lerp(definition.placeholder_color.lightened(0.35), 0.5) if filled else Color(0.75, 0.72, 0.68, 0.85)
		badge.visible = filled
		badge.texture = HeroSelectionCard.atlas_texture(HeroSelectionCard.BADGE_REGIONS[identity_index])
		gem.visible = not filled
		button.disabled = not filled
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if filled else Control.CURSOR_ARROW
		button.tooltip_text = definition.display_name if filled else ""
		var previous_id: StringName = slot["hero_id"]
		slot["hero_id"] = hero_id
		if filled and previous_id != hero_id:
			_pop_slot(slot["visual"])


func _pop_slot(visual: Control) -> void:
	visual.scale = Vector2.ONE * 1.3
	visual.modulate = Color(1.6, 1.6, 1.6, 1.0)
	var tween := visual.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", Vector2.ONE, 0.35)
	tween.tween_property(visual, "modulate", Color.WHITE, 0.45)


func _on_roster_slot_pressed(index: int) -> void:
	if index >= selected_hero_ids.size():
		return
	for hero_index in heroes.size():
		if heroes[hero_index].id == selected_hero_ids[index]:
			current_index = hero_index
			_refresh()
			return


func _apply_design_scale() -> void:
	if not is_node_ready():
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	%DesignRoot.scale = Vector2.ONE * factor
	%DesignRoot.position = (size - DESIGN_SIZE * factor) * 0.5


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
