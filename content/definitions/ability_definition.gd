class_name AbilityDefinition
extends ContentDefinition


enum AbilityKind {
	ACTIVE,
	PASSIVE,
}

enum TargetingPolicy {
	SELF,
	CLOSEST_ENEMY,
	LOWEST_HP_ALLY,
	RANDOM_VALID_ENEMY,
}

enum DeliveryMethod {
	INSTANT,
	MELEE_HIT,
	PROJECTILE,
	AREA_AROUND_TARGET,
}

@export var kind := AbilityKind.ACTIVE
@export_range(0.0, 3600.0, 0.1, "or_greater") var cooldown_seconds := 0.0
@export var targeting_policy := TargetingPolicy.CLOSEST_ENEMY
@export var delivery_method := DeliveryMethod.INSTANT
@export var effects: Array[AbilityEffect] = []
@export var priority := 0
@export_range(0.0, 10000.0, 1.0, "or_greater") var area_radius := 0.0
@export var presentation_icon: Texture2D
@export var presentation_color := Color.WHITE
@export var presentation_text := ""
