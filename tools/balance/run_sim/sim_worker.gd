extends SceneTree


## One Balance Lab worker process, started by SimParallel. Reads its share of the
## run configs, simulates them and keeps rewriting the finished reports, so a batch
## that is stopped early still keeps every finished run.
##   -- job=<file with [{index, config}]> out=<reports file> progress=<counter file>


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var job_file := FileAccess.open(String(options.get("job", "")), FileAccess.READ)
	if job_file == null:
		push_error("Balance Lab worker: job file not found.")
		quit(1)
		return
	var jobs = job_file.get_var()
	job_file.close()
	var simulator := RunSimulator.new(self)
	var finished := []
	for job in jobs:
		var report: Dictionary = await simulator.simulate_run(job.config)
		finished.append({"index": int(job.index), "report": report})
		_write_var(String(options.get("out", "")), finished)
		_write_text(String(options.get("progress", "")), str(finished.size()))
	quit()


func _write_var(path: String, value: Variant) -> void:
	# Written to a temporary file first, so the window never reads half a file.
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_var(value)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path + ".tmp", path)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
