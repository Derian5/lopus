class_name AbilityDefinition
extends ContentDefinition


const MAX_HERO_ABILITY_LEVEL := 4


enum AbilityKind {
	ACTIVE,
	PASSIVE,
}

enum TargetingPolicy {
	SELF,
	CLOSEST_ENEMY,
	LOWEST_HP_ALLY,
	RANDOM_VALID_ENEMY,
	NEAREST_NEGATIVE_STATUS_ALLY,
	RANDOM_ENEMY_WITHOUT_STATUS,
	LOWEST_CURRENT_HP_ALLY,
	MOST_TARGETED_ALLY,
	HIGHEST_DAMAGE_ENEMY,
	HIGHEST_HP_NON_BOSS_ENEMY,
	## Random ranged enemy within the search radius, otherwise any enemy.
	RANDOM_BACK_LINE_ENEMY,
}

enum DeliveryMethod {
	INSTANT,
	MELEE_HIT,
	PROJECTILE,
	AREA_AROUND_TARGET,
}

enum ActivationMode {
	STANDARD,
	REPLACE_BASIC_ATTACK,
}

@export var kind := AbilityKind.ACTIVE
@export var activation_mode := ActivationMode.STANDARD
@export_range(0.0, 3600.0, 0.1, "or_greater") var cooldown_seconds := 0.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var initial_cooldown_seconds := 0.0
@export var targeting_policy := TargetingPolicy.CLOSEST_ENEMY
@export var delivery_method := DeliveryMethod.INSTANT
@export var effects: Array[AbilityEffect] = []
@export var priority := 0
@export_range(0.0, 10000.0, 1.0, "or_greater") var area_radius := 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var target_search_radius := 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var cast_range := 0.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var required_recent_damage_seconds := 0.0
@export var presentation_icon: Texture2D
@export var presentation_color := Color.WHITE
@export var presentation_text := ""
## Visual profile; empty selects a profile from the effects. No gameplay changes.
@export var presentation_style: StringName
## Optional CombatVfx projectile profile, e.g. fire_arrow.
@export var projectile_vfx: StringName
@export_range(0, 1000000, 1, "or_greater") var price := 0
## A purchasable Job upgrade requires ownership of this preceding level.
@export var upgrades_ability_id: StringName
@export var available_to_heroes := true
@export var allowed_hero_ids: Array[StringName] = []
@export var hero_levels: Array[AbilityLevelDefinition] = []
@export var excluded_target_status_id: StringName


func is_allowed_for_hero(hero_definition_id: StringName) -> bool:
	return available_to_heroes and (allowed_hero_ids.is_empty() or allowed_hero_ids.has(hero_definition_id))


func job_skill_level(registry: Node) -> int:
	var level := 1
	var current: AbilityDefinition = self
	var visited := {}
	while not current.upgrades_ability_id.is_empty() and not visited.has(current.id):
		visited[current.id] = true
		var previous := registry.get_definition(current.upgrades_ability_id, false) as AbilityDefinition
		if previous == null:
			break
		level += 1
		current = previous
	return level


func for_hero_level(level: int) -> AbilityDefinition:
	if hero_levels.is_empty():
		return self
	var level_index := clampi(level, 1, hero_levels.size()) - 1
	var level_definition := hero_levels[level_index]
	if level_definition == null:
		return self
	var runtime := duplicate() as AbilityDefinition
	runtime.cooldown_seconds = level_definition.cooldown_seconds
	runtime.area_radius = level_definition.area_radius
	runtime.effects = level_definition.effects.duplicate()
	# Remembered for tooltips so a leveled copy highlights its own level's numbers.
	runtime.set_meta(&"hero_level", level_index + 1)
	return runtime
