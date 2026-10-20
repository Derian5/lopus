class_name SimBatch
extends RefCounted


## Turns Balance Lab options into one config per simulated run.

var registry: Node


func _init(content_registry: Node) -> void:
	registry = content_registry


func selectable_heroes() -> Array[StringName]:
	var heroes: Array[HeroDefinition] = []
	for definition in registry.definitions.values():
		if definition is HeroDefinition and definition.available_in_new_game:
			heroes.append(definition)
	heroes.sort_custom(func(a: HeroDefinition, b: HeroDefinition) -> bool: return a.selection_order < b.selection_order)
	var ids: Array[StringName] = []
	for hero in heroes:
		ids.append(hero.id)
	return ids


func all_trios() -> Array:
	var ids := selectable_heroes()
	var trios := []
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			for c in range(b + 1, ids.size()):
				trios.append([ids[a], ids[b], ids[c]])
	return trios


## Jobs the One Job / Two Jobs styles can focus on (every Job except Militia).
func focus_jobs() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in registry.definitions.values():
		if definition is JobDefinition and definition.id != &"job.militia":
			ids.append(definition.id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## options: styles, runs, seed, heroes, jobs (random|fixed), job_a, job_b, focus_hero,
## pick, rerolls, resurrect. With jobs=random (default) every run picks its own Job A
## and a different Job B; run N uses the same pair in every style.
func build_configs(options: Dictionary) -> Array[Dictionary]:
	var styles: Array = []
	var style_arg := String(options.get("styles", "all"))
	styles = SimBot.STYLES.duplicate() if style_arg == "all" else Array(style_arg.split(","))
	var runs := maxi(1, int(options.get("runs", 10)))
	var first_seed := int(options.get("seed", 1000))
	var hero_mode := String(options.get("heroes", "random"))
	var trios := all_trios()
	var rng := RandomNumberGenerator.new()
	rng.seed = first_seed
	if hero_mode == "all_trios":
		# Shuffled once, so even a short batch spreads every Hero evenly.
		for index in range(trios.size() - 1, 0, -1):
			var swap := rng.randi_range(0, index)
			var held = trios[index]
			trios[index] = trios[swap]
			trios[swap] = held
	# The same seed and trio for run N of every style, so styles are compared fairly.
	var run_heroes: Array = []
	for index in runs:
		var heroes: Array = []
		if hero_mode == "random":
			heroes = trios[rng.randi_range(0, trios.size() - 1)]
		elif hero_mode == "all_trios":
			heroes = trios[index % trios.size()]
		else:
			for hero_id in hero_mode.split(","):
				heroes.append(StringName(hero_id.strip_edges()))
		run_heroes.append(heroes)
	var random_jobs := String(options.get("jobs", "random")) != "fixed"
	var job_rng := RandomNumberGenerator.new()
	job_rng.seed = first_seed * 31 + 7
	var jobs := focus_jobs()
	var run_jobs: Array = []
	for index in runs:
		var first := String(options.get("job_a", "job.warrior"))
		var second := String(options.get("job_b", "job.archer"))
		if random_jobs and jobs.size() >= 2:
			var a := job_rng.randi_range(0, jobs.size() - 1)
			var b := job_rng.randi_range(0, jobs.size() - 2)
			if b >= a:
				b += 1
			first = String(jobs[a])
			second = String(jobs[b])
		run_jobs.append([first, second])
	var configs: Array[Dictionary] = []
	for style in styles:
		for index in runs:
			var heroes: Array = run_heroes[index]
			configs.append({
				"style": String(style).strip_edges(),
				"seed": first_seed + index,
				"heroes": heroes,
				"job_a": run_jobs[index][0],
				"job_b": run_jobs[index][1],
				"focus_hero": int(options.get("focus_hero", 0)),
				"encounter_pick": String(options.get("pick", "easiest")),
				"max_rerolls": int(options.get("rerolls", 1)),
				"resurrect": String(options.get("resurrect", "true")) != "false",
			})
	return configs
