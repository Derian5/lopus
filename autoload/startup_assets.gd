extends Node

## Explicit startup preparation. Kept as an autoload so resources remain strongly
## referenced after the loading scene goes away (ResourceLoader's cache is weak).
signal progress_changed(fraction: float, message: String)
signal preparation_finished(success: bool)

const ACTOR := preload("res://combat/combatant.gd")
const VFX := preload("res://combat/vfx/combat_vfx.gd")
const GPU_WARMUP := preload("res://ui/loading/render_warmup.gd")
const MAIN_SCENE := "res://main.tscn"
const SCENERY := ["res://graphics/battleground.png", "res://graphics/battleground/battleground_back.ogv", "res://graphics/battleground/battleground_front.png"]
const MAX_REQUESTS := 8

var prepared := false
var preparing := false
var progress := 0.0
var error_message := ""
var main_scene: PackedScene
var loaded_resources := {}
var retained_resources: Array[Resource] = []
var textures: Array[Texture2D] = []
var fonts: Array[Font] = []
var materials: Array[Material] = []
var report := {}
var _visited := {}
var _texture_ids := {}
var _font_ids := {}
var _material_ids := {}


func _progress(value: float, message: String) -> void:
	progress = maxf(progress, clampf(value, 0.0, 1.0))
	progress_changed.emit(progress, message)


func _fail(message: String) -> bool:
	error_message = message
	preparing = false
	preparation_finished.emit(false)
	return false


func prepare() -> bool:
	if prepared:
		return true
	if preparing:
		await preparation_finished
		return prepared
	preparing = true
	error_message = ""
	var started := Time.get_ticks_usec()
	_progress(0.0, "Loading screens and interfaces")
	# Load the script-heavy scene graph on the main thread. Godot 4.7.2 leaks
	# native RefCounteds when these scripts are first loaded by a worker thread.
	# The loading screen is already visible; bulk textures still load in workers.
	main_scene = ResourceLoader.load(MAIN_SCENE) as PackedScene
	if main_scene == null:
		return _fail("The main scene could not be loaded.")
	loaded_resources[MAIN_SCENE] = main_scene
	_retain_graph(main_scene)
	_retain_graph(get_node("/root/ContentRegistry").definitions)
	_retain_graph(ThemeDB.get_project_theme())
	_progress(0.08, "Loading screens and interfaces")
	var paths := _media_paths()
	if not await _load_paths(paths, 0.08, 0.50, "Loading sprites and effects"):
		return _fail(error_message)
	var builder := ACTOR.new()
	var ids: Array[String] = []
	for id in ACTOR.UNIT_ANIMATION_CONFIGS:
		ids.append(String(id))
	ids.sort()
	var frame_count := 0
	var yield_started := Time.get_ticks_usec()
	for index in ids.size():
		var id := StringName(ids[index])
		var config: Dictionary = ACTOR.UNIT_ANIMATION_CONFIGS[id]
		if not ACTOR.unit_sprite_frames.has(id):
			ACTOR.unit_sprite_frames[id] = builder._build_unit_sprite_frames(config)
		var frames := ACTOR.unit_sprite_frames[id] as SpriteFrames
		ACTOR._authored_offsets(String(config.get("frame_directory", "")))
		var chroma := bool(config.get("chroma_key", false))
		for animation in frames.get_animation_names():
			for frame in frames.get_frame_count(animation):
				var texture := frames.get_frame_texture(animation, frame)
				_retain_graph(texture)
				# Legacy anchors are still used by facing/projectile fallbacks,
				# including every Hero attack frame when used by an illusion.
				if chroma:
					builder._chroma_frame_offset(texture)
					var anchor_key: Variant = texture.resource_path if not texture.resource_path.is_empty() else texture.get_instance_id()
					if not ACTOR.chroma_frame_offsets.has(anchor_key):
						builder.free()
						return _fail("Could not prepare sprite image: %s / %s / %d" % [id, animation, frame])
				frame_count += 1
				if Time.get_ticks_usec() - yield_started >= 6000:
					await get_tree().process_frame
					yield_started = Time.get_ticks_usec()
		var standing := frames.get_frame_texture(&"move", 0)
		var key := ACTOR.feet_cache_key(standing, chroma)
		if not ACTOR.feet_cache.has(key):
			ACTOR.feet_cache[key] = ACTOR._scan_feet(standing, chroma)
		_progress(0.58 + 0.23 * float(index + 1) / ids.size(), "Preparing character animations (%d/%d)" % [index + 1, ids.size()])
		await get_tree().process_frame
	builder.free()
	var effect_ids: Array[String] = []
	for id in VFX.ATLASES:
		effect_ids.append(String(id))
	effect_ids.sort()
	for index in effect_ids.size():
		var id := StringName(effect_ids[index])
		var frames := VFX.get_frames(id)
		if frames == null:
			return _fail("Could not prepare effect: %s" % id)
		_retain_graph(frames)
		_retain_graph(VFX.material_for(id))
		_progress(0.81 + 0.05 * float(index + 1) / effect_ids.size(), "Preparing battle effects")
		await get_tree().process_frame
	_retain_graph(VFX.get_shadow_texture())
	_retain_graph(VFX.get_light_texture())
	_retain_graph(VFX.get_vignette_texture())
	for shader in [ACTOR.CHROMA_KEY_SHADER, ACTOR.ALPHA_SPRITE_SHADER]:
		var material := ShaderMaterial.new()
		material.shader = shader
		_retain_graph(material)
	if DisplayServer.get_name() != "headless":
		_progress(0.86, "Preparing graphics")
		var warmer := GPU_WARMUP.new()
		add_child(warmer)
		await warmer.prepare(textures, materials, fonts, loaded_resources.get(SCENERY[1]), _graphics_progress)
		warmer.free()
	report = {"resources": loaded_resources.size(), "textures": textures.size(), "unit_animations": ids.size(),
		"frames": frame_count, "effects": effect_ids.size(), "feet": ACTOR.feet_cache.size(),
		"legacy_anchors": ACTOR.chroma_frame_offsets.size(), "gpu_prepared": DisplayServer.get_name() != "headless",
		"seconds": (Time.get_ticks_usec() - started) / 1000000.0}
	prepared = true
	preparing = false
	_progress(1.0, "Ready")
	preparation_finished.emit(true)
	return true


func _graphics_progress(fraction: float) -> void:
	_progress(0.86 + fraction * 0.14, "Preparing graphics")


func _media_paths() -> Array[String]:
	var paths := {}
	for config in ACTOR.UNIT_ANIMATION_CONFIGS.values():
		if config.has("frame_directory"):
			for animation in ACTOR.animation_names_for(config):
				for frame in int(config["%s_frames" % animation]):
					paths[ACTOR.animation_frame_path(config, animation, frame)] = true
	for id in VFX.ATLASES:
		paths[VFX.FOLDER + String(VFX.ATLASES[id].get("texture", id)) + ".png"] = true
	for path in SCENERY:
		paths[path] = true
	_collect_ui_paths("res://graphics/ui", paths)
	var result: Array[String] = []
	for path in paths:
		result.append(path)
	result.sort()
	return result


func _collect_ui_paths(directory: String, paths: Dictionary) -> void:
	for entry in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			_collect_ui_paths(directory.path_join(entry.trim_suffix("/")), paths)
		elif entry.get_extension().to_lower() in ["png", "svg", "webp", "tres"]:
			paths[directory.path_join(entry)] = true


func _load_paths(paths: Array[String], start: float, weight: float, message: String) -> bool:
	# The dummy/headless texture storage is not safe for parallel RID creation.
	# Keep CLI tools/tests on a time-sliced main-thread path; the live renderer
	# can use Godot's threaded resource loader.
	if DisplayServer.get_name() == "headless":
		var yielded := Time.get_ticks_usec()
		for index in paths.size():
			var path := paths[index]
			if not ResourceLoader.exists(path):
				error_message = "Missing resource: %s" % path
				return false
			var resource := ResourceLoader.load(path)
			if resource == null:
				error_message = "Could not read resource: %s" % path
				return false
			loaded_resources[path] = resource
			_retain_graph(resource)
			_progress(start + weight * float(index + 1) / maxi(paths.size(), 1), "%s (%d/%d)" % [message, index + 1, paths.size()])
			if Time.get_ticks_usec() - yielded >= 6000:
				await get_tree().process_frame
				yielded = Time.get_ticks_usec()
		return true
	var pending: Array[String] = []
	var next := 0
	var done := 0
	while done < paths.size():
		while next < paths.size() and pending.size() < MAX_REQUESTS:
			var path := paths[next]
			next += 1
			var cached := ResourceLoader.get_cached_ref(path)
			if cached != null:
				loaded_resources[path] = cached
				_retain_graph(cached)
				done += 1
				continue
			if not ResourceLoader.exists(path):
				error_message = "Missing resource: %s" % path
				return false
			var error := ResourceLoader.load_threaded_request(path)
			if error != OK:
				error_message = "Could not load resource: %s (error %d)" % [path, error]
				return false
			pending.append(path)
		for index in range(pending.size() - 1, -1, -1):
			var path := pending[index]
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource == null:
					error_message = "Could not read resource: %s" % path
					return false
				loaded_resources[path] = resource
				_retain_graph(resource)
				pending.remove_at(index)
				done += 1
			elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
				error_message = "Resource loading failed: %s" % path
				return false
		_progress(start + weight * float(done) / maxi(paths.size(), 1), "%s (%d/%d)" % [message, done, paths.size()])
		await get_tree().process_frame
	return true


## PackedScene._bundled and script constants hold textures of all the screens.
## Follow storage resources/collections only; no scene instantiation/gameplay.
func _retain_graph(value: Variant) -> void:
	if value is Resource:
		var resource := value as Resource
		var id := resource.get_instance_id()
		if _visited.has(id):
			return
		_visited[id] = true
		retained_resources.append(resource)
		if resource is Texture2D and not resource is AtlasTexture and not _texture_ids.has(id):
			_texture_ids[id] = true
			textures.append(resource)
		if resource is Font and not _font_ids.has(id):
			_font_ids[id] = true
			fonts.append(resource)
		if resource is Material and not _material_ids.has(id):
			_material_ids[id] = true
			materials.append(resource)
		if resource is GDScript:
			_retain_graph(resource.get_script_constant_map())
		for property in resource.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				_retain_graph(resource.get(property.name))
	elif value is Array:
		for entry in value:
			_retain_graph(entry)
	elif value is Dictionary:
		for entry in value.values():
			_retain_graph(entry)
