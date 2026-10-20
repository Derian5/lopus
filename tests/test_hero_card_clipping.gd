extends SceneTree


const CARD_SCENE := preload("res://ui/hero_selection/hero_selection_card.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1470, 780)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.04, 0.07, 0.1)
	background.size = Vector2(viewport.size)
	viewport.add_child(background)
	var source_sizes := [Vector2i(800, 400), Vector2i(400, 800), Vector2i(512, 512)]
	var cards: Array[HeroSelectionCard] = []
	for index in source_sizes.size():
		var image := Image.create_empty(source_sizes[index].x, source_sizes[index].y, false, Image.FORMAT_RGB8)
		image.fill([Color.MAGENTA, Color.CYAN, Color.YELLOW][index])
		var hero := HeroDefinition.new()
		hero.id = &"hero.control_savant"
		hero.display_name = "Pride"
		hero.base_stats = StatBlock.new()
		hero.portrait = ImageTexture.create_from_image(image)
		var card: HeroSelectionCard = CARD_SCENE.instantiate()
		viewport.add_child(card)
		card.position = Vector2(45 + index * 475, 40)
		card.setup(hero, -1, true)
		card.button_motion.set_process(false)
		cards.append(card)
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		for factor in [1.0, 1.045, 0.92]:
			for card in cards:
				card.get_node("%VisualRoot").scale = Vector2.ONE * factor
				card.get_node("VisualRoot/ArtClip").show()
			await _draw_frame()
			var visible_art := viewport.get_texture().get_image()
			for card in cards:
				card.get_node("VisualRoot/ArtClip").hide()
			await _draw_frame()
			var hidden_art := viewport.get_texture().get_image()
			for card in cards:
				var transform: Transform2D = card.get_node("%VisualRoot").get_global_transform()
				for local in [Vector2(-15, 380), Vector2(445, 380), Vector2(13, 13), Vector2(417, 13), Vector2(13, 200), Vector2(417, 200), Vector2(200, 470)]:
					var point := Vector2i(transform * local)
					_check(_difference(visible_art.get_pixelv(point), hidden_art.get_pixelv(point)) < 0.02, "Portrait art stays inside the inner frame at scale %.3f / local %s." % [factor, local])
				var inside := Vector2i(transform * Vector2(210, 220))
				_check(_difference(visible_art.get_pixelv(inside), hidden_art.get_pixelv(inside)) > 0.2, "Clipping preserves the visible portrait rather than hiding the image.")
			for card in cards:
				card.get_node("VisualRoot/Info").hide()
			await _draw_frame()
			var hidden_info := viewport.get_texture().get_image()
			for card in cards:
				var transform: Transform2D = card.get_node("%VisualRoot").get_global_transform()
				for local in [Vector2(13, 470), Vector2(417, 470)]:
					var point := Vector2i(transform * local)
					_check(_difference(hidden_art.get_pixelv(point), hidden_info.get_pixelv(point)) < 0.02, "The information background also stays inside the visible bronze frame.")
				card.get_node("VisualRoot/Info").show()
	for card in cards:
		_check(not card.get_node("%OrnamentFrame").clip_contents, "Decorative frames and crests remain free to extend beyond the artwork.")
	viewport.free()
	if failures == 0:
		print("Hero card clipping tests passed%s." % (" (wide, tall and square portraits; rendered pixels at three scales)" if rendered else " (scene checks)"))
		quit()
	else:
		quit(1)


func _draw_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _difference(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
