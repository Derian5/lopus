extends SceneTree


## Command-line Balance Lab: simulates whole runs and writes CSV + HTML reports.
##
## godot --headless --path . --script res://tools/balance/run_sim/sim_cli.gd -- [options]
##   styles=heroes,army,one_job,two_jobs,one_hero,nothing   (or styles=all)
##   runs=10            runs per style
##   seed=1000          first seed (each run uses seed + index)
##   heroes=random      random trio per run; or a comma list of three hero ids;
##                      or heroes=all_trios to cycle through every trio
##   jobs=random|fixed  (random: each run picks its own Job A and Job B)
##   job_a=job.warrior job_b=job.archer   (used with jobs=fixed)   focus_hero=0
##   pick=easiest|random|hardest   rerolls=1   resurrect=true
##   out=user://balance_reports    report folder (CSV + HTML)
##   workers=auto       parallel Godot processes (auto = CPU cores - 1; 1 = this process only)

## Preloaded (not by class name) so it works before the editor has scanned the class.
const PARALLEL := preload("res://tools/balance/run_sim/sim_parallel.gd")

var reports: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _parse(OS.get_cmdline_user_args())
	var registry := root.get_node("ContentRegistry")
	var batch := SimBatch.new(registry)
	var configs := batch.build_configs(options)
	var started := Time.get_ticks_msec()
	var worker_arg := String(options.get("workers", "auto"))
	var workers := PARALLEL.default_workers() if worker_arg == "auto" else maxi(1, worker_arg.to_int())
	workers = mini(workers, configs.size())
	if workers > 1:
		print("Simulating %d runs in %d worker processes..." % [configs.size(), workers])
		var parallel := PARALLEL.new()
		if parallel.start(configs, workers) != OK:
			push_error("Could not start the worker processes.")
			quit(1)
			return
		var shown := -1
		while parallel.is_running():
			OS.delay_msec(500)
			var done := parallel.done_count()
			if done != shown:
				shown = done
				print("  %d / %d runs  (%.0f s)" % [done, configs.size(), (Time.get_ticks_msec() - started) / 1000.0])
		reports = parallel.collect()
		if reports.size() < configs.size():
			push_warning("%d runs did not finish; see the worker logs in %s" % [configs.size() - reports.size(), ProjectSettings.globalize_path(parallel.folder)])
		else:
			parallel.cleanup()
	else:
		var simulator := RunSimulator.new(self)
		for index in configs.size():
			var report: Dictionary = await simulator.simulate_run(configs[index])
			reports.append(report)
			print("RUN %d/%d  %-9s %-8s won %2d battles  %s  [%s]" % [index + 1, configs.size(), report.style, report.result, int(report.battles_won), report.died_at, ", ".join(SimReport.hero_names(report.heroes, registry))])
	var folder := String(options.get("out", SimReport.DEFAULT_FOLDER))
	var paths := SimReport.write(reports, folder, registry, options)
	print("Simulated %d runs in %.1f s" % [reports.size(), (Time.get_ticks_msec() - started) / 1000.0])
	print(SimReport.text_summary(reports, registry))
	print("CSV:  %s" % ProjectSettings.globalize_path(paths.csv))
	print("HTML: %s" % ProjectSettings.globalize_path(paths.html))
	quit()


func _parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	return options
