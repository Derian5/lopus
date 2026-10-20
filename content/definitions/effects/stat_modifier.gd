class_name StatModifier
extends Resource


enum Operation {
	ADD,
	MULTIPLY,
	## Percent bonus: all ADD_PERCENT entries for a stat are summed, then the stat is
	## multiplied by (1 + sum / 100). "+25% attack speed" from two items = +50%.
	ADD_PERCENT,
}

## Secondary stats (all default to 0 and are shown only when non-zero):
## crit_chance (%), crit_multiplier (x, highest source wins), lifesteal (% of basic-attack
## damage healed), dodge (% to evade basic attacks), hp_regen (HP per second),
## cooldown_reduction (%), damage_taken (% extra damage received, negative = reduction),
## armor_penetration (% of the target's armor ignored).
## dodge and cooldown_reduction stack with diminishing returns: 1 - (1-a)(1-b).
const DIMINISHING_STATS := ["dodge", "cooldown_reduction"]
const HIGHEST_WINS_STATS := ["crit_multiplier"]

@export_enum("max_hp", "damage", "attack_speed", "movement_speed", "attack_range", "armor", "crit_chance", "crit_multiplier", "lifesteal", "dodge", "hp_regen", "cooldown_reduction", "damage_taken", "armor_penetration") var stat := "damage"
@export var operation := Operation.ADD
@export var value := 0.0


func apply_to(base_value: float, stack_count := 1) -> float:
	match operation:
		Operation.MULTIPLY:
			return base_value * pow(value, stack_count)
		Operation.ADD_PERCENT:
			return base_value * (1.0 + value * stack_count / 100.0)
	if stat in DIMINISHING_STATS:
		var remaining := (100.0 - base_value) / 100.0
		return 100.0 - 100.0 * remaining * pow(maxf(0.0, 1.0 - value / 100.0), stack_count)
	if stat in HIGHEST_WINS_STATS:
		return maxf(base_value, value)
	return base_value + value * stack_count


const STAT_LABELS := {
	"max_hp": "Max HP",
	"damage": "Damage",
	"attack_speed": "Attack Speed",
	"movement_speed": "Move Speed",
	"attack_range": "Attack Range",
	"armor": "Armor",
	"crit_chance": "Crit Chance",
	"crit_multiplier": "Crit Damage",
	"lifesteal": "Lifesteal",
	"dodge": "Dodge",
	"hp_regen": "HP Regen",
	"cooldown_reduction": "Cooldown Reduction",
	"damage_taken": "Damage Taken",
	"armor_penetration": "Armor Penetration",
}
## Secondary stats whose ADD value is a percentage.
const PERCENT_STATS := ["crit_chance", "lifesteal", "dodge", "cooldown_reduction", "damage_taken", "armor_penetration"]


static func stat_label(stat_name: String) -> String:
	return String(STAT_LABELS.get(stat_name, stat_name.replace("_", " ").capitalize()))


static func format_number(number: float) -> String:
	if is_equal_approx(number, roundf(number)):
		return "%d" % roundi(number)
	return ("%.2f" % number).rstrip("0").rstrip(".")


## Player-facing text such as "+45 Damage", "+25% Attack Speed", "x2.5 Crit Damage".
func display_text(stack_count := 1) -> String:
	var label := stat_label(stat)
	match operation:
		Operation.MULTIPLY:
			var percent := (pow(value, stack_count) - 1.0) * 100.0
			return "%s%s%% %s" % ["+" if percent >= 0.0 else "", format_number(percent), label]
		Operation.ADD_PERCENT:
			var amount := value * stack_count
			return "%s%s%% %s" % ["+" if amount >= 0.0 else "", format_number(amount), label]
	if stat in HIGHEST_WINS_STATS:
		return "x%s %s" % [format_number(value), label]
	var total := value * stack_count
	var unit := "%" if stat in PERCENT_STATS else ("/s" if stat == "hp_regen" else "")
	return "%s%s%s %s" % ["+" if total >= 0.0 else "", format_number(total), unit, label]
