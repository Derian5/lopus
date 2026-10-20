class_name HeroSelectionCard
extends Control


signal card_requested

const UI_ATLAS := preload("res://graphics/ui/atlas_ui.png")
const IDENTITY_INDEX := {
	"Greed": 0,
	"Pride": 1,
	"Wrath": 2,
	"Envy": 3,
	"Despair": 4,
	"Gluttony": 5,
	"Lust": 6,
}
const BACKGROUND_REGIONS := [
	Rect2(20, 535, 147, 165), Rect2(174, 535, 147, 165), Rect2(327, 535, 146, 165),
	Rect2(481, 535, 139, 165), Rect2(628, 535, 148, 165), Rect2(782, 535, 148, 165),
	Rect2(936, 535, 147, 165),
]
const BADGE_REGIONS := [
	Rect2(18, 432, 77, 92), Rect2(99, 432, 77, 92), Rect2(180, 432, 77, 92),
	Rect2(261, 432, 77, 92), Rect2(342, 432, 77, 92), Rect2(425, 432, 77, 92),
	Rect2(508, 432, 77, 92),
]
## Lit identity gems, indexed like BADGE_REGIONS.
const LIT_GEM_REGIONS := [
	Rect2(1285, 661, 37, 36), Rect2(1582, 794, 29, 30), Rect2(1404, 661, 35, 36),
	Rect2(1461, 662, 36, 35), Rect2(1516, 662, 35, 35), Rect2(1570, 662, 34, 35),
	Rect2(1623, 664, 31, 32),
]
## Unlit identity gems, indexed like BADGE_REGIONS.
const DIM_GEM_REGIONS := [
	Rect2(1289, 702, 30, 30), Rect2(1350, 703, 28, 28), Rect2(1406, 703, 29, 28),
	Rect2(1464, 702, 30, 29), Rect2(1520, 703, 29, 28), Rect2(1572, 703, 29, 28),
	Rect2(1625, 703, 27, 28),
]
## Glowing name plaques, indexed like BADGE_REGIONS.
const GLOW_PLAQUE_REGIONS := [
	Rect2(21, 843, 147, 35), Rect2(175, 843, 147, 35), Rect2(329, 843, 148, 35),
	Rect2(483, 843, 147, 35), Rect2(638, 843, 149, 35), Rect2(795, 843, 149, 35),
	Rect2(951, 843, 144, 35),
]
const EMPTY_PLAQUE_REGION := Rect2(21, 885, 146, 36)
const EMPTY_GEM_REGION := Rect2(1626, 881, 26, 26)
const STAT_ICON_REGIONS := [
	Rect2(610, 445, 66, 66), Rect2(686, 445, 66, 66), Rect2(755, 445, 66, 66),
	Rect2(832, 445, 66, 66), Rect2(915, 444, 66, 66), Rect2(994, 444, 66, 66),
]

@onready var hero_name: Label = %HeroName
@onready var role_label: Label = %RoleLabel
@onready var description_label: Label = %Description
@onready var portrait: TextureRect = %Portrait
@onready var initials: Label = %Initials
@onready var card_hitbox: Button = %CardHitbox
@onready var button_motion: ButtonMotion = %CardHitbox.get_node("ButtonMotion")
@onready var ornament_frame = %OrnamentFrame

var hero: HeroDefinition
var is_active_card := false
var selected_order := -1


func _ready() -> void:
	%CardHitbox.pressed.connect(func() -> void: card_requested.emit())
	var icons := [%HpIcon, %DamageIcon, %AttackSpeedIcon, %MoveSpeedIcon, %RangeIcon, %ArmorIcon]
	for index in icons.size():
		icons[index].texture = atlas_texture(STAT_ICON_REGIONS[index])


func setup(definition: HeroDefinition, selected_order_arg: int, active_card: bool) -> void:
	var same_hero := hero == definition
	hero = definition
	is_active_card = active_card
	selected_order = selected_order_arg if definition != null else -1
	visible = hero != null
	if hero == null:
		return
	var identity_index := identity_index_of(hero)
	%Backdrop.texture = atlas_texture(BACKGROUND_REGIONS[identity_index])
	%Badge.texture = atlas_texture(BADGE_REGIONS[identity_index])
	portrait.texture = hero.portrait
	portrait.visible = hero.portrait != null
	initials.visible = hero.portrait == null
	initials.text = _initials(hero.display_name)
	_align_portrait_top()
	hero_name.text = hero.display_name.to_upper()
	role_label.text = _role_text(hero)
	description_label.text = hero.description
	%HpValue.text = _number(hero.base_stats.max_hp)
	%DamageValue.text = _number(hero.base_stats.damage)
	%AttackSpeedValue.text = _number(hero.base_stats.attack_speed)
	%MoveSpeedValue.text = _number(hero.base_stats.movement_speed)
	%RangeValue.text = _number(hero.base_stats.attack_range)
	%ArmorValue.text = _number(hero.base_stats.armor)
	%Badge.modulate = Color(1.25, 1.25, 1.25, 1.0) if selected_order >= 0 else Color.WHITE
	card_hitbox.disabled = false
	card_hitbox.mouse_filter = Control.MOUSE_FILTER_STOP
	card_hitbox.focus_mode = Control.FOCUS_ALL if is_active_card else Control.FOCUS_NONE
	modulate = Color.WHITE if is_active_card else Color(0.72, 0.75, 0.82, 0.88)
	_scale_content(active_card)
	_configure_motion(active_card)
	_apply_styles(hero.placeholder_color, active_card, identity_index, same_hero)


func set_select_disabled(disabled: bool) -> void:
	card_hitbox.disabled = disabled


func grab_selection_focus() -> void:
	card_hitbox.grab_focus()


func _align_portrait_top() -> void:
	if portrait.texture == null:
		return
	var source_size: Vector2 = portrait.texture.get_size()
	var frame_size: Vector2 = (%PortraitClip as Control).size
	if source_size.x <= 0.0 or source_size.y <= 0.0 or frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return
	var factor: float = maxf(frame_size.x / source_size.x, frame_size.y / source_size.y)
	portrait.size = source_size * factor
	portrait.position = Vector2((frame_size.x - portrait.size.x) * 0.5, 0.0)


func _scale_content(active_card: bool) -> void:
	var target_scale := Vector2.ONE if active_card else Vector2(0.92, 0.92)
	%VisualRoot.scale = target_scale
	button_motion.set_rest_state(target_scale)


func _configure_motion(active_card: bool) -> void:
	button_motion.animate_focus = false
	button_motion.hover_scale = 1.045 if active_card else 1.025
	button_motion.hover_color = Color(1.12, 1.12, 1.16, 1.0) if active_card else Color(1.06, 1.06, 1.09, 1.0)
	button_motion.pressed_scale = 0.975 if active_card else 0.96


func _apply_styles(color: Color, active_card: bool, identity_index: int, animate: bool) -> void:
	ornament_frame.configure(
		color,
		active_card,
		selected_order,
		atlas_texture(LIT_GEM_REGIONS[identity_index]),
		atlas_texture(DIM_GEM_REGIONS[identity_index]),
		animate
	)
	hero_name.add_theme_color_override("font_color", color.lightened(0.35))
	role_label.add_theme_color_override("font_color", color.lightened(0.2))


static func identity_index_of(definition: HeroDefinition) -> int:
	if definition == null:
		return 0
	return int(IDENTITY_INDEX.get(definition.display_name, 0))


static func atlas_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = UI_ATLAS
	texture.region = region
	return texture


func _role_text(definition: HeroDefinition) -> String:
	if not definition.role_title.is_empty():
		return definition.role_title
	var roles := PackedStringArray()
	for tag in definition.tags:
		if tag != &"hero" and tag != &"test":
			roles.append(String(tag).to_upper())
	return " / ".join(roles)


func _initials(display_name: String) -> String:
	var result := ""
	for word in display_name.split(" ", false):
		result += word.left(1).to_upper()
	return result.left(3)


func _number(value: float) -> String:
	return "%.2f" % value if not is_equal_approx(value, roundf(value)) else "%d" % int(value)
