@tool
class_name OrnateFrame
extends Control


## Decorative overlay for gothic bronze panels: warm (or identity colored) glow, bronze crest on the top edge, hanging pendant below, optional
## bronze border and corner gems. Place it as the last child of a panel.

const UI_ATLAS := preload("res://graphics/ui/atlas_ui.png")
const GOTHIC_ATLAS := preload("res://graphics/ui/ui_atlas_v2_dop.png")
## Lit gems from atlas_ui.png, plus bronze/gold/ruby gems from the gothic atlas.
const GEM_REGIONS := {
	&"gold": Rect2(1285, 661, 37, 36),
	&"purple": Rect2(1582, 794, 29, 30),
	&"red": Rect2(1404, 661, 35, 36),
	&"green": Rect2(1461, 662, 36, 35),
	&"blue": Rect2(1516, 662, 35, 35),
	&"orange": Rect2(1570, 662, 34, 35),
	&"pink": Rect2(1623, 664, 31, 32),
	&"steel": Rect2(1582, 879, 29, 29),
}
const GOTHIC_GEM_REGIONS := {
	&"bronze": Rect2(1051, 638, 47, 49),
	&"amber": Rect2(1103, 638, 49, 52),
	&"ruby": Rect2(1156, 638, 51, 52),
}
## Clean single-piece ornaments extracted from the gothic atlas.
const CREST_TEXTURE := preload("res://graphics/ui/gothic_crest.png")
const PENDANT_TEXTURE := preload("res://graphics/ui/gothic_pendant.png")
const BORDER_REGION := Rect2(982, 247, 374, 133)
## Same bronze frame with a transparent interior (generated from BORDER_REGION).
const BORDER_ONLY := preload("res://graphics/ui/gothic_frame_border.png")
const CANDLE_COLOR := Color(1.0, 0.68, 0.32)

@export var accent_color := Color(0.72, 0.55, 0.32):
	set(value):
		accent_color = value
		queue_redraw()
## 0 = no glow, 1 = full glow like a selected Hero card.
@export_range(0.0, 1.0, 0.05) var glow := 0.0:
	set(value):
		glow = value
		queue_redraw()
@export var pulse := false:
	set(value):
		pulse = value
		_update_processing()
@export var cut := 18.0:
	set(value):
		cut = value
		queue_redraw()
@export var inset := 4.0:
	set(value):
		inset = value
		queue_redraw()
@export var crest_top := true:
	set(value):
		crest_top = value
		queue_redraw()
@export var crest_bottom := true:
	set(value):
		crest_bottom = value
		queue_redraw()
@export var side_notches := false:
	set(value):
		side_notches = value
		queue_redraw()
## Draws the bronze 9-patch border itself (for elements without a bronze panel).
@export var draw_border := false:
	set(value):
		draw_border = value
		queue_redraw()
## Empty = no corner gems. Otherwise a key of GEM_REGIONS or GOTHIC_GEM_REGIONS.
@export var corner_gem: StringName = &"":
	set(value):
		corner_gem = value
		_gem_texture = null
		queue_redraw()
@export var corner_gem_size := 24.0:
	set(value):
		corner_gem_size = value
		queue_redraw()
## Width of the top crest ornament in pixels.
@export var crest_width := 96.0:
	set(value):
		crest_width = value
		queue_redraw()

var flash := 0.0:
	set(value):
		flash = value
		queue_redraw()

var _time := 0.0
var _gem_texture: Texture2D
var _border_box: StyleBoxTexture
var _flash_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_parent() is Control and size == Vector2.ZERO:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_processing()


func play_flash(duration := 0.5) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	flash = 1.0
	_flash_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(self, "flash", 0.0, duration)


static func gem_texture(key: StringName) -> AtlasTexture:
	var texture := AtlasTexture.new()
	if GEM_REGIONS.has(key):
		texture.atlas = UI_ATLAS
		texture.region = GEM_REGIONS[key]
	elif GOTHIC_GEM_REGIONS.has(key):
		texture.atlas = GOTHIC_ATLAS
		texture.region = GOTHIC_GEM_REGIONS[key]
	else:
		return null
	return texture


static func gothic_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = GOTHIC_ATLAS
	texture.region = region
	texture.filter_clip = true
	return texture


## Bronze 9-patch frame from the gothic atlas.
static func bronze_box(draw_center := true) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = gothic_texture(BORDER_REGION) if draw_center else BORDER_ONLY
	box.texture_margin_left = 44.0
	box.texture_margin_right = 44.0
	box.texture_margin_top = 38.0
	box.texture_margin_bottom = 38.0
	box.draw_center = draw_center
	return box


## Closest gem key for an arbitrary accent color.
static func gem_for_color(color: Color) -> StringName:
	if color.s < 0.22:
		return &"bronze"
	var hue := color.h * 360.0
	if hue < 18.0 or hue >= 345.0:
		return &"red"
	if hue < 38.0:
		return &"orange"
	if hue < 70.0:
		return &"gold"
	if hue < 165.0:
		return &"green"
	if hue < 250.0:
		return &"blue"
	if hue < 300.0:
		return &"purple"
	return &"pink"


func _update_processing() -> void:
	set_process(pulse and glow > 0.0 and not Engine.is_editor_hint())
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _glow_color() -> Color:
	# Neutral bronze accents glow like candle light; identity colors keep their hue.
	return CANDLE_COLOR if accent_color.h > 0.05 and accent_color.h < 0.15 and accent_color.s < 0.8 else accent_color


func _draw() -> void:
	var rect := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
	if rect.size.x < 60.0 or rect.size.y < 60.0:
		return
	var wave := 0.5 + 0.5 * sin(_time * 2.2) if pulse else 0.65
	var glow_color := _glow_color()

	if glow > 0.0:
		for step in 6:
			var halo := glow_color
			halo.a = ((0.2 - step * 0.032) * (0.6 + 0.4 * wave) + flash * 0.14) * glow
			draw_polyline(chamfer(rect.grow(1.0 + step * 4.0), cut + step * 3.0), halo, 6.0, true)
		for step in 4:
			var tint := glow_color
			tint.a = ((0.07 - step * 0.015) * (0.75 + 0.25 * wave) + flash * 0.04) * glow
			draw_polyline(chamfer(rect.grow(-10.0 - step * 7.0), maxf(cut - 4.0, 4.0)), tint, 8.0, true)

	if draw_border:
		if _border_box == null:
			_border_box = bronze_box(false)
		var border_tint := Color.WHITE.lerp(Color(1.25, 1.1, 0.9), glow * (0.4 + 0.3 * wave))
		_border_box.modulate_color = border_tint
		draw_style_box(_border_box, rect)

	var ornament_tint := Color.WHITE.lerp(Color(1.3, 1.15, 0.9), glow * 0.5 * wave + flash * 0.5)
	if crest_top:
		var crest_size := Vector2(crest_width, crest_width * CREST_TEXTURE.get_height() / CREST_TEXTURE.get_width())
		draw_texture_rect(CREST_TEXTURE, Rect2(Vector2(size.x * 0.5 - crest_size.x * 0.5, rect.position.y - crest_size.y * 0.5), crest_size), false, ornament_tint)
	if crest_bottom:
		var pendant_size := Vector2(crest_width * 0.36, crest_width * 0.36 * PENDANT_TEXTURE.get_height() / PENDANT_TEXTURE.get_width())
		draw_texture_rect(PENDANT_TEXTURE, Rect2(Vector2(size.x * 0.5 - pendant_size.x * 0.5, rect.end.y - pendant_size.y * 0.32), pendant_size), false, ornament_tint)
	if side_notches:
		var gem := gem_texture(&"amber")
		var side_size := corner_gem_size * 0.9
		for x in [rect.position.x, rect.end.x]:
			draw_texture_rect(gem, Rect2(Vector2(x - side_size * 0.5, size.y * 0.5 - side_size * 0.5), Vector2.ONE * side_size), false, ornament_tint)

	if not String(corner_gem).is_empty():
		if _gem_texture == null:
			_gem_texture = gem_texture(corner_gem)
		if _gem_texture != null:
			var tint := Color.WHITE.lerp(Color(1.35, 1.35, 1.35), wave * 0.35 * glow + flash * 0.6)
			var offset := 13.0
			for corner in [
				rect.position + Vector2(offset, offset),
				Vector2(rect.end.x - offset, rect.position.y + offset),
				rect.end - Vector2(offset, offset),
				Vector2(rect.position.x + offset, rect.end.y - offset),
			]:
				draw_texture_rect(_gem_texture, Rect2(corner - Vector2.ONE * corner_gem_size * 0.5, Vector2.ONE * corner_gem_size), false, tint)

	if flash > 0.0:
		var flash_color := glow_color.lightened(0.5)
		flash_color.a = flash * 0.16
		draw_colored_polygon(chamfer(rect.grow(-6.0), cut, false), flash_color)


static func chamfer(rect: Rect2, amount: float, closed := true) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var points := PackedVector2Array([
		Vector2(p.x + amount, p.y), Vector2(e.x - amount, p.y), Vector2(e.x, p.y + amount),
		Vector2(e.x, e.y - amount), Vector2(e.x - amount, e.y), Vector2(p.x + amount, e.y),
		Vector2(p.x, e.y - amount), Vector2(p.x, p.y + amount),
	])
	if closed:
		points.append(points[0])
	return points
