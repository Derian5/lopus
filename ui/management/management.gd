extends Control


signal combat_requested
signal menu_requested
signal run_state_changed(action: StringName)
signal run_event_choice_requested(choice_id: StringName)
signal hero_ability_reward_requested(offer_id: String)

const ICON_SIZE := Vector2(92, 92)
const HERO_SLOT_SIZE := Vector2(56, 56)
const ATLAS := preload("res://graphics/ui/ui_atlas_v2.png")
## Atlas regions of the inspector's stat icons, reused by the Market cards.
const STAT_ATLAS_REGIONS := {
	"max_hp": Rect2(1038, 203, 46, 43),
	"damage": Rect2(1102, 149, 47, 47),
	"armor": Rect2(1168, 149, 47, 47),
	"attack_range": Rect2(1233, 149, 47, 47),
}
## Small ability icons (graphics/ui/ability_icons) for the other stats.
const STAT_ICON_NAMES := {
	"attack_speed": "buff", "movement_speed": "buff", "crit_chance": "damage", "crit_multiplier": "damage",
	"lifesteal": "heal", "dodge": "shield", "hp_regen": "heal", "cooldown_reduction": "cooldown",
	"damage_taken": "debuff", "armor_penetration": "damage",
}
const STAT_SHORT := {
	"max_hp": "HP", "damage": "DMG", "attack_speed": "ATK SPD", "movement_speed": "MOVE", "attack_range": "RANGE",
	"armor": "ARMOR", "crit_chance": "CRIT", "crit_multiplier": "CRIT DMG", "lifesteal": "LIFESTEAL", "dodge": "DODGE",
	"hp_regen": "REGEN", "cooldown_reduction": "CDR", "damage_taken": "DMG TAKEN", "armor_penetration": "ARMOR PEN",
}
const OFFER_ACCENTS := {
	&"job_unlock": Color(0.42, 0.8, 0.48),
	&"job_capacity": Color(0.46, 0.68, 0.98),
	&"job_ability": Color(0.72, 0.52, 1.0),
}
## Item accents by ItemDefinition.ItemCategory: damage, tank, support, command, unique.
const ITEM_ACCENTS := [Color(0.95, 0.46, 0.32), Color(0.46, 0.68, 0.98), Color(0.45, 0.84, 0.52), Color(0.96, 0.76, 0.36), Color(0.8, 0.52, 1.0)]
const CARD_TITLE := Color(0.96, 0.88, 0.7)
const CARD_BODY := Color(0.78, 0.71, 0.6)
const CARD_MUTED := Color(0.56, 0.5, 0.42)

var run_state: RunState
var selected_kind := ""
var selected_index := -1
var selected_job_id: StringName
var selected_ability_slot := 0
var selected_equipment_slot := 0
var roster_job_ids: Array[StringName] = []
var field_view := false


func _ready() -> void:
	%SelectedPortrait.resized.connect(_update_portrait_shader_size)
	_update_portrait_shader_size()
	%TargetClosestButton.pressed.connect(_set_targeting_behavior.bind(&"closest"))
	%TargetFarthestButton.pressed.connect(_set_targeting_behavior.bind(&"farthest"))
	%AvoidDamageButton.pressed.connect(_set_damage_avoidance.bind(true))
	%AcceptDamageButton.pressed.connect(_set_damage_avoidance.bind(false))
	%ResurrectionButton.pressed.connect(_resurrect_selected_hero)
	%RunEventPopup.choice_selected.connect(_on_run_event_choice_selected)
	%HeroAbilityRewardPopup.offer_selected.connect(_on_hero_ability_reward_selected)
	var view_group := ButtonGroup.new()
	%ArmyViewTab.button_group = view_group
	%FieldViewTab.button_group = view_group
	%ArmyViewTab.pressed.connect(set_field_view.bind(false))
	%FieldViewTab.pressed.connect(set_field_view.bind(true))
	%ResetFormationButton.pressed.connect(_on_reset_formation_pressed)
	%BattlefieldPreview.formation_changed.connect(_on_formation_changed)
	%BattlefieldPreview.unit_selected.connect(_on_preview_unit_selected)
	call_deferred("_ensure_setup")


func setup(new_run_state: RunState) -> void:
	run_state = new_run_state
	if is_node_ready():
		_refresh_all()
		_show_pending_popups()


func _ensure_setup() -> void:
	if run_state == null:
		run_state = DemoRunFactory.create_starting_run()
	_refresh_all()
	if selected_index < 0:
		for index in run_state.heroes.size():
			if run_state.heroes[index].life_state != HeroState.EXECUTED:
				_select_unit("hero", index)
				break
		if selected_index < 0 and not run_state.soldiers.is_empty():
			_select_unit("soldier", 0)
	%FightButton.grab_focus()
	_show_pending_popups()


func _on_run_event_choice_selected(choice_id: StringName) -> void:
	run_event_choice_requested.emit(choice_id)


func _on_hero_ability_reward_selected(offer_id: String) -> void:
	hero_ability_reward_requested.emit(offer_id)


func _show_pending_popups() -> void:
	%HeroAbilityRewardPopup.show_pending(run_state)
	if run_state.pending_hero_ability_reward.is_empty():
		%RunEventPopup.show_pending(run_state)
	else:
		%RunEventPopup.visible = false


## Switches between the build view (inspector + market) and the battlefield preview.
func set_field_view(enabled: bool) -> void:
	field_view = enabled
	%ArmyViewTab.set_pressed_no_signal(not enabled)
	%FieldViewTab.set_pressed_no_signal(enabled)
	$Page/Layout/ColumnsScroll/Columns/InspectorCard.visible = not enabled
	$Page/Layout/ColumnsScroll/Columns/RightCard.visible = not enabled
	%BattlefieldCard.visible = enabled
	if enabled:
		%BattlefieldPreview.setup(run_state)
		%BattlefieldPreview.highlight_unit(_selected_unit_id())


func _on_formation_changed() -> void:
	_set_feedback("", false)
	run_state_changed.emit(&"formation_changed")


func _on_reset_formation_pressed() -> void:
	%BattlefieldPreview.reset_formation()
	_set_feedback("", false)


func _on_preview_unit_selected(kind: String, index: int) -> void:
	if index < 0:
		return
	_select_unit(kind, index)
	set_field_view(false)


func _selected_unit_id() -> String:
	if selected_kind == "hero" and selected_index >= 0 and selected_index < run_state.heroes.size():
		return run_state.heroes[selected_index].unique_id
	if selected_kind == "soldier" and selected_index >= 0 and selected_index < run_state.soldiers.size():
		return run_state.soldiers[selected_index].unique_id
	return ""


func _refresh_all() -> void:
	%GoldLabel.text = "GOLD  %d" % run_state.gold
	%PhaseLabel.text = "PREPARATION"
	if _auto_equip_spare_items():
		run_state_changed.emit(&"equipment_changed")
	_refresh_roster_job_ids()
	_refresh_roster()
	_refresh_job_build_panel()
	_refresh_market()
	_refresh_encounter()
	_refresh_selected()
	if field_view:
		%BattlefieldPreview.setup(run_state)
		%BattlefieldPreview.highlight_unit(_selected_unit_id())


func _refresh_roster() -> void:
	_clear(%Roster)
	var hero_heading := Label.new()
	hero_heading.text = "HEROES"
	hero_heading.theme_type_variation = &"EyebrowLabel"
	hero_heading.add_theme_color_override("font_color", Color("e2b468"))
	%Roster.add_child(hero_heading)
	for index in run_state.heroes.size():
		var hero := run_state.heroes[index]
		if hero.life_state == HeroState.EXECUTED:
			continue
		_add_hero_card(index)
	_add_spare_items()
	for job_id in roster_job_ids:
		var job := _registry().get_definition(job_id, false) as JobDefinition
		if job == null:
			continue
		var heading := ManagementDropSlot.new()
		var assigned := _assigned_count(job_id)
		heading.text = "%s   %s" % [job.display_name.to_upper(), "UNLIMITED" if job_id == &"job.militia" else "%d / %d" % [assigned, _capacity(job_id)]]
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.theme_type_variation = &"LedgerButton"
		heading.custom_minimum_size.y = 42.0
		heading.content_id = job.id
		heading.icon = _market_icon_texture(job, &"job_capacity")
		heading.expand_icon = true
		heading.add_theme_constant_override("icon_max_width", 28)
		heading.accepted_sources = [&"soldier"]
		heading.target_payload = {"target": &"job", "job_id": job_id}
		heading.payload_dropped.connect(_on_management_drop)
		heading.pressed.connect(_select_job.bind(job_id))
		%Roster.add_child(heading)
		for index in run_state.soldiers.size():
			var soldier := run_state.soldiers[index]
			if soldier.current_job_id == job_id:
				var soldier_label := soldier.display_name(job.display_name)
				_add_roster_row(soldier_label, job.id, "soldier", index)


## Hero card in the roster: identity, level and the six item slots. Items move
## between Heroes by dragging them onto another Hero's slot or card.
func _add_hero_card(index: int) -> void:
	var hero := run_state.heroes[index]
	var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
	var selected := selected_kind == "hero" and selected_index == index
	var dead := hero.life_state == HeroState.DEAD
	var card := PanelContainer.new()
	card.name = "HeroCard%d" % index
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _hero_card_style(definition.placeholder_color, selected))
	card.gui_input.connect(_on_hero_card_gui_input.bind(index))
	card.set_drag_forwarding(Callable(), _hero_card_can_drop.bind(index), _hero_card_drop.bind(index))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(top)
	var badge := TextureRect.new()
	badge.custom_minimum_size = Vector2(30, 36)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.texture = HeroSelectionCard.atlas_texture(HeroSelectionCard.BADGE_REGIONS[HeroSelectionCard.identity_index_of(definition)])
	badge.modulate = Color(0.55, 0.55, 0.55) if dead else Color.WHITE
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(names)
	var title := Label.new()
	title.name = "HeroName"
	title.text = definition.display_name.to_upper()
	title.theme_type_variation = &"EyebrowLabel"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", CARD_MUTED if dead else (Color(1.0, 0.86, 0.56) if selected else CARD_TITLE))
	names.add_child(title)
	var sub := Label.new()
	sub.text = "LEVEL %d   ·   %d / %d ITEMS" % [hero.level, hero.item_ids.size(), HeroState.MAX_ITEM_SLOTS]
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", CARD_MUTED)
	names.add_child(sub)
	if dead:
		var fallen := Label.new()
		fallen.text = "FALLEN"
		fallen.add_theme_font_size_override("font_size", 14)
		fallen.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38))
		fallen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(fallen)
	var slots := HBoxContainer.new()
	slots.name = "ItemSlots"
	slots.add_theme_constant_override("separation", 6)
	slots.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(slots)
	for slot_index in HeroState.MAX_ITEM_SLOTS:
		var occupied := slot_index < hero.item_ids.size()
		var item := _item_definition(hero.item_ids[slot_index]) if occupied else null
		var slot := ManagementDropSlot.new()
		slot.configure(item, &"item", "", false)
		_apply_atlas_slot(slot, selected and occupied and selected_equipment_slot == slot_index)
		slot.custom_minimum_size = HERO_SLOT_SIZE
		if occupied:
			slot.drag_payload = {
				"source": &"equipped_item",
				"owner_kind": &"hero",
				"owner_index": index,
				"slot_index": slot_index,
				"instance_id": hero.item_ids[slot_index],
			}
		slot.accepted_sources = [&"equipped_item", &"inventory_item", &"market"]
		slot.target_payload = {"target": &"equipment", "owner_kind": &"hero", "owner_index": index, "slot_index": slot_index if occupied else -1}
		slot.payload_dropped.connect(_on_management_drop)
		slot.pressed.connect(_on_hero_slot_pressed.bind(index, slot_index))
		slots.add_child(slot)
	%Roster.add_child(card)


func _hero_card_style(accent: Color, selected: bool) -> StyleBoxFlat:
	var border := Color(0.98, 0.78, 0.42, 0.95) if selected else Color(accent.r, accent.g, accent.b, 0.45)
	var bg := Color(0.12, 0.08, 0.05, 0.96) if selected else Color(0.065, 0.047, 0.035, 0.92)
	var style := UiStyle.chamfer_box(bg, border, 2, 6, Color(0.98, 0.7, 0.3, 0.2) if selected else Color(0, 0, 0, 0), 8 if selected else 0, Vector4(12, 9, 12, 10))
	style.border_width_left = 5
	return style


func _on_hero_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		call_deferred("_select_hero_from_card", index)


func _select_hero_from_card(index: int) -> void:
	_select_unit("hero", index)


func _on_hero_slot_pressed(index: int, slot_index: int) -> void:
	if selected_kind != "hero" or selected_index != index:
		_select_unit("hero", index)
	selected_equipment_slot = slot_index
	call_deferred("_refresh_roster")
	call_deferred("_refresh_selected")


func _hero_card_can_drop(_position: Vector2, data: Variant, _index: int) -> bool:
	if not data is Dictionary:
		return false
	var source := StringName(data.get("source", ""))
	if source == &"market":
		return StringName(data.get("offer_type", "")) == &"hero_item"
	return source in [&"equipped_item", &"inventory_item"]


func _hero_card_drop(_position: Vector2, data: Variant, index: int) -> void:
	_on_management_drop(Dictionary(data).duplicate(true), {"target": &"equipment", "owner_kind": &"hero", "owner_index": index, "slot_index": -1})


## Gear that no Hero has room for (event rewards, old saves) waits here until it is
## dragged onto a Hero or sold on the Market.
func _add_spare_items() -> void:
	var spare := EquipmentService.get_unequipped_items(run_state)
	if spare.is_empty():
		return
	var heading := Label.new()
	heading.name = "SpareHeading"
	heading.text = "SPARE GEAR  -  DRAG TO A HERO OR SELL"
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color(1.0, 0.62, 0.42))
	%Roster.add_child(heading)
	var strip := HFlowContainer.new()
	strip.name = "SpareItems"
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 6)
	for item in spare:
		var definition := _registry().get_definition(StringName(item.definition_id), false) as ItemDefinition
		var slot := ManagementDropSlot.new()
		slot.configure(definition, &"item", "", false)
		_apply_atlas_slot(slot, false)
		slot.custom_minimum_size = HERO_SLOT_SIZE
		slot.accepted_sources = [&"none"]
		slot.drag_payload = {"source": &"inventory_item", "instance_id": StringName(item.instance_id)}
		strip.add_child(slot)
	%Roster.add_child(strip)


## Puts every unequipped item on a Hero who can use it and has a free slot (the
## selected Hero first). Returns true when something moved.
func _auto_equip_spare_items() -> bool:
	if run_state == null or run_state.run_phase != &"management":
		return false
	var changed := false
	for item in EquipmentService.get_unequipped_items(run_state):
		var target := _free_item_slot_hero(StringName(item.definition_id))
		if target < 0:
			continue
		var result := EquipmentService.equip_or_swap(run_state, &"hero", target, run_state.heroes[target].item_ids.size(), StringName(item.instance_id), _registry())
		changed = changed or result.ok
	return changed


## Index of the Hero who should receive a new item: the selected Hero if it fits,
## otherwise the first compatible Hero with a free slot; -1 when nobody has room.
func _free_item_slot_hero(item_id: StringName) -> int:
	var item := _registry().get_definition(item_id, false) as ItemDefinition
	if item == null:
		return -1
	var order: Array[int] = []
	if selected_kind == "hero" and selected_index >= 0 and selected_index < run_state.heroes.size():
		order.append(selected_index)
	for index in run_state.heroes.size():
		if not order.has(index):
			order.append(index)
	for index in order:
		var hero := run_state.heroes[index]
		if hero.life_state == HeroState.EXECUTED or hero.item_ids.size() >= HeroState.MAX_ITEM_SLOTS:
			continue
		if item.is_compatible_with_hero(_registry().get_definition(hero.definition_id, false) as HeroDefinition):
			return index
	return -1


func _add_roster_row(
	label: String,
	content_id: StringName,
	kind: String,
	index: int
) -> void:
	var row := HBoxContainer.new()
	var hero_definition := _registry().get_definition(content_id, false) as HeroDefinition if kind == "hero" else null
	if hero_definition != null:
		var badge := TextureRect.new()
		badge.custom_minimum_size = Vector2(34, 40)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.texture = HeroSelectionCard.atlas_texture(HeroSelectionCard.BADGE_REGIONS[HeroSelectionCard.identity_index_of(hero_definition)])
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(badge)
	else:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = _market_icon_texture(_registry().get_definition(content_id, false), &"job_capacity")
		row.add_child(icon)
	var button: ContentButton
	if kind == "soldier":
		var draggable := ManagementDragButton.new()
		draggable.drag_payload = {"source": &"soldier", "soldier_index": index}
		button = draggable
	else:
		button = ContentButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.theme_type_variation = &"RowButton"
	button.custom_minimum_size.y = 36.0
	button.content_id = content_id
	button.pressed.connect(_select_unit.bind(kind, index))
	row.add_child(button)
	if kind == "soldier" and index >= 0 and index < run_state.soldiers.size():
		var insignia := VeterancyInsignia.new()
		insignia.custom_minimum_size = Vector2(30, 34)
		insignia.level = run_state.soldiers[index].veterancy_level
		insignia.tooltip_text = _veterancy_text(run_state.soldiers[index])
		row.add_child(insignia)
	%Roster.add_child(row)


func _select_unit(kind: String, index: int) -> void:
	if kind == "hero" and (index < 0 or index >= run_state.heroes.size() or run_state.heroes[index].life_state == HeroState.EXECUTED):
		_set_feedback("Executed Heroes are sealed in the run history.", true)
		return
	selected_kind = kind
	selected_index = index
	selected_job_id = &""
	selected_ability_slot = 0
	selected_equipment_slot = 0
	_refresh_selected()
	call_deferred("_refresh_roster")
	if field_view:
		%BattlefieldPreview.highlight_unit(_selected_unit_id())


func _select_job(job_id: StringName) -> void:
	selected_kind = "job"
	selected_index = -1
	selected_job_id = job_id
	_refresh_job_build_panel()
	_refresh_selected()


func _refresh_selected() -> void:
	%ResurrectionButton.visible = false
	if run_state == null or (selected_index < 0 and selected_kind != "job"):
		return
	var registry := _registry()
	if selected_kind == "hero" and selected_index < run_state.heroes.size():
		var hero := run_state.heroes[selected_index]
		if hero.life_state == HeroState.EXECUTED:
			selected_index = -1
			return
		var definition := registry.get_definition(hero.definition_id) as HeroDefinition
		var snapshot := CombatSnapshotBuilder.build_hero(hero, run_state.inventory, registry)
		snapshot = _army_snapshot(hero.unique_id, snapshot)
		_set_selected_portrait(definition.portrait, definition.placeholder_color, definition.display_name.left(1), definition, hero.life_state == HeroState.DEAD)
		%SelectedTitle.text = definition.display_name.to_upper()
		%DetailsLabel.text = "HERO  -  LEVEL %d  -  XP %d  -  STATE: %s" % [hero.level, hero.xp, String(hero.life_state).to_upper()]
		_set_stat_values(snapshot.stats)
		_refresh_selected_resurrection(hero)
		%JobBuildControls.visible = false
		%BehaviorControls.visible = true
		%AbilityTitle.visible = true
		%AbilityRows.visible = true
		%EquipmentColumn.visible = true
		%EquipmentCount.visible = true
		%EquipmentRows.visible = true
		_refresh_behavior_controls(hero, snapshot.attack_type)
		_refresh_hero_abilities(hero)
		_refresh_equipment(hero.item_ids, HeroState.MAX_ITEM_SLOTS)
	elif selected_kind == "soldier" and selected_index < run_state.soldiers.size():
		var soldier := run_state.soldiers[selected_index]
		var job := registry.get_definition(soldier.current_job_id) as JobDefinition
		var snapshot := CombatSnapshotBuilder.build_soldier(soldier, _job_build(soldier.current_job_id), registry)
		snapshot = _army_snapshot(soldier.unique_id, snapshot)
		_set_selected_portrait(null, job.placeholder_color, job.display_name.left(1))
		%SelectedTitle.text = soldier.display_name(job.display_name).to_upper()
		%DetailsLabel.text = "SOLDIER  -  %s  -  %s" % [job.display_name.to_upper(), _veterancy_text(soldier).to_upper()]
		_set_portrait_veterancy(soldier.veterancy_level)
		_set_stat_values(snapshot.stats)
		%ResurrectionButton.visible = false
		%JobBuildControls.visible = false
		%BehaviorControls.visible = true
		%AbilityTitle.visible = true
		%AbilityRows.visible = true
		%EquipmentColumn.visible = false
		%EquipmentCount.visible = false
		%EquipmentRows.visible = false
		_refresh_behavior_controls(soldier, snapshot.attack_type)
		_refresh_soldier_abilities(job, snapshot.abilities)
		_clear(%EquipmentRows)
	elif selected_kind == "job" and not String(selected_job_id).is_empty():
		var job := registry.get_definition(selected_job_id, false) as JobDefinition
		if job == null:
			return
		_set_selected_portrait(null, job.placeholder_color, job.display_name.left(1))
		%SelectedTitle.text = "%s COMPANY" % job.display_name.to_upper()
		%DetailsLabel.text = "SHARED JOB BUILD  -  %d / %s" % [
			_assigned_count(job.id), "unlimited" if job.id == &"job.militia" else str(_capacity(job.id)),
		]
		%StatsGrid.visible = false
		if %StatsGrid.get_parent().has_node("SecondaryStats"):
			%StatsGrid.get_parent().get_node("SecondaryStats").visible = false
		%ResurrectionButton.visible = false
		%JobBuildControls.visible = true
		%BehaviorControls.visible = false
		%AbilityTitle.visible = true
		%AbilityRows.visible = true
		%EquipmentColumn.visible = false
		%EquipmentCount.visible = false
		%EquipmentRows.visible = false
		_clear(%EquipmentRows)
		_refresh_job_ability_slots(job.id)
	_refresh_preview()


## Large rank insignia in the portrait corner for the selected Soldier (-1 hides it).
func _set_portrait_veterancy(level: int) -> void:
	var layer := %PortraitFallback.get_parent() as Control
	var insignia := layer.get_node_or_null("VeterancyBadge") as VeterancyInsignia
	if insignia == null:
		insignia = VeterancyInsignia.new()
		insignia.name = "VeterancyBadge"
		insignia.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(insignia)
		insignia.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		insignia.offset_left = -52.0
		insignia.offset_top = 8.0
		insignia.offset_right = -8.0
		insignia.offset_bottom = 56.0
	insignia.level = level
	insignia.visible = level >= 0


func _set_selected_portrait(texture: Texture2D, color: Color, glyph: String, hero: HeroDefinition = null, is_dead := false) -> void:
	_set_portrait_veterancy(-1)
	%SelectedPortrait.texture = _management_portrait_crop(texture)
	%SelectedPortrait.visible = texture != null
	%PortraitFallback.visible = texture == null
	%PortraitFallback.text = glyph.to_upper()
	%PortraitFallback.add_theme_color_override("font_color", color.lightened(0.25))
	%SelectedHeroCrest.visible = hero != null
	if hero != null:
		%SelectedHeroCrest.texture = HeroSelectionCard.atlas_texture(HeroSelectionCard.BADGE_REGIONS[HeroSelectionCard.identity_index_of(hero)])
		%SelectedHeroCrest.modulate = Color(0.55, 0.55, 0.55) if is_dead else Color.WHITE
	var material := %SelectedPortrait.material as ShaderMaterial
	material.set_shader_parameter("dead_amount", 1.0 if is_dead else 0.0)
	_update_portrait_shader_size()


func _management_portrait_crop(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return texture
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2(source.x * 0.18, 0.0, source.x * 0.64, minf(source.y, source.x * 0.72))
	crop.filter_clip = true
	return crop


func _update_portrait_shader_size() -> void:
	var portrait := %SelectedPortrait as TextureRect
	var material := portrait.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("portrait_size", portrait.size.max(Vector2.ONE))


func _set_stat_values(stats: CombatStats) -> void:
	%StatsGrid.visible = true
	%HpStatValue.text = "%.0f" % stats.max_hp
	%DamageStatValue.text = "%.0f" % stats.damage
	%ArmorStatValue.text = "%.0f" % stats.armor
	%RangeStatValue.text = "%.0f" % stats.attack_range
	_set_control_tooltip(%StatsGrid.get_node("HpStat"), StatBreakdownFormatter.from_stats(stats, &"max_hp"))
	_set_control_tooltip(%StatsGrid.get_node("DamageStat"), StatBreakdownFormatter.from_stats(stats, &"damage"))
	_set_control_tooltip(%StatsGrid.get_node("ArmorStat"), StatBreakdownFormatter.from_stats(stats, &"armor"))
	_set_control_tooltip(%StatsGrid.get_node("RangeStat"), StatBreakdownFormatter.from_stats(stats, &"attack_range"))
	var extra_label := %StatsGrid.get_parent().get_node_or_null("SecondaryStats") as Label
	if extra_label == null:
		extra_label = Label.new()
		extra_label.name = "SecondaryStats"
		extra_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		extra_label.add_theme_font_size_override("font_size", 14)
		extra_label.add_theme_color_override("font_color", Color(0.85, 0.76, 0.6))
		%StatsGrid.get_parent().add_child(extra_label)
		%StatsGrid.get_parent().move_child(extra_label, %StatsGrid.get_index() + 1)
	extra_label.text = SelectedUnitPanel.secondary_stats_text(func(stat: StringName) -> float: return float(stats.get(stat)))
	extra_label.visible = not extra_label.text.is_empty()


func _army_snapshot(runtime_id: String, fallback: CombatUnitSnapshot) -> CombatUnitSnapshot:
	for snapshot in CombatSnapshotBuilder.build_player_army(run_state, _registry()):
		if snapshot.runtime_id == runtime_id:
			return snapshot
	return fallback


func _set_control_tooltip(control: Control, text: String) -> void:
	var binding: StatTooltipBinding = control.get_meta("stat_tooltip_binding") as StatTooltipBinding if control.has_meta("stat_tooltip_binding") else null
	if binding == null:
		binding = StatTooltipBinding.new()
		binding.bind(control)
	binding.set_text(text)
	control.tooltip_text = ""
	for child in control.find_children("*", "Control", true, false):
		var child_control := child as Control
		child_control.tooltip_text = ""
		child_control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_selected_resurrection(hero: HeroState) -> void:
	%ResurrectionButton.visible = hero.life_state == HeroState.DEAD
	if not %ResurrectionButton.visible:
		return
	var progression := _registry().get_definition(&"progression.demo", false) as ProgressionDefinition
	var cost := progression.resurrection_cost if progression != null else 0
	%ResurrectionButton.text = "RESURRECT HERO  /  %d GOLD" % cost
	%ResurrectionButton.disabled = progression == null or run_state.gold < cost
	%ResurrectionButton.tooltip_text = "Not enough Gold." if progression != null and run_state.gold < cost else "Restore this Hero to full HP."


func _refresh_behavior_controls(owner, attack_type: StringName) -> void:
	var farthest: bool = owner.targeting_mode == &"farthest"
	var avoids_damage: bool = owner.damage_avoidance_override == 1 or (owner.damage_avoidance_override < 0 and attack_type == &"ranged")
	%TargetClosestButton.button_pressed = not farthest
	%TargetFarthestButton.button_pressed = farthest
	%AvoidDamageButton.button_pressed = avoids_damage
	%AcceptDamageButton.button_pressed = not avoids_damage


func _set_targeting_behavior(mode: StringName) -> void:
	if not _require_preparation():
		_refresh_selected()
		return
	var owner = _selected_behavior_owner()
	if owner == null:
		return
	owner.targeting_mode = mode
	_refresh_selected()
	_set_feedback("", false)
	run_state_changed.emit(&"combat_behavior_changed")


func _set_damage_avoidance(enabled: bool) -> void:
	if not _require_preparation():
		_refresh_selected()
		return
	var owner = _selected_behavior_owner()
	if owner == null:
		return
	owner.damage_avoidance_override = 1 if enabled else 0
	_refresh_selected()
	_set_feedback("", false)
	run_state_changed.emit(&"combat_behavior_changed")


func _selected_behavior_owner():
	if selected_kind == "hero" and selected_index >= 0 and selected_index < run_state.heroes.size():
		return run_state.heroes[selected_index]
	if selected_kind == "soldier" and selected_index >= 0 and selected_index < run_state.soldiers.size():
		return run_state.soldiers[selected_index]
	return null


func _refresh_equipment(item_ids: Array[StringName], max_slots: int) -> void:
	_clear(%EquipmentRows)
	selected_equipment_slot = clampi(selected_equipment_slot, 0, max_slots - 1)
	for slot_index in max_slots:
		var occupied := slot_index < item_ids.size()
		var definition := _item_definition(item_ids[slot_index]) if occupied else null
		var button := ManagementDropSlot.new()
		button.configure(definition, &"item", str(slot_index + 1), selected_equipment_slot == slot_index)
		_apply_atlas_slot(button, selected_equipment_slot == slot_index)
		button.custom_minimum_size = ICON_SIZE
		if definition != null:
			button.drag_payload = {
				"source": &"equipped_item",
				"owner_kind": StringName(selected_kind),
				"owner_index": selected_index,
				"slot_index": slot_index,
				"instance_id": item_ids[slot_index],
			}
		button.accepted_sources = [&"equipped_item", &"inventory_item", &"market"]
		button.target_payload = {"target": &"equipment", "owner_kind": StringName(selected_kind), "owner_index": selected_index, "slot_index": slot_index if occupied else -1}
		button.payload_dropped.connect(_on_management_drop)
		button.pressed.connect(_select_equipment_slot.bind(slot_index))
		%EquipmentRows.add_child(button)
	%EquipmentCount.text = "EQUIPMENT  %d / %d" % [item_ids.size(), max_slots]


func _refresh_hero_abilities(hero: HeroState) -> void:
	_clear(%AbilityRows)
	for index in HeroState.MAX_ABILITY_SLOTS:
		var occupied := index < hero.ability_ids.size()
		var ability := _registry().get_definition(hero.ability_ids[index]) as AbilityDefinition if occupied else null
		var cell := Control.new()
		cell.custom_minimum_size = ICON_SIZE
		var select := ManagementDropSlot.new()
		var level_badge := "L%d" % hero.ability_level(ability.id) if ability != null else str(index + 1)
		var tooltip := ContentButton.describe_ability_definition(ability, hero.ability_level(ability.id)) if ability != null else ""
		select.configure(ability, &"ability", level_badge, selected_ability_slot == index, tooltip)
		_apply_atlas_slot(select, selected_ability_slot == index)
		select.custom_minimum_size = ICON_SIZE
		select.accepted_sources = []
		select.target_payload = {"target": &"ability", "owner_kind": &"hero", "owner_index": selected_index, "slot_index": index}
		select.payload_dropped.connect(_on_management_drop)
		select.pressed.connect(_select_ability_slot.bind(index))
		cell.add_child(select)
		select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		%AbilityRows.add_child(cell)


func _refresh_readonly_abilities(abilities: Array[AbilityDefinition]) -> void:
	_clear(%AbilityRows)
	for index in maxi(HeroState.MAX_ABILITY_SLOTS, abilities.size()):
		var ability: AbilityDefinition = abilities[index] if index < abilities.size() else null
		var button := ContentIconButton.new()
		button.configure(ability, &"ability", str(index + 1), false, ContentButton.describe_ability_definition(ability) if ability != null else "")
		_apply_atlas_slot(button, false)
		button.custom_minimum_size = ICON_SIZE
		%AbilityRows.add_child(button)


## Soldier abilities include previews of every purchasable Job skill level.
func _refresh_soldier_abilities(job: JobDefinition, abilities: Array[AbilityDefinition]) -> void:
	_clear(%AbilityRows)
	var trait_ids: Array[StringName] = []
	trait_ids.append_array(job.innate_ability_ids)
	trait_ids.append_array(job.available_ability_ids)
	var shown := 0
	for ability in abilities:
		if ability == null or trait_ids.has(ability.id):
			continue
		var button := ContentIconButton.new()
		button.configure(ability, &"ability", str(shown + 1), false, ContentButton.describe_ability_definition(ability))
		_apply_atlas_slot(button, false)
		button.custom_minimum_size = ICON_SIZE
		%AbilityRows.add_child(button)
		shown += 1
	_append_job_skill_previews(job)
	while %AbilityRows.get_child_count() < HeroState.MAX_ABILITY_SLOTS:
		var empty := ContentIconButton.new()
		empty.configure(null, &"ability", "")
		_apply_atlas_slot(empty, false)
		empty.custom_minimum_size = ICON_SIZE
		%AbilityRows.add_child(empty)


## Preview unpurchased levels even before their prerequisites have been bought.
func _append_job_skill_previews(job: JobDefinition, skip_equipped := false) -> void:
	for ability_id in job.innate_ability_ids:
		var innate := _registry().get_definition(ability_id, false) as AbilityDefinition
		if innate == null:
			continue
		var button := ContentIconButton.new()
		var lines: Array[String] = ["", "[color=%s]INNATE  -  every %s has it[/color]" % [AbilityText.MUTED, job.display_name]]
		button.configure(innate, &"ability", "I", false, ContentButton.describe_ability_definition(innate, 0, lines))
		_apply_atlas_slot(button, false)
		button.custom_minimum_size = ICON_SIZE
		%AbilityRows.add_child(button)
	var build := _job_build(job.id)
	for ability_id in job.available_ability_ids:
		var ability := _registry().get_definition(ability_id, false) as AbilityDefinition
		if ability == null:
			continue
		var equipped := build.active_ability_id == ability_id or build.passive_ability_ids.has(ability_id)
		if skip_equipped and equipped:
			continue
		var owned := build.owned_ability_ids.has(ability_id)
		var replaced := build.has_owned_upgrade(ability_id, _registry())
		var level := ability.job_skill_level(_registry())
		var lines: Array[String] = [""]
		var badge := "LV %d" % level
		if replaced:
			badge = "REPLACED"
			lines.append("[color=%s]PURCHASED  -  replaced by a purchased upgrade[/color]" % AbilityText.MUTED)
		elif owned:
			lines.append("[color=%s]PURCHASED  -  %s for every %s[/color]" % [AbilityText.TAG_STYLES.heal.color, "equipped" if equipped else "not equipped", job.display_name])
		else:
			badge = "NOT BOUGHT"
			lines.append("[color=%s]NOT PURCHASED  -  buy in the Market for %d Gold[/color]" % [AbilityText.TAG_STYLES.debuff.color, ability.price])
			if not ability.upgrades_ability_id.is_empty():
				lines.append("Requires purchase of %s first." % _display_name(ability.upgrades_ability_id))
		var button := ContentIconButton.new()
		button.configure(ability, &"ability", badge, equipped, ContentButton.describe_ability_definition(ability, 0, lines))
		_apply_atlas_slot(button, equipped)
		button.custom_minimum_size = ICON_SIZE
		button.locked = not owned
		if replaced:
			button.modulate = Color(0.7, 0.66, 0.6)
		%AbilityRows.add_child(button)


func _refresh_roster_job_ids() -> void:
	roster_job_ids.clear()
	for definition in _definitions(JobDefinition):
		var job := definition as JobDefinition
		if run_state.unlocked_job_ids.has(job.id):
			roster_job_ids.append(job.id)


func _refresh_job_build_panel() -> void:
	if selected_kind != "job" or String(selected_job_id).is_empty():
		%CapacityLabel.text = "NO SPECIALIST JOBS UNLOCKED"
		return
	var job_id := selected_job_id
	var job := _registry().get_definition(job_id) as JobDefinition
	if job == null:
		return
	%CapacityLabel.text = (
		"CAPACITY  %d assigned / UNLIMITED" % _assigned_count(job_id)
		if job_id == &"job.militia"
		else "CAPACITY  %d / %d assigned" % [_assigned_count(job_id), _capacity(job_id)]
	)
	%CapacityLabel.tooltip_text = String(job_id)
	_refresh_job_ability_slots(job_id)


func _refresh_job_ability_slots(job_id: StringName) -> void:
	_clear(%AbilityRows)
	var build := _job_build(job_id)
	var active := _registry().get_definition(build.active_ability_id, false) as AbilityDefinition
	var active_slot := _job_ability_drop_slot(job_id, &"active", 0, active)
	%AbilityRows.add_child(active_slot)
	for index in 3:
		var ability_id: StringName = build.passive_ability_ids[index] if index < build.passive_ability_ids.size() else &""
		var passive := _registry().get_definition(ability_id, false) as AbilityDefinition
		var slot := _job_ability_drop_slot(job_id, &"passive", index, passive)
		%AbilityRows.add_child(slot)
	var job := _registry().get_definition(job_id, false) as JobDefinition
	if job != null:
		_append_job_skill_previews(job, true)


func _job_ability_drop_slot(job_id: StringName, slot_kind: StringName, slot_index: int, ability: AbilityDefinition) -> ManagementDropSlot:
	var slot := ManagementDropSlot.new()
	slot.configure(ability, &"ability", "A" if slot_kind == &"active" else "P%d" % (slot_index + 1))
	_apply_atlas_slot(slot, false)
	slot.custom_minimum_size = ICON_SIZE
	slot.accepted_sources = [&"market"]
	slot.target_payload = {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": slot_kind, "slot_index": slot_index}
	slot.payload_dropped.connect(_on_management_drop)
	return slot


func _apply_atlas_slot(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", _slot_style(Color(1.12, 0.94, 0.66) if selected else Color(0.86, 0.8, 0.72)))
	button.add_theme_stylebox_override("hover", _slot_style(Color(1.25, 1.02, 0.7)))
	button.add_theme_stylebox_override("pressed", _slot_style(Color(1.25, 0.66, 0.48)))
	button.add_theme_stylebox_override("disabled", _slot_style(Color(0.5, 0.46, 0.42, 0.8)))


func _slot_style(tint: Color) -> StyleBoxTexture:
	return UiStyle.atlas_box(UiStyle.SLOT_REGION, Vector4(16, 16, 16, 16), Vector4(8, 8, 8, 8), tint)


func _refresh_market() -> void:
	_clear(%MarketRows)
	var toolbar := HBoxContainer.new()
	toolbar.name = "MarketToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	%MarketRows.add_child(toolbar)
	var reroll := Button.new()
	reroll.name = "RerollButton"
	reroll.theme_type_variation = &"GoldButton"
	reroll.custom_minimum_size = Vector2(0.0, 50.0)
	reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll.text = "REROLL   %d" % MarketService.reroll_price(run_state.market)
	reroll.icon = _ability_icon("gold")
	reroll.add_theme_constant_override("icon_max_width", 22)
	reroll.add_theme_font_override("font", _number_font())
	reroll.add_theme_font_size_override("font_size", 19)
	reroll.pressed.connect(_on_market_reroll_pressed)
	toolbar.add_child(reroll)
	var sell := ManagementDropSlot.new()
	sell.name = "SellDropSlot"
	sell.text = "SELL  -  DROP GEAR HERE"
	sell.custom_minimum_size = Vector2(0.0, 50.0)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.theme_type_variation = &"LedgerButton"
	sell.add_theme_font_size_override("font_size", 15)
	sell.add_theme_color_override("font_color", Color(0.95, 0.72, 0.5))
	sell.tooltip_override = "Drag an item from a Hero onto this slot to sell it for its sell price."
	sell.accepted_sources = [&"equipped_item", &"inventory_item"]
	sell.target_payload = {"target": &"sell"}
	sell.payload_dropped.connect(_on_management_drop)
	toolbar.add_child(sell)
	var hint := Label.new()
	hint.name = "MarketHint"
	hint.text = "Drag an offer onto a Hero or Job slot, or press its price."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", CARD_MUTED)
	%MarketRows.add_child(hint)
	for offer in run_state.market.offers:
		var definition: ContentDefinition = _registry().get_definition(offer.content_id, false)
		if definition != null:
			%MarketRows.add_child(_market_card(offer, definition))


## One Market offer: framed icon, name, kind, a short description, key numbers with
## icons, the price button and the lock toggle. The whole card is a drag source.
func _market_card(offer: MarketOffer, definition: ContentDefinition) -> PanelContainer:
	var accent := _offer_accent(offer, definition)
	var payload := {
		"source": &"market",
		"offer_id": offer.offer_id,
		"offer_type": offer.offer_type,
		"content_id": offer.content_id,
	}
	var tooltip := "%s\n\n%s" % [_offer_tag(offer, definition), ContentButton.describe_content(definition.id)]
	var card := PanelContainer.new()
	card.name = "Offer_%s" % offer.offer_id.validate_node_name()
	card.set_meta("offer_id", offer.offer_id)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _offer_card_style(accent, offer.is_pinned))
	card.gui_input.connect(_on_market_offer_gui_input.bind(offer.offer_id))
	card.set_drag_forwarding(_market_card_drag.bind(payload, _market_icon_texture(definition, offer.offer_type)), Callable(), Callable())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(row)

	var icon := ManagementDropSlot.new()
	icon.name = "Icon"
	icon.configure(definition, &"item" if definition is ItemDefinition else &"ability", "", false, tooltip)
	icon.icon = _market_icon_texture(definition, offer.offer_type)
	icon.custom_minimum_size = Vector2(76, 76)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.accepted_sources = [&"none"]
	icon.drag_payload = payload
	icon.gui_input.connect(_on_market_offer_gui_input.bind(offer.offer_id))
	for state in ["normal", "hover", "pressed"]:
		icon.add_theme_stylebox_override(state, _icon_frame_style(accent, state != "normal"))
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(info)
	var title := Label.new()
	title.name = "Title"
	title.text = definition.display_name
	title.theme_type_variation = &"EyebrowLabel"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", CARD_TITLE)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	var tag := Label.new()
	tag.name = "Tag"
	tag.text = _offer_tag(offer, definition)
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", accent.lightened(0.25))
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(tag)
	var description := _offer_description(offer, definition)
	if not description.is_empty():
		var body := Label.new()
		body.name = "Description"
		body.text = description
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.max_lines_visible = 2
		body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		body.add_theme_font_size_override("font_size", 14)
		body.add_theme_color_override("font_color", CARD_BODY)
		body.custom_minimum_size.x = 200.0
		info.add_child(body)
	var stats := HFlowContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("h_separation", 14)
	stats.add_theme_constant_override("v_separation", 2)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_offer_stats(stats, offer, definition)
	if stats.get_child_count() > 0:
		info.add_child(stats)
	else:
		stats.free()

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(actions)
	var affordable := run_state.gold >= offer.price
	var buy := Button.new()
	buy.name = "BuyButton"
	buy.theme_type_variation = &"GoldButton"
	buy.custom_minimum_size = Vector2(108.0, 44.0)
	buy.text = "%d" % offer.price
	buy.icon = _ability_icon("gold")
	buy.add_theme_constant_override("icon_max_width", 20)
	buy.add_theme_font_size_override("font_size", 20)
	buy.add_theme_font_override("font", _number_font())
	if not affordable:
		buy.add_theme_color_override("font_color", Color(0.9, 0.48, 0.4))
		buy.add_theme_color_override("font_hover_color", Color(1.0, 0.56, 0.48))
		buy.tooltip_text = "Need %d more Gold." % (offer.price - run_state.gold)
	buy.pressed.connect(_buy_market_offer.bind(offer.offer_id))
	actions.add_child(buy)
	var pin := Button.new()
	pin.name = "PinButton"
	pin.theme_type_variation = &"TabButton"
	pin.custom_minimum_size = Vector2(108.0, 30.0)
	pin.toggle_mode = true
	pin.button_pressed = offer.is_pinned
	pin.text = "LOCKED" if offer.is_pinned else "LOCK"
	pin.add_theme_font_size_override("font_size", 13)
	pin.tooltip_text = "Keep this offer in the same position when the Market refreshes."
	pin.toggled.connect(_on_market_pin_toggled.bind(offer.offer_id))
	actions.add_child(pin)
	return card


func _market_card_drag(_position: Vector2, payload: Dictionary, texture: Texture2D) -> Variant:
	set_drag_preview(ManagementDropSlot.make_icon_preview(texture))
	return payload.duplicate(true)


func _offer_accent(offer: MarketOffer, definition: ContentDefinition) -> Color:
	if definition is ItemDefinition:
		var item := definition as ItemDefinition
		return ITEM_ACCENTS[4] if item.is_unique() else ITEM_ACCENTS[clampi(item.category, 0, 4)]
	if offer.offer_type == &"job_unlock" and run_state.unlocked_job_ids.has(offer.content_id):
		return OFFER_ACCENTS[&"job_capacity"]
	return OFFER_ACCENTS.get(offer.offer_type, UiStyle.BRONZE)


## Short kind line: "TANK ITEM  ·  MELEE HEROES", "NEW JOB", "ARCHER SKILL  ·  LEVEL 2  ·  UPGRADE".
func _offer_tag(offer: MarketOffer, definition: ContentDefinition) -> String:
	match offer.offer_type:
		&"hero_item":
			var item := definition as ItemDefinition
			var parts: Array[String] = ["UNIQUE ITEM" if item.is_unique() else "%s ITEM" % ItemDefinition.category_name(item.category).to_upper()]
			parts.append(item.restriction_text(_registry()).to_upper() if not item.restriction_text(_registry()).is_empty() else "ANY HERO")
			return "  ·  ".join(parts)
		&"job_unlock":
			if run_state.unlocked_job_ids.has(offer.content_id):
				return "+1 JOB PLACE"
			return "NEW JOB  ·  1 PLACE"
		&"job_capacity":
			return "+1 JOB PLACE  ·  %d %s" % [_capacity(offer.content_id), "→ %d" % (_capacity(offer.content_id) + 1)]
		&"job_ability":
			var ability := definition as AbilityDefinition
			var parts: Array[String] = ["%s SKILL" % _display_name(StringName(offer.target_id)).to_upper(), "LEVEL %d" % ability.job_skill_level(_registry())]
			if not ability.upgrades_ability_id.is_empty():
				parts.append("UPGRADE")
			return "  ·  ".join(parts)
	return _market_offer_type_name(offer.offer_type)


func _offer_description(offer: MarketOffer, definition: ContentDefinition) -> String:
	match offer.offer_type:
		&"job_ability":
			return AbilityText.plain(definition as AbilityDefinition)
		&"job_capacity":
			return "One more Soldier can take the %s Job." % definition.display_name
		&"job_unlock":
			if run_state.unlocked_job_ids.has(offer.content_id):
				return "One more Soldier can take the %s Job." % definition.display_name
	return definition.description


## Key numbers as icon + value pairs: item bonuses and abilities, a Job's base stats,
## or a skill's type, cooldown and reach.
func _fill_offer_stats(stats: HFlowContainer, offer: MarketOffer, definition: ContentDefinition) -> void:
	if definition is ItemDefinition:
		var item := definition as ItemDefinition
		for modifier in item.passive_effects:
			if modifier == null:
				continue
			var value := modifier.display_text()
			value = value.substr(0, value.find(" ")) if value.find(" ") > 0 else value
			_stat_chip(stats, _stat_icon(modifier.stat), value, String(STAT_SHORT.get(modifier.stat, modifier.stat)), modifier.value < 0.0 and modifier.stat != "damage_taken")
		for ability_id in item.ability_ids:
			var ability := _registry().get_definition(ability_id, false) as AbilityDefinition
			if ability != null:
				var passive := ability.kind == AbilityDefinition.AbilityKind.PASSIVE
				_stat_chip(stats, _ability_icon("passive" if passive else "active"), ability.display_name, "", false)
	elif definition is JobDefinition:
		var job := definition as JobDefinition
		if job.stat_modifiers != null:
			_stat_chip(stats, _stat_icon("max_hp"), StatModifier.format_number(job.stat_modifiers.max_hp), "HP")
			_stat_chip(stats, _stat_icon("damage"), StatModifier.format_number(job.stat_modifiers.damage), "DMG")
			_stat_chip(stats, _stat_icon("armor"), StatModifier.format_number(job.stat_modifiers.armor), "ARMOR")
			if job.attack_type == &"ranged":
				_stat_chip(stats, _stat_icon("attack_range"), StatModifier.format_number(job.stat_modifiers.attack_range), "RANGE")
			else:
				_stat_chip(stats, _ability_icon("damage"), "MELEE", "")
	elif definition is AbilityDefinition:
		var ability := definition as AbilityDefinition
		var passive := ability.kind == AbilityDefinition.AbilityKind.PASSIVE
		_stat_chip(stats, _ability_icon("passive" if passive else "active"), "PASSIVE" if passive else "ACTIVE", "")
		if not passive and ability.cooldown_seconds > 0.0:
			_stat_chip(stats, _ability_icon("cooldown"), "%ss" % StatModifier.format_number(ability.cooldown_seconds), "")
		var reach := ability.target_search_radius if ability.target_search_radius > 0.0 else ability.cast_range
		if reach > 0.0:
			_stat_chip(stats, _ability_icon("range"), StatModifier.format_number(reach), "")
		if ability.area_radius > 0.0:
			_stat_chip(stats, _ability_icon("radius"), StatModifier.format_number(ability.area_radius), "")


## One "icon value LABEL" group; groups wrap as a whole inside the stats flow.
func _stat_chip(stats: HFlowContainer, texture: Texture2D, value: String, label: String, negative := false) -> void:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2(20, 20)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(image)
	var number := Label.new()
	number.text = value
	number.add_theme_font_size_override("font_size", 16)
	number.add_theme_color_override("font_color", Color(1.0, 0.56, 0.48) if negative else Color(0.98, 0.9, 0.72))
	chip.add_child(number)
	if not label.is_empty():
		var caption := Label.new()
		caption.text = label
		caption.add_theme_font_size_override("font_size", 11)
		caption.add_theme_color_override("font_color", CARD_MUTED)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(caption)
	stats.add_child(chip)


## Lining numerals: the heading font's old-style digits read poorly in prices.
func _number_font() -> Font:
	return get_theme_font("font", &"NumberLabel")


func _stat_icon(stat: String) -> Texture2D:
	if STAT_ATLAS_REGIONS.has(stat):
		var texture := AtlasTexture.new()
		texture.atlas = ATLAS
		texture.region = STAT_ATLAS_REGIONS[stat]
		texture.filter_clip = true
		return texture
	return _ability_icon(String(STAT_ICON_NAMES.get(stat, "buff")))


func _ability_icon(icon_name: String) -> Texture2D:
	var path := AbilityText.ICON_DIR + icon_name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _offer_card_style(accent: Color, pinned: bool) -> StyleBoxFlat:
	var style := UiStyle.chamfer_box(
		Color(0.075, 0.054, 0.04, 0.95),
		Color(accent.r, accent.g, accent.b, 0.55 if pinned else 0.3),
		2, 6, Color(0, 0, 0, 0), 0, Vector4(10, 10, 12, 10)
	)
	style.border_width_left = 5
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85 if pinned else 0.55)
	return style


func _icon_frame_style(accent: Color, hover: bool) -> StyleBoxFlat:
	var style := UiStyle.chamfer_box(
		Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.98),
		Color(accent.r, accent.g, accent.b, 0.95 if hover else 0.6),
		2, 6, Color(accent.r, accent.g, accent.b, 0.3 if hover else 0.12), 8 if hover else 4, Vector4(6, 6, 6, 6)
	)
	return style


func _refresh_encounter() -> void:
	%EncounterTitle.text = "ACT %s  /  BATTLE %d" % [_roman(run_state.current_act), run_state.encounter_index + 1]
	if run_state.available_encounter_ids.is_empty():
		%EncounterLabel.text = "NO ENCOUNTER"
		%FightButton.disabled = true
		return
	if String(run_state.selected_encounter_id).is_empty():
		%EncounterLabel.text = "CHOOSE THE NEXT BATTLE"
		%EncounterLabel.tooltip_text = ""
		%FightButton.disabled = true
		%FightButton.text = "CHOOSE AN ENCOUNTER"
		_refresh_preview()
		return
	var encounter := _registry().get_definition(run_state.selected_encounter_id, false) as EncounterDefinition
	if encounter == null:
		%EncounterLabel.text = "Selected encounter content is missing."
		%FightButton.disabled = true
		return
	%EncounterLabel.text = "%s  /  %s THREAT  /  %d GOLD" % [encounter.display_name.to_upper(), encounter.difficulty_hint.to_upper(), encounter.gold_reward]
	if encounter.has_reinforcements():
		%EncounterLabel.text += "  /  REINFORCEMENTS AT %d" % encounter.reinforcement_alive_threshold
	%EncounterLabel.tooltip_text = String(encounter.id)
	var threat_color: Color = EncounterChoiceScreen.UNKNOWN_COLOR if encounter.is_unknown else EncounterChoiceScreen.THREAT_COLORS.get(encounter.difficulty_hint, UiStyle.GOLD)
	%EncounterLabel.add_theme_color_override("font_color", threat_color.lightened(0.25))
	%FightButton.disabled = false
	%FightButton.text = "COMMIT TO BATTLE"
	_refresh_preview()


func _select_encounter(encounter_id: StringName) -> void:
	var result := EncounterService.select_encounter(run_state, encounter_id)
	if not result.ok:
		_set_feedback(result.error, true)
		return
	call_deferred("_refresh_all")
	_set_feedback("", false)
	run_state_changed.emit(&"encounter_selected")


func _on_management_drop(source: Dictionary, target: Dictionary) -> void:
	var result := ArmyBuildService.perform_drop(run_state, source, target, _registry())
	if not result.ok:
		_set_feedback(result.error, not result.error.is_empty())
		return
	# The drop target is locked until Control._drop_data() returns.
	call_deferred("_refresh_all")
	var action := StringName(result.get("action", &"build_changed"))
	_set_feedback("", false)
	run_state_changed.emit(action)


func _refresh_preview() -> void:
	if run_state == null:
		return
	var snapshots := CombatSnapshotBuilder.build_player_army(run_state, _registry())
	var melee := 0
	var ranged := 0
	for snapshot in snapshots:
		if snapshot.attack_type == &"ranged":
			ranged += 1
		else:
			melee += 1
	%PreviewLabel.text = "%d UNITS   ·   %d MELEE   ·   %d RANGED" % [snapshots.size(), melee, ranged]


func _select_ability_slot(index: int) -> void:
	selected_ability_slot = index
	call_deferred("_refresh_selected")
	_set_feedback("", false)


func _select_equipment_slot(index: int) -> void:
	selected_equipment_slot = index
	call_deferred("_refresh_selected")
	_set_feedback("", false)


func _buy_market_offer(offer_id: String) -> void:
	var offer := _market_offer(offer_id)
	if offer == null:
		_set_feedback("That Market offer is no longer available.", true)
		return
	if offer.offer_type != &"hero_item":
		var purchase := MarketService.buy_offer(run_state, offer_id, _registry())
		if not purchase.ok:
			_set_feedback(purchase.error, true)
			return
		call_deferred("_refresh_all")
		_set_feedback("", false)
		run_state_changed.emit(&"job_build_changed" if offer.offer_type == &"job_ability" else &"market_purchase")
		return
	var target := _automatic_market_target(offer)
	if not target.ok:
		_set_feedback(target.error, true)
		return
	var result := ArmyBuildService.perform_drop(
		run_state,
		{"source": &"market", "offer_id": offer.offer_id},
		target.target,
		_registry()
	)
	if not result.ok:
		_set_feedback(result.error, true)
		return
	call_deferred("_refresh_all")
	_set_feedback("", false)
	run_state_changed.emit(StringName(result.get("action", &"market_purchase")))


func _market_offer(offer_id: String) -> MarketOffer:
	for offer in run_state.market.offers:
		if offer.offer_id == offer_id:
			return offer
	return null


func _automatic_market_target(offer: MarketOffer) -> Dictionary:
	if offer.offer_type == &"hero_item":
		var target := _free_item_slot_hero(offer.content_id)
		if target >= 0:
			return {"ok": true, "target": {"target": &"equipment", "owner_kind": &"hero", "owner_index": target, "slot_index": -1}}
		var item := _registry().get_definition(offer.content_id, false) as ItemDefinition
		for hero in run_state.heroes:
			if hero.life_state != HeroState.EXECUTED and item != null and item.is_compatible_with_hero(_registry().get_definition(hero.definition_id, false) as HeroDefinition):
				return _target_failure("Every Hero who can use this item has six. Sell one by dragging it onto the Market.")
		return _target_failure("No Hero in the army can use this item.")
	if selected_kind == "soldier" and selected_index >= 0 and selected_index < run_state.soldiers.size() and offer.offer_type == &"job_ability":
		return _automatic_job_ability_target(offer, run_state.soldiers[selected_index].current_job_id)
	if selected_kind == "job" and offer.offer_type == &"job_ability":
		return _automatic_job_ability_target(offer, selected_job_id)
	return _target_failure("Select the Hero or Job named on this offer.")


func _automatic_job_ability_target(offer: MarketOffer, job_id: StringName) -> Dictionary:
	var ability := _registry().get_definition(offer.content_id, false) as AbilityDefinition
	if ability == null:
		return _target_failure("That ability content is missing.")
	if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
		return {"ok": true, "target": {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": &"active", "slot_index": 0}}
	var passive_count := 0
	for build in run_state.job_builds:
		if build.job_id == job_id:
			var previous_slot := build.passive_ability_ids.find(ability.upgrades_ability_id)
			if previous_slot >= 0:
				return {"ok": true, "target": {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": &"passive", "slot_index": previous_slot}}
			passive_count = build.passive_ability_ids.size()
			break
	if passive_count >= 3:
		return _target_failure("All Job passive slots are full. Drag the offer onto a passive slot to replace it.")
	return {"ok": true, "target": {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": &"passive", "slot_index": passive_count}}


func _target_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _on_market_offer_gui_input(event: InputEvent, offer_id: String) -> void:
	if _is_left_double_click(event):
		call_deferred("_buy_market_offer", offer_id)


func _buy_capacity(job_id: StringName) -> void:
	for offer in run_state.market.offers:
		if offer.content_id == job_id and offer.offer_type == &"job_capacity":
			_buy_market_offer(offer.offer_id)
			return
	_set_feedback("No capacity offer is available for %s." % _display_name(job_id), true)


func _on_market_reroll_pressed() -> void:
	var result := MarketService.reroll(run_state, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	call_deferred("_refresh_all")
	_set_feedback("", false)
	run_state_changed.emit(&"market_reroll")


func _on_market_pin_toggled(pinned: bool, offer_id: String) -> void:
	var result := MarketService.set_offer_pinned(run_state, offer_id, pinned)
	if not result.ok:
		_set_feedback(result.error, true)
		call_deferred("_refresh_market")
		return
	call_deferred("_refresh_market")
	_set_feedback("", false)
	run_state_changed.emit(&"market_pin_changed")


func _resurrect_hero(hero_id: String) -> void:
	var result := ResurrectionService.resurrect(run_state, hero_id, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	_refresh_all()
	_set_feedback("%s returned to life at full HP for %d Gold." % [_display_name(result.hero.definition_id), result.cost], false)
	run_state_changed.emit(&"hero_resurrected")


func _resurrect_selected_hero() -> void:
	if selected_kind != "hero" or selected_index < 0 or selected_index >= run_state.heroes.size():
		return
	_resurrect_hero(run_state.heroes[selected_index].unique_id)


func _on_fight_button_pressed() -> void:
	combat_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()


func _job_build(job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	var build := JobBuildState.new()
	build.job_id = job_id
	run_state.job_builds.append(build)
	return build


func _assigned_count(job_id: StringName) -> int:
	var count := 0
	for soldier in run_state.soldiers:
		if soldier.current_job_id == job_id:
			count += 1
	return count


func _capacity(job_id: StringName) -> int:
	return int(run_state.job_capacities.get(String(job_id), 0))


func _definitions(script_type: Variant) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	for definition in _registry().definitions.values():
		if is_instance_of(definition, script_type):
			result.append(definition)
	result.sort_custom(func(a: ContentDefinition, b: ContentDefinition) -> bool: return a.display_name < b.display_name)
	return result


func _is_left_double_click(event: InputEvent) -> bool:
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and event.double_click
	)


func _display_name(content_id: StringName) -> String:
	var definition: ContentDefinition = _registry().get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


func _market_icon_texture(definition: ContentDefinition, offer_type: StringName) -> Texture2D:
	if definition is AbilityDefinition and definition.presentation_icon != null:
		return definition.presentation_icon
	if definition != null and definition.icon != null:
		return definition.icon
	return OrnateFrame.gem_texture(_market_offer_gem(offer_type))


func _market_offer_gem(offer_type: StringName) -> StringName:
	match offer_type:
		&"hero_item": return &"amber"
		&"job_unlock": return &"green"
		&"job_capacity": return &"blue"
		&"job_ability": return &"purple"
	return &"bronze"


func _market_offer_type_name(offer_type: StringName) -> String:
	return String(offer_type).replace("_", " ").to_upper()


func _encounter_card_text(encounter: EncounterDefinition) -> String:
	var heading := "UNKNOWN ENCOUNTER" if encounter.is_unknown else encounter.display_name.to_upper()
	var details := "Composition concealed" if encounter.is_unknown else _enemy_composition(encounter.enemy_ids)
	if encounter.has_reinforcements():
		var direction := "right side" if encounter.reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE else "all sides"
		details += "\nReinforcements at %d from %s" % [encounter.reinforcement_alive_threshold, direction]
		if not encounter.is_unknown:
			details += ": %s" % _enemy_composition(encounter.reinforcement_enemy_ids)
	var properties := "Risk concealed" if encounter.is_unknown else "; ".join(encounter.key_properties)
	return "%s\n%s | %d GOLD\n%s\n%s" % [heading, encounter.difficulty_hint.to_upper(), encounter.gold_reward, details, properties]


func _enemy_composition(enemy_ids: Array[StringName]) -> String:
	var counts: Dictionary = {}
	for enemy_id in enemy_ids:
		var enemy := _registry().get_definition(enemy_id, false) as EnemyDefinition
		var name := enemy.display_name if enemy != null else String(enemy_id)
		counts[name] = int(counts.get(name, 0)) + 1
	var parts := PackedStringArray()
	for enemy_name in counts:
		parts.append("%s x%d" % [enemy_name, counts[enemy_name]])
	return ", ".join(parts)


func _require_preparation() -> bool:
	if not String(run_state.selected_encounter_id).is_empty():
		return true
	_set_feedback("Choose an Encounter Card before rebuilding the army.", true)
	return false


func _roman(value: int) -> String:
	return "II" if value == 2 else "I"


func _item_definition(instance_id: StringName) -> ItemDefinition:
	return _registry().get_definition(run_state.inventory.get_definition_id(instance_id), false) as ItemDefinition


func _names(ids: Array[StringName]) -> String:
	if ids.is_empty():
		return "Empty"
	var names := PackedStringArray()
	for content_id in ids:
		names.append(_display_name(content_id))
	return ", ".join(names)


func _set_feedback(message: String, is_error: bool) -> void:
	%FeedbackLabel.text = message
	%FeedbackLabel.modulate = Color(1.0, 0.48, 0.4) if is_error else Color(0.62, 0.82, 0.68)


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")


## "Veterancy 3  -  260 / 500 XP" (or "max rank" at the last threshold).
func _veterancy_text(soldier: SoldierState) -> String:
	var progression := _registry().get_definition(&"progression.demo", false) as ProgressionDefinition
	if progression == null:
		return "Veterancy %d" % soldier.veterancy_level
	var thresholds := progression.veterancy_xp_thresholds
	var next_index := soldier.veterancy_level + 1
	if next_index >= thresholds.size():
		return "Veterancy %d  -  max rank" % soldier.veterancy_level
	return "Veterancy %d  -  %d / %d XP" % [soldier.veterancy_level, soldier.veterancy_xp, thresholds[next_index]]
