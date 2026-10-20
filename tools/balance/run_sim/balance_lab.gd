extends Control


## Balance Lab window. Open tools/balance/run_sim/balance_lab.tscn in the editor and
## press F6 (Run Current Scene). Pick play styles and options, press SIMULATE, then
## read the summary here or open the full HTML report.

const STYLE_HINTS := {
	"heroes": "Buys items for every Hero (the weakest Hero gets the next item).",
	"one_hero": "Buys items only for the focus Hero; that Hero is never executed.",
	"army": "Buys Job unlocks, capacity and Job abilities for every Job.",
	"one_job": "Spends everything on one Job (random per run, or Job A when Jobs = Fixed).",
	"two_jobs": "Splits spending between two different Jobs (random per run, or Job A / Job B when Fixed).",
	"nothing": "Never buys anything (resurrection still allowed if enabled).",
}

## Preloaded (not by class name) so it works before the editor has scanned the class.
const PARALLEL := preload("res://tools/balance/run_sim/sim_parallel.gd")

var registry: Node
var batch: SimBatch
var style_boxes := {}
var runs_spin: SpinBox
var seed_spin: SpinBox
var hero_mode: OptionButton
var hero_pickers: Array[OptionButton] = []
var job_mode: OptionButton
var job_a: OptionButton
var job_b: OptionButton
var focus_spin: SpinBox
var pick_mode: OptionButton
var reroll_spin: SpinBox
var workers_spin: SpinBox
var active_parallel = null
var resurrect_box: CheckBox
var run_button: Button
var stop_button: Button
var open_button: Button
var progress: ProgressBar
var status_label: Label
var summary: RichTextLabel
var hero_ids: Array[StringName] = []
var job_ids: Array[StringName] = []
var running := false
var stop_requested := false
var last_html := ""


func _ready() -> void:
	registry = get_node("/root/ContentRegistry")
	batch = SimBatch.new(registry)
	hero_ids = batch.selectable_heroes()
	for definition in registry.definitions.values():
		if definition is JobDefinition and definition.id != &"job.militia":
			job_ids.append(definition.id)
	job_ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.06, 0.05)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	margin.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	scroll.add_child(left)
	left.add_child(_title("BALANCE LAB"))
	left.add_child(_muted("Simulates whole runs through the real game code. Every style plays the same seeds and Hero trios."))
	left.add_child(_header("Play styles"))
	for style in SimBot.STYLES:
		var box := CheckBox.new()
		box.text = SimBot.STYLE_NAMES[style]
		box.button_pressed = true
		box.tooltip_text = STYLE_HINTS[style]
		style_boxes[style] = box
		left.add_child(box)

	left.add_child(_header("Runs"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	left.add_child(grid)
	runs_spin = _spin(grid, "Runs per style", 1, 500, 10)
	seed_spin = _spin(grid, "First seed", 1, 999999, 1000)
	hero_mode = _option(grid, "Heroes", ["Random trio per run", "Cycle every trio", "Fixed trio"])
	hero_mode.item_selected.connect(func(_index: int) -> void: _refresh_hero_pickers())
	for index in 3:
		var picker := _option(grid, "  Hero %d" % (index + 1), hero_ids.map(func(id: StringName) -> String: return _hero_name(id)))
		picker.select(index)
		hero_pickers.append(picker)
	job_mode = _option(grid, "Jobs (One / Two Jobs)", ["Random per run", "Fixed: Job A / Job B"])
	job_mode.item_selected.connect(func(_index: int) -> void: _refresh_job_pickers())
	job_a = _option(grid, "Job A", job_ids.map(func(id: StringName) -> String: return _content_name(id)))
	job_b = _option(grid, "Job B", job_ids.map(func(id: StringName) -> String: return _content_name(id)))
	job_a.select(maxi(job_ids.find(&"job.warrior"), 0))
	job_b.select(maxi(job_ids.find(&"job.archer"), 0))
	focus_spin = _spin(grid, "Focus Hero (One Hero)", 1, 3, 1)
	pick_mode = _option(grid, "Encounter card", ["Easiest", "Random", "Hardest"])
	reroll_spin = _spin(grid, "Rerolls per Market", 0, 10, 1)
	workers_spin = _spin(grid, "Parallel processes", 1, 32, PARALLEL.default_workers())
	workers_spin.tooltip_text = "Runs are simulated in this many headless Godot processes at once (one per CPU core). 1 = inside this window."
	resurrect_box = CheckBox.new()
	resurrect_box.text = "Resurrect dead Heroes"
	resurrect_box.button_pressed = true
	left.add_child(resurrect_box)
	_refresh_hero_pickers()
	_refresh_job_pickers()

	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	run_button = Button.new()
	run_button.text = "SIMULATE"
	run_button.custom_minimum_size = Vector2(150, 40)
	run_button.pressed.connect(_on_run_pressed)
	buttons.add_child(run_button)
	stop_button = Button.new()
	stop_button.text = "STOP"
	stop_button.disabled = true
	stop_button.pressed.connect(func() -> void: stop_requested = true)
	buttons.add_child(stop_button)
	open_button = Button.new()
	open_button.text = "OPEN HTML REPORT"
	open_button.disabled = true
	open_button.pressed.connect(func() -> void: OS.shell_open(ProjectSettings.globalize_path(last_html)))
	buttons.add_child(open_button)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 18)
	left.add_child(progress)
	status_label = _muted("Ready.")
	left.add_child(status_label)

	summary = RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("normal_font_size", 15)
	summary.add_theme_font_size_override("mono_font_size", 15)
	summary.text = "[color=#9a8b74]Results appear here. The HTML report adds survival charts, the Hero × style table, Encounter danger and every run battle by battle.[/color]"
	columns.add_child(summary)


func _refresh_job_pickers() -> void:
	job_a.disabled = job_mode.selected == 0
	job_b.disabled = job_mode.selected == 0


func _refresh_hero_pickers() -> void:
	for picker in hero_pickers:
		picker.disabled = hero_mode.selected != 2


func _options() -> Dictionary:
	var styles: Array[String] = []
	for style in SimBot.STYLES:
		if style_boxes[style].button_pressed:
			styles.append(style)
	var heroes: String = ["random", "all_trios", ""][hero_mode.selected]
	if hero_mode.selected == 2:
		var picked: Array[String] = []
		for picker in hero_pickers:
			picked.append(String(hero_ids[picker.selected]))
		heroes = ",".join(picked)
	return {
		"styles": ",".join(styles),
		"runs": int(runs_spin.value),
		"seed": int(seed_spin.value),
		"heroes": heroes,
		"jobs": "random" if job_mode.selected == 0 else "fixed",
		"job_a": String(job_ids[job_a.selected]),
		"job_b": String(job_ids[job_b.selected]),
		"focus_hero": int(focus_spin.value) - 1,
		"pick": ["easiest", "random", "hardest"][pick_mode.selected],
		"rerolls": int(reroll_spin.value),
		"resurrect": "true" if resurrect_box.button_pressed else "false",
	}


func _on_run_pressed() -> void:
	if running:
		return
	var options := _options()
	if String(options.styles).is_empty():
		status_label.text = "Pick at least one play style."
		return
	if hero_mode.selected == 2:
		var unique := {}
		for picker in hero_pickers:
			unique[picker.selected] = true
		if unique.size() != 3:
			status_label.text = "A fixed trio needs three different Heroes."
			return
	running = true
	stop_requested = false
	run_button.disabled = true
	stop_button.disabled = false
	var configs := batch.build_configs(options)
	var workers := mini(int(workers_spin.value), configs.size())
	if workers > 1:
		await _run_parallel(configs, workers, options)
		return
	var simulator := RunSimulator.new(get_tree())
	simulator.yield_every_steps = 900
	var reports: Array[Dictionary] = []
	var started := Time.get_ticks_msec()
	progress.max_value = configs.size()
	for index in configs.size():
		if stop_requested:
			break
		var config := configs[index]
		status_label.text = "Run %d / %d  -  %s, seed %d" % [index + 1, configs.size(), SimBot.STYLE_NAMES.get(config.style, config.style), config.seed]
		var report: Dictionary = await simulator.simulate_run(config)
		reports.append(report)
		progress.value = index + 1
		summary.text = _summary_bbcode(reports)
		await get_tree().process_frame
	if not reports.is_empty():
		var paths := SimReport.write(reports, SimReport.DEFAULT_FOLDER, registry, options)
		last_html = paths.html
		open_button.disabled = false
		status_label.text = "%d runs in %.0f s%s. Report: %s" % [reports.size(), (Time.get_ticks_msec() - started) / 1000.0, " (stopped)" if stop_requested else "", ProjectSettings.globalize_path(paths.html)]
	running = false
	run_button.disabled = false
	stop_button.disabled = true


func _run_parallel(configs: Array[Dictionary], workers: int, options: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	progress.max_value = configs.size()
	progress.value = 0
	var parallel := PARALLEL.new()
	active_parallel = parallel
	if parallel.start(configs, workers) != OK:
		status_label.text = "Could not start the worker processes."
	else:
		while parallel.is_running():
			if stop_requested:
				parallel.stop()
				break
			await get_tree().create_timer(0.4).timeout
			var done := parallel.done_count()
			progress.value = done
			status_label.text = "%d / %d runs in %d processes  -  %.0f s" % [done, configs.size(), workers, (Time.get_ticks_msec() - started) / 1000.0]
		var reports := parallel.collect()
		if not reports.is_empty():
			summary.text = _summary_bbcode(reports)
			var paths := SimReport.write(reports, SimReport.DEFAULT_FOLDER, registry, options)
			last_html = paths.html
			open_button.disabled = false
			var missing := configs.size() - reports.size()
			status_label.text = "%d runs in %.0f s (%d processes)%s. Report: %s" % [reports.size(), (Time.get_ticks_msec() - started) / 1000.0, workers, " (stopped)" if stop_requested else (" - %d runs failed, logs in %s" % [missing, ProjectSettings.globalize_path(parallel.folder)] if missing > 0 else ""), ProjectSettings.globalize_path(paths.html)]
		else:
			status_label.text = "No run finished. Worker logs: %s" % ProjectSettings.globalize_path(parallel.folder)
		if reports.size() == configs.size() or stop_requested:
			parallel.cleanup()
	active_parallel = null
	running = false
	run_button.disabled = false
	stop_button.disabled = true


func _exit_tree() -> void:
	# Closing the window must not leave worker processes behind.
	if active_parallel != null:
		active_parallel.stop()


func _summary_bbcode(reports: Array[Dictionary]) -> String:
	var data := SimReport.summarize(reports, registry)
	var lines := PackedStringArray()
	lines.append("[font_size=20][color=#e6b85c]PLAY STYLES[/color][/font_size]")
	lines.append("[table=6][cell][b]Style[/b]  [/cell][cell][b]Runs[/b]  [/cell][cell][b]Winrate[/b]  [/cell][cell][b]Avg won[/b]  [/cell][cell][b]Soldiers lost/battle[/b]  [/cell][cell][b]Hero deaths/battle[/b][/cell]")
	for style in SimBot.STYLES:
		if not data.styles.has(style):
			continue
		var s: Dictionary = data.styles[style]
		var rate := float(s.wins) / maxf(s.runs, 1)
		lines.append("[cell]%s  [/cell][cell]%d[/cell][cell][color=%s]%.0f%%[/color][/cell][cell]%.1f[/cell][cell]%.2f[/cell][cell]%.2f[/cell]" % [SimBot.STYLE_NAMES[style], s.runs, _rate_color(rate), rate * 100.0, float(s.battles_won) / maxf(s.runs, 1), float(s.soldiers_lost) / maxf(s.battles, 1), float(s.hero_deaths) / maxf(s.battles, 1)])
	lines.append("[/table]")
	lines.append("")
	lines.append("[font_size=20][color=#e6b85c]HEROES[/color][/font_size]")
	lines.append("[table=6][cell][b]Hero[/b]  [/cell][cell][b]Runs[/b]  [/cell][cell][b]Winrate[/b]  [/cell][cell][b]Avg won[/b]  [/cell][cell][b]Damage/battle[/b]  [/cell][cell][b]Deaths/battle[/b][/cell]")
	var ids: Array = data.heroes.keys()
	ids.sort_custom(func(a, b) -> bool:
		var ha: Dictionary = data.heroes[a]
		var hb: Dictionary = data.heroes[b]
		return float(ha.battles_won) / maxf(ha.runs, 1) > float(hb.battles_won) / maxf(hb.runs, 1)
	)
	for hero_id in ids:
		var h: Dictionary = data.heroes[hero_id]
		var rate := float(h.wins) / maxf(h.runs, 1)
		lines.append("[cell]%s  [/cell][cell]%d[/cell][cell][color=%s]%.0f%%[/color][/cell][cell]%.1f[/cell][cell]%.0f[/cell][cell]%.2f[/cell]" % [h.name, h.runs, _rate_color(rate), rate * 100.0, float(h.battles_won) / maxf(h.runs, 1), float(h.damage) / maxf(h.battles, 1), float(h.deaths) / maxf(h.battles, 1)])
	lines.append("[/table]")
	lines.append("")
	lines.append("[font_size=20][color=#e6b85c]DEADLIEST ENCOUNTERS[/color][/font_size]")
	var encounters: Array = data.encounters.keys()
	encounters.sort_custom(func(a, b) -> bool: return float(data.encounters[a].losses) / data.encounters[a].fights > float(data.encounters[b].losses) / data.encounters[b].fights)
	for index in mini(6, encounters.size()):
		var e: Dictionary = data.encounters[encounters[index]]
		lines.append("%s  -  loss rate [color=%s]%.0f%%[/color] of %d fights, %.1f soldiers lost" % [e.name, _rate_color(1.0 - float(e.losses) / e.fights), 100.0 * e.losses / e.fights, e.fights, float(e.soldiers_lost) / e.fights])
	return "\n".join(lines)


func _rate_color(rate: float) -> String:
	if rate >= 0.6:
		return "#7fd67a"
	return "#e8735a" if rate <= 0.25 else "#e6b85c"


func _hero_name(hero_id: StringName) -> String:
	return _content_name(hero_id)


func _content_name(content_id: StringName) -> String:
	var definition := registry.get_definition(content_id, false) as ContentDefinition
	return definition.display_name if definition != null else String(content_id)


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.9, 0.72, 0.36))
	return label


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", Color(0.79, 0.64, 0.42))
	return label


func _muted(text: String, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		label.custom_minimum_size = Vector2(190, 0)
	label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.46))
	return label


func _spin(grid: GridContainer, caption: String, minimum: float, maximum: float, value: float) -> SpinBox:
	grid.add_child(_muted(caption, false))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.custom_minimum_size = Vector2(170, 0)
	grid.add_child(spin)
	return spin


func _option(grid: GridContainer, caption: String, items: Array) -> OptionButton:
	grid.add_child(_muted(caption, false))
	var option := OptionButton.new()
	for item in items:
		option.add_item(String(item))
	option.custom_minimum_size = Vector2(170, 0)
	grid.add_child(option)
	return option
