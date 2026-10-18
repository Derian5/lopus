class_name AbilityText
extends RefCounted


## Renders ability descriptions written as templates into MOBA-style BBCode.
##
## Template syntax (used in AbilityDefinition.description):
## - {path}            a number read from the ability data, e.g. {e0.damage}, {cd},
##                     {area}, {e1.status.default_duration}, {e1.status.stat_modifiers.0.value}.
##                     Roots: cd, icd, area, search, cast, recent, eN (effect N).
## - {a*b}             product of two paths or a path and a number.
## - {path:fmt}        pct (x100), inv_pct ((1-x)x100), bonus_pct ((x-1)x100), abs.
## - [dmg] [heal] [shield] [cc] [buff] [debuff] [gold] [summon] [xp] [kw] ... [/tag]
##                     colour-coded keywords; most also get a small icon.
## Hero abilities resolve every token for each level, so numbers can never drift from
## the data: one number for a known level, "old -> new" for an upgrade preview, and
## "200/400/600/800" when no level is given.

const ICON_DIR := "res://graphics/ui/ability_icons/"
const TAG_STYLES := {
	"dmg": {"color": "#f08a5d", "icon": "damage"},
	"heal": {"color": "#7fd67a", "icon": "heal"},
	"shield": {"color": "#8ec9ff", "icon": "shield"},
	"cc": {"color": "#c59bff", "icon": "cc"},
	"buff": {"color": "#f2c96b", "icon": "buff"},
	"debuff": {"color": "#e8875a", "icon": "debuff"},
	"gold": {"color": "#f5c542", "icon": "gold"},
	"summon": {"color": "#7fd6c4", "icon": "summon"},
	"xp": {"color": "#f2c96b", "icon": "xp"},
	"kw": {"color": "#f1e6cf", "icon": ""},
}
const MUTED := "#8f8371"
const BODY := "#d9cfbd"
const TITLE := "#f3dfb4"
const ICON_SIZE := 18
const ARROW := "\u2192"


## Full tooltip: icon line, name, type line, key numbers and the rendered description.
## level: 0 shows every level of a hero ability; N highlights level N.
static func tooltip(ability: AbilityDefinition, level := 0, extra_lines: Array[String] = []) -> String:
	if ability == null:
		return ""
	var lines: Array[String] = []
	lines.append("[font_size=21][color=%s][b]%s[/b][/color][/font_size]" % [TITLE, ability.display_name.to_upper()])
	lines.append(type_line(ability, level))
	var stats := stat_line(ability, level)
	if not stats.is_empty():
		lines.append(stats)
	lines.append("")
	lines.append("[color=%s]%s[/color]" % [BODY, render(ability, level)])
	for line in extra_lines:
		lines.append(line)
	return "\n".join(lines)


static func type_line(ability: AbilityDefinition, level := 0) -> String:
	var parts: Array[String] = []
	var passive := ability.kind == AbilityDefinition.AbilityKind.PASSIVE
	parts.append("%s [color=%s]%s[/color]" % [icon("passive" if passive else "active"), MUTED, "PASSIVE" if passive else "ACTIVE"])
	if ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
		parts.append("[color=%s]EMPOWERED ATTACK[/color]" % MUTED)
	var levels := level_count(ability)
	if levels > 1:
		parts.append("[color=%s]%s[/color]" % [MUTED, "LEVEL %d / %d" % [level, levels] if level > 0 else "%d LEVELS" % levels])
	return "   ".join(parts)


## Cooldown, range and radius with icons; per-level values when they differ.
static func stat_line(ability: AbilityDefinition, level := 0, compare_level := 0) -> String:
	var parts: Array[String] = []
	if ability.kind == AbilityDefinition.AbilityKind.ACTIVE and ability.cooldown_seconds > 0.0:
		parts.append("%s %s" % [icon("cooldown"), _values_text(ability, "cd", "", level, true, compare_level, "s")])
	var reach := "search" if ability.target_search_radius > 0.0 else ("cast" if ability.cast_range > 0.0 else "")
	if not reach.is_empty():
		parts.append("%s %s" % [icon("range"), _values_text(ability, reach, "", level, true, compare_level)])
	if ability.area_radius > 0.0:
		parts.append("%s %s" % [icon("radius"), _values_text(ability, "area", "", level, true, compare_level)])
	return "    ".join(parts)


## Description template rendered to BBCode.
static func render(ability: AbilityDefinition, level := 0, compare_level := 0) -> String:
	if ability == null:
		return ""
	var text := ability.description
	text = _resolve_tokens(ability, text, level, true, compare_level)
	for tag in TAG_STYLES:
		var style: Dictionary = TAG_STYLES[tag]
		var prefix := (icon(style.icon) + " ") if not String(style.icon).is_empty() else ""
		text = text.replace("[%s]" % tag, "%s[color=%s]" % [prefix, style.color]).replace("[/%s]" % tag, "[/color]")
	return text


## Plain text for Godot's built-in tooltips and logs.
static func plain(ability: AbilityDefinition, level := 0, compare_level := 0) -> String:
	if ability == null:
		return ""
	var text := _resolve_tokens(ability, ability.description, level, false, compare_level)
	for tag in TAG_STYLES:
		text = text.replace("[%s]" % tag, "").replace("[/%s]" % tag, "")
	return text


static func icon(name: String) -> String:
	return "[img=%dx%d]%s%s.png[/img]" % [ICON_SIZE, ICON_SIZE, ICON_DIR, name]


static func level_count(ability: AbilityDefinition) -> int:
	return maxi(1, ability.hero_levels.size())


# --- tokens ------------------------------------------------------------------

## Display rules (MOBA style):
## - level N known: only that level's number, e.g. "40%".
## - compare_level M set (an upgrade preview): "20% -> 40%", old value muted.
## - level unknown: the whole chain in one style, unit once: "20/40/60/80%".
## A unit written right after a token ({x}% or {x}s) belongs to the number.
static func _resolve_tokens(ability: AbilityDefinition, text: String, level: int, rich: bool, compare_level := 0) -> String:
	var result := ""
	var cursor := 0
	while true:
		var open := text.find("{", cursor)
		if open < 0:
			break
		var close := text.find("}", open)
		if close < 0:
			break
		result += text.substr(cursor, open - cursor)
		var token := text.substr(open + 1, close - open - 1)
		var parts := token.split(":")
		var unit := ""
		cursor = close + 1
		if cursor < text.length():
			var next := text[cursor]
			var after := text[cursor + 1] if cursor + 1 < text.length() else " "
			if next == "%" or (next == "s" and not (after.to_lower() != after.to_upper() or after.is_valid_int())):
				unit = next
				cursor += 1
		result += _values_text(ability, parts[0], parts[1] if parts.size() > 1 else "", level, rich, compare_level, unit)
	return result + text.substr(cursor)


static func _values_text(ability: AbilityDefinition, expression: String, format: String, level: int, rich := true, compare_level := 0, unit := "") -> String:
	var values: Array[String] = []
	for index in level_count(ability):
		var source := ability.for_hero_level(index + 1) if not ability.hero_levels.is_empty() else ability
		values.append(_number(_apply_format(_evaluate(source, expression), format)))
	var unique := {}
	for value in values:
		unique[value] = true
	var shown := ""
	if unique.size() == 1:
		shown = values[0] + unit
	elif level > 0:
		var current := values[clampi(level - 1, 0, values.size() - 1)]
		if compare_level > 0 and compare_level != level:
			var previous := values[clampi(compare_level - 1, 0, values.size() - 1)]
			if previous != current:
				if not rich:
					return "%s%s -> %s%s" % [previous, unit, current, unit]
				return "[color=%s]%s%s %s[/color] [b]%s%s[/b]" % [MUTED, previous, unit, ARROW, current, unit]
		shown = current + unit
	else:
		shown = "/".join(values) + unit
	return "[b]%s[/b]" % shown if rich else shown


static func _evaluate(ability: AbilityDefinition, expression: String) -> float:
	if expression.contains("*"):
		var factors := expression.split("*")
		var product := 1.0
		for factor in factors:
			product *= _evaluate(ability, factor.strip_edges())
		return product
	if expression.is_valid_float():
		return float(expression)
	var path := expression.strip_edges().split(".")
	var value: Variant
	match path[0]:
		"cd":
			value = ability.cooldown_seconds
		"icd":
			value = ability.initial_cooldown_seconds
		"area":
			value = ability.area_radius
		"search":
			value = ability.target_search_radius
		"cast":
			value = ability.cast_range
		"recent":
			value = ability.required_recent_damage_seconds
		_:
			if path[0].begins_with("e") and path[0].substr(1).is_valid_int():
				var index := int(path[0].substr(1))
				value = ability.effects[index] if index < ability.effects.size() else null
			else:
				push_warning("AbilityText: unknown token root '%s' in %s" % [path[0], ability.id])
				return 0.0
	for step in range(1, path.size()):
		if value == null:
			break
		var key := path[step]
		if (value is Array) and key.is_valid_int():
			var items: Array = value
			value = items[int(key)] if int(key) < items.size() else null
		elif value is Object:
			value = (value as Object).get(key)
		else:
			value = null
	if value == null:
		push_warning("AbilityText: token '%s' not found on %s" % [expression, ability.id])
		return 0.0
	return float(value)


static func _apply_format(value: float, format: String) -> float:
	match format:
		"pct":
			return value * 100.0
		"inv_pct":
			return (1.0 - value) * 100.0
		"bonus_pct":
			return (value - 1.0) * 100.0
		"abs":
			return absf(value)
	return value


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	if absf(value) < 1.0:
		return ("%.2f" % value).rstrip("0").rstrip(".")
	return ("%.1f" % value).rstrip("0").rstrip(".")
