extends SceneTree

## Measure displayed artwork, including chroma-key removal and canvas cropping.
## Keep one scale per animation, never resize the body on every animation frame.
func _initialize() -> void:
	var builder := Combatant.new()
	var result := {}
	for id in Combatant.UNIT_ANIMATION_CONFIGS:
		var config: Dictionary = Combatant.UNIT_ANIMATION_CONFIGS[id]
		var frames := builder._build_unit_sprite_frames(config)
		var heights := {}
		for animation in frames.get_animation_names():
			var samples: Array[float] = []
			var count := 1 if animation == &"death" else frames.get_frame_count(animation)
			for frame in count:
				var image := frames.get_frame_texture(animation, frame).get_image().duplicate() as Image
				var top := image.get_height()
				var bottom := -1
				for y in image.get_height():
					var pixels := 0
					for x in image.get_width():
						var color := image.get_pixel(x, y)
						if color.a >= 0.5 and (not config.get("chroma_key", false) or color.g - maxf(color.r, color.b) < 0.08):
							pixels += 1
							if pixels >= 2:
								break
					if pixels >= 2:
						top = mini(top, y)
						bottom = maxi(bottom, y)
				samples.append(float(maxi(1, bottom - top + 1)))
			samples.sort()
			heights[String(animation)] = samples[samples.size() / 2]
		result[String(config.frame_directory)] = heights
		print("%s: %s" % [id, heights])
	builder.free()
	var output := FileAccess.open("res://combat/unit_visible_sizes.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	quit()
