class_name ChamferClip
extends Control


## Clips its children to a chamfered rectangle that sits just inside the hero card's
## bronze frame, so portrait and backdrop art never poke past the cut corners.

## The bronze texture has transparent padding outside its visible inner edge.
@export var inset := 25.0
@export var cut := 22.0
## Bottom edge of the clipped art area (the info panel covers everything below).
@export var clip_bottom := 414.0


func _ready() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect := Rect2(Vector2(inset, inset), Vector2(size.x - inset * 2.0, minf(clip_bottom, size.y) - inset))
	var p := rect.position
	var e := rect.end
	draw_colored_polygon(PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut),
		Vector2(e.x, e.y), Vector2(p.x, e.y), Vector2(p.x, p.y + cut),
	]), Color.WHITE)
