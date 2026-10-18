class_name ItemDefinition
extends ContentDefinition


enum HeroEligibility {
	ANY,
	MELEE,
	RANGED,
}

@export var passive_effects: Array[StatModifier] = []
@export_range(0, 1000000, 1, "or_greater") var price := 0
@export_range(0, 1000000, 1, "or_greater") var sell_price := 0
@export var hero_eligibility: HeroEligibility = HeroEligibility.ANY


func is_compatible_with_hero(hero: HeroDefinition) -> bool:
	if hero == null:
		return false
	var is_ranged := hero.tags.has(&"ranged")
	return (
		hero_eligibility == HeroEligibility.ANY
		or (hero_eligibility == HeroEligibility.MELEE and not is_ranged)
		or (hero_eligibility == HeroEligibility.RANGED and is_ranged)
	)


func eligibility_text() -> String:
	match hero_eligibility:
		HeroEligibility.MELEE:
			return "Melee Heroes"
		HeroEligibility.RANGED:
			return "Ranged Heroes"
	return "Any Hero"
