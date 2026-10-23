extends SubViewport

## Render into an isolated, undisplayed viewport before the menu becomes active.
## This flushes texture uploads, material/light variants, glyphs and video startup.
func prepare(textures: Array[Texture2D], materials: Array[Material], fonts: Array[Font], video: VideoStream, progress: Callable) -> void:
	size = Vector2i(256, 256)
	world_2d = World2D.new()
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var probes := Node2D.new()
	add_child(probes)
	if not textures.is_empty():
		for index in materials.size():
			var sprite := Sprite2D.new()
			sprite.texture = textures[0]
			sprite.material = materials[index]
			sprite.scale = Vector2.ONE * 22.0 / maxf(sprite.texture.get_width(), sprite.texture.get_height())
			sprite.position = Vector2(16 + (index % 12) * 20, 164 + (index / 12) * 24)
			probes.add_child(sprite)
	var light := preload("res://combat/vfx/combat_vfx.gd").make_light(Color(1, 0.8, 0.6), 1.0, 2.0)
	light.position = Vector2(128, 128)
	probes.add_child(light)
	# Small combat/UI text plus the larger menu and Hero-selection headings.
	var font_sizes := range(10, 41)
	font_sizes.append_array([50, 63, 64, 88])
	for font in fonts:
		for font_size in font_sizes:
			var label := Label.new()
			label.text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789%+-.,:!?/()"
			label.add_theme_font_override("font", font)
			label.add_theme_font_size_override("font_size", font_size)
			label.size = Vector2(256, 200)
			label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			probes.add_child(label)
	if video != null:
		var player := VideoStreamPlayer.new()
		player.stream = video
		player.expand = true
		player.size = Vector2(48, 32)
		player.position = Vector2(208, 220)
		player.volume_db = -80
		probes.add_child(player)
		player.play()
	var count := maxi(1, ceili(textures.size() / 64.0))
	for batch_index in count:
		var batch := Node2D.new()
		add_child(batch)
		for index in range(batch_index * 64, mini((batch_index + 1) * 64, textures.size())):
			var sprite := Sprite2D.new()
			sprite.texture = textures[index]
			var local_index := index % 64
			sprite.position = Vector2(8 + (local_index % 16) * 16, 8 + (local_index / 16) * 16)
			sprite.scale = Vector2.ONE * 12.0 / maxf(sprite.texture.get_width(), sprite.texture.get_height())
			batch.add_child(sprite)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		batch.free()
		progress.call(float(batch_index + 1) / count)
	# Both the unlit and point-lit CanvasItem paths must have been submitted.
	light.enabled = false
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
