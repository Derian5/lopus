class_name SimParallel
extends RefCounted


## Runs a batch of simulated runs in several headless Godot processes at once (one
## run per CPU core at a time) and gathers the reports back in config order.
## GDScript runs on one core, so this is where most of the speed-up comes from.
##
## var parallel := SimParallel.new()
## parallel.start(configs, 4)
## while parallel.is_running(): OS.delay_msec(300)   # or await a timer in a window
## var reports := parallel.collect()

const WORKER_SCRIPT := "res://tools/balance/run_sim/sim_worker.gd"
const JOB_FOLDER := "user://balance_jobs"

var total := 0
var folder := ""
var pids: Array[int] = []
var out_files: Array[String] = []
var progress_files: Array[String] = []
var log_files: Array[String] = []


## Leaves one core free for the window/OS; at most 12 processes.
static func default_workers() -> int:
	return clampi(OS.get_processor_count() - 1, 1, 12)


func start(configs: Array[Dictionary], workers: int) -> Error:
	total = configs.size()
	workers = clampi(workers, 1, maxi(total, 1))
	folder = JOB_FOLDER.path_join("%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	# Round-robin, so slow and fast styles are spread over every worker.
	var chunks := []
	for index in workers:
		chunks.append([])
	for index in configs.size():
		chunks[index % workers].append({"index": index, "config": configs[index]})
	for worker in workers:
		var job_path := ProjectSettings.globalize_path(folder.path_join("job_%d.bin" % worker))
		var file := FileAccess.open(job_path, FileAccess.WRITE)
		if file == null:
			stop()
			return FileAccess.get_open_error()
		file.store_var(chunks[worker])
		file.close()
		var out_path := ProjectSettings.globalize_path(folder.path_join("out_%d.bin" % worker))
		var progress_path := ProjectSettings.globalize_path(folder.path_join("progress_%d.txt" % worker))
		var log_path := ProjectSettings.globalize_path(folder.path_join("log_%d.txt" % worker))
		var args := PackedStringArray([
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"--log-file", log_path,
			"--script", WORKER_SCRIPT,
			"--",
			"job=" + job_path,
			"out=" + out_path,
			"progress=" + progress_path,
		])
		var pid := OS.create_process(OS.get_executable_path(), args)
		if pid <= 0:
			stop()
			return ERR_CANT_CREATE
		pids.append(pid)
		out_files.append(out_path)
		progress_files.append(progress_path)
		log_files.append(log_path)
	return OK


func is_running() -> bool:
	for pid in pids:
		if OS.is_process_running(pid):
			return true
	return false


## Runs finished so far, over all workers.
func done_count() -> int:
	var done := 0
	for path in progress_files:
		if FileAccess.file_exists(path):
			done += FileAccess.get_file_as_string(path).strip_edges().to_int()
	return done


func stop() -> void:
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)


## Reports of every finished run, in the order of the configs.
func collect() -> Array[Dictionary]:
	var by_index := {}
	for path in out_files:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var entries = file.get_var()
		file.close()
		if entries is Array:
			for entry in entries:
				if entry is Dictionary and entry.has("index"):
					by_index[int(entry.index)] = entry.report
	var reports: Array[Dictionary] = []
	for index in total:
		if by_index.has(index):
			reports.append(by_index[index])
	return reports


## Worker logs (for errors) and the job folder are removed once the batch is read.
func cleanup() -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(folder))
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
