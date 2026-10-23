extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const VFX := preload("res://combat/vfx/combat_vfx.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var assets = root.get_node("StartupAssets")
	var observed: Array[float] = []
	assets.progress_changed.connect(func(value: float, _message: String) -> void: observed.append(value))
	var success: bool = await assets.prepare()
	_check(success and assets.prepared and not assets.preparing, "Startup preparation completes before the game is opened.")
	if not success:
		push_error(assets.error_message)
		quit(1)
		return
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://ui/loading/startup.tscn", "Normal application launch uses the loading scene.")
	_check(not observed.is_empty() and is_equal_approx(observed[-1], 1.0), "The loading screen reaches real completion.")
	for index in range(1, observed.size()):
		_check(observed[index] >= observed[index - 1], "Startup progress never runs backwards.")
	_check(Combatant.unit_sprite_frames.size() == Combatant.UNIT_ANIMATION_CONFIGS.size(), "Every unit's SpriteFrames is built at startup.")
	_check(VFX.frame_cache.size() == VFX.ATLASES.size(), "All battle effect atlases are sliced at startup.")
	for id in Combatant.UNIT_ANIMATION_CONFIGS:
		var config: Dictionary = Combatant.UNIT_ANIMATION_CONFIGS[id]
		var frames := Combatant.unit_sprite_frames[id] as SpriteFrames
		var standing := frames.get_frame_texture(&"move", 0)
		var chroma := bool(config.get("chroma_key", false))
		_check(Combatant.feet_cache.has(Combatant.feet_cache_key(standing, chroma)), "Every standing frame has a prepared foot anchor.")
		if chroma:
			for animation in frames.get_animation_names():
				for frame in frames.get_frame_count(animation):
					var texture := frames.get_frame_texture(animation, frame)
					var key: Variant = texture.resource_path if not texture.resource_path.is_empty() else texture.get_instance_id()
					_check(Combatant.chroma_frame_offsets.has(key), "Every legacy/chroma frame has a prepared pixel-scan result.")
	_check(assets.loaded_resources.has(CombatSession.BACKDROP_VIDEO_PATH) and assets.loaded_resources.has(CombatSession.FOREGROUND_PATH), "Battlefield scenery is retained before first combat.")
	var frames_before := Combatant.unit_sprite_frames.duplicate()
	var feet_before := Combatant.feet_cache.size()
	var anchors_before := Combatant.chroma_frame_offsets.size()
	var effects_before := VFX.frame_cache.duplicate()
	var army: Array[CombatUnitSnapshot] = []
	for id in Combatant.UNIT_ANIMATION_CONFIGS:
		var snapshot := CombatUnitSnapshot.new()
		snapshot.runtime_id = String(id)
		snapshot.definition_id = id
		snapshot.stats.max_hp = 1000.0
		if String(id).begins_with("job."):
			snapshot.job_id = id
			snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER
		elif String(id).begins_with("hero."):
			snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO
		else:
			snapshot.unit_kind = CombatUnitSnapshot.UnitKind.ENEMY
		army.append(snapshot)
	var session: CombatSession = SESSION.instantiate()
	session.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1748, 798)
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	var creation_started := Time.get_ticks_usec()
	session.setup(army, [], 91001)
	var creation_ms := (Time.get_ticks_usec() - creation_started) / 1000.0
	_check(session.combatants.size() == army.size(), "Every prepared visual can create its real combatant.")
	for unit in session.combatants:
		unit.set_simulation_active(false)
		for animation in unit.unit_sprite.sprite_frames.get_animation_names():
			unit.unit_sprite.animation = animation
			for frame in unit.unit_sprite.sprite_frames.get_frame_count(animation):
				unit.unit_sprite.frame = frame
				unit._update_unit_sprite_offset()
		_check(unit.unit_sprite.sprite_frames == frames_before[unit.snapshot.definition_id], "Combat instances reuse the prepared animation objects.")
	for id in VFX.ATLASES:
		_check(VFX.get_frames(id) == effects_before[id], "Battle effects reuse their prepared atlas objects.")
	_check(Combatant.feet_cache.size() == feet_before, "First creation performs no deferred foot-image scans.")
	_check(Combatant.chroma_frame_offsets.size() == anchors_before, "Walking, attack and death frames perform no deferred chroma-image scans.")
	var resources_before: int = assets.loaded_resources.size()
	var updates_before := observed.size()
	_check(await assets.prepare(), "Returning to preparation after boot is safe.")
	_check(observed.size() == updates_before and assets.loaded_resources.size() == resources_before, "Preparation is idempotent, retaining its caches for later screens/battles.")
	print("Startup cache report: %s; warm creation of %d units: %.2f ms" % [assets.report, army.size(), creation_ms])
	session.free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if failures == 0:
		print("Startup asset tests passed: real loading progress, retained resources, complete animation/effect caches, warmed image calculations and idempotent boot.")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
