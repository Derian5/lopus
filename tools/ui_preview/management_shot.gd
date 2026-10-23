extends SceneTree

## Visual check of the management screen (needs a display, not --headless): renders it once and saves a PNG.
##   godot --path . --resolution 1920x1080 -s tools/ui_preview/management_shot.gd
## Env: OUT=<png path> (default user://mgmt.png), NITEMS=<items to hand out>, SOLDIER=1 (select an Archer, add Job skill offers).
func _initialize() -> void:
	call_deferred("_go")
func _go() -> void:
	var run := DemoRunFactory.create_starting_run(7, [&"hero.army_support", &"hero.control_savant", &"hero.ashen_duelist"])
	run.gold = 900
	var reg = root.get_node("ContentRegistry")
	var given := 0
	for d in reg.definitions.values():
		if d is ItemDefinition and given < int(OS.get_environment("NITEMS") if OS.get_environment("NITEMS") != "" else "5"):
			run.inventory.create_item(d.id)
			given += 1
	var scene = load("res://ui/management/management.tscn").instantiate()
	root.add_child(scene)
	scene.setup(run)
	for i in 6: await process_frame
	if OS.get_environment("SOLDIER") != "":
		run.unlocked_job_ids.append(&"job.archer")
		run.job_capacities["job.archer"] = 3
		run.soldiers[0].current_job_id = &"job.archer"
		var job := reg.get_definition(&"job.archer") as JobDefinition
		var n := 0
		for ab in job.available_ability_ids:
			var o := MarketOffer.new()
			o.offer_id = "shot-%d" % n
			o.offer_type = &"job_ability"
			o.content_id = ab
			o.price = 120
			o.target_type = &"job"
			o.target_id = "job.archer"
			o.allowed_job_ids.assign([&"job.archer"])
			run.market.offers.insert(0, o)
			n += 1
		scene._refresh_all()
		scene._select_unit("soldier", 0)
		for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else ProjectSettings.globalize_path("user://mgmt.png"))
	print("OFFERS ", run.market.offers.map(func(o): return o.offer_type))
	quit()
