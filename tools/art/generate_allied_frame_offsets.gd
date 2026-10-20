extends SceneTree

## Regenerate with Godot --headless --path . --script res://tools/art/generate_allied_frame_offsets.gd
## These transparent frame sequences use alpha, not chroma-key colour, to locate
## their bodies. Green clothing and spell effects remain part of the artwork.
const OUTPUT := "res://combat/allied_frame_offsets.json"
const UNITS := ["archer", "priest", "summoner", "warrior", "shieldbearer", "creature"]
const ANIMATIONS := {"move": "walk", "attack": "attack", "skill": "skill", "death": "death"}
const SAMPLE_STEP := 2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result := {}
	var total := 0
	for unit in UNITS:
		var directory := "res://graphics/units/player/units/%s" % unit
		var animations := {}
		for animation in ANIMATIONS:
			var path := "%s/%s" % [directory, ANIMATIONS[animation]]
			if not DirAccess.dir_exists_absolute(path):
				continue
			var files := Array(DirAccess.get_files_at(path)).filter(func(p: String) -> bool: return p.ends_with(".png"))
			files.sort()
			if files.is_empty():
				continue
			var offsets := []
			var anchors := []
			var death_anchor := Vector2.ZERO
			for index in files.size():
				var texture := load(path + "/" + files[index]) as Texture2D
				if texture == null:
					push_error("Missing animation texture: %s/%s" % [path, files[index]])
					quit(1)
					return
				var image := texture.get_image()
				var anchor := _foot_anchor(image)
				# Falling is deliberate motion: keep the original death pose's origin.
				if animation == "death":
					if index == 0:
						death_anchor = anchor
					anchor = death_anchor
				var offset := Vector2(image.get_size()) * 0.5 - anchor
				offsets.append([offset.x, offset.y])
				anchors.append([anchor.x, anchor.y])
				total += 1
			animations[animation] = offsets
			animations[animation + "_anchor"] = anchors
		result[directory] = animations
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % OUTPUT)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("Generated allied body anchors: %d units, %d animation frames." % [result.size(), total])
	quit()


func _foot_anchor(image: Image) -> Vector2:
	var bounds := image.get_used_rect()
	var bottom := bounds.position.y
	for y in range(bounds.end.y - 1, bounds.position.y - 1, -1):
		var opaque_pixels := 0
		for x in range(bounds.position.x, bounds.end.x, SAMPLE_STEP):
			if image.get_pixel(x, y).a >= 0.5:
				opaque_pixels += 1
		if opaque_pixels >= 3:
			bottom = y
			break
	# The lower body is more stable than a weapon-weighted whole-sprite centroid.
	var xs: Array[int] = []
	var band_top := bounds.position.y + roundi(bounds.size.y * 0.55)
	var band_bottom := bounds.position.y + roundi(bounds.size.y * 0.85)
	for y in range(band_top, band_bottom + 1, SAMPLE_STEP):
		for x in range(bounds.position.x, bounds.end.x, SAMPLE_STEP):
			if image.get_pixel(x, y).a >= 0.5:
				xs.append(x)
	xs.sort()
	var center_x: float = float(xs[floori(xs.size() * 0.5)]) if not xs.is_empty() else float(bounds.get_center().x)
	return Vector2(center_x, bottom)
