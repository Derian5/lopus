class_name ItemDefinition
extends ContentDefinition


enum ItemCategory {
	DAMAGE,
	TANK,
	SUPPORT,
	COMMAND,
	UNIQUE,
}

enum HeroEligibility {
	ANY,
	MELEE,
	RANGED,
}

@export var category := ItemCategory.DAMAGE
## Stat bonuses. Use ADD for flat values and ADD_PERCENT for "+X%" bonuses.
@export var passive_effects: Array[StatModifier] = []
## Item abilities (AbilityDefinition ids, usually with available_to_heroes = false).
## Active ones are cast automatically like Hero abilities; passive ones apply at battle start.
@export var ability_ids: Array[StringName] = []
## Unique items: only these Heroes can buy and equip them (empty = any Hero).
@export var allowed_hero_ids: Array[StringName] = []
@export_range(0, 1000000, 1, "or_greater") var price := 0
@export_range(0, 1000000, 1, "or_greater") var sell_price := 0
@export var hero_eligibility: HeroEligibility = HeroEligibility.ANY


func is_compatible_with_hero(hero: HeroDefinition) -> bool:
	if hero == null:
		return false
	if not allowed_hero_ids.is_empty() and not allowed_hero_ids.has(hero.id):
		return false
	var is_ranged := hero.tags.has(&"ranged")
	return (
		hero_eligibility == HeroEligibility.ANY
		or (hero_eligibility == HeroEligibility.MELEE and not is_ranged)
		or (hero_eligibility == HeroEligibility.RANGED and is_ranged)
	)


## Short restriction shown in lists ("Pride only", "Melee Heroes"); empty for any Hero.
func restriction_text(registry: Node) -> String:
	if is_unique():
		var names: Array[String] = []
		for hero_id in allowed_hero_ids:
			var hero := registry.get_definition(hero_id, false) as HeroDefinition if registry != null else null
			names.append(hero.display_name if hero != null else String(hero_id))
		return "%s only" % ", ".join(names)
	return eligibility_text() if hero_eligibility != HeroEligibility.ANY else ""


func is_unique() -> bool:
	return not allowed_hero_ids.is_empty()


static func category_name(value: int) -> String:
	return ["Damage", "Tank", "Support", "Command", "Unique"][clampi(value, 0, 4)]


func eligibility_text() -> String:
	match hero_eligibility:
		HeroEligibility.MELEE:
			return "Melee Heroes"
		HeroEligibility.RANGED:
			return "Ranged Heroes"
	return "Any Hero"
