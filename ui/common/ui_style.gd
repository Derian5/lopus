class_name UiStyle
extends RefCounted


## Shared palette and StyleBox factories for the gothic bronze interface.
## Theme-wide defaults live in res://ui/game_theme.tres (generated); use these
## helpers for elements that need an identity accent (Hero colors, threat colors).

const BG := Color(0.06, 0.042, 0.03)
const BRONZE := Color(0.72, 0.55, 0.32)
const BRONZE_DARK := Color(0.42, 0.3, 0.17)
const STEEL := Color(0.42, 0.36, 0.3)
const STEEL_BRIGHT := Color(0.78, 0.66, 0.48)
const GOLD := Color(0.96, 0.77, 0.4)
const GOLD_DIM := Color(0.7, 0.53, 0.3)
const PURPLE := Color(0.56, 0.32, 0.95)
const RED := Color(0.86, 0.22, 0.18)
const GREEN := Color(0.3, 0.78, 0.42)
const TEXT := Color(0.9, 0.84, 0.72)
const TEXT_MUTED := Color(0.64, 0.58, 0.49)
const CANDLE := Color(1.0, 0.68, 0.32)

const DARK_PLAQUE_REGION := Rect2(1150, 111, 164, 60)
const RED_PLAQUE_REGION := Rect2(984, 111, 166, 60)
const SLOT_REGION := Rect2(61, 725, 89, 74)


static func chamfer_box(bg: Color, border: Color, border_width := 2, cut := 10, shadow := Color(0, 0, 0, 0), shadow_size := 0, margin := Vector4(16, 9, 16, 9)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(cut)
	style.corner_detail = 1
	style.shadow_color = shadow
	style.shadow_size = shadow_size
	style.content_margin_left = margin.x
	style.content_margin_top = margin.y
	style.content_margin_right = margin.z
	style.content_margin_bottom = margin.w
	return style


static func atlas_box(region: Rect2, margins: Vector4, content: Vector4, modulate := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = OrnateFrame.gothic_texture(region)
	style.texture_margin_left = margins.x
	style.texture_margin_top = margins.y
	style.texture_margin_right = margins.z
	style.texture_margin_bottom = margins.w
	style.content_margin_left = content.x
	style.content_margin_top = content.y
	style.content_margin_right = content.z
	style.content_margin_bottom = content.w
	style.modulate_color = modulate
	return style


## Bronze-framed dark wood panel. The accent only warms/tints it slightly;
## identity color is carried by the OrnateFrame glow and gems on top.
static func accent_panel(accent: Color, emphasized := false, _cut := 14) -> StyleBoxTexture:
	var tint := Color.WHITE.lerp(Color(accent.r * 1.2 + 0.25, accent.g * 1.2 + 0.25, accent.b * 1.2 + 0.25), 0.22 if emphasized else 0.12)
	var style := OrnateFrame.bronze_box(true)
	style.modulate_color = tint
	style.content_margin_left = 22
	style.content_margin_top = 20
	style.content_margin_right = 22
	style.content_margin_bottom = 20
	return style


## Applies dark/red plaque styles with an accent tint to a Button.
static func apply_accent_button(button: Button, accent: Color, _cut := 10, margin := Vector4(16, 9, 16, 9)) -> void:
	var margins := Vector4(16, 15, 16, 15)
	var soft := Color.WHITE.lerp(Color(accent.r + 0.35, accent.g + 0.35, accent.b + 0.35), 0.3)
	var bright := Color.WHITE.lerp(Color(accent.r + 0.5, accent.g + 0.5, accent.b + 0.5), 0.55)
	button.add_theme_stylebox_override("normal", atlas_box(DARK_PLAQUE_REGION, margins, margin, soft))
	button.add_theme_stylebox_override("hover", atlas_box(DARK_PLAQUE_REGION, margins, margin, bright * Color(1.2, 1.1, 1.0)))
	button.add_theme_stylebox_override("hover_pressed", atlas_box(RED_PLAQUE_REGION, margins, margin, Color(0.9, 0.8, 0.75)))
	button.add_theme_stylebox_override("pressed", atlas_box(RED_PLAQUE_REGION, margins, margin, Color(0.9, 0.8, 0.75)))
	button.add_theme_stylebox_override("disabled", atlas_box(DARK_PLAQUE_REGION, margins, margin, Color(0.45, 0.42, 0.38, 0.75)))
	button.add_theme_color_override("font_hover_color", accent.lightened(0.6))


## Adds an OrnateFrame overlay as the last child of a Panel or PanelContainer.
## Use inset < 0 when the parent is a container that pads its children.
static func add_frame(parent: Control, accent: Color, glow := 0.0, inset := 4.0, gem := true) -> OrnateFrame:
	var frame := OrnateFrame.new()
	frame.name = "Ornament"
	frame.accent_color = accent
	frame.glow = glow
	frame.inset = inset
	frame.pulse = glow > 0.0
	frame.corner_gem = OrnateFrame.gem_for_color(accent) if gem else &""
	parent.add_child(frame)
	if not parent is Container:
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return frame
