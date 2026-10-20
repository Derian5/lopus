extends Node


## Visual check of the combat effects with the real art: open vfx_preview.tscn and press
## F6. It plays scripted battles and saves frames as PNG into tools/vfx_preview/shots/
## (ignored by the importer), then closes.

const STEP := 0.25
const START := 1.0
const END := 9.0

var out := ""


@export var scene := "all"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	out = ProjectSettings.globalize_path("res://tools/vfx_preview/shots")
	DirAccess.make_dir_recursive_absolute(out)
	var marker := FileAccess.open(out.path_join(".gdignore"), FileAccess.WRITE)
	if marker != null:
		marker.close()
	get_window().size = Vector2i(1600, 900)
	if scene in ["all", "showcase"]:
		await _showcase()
	if scene in ["all", "ranged"]:
		await _battle("ranged", [&"hero.army_support", &"hero.control_savant", &"hero.iron_oracle"], [&"job.archer", &"job.archer", &"job.priest", &"job.priest", &"job.summoner", &"job.summoner", &"job.warrior", &"job.warrior", &"job.shieldbearer"], "witch_doctor")
	if scene in ["all", "melee"]:
		await _battle("melee", [&"hero.ashen_duelist", &"hero.test_vanguard", &"hero.thorn_warden"], [&"job.warrior", &"job.warrior", &"job.warrior", &"job.shieldbearer", &"job.shieldbearer", &"job.archer", &"job.archer", &"job.priest", &"job.militia"], "ogre")
	print("VFX_PREVIEW_DONE ", out)
	var done := FileAccess.open(out.path_join("done.txt"), FileAccess.WRITE)
	if done != null:
		done.store_string("done")
		done.close()
	get_tree().quit()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")


func _make_run(hero_ids: Array[StringName], jobs: Array[StringName]) -> RunState:
	var run := DemoRunFactory.create_starting_run(17, hero_ids)
	for index in run.soldiers.size():
		var job_id: StringName = jobs[index % jobs.size()]
		if not run.unlocked_job_ids.has(job_id):
			run.unlocked_job_ids.append(job_id)
		run.soldiers[index].current_job_id = job_id
		var found := false
		for build in run.job_builds:
			if build.job_id == job_id:
				found = true
		if not found and job_id != &"job.militia":
			var build := JobBuildState.new()
			build.job_id = job_id
			run.job_builds.append(build)
	for hero in run.heroes:
		hero.level = 4
	return run


func _encounter(fragment: String) -> EncounterDefinition:
	var best: EncounterDefinition
	for definition in _registry().definitions.values():
		if definition is EncounterDefinition and not definition.is_boss:
			if String(definition.id).contains(fragment) or definition.display_name.to_lower().contains(fragment):
				best = definition
	if best == null:
		for definition in _registry().definitions.values():
			if definition is EncounterDefinition and not definition.is_boss:
				return definition
	return best


func _new_session() -> CombatSession:
	var session: CombatSession = load("res://combat/combat_session.tscn").instantiate()
	add_child(session)
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.position = Vector2.ZERO
	session.size = FormationService.REFERENCE_ARENA
	return session


func _battle(tag: String, hero_ids: Array[StringName], jobs: Array[StringName], encounter_fragment: String) -> void:
	var run := _make_run(hero_ids, jobs)
	var encounter := _encounter(encounter_fragment)
	var enemies := CombatDemoFactory.create_enemy_army_from_encounter(encounter, 1.4, 4)
	var session := _new_session()
	session.setup(CombatSnapshotBuilder.build_player_army(run, _registry()), enemies, 99)
	var t := 0.0
	var next := START
	var index := 0
	while t < END and session.battle_active:
		await get_tree().process_frame
		t += 1.0 / 60.0
		if t >= next:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%02d.png" % [tag, index]))
			index += 1
			next += STEP
	session.queue_free()
	await get_tree().process_frame


## Every effect next to a standing Hero and Soldier, frozen at a few moments.
func _showcase() -> void:
	var run := _make_run([&"hero.army_support", &"hero.control_savant", &"hero.ashen_duelist"], [&"job.archer", &"job.warrior"])
	var session := _new_session()
	session.setup(CombatSnapshotBuilder.build_player_army(run, _registry()), [], 5)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
		unit.position = Vector2(-500, -500)
	var vfx := preload("res://combat/vfx/combat_vfx.gd")
	var ids := ["hit_slash", "hit_heavy", "magic_burst", "cast_sigil", "heal_sparkle", "death_soul", "summon_portal", "slam_ring", "walk_dust"]
	var shots := ["arrow", "holy_bolt", "spirit_wisp", "venom_bolt", "arcane_lance", "gloom_orb", "hex_orb", "ember_bolt", "magic_orb"]
	var hero := session.combatants[0]
	var soldier := session.combatants[3]
	hero.position = Vector2(140, 200)
	soldier.position = Vector2(140, 470)
	for frame in [2, 4, 6]:
		var effects := session.get_node("Effects")
		for child in effects.get_children():
			child.free()
		for i in ids.size():
			var pos := Vector2(260 + i * 112, 200 if i < 5 else 470)
			if i >= 5:
				pos.x = 260 + (i - 5) * 150
			var effect := vfx.spawn(effects, StringName(ids[i]), pos, 0.5 if ids[i] != "slam_ring" else 0.8)
			if effect != null:
				effect.stop()
				effect.frame = mini(frame, effect.sprite_frames.get_frame_count(&"play") - 1)
		for i in shots.size():
			var sprite := vfx.make_projectile_sprite(StringName(shots[i]))
			effects.add_child(sprite)
			sprite.position = Vector2(860 + (i % 3) * 140, 400 + floori(i / 3.0) * 90)
			sprite.z_index = 30
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("showcase_%d.png" % frame))
	session.queue_free()
	await get_tree().process_frame
