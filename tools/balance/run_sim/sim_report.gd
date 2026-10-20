class_name SimReport
extends RefCounted


## Aggregates simulated runs and writes them as CSV (one row per run), JSON and a
## self-contained HTML report (styles, Heroes, Encounters, every run).

const DEFAULT_FOLDER := "user://balance_reports"


static func hero_names(ids: Array, registry: Node) -> Array[String]:
	var names: Array[String] = []
	for hero_id in ids:
		var hero := registry.get_definition(StringName(hero_id), false) as HeroDefinition
		names.append(hero.display_name if hero != null else String(hero_id))
	return names


static func summarize(reports: Array[Dictionary], registry: Node) -> Dictionary:
	var styles := {}
	var heroes := {}
	var encounters := {}
	var hero_style := {}
	var total_battles := 0
	for report in reports:
		var style := String(report.style)
		var s: Dictionary = styles.get(style, {"runs": 0, "wins": 0, "battles_won": 0, "soldiers_lost": 0, "hero_deaths": 0, "battles": 0, "final_gold": 0, "levels": 0.0, "deaths_at": {}, "spent": {}})
		var won := String(report.result) == "win"
		s.runs += 1
		s.wins += 1 if won else 0
		s.battles_won += int(report.battles_won)
		s.final_gold += int(report.final_gold)
		var level_sum := 0
		for level in report.final_levels:
			level_sum += int(level)
		s.levels += float(level_sum) / maxf(report.final_levels.size(), 1)
		for key in report.spent:
			s.spent[key] = int(s.spent.get(key, 0)) + int(report.spent[key])
		for battle in report.battles:
			s.battles += 1
			s.soldiers_lost += int(battle.soldiers_lost)
			s.hero_deaths += int(battle.heroes_died)
			total_battles += 1
			var e: Dictionary = encounters.get(String(battle.encounter), {"name": String(battle.encounter_name), "act": int(battle.act), "fights": 0, "losses": 0, "soldiers_lost": 0, "duration": 0.0, "timeouts": 0, "numbers": {}})
			e.fights += 1
			e.losses += 0 if bool(battle.win) else 1
			e.soldiers_lost += int(battle.soldiers_lost)
			e.duration += float(battle.duration)
			e.timeouts += 1 if bool(battle.timed_out) else 0
			e.numbers[str(int(battle.number))] = true
			encounters[String(battle.encounter)] = e
		if not won and not report.battles.is_empty():
			var key := str(int(report.battles[-1].number))
			s.deaths_at[key] = int(s.deaths_at.get(key, 0)) + 1
		styles[style] = s
		for hero_id in report.heroes:
			var h: Dictionary = heroes.get(String(hero_id), {"runs": 0, "wins": 0, "battles_won": 0, "damage": 0.0, "tanked": 0.0, "healing": 0.0, "kills": 0, "deaths": 0, "battles": 0, "executed": 0, "final_level": 0.0, "best_damage": 0.0, "best_tanked": 0.0, "best_healing": 0.0, "by_battle": {}, "by_act": {}})
			h.runs += 1
			h.wins += 1 if won else 0
			h.battles_won += int(report.battles_won)
			h.executed += 1 if String(report.executed_hero) == String(hero_id) else 0
			var stats: Dictionary = report.hero_stats.get(String(hero_id), {})
			for key in ["damage", "tanked", "healing", "kills", "deaths", "battles"]:
				h[key] = h[key] + stats.get(key, 0)
			var slot := (report.heroes as Array).find(hero_id)
			if slot >= 0 and slot < report.final_levels.size():
				h.final_level += float(report.final_levels[slot])
			for battle in report.battles:
				for row in battle.get("heroes", []):
					if String(row.id) != String(hero_id):
						continue
					h.best_damage = maxf(h.best_damage, float(row.damage))
					h.best_tanked = maxf(h.best_tanked, float(row.tanked))
					h.best_healing = maxf(h.best_healing, float(row.healing))
					# Per battle number: how many times fought, level after it and its totals.
					var bkey := str(int(battle.number))
					var b: Dictionary = h.by_battle.get(bkey, {"n": 0, "level": 0.0, "damage": 0.0, "tanked": 0.0, "healing": 0.0, "kills": 0, "deaths": 0})
					b.n += 1
					b.level += float(row.level)
					b.damage += float(row.damage)
					b.tanked += float(row.tanked)
					b.healing += float(row.healing)
					b.kills += int(row.kills)
					b.deaths += 1 if bool(row.died) else 0
					h.by_battle[bkey] = b
					var akey := str(int(battle.act))
					var a: Dictionary = h.by_act.get(akey, {"n": 0, "damage": 0.0, "tanked": 0.0, "healing": 0.0})
					a.n += 1
					a.damage += float(row.damage)
					a.tanked += float(row.tanked)
					a.healing += float(row.healing)
					h.by_act[akey] = a
			heroes[String(hero_id)] = h
			var hs_key := "%s|%s" % [hero_id, style]
			var hs: Dictionary = hero_style.get(hs_key, {"runs": 0, "wins": 0, "battles_won": 0})
			hs.runs += 1
			hs.wins += 1 if won else 0
			hs.battles_won += int(report.battles_won)
			hero_style[hs_key] = hs
	for hero_id in heroes:
		var hero := registry.get_definition(StringName(hero_id), false) as HeroDefinition
		heroes[hero_id]["name"] = hero.display_name if hero != null else hero_id
	return {"styles": styles, "heroes": heroes, "encounters": encounters, "hero_style": hero_style, "total_battles": total_battles}


static func text_summary(reports: Array[Dictionary], registry: Node) -> String:
	var summary := summarize(reports, registry)
	var lines := PackedStringArray(["", "STYLE          RUNS  WINRATE  AVG BATTLES WON  SOLDIERS LOST/BATTLE"])
	for style in SimBot.STYLES:
		if not summary.styles.has(style):
			continue
		var s: Dictionary = summary.styles[style]
		lines.append("%-14s %4d  %6.0f%%  %15.1f  %20.2f" % [SimBot.STYLE_NAMES.get(style, style), s.runs, 100.0 * s.wins / maxf(s.runs, 1), float(s.battles_won) / maxf(s.runs, 1), float(s.soldiers_lost) / maxf(s.battles, 1)])
	lines.append("")
	lines.append("HERO           RUNS  WINRATE  AVG BATTLES WON  DAMAGE/B  TANKED/B  HEALING/B  DEATHS/B  FINAL LVL")
	var hero_ids: Array = summary.heroes.keys()
	hero_ids.sort_custom(func(a, b) -> bool: return _winrate(summary.heroes[a]) > _winrate(summary.heroes[b]))
	for hero_id in hero_ids:
		var h: Dictionary = summary.heroes[hero_id]
		var b := maxf(h.battles, 1)
		lines.append("%-14s %4d  %6.0f%%  %15.1f  %8.0f  %8.0f  %9.0f  %8.2f  %9.1f" % [h.name, h.runs, 100.0 * _winrate(h), float(h.battles_won) / maxf(h.runs, 1), float(h.damage) / b, float(h.tanked) / b, float(h.healing) / b, float(h.deaths) / b, float(h.final_level) / maxf(h.runs, 1)])
	return "\n".join(lines)


static func _winrate(entry: Dictionary) -> float:
	return float(entry.wins) / maxf(float(entry.runs), 1.0)


static func write(reports: Array[Dictionary], folder: String, registry: Node, options: Dictionary = {}) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var base := folder.path_join("balance_%s" % stamp)
	var csv_path := base + ".csv"
	var html_path := base + ".html"
	var json_path := base + ".json"
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv != null:
		csv.store_line("style,seed,heroes,result,battles_won,died_at,executed_hero,final_gold,final_levels,soldiers_lost,hero_deaths,spent_hero_items,spent_army,spent_rerolls,spent_resurrection,final_jobs,hero_damage,hero_tanked,hero_healing")
		for report in reports:
			var lost := 0
			var hero_deaths := 0
			for battle in report.battles:
				lost += int(battle.soldiers_lost)
				hero_deaths += int(battle.heroes_died)
			var army := int(report.spent.job_unlock) + int(report.spent.job_capacity) + int(report.spent.job_ability)
			csv.store_line(",".join(PackedStringArray([
				report.style, str(report.seed), _csv(" / ".join(hero_names(report.heroes, registry))), report.result,
				str(report.battles_won), _csv(report.died_at), _csv(" ".join(hero_names([report.executed_hero], registry)) if not String(report.executed_hero).is_empty() else ""),
				str(report.final_gold), _csv(" / ".join(report.final_levels.map(func(l) -> String: return str(l)))),
				str(lost), str(hero_deaths), str(report.spent.hero_items), str(army), str(report.spent.reroll), str(report.spent.resurrection),
				_csv(JSON.stringify(report.final_jobs)),
				_csv(_hero_totals(report, "damage")), _csv(_hero_totals(report, "tanked")), _csv(_hero_totals(report, "healing")),
			])))
		csv.close()
	var data := {
		"generated": Time.get_datetime_string_from_system(false, true),
		"options": options,
		"style_names": SimBot.STYLE_NAMES,
		"styles_order": SimBot.STYLES,
		"summary": summarize(reports, registry),
		"runs": reports,
		"hero_names": _all_hero_names(registry),
		"route_battles": _route_battles(registry),
	}
	var json := FileAccess.open(json_path, FileAccess.WRITE)
	if json != null:
		json.store_string(JSON.stringify(data))
		json.close()
	var html := FileAccess.open(html_path, FileAccess.WRITE)
	if html != null:
		var template := FileAccess.get_file_as_string("res://tools/balance/run_sim/report_template.html")
		html.store_string(template.replace("/*__DATA__*/null", JSON.stringify(data)))
		html.close()
	return {"csv": csv_path, "html": html_path, "json": json_path}


static func _route_battles(registry: Node) -> int:
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	return route.act_one_boss_wave + route.act_two_battle_count if route != null else 0


static func _all_hero_names(registry: Node) -> Dictionary:
	var names := {}
	for definition in registry.definitions.values():
		if definition is HeroDefinition:
			names[String(definition.id)] = definition.display_name
	return names


## "a / b / c" in trio order: a run's total of one stat for each Hero.
static func _hero_totals(report: Dictionary, key: String) -> String:
	var parts := PackedStringArray()
	for hero_id in report.heroes:
		var stats: Dictionary = report.hero_stats.get(String(hero_id), {})
		parts.append(str(roundi(float(stats.get(key, 0.0)))))
	return " / ".join(parts)


static func _csv(value: String) -> String:
	return "\"%s\"" % value.replace("\"", "\"\"")
