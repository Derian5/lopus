extends SceneTree

const MEASURE := preload("res://tools/art/enemy_frame_measurement.gd")
const OUTPUT := "res://combat/enemy_frame_offsets.json"

func _initialize() -> void:
	var result := {}
	var total := 0
	for id in Combatant.UNIT_ANIMATION_CONFIGS:
		var config: Dictionary = Combatant.UNIT_ANIMATION_CONFIGS[id]
		var directory: String = config.get("frame_directory", "")
		if not directory.begins_with("res://graphics/units/enemies/"):
			continue
		var frames := Combatant.new()
		var animations := frames._build_unit_sprite_frames(config)
		frames.free()
		var standing: Dictionary = Combatant.UNIT_VISIBLE_SIZES.data.get(directory, {})
		var reference_height := float(standing.get("move", 280.0))
		var offsets_by_animation := {}
		for animation in animations.get_animation_names():
			var raw: Array[Vector2] = []
			var textures: Array[Texture2D] = []
			for frame in animations.get_frame_count(animation):
				var texture := animations.get_frame_texture(animation, frame)
				textures.append(texture)
				raw.append(MEASURE.body_anchor(texture.get_image(), reference_height))
			var offsets := []
			var anchors := []
			var largest_step := 0.0
			for frame in raw.size():
				var anchor := raw[frame]
				if animation == &"death":
					# Fix the original death origin; allow the body to fall and stay down.
					anchor = raw[0]
				elif frame > 0 and frame < raw.size() - 1:
					# Suppress one-frame extraction jitter without moving either endpoint.
					anchor = (raw[frame - 1] + raw[frame] * 2.0 + raw[frame + 1]) * 0.25
				var offset := textures[frame].get_size() * 0.5 - anchor
				offsets.append([offset.x, offset.y])
				anchors.append([anchor.x, anchor.y])
				if frame > 0:
					largest_step = maxf(largest_step, anchor.distance_to(Vector2(anchors[frame - 1][0], anchors[frame - 1][1])))
				total += 1
			offsets_by_animation[String(animation)] = offsets
			offsets_by_animation[String(animation) + "_anchor"] = anchors
			print("%s / %s: %d frames, largest source anchor step %.1f px" % [id, animation, raw.size(), largest_step])
		result[directory] = offsets_by_animation
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("Generated enemy anchors: %d enemies, %d frames." % [result.size(), total])
	quit()
