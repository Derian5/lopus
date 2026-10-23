extends SceneTree
## Visual check of condition effects (needs a display, not --headless): a burning Hero,
## Soldier and enemy, a bleeding and a badly hurt Soldier, blows drawing blood. Saves
## c_0..5.png into OUT (default tools/vfx_preview/shots, ignored by the importer).
##   godot --path . --resolution 1600x900 -s tools/vfx_preview/condition_preview.gd
func _initialize() -> void:
	call_deferred("_go")
func _go() -> void:
	var reg = root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(17, [&"hero.ashen_duelist", &"hero.army_support", &"hero.thorn_warden"])
	var jobs := [&"job.archer", &"job.warrior", &"job.militia", &"job.priest", &"job.shieldbearer"]
	for i in run.soldiers.size():
		var j: StringName = jobs[i % jobs.size()]
		if not run.unlocked_job_ids.has(j):
			run.unlocked_job_ids.append(j)
		run.soldiers[i].current_job_id = j
	var enc: EncounterDefinition
	for d in reg.definitions.values():
		if d is EncounterDefinition and not d.is_boss and String(d.id).contains("ogre"):
			enc = d
	var session: CombatSession = load("res://combat/combat_session.tscn").instantiate()
	root.add_child(session)
	session.size = FormationService.REFERENCE_ARENA
	root.size = Vector2i(1600, 900)
	session.setup(CombatSnapshotBuilder.build_player_army(run, reg), CombatDemoFactory.create_enemy_army_from_encounter(enc, 1.0, 1), 5)
	for u in session.combatants:
		u.set_simulation_active(false)
		u.position = Vector2(-600, -600)
	var fire_arrow := load("res://content/demo/abilities/jobs/archer/professionalism_fire_arrow_tier_1.tres") as AbilityDefinition
	var burn: StatusDefinition = fire_arrow.effects[1].status
	var bleed: StatusDefinition = (load("res://content/demo/abilities/items/butcher_cleaver.tres") as AbilityDefinition).effects[0].status
	var row := [session.combatants[0], session.combatants[3], session.combatants[4], session.combatants[5], session.combatants[6]]
	var enemy: Combatant
	for u in session.combatants:
		if u.snapshot.team == CombatUnitSnapshot.Team.ENEMY:
			enemy = u
	for i in row.size():
		row[i].position = Vector2(260 + i * 210, 420)
	enemy.position = Vector2(1300, 420)
	await process_frame
	for i in row.size():
		row[i].position = Vector2(260 + i * 210, 420)
	enemy.position = Vector2(1300, 420)
	row.append(enemy)
	# 0 hero burning, 1 soldier burning, 2 bleeding + hurt, 3 hurt 20%, 4 healthy hit by blows, 5 enemy burning
	for u in [row[0], row[1], row[5]]:
		u.apply_status(burn, row[4], fire_arrow.id)
	row[2].apply_status(bleed, row[4], &"ability.item_butcher_cleaver")
	row[2].current_hp = row[2].get_effective_stat(&"max_hp") * 0.3
	row[3].current_hp = row[3].get_effective_stat(&"max_hp") * 0.15
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else ProjectSettings.globalize_path("res://tools/vfx_preview/shots")
	DirAccess.make_dir_recursive_absolute(out)
	var t0 := Time.get_ticks_msec()
	var shot := 0
	var next_blow := 0.0
	while shot < 6:
		await process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		session.elapsed_time = t
		if t >= next_blow:
			next_blow += 0.5
			session.record_event(CombatEvent.DAMAGE_APPLIED, row[0].snapshot.runtime_id, row[4].snapshot.runtime_id, &"attack.basic", &"attack.basic", 60.0)
			session.record_event(CombatEvent.DAMAGE_APPLIED, row[4].snapshot.runtime_id, row[2].snapshot.runtime_id, &"ability.item_butcher_cleaver", &"effect.item_bleed_tick", 15.0)
			session.record_event(CombatEvent.DAMAGE_APPLIED, row[4].snapshot.runtime_id, row[1].snapshot.runtime_id, fire_arrow.id, &"effect.archer_professionalism_burn_tick", 5.0)
		if t >= 1.2 + shot * 0.45:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("c_%d.png" % shot))
			shot += 1
	print("CDONE")
	quit()
