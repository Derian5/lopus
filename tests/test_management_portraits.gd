extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")
const PORTRAIT_SHADER := preload("res://ui/management/management_portrait.gdshader")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(77031)
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	await process_frame
	await process_frame
	var portrait := screen.get_node("%SelectedPortrait") as TextureRect
	var material := portrait.material as ShaderMaterial
	_check(material != null and material.shader == PORTRAIT_SHADER, "The management portrait uses its own restrained treatment.")
	var frame := screen.get_node("%PortraitFrame") as PanelContainer
	var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
	_check(frame.size.x <= 190 and frame.size.y <= 210 and style != null and style.border_width_left == 1, "The inspector uses a compact portrait with a thin bronze frame.")
	_check(screen.get_node("%PortraitLayer").clip_contents, "Portrait art stays inside the inspector frame.")
	for definition in registry.definitions.values():
		if not definition is HeroDefinition or not definition.available_in_new_game:
			continue
		var hero := definition as HeroDefinition
		var original := hero.portrait
		run.heroes[0].definition_id = hero.id
		screen._select_unit("hero", 0)
		var crop := portrait.texture as AtlasTexture
		_check(crop != null and crop.atlas == original and Rect2(Vector2.ZERO, original.get_size()).encloses(crop.region), "%s uses an in-bounds crop of its original portrait." % hero.display_name)
		_check(crop.region.position.y == 0.0 and crop.region.size.y < original.get_height() * 0.55, "%s is framed as an upper-body portrait with its head retained." % hero.display_name)
		_check(hero.portrait == original and screen.get_node("%SelectedHeroCrest").visible, "Management preserves source artwork and shows a small identity crest.")
	var definition := registry.get_definition(run.heroes[0].definition_id) as HeroDefinition
	var source := definition.portrait
	definition.portrait = null
	screen._select_unit("hero", 0)
	_check(not portrait.visible and screen.get_node("%PortraitFallback").visible and screen.get_node("%SelectedHeroCrest").visible, "Missing Hero artwork retains the fallback and identity crest.")
	definition.portrait = source
	run.heroes[0].life_state = HeroState.DEAD
	screen._select_unit("hero", 0)
	_check(float(material.get_shader_parameter("dead_amount")) == 1.0 and screen.get_node("%ResurrectionButton").visible, "A fallen Hero receives a subdued portrait and keeps its resurrection action.")
	var other_run := DemoRunFactory.create_starting_run(77032)
	var other = MANAGEMENT_SCENE.instantiate()
	root.add_child(other)
	other.setup(other_run)
	other._select_unit("hero", 0)
	var other_material := (other.get_node("%SelectedPortrait") as TextureRect).material as ShaderMaterial
	_check(other_material != material and float(other_material.get_shader_parameter("dead_amount")) == 0.0, "Portrait treatment is instance-local rather than shared with another screen.")
	other.free()
	run.soldiers[0].veterancy_level = 3
	screen._select_unit("soldier", 0)
	var badge := screen.get_node("%PortraitLayer/VeterancyBadge") as VeterancyInsignia
	_check(not portrait.visible and screen.get_node("%PortraitFallback").visible and not screen.get_node("%SelectedHeroCrest").visible and badge.visible and badge.level == 3, "Soldier fallback portraits and veterancy remain readable without a stale Hero crest.")
	_check(float(material.get_shader_parameter("dead_amount")) == 0.0, "Changing selection clears the previous Hero's dead-state treatment.")
	run.heroes[0].life_state = HeroState.ALIVE
	screen._select_unit("hero", 0)
	_check(portrait.visible and not badge.visible and not screen.get_node("%PortraitFallback").visible, "Returning to a Hero restores the portrait and clears Soldier overlays.")
	screen.free()
	if DisplayServer.get_name() != "headless":
		await _test_rendered_treatment()
	if failures == 0:
		print("Management portrait tests passed: all Hero crops, quiet frame, fallbacks, death and instance-local materials.")
		quit()
	else:
		quit(1)


func _test_rendered_treatment() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.06, 0.04, 0.03)
	background.size = Vector2(64, 64)
	viewport.add_child(background)
	var image := Image.create_empty(128, 256, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var crop := AtlasTexture.new()
	crop.atlas = ImageTexture.create_from_image(image)
	crop.region = Rect2(16, 0, 96, 112)
	var portrait := TextureRect.new()
	portrait.size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = crop
	var material := ShaderMaterial.new()
	material.shader = PORTRAIT_SHADER
	material.set_shader_parameter("portrait_size", Vector2(64, 64))
	portrait.material = material
	viewport.add_child(portrait)
	await _draw_frame()
	var rendered := viewport.get_texture().get_image()
	var center := rendered.get_pixel(32, 32)
	_check(center.r > 0.3 and center.r < 0.95 and center.g > 0.02, "Rendered portrait colors are gently dimmed and desaturated.")
	for point in [Vector2i(0, 32), Vector2i(32, 63)]:
		var pixel := rendered.get_pixelv(point)
		_check(_difference(pixel, background.color) < 0.03, "Portrait edges and lower crop blend into the backing even with atlas UVs.")
	material.set_shader_parameter("dead_amount", 1.0)
	await _draw_frame()
	var dead := viewport.get_texture().get_image().get_pixel(32, 32)
	_check(dead.r < center.r and dead.r - dead.g < (center.r - center.g) * 0.5, "The fallen-Hero treatment visibly reduces brightness and saturation.")
	viewport.free()


func _draw_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _difference(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
