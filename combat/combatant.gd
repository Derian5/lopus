class_name Combatant
extends CharacterBody2D


enum State {
	IDLE,
	ACQUIRE_TARGET,
	MOVE_INTO_RANGE,
	ATTACK_WINDUP,
	ATTACK_RECOVERY,
	DEAD,
}

const HERO_VISUAL_RADIUS := 28.8
const UNIT_VISUAL_RADIUS := 28.8
const BOSS_VISUAL_RADIUS := 45.6
const COLLISION_SCALE := 0.7
const HERO_RADIUS := HERO_VISUAL_RADIUS * COLLISION_SCALE
const UNIT_RADIUS := UNIT_VISUAL_RADIUS * COLLISION_SCALE
const BOSS_RADIUS := BOSS_VISUAL_RADIUS * COLLISION_SCALE
## Visible standing silhouette, excluding transparent/chroma-key canvas margins.
const UNIT_SPRITE_HEIGHT := 128.0
const HERO_SPRITE_HEIGHT := 156.0
const SUMMON_SPRITE_HEIGHT := 64.0
const OGRE_VISUAL_SCALE := 1.5
const SUMMON_VISUAL_SCALE := 1.3
const UNIT_VISIBLE_SIZES := preload("res://combat/unit_visible_sizes.json")
const ARENA_GEOMETRY := preload("res://combat/arena_geometry.gd")
const STUCK_TIMEOUT := 3.0
const RANGED_ATTACK_PAUSE := 0.1
## Simulation-defined standstill; presentation fits the swing to this interval.
const ATTACK_SWING_FRACTION := 2.0 / 3.0
const APPROACH_INSET := 14.0
const MOVEMENT_ARRIVAL_DISTANCE := 8.0
const MOVEMENT_REPLAN_DISTANCE := 32.0
const STEERING_INTERVAL := 0.18
const RANGED_RETREAT_START := 0.55
const RANGED_RETREAT_END := 0.8
const FRENZY_ACTIVATION_DELAY := 3.0
const FRENZY_DIRECTION_INTERVAL := 0.75
const HEALING_FLASH_PRIORITY := 1
const DAMAGE_FLASH_PRIORITY := 2
const CHROMA_KEY_SHADER := preload("res://combat/unit_chroma_key.gdshader")
## Every unit animation plays this much faster than authored. Presentation only:
## attack and cast timings in combat do not change.
const ANIMATION_SPEED := 1.5
## How long a Hero with "attack_hold" keeps the weapon raised between two shots.
const ATTACK_HOLD_GRACE := 0.45
const HERO_PROJECTILE_TIPS := {
	&"hero.army_support": Vector2(323.0, -100.0),
	&"hero.iron_oracle": Vector2(168.0, -174.0),
	&"hero.control_savant": Vector2(280.0, -128.0),
}
## Where the weapon tip is in every attack frame (texture pixels, measured from the
## source frames). While the attack animation plays, shots leave exactly from the drawn
## staff; otherwise (and in the Balance Lab, where sprites do not animate) the fixed
## HERO_PROJECTILE_TIPS above are used.
const HERO_PROJECTILE_FRAME_TIPS := {
	&"hero.control_savant": [
		Vector2(350, 209), Vector2(357, 211), Vector2(393, 211), Vector2(462, 210),
		Vector2(465, 211), Vector2(464, 210), Vector2(464, 210), Vector2(464, 211),
		Vector2(464, 211), Vector2(464, 211), Vector2(464, 211), Vector2(464, 211),
		Vector2(464, 210), Vector2(452, 202), Vector2(427, 201), Vector2(376, 207),
	],
}
const UNIT_ANIMATION_CONFIGS := {
	&"job.militia": {
		"frame_directory": "res://graphics/units/player/units/militia",
		"move_frames": 16,
		"attack_frames": 16,
		"death_frames": 16,
		"move_speed": 12.0,
		"attack_speed": 16.0,
		"death_speed": 12.0,
		"scale": 0.16,
		"reference_height": 388.0,
		"chroma_key": true,
		"health_bar_offset": 72.0,
	},
	&"job.archer": {"frame_directory": "res://graphics/units/player/units/archer", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.17, "reference_height": 356.0, "ground_offset": 52.0, "health_bar_offset": 62.0, "attack_impact_frame": 8, "projectile_tip": Vector2(514, 263)},
	&"job.priest": {"frame_directory": "res://graphics/units/player/units/priest", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "skill_frames": 16, "skill_speed": 16.0, "scale": 0.22, "reference_height": 276.0, "ground_offset": 52.0, "health_bar_offset": 62.0, "attack_impact_frame": 9, "projectile_tip": Vector2(490, 260)},
	&"job.summoner": {"frame_directory": "res://graphics/units/player/units/summoner", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "skill_frames": 16, "skill_speed": 16.0, "scale": 0.20, "reference_height": 312.0, "ground_offset": 52.0, "health_bar_offset": 64.0, "attack_impact_frame": 8, "projectile_tip": Vector2(203, 184)},
	&"job.warrior": {"frame_directory": "res://graphics/units/player/units/warrior", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.23, "reference_height": 256.0, "ground_offset": 52.0, "health_bar_offset": 62.0},
	&"job.shieldbearer": {"frame_directory": "res://graphics/units/player/units/shieldbearer", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.22, "reference_height": 268.0, "ground_offset": 52.0, "health_bar_offset": 62.0},
	&"enemy.summoned_brawler": {"frame_directory": "res://graphics/units/player/units/creature", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.19, "reference_height": 216.0, "ground_offset": 32.0, "health_bar_offset": 46.0},
	&"enemy.summoned_shooter": {"frame_directory": "res://graphics/units/player/units/creature", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.17, "reference_height": 216.0, "ground_offset": 30.0, "health_bar_offset": 44.0, "attack_impact_frame": 6, "projectile_tip": Vector2(520, 311)},
	&"enemy.summoned_amalgam": {"frame_directory": "res://graphics/units/player/units/creature", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.29, "reference_height": 216.0, "ground_offset": 52.0, "health_bar_offset": 62.0},
	&"enemy.raider": {"frame_directory": "res://graphics/units/enemies/brute", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 20},
	&"enemy.troll_berserker": {"frame_directory": "res://graphics/units/enemies/berserker", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 16},
	&"enemy.ogre_bonebreaker": {"frame_directory": "res://graphics/units/enemies/bonebreaker", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 20},
	&"enemy.summoner": {"frame_directory": "res://graphics/units/enemies/hexer", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 22, "projectile_tip": Vector2(424, 100)},
	&"enemy.troll_priest": {"frame_directory": "res://graphics/units/enemies/witch doctor", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 22, "projectile_tip": Vector2(702, 300)},
	&"enemy.bog_spawn": {"frame_directory": "res://graphics/units/enemies/bog spawn", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 18},
	&"enemy.iron_warden": {"frame_directory": "res://graphics/units/enemies/iron_warden", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "skill_frames": 30, "skill_directory": "spell", "skill_speed": 20.0, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 20, "reactive_skill": true},
	&"enemy.bog_king": {"frame_directory": "res://graphics/units/enemies/mugrot", "move_frames": 30, "attack_frames": 30, "death_frames": 30, "move_speed": 20.0, "death_speed": 15.0, "despill_edges": true, "attack_impact_frame": 20},
	&"hero.iron_oracle": {"frame_directory": "res://graphics/units/player/hero/Despair", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.17, "reference_height": 452.0, "chroma_key": true, "health_bar_offset": 78.0, "attack_impact_frame": 9, "projectile_tip": Vector2(417, 110)},
	&"hero.army_support": {"frame_directory": "res://graphics/units/player/hero/Envy", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "attack_hold": [4, 13], "scale": 0.15, "reference_height": 505.0, "chroma_key": true, "despill_green_edges": true, "health_bar_offset": 78.0, "projectile_frame": 13, "projectile_tip": Vector2(670, 126)},
	&"hero.thorn_warden": {"frame_directory": "res://graphics/units/player/hero/gluttony", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.15, "reference_height": 505.0, "animation_scales": {&"attack": 2.2}, "chroma_key": true, "crop_green_canvas": true, "health_bar_offset": 78.0},
	&"hero.test_vanguard": {"frame_directory": "res://graphics/units/player/hero/greed", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.095, "reference_height": 800.0, "chroma_key": true, "reverse_attack_recovery": true, "health_bar_offset": 78.0},
	&"hero.glass_arcanist": {"frame_directory": "res://graphics/units/player/hero/lust", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.078, "reference_height": 977.0, "animation_scales": {&"attack": 4.15}, "chroma_key": true, "health_bar_offset": 78.0},
	&"hero.control_savant": {"frame_directory": "res://graphics/units/player/hero/Pride", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "attack_hold": [4, 13], "scale": 0.22, "reference_height": 344.0, "chroma_key": true, "health_bar_offset": 78.0, "projectile_frame": 13, "projectile_tip": Vector2(464, 210)},
	&"hero.ashen_duelist": {"frame_directory": "res://graphics/units/player/hero/Wrath", "move_frames": 16, "attack_frames": 16, "death_frames": 16, "scale": 0.125, "reference_height": 625.0, "chroma_key": true, "crop_green_canvas": true, "health_bar_offset": 78.0},
}

## Per-frame body-anchor offsets generated from the source frames
## (see combat/unit_frame_offsets.json). They keep each unit's torso and feet
## planted while it walks and attacks, removing sprite jitter.
const FACING_DEAD_ZONE := 6.0
const FACING_MIN_SPEED := 8.0
const FRAME_OFFSETS_PATH := "res://combat/unit_frame_offsets.json"
const ALLIED_FRAME_OFFSETS_PATH := "res://combat/allied_frame_offsets.json"
const ENEMY_FRAME_OFFSETS_PATH := "res://combat/enemy_frame_offsets.json"
const ALPHA_SPRITE_SHADER := preload("res://combat/unit_alpha_sprite.gdshader")
var unit_sprite_uses_alpha_shader := false
var unit_sprite_attack_impact_frame := -1
var unit_sprite_skill_overrides_attack := false
var queued_reactive_skill := false
static var unit_sprite_frames: Dictionary = {}
static var authored_frame_offsets: Dictionary = {}
static var authored_frame_offsets_loaded := false
static var chroma_frame_offsets: Dictionary = {}

const GROUND_MARKER := preload("res://combat/unit_ground_marker.gd")
const STATUS_VFX := preload("res://combat/vfx/unit_status_vfx.gd")
const ENEMY_MEDALLION := preload("res://ui/encounter_choice/enemy_token.gd")
var ground_marker: Node2D
var status_vfx: Node2D
## Condition look written by status_vfx (presentation only): burning glow and the
## drained, heartbeat-red look of a badly hurt unit (0..1 each).
var condition_burn := 0.0
var condition_hurt := 0.0
var condition_phase := 0.0
var placeholder_medallion: Control
## Damage trail belongs to presentation only and never feeds the simulation.
var health_trail_ratio := -1.0
var health_trail_delay := 0.0
var last_visual_health_ratio := -1.0

@export var damage_flash_color := Color.WHITE
@export_range(0.0, 10.0, 0.01, "or_greater") var damage_flash_duration := 0.1
## Knockback for a hit worth damage_knockback_reference_percent of Max HP; it scales
## linearly with the hit's share of Max HP and is capped at damage_knockback_max_distance.
@export_range(0.0, 1000.0, 0.1, "or_greater") var damage_knockback_distance := 10.0
@export_range(0.1, 100.0, 0.1) var damage_knockback_reference_percent := 5.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var damage_knockback_max_distance := 36.0
@export var healing_flash_color := Color(1.0, 0.9, 0.2, 1.0)
@export_range(0.0, 10.0, 0.01, "or_greater") var healing_flash_duration := 0.1

var snapshot: CombatUnitSnapshot
var session
var arena_bounds := Rect2()
var state := State.IDLE
var target: Combatant
var current_hp := 0.0
var body_radius := UNIT_RADIUS
var base_body_radius := UNIT_RADIUS
var visual_radius := UNIT_VISUAL_RADIUS
var base_visual_radius := UNIT_VISUAL_RADIUS
var state_timer := 0.0
var windup_duration := 0.0
var attack_animation_duration := 0.0
var attack_committed := false
var committed_attack_target: Combatant
var committed_attack_ability: AbilityDefinition
var committed_windup_remaining := 0.0
var attack_motion_lock_remaining := 0.0
var attack_serial := 0
var presented_attack_serial := 0
var stuck_time := 0.0
var last_movement_position := Vector2.ZERO
## Navigation decisions are simulation state, never render-frame state.
var approach_target: Combatant
var approach_goal := Vector2.ZERO
var approach_target_position := Vector2.ZERO
var approach_slot_index := -1
var approach_reach := 0.0
var approach_committed := false
var approach_arc_side := 1.0
var steering_direction := Vector2.ZERO
var steering_goal := Vector2.ZERO
var steering_recheck_remaining := 0.0
var ranged_retreat_active := false
var ranged_retreat_target: Combatant
var ranged_retreat_destination := Vector2.ZERO
var ranged_retreat_retry_remaining := 0.0
var ranged_retreat_pending := false
var ranged_retreat_source: Combatant
var ranged_retreat_best_distance := INF
var ranged_retreat_stuck_time := 0.0
var simulation_active := false
var temporarily_removed := false
var selected := false
var last_damage_source_id := ""
var last_effect_id: StringName
var last_damage_taken_time := -1.0
var ability_cooldowns: Dictionary = {}
var statuses: Array[StatusInstance] = []
var temporary_modifiers: Array[Dictionary] = []
var basic_attack_empowerments: Array[Dictionary] = []
var shields: Array[Dictionary] = []
var pending_ability: AbilityDefinition
var boss_phase := 1
var phase_banner_timer := 0.0
## Seconds left of the "RANK UP" banner after a mid-battle Veterancy gain.
var veterancy_banner_timer := 0.0
const VETERANCY_BANNER_TIME := 1.6
var last_stand_aura_duration := 0.0
var last_stand_remaining := 0.0
var basic_attack_range_bonus := 0.0
var passive_basic_lifesteal_percent := 0.0
var passive_basic_lifesteal_ability_id: StringName
var passive_basic_lifesteal_effect_id: StringName
## [{"status": StatusDefinition, "ability_id": StringName}] applied by every successful basic hit.
var on_hit_statuses: Array[Dictionary] = []
var nearby_ally_bonus_stat: StringName
var nearby_ally_bonus_value := 0.0
var nearby_ally_bonus_radius := 0.0
var nearby_ally_bonus_max := 0
var nearby_ally_bonus_ability_id: StringName
var targets_farthest_enemy := false
var prefers_farthest_enemy := false
var melee_teleport_distance := 0.0
var melee_teleport_cooldown := 0.0
var melee_teleport_cooldown_remaining := 0.0
var melee_teleport_ability_id: StringName
var enemy_attack_speed_aura_radius := 0.0
var enemy_attack_speed_aura_multiplier := 1.0
var stealth_remaining := 0.0
var stealth_ability_id: StringName
var stealth_effect_id: StringName
var kill_gold_reward := 0
var kill_permanent_damage := 0.0
var kill_reward_ability_id: StringName
var kill_reward_effect_id: StringName
var melee_retaliation_radius := 0.0
var melee_retaliation_multiplier := 0.0
var melee_retaliation_ability_id: StringName
var melee_retaliation_effect_id: StringName
var attack_reflect_percent := 0.0
var attack_reflect_ability_id: StringName
var attack_reflect_effect_id: StringName
var focused_damage_per_stack := 0.0
var focused_stack_duration := 0.0
var focused_damage_stacks: Dictionary = {}
var frenzy_remaining := 0.0
var frenzy_attack_speed_multiplier := 1.0
var frenzy_ability_id: StringName
var frenzy_effect_id: StringName
var frenzy_destination := Vector2.ZERO
var frenzy_direction_timer := 0.0
var first_enemy_damage_time := -1.0
var threshold_guard_health_ratio := 0.0
var threshold_guard_shield_multiplier := 0.0
var threshold_guard_armor_multiplier := 1.0
var threshold_guard_duration := 0.0
var threshold_guard_cooldown := 0.0
var threshold_guard_cooldown_remaining := 0.0
var threshold_guard_ability_id: StringName
var threshold_guard_effect_id: StringName
var ground_slam_damage_multiplier := 0.0
var ground_slam_radius := 0.0
var ground_slam_ability_id: StringName
var ground_slam_effect_id: StringName
var melee_retreat_remaining := 0.0
var melee_retreat_source: Combatant
var melee_retreat_direction := Vector2.ZERO
var melee_retreat_counterattack_pending := false
var envy_strongest_ally_damage_percent := 0.0
var envy_dart_slow_applied := false
var runtime_status_metadata: Array[Dictionary] = []
var forced_basic_target: Combatant
var forced_basic_target_remaining := 0.0
var lust_death_scaling_percent := 0.0
var lust_death_scaling_ability_id: StringName
var lust_target_slow_percent := 0.0
var lust_target_slow_ability_id: StringName
var lust_bond_pending := false
var lust_bond_partner: Combatant
var lust_bond_lifesteal_percent := 0.0
var lust_bond_attack_speed_multiplier := 1.0
var lust_bond_ability_id: StringName
var lust_bond_effect_id: StringName
var lust_basic_hits_required := 0
var lust_basic_hit_count := 0
var lust_basic_knockback_distance := 0.0
var lust_basic_stun_duration := 0.0
var lust_basic_ability_id: StringName
var lust_basic_effect_id: StringName
var basic_attack_target_active := false
var gluttony_lifesteal_aura_radius := 0.0
var gluttony_lifesteal_percent := 0.0
var gluttony_lifesteal_ability_id: StringName
var gluttony_lifesteal_effect_id: StringName
var gluttony_regeneration_max_stacks := 0
var gluttony_regeneration_stacks := 0
var gluttony_regeneration_percent_per_stack := 0.0
var gluttony_regeneration_tick_remaining := 1.0
var gluttony_regeneration_ability_id: StringName
var gluttony_regeneration_effect_id: StringName
var gluttony_damage_aura_radius := 0.0
var gluttony_damage_aura_damage := 0.0
var gluttony_damage_aura_interval := 0.0
var gluttony_damage_aura_tick_remaining := 0.0
var gluttony_damage_aura_ability_id: StringName
var gluttony_damage_aura_effect_id: StringName
var gluttony_death_explosion_radius := 0.0
var gluttony_death_explosion_damage := 0.0
var gluttony_death_explosion_triggered := false
var gluttony_death_explosion_ability_id: StringName
var gluttony_death_explosion_effect_id: StringName
var gluttony_grease_miss_percent := 0.0
var despair_team_proc_chance_percent := 0.0
var despair_team_proc_total_damage_percent := 0.0
var despair_team_proc_ability_id: StringName
var despair_team_proc_effect_id: StringName
var despair_attack_slow_max_stacks := 0
var despair_attack_slow_percent_per_stack := 0.0
var despair_attack_slow_maximum_percent := 0.0
var despair_slow_ability_id: StringName
var despair_slow_effect_id: StringName
var despair_slow_max_stacks := 0
var despair_slow_percent_per_stack := 0.0
var despair_slow_maximum_percent := 0.0
var despair_slow_stacks := 0
var despair_slow_applied_percent := 0.0
var despair_sanctuary_remaining := 0.0
var despair_sanctuary_heal_percent := 0.0
var despair_sanctuary_interval := 0.0
var despair_sanctuary_tick_remaining := 0.0
var despair_sanctuary_source: Combatant
var despair_sanctuary_ability_id: StringName
var despair_sanctuary_effect_id: StringName
var despair_growth_rates: Dictionary = {}
var despair_growth_bonus_percent: Dictionary = {}
var despair_growth_maximum_percent := 0.0
var despair_growth_interval := 0.0
var despair_growth_tick_remaining := 0.0
var despair_growth_ability_id: StringName
var despair_growth_effect_id: StringName
var flash_remaining := 0.0
var flash_color := Color.TRANSPARENT
var flash_priority := 0
var sprite_was_attacking := false
var sprite_was_attack_recovery := false
var sprite_was_windup := false
## "attack_hold" units: x = first frame of a follow-up shot, y = frame held between
## shots (weapon raised). x < 0 = the unit plays its whole attack every time.
var attack_hold_frames := Vector2i(-1, -1)
var attack_hold_raised := false
var attack_hold_lowering := false
var attack_hold_grace := 0.0
## Seconds until the next footstep dust puff (presentation only).
var dust_timer := 0.0
var unit_sprite_frame_offsets: Dictionary = {}
## Offsets the sprites used before authored body anchors; kept for gameplay-facing
## positions (projectile origins) so combat timing stays identical.
var unit_sprite_legacy_offsets: Dictionary = {}
var unit_sprite_legacy_position := Vector2.ZERO
var unit_sprite_uses_chroma_key := false
var unit_sprite_reverses_attack_recovery := false
var unit_sprite_base_scale := 1.0
var unit_sprite_ground_offset := Vector2.ZERO
var unit_sprite_animation_scales: Dictionary = {}
var health_bar_offset := 0.0
var skill_animation_remaining := 0.0
var skill_animation_target: Combatant
var initial_walk_delay_frames := 0
var initial_walk_delay_remaining := 0.0
var items := CombatantItemRuntime.new()

@onready var unit_sprite: AnimatedSprite2D = $UnitSprite
@onready var overhead: Node2D = $Overhead


func setup(unit_snapshot: CombatUnitSnapshot, combat_session, bounds: Rect2, walk_delay_frames: int = 0) -> void:
	snapshot = unit_snapshot.duplicate_snapshot()
	session = combat_session
	arena_bounds = bounds
	initial_walk_delay_frames = clampi(walk_delay_frames, 0, 9)
	current_hp = snapshot.stats.max_hp
	prefers_farthest_enemy = snapshot.targeting_mode == &"farthest"
	base_body_radius = BOSS_RADIUS if snapshot.is_boss else (HERO_RADIUS if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else UNIT_RADIUS)
	body_radius = base_body_radius
	base_visual_radius = BOSS_VISUAL_RADIUS if snapshot.is_boss else (HERO_VISUAL_RADIUS if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else UNIT_VISUAL_RADIUS)
	visual_radius = base_visual_radius
	var collision_shape := CircleShape2D.new()
	collision_shape.radius = body_radius
	$CollisionShape2D.shape = collision_shape
	# Soft separation is predictable and avoids crowd deadlocks.
	collision_layer = 0
	collision_mask = 0
	last_movement_position = position
	state = State.ACQUIRE_TARGET
	simulation_active = true
	_setup_unit_sprite()
	_update_visual_layers()
	items.setup(self)
	_setup_ground_shadow()
	_apply_passive_abilities()
	for ability in snapshot.abilities:
		if ability.kind == AbilityDefinition.AbilityKind.ACTIVE and ability.initial_cooldown_seconds > 0.0:
			ability_cooldowns[ability.id] = ability.initial_cooldown_seconds
	queue_redraw()


func _physics_process(delta: float) -> void:
	_update_flash(delta)
	if not simulation_active or state == State.DEAD:
		velocity = Vector2.ZERO
		return
	_update_runtime(delta)
	if not is_alive():
		return
	if is_stunned():
		velocity = Vector2.ZERO
		return
	if attack_committed:
		_update_attack_windup(delta)
		return
	if attack_motion_lock_remaining > 0.0:
		state = State.ATTACK_RECOVERY
		_update_attack_recovery(delta)
		return
	if is_feared():
		_update_fear(delta)
		return
	if frenzy_remaining > 0.0:
		_update_frenzy(delta)
		return
	if melee_retreat_remaining > 0.0:
		_update_melee_retreat(delta)
		return
	if _try_use_priority_summon():
		return

	match state:
		State.IDLE:
			state = State.ACQUIRE_TARGET
		State.ACQUIRE_TARGET:
			_acquire_target()
		State.MOVE_INTO_RANGE:
			_move_toward_target(delta)
		State.ATTACK_WINDUP:
			_update_attack_windup(delta)
		State.ATTACK_RECOVERY:
			_update_attack_recovery(delta)


func _process(delta: float) -> void:
	_update_visual_layers()
	if queued_reactive_skill:
		if state == State.DEAD:
			queued_reactive_skill = false
		elif velocity.length_squared() <= 1.0:
			queued_reactive_skill = false
			play_ability_animation(self, session.get_ability_definition(threshold_guard_ability_id), true)
	if session != null and session.vfx_enabled:
		_update_health_trail(delta)
	initial_walk_delay_remaining = maxf(0.0, initial_walk_delay_remaining - delta)
	skill_animation_remaining = maxf(0.0, skill_animation_remaining - delta)
	attack_hold_grace = maxf(0.0, attack_hold_grace - delta)
	_update_walk_dust(delta)
	if unit_sprite.visible:
		_update_unit_sprite()


func _update_walk_dust(delta: float) -> void:
	if session == null or not session.vfx_enabled or not session.battle_active or not is_alive() or velocity.length_squared() < 400.0:
		dust_timer = minf(dust_timer, 0.08)
		return
	dust_timer -= delta
	if dust_timer <= 0.0:
		dust_timer = 0.3 + randf() * 0.12
		session.spawn_dust_vfx(self)


## Presentation only: a soft shadow under the feet, below every unit (not in the
## Balance Lab, where visual effects are off).
var ground_shadow: Sprite2D
## Feet of the idle pose relative to the unit (facing right) and the stance width, both
## measured from the art; zero until measured.
var ground_feet := Vector2.ZERO
var ground_stance := 0.0
## Measured feet per frame texture: {path: [feet (texture px from its centre), stance px]}.
static var feet_cache: Dictionary = {}


func _setup_ground_shadow() -> void:
	if session == null or not bool(session.get("vfx_enabled")) or ground_shadow != null:
		return
	ground_shadow = Sprite2D.new()
	ground_shadow.name = "GroundShadow"
	ground_shadow.texture = preload("res://combat/vfx/combat_vfx.gd").get_shadow_texture()
	# Global z 1: above the battlefield (0), below the units layer (2).
	ground_shadow.z_as_relative = false
	ground_shadow.z_index = 1
	_measure_ground_feet()
	var width := visual_radius * (4.2 if snapshot.is_boss else 3.6)
	if ground_stance > 0.0:
		# A little wider than the stance itself, never smaller than the body.
		width = clampf(ground_stance * 1.35, visual_radius * 1.8, visual_radius * 5.0)
	ground_shadow.scale = Vector2(width, width * 0.3) / 128.0
	ground_shadow.position = feet_offset()
	add_child(ground_shadow)
	ground_marker = GROUND_MARKER.new()
	ground_marker.name = "GroundMarker"
	ground_marker.z_as_relative = false
	ground_marker.z_index = 1
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	ground_marker.material = unshaded
	add_child(ground_marker)
	status_vfx = STATUS_VFX.new()
	status_vfx.name = "StatusVfx"
	status_vfx.unit = self
	status_vfx.z_index = 16
	add_child(status_vfx)


## Finds where the feet of the idle pose are drawn: the lowest rows of opaque (and,
## for chroma-keyed art, non-green) pixels. Cached per texture.
func _measure_ground_feet() -> void:
	if unit_sprite == null or not unit_sprite.visible or unit_sprite.sprite_frames == null or not unit_sprite.sprite_frames.has_animation(&"move"):
		return
	var texture := unit_sprite.sprite_frames.get_frame_texture(&"move", 0)
	if texture == null:
		return
	var key := feet_cache_key(texture, unit_sprite_uses_chroma_key)
	if not feet_cache.has(key):
		feet_cache[key] = _scan_feet(texture, unit_sprite_uses_chroma_key)
	var measured: Array = feet_cache[key]
	if measured.is_empty():
		return
	var sprite_scale := absf(unit_sprite.scale.x)
	var sprite_position := unit_sprite.position
	if unit_sprite.flip_h:
		sprite_position.x = -sprite_position.x
	ground_feet = sprite_position + Vector2(measured[0]) * sprite_scale
	ground_stance = float(measured[1]) * sprite_scale


## Drawn body height used to size effects on this unit (feet to the top of the head).
func visual_height() -> float:
	return maxf(health_bar_offset / 0.65, 48.0)


## Effect scale for this unit's size (1 for an ordinary Soldier).
func vfx_size() -> float:
	return clampf(visual_height() / 96.0, 0.7, 2.4)


static func feet_cache_key(texture: Texture2D, chroma_key: bool) -> String:
	return "%s:%s" % [texture.resource_path if not texture.resource_path.is_empty() else texture.get_instance_id(), chroma_key]


static func _scan_feet(texture: Texture2D, chroma_key := false) -> Array:
	var image := texture.get_image()
	if image == null:
		return []
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	var width := image.get_width()
	var height := image.get_height()
	var step := maxi(1, width / 160)
	var top := -1
	var bottom := -1
	for y in range(0, height, step):
		var solid := 0
		for x in range(0, width, step):
			var color := image.get_pixel(x, y)
			if color.a > 0.5 and (not chroma_key or color.g - maxf(color.r, color.b) < 0.08):
				solid += 1
		if solid >= 2:
			if top < 0:
				top = y
			bottom = y
	if bottom < 0:
		return []
	# The feet: the lowest 7% of the body.
	var band_top := bottom - maxi(step, int((bottom - top) * 0.07))
	var min_x := width
	var max_x := -1
	var sum_x := 0.0
	var count := 0
	for y in range(band_top, bottom + 1, step):
		for x in range(0, width, step):
			var color := image.get_pixel(x, y)
			if color.a > 0.5 and (not chroma_key or color.g - maxf(color.r, color.b) < 0.08):
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				sum_x += x
				count += 1
	if count == 0:
		return []
	var feet := Vector2(sum_x / count, bottom) - Vector2(width, height) * 0.5
	return [feet, float(max_x - min_x)]


## Where the drawn feet touch the ground, relative to the unit: the bottom of the
## current sprite frame (frames are drawn with their feet at the bottom edge);
## placeholder bodies stand on their circle.
func feet_offset() -> Vector2:
	if ground_feet != Vector2.ZERO and unit_sprite.visible:
		return Vector2(-ground_feet.x if unit_sprite.flip_h else ground_feet.x, ground_feet.y)
	if unit_sprite != null and unit_sprite.visible and unit_sprite.sprite_frames != null:
		var frame_texture := unit_sprite.sprite_frames.get_frame_texture(unit_sprite.animation, unit_sprite.frame)
		if frame_texture != null:
			return Vector2(0.0, unit_sprite.position.y + frame_texture.get_height() * absf(unit_sprite.scale.y) * 0.46)
	return Vector2(0.0, visual_radius)


func feet_position() -> Vector2:
	return position + feet_offset()


func _update_visual_layers() -> void:
	# Keep live bodies on the same Z plane so the arena's Y-sort can order them.
	z_index = -1 if state == State.DEAD else 0
	if ground_shadow != null:
		ground_shadow.modulate.a = 0.45 if state == State.DEAD else 1.0
		ground_shadow.position = feet_offset()
	if ground_marker != null:
		ground_marker.position = feet_offset()
		ground_marker.queue_redraw()
	if placeholder_medallion != null:
		placeholder_medallion.modulate = Color.WHITE.darkened(0.65) if state == State.DEAD else Color.WHITE.lerp(flash_color, 0.35 if flash_remaining > 0.0 else 0.0)
	overhead.visible = state != State.DEAD
	overhead.queue_redraw()


func _setup_unit_sprite() -> void:
	var animation_id := snapshot.job_id if UNIT_ANIMATION_CONFIGS.has(snapshot.job_id) else snapshot.definition_id
	unit_sprite.visible = UNIT_ANIMATION_CONFIGS.has(animation_id)
	var registry := get_node_or_null("/root/ContentRegistry")
	var definition := registry.get_definition(snapshot.definition_id, false) as EnemyDefinition if registry != null else null
	var is_troll := definition != null and definition.tags.has(&"troll")
	var display_height := UNIT_SPRITE_HEIGHT
	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
		display_height = HERO_SPRITE_HEIGHT
	elif snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON:
		# Trolls retain their existing size, including summoned Bog Spawn.
		display_height = SUMMON_SPRITE_HEIGHT * (1.0 if is_troll else SUMMON_VISUAL_SCALE)
	elif snapshot.unit_kind == CombatUnitSnapshot.UnitKind.ENEMY and definition != null and definition.tags.has(&"ogre") and not is_troll:
		display_height *= OGRE_VISUAL_SCALE
	if not unit_sprite.visible:
		base_visual_radius = display_height * 0.5
		visual_radius = base_visual_radius
		health_bar_offset = display_height * 0.65
		if definition != null and session != null and session.vfx_enabled:
			placeholder_medallion = ENEMY_MEDALLION.new()
			placeholder_medallion.name = "PlaceholderMedallion"
			add_child(placeholder_medallion)
			placeholder_medallion.setup(definition, 1, false, false, false)
			placeholder_medallion.size = placeholder_medallion.custom_minimum_size
			placeholder_medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
			placeholder_medallion.tooltip_text = ""
			var medallion_scale := display_height / (ENEMY_MEDALLION.SIZE - 4.0)
			placeholder_medallion.scale = Vector2.ONE * medallion_scale
			placeholder_medallion.position = -Vector2(placeholder_medallion.size.x * 0.5, ENEMY_MEDALLION.SIZE * 0.5 + 1.0) * medallion_scale
		return
	var config: Dictionary = UNIT_ANIMATION_CONFIGS[animation_id]
	if not unit_sprite_frames.has(animation_id):
		unit_sprite_frames[animation_id] = _build_unit_sprite_frames(config)
	unit_sprite.sprite_frames = unit_sprite_frames[animation_id]
	var visible_sizes: Dictionary = UNIT_VISIBLE_SIZES.data.get(String(config.get("frame_directory", "")), {})
	var reference_height := float(visible_sizes.get("move", config.get("reference_height", 128.0)))
	unit_sprite_base_scale = display_height / reference_height
	unit_sprite_ground_offset = Vector2(0.0, float(config.get("ground_offset", 0.0)))
	unit_sprite_animation_scales = config.get("animation_scales", {})
	unit_sprite_attack_impact_frame = int(config.get("attack_impact_frame", -1))
	unit_sprite_skill_overrides_attack = bool(config.get("reactive_skill", false))
	unit_sprite.scale = Vector2.ONE * unit_sprite_base_scale
	health_bar_offset = float(config.get("health_bar_offset", 0.0))
	if display_height > 0.0:
		health_bar_offset = display_height * 0.65
	unit_sprite_uses_chroma_key = bool(config.get("chroma_key", false))
	unit_sprite_reverses_attack_recovery = bool(config.get("reverse_attack_recovery", false))
	var hold: Array = config.get("attack_hold", [])
	attack_hold_frames = Vector2i(int(hold[0]), int(hold[1])) if hold.size() == 2 else Vector2i(-1, -1)
	if unit_sprite_uses_chroma_key and bool(config.get("despill_green_edges", false)):
		# Frames already carry real alpha and the costume itself is green (Envy): the
		# chroma key would bleach it. Only clean the green fringe along the cut-out edges.
		var edge_material := ShaderMaterial.new()
		edge_material.shader = ALPHA_SPRITE_SHADER
		edge_material.set_shader_parameter("despill_green", true)
		unit_sprite.material = edge_material
	elif unit_sprite_uses_chroma_key:
		var chroma_material := ShaderMaterial.new()
		chroma_material.shader = CHROMA_KEY_SHADER
		unit_sprite.material = chroma_material
	elif bool(config.get("despill_edges", false)):
		unit_sprite_uses_alpha_shader = true
		var alpha_material := ShaderMaterial.new()
		alpha_material.shader = ALPHA_SPRITE_SHADER
		unit_sprite.material = alpha_material
	unit_sprite_legacy_offsets = config.get("frame_offsets", {})
	unit_sprite_frame_offsets = config.get("frame_offsets", _authored_offsets(String(config.get("frame_directory", ""))))
	unit_sprite.frame_changed.connect(_update_unit_sprite_offset)
	unit_sprite.animation = &"move"
	unit_sprite.frame = 0
	unit_sprite.pause()
	if initial_walk_delay_frames > 0:
		var move_fps := unit_sprite.sprite_frames.get_animation_speed(&"move")
		initial_walk_delay_remaining = float(initial_walk_delay_frames) / (move_fps / ANIMATION_SPEED)
	_update_unit_sprite_offset()
	if display_height > 0.0:
		# Resizing must not lift feet off the shared ground plane.
		unit_sprite_ground_offset.y += display_height * (52.0 / 96.0) - body_anchor_offset().y
		_update_unit_sprite_offset()


static func animation_names_for(config: Dictionary) -> Array[StringName]:
	var names: Array[StringName] = [&"move", &"attack"]
	if int(config.get("death_frames", 0)) > 0:
		names.append(&"death")
	if int(config.get("skill_frames", 0)) > 0:
		names.append(&"skill")
	return names


static func animation_frame_path(config: Dictionary, animation: StringName, frame: int) -> String:
	var folder: String = config.get("%s_directory" % animation, String(animation) if animation != &"move" else "walk")
	return "%s/%s/frame_%04d.png" % [config["frame_directory"], folder, frame]


func _build_unit_sprite_frames(config: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var animation_names := animation_names_for(config)
	for row in animation_names.size():
		var animation_name := animation_names[row]
		var frame_count := int(config["%s_frames" % animation_name])
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, animation_name == &"move")
		frames.set_animation_speed(animation_name, ANIMATION_SPEED * float(config.get("%s_speed" % animation_name, 10.0 if animation_name == &"move" else 12.0)))
		for column in frame_count:
			if config.has("frame_directory"):
				var path := animation_frame_path(config, animation_name, column)
				var texture := load(path) as Texture2D
				if bool(config.get("crop_green_canvas", false)):
					texture = _crop_to_green_canvas(texture)
				frames.add_frame(animation_name, texture)
			else:
				var atlas := config["atlas"] as Texture2D
				var columns := int(config["columns"])
				var top := roundi(float(row) * atlas.get_height() / 2.0)
				var bottom := roundi(float(row + 1) * atlas.get_height() / 2.0)
				var left := roundi(float(column) * atlas.get_width() / columns)
				var right := roundi(float(column + 1) * atlas.get_width() / columns)
				var frame := AtlasTexture.new()
				frame.atlas = atlas
				frame.region = Rect2(left, top, right - left, bottom - top)
				frames.add_frame(animation_name, frame)
	return frames


func _update_unit_sprite() -> void:
	var is_attacking := attack_committed or state == State.ATTACK_WINDUP or (state == State.ATTACK_RECOVERY and attack_motion_lock_remaining > 0.0)
	var is_moving := state != State.DEAD and velocity.length_squared() > 1.0
	if is_moving:
		skill_animation_remaining = 0.0
	var is_casting := state != State.DEAD and not is_moving and (not is_attacking or unit_sprite_skill_overrides_attack) and skill_animation_remaining > 0.0
	if presented_attack_serial != attack_serial:
		sprite_was_attacking = false
		sprite_was_attack_recovery = false
		sprite_was_windup = false
		presented_attack_serial = attack_serial
	if state == State.DEAD or is_casting:
		attack_hold_raised = false
		attack_hold_lowering = false
	if state == State.DEAD and unit_sprite.sprite_frames.has_animation(&"death"):
		if unit_sprite.animation != &"death":
			unit_sprite.speed_scale = 1.0
			unit_sprite.play(&"death")
	elif is_moving:
		attack_hold_raised = false
		attack_hold_lowering = false
		if initial_walk_delay_remaining <= 0.0 and (unit_sprite.animation != &"move" or not unit_sprite.is_playing()):
			unit_sprite.speed_scale = 1.0
			unit_sprite.play(&"move")
	elif is_attacking and not is_casting:
		if unit_sprite_attack_impact_frame >= 0:
			_update_split_attack_sprite()
		elif attack_hold_frames.x >= 0:
			_update_held_attack_sprite()
		elif unit_sprite_reverses_attack_recovery:
			if state == State.ATTACK_WINDUP and not sprite_was_attacking:
				unit_sprite.speed_scale = _attack_animation_speed_scale(windup_duration)
				unit_sprite.play(&"attack")
			elif state == State.ATTACK_RECOVERY and not sprite_was_attack_recovery:
				unit_sprite.speed_scale = _attack_animation_speed_scale(state_timer)
				unit_sprite.play(&"attack", -1.0, true)
		elif not sprite_was_attacking:
			var duration := attack_motion_lock_remaining * ANIMATION_SPEED if attack_motion_lock_remaining > 0.0 else attack_animation_duration
			unit_sprite.speed_scale = _attack_animation_speed_scale(duration)
			unit_sprite.play(&"attack")
	elif is_casting:
		if unit_sprite.animation != &"skill":
			unit_sprite.speed_scale = 1.0
			unit_sprite.play(&"skill")
	elif attack_hold_frames.x >= 0 and _update_held_attack_idle():
		pass
	else:
		unit_sprite.speed_scale = 1.0
		unit_sprite.animation = &"move"
		unit_sprite.frame = 0
		unit_sprite.pause()
	unit_sprite.scale = Vector2.ONE * unit_sprite_base_scale * float(unit_sprite_animation_scales.get(unit_sprite.animation, 1.0))

	if is_casting:
		if is_instance_valid(skill_animation_target):
			var dx := skill_animation_target.position.x - position.x
			if absf(dx) > FACING_DEAD_ZONE:
				unit_sprite.flip_h = dx < 0.0
	else:
		_update_sprite_facing(is_attacking)

	var sprite_color := Color.WHITE
	if stealth_remaining > 0.0:
		sprite_color.a = 0.35
	if state == State.DEAD:
		sprite_color = sprite_color.darkened(0.25 if unit_sprite.sprite_frames.has_animation(&"death") else 0.65)
	if flash_remaining > 0.0 and not unit_sprite_uses_chroma_key and not unit_sprite_uses_alpha_shader:
		sprite_color = flash_color
	if unit_sprite_uses_chroma_key or unit_sprite_uses_alpha_shader:
		var chroma_material := unit_sprite.material as ShaderMaterial
		chroma_material.set_shader_parameter("flash_color", flash_color)
		chroma_material.set_shader_parameter("flash_amount", 1.0 if flash_remaining > 0.0 else 0.0)
		chroma_material.set_shader_parameter("burn_amount", condition_burn)
		chroma_material.set_shader_parameter("hurt_amount", condition_hurt)
		chroma_material.set_shader_parameter("pulse_phase", condition_phase)
	elif flash_remaining <= 0.0:
		sprite_color = sprite_color.lerp(Color(1.25, 0.72, 0.5, sprite_color.a), condition_burn * 0.45)
		sprite_color = sprite_color.lerp(Color(1.0, 0.6, 0.6, sprite_color.a), condition_hurt * 0.3)
	unit_sprite.modulate = sprite_color
	sprite_was_attacking = is_attacking and not is_casting and not is_moving
	sprite_was_attack_recovery = state == State.ATTACK_RECOVERY and sprite_was_attacking
	sprite_was_windup = state == State.ATTACK_WINDUP and sprite_was_attacking
	_update_unit_sprite_offset()


## Enemy windup reaches the authored impact pose when the simulation delivers the
## blow. Finish the recovery in the remaining planted interval, without changing AI.
func _update_split_attack_sprite() -> void:
	var frame_count := unit_sprite.sprite_frames.get_frame_count(&"attack")
	var impact := clampi(unit_sprite_attack_impact_frame, 0, frame_count - 1)
	var fps := unit_sprite.sprite_frames.get_animation_speed(&"attack")
	if state == State.ATTACK_WINDUP:
		if not sprite_was_attacking or unit_sprite.animation != &"attack":
			unit_sprite.play(&"attack")
			unit_sprite.frame = 0
			unit_sprite.speed_scale = float(impact + 1) / (fps * maxf(state_timer, 0.01))
		elif unit_sprite.frame >= impact:
			unit_sprite.frame = impact
			unit_sprite.pause()
	elif not sprite_was_attack_recovery or not sprite_was_attacking:
		unit_sprite.play(&"attack")
		unit_sprite.frame = impact
		unit_sprite.speed_scale = float(frame_count - impact) / (fps * maxf(attack_motion_lock_remaining, 0.05))


## Envy and Pride: the first shot raises the weapon (frames 0..hold), every next shot
## replays only the aiming part (loop_start..hold), and the weapon stays raised between
## shots. It is lowered (frames after hold) only once the Hero stops shooting.
func _update_held_attack_sprite() -> void:
	attack_hold_grace = ATTACK_HOLD_GRACE
	attack_hold_lowering = false
	var hold_frame := attack_hold_frames.y
	if (state == State.ATTACK_WINDUP and not sprite_was_windup) or not sprite_was_attacking:
		var first := attack_hold_frames.x if attack_hold_raised and unit_sprite.animation == &"attack" else 0
		var fps := unit_sprite.sprite_frames.get_animation_speed(&"attack")
		unit_sprite.speed_scale = float(hold_frame + 1 - first) / (fps * maxf(state_timer if state == State.ATTACK_WINDUP else windup_duration, 0.01))
		unit_sprite.play(&"attack")
		unit_sprite.frame = first
		attack_hold_raised = true
		if state != State.ATTACK_WINDUP:
			unit_sprite.frame = hold_frame
			unit_sprite.pause()
	elif state == State.ATTACK_RECOVERY and not sprite_was_attack_recovery:
		unit_sprite.frame = hold_frame
		unit_sprite.pause()
	else:
		_pause_on_hold_frame()


## Between shots and after the last one. Returns true while the held pose (or the
## lowering) is still showing, so the idle pose must not replace it yet.
func _update_held_attack_idle() -> bool:
	if attack_hold_raised:
		_pause_on_hold_frame()
		if attack_hold_grace > 0.0:
			return true
		attack_hold_raised = false
		if unit_sprite.animation == &"attack" and attack_hold_frames.y < unit_sprite.sprite_frames.get_frame_count(&"attack") - 1:
			unit_sprite.speed_scale = 1.0
			unit_sprite.play(&"attack")
			unit_sprite.frame = attack_hold_frames.y + 1
			attack_hold_lowering = true
			return true
		return false
	if attack_hold_lowering:
		if unit_sprite.animation == &"attack" and unit_sprite.is_playing():
			return true
		attack_hold_lowering = false
	return false


func _pause_on_hold_frame() -> void:
	if unit_sprite.animation == &"attack" and unit_sprite.frame >= attack_hold_frames.y and (unit_sprite.is_playing() or unit_sprite.frame > attack_hold_frames.y):
		unit_sprite.pause()
		unit_sprite.frame = attack_hold_frames.y


## Presentation only: casting frames must never delay effects, cooldowns or the AI.
func play_ability_animation(ability_target: Combatant, ability: AbilityDefinition, allow_passive := false) -> void:
	if state == State.DEAD or not unit_sprite.visible or ability == null or (ability.kind != AbilityDefinition.AbilityKind.ACTIVE and not allow_passive):
		return
	if not unit_sprite.sprite_frames.has_animation(&"skill"):
		return
	skill_animation_target = ability_target
	initial_walk_delay_remaining = 0.0
	skill_animation_remaining = float(unit_sprite.sprite_frames.get_frame_count(&"skill")) / unit_sprite.sprite_frames.get_animation_speed(&"skill")
	unit_sprite.speed_scale = 1.0
	unit_sprite.stop()
	unit_sprite.play(&"skill")
	_update_unit_sprite()


## Moving units face their travel direction; stationary attacks face their locked
## target. Retreating is a walk away, never a sliding attack pose.
func _update_sprite_facing(is_attacking: bool) -> void:
	if state == State.DEAD:
		return
	if velocity.length_squared() > 1.0:
		if absf(velocity.x) > FACING_MIN_SPEED:
			unit_sprite.flip_h = velocity.x < 0.0
		return
	var threat := committed_attack_target if attack_committed else target
	if not is_attacking:
		threat = target
	if is_instance_valid(threat):
		var dx := threat.position.x - position.x
		if absf(dx) > FACING_DEAD_ZONE:
			unit_sprite.flip_h = dx < 0.0
		return


func _update_unit_sprite_offset() -> void:
	var offset := _sprite_offset_from(unit_sprite_frame_offsets)
	var legacy_offset := _sprite_offset_from(unit_sprite_legacy_offsets) if unit_sprite_legacy_offsets != unit_sprite_frame_offsets else offset
	var anchor_correction := _scaled_animation_anchor_correction(offset)
	if unit_sprite.flip_h:
		offset.x = -offset.x
		legacy_offset.x = -legacy_offset.x
		anchor_correction.x = -anchor_correction.x
	unit_sprite.position = offset * unit_sprite.scale + unit_sprite_ground_offset + anchor_correction
	unit_sprite_legacy_position = legacy_offset * unit_sprite.scale + unit_sprite_ground_offset + anchor_correction


## Canvas scale compensation must not lift or shift the standing body anchor.
## These tables are premeasured; no image scanning is needed during playback.
func _scaled_animation_anchor_correction(authored_offset: Vector2) -> Vector2:
	if not unit_sprite_animation_scales.has(unit_sprite.animation):
		return Vector2.ZERO
	var anchors: Array = unit_sprite_frame_offsets.get(StringName(String(unit_sprite.animation) + "_anchor"), [])
	var move_anchors: Array = unit_sprite_frame_offsets.get(&"move_anchor", [])
	var move_offsets: Array = unit_sprite_frame_offsets.get(&"move", [])
	if unit_sprite.frame >= anchors.size() or move_anchors.is_empty() or move_offsets.is_empty():
		return Vector2.ZERO
	var frames := unit_sprite.sprite_frames
	var standing_anchor: Vector2 = move_anchors[0] - frames.get_frame_texture(&"move", 0).get_size() * 0.5 + move_offsets[0]
	var current_anchor: Vector2 = anchors[unit_sprite.frame] - frames.get_frame_texture(unit_sprite.animation, unit_sprite.frame).get_size() * 0.5 + authored_offset
	var standing_scale := unit_sprite_base_scale * float(unit_sprite_animation_scales.get(&"move", 1.0))
	return standing_anchor * standing_scale - current_anchor * unit_sprite.scale


func _sprite_offset_from(offset_table: Dictionary) -> Vector2:
	var offsets: Array = offset_table.get(unit_sprite.animation, [])
	if unit_sprite.frame < offsets.size():
		return offsets[unit_sprite.frame]
	if unit_sprite_uses_chroma_key:
		var offset_frame := 0 if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO and unit_sprite.animation == &"attack" else unit_sprite.frame
		var texture := unit_sprite.sprite_frames.get_frame_texture(unit_sprite.animation, offset_frame)
		return _chroma_frame_offset(texture)
	return Vector2.ZERO


static func _authored_offsets(frame_directory: String) -> Dictionary:
	if frame_directory.is_empty():
		return {}
	if not authored_frame_offsets_loaded:
		authored_frame_offsets_loaded = true
		for path in [FRAME_OFFSETS_PATH, ALLIED_FRAME_OFFSETS_PATH, ENEMY_FRAME_OFFSETS_PATH]:
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed = JSON.parse_string(file.get_as_text())
				if parsed is Dictionary:
					for directory in parsed:
						var animations := {}
						for animation_name in parsed[directory]:
							var offsets: Array[Vector2] = []
							for pair in parsed[directory][animation_name]:
								offsets.append(Vector2(float(pair[0]), float(pair[1])))
							animations[StringName(animation_name)] = offsets
						authored_frame_offsets[String(directory)] = animations
	return authored_frame_offsets.get(frame_directory, {})


## Screen-space position of the body anchor for the current frame, relative to the unit.
## Used by tests to verify that walking and attacking keep the body planted.
func body_anchor_offset() -> Vector2:
	var directory := String(UNIT_ANIMATION_CONFIGS.get(snapshot.definition_id, UNIT_ANIMATION_CONFIGS.get(snapshot.job_id, {})).get("frame_directory", ""))
	var offsets: Array = unit_sprite_frame_offsets.get(unit_sprite.animation, [])
	if directory.is_empty() or unit_sprite.frame >= offsets.size():
		return unit_sprite.position
	var anchors: Array = unit_sprite_frame_offsets.get(StringName(String(unit_sprite.animation) + "_anchor"), [])
	if unit_sprite.frame >= anchors.size():
		return unit_sprite.position
	var texture := unit_sprite.sprite_frames.get_frame_texture(unit_sprite.animation, unit_sprite.frame)
	var half := texture.get_size() * 0.5
	var anchor_offset := Vector2(anchors[unit_sprite.frame]) - half
	if unit_sprite.flip_h:
		anchor_offset.x = -anchor_offset.x
	return anchor_offset * unit_sprite.scale + unit_sprite.position


func _chroma_frame_offset(texture: Texture2D) -> Vector2:
	var cache_key: Variant = texture.resource_path if not texture.resource_path.is_empty() else texture.get_instance_id()
	if chroma_frame_offsets.has(cache_key):
		return chroma_frame_offsets[cache_key]
	var image := texture.get_image()
	var weighted_position := Vector2.ZERO
	var sample_count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.g - maxf(color.r, color.b) < 0.08:
				weighted_position += Vector2(x, y)
				sample_count += 1
	var visual_center := weighted_position / sample_count if sample_count > 0 else Vector2(image.get_size()) * 0.5
	var offset := Vector2(image.get_size()) * 0.5 - visual_center
	chroma_frame_offsets[cache_key] = offset
	return offset


func _crop_to_green_canvas(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	var width := image.get_width()
	var height := image.get_height()
	var top := 0
	var bottom := height - 1
	var required_green_samples := ceili(float(width) / 8.0)
	for y in range(0, height, 2):
		var green_samples := 0
		for x in range(0, width, 4):
			var color := image.get_pixel(x, y)
			if color.g - maxf(color.r, color.b) >= 0.08:
				green_samples += 1
		if green_samples >= required_green_samples:
			top = y
			break
	for y in range(height - 1, -1, -2):
		var green_samples := 0
		for x in range(0, width, 4):
			var color := image.get_pixel(x, y)
			if color.g - maxf(color.r, color.b) >= 0.08:
				green_samples += 1
		if green_samples >= required_green_samples:
			bottom = y
			break
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(0.0, float(top), float(width), float(bottom - top + 1))
	return cropped


func _acquire_target() -> void:
	if attack_committed:
		return
	if _has_forced_basic_target():
		target = forced_basic_target
		basic_attack_target_active = true
		pending_ability = null
		velocity = Vector2.ZERO
		state = State.MOVE_INTO_RANGE
		return
	if _try_use_ability():
		return
	target = session.find_basic_attack_target(self)
	basic_attack_target_active = is_instance_valid(target)
	velocity = Vector2.ZERO
	state = State.MOVE_INTO_RANGE if is_instance_valid(target) else State.IDLE


func _move_toward_target(delta: float) -> void:
	if attack_committed:
		_stop_navigation()
		return
	if snapshot.attack_type == &"ranged" and snapshot.avoids_damage and (ranged_retreat_active or ranged_retreat_pending):
		_move_ranged_during_recovery(delta)
		if ranged_retreat_active:
			return
	if not _has_valid_target():
		pending_ability = null
		state = State.ACQUIRE_TARGET
		_stop_navigation()
		return

	var offset := target.position - position
	var distance := offset.length()
	var attack_range := basic_attack_reach(target)
	if pending_ability != null and pending_ability.cast_range > 0.0:
		attack_range = pending_ability.cast_range + body_radius + target.body_radius

	var basic_move := pending_ability == null
	if approach_target != target or not is_equal_approx(approach_reach, attack_range):
		approach_committed = false
	var reached_position := position.distance_squared_to(approach_goal) <= MOVEMENT_ARRIVAL_DISTANCE * MOVEMENT_ARRIVAL_DISTANCE
	if distance <= attack_range and (not basic_move or is_basic_attack_side_position(target, position)) and (snapshot.attack_type == &"ranged" or not basic_move or not approach_committed or reached_position or distance <= attack_range - 4.0 or is_rooted()):
		if pending_ability == null and targets_farthest_enemy:
			target = session.find_basic_attack_target(self)
		approach_committed = false
		_stop_navigation()
		if pending_ability != null:
			_start_ability_windup()
		else:
			_start_attack()
		return
	if is_rooted():
		_stop_navigation()
		return

	if basic_move:
		_ensure_approach_goal(attack_range)
		approach_committed = true
		_move_to_navigation_point(approach_goal, delta, target if snapshot.attack_type == &"melee" else null)
	else:
		_move_to_navigation_point(target.position, delta)


func personal_space_radius() -> float:
	var radius := 44.0
	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON:
		radius = 24.0
	elif snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
		radius = 52.0
	elif snapshot.is_boss:
		radius = 56.0
	return maxf(body_radius, radius * body_radius / maxf(base_body_radius, 0.01))


func _ensure_approach_goal(reach: float) -> void:
	var same_target := approach_target == target
	var goal_distance := approach_goal.distance_to(target.position)
	if (
		same_target and is_equal_approx(approach_reach, reach)
		and approach_target_position.distance_squared_to(target.position) <= MOVEMENT_REPLAN_DISTANCE * MOVEMENT_REPLAN_DISTANCE
		and goal_distance >= body_radius + target.body_radius - 0.1
		and goal_distance <= maxf(reach - 4.0, body_radius + target.body_radius)
		and is_basic_attack_side_position(target, approach_goal)
		and ARENA_GEOMETRY.contains(approach_goal, arena_bounds, body_radius)
	):
		return
	if snapshot.attack_type == &"melee":
		var choice: Dictionary = session.melee_approach_position(self, target, approach_slot_index if same_target else -1)
		approach_goal = choice.position
		approach_slot_index = int(choice.slot)
	else:
		var away := (position - target.position).normalized()
		if away.is_zero_approx():
			away = Vector2.LEFT if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
		approach_goal = _clamp_navigation_point(target.position + away * maxf(body_radius + target.body_radius, reach - APPROACH_INSET))
		approach_slot_index = -1
	approach_target = target
	approach_target_position = target.position
	approach_reach = reach
	var cross := (position - target.position).cross(approach_goal - target.position)
	approach_arc_side = signf(cross) if absf(cross) > 0.01 else _navigation_side()


func _navigation_side() -> float:
	return -1.0 if String(snapshot.runtime_id).hash() % 2 == 0 else 1.0


func _clamp_navigation_point(point: Vector2) -> Vector2:
	return ARENA_GEOMETRY.clamp_point(point, arena_bounds, body_radius)


func _stop_navigation() -> void:
	velocity = Vector2.ZERO
	steering_direction = Vector2.ZERO
	steering_recheck_remaining = 0.0


func _move_to_navigation_point(goal: Vector2, delta: float, avoid_target: Combatant = null) -> void:
	goal = _clamp_navigation_point(goal)
	var destination := goal
	# Extra clearance keeps corner waypoints away from wall collision epsilon.
	goal = ARENA_GEOMETRY.next_waypoint(position, goal, arena_bounds, body_radius + 1.0)
	var routing := goal.distance_squared_to(destination) > 4.0
	var offset := goal - position
	var distance := offset.length()
	var arrival_distance := 0.001 if routing else MOVEMENT_ARRIVAL_DISTANCE
	if is_instance_valid(avoid_target) and distance <= arrival_distance:
		# A cached goal can still be valid after a small target movement while
		# our arrival circle extends past attack reach. Stopping there deadlocks
		# MOVE_INTO_RANGE: neither an attack nor the stuck timer can advance.
		var within_reach := position.distance_to(avoid_target.position) <= basic_attack_reach(avoid_target)
		if not within_reach or not is_basic_attack_side_position(avoid_target, position):
			arrival_distance = 0.1
	if distance <= arrival_distance or delta <= 0.0:
		_stop_navigation()
		return
	var direction := offset / distance
	# Walk around an opponent to reach a reserved sector, rather than bulldozing
	# through its centre to get to the other side.
	if is_instance_valid(avoid_target):
		var radial := position - avoid_target.position
		var obstacle_radius := maxf(0.0, body_radius + avoid_target.body_radius - 0.5)
		var closest := Geometry2D.get_closest_point_to_segment(avoid_target.position, position, goal)
		if radial.length() < approach_reach + 24.0 and closest.distance_squared_to(avoid_target.position) < obstacle_radius * obstacle_radius:
			var outward := radial.normalized()
			var tangent := Vector2(-outward.y, outward.x) * approach_arc_side
			var ring := maxf(body_radius + avoid_target.body_radius, approach_reach - APPROACH_INSET)
			var correction := clampf((radial.length() - ring) / maxf(ring, 1.0), -0.5, 0.6)
			direction = (tangent - outward * correction).normalized()
	var separation: Vector2 = session.get_separation_vector(self)
	# Near the chosen destination, soften avoidance so neighbours cannot prevent
	# arrival forever. Stationary attacks never use this soft steering.
	separation *= minf(1.0, distance / 40.0)
	var desired := direction + separation * 0.8
	if separation.dot(direction) < -0.1:
		var side := signf(direction.cross(separation))
		if is_zero_approx(side):
			side = _navigation_side()
		desired += Vector2(-direction.y, direction.x) * side * separation.length() * 0.65
	desired = desired.normalized()
	steering_recheck_remaining = maxf(0.0, steering_recheck_remaining - delta)
	if steering_direction.is_zero_approx() or steering_recheck_remaining <= 0.0 or steering_goal.distance_squared_to(goal) > 24.0 * 24.0 or steering_direction.dot(desired) < 0.5:
		steering_direction = desired
		steering_goal = goal
		steering_recheck_remaining = STEERING_INTERVAL
	velocity = steering_direction * minf(get_effective_stat(&"movement_speed"), distance / delta)
	var before := position
	_slide(delta)
	position = _clamp_navigation_point(position)
	velocity = (position - before) / delta
	_update_stuck_state(delta)


func _start_attack() -> void:
	if attack_committed:
		return
	if not is_instance_valid(target) or not is_basic_attack_side_position(target, position):
		state = State.MOVE_INTO_RANGE
		return
	approach_committed = false
	_stop_navigation()
	basic_attack_target_active = true
	pending_ability = _ready_basic_replacement()
	committed_attack_target = target
	committed_attack_ability = pending_ability
	attack_committed = true
	attack_serial += 1
	initial_walk_delay_remaining = 0.0
	state = State.ATTACK_WINDUP
	if snapshot.attack_type == &"ranged" and not snapshot.is_boss:
		windup_duration = RANGED_ATTACK_PAUSE
	else:
		windup_duration = 0.65 if snapshot.is_boss else minf(0.35, 0.25 / maxf(get_effective_stat(&"attack_speed"), 0.01))
	state_timer = windup_duration
	committed_windup_remaining = windup_duration
	attack_animation_duration = _current_attack_cycle_duration()
	attack_motion_lock_remaining = maxf(windup_duration, attack_animation_duration * ATTACK_SWING_FRACTION)
	queue_redraw()
	session.record_event(
		CombatEvent.ATTACK_STARTED,
		snapshot.runtime_id,
		target.snapshot.runtime_id,
		pending_ability.id if pending_ability != null else &"attack.basic",
		pending_ability.id if pending_ability != null else &"attack.basic"
	)


func _start_ability_windup() -> void:
	if attack_committed:
		return
	approach_committed = false
	_stop_navigation()
	attack_serial += 1
	state = State.ATTACK_WINDUP
	windup_duration = 0.55 if snapshot.is_boss else 0.2
	state_timer = windup_duration
	attack_animation_duration = _current_attack_cycle_duration()
	queue_redraw()


func _current_attack_cycle_duration() -> float:
	var attack_interval := 1.0 / maxf(get_effective_stat(&"attack_speed"), 0.01)
	var minimum_recovery := 0.0 if snapshot.attack_type == &"ranged" else 0.05
	return windup_duration + maxf(minimum_recovery, attack_interval - windup_duration)


## Speed that plays frame_count attack frames (all by default) in playback_duration,
## sped up by ANIMATION_SPEED: the swing finishes early and rests on its last frame.
func _attack_animation_speed_scale(playback_duration: float, frame_count := -1) -> float:
	if playback_duration <= 0.0:
		return 1.0
	if frame_count <= 0:
		frame_count = unit_sprite.sprite_frames.get_frame_count(&"attack")
	# The frames already play ANIMATION_SPEED times faster than authored.
	var fps := unit_sprite.sprite_frames.get_animation_speed(&"attack")
	var duration_at_fps := float(frame_count) / maxf(fps, 0.01)
	return ANIMATION_SPEED * duration_at_fps / playback_duration


## Basic/replacement melee swings start only in the lateral fans. This is never
## rechecked during a committed swing, so moving targets cannot cancel a hit.
func is_basic_attack_side_position(other: Combatant, point: Vector2) -> bool:
	if snapshot.attack_type != &"melee":
		return true
	if not is_instance_valid(other):
		return false
	var offset := point - other.position
	return absf(offset.x) > 0.01 and absf(offset.y) <= absf(offset.x) * 0.6


func basic_attack_reach(other: Combatant) -> float:
	if not is_instance_valid(other):
		return get_effective_stat(&"attack_range") + body_radius
	return get_effective_stat(&"attack_range") + body_radius + other.body_radius


func basic_projectile_origin(projectile_target: Combatant) -> Vector2:
	var animation_id := snapshot.job_id if UNIT_ANIMATION_CONFIGS.has(snapshot.job_id) else snapshot.definition_id
	var config: Dictionary = UNIT_ANIMATION_CONFIGS.get(animation_id, {})
	if config.has("projectile_tip") and unit_sprite.sprite_frames != null:
		return _calibrated_projectile_origin(config, projectile_target)
	if not HERO_PROJECTILE_TIPS.has(snapshot.definition_id) or not unit_sprite.visible:
		return position
	if HERO_PROJECTILE_FRAME_TIPS.has(snapshot.definition_id) and unit_sprite.animation == &"attack":
		var tips: Array = HERO_PROJECTILE_FRAME_TIPS[snapshot.definition_id]
		var frame := clampi(unit_sprite.frame, 0, tips.size() - 1)
		var texture_size := unit_sprite.sprite_frames.get_frame_texture(&"attack", frame).get_size()
		var drawn_tip: Vector2 = (Vector2(tips[frame]) - texture_size * 0.5) * unit_sprite.scale
		var sprite_position := unit_sprite.position
		var aims_left := projectile_target.position.x < position.x
		# The Hero turns toward the target before shooting: mirror if it is not drawn so yet.
		if unit_sprite.flip_h != aims_left:
			sprite_position.x = -sprite_position.x
		if aims_left:
			drawn_tip.x = -drawn_tip.x
		return position + sprite_position + drawn_tip
	var faces_left := projectile_target.position.x < position.x
	var sprite_anchor := Vector2(absf(unit_sprite_legacy_position.x) * (-1.0 if faces_left else 1.0), unit_sprite_legacy_position.y)
	var local_tip: Vector2 = HERO_PROJECTILE_TIPS[snapshot.definition_id] * unit_sprite.scale
	if faces_left:
		local_tip.x = -local_tip.x
	return position + sprite_anchor + local_tip


## Sample an authored release pose, never the renderer's current frame/facing.
## Live battles and manual/headless simulation therefore launch identical shots.
func _calibrated_projectile_origin(config: Dictionary, projectile_target: Combatant) -> Vector2:
	var frame := int(config.get("projectile_frame", config.get("attack_impact_frame", 0)))
	var texture := unit_sprite.sprite_frames.get_frame_texture(&"attack", frame)
	var offsets: Array = unit_sprite_frame_offsets.get(&"attack", [])
	var offset: Vector2 = offsets[frame] if frame < offsets.size() else Vector2.ZERO
	var scale := unit_sprite_base_scale * float(unit_sprite_animation_scales.get(&"attack", 1.0))
	var local: Vector2 = (Vector2(config.projectile_tip) - texture.get_size() * 0.5 + offset) * scale + unit_sprite_ground_offset
	if is_instance_valid(projectile_target) and projectile_target.position.x < position.x:
		local.x = -local.x
	var origin := position + local
	if is_instance_valid(projectile_target):
		var direction := (projectile_target.position - position).normalized()
		var distance := position.distance_to(projectile_target.position)
		var forward := local.dot(direction)
		if forward > distance and forward > 0.01:
			# Avoid a backwards flight when the target overlaps the extended weapon.
			origin = position + local * maxf(0.0, distance - projectile_target.body_radius * 0.25) / forward
	return origin


func _update_attack_windup(delta: float) -> void:
	if not attack_committed and state != State.ATTACK_WINDUP:
		return
	velocity = Vector2.ZERO
	var committed := attack_committed
	if committed:
		state = State.ATTACK_WINDUP
		target = committed_attack_target
		pending_ability = committed_attack_ability
	if snapshot.is_boss:
		queue_redraw()
	if not committed and not _has_valid_target():
		pending_ability = null
		state = State.ACQUIRE_TARGET
		return

	if not committed and pending_ability != null and pending_ability.cast_range > 0.0:
		var allowed_distance := pending_ability.cast_range + body_radius + target.body_radius
		if position.distance_to(target.position) > allowed_distance * 1.25:
			state = State.MOVE_INTO_RANGE
			return
	elif not committed and snapshot.attack_type == &"melee":
		if position.distance_to(target.position) > basic_attack_reach(target) + 0.01:
			state = State.MOVE_INTO_RANGE
			return

	if committed:
		committed_windup_remaining -= delta
		state_timer = committed_windup_remaining
	else:
		state_timer -= delta
	if state_timer > 0.0:
		return
	var hit_allowed := _has_valid_target()
	if committed:
		hit_allowed = is_instance_valid(target) and target.is_targetable() and (target.snapshot.team != snapshot.team or (frenzy_remaining > 0.0 and target != self))
		attack_committed = false
		committed_attack_target = null
		committed_attack_ability = null

	if pending_ability != null:
		var used_ability := pending_ability
		pending_ability = null
		ability_cooldowns[used_ability.id] = cooldown_for(used_ability)
		if hit_allowed:
			session.deliver_ability(self, target, used_ability)
		if used_ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
			prefers_farthest_enemy = false
	elif hit_allowed and snapshot.attack_type == &"ranged":
		session.spawn_projectile(self, target, get_effective_stat(&"damage"))
		prefers_farthest_enemy = false
	elif hit_allowed:
		var attack_target := target
		var raw_damage := get_effective_stat(&"damage") + _focused_damage_bonus(attack_target)
		session.spawn_hit_vfx(self, attack_target.position, (attack_target.position - position).normalized())
		var damage_dealt := attack_target.take_damage(raw_damage, self, &"attack.basic", &"attack.basic", true)
		prefers_farthest_enemy = false
		_add_focused_damage_stack(attack_target)
		apply_basic_attack_lifesteal(damage_dealt)
		record_successful_basic_hit(attack_target, damage_dealt)
		if ground_slam_damage_multiplier > 0.0:
			session.apply_ground_slam(
				self,
				attack_target.position,
				get_effective_stat(&"damage") * ground_slam_damage_multiplier,
				ground_slam_radius,
				ground_slam_ability_id,
				ground_slam_effect_id
			)
			ground_slam_damage_multiplier = 0.0
			ground_slam_radius = 0.0

	if state == State.DEAD:
		return
	state = State.ATTACK_RECOVERY
	var attack_interval := 1.0 / maxf(get_effective_stat(&"attack_speed"), 0.01)
	state_timer = maxf(0.0 if snapshot.attack_type == &"ranged" else 0.05, attack_interval - windup_duration)
	queue_redraw()


func _update_attack_recovery(delta: float) -> void:
	state_timer = maxf(0.0, state_timer - delta)
	if attack_motion_lock_remaining > 0.0:
		_stop_navigation()
		return
	if snapshot.attack_type == &"ranged" and snapshot.avoids_damage:
		_move_ranged_during_recovery(delta)
	else:
		velocity = Vector2.ZERO
	if state == State.ATTACK_RECOVERY and state_timer <= 0.0 and not ranged_retreat_active:
		_stop_navigation()
		state = State.ACQUIRE_TARGET


func _move_ranged_during_recovery(delta: float) -> void:
	ranged_retreat_retry_remaining = maxf(0.0, ranged_retreat_retry_remaining - delta)
	if is_rooted():
		_finish_ranged_retreat()
		_stop_navigation()
		return
	var threat := ranged_retreat_source
	if not is_instance_valid(threat) or not threat.is_targetable() or threat.snapshot.team == snapshot.team:
		ranged_retreat_source = null
		ranged_retreat_pending = false
		threat = target if _has_valid_target() and target.snapshot.team != snapshot.team else null
	if not is_instance_valid(threat):
		ranged_retreat_active = false
		_stop_navigation()
		state = State.ACQUIRE_TARGET
		return
	var offset := threat.position - position
	var distance := offset.length()
	var direction := offset.normalized()
	var attack_range := get_effective_stat(&"attack_range")
	var safe_distance := attack_range * RANGED_RETREAT_END
	if threat.snapshot.attack_type == &"melee":
		safe_distance = maxf(safe_distance, threat.basic_attack_reach(self) + 16.0)
	safe_distance = minf(safe_distance, basic_attack_reach(threat) - MOVEMENT_ARRIVAL_DISTANCE)
	if ranged_retreat_target != threat:
		ranged_retreat_active = false
		ranged_retreat_retry_remaining = 0.0
		ranged_retreat_target = threat
	if ranged_retreat_pending and distance >= safe_distance:
		ranged_retreat_pending = false
		ranged_retreat_source = null
	if ranged_retreat_active:
		var remaining_distance := position.distance_to(ranged_retreat_destination)
		if remaining_distance + 4.0 < ranged_retreat_best_distance:
			ranged_retreat_best_distance = remaining_distance
			ranged_retreat_stuck_time = 0.0
		else:
			ranged_retreat_stuck_time += delta
		if ranged_retreat_stuck_time >= 0.6:
			_finish_ranged_retreat()
			_stop_navigation()
			return
		if distance >= safe_distance or position.distance_squared_to(ranged_retreat_destination) <= MOVEMENT_ARRIVAL_DISTANCE * MOVEMENT_ARRIVAL_DISTANCE:
			_finish_ranged_retreat()
			_stop_navigation()
			return
		# Reconsider a retreat only for a substantial threat change, not tiny jitter.
		if (ranged_retreat_destination - position).normalized().dot(-direction) < 0.1:
			_plan_ranged_retreat(direction, distance, attack_range, safe_distance)
	elif (ranged_retreat_pending or distance < attack_range * RANGED_RETREAT_START) and ranged_retreat_retry_remaining <= 0.0:
		_plan_ranged_retreat(direction, distance, attack_range, safe_distance)
	if ranged_retreat_active:
		approach_committed = false
		_move_to_navigation_point(ranged_retreat_destination, delta)
	elif _has_valid_target() and position.distance_to(target.position) > basic_attack_reach(target) + MOVEMENT_ARRIVAL_DISTANCE:
		_ensure_approach_goal(basic_attack_reach(target))
		approach_committed = true
		_move_to_navigation_point(approach_goal, delta)
	else:
		_stop_navigation()


func _plan_ranged_retreat(direction: Vector2, distance: float, attack_range: float, safe_distance := -1.0) -> void:
	if safe_distance < 0.0:
		safe_distance = attack_range * RANGED_RETREAT_END
	var retreat_distance := maxf(48.0, safe_distance - distance + 16.0)
	ranged_retreat_destination = _clamp_navigation_point(position - direction * retreat_distance)
	ranged_retreat_active = position.distance_squared_to(ranged_retreat_destination) > MOVEMENT_ARRIVAL_DISTANCE * MOVEMENT_ARRIVAL_DISTANCE
	if ranged_retreat_active:
		ranged_retreat_best_distance = position.distance_to(ranged_retreat_destination)
		ranged_retreat_stuck_time = 0.0
	else:
		_finish_ranged_retreat()


func _finish_ranged_retreat() -> void:
	ranged_retreat_active = false
	ranged_retreat_pending = false
	ranged_retreat_source = null
	ranged_retreat_target = target if _has_valid_target() else null
	ranged_retreat_retry_remaining = 0.35
	ranged_retreat_stuck_time = 0.0
	ranged_retreat_best_distance = INF


func is_attack_motion_locked() -> bool:
	return attack_committed or state == State.ATTACK_WINDUP or attack_motion_lock_remaining > 0.0


func take_damage(
	raw_damage: float,
	source: Combatant,
	ability_id: StringName = &"attack.basic",
	effect_id: StringName = &"attack.basic",
	is_melee := false,
	allow_source_lifesteal := true,
	allow_redirect := true
) -> float:
	if not is_targetable():
		return 0.0
	if despair_sanctuary_remaining > 0.0 and is_instance_valid(source) and source.snapshot.team != snapshot.team:
		return 0.0
	if is_invulnerable():
		return 0.0
	if session.should_dodge(self, ability_id == &"attack.basic"):
		return 0.0
	if ability_id == &"attack.basic" and is_instance_valid(source):
		raw_damage = session.get_basic_attack_damage(source, raw_damage)
		raw_damage = source.roll_critical_damage(raw_damage)
	raw_damage *= maxf(0.0, 1.0 + get_effective_stat(&"damage_taken") / 100.0)
	if allow_redirect and is_instance_valid(source) and source.snapshot.team != snapshot.team:
		var redirector: Combatant = session.find_damage_redirector(self)
		if redirector != null:
			var redirected := raw_damage * redirector.items.redirect_percent / 100.0
			raw_damage -= redirected
			var taken := redirector.take_damage(redirected, source, redirector.items.redirect_ability_id, redirector.items.redirect_effect_id, false, false, false)
			if taken > 0.0 and redirector.is_alive():
				redirector.receive_healing(taken * redirector.items.redirect_heal_percent / 100.0, redirector, redirector.items.redirect_ability_id, redirector.items.redirect_effect_id)

	var armor := get_effective_stat(&"armor")
	if is_instance_valid(source):
		armor *= 1.0 - source.get_effective_stat(&"armor_penetration") / 100.0
	var applied_damage := CombatRules.calculate_damage(raw_damage, armor)
	var absorbed_damage := 0.0
	for shield in shields:
		if applied_damage <= 0.0:
			break
		var absorbed := minf(applied_damage, float(shield.amount))
		shield.amount = float(shield.amount) - absorbed
		applied_damage -= absorbed
		absorbed_damage += absorbed
	shields = shields.filter(func(shield: Dictionary) -> bool: return float(shield.amount) > 0.0)
	applied_damage = minf(applied_damage, current_hp)
	current_hp = maxf(0.0, current_hp - applied_damage)
	if absorbed_damage + applied_damage > 0.0:
		last_damage_taken_time = session.elapsed_time
		_trigger_flash(damage_flash_color, damage_flash_duration, DAMAGE_FLASH_PRIORITY)
		_apply_damage_knockback(source, absorbed_damage + applied_damage)
	if applied_damage > 0.0:
		_remove_hp_damage_break_statuses()
	last_damage_source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	last_effect_id = effect_id
	session.record_event(
		CombatEvent.DAMAGE_APPLIED,
		last_damage_source_id,
		snapshot.runtime_id,
		ability_id,
		effect_id,
		applied_damage
	)
	if applied_damage > 0.0 and is_instance_valid(source) and source != self:
		if allow_source_lifesteal:
			source.apply_all_damage_lifesteal(applied_damage)
		if source.snapshot.team != snapshot.team:
			source.record_enemy_damage_dealt()
			if ability_id == &"attack.basic":
				_gain_gluttony_regeneration_stack()
				_reflect_basic_attack_damage(source, applied_damage)
	queue_redraw()
	if applied_damage > 0.0 and is_melee and is_instance_valid(source) and source.snapshot.team != snapshot.team:
		_try_melee_teleport(source)
		if melee_retaliation_multiplier > 0.0:
			session.trigger_melee_retaliation(self, source, melee_retaliation_radius, melee_retaliation_multiplier, melee_retaliation_ability_id, melee_retaliation_effect_id)
		if source.is_targetable() and snapshot.avoids_damage and snapshot.attack_type == &"melee" and source.snapshot.attack_type == &"melee":
			_start_melee_retreat(source)
	if applied_damage > 0.0 and current_hp > 0.0:
		_try_threshold_guard()
	if absorbed_damage + applied_damage > 0.0 and current_hp > 0.0:
		items.on_damage_taken(absorbed_damage + applied_damage, source)
	if current_hp > 0.0:
		_update_boss_phase()
	if current_hp <= 0.0:
		var duration: float = session.get_last_stand_duration(self)
		if duration > 0.0:
			last_stand_remaining = duration
			target = null
			state = State.ACQUIRE_TARGET
		else:
			_die(source)
	return applied_damage


func receive_healing(
	amount: float,
	source: Combatant,
	ability_id: StringName,
	effect_id: StringName
) -> float:
	if not is_targetable():
		return 0.0
	var missing_health := maxf(0.0, get_effective_stat(&"max_hp") - current_hp)
	var applied_healing := minf(maxf(amount, 0.0), missing_health)
	current_hp += applied_healing
	if applied_healing > 0.0:
		_trigger_flash(healing_flash_color, healing_flash_duration, HEALING_FLASH_PRIORITY)
	session.record_event(
		CombatEvent.HEALING_APPLIED,
		source.snapshot.runtime_id if is_instance_valid(source) else "",
		snapshot.runtime_id,
		ability_id,
		effect_id,
		applied_healing
	)
	queue_redraw()
	return applied_healing


func _trigger_flash(color: Color, duration: float, priority: int) -> void:
	var requested_duration := maxf(duration, 0.0)
	if requested_duration <= 0.0 or (flash_remaining > 0.0 and priority < flash_priority):
		return
	flash_color = color
	flash_color.a = 1.0
	flash_remaining = requested_duration
	flash_priority = priority
	queue_redraw()


func _update_flash(delta: float) -> void:
	if flash_remaining <= 0.0:
		return
	flash_remaining = maxf(0.0, flash_remaining - delta)
	if flash_remaining <= 0.0:
		flash_priority = 0
	queue_redraw()


## Distance a hit of the given size pushes this unit: heavy blows relative to the
## unit's Max HP shove it far, chip damage barely moves it.
func damage_knockback_for(damage: float) -> float:
	var max_hp := maxf(get_effective_stat(&"max_hp"), 1.0)
	var share_percent := maxf(damage, 0.0) / max_hp * 100.0
	return minf(damage_knockback_distance * share_percent / damage_knockback_reference_percent, damage_knockback_max_distance)


func _apply_damage_knockback(source: Combatant, damage: float) -> void:
	if damage_knockback_distance <= 0.0 or not is_instance_valid(source) or source == self:
		return
	var distance := damage_knockback_for(damage)
	if distance < 0.5:
		return
	var direction := (position - source.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT if snapshot.runtime_id > source.snapshot.runtime_id else Vector2.LEFT
	position = ARENA_GEOMETRY.move_point(position, position + direction * distance, arena_bounds, body_radius)


func is_alive() -> bool:
	return not temporarily_removed and state != State.DEAD and (current_hp > 0.0 or last_stand_remaining > 0.0)


func is_targetable() -> bool:
	return not temporarily_removed and state != State.DEAD and current_hp > 0.0


func can_be_targeted_by(requester: Combatant) -> bool:
	if not is_targetable():
		return false
	if despair_sanctuary_remaining > 0.0 and is_instance_valid(requester) and requester.snapshot.team != snapshot.team:
		return false
	return stealth_remaining <= 0.0 or not is_instance_valid(requester) or requester.snapshot.team == snapshot.team


func can_receive_effect_from(source: Combatant) -> bool:
	return is_targetable() and not (despair_sanctuary_remaining > 0.0 and is_instance_valid(source) and source.snapshot.team != snapshot.team)


func apply_stealth(duration: float, ability_id: StringName = &"", effect_id: StringName = &"") -> void:
	stealth_remaining = maxf(stealth_remaining, duration)
	stealth_ability_id = ability_id
	stealth_effect_id = effect_id
	target = null
	queue_redraw()


func set_simulation_active(value: bool) -> void:
	simulation_active = value and not temporarily_removed
	if not value:
		velocity = Vector2.ZERO


func set_temporarily_removed(value: bool) -> void:
	temporarily_removed = value
	visible = not value
	velocity = Vector2.ZERO
	target = null
	pending_ability = null
	basic_attack_target_active = false
	state_timer = 0.0
	if value:
		attack_committed = false
		attack_motion_lock_remaining = 0.0
		committed_attack_target = null
		committed_attack_ability = null
		simulation_active = false
	else:
		state = State.ACQUIRE_TARGET
		simulation_active = session != null and session.battle_active


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func get_effective_stat(stat: StringName) -> float:
	return _calculate_effective_stat(stat)


func get_stat_breakdown(stat: StringName) -> Dictionary:
	var entries := snapshot.stats.breakdown_for(stat)
	var snapshot_value := float(snapshot.stats.get(stat))
	if entries.is_empty():
		entries.append({"source": "Snapshot base", "operation": &"base", "operand": snapshot_value, "before": 0.0, "after": snapshot_value})
	elif not is_equal_approx(float(entries[-1].after), snapshot_value):
		entries.append({"source": "Combat stat changes", "operation": &"set", "operand": snapshot_value, "before": float(entries[-1].after), "after": snapshot_value})
	return {"value": _calculate_effective_stat(stat, entries), "entries": entries}


func _calculate_effective_stat(stat: StringName, entries = null) -> float:
	var value := float(snapshot.stats.get(stat))
	if stat == &"attack_range":
		var before := value
		value += basic_attack_range_bonus
		if entries != null:
			_record_stat_step(entries, "Ability: attack range bonus", &"add", basic_attack_range_bonus, before, value)
	for status in statuses:
		for modifier in status.definition.stat_modifiers:
			if StringName(modifier.stat) == stat:
				var before := value
				value = _apply_modifier(value, modifier, status.stacks)
				var operand := pow(modifier.value, status.stacks) if modifier.operation == StatModifier.Operation.MULTIPLY else modifier.value * status.stacks
				if entries != null:
					_record_stat_step(entries, "Status: %s%s" % [status.definition.display_name, " x%d" % status.stacks if status.stacks > 1 else ""], &"multiply" if modifier.operation == StatModifier.Operation.MULTIPLY else &"add", operand, before, value)
	for entry in temporary_modifiers:
		if StringName(entry.modifier.stat) == stat:
			var before := value
			value = _apply_modifier(value, entry.modifier, 1)
			if entries != null:
				_record_stat_step(entries, _ability_source_name(entry.ability_id, "Temporary modifier"), &"multiply" if entry.modifier.operation == StatModifier.Operation.MULTIPLY else &"add", entry.modifier.value, before, value)
	if snapshot.is_boss and boss_phase > 1:
		if stat == &"damage":
			var multiplier := pow(snapshot.boss_phase_damage_multiplier, boss_phase - 1)
			var before := value
			value *= multiplier
			if entries != null:
				_record_stat_step(entries, "Boss phase %d" % boss_phase, &"multiply", multiplier, before, value)
		elif stat == &"attack_speed":
			var multiplier := pow(snapshot.boss_phase_attack_speed_multiplier, boss_phase - 1)
			var before := value
			value *= multiplier
			if entries != null:
				_record_stat_step(entries, "Boss phase %d" % boss_phase, &"multiply", multiplier, before, value)
	if stat == &"attack_speed" and session != null:
		var multiplier: float = session.get_enemy_attack_speed_aura_multiplier(self)
		var before := value
		value *= multiplier
		if entries != null:
			_record_stat_step(entries, "Enemy attack-speed aura", &"multiply", multiplier, before, value)
		multiplier = session.get_lust_target_attack_speed_multiplier(self)
		before = value
		value *= multiplier
		if entries != null:
			_record_stat_step(entries, "Ability: Beguiling Presence", &"multiply", multiplier, before, value)
		if frenzy_remaining > 0.0:
			before = value
			value *= frenzy_attack_speed_multiplier
			if entries != null:
				_record_stat_step(entries, _ability_source_name(frenzy_ability_id, "Frenzy"), &"multiply", frenzy_attack_speed_multiplier, before, value)
		if despair_slow_stacks > 0:
			multiplier = 1.0 - despair_slow_applied_percent / 100.0
			before = value
			value *= multiplier
			if entries != null:
				_record_stat_step(entries, _ability_source_name(despair_slow_ability_id, "Despair slow"), &"multiply", multiplier, before, value)
	if stat == &"damage" and envy_strongest_ally_damage_percent > 0.0 and session != null:
		var bonus: float = session.get_strongest_non_hero_ally_damage(self) * envy_strongest_ally_damage_percent / 100.0
		var before := value
		value += bonus
		if entries != null:
			_record_stat_step(entries, "Ability: Borrowed Might", &"add", bonus, before, value)
	if lust_death_scaling_percent > 0.0 and session != null and (stat == &"max_hp" or stat == &"damage" or stat == &"armor"):
		var multiplier: float = 1.0 + session.get_lust_allied_death_count(self) * lust_death_scaling_percent / 100.0
		var before := value
		value *= multiplier
		if entries != null:
			_record_stat_step(entries, _ability_source_name(lust_death_scaling_ability_id, "Fallen Devotion"), &"multiply", multiplier, before, value)
	if stat == &"attack_speed" and is_instance_valid(lust_bond_partner):
		var before := value
		value *= lust_bond_attack_speed_multiplier
		if entries != null:
			_record_stat_step(entries, _ability_source_name(lust_bond_ability_id, "Fatal Bond"), &"multiply", lust_bond_attack_speed_multiplier, before, value)
	if stat == nearby_ally_bonus_stat and nearby_ally_bonus_value > 0.0:
		var allies := nearby_same_job_allies()
		if allies > 0:
			var before := value
			value += nearby_ally_bonus_value * allies
			if entries != null:
				_record_stat_step(entries, "%s (%d nearby)" % [_ability_source_name(nearby_ally_bonus_ability_id, "Nearby allies"), allies], &"add", nearby_ally_bonus_value * allies, before, value)
	if despair_growth_bonus_percent.has(stat):
		var multiplier := 1.0 + float(despair_growth_bonus_percent[stat]) / 100.0
		var before := value
		value *= multiplier
		if entries != null:
			_record_stat_step(entries, _ability_source_name(despair_growth_ability_id, "Endless Descent"), &"multiply", multiplier, before, value)
	value = items.modify_stat(stat, value, entries)
	if stat == &"damage_taken":
		return maxf(value, -90.0)
	if stat == &"dodge":
		return clampf(value, 0.0, CombatStats.MAX_DODGE)
	if stat == &"cooldown_reduction":
		return clampf(value, 0.0, CombatStats.MAX_COOLDOWN_REDUCTION)
	return maxf(value, 0.0)


func _record_stat_step(entries, source: String, operation: StringName, operand: float, before: float, after: float) -> void:
	if entries == null or is_equal_approx(before, after):
		return
	entries.append({"source": source, "operation": operation, "operand": operand, "before": before, "after": after})


func _ability_source_name(ability_id: StringName, fallback: String) -> String:
	if not String(ability_id).is_empty() and session != null:
		var ability: AbilityDefinition = session.get_ability_definition(ability_id)
		if ability != null:
			return "Ability: %s" % ability.display_name
	return fallback


func get_damage_multiplier() -> float:
	return get_effective_stat(&"damage") / maxf(snapshot.stats.damage, 0.01)


func add_temporary_modifier(
	modifier: StatModifier,
	duration: float,
	source,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	temporary_modifiers.append({
		"modifier": modifier,
		"remaining": duration if duration > 0.0 else -1.0,
		"source_id": source.snapshot.runtime_id if is_instance_valid(source) else "",
		"ability_id": ability_id,
		"effect_id": effect_id,
	})
	_clamp_current_hp_to_max()


func _clamp_current_hp_to_max() -> void:
	current_hp = minf(current_hp, get_effective_stat(&"max_hp"))
	queue_redraw()


func apply_envy_dart_slow(slow_percent: float, source: Combatant, ability_id: StringName, effect_id: StringName) -> void:
	if envy_dart_slow_applied:
		return
	var slow := StatModifier.new()
	slow.stat = "movement_speed"
	slow.operation = StatModifier.Operation.MULTIPLY
	slow.value = 1.0 - clampf(slow_percent, 0.0, 100.0) / 100.0
	add_temporary_modifier(slow, 0.0, source, ability_id, effect_id)
	envy_dart_slow_applied = true


func apply_envy_dart_poison(damage: float, slow_percent: float, source: Combatant, ability_id: StringName, effect_id: StringName) -> void:
	var poison := StatusDefinition.new()
	poison.id = &"status.envy_dart_poison"
	poison.display_name = "Jealous Poison"
	poison.description = "Deals %.1f damage every second until battle end." % damage
	poison.default_duration = 0.0
	poison.max_stacks = 1
	poison.stack_policy = StatusDefinition.StackPolicy.REFRESH_DURATION
	poison.periodic_interval = 1.0
	poison.polarity = StatusDefinition.Polarity.NEGATIVE
	var tick := DamageEffect.new()
	tick.effect_id = effect_id
	tick.amount = damage
	poison.periodic_effects.append(tick)
	apply_status(poison, source, ability_id)
	apply_envy_dart_slow(slow_percent, source, ability_id, effect_id)


func add_basic_attack_empowerment(
	lifesteal_percent: float,
	size_multiplier: float,
	duration: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	basic_attack_empowerments.append({
		"lifesteal_percent": maxf(lifesteal_percent, 0.0),
		"size_multiplier": maxf(size_multiplier, 0.01),
		"remaining": duration if duration > 0.0 else -1.0,
		"ability_id": ability_id,
		"effect_id": effect_id,
	})
	_refresh_body_radius()


func apply_basic_attack_lifesteal(damage_dealt: float) -> float:
	if damage_dealt <= 0.0:
		return 0.0
	var percent := 0.0
	for empowerment in basic_attack_empowerments:
		percent += float(empowerment.lifesteal_percent)
	var aura: Dictionary = session.get_gluttony_lifesteal_aura(self)
	percent += float(aura.get("percent", 0.0))
	percent += passive_basic_lifesteal_percent
	var stat_lifesteal := get_effective_stat(&"lifesteal")
	percent += stat_lifesteal
	if percent <= 0.0:
		return 0.0
	var ability_id := StringName(aura.get("ability_id", &""))
	var effect_id := StringName(aura.get("effect_id", &""))
	if passive_basic_lifesteal_percent > 0.0 and String(ability_id).is_empty():
		ability_id = passive_basic_lifesteal_ability_id
		effect_id = passive_basic_lifesteal_effect_id
	if stat_lifesteal > 0.0 and String(ability_id).is_empty():
		ability_id = &"stat.lifesteal"
		effect_id = &"stat.lifesteal"
	if not basic_attack_empowerments.is_empty():
		ability_id = StringName(basic_attack_empowerments[0].ability_id)
		effect_id = StringName(basic_attack_empowerments[0].effect_id)
	return receive_healing(
		damage_dealt * percent / 100.0,
		self,
		ability_id,
		effect_id
	)


func set_gluttony_lifesteal_aura(radius: float, percent: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_lifesteal_aura_radius = radius
	gluttony_lifesteal_percent = percent
	gluttony_lifesteal_ability_id = ability_id
	gluttony_lifesteal_effect_id = effect_id


func set_gluttony_regeneration(max_stacks: int, percent_per_stack: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_regeneration_max_stacks = max_stacks
	gluttony_regeneration_percent_per_stack = percent_per_stack
	gluttony_regeneration_ability_id = ability_id
	gluttony_regeneration_effect_id = effect_id


func _gain_gluttony_regeneration_stack() -> void:
	if gluttony_regeneration_max_stacks <= 0 or gluttony_regeneration_stacks >= gluttony_regeneration_max_stacks:
		return
	if gluttony_regeneration_stacks == 0:
		gluttony_regeneration_tick_remaining = 1.0
	gluttony_regeneration_stacks += 1


func gluttony_regeneration_per_second() -> float:
	return get_effective_stat(&"max_hp") * gluttony_regeneration_percent_per_stack * gluttony_regeneration_stacks / 100.0


func set_gluttony_damage_aura(radius: float, damage: float, interval: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_damage_aura_radius = radius
	gluttony_damage_aura_damage = damage
	gluttony_damage_aura_interval = interval
	gluttony_damage_aura_tick_remaining = interval
	gluttony_damage_aura_ability_id = ability_id
	gluttony_damage_aura_effect_id = effect_id


func set_gluttony_death_explosion(radius: float, damage: float, ability_id: StringName, effect_id: StringName) -> void:
	gluttony_death_explosion_radius = radius
	gluttony_death_explosion_damage = damage
	gluttony_death_explosion_ability_id = ability_id
	gluttony_death_explosion_effect_id = effect_id


func set_despair_team_proc(chance_percent: float, total_damage_percent: float, ability_id: StringName, effect_id: StringName) -> void:
	despair_team_proc_chance_percent = clampf(chance_percent, 0.0, 100.0)
	despair_team_proc_total_damage_percent = maxf(total_damage_percent, 100.0)
	despair_team_proc_ability_id = ability_id
	despair_team_proc_effect_id = effect_id


func set_despair_attack_slow(max_stacks: int, percent_per_stack: float, maximum_percent: float, ability_id: StringName, effect_id: StringName) -> void:
	despair_attack_slow_max_stacks = maxi(max_stacks, 1)
	despair_attack_slow_percent_per_stack = maxf(percent_per_stack, 0.0)
	despair_attack_slow_maximum_percent = clampf(maximum_percent, 0.0, 80.0)
	despair_slow_ability_id = ability_id
	despair_slow_effect_id = effect_id


func apply_despair_attack_slow(max_stacks: int, percent_per_stack: float, maximum_percent: float) -> void:
	despair_slow_max_stacks = maxi(despair_slow_max_stacks, max_stacks)
	despair_slow_percent_per_stack = maxf(despair_slow_percent_per_stack, percent_per_stack)
	despair_slow_maximum_percent = maxf(despair_slow_maximum_percent, clampf(maximum_percent, 0.0, 80.0))
	despair_slow_stacks = mini(despair_slow_stacks + 1, despair_slow_max_stacks)
	despair_slow_applied_percent = minf(despair_slow_stacks * despair_slow_percent_per_stack, despair_slow_maximum_percent)


func apply_despair_sanctuary(source: Combatant, heal_percent: float, duration: float, interval: float, ability_id: StringName, effect_id: StringName) -> void:
	despair_sanctuary_remaining = maxf(duration, 0.0)
	despair_sanctuary_heal_percent = maxf(heal_percent, 0.0)
	despair_sanctuary_interval = maxf(interval, 0.01)
	despair_sanctuary_tick_remaining = despair_sanctuary_interval
	despair_sanctuary_source = source
	despair_sanctuary_ability_id = ability_id
	despair_sanctuary_effect_id = effect_id
	clear_combat_action()


func set_despair_growth(
	max_hp_rate: float,
	damage_rate: float,
	armor_rate: float,
	movement_speed_rate: float,
	attack_speed_rate: float,
	maximum_percent: float,
	interval: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	despair_growth_rates = {
		&"max_hp": maxf(max_hp_rate, 0.0),
		&"damage": maxf(damage_rate, 0.0),
		&"armor": maxf(armor_rate, 0.0),
		&"movement_speed": maxf(movement_speed_rate, 0.0),
		&"attack_speed": maxf(attack_speed_rate, 0.0),
	}
	despair_growth_bonus_percent = {&"max_hp": 0.0, &"damage": 0.0, &"armor": 0.0, &"movement_speed": 0.0, &"attack_speed": 0.0}
	despair_growth_maximum_percent = maxf(maximum_percent, 0.0)
	despair_growth_interval = maxf(interval, 0.01)
	despair_growth_tick_remaining = despair_growth_interval
	despair_growth_ability_id = ability_id
	despair_growth_effect_id = effect_id


func apply_gluttony_grease(miss_percent: float, duration: float, source: Combatant, ability_id: StringName) -> void:
	gluttony_grease_miss_percent = clampf(miss_percent, 0.0, 100.0)
	var grease := StatusDefinition.new()
	grease.id = &"status.gluttony_grease"
	grease.display_name = "Greased"
	grease.description = "Basic attacks have a %.0f%% chance to miss." % gluttony_grease_miss_percent
	grease.default_duration = duration
	grease.max_stacks = 1
	grease.stack_policy = StatusDefinition.StackPolicy.REFRESH_DURATION
	grease.polarity = StatusDefinition.Polarity.NEGATIVE
	apply_status(grease, source, ability_id)


func get_gluttony_grease_miss_chance() -> float:
	return gluttony_grease_miss_percent / 100.0 if has_status(&"status.gluttony_grease") else 0.0


func apply_all_damage_lifesteal(damage_dealt: float) -> float:
	if damage_dealt <= 0.0 or lust_bond_lifesteal_percent <= 0.0 or not is_instance_valid(lust_bond_partner):
		return 0.0
	return receive_healing(damage_dealt * lust_bond_lifesteal_percent / 100.0, self, lust_bond_ability_id, lust_bond_effect_id)


func add_runtime_status(name: String, details: String, polarity: String, duration: float, ability_id: StringName = &"") -> void:
	runtime_status_metadata.append({
		"name": name,
		"details": details,
		"polarity": polarity,
		"remaining": duration if duration > 0.0 else -1.0,
		"ability_id": ability_id,
	})


func set_forced_basic_target(value: Combatant, duration: float, ability_id: StringName) -> void:
	forced_basic_target = value
	forced_basic_target_remaining = maxf(duration, 0.0)
	add_runtime_status("Taunted", "Basic attacks are forced toward %s." % value.snapshot.display_name, "DEBUFF", duration, ability_id)
	if attack_committed or state == State.ATTACK_RECOVERY:
		return
	pending_ability = null
	target = value
	basic_attack_target_active = true
	state_timer = 0.0
	state = State.ACQUIRE_TARGET


func clear_combat_action() -> void:
	forced_basic_target = null
	forced_basic_target_remaining = 0.0
	_remove_runtime_status("Taunted")
	pending_ability = null
	target = null
	basic_attack_target_active = false
	velocity = Vector2.ZERO
	state_timer = 0.0
	state = State.ACQUIRE_TARGET


func _remove_runtime_status(status_name: String) -> void:
	for index in range(runtime_status_metadata.size() - 1, -1, -1):
		if String(runtime_status_metadata[index].name) == status_name:
			runtime_status_metadata.remove_at(index)


func set_lust_death_scaling(percent_per_death: float, ability_id: StringName) -> void:
	lust_death_scaling_percent = percent_per_death
	lust_death_scaling_ability_id = ability_id


func set_lust_target_slow(slow_percent: float, ability_id: StringName) -> void:
	lust_target_slow_percent = slow_percent
	lust_target_slow_ability_id = ability_id


func prepare_lust_bond(lifesteal_percent: float, attack_speed_multiplier: float, ability_id: StringName, effect_id: StringName) -> void:
	lust_bond_pending = true
	lust_bond_lifesteal_percent = lifesteal_percent
	lust_bond_attack_speed_multiplier = attack_speed_multiplier
	lust_bond_ability_id = ability_id
	lust_bond_effect_id = effect_id


func establish_lust_bond(partner: Combatant) -> void:
	if not is_instance_valid(partner) or partner == self:
		return
	lust_bond_pending = false
	lust_bond_partner = partner
	partner.lust_bond_partner = self
	partner.lust_bond_lifesteal_percent = lust_bond_lifesteal_percent
	partner.lust_bond_attack_speed_multiplier = lust_bond_attack_speed_multiplier
	partner.lust_bond_ability_id = lust_bond_ability_id
	partner.lust_bond_effect_id = lust_bond_effect_id


func set_lust_basic_knockback(hits_required: int, knockback_distance: float, stun_duration: float, ability_id: StringName, effect_id: StringName) -> void:
	lust_basic_hits_required = hits_required
	lust_basic_hit_count = 0
	lust_basic_knockback_distance = knockback_distance
	lust_basic_stun_duration = stun_duration
	lust_basic_ability_id = ability_id
	lust_basic_effect_id = effect_id


func add_passive_basic_lifesteal(percent: float, ability_id: StringName, effect_id: StringName) -> void:
	passive_basic_lifesteal_percent += percent
	passive_basic_lifesteal_ability_id = ability_id
	passive_basic_lifesteal_effect_id = effect_id


func add_on_hit_status(status: StatusDefinition, ability_id: StringName) -> void:
	on_hit_statuses.append({"status": status, "ability_id": ability_id})


func set_nearby_ally_stat_bonus(stat: StringName, value_per_ally: float, radius: float, max_allies: int, ability_id: StringName) -> void:
	nearby_ally_bonus_stat = stat
	nearby_ally_bonus_value = value_per_ally
	nearby_ally_bonus_radius = radius
	nearby_ally_bonus_max = max_allies
	nearby_ally_bonus_ability_id = ability_id


## Living allies of the same Job within the Strength in Numbers radius (capped).
func nearby_same_job_allies() -> int:
	if session == null or nearby_ally_bonus_max <= 0 or String(snapshot.job_id).is_empty():
		return 0
	var count := 0
	for other in session.combatants:
		if other == self or not other.is_alive() or other.snapshot.team != snapshot.team or other.snapshot.job_id != snapshot.job_id:
			continue
		if other.position.distance_to(position) <= nearby_ally_bonus_radius:
			count += 1
			if count >= nearby_ally_bonus_max:
				break
	return count


func record_successful_basic_hit(hit_target: Combatant, damage_dealt: float) -> void:
	if damage_dealt <= 0.0 or not is_instance_valid(hit_target):
		return
	items.on_basic_hit(hit_target, damage_dealt)
	if not is_instance_valid(hit_target):
		return
	for entry in on_hit_statuses:
		if hit_target.is_alive():
			hit_target.apply_status(entry.status, self, entry.ability_id)
	if despair_attack_slow_max_stacks > 0:
		hit_target.apply_despair_attack_slow(despair_attack_slow_max_stacks, despair_attack_slow_percent_per_stack, despair_attack_slow_maximum_percent)
	if lust_basic_hits_required <= 0:
		return
	lust_basic_hit_count += 1
	if lust_basic_hit_count < lust_basic_hits_required:
		return
	lust_basic_hit_count = 0
	session.apply_lust_basic_knockback(self, hit_target, lust_basic_knockback_distance, lust_basic_stun_duration, lust_basic_ability_id, lust_basic_effect_id)


func _has_forced_basic_target() -> bool:
	return forced_basic_target_remaining > 0.0 and is_instance_valid(forced_basic_target) and forced_basic_target.is_targetable() and forced_basic_target.snapshot.team != snapshot.team


func add_shield(
	amount: float,
	duration: float,
	source,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	if amount > 0.0:
		shields.append({
			"amount": amount,
			"remaining": duration if duration > 0.0 else -1.0,
			"source_id": source.snapshot.runtime_id if is_instance_valid(source) else "",
			"ability_id": ability_id,
			"effect_id": effect_id,
		})


func set_melee_retaliation(radius: float, multiplier: float, ability_id: StringName, effect_id: StringName) -> void:
	melee_retaliation_radius = maxf(radius, 0.0)
	melee_retaliation_multiplier = maxf(multiplier, 0.0)
	melee_retaliation_ability_id = ability_id
	melee_retaliation_effect_id = effect_id


func set_attack_reflection(percent: float, ability_id: StringName, effect_id: StringName) -> void:
	attack_reflect_percent = maxf(percent, 0.0)
	attack_reflect_ability_id = ability_id
	attack_reflect_effect_id = effect_id


func _reflect_basic_attack_damage(attacker: Combatant, applied_damage: float) -> void:
	if attack_reflect_percent <= 0.0 or applied_damage <= 0.0 or not attacker.is_targetable():
		return
	attacker.take_damage(
		applied_damage * attack_reflect_percent / 100.0,
		self,
		attack_reflect_ability_id,
		attack_reflect_effect_id,
		false,
		false
	)


func set_focused_damage(damage_per_stack: float, duration: float, _ability_id: StringName, _effect_id: StringName) -> void:
	focused_damage_per_stack = maxf(damage_per_stack, 0.0)
	focused_stack_duration = maxf(duration, 0.0)


func apply_frenzy(attack_speed_multiplier: float, duration: float, ability_id: StringName, effect_id: StringName) -> void:
	frenzy_attack_speed_multiplier = maxf(attack_speed_multiplier, 0.01)
	frenzy_remaining = maxf(frenzy_remaining, duration)
	frenzy_ability_id = ability_id
	frenzy_effect_id = effect_id
	frenzy_direction_timer = 0.0
	first_enemy_damage_time = -1.0
	target = null
	pending_ability = null
	state = State.ACQUIRE_TARGET


func record_enemy_damage_dealt() -> void:
	if first_enemy_damage_time < 0.0:
		first_enemy_damage_time = session.elapsed_time


func can_activate_frenzy() -> bool:
	return first_enemy_damage_time >= 0.0 and session.elapsed_time - first_enemy_damage_time >= FRENZY_ACTIVATION_DELAY


func set_threshold_guard(
	health_ratio: float,
	shield_multiplier: float,
	armor_multiplier: float,
	duration: float,
	cooldown: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	threshold_guard_health_ratio = clampf(health_ratio, 0.0, 1.0)
	threshold_guard_shield_multiplier = maxf(shield_multiplier, 0.0)
	threshold_guard_armor_multiplier = maxf(armor_multiplier, 0.01)
	threshold_guard_duration = maxf(duration, 0.0)
	threshold_guard_cooldown = maxf(cooldown, 0.0)
	threshold_guard_ability_id = ability_id
	threshold_guard_effect_id = effect_id


func prepare_ground_slam(multiplier: float, radius: float, ability_id: StringName, effect_id: StringName) -> void:
	ground_slam_damage_multiplier = maxf(multiplier, 0.0)
	ground_slam_radius = maxf(radius, 0.0)
	ground_slam_ability_id = ability_id
	ground_slam_effect_id = effect_id


func apply_status(definition: StatusDefinition, source: Combatant, ability_id: StringName) -> void:
	if definition.polarity == StatusDefinition.Polarity.NEGATIVE and has_negative_status_immunity():
		return
	for status in statuses:
		if status.definition.id == definition.id:
			status.refresh(source, ability_id)
			session.record_status_applied(source, self, ability_id, definition.id)
			return
	var instance := StatusInstance.new()
	instance.setup(definition, source, ability_id)
	statuses.append(instance)
	session.record_status_applied(source, self, ability_id, definition.id)


func _remove_hp_damage_break_statuses() -> void:
	for index in range(statuses.size() - 1, -1, -1):
		if statuses[index].definition != null and statuses[index].definition.breaks_on_hp_damage:
			statuses.remove_at(index)


func has_negative_status() -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.polarity == StatusDefinition.Polarity.NEGATIVE
	)


func has_negative_status_immunity() -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.grants_negative_status_immunity
	)


func has_status(status_id: StringName) -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.id == status_id
	)


func remove_random_negative_status(_source: Combatant, _ability_id: StringName, _effect_id: StringName) -> bool:
	var candidates: Array[int] = []
	for index in statuses.size():
		if statuses[index].definition != null and statuses[index].definition.polarity == StatusDefinition.Polarity.NEGATIVE:
			candidates.append(index)
	if candidates.is_empty():
		return false
	var selected_index := candidates[session.combat_rng.randi_range(0, candidates.size() - 1)]
	statuses.remove_at(selected_index)
	return true


func is_stunned() -> bool:
	if despair_sanctuary_remaining > 0.0:
		return true
	for status in statuses:
		if status.definition.prevents_actions:
			return true
	return false


func is_rooted() -> bool:
	for status in statuses:
		if status.definition != null and status.definition.prevents_movement:
			return true
	return false


func is_feared() -> bool:
	for status in statuses:
		if status.definition != null and status.definition.causes_fear:
			return true
	return false


func is_invulnerable() -> bool:
	for status in statuses:
		if status.definition != null and status.definition.grants_invulnerability:
			return true
	return false


func status_stacks(status_id: StringName) -> int:
	for status in statuses:
		if status.definition != null and status.definition.id == status_id:
			return status.stacks
	return 0


func remove_status(status_id: StringName) -> void:
	for index in range(statuses.size() - 1, -1, -1):
		if statuses[index].definition != null and statuses[index].definition.id == status_id:
			statuses.remove_at(index)


## Ability cooldown after Cooldown Reduction.
func cooldown_for(ability: AbilityDefinition) -> float:
	return ability.cooldown_seconds * (1.0 - get_effective_stat(&"cooldown_reduction") / 100.0)


## Basic-attack critical strikes: crit_chance %, crit_multiplier (default x2).
func roll_critical_damage(raw_damage: float) -> float:
	var chance := get_effective_stat(&"crit_chance")
	if chance <= 0.0 or session == null or session.combat_rng.randf() * 100.0 >= chance:
		return raw_damage
	var multiplier := get_effective_stat(&"crit_multiplier")
	if multiplier <= 1.0:
		multiplier = CombatStats.DEFAULT_CRIT_MULTIPLIER
	session.record_critical_hit(self)
	return raw_damage * multiplier


## Feared units run directly away from whoever frightened them.
func _update_fear(delta: float) -> void:
	pending_ability = null
	basic_attack_target_active = false
	var source_position := position + Vector2.LEFT
	for status in statuses:
		if status.definition != null and status.definition.causes_fear and is_instance_valid(status.source):
			source_position = status.source.position
			break
	if is_rooted():
		velocity = Vector2.ZERO
		return
	var direction := (position - source_position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	velocity = direction * get_effective_stat(&"movement_speed")
	_slide(delta)
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	state = State.ACQUIRE_TARGET


func get_debug_text() -> String:
	var target_id := "none"
	if is_instance_valid(target):
		target_id = target.snapshot.runtime_id
	var cooldown := state_timer if state == State.ATTACK_RECOVERY else 0.0
	return "ID: %s\nTeam: %s\nState: %s\nTarget: %s\nHP: %.1f / %.1f\nCooldown: %.2f s\nStatuses: %d%s" % [
		snapshot.runtime_id,
		"PLAYER" if snapshot.team == CombatUnitSnapshot.Team.PLAYER else "ENEMY",
		State.keys()[state],
		target_id,
		current_hp,
		get_effective_stat(&"max_hp"),
		cooldown,
		statuses.size(),
		"\nBoss phase: %d / %d" % [boss_phase, snapshot.boss_phase_count] if snapshot.is_boss else "",
	]


func _die(source: Combatant) -> void:
	if state == State.DEAD:
		return
	last_stand_remaining = 0.0
	attack_committed = false
	attack_motion_lock_remaining = 0.0
	committed_attack_target = null
	committed_attack_ability = null
	skill_animation_remaining = 0.0
	skill_animation_target = null
	state = State.DEAD
	_update_visual_layers()
	simulation_active = false
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	queue_redraw()
	if is_instance_valid(source) and source.snapshot.team != snapshot.team:
		session.grant_kill_reward(source)
		source.items.on_kill(self)
	session.record_event(
		CombatEvent.UNIT_DIED,
		source.snapshot.runtime_id if is_instance_valid(source) else last_damage_source_id,
		snapshot.runtime_id,
		&"",
		last_effect_id
	)
	if not gluttony_death_explosion_triggered and gluttony_death_explosion_damage > 0.0:
		gluttony_death_explosion_triggered = true
		session.damage_enemies_in_radius(self, gluttony_death_explosion_radius, gluttony_death_explosion_damage, gluttony_death_explosion_ability_id, gluttony_death_explosion_effect_id, false)
	session.notify_combatant_died(self, source)


func force_die(source: Combatant, effect_id: StringName) -> void:
	last_effect_id = effect_id
	current_hp = 0.0
	_die(source)


func _has_valid_target() -> bool:
	if not is_instance_valid(target):
		return false
	if pending_ability != null and target.snapshot.team == snapshot.team:
		return target.is_targetable()
	if frenzy_remaining > 0.0:
		return target.is_targetable() and target != self
	return target.can_be_targeted_by(self) and target.snapshot.team != snapshot.team


func _try_use_ability() -> bool:
	for ability in snapshot.abilities:
		if ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
			continue
		if _try_activate_ability(ability, false):
			return true
	return false


func _try_use_priority_summon() -> bool:
	for ability in snapshot.abilities:
		if not _is_summon_ability(ability):
			continue
		if _try_activate_ability(ability, true):
			return true
	return false


func _try_activate_ability(ability: AbilityDefinition, interrupt_current_action: bool) -> bool:
	if attack_committed or attack_motion_lock_remaining > 0.0:
		return false
	if ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
		return false
	if float(ability_cooldowns.get(ability.id, 0.0)) > 0.0:
		return false
	if ability.required_recent_damage_seconds > 0.0 and (
		last_damage_taken_time < 0.0
		or session.elapsed_time - last_damage_taken_time > ability.required_recent_damage_seconds
	):
		return false
	var ability_target: Combatant = session.resolve_ability_target(self, ability)
	if not is_instance_valid(ability_target) or not session.can_use_ability(self, ability_target, ability):
		return false
	if ranged_retreat_active or ranged_retreat_pending:
		_finish_ranged_retreat()
	basic_attack_target_active = false
	if interrupt_current_action:
		pending_ability = null
		target = null
		velocity = Vector2.ZERO
		state_timer = 0.0
		windup_duration = 0.0
		queue_redraw()
	var outside_cast_range := ability.cast_range > 0.0 and position.distance_to(ability_target.position) > ability.cast_range
	if outside_cast_range or ability.delivery_method == AbilityDefinition.DeliveryMethod.MELEE_HIT or (snapshot.is_boss and not _is_summon_ability(ability)):
		pending_ability = ability
		target = ability_target
		basic_attack_target_active = false
		state = State.MOVE_INTO_RANGE
	else:
		ability_cooldowns[ability.id] = cooldown_for(ability)
		session.deliver_ability(self, ability_target, ability)
		state = State.ACQUIRE_TARGET
	return true


func _ready_basic_replacement() -> AbilityDefinition:
	for ability in snapshot.abilities:
		if (
			ability.kind == AbilityDefinition.AbilityKind.ACTIVE
			and ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK
			and float(ability_cooldowns.get(ability.id, 0.0)) <= 0.0
			and session.can_use_ability(self, target, ability)
		):
			return ability
	return null


func _is_summon_ability(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect is SummonEffect or effect is SummonMergeEffect:
			return true
	return false


func _apply_passive_abilities() -> void:
	for ability in snapshot.abilities:
		if ability.kind != AbilityDefinition.AbilityKind.PASSIVE:
			continue
		for effect in ability.effects:
			effect.apply(self, self, ability)


func _update_runtime(delta: float) -> void:
	attack_motion_lock_remaining = maxf(0.0, attack_motion_lock_remaining - delta)
	if forced_basic_target_remaining > 0.0:
		forced_basic_target_remaining = maxf(0.0, forced_basic_target_remaining - delta)
		if not _has_forced_basic_target():
			forced_basic_target = null
			_remove_runtime_status("Taunted")
			if not attack_committed and state != State.ATTACK_RECOVERY:
				target = null
				basic_attack_target_active = false
				pending_ability = null
				state = State.ACQUIRE_TARGET
	for index in range(runtime_status_metadata.size() - 1, -1, -1):
		if float(runtime_status_metadata[index].remaining) < 0.0:
			continue
		runtime_status_metadata[index].remaining = float(runtime_status_metadata[index].remaining) - delta
		if float(runtime_status_metadata[index].remaining) <= 0.0:
			runtime_status_metadata.remove_at(index)
	if frenzy_remaining > 0.0:
		frenzy_remaining = maxf(0.0, frenzy_remaining - delta)
		if frenzy_remaining <= 0.0:
			target = null
			state = State.ACQUIRE_TARGET
	if stealth_remaining > 0.0:
		stealth_remaining = maxf(0.0, stealth_remaining - delta)
		if stealth_remaining <= 0.0:
			queue_redraw()
	if last_stand_remaining > 0.0:
		last_stand_remaining = maxf(0.0, last_stand_remaining - delta)
		if last_stand_remaining <= 0.0:
			_die(null)
			return
	if melee_teleport_cooldown_remaining > 0.0:
		melee_teleport_cooldown_remaining = maxf(0.0, melee_teleport_cooldown_remaining - delta)
	if threshold_guard_cooldown_remaining > 0.0:
		threshold_guard_cooldown_remaining = maxf(0.0, threshold_guard_cooldown_remaining - delta)
	if phase_banner_timer > 0.0:
		phase_banner_timer = maxf(0.0, phase_banner_timer - delta)
		queue_redraw()
	if veterancy_banner_timer > 0.0:
		veterancy_banner_timer = maxf(0.0, veterancy_banner_timer - delta)
	for ability_id in ability_cooldowns:
		ability_cooldowns[ability_id] = maxf(0.0, float(ability_cooldowns[ability_id]) - delta)
	for index in range(statuses.size() - 1, -1, -1):
		if statuses[index].update(delta, self):
			statuses.remove_at(index)
	for index in range(temporary_modifiers.size() - 1, -1, -1):
		if float(temporary_modifiers[index].remaining) < 0.0:
			continue
		temporary_modifiers[index].remaining = float(temporary_modifiers[index].remaining) - delta
		if float(temporary_modifiers[index].remaining) <= 0.0:
			temporary_modifiers.remove_at(index)
			_clamp_current_hp_to_max()
	var body_radius_changed := false
	for index in range(basic_attack_empowerments.size() - 1, -1, -1):
		if float(basic_attack_empowerments[index].remaining) < 0.0:
			continue
		basic_attack_empowerments[index].remaining = float(basic_attack_empowerments[index].remaining) - delta
		if float(basic_attack_empowerments[index].remaining) <= 0.0:
			basic_attack_empowerments.remove_at(index)
			body_radius_changed = true
	if body_radius_changed:
		_refresh_body_radius()
	for index in range(shields.size() - 1, -1, -1):
		if float(shields[index].remaining) < 0.0:
			continue
		shields[index].remaining = float(shields[index].remaining) - delta
		if float(shields[index].remaining) <= 0.0:
			shields.remove_at(index)
	if gluttony_regeneration_stacks > 0 and is_alive():
		gluttony_regeneration_tick_remaining -= delta
		while gluttony_regeneration_tick_remaining <= 0.000001:
			gluttony_regeneration_tick_remaining += 1.0
			receive_healing(gluttony_regeneration_per_second(), self, gluttony_regeneration_ability_id, gluttony_regeneration_effect_id)
	if gluttony_damage_aura_interval > 0.0 and is_alive():
		gluttony_damage_aura_tick_remaining -= delta
		while gluttony_damage_aura_tick_remaining <= 0.000001:
			gluttony_damage_aura_tick_remaining += gluttony_damage_aura_interval
			session.damage_enemies_in_radius(self, gluttony_damage_aura_radius, gluttony_damage_aura_damage, gluttony_damage_aura_ability_id, gluttony_damage_aura_effect_id)
	if despair_sanctuary_remaining > 0.0:
		var sanctuary_delta := minf(delta, despair_sanctuary_remaining)
		despair_sanctuary_remaining = maxf(0.0, despair_sanctuary_remaining - delta)
		despair_sanctuary_tick_remaining -= sanctuary_delta
		while despair_sanctuary_tick_remaining <= 0.000001:
			despair_sanctuary_tick_remaining += despair_sanctuary_interval
			receive_healing(get_effective_stat(&"max_hp") * despair_sanctuary_heal_percent / 100.0, despair_sanctuary_source, despair_sanctuary_ability_id, despair_sanctuary_effect_id)
	if despair_growth_interval > 0.0 and is_alive():
		despair_growth_tick_remaining -= delta
		while despair_growth_tick_remaining <= 0.000001:
			despair_growth_tick_remaining += despair_growth_interval
			_apply_despair_growth_tick()
	_update_focused_damage_stacks(delta)
	items.update(delta)


## Mid-battle Veterancy rank up: the growth of the new rank is applied to the
## battle stats (same per-rank multipliers as CombatSnapshotBuilder), the extra max HP
## is granted as health, and Veterancy-scaled heals grow too.
func gain_veterancy_level(progression: ProgressionDefinition) -> void:
	var old_level := snapshot.veterancy_level
	var new_level := old_level + 1
	var old_max_hp := get_effective_stat(&"max_hp")
	var growth := {
		&"max_hp": progression.veterancy_max_hp_growth_per_level,
		&"damage": progression.veterancy_damage_growth_per_level,
		&"attack_speed": progression.veterancy_attack_speed_growth_per_level,
		&"movement_speed": progression.veterancy_movement_speed_growth_per_level,
		&"attack_range": progression.veterancy_attack_range_growth_per_level,
		&"armor": progression.veterancy_armor_growth_per_level,
	}
	for stat in growth:
		var rate := float(growth[stat])
		var multiplier := (1.0 + new_level * rate) / maxf(1.0 + old_level * rate, 0.001)
		var before := float(snapshot.stats.get(stat))
		snapshot.stats.set(stat, before * multiplier)
		snapshot.stats.record_change(stat, "Veterancy %d (gained in battle)" % new_level, &"multiply", multiplier, before, before * multiplier)
	for index in snapshot.abilities.size():
		var ability := snapshot.abilities[index]
		if not ability.effects.any(func(effect: AbilityEffect) -> bool: return effect is HealEffect and effect.veterancy_bonus_percent_per_level > 0.0):
			continue
		var scaled := ability.duplicate(true) as AbilityDefinition
		for effect in scaled.effects:
			if effect is HealEffect and effect.veterancy_bonus_percent_per_level > 0.0:
				var bonus: float = effect.veterancy_bonus_percent_per_level / 100.0
				effect.amount *= (1.0 + new_level * bonus) / (1.0 + old_level * bonus)
		snapshot.abilities[index] = scaled
	snapshot.veterancy_level = new_level
	current_hp = minf(current_hp + maxf(0.0, get_effective_stat(&"max_hp") - old_max_hp), get_effective_stat(&"max_hp"))
	veterancy_banner_timer = VETERANCY_BANNER_TIME
	queue_redraw()


func _apply_despair_growth_tick() -> void:
	var old_max_hp := get_effective_stat(&"max_hp")
	var health_ratio := current_hp / maxf(old_max_hp, 0.01)
	for stat in despair_growth_rates:
		despair_growth_bonus_percent[stat] = minf(
			float(despair_growth_bonus_percent.get(stat, 0.0)) + float(despair_growth_rates[stat]) * despair_growth_interval,
			despair_growth_maximum_percent
		)
	current_hp = get_effective_stat(&"max_hp") * health_ratio
	queue_redraw()


func _start_melee_retreat(attacker: Combatant) -> void:
	if snapshot.attack_type == &"ranged":
		if not is_instance_valid(ranged_retreat_source) or not ranged_retreat_source.is_alive():
			ranged_retreat_source = attacker
		ranged_retreat_pending = true
		return
	var counterattack_in_progress := melee_retreat_remaining > 0.0 and state == State.ATTACK_WINDUP and pending_ability == null
	var attack_ready := state != State.ATTACK_WINDUP and (state != State.ATTACK_RECOVERY or state_timer <= 0.0)
	if melee_retreat_remaining <= 0.0 or not is_instance_valid(melee_retreat_source) or not melee_retreat_source.is_alive():
		melee_retreat_source = attacker
		melee_retreat_direction = (position - attacker.position).normalized()
		if melee_retreat_direction.is_zero_approx():
			melee_retreat_direction = Vector2.LEFT if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	melee_retreat_remaining = 0.2
	if counterattack_in_progress or is_attack_motion_locked():
		return
	pending_ability = null
	if state == State.ATTACK_WINDUP:
		state = State.ACQUIRE_TARGET
		state_timer = 0.0
	melee_retreat_counterattack_pending = melee_retreat_counterattack_pending or attack_ready


func _update_melee_retreat(delta: float) -> void:
	if state == State.ATTACK_WINDUP:
		_update_attack_windup(delta)
		return
	if state == State.ATTACK_RECOVERY:
		state_timer = maxf(0.0, state_timer - delta)
	if melee_retreat_counterattack_pending and is_instance_valid(melee_retreat_source) and melee_retreat_source.is_targetable():
		if position.distance_to(melee_retreat_source.position) <= basic_attack_reach(melee_retreat_source) and is_basic_attack_side_position(melee_retreat_source, position):
			target = melee_retreat_source
			melee_retreat_counterattack_pending = false
			_start_attack()
			return

	melee_retreat_remaining = maxf(0.0, melee_retreat_remaining - delta)
	if is_rooted():
		velocity = Vector2.ZERO
		return
	velocity = melee_retreat_direction * get_effective_stat(&"movement_speed")
	_slide(delta)
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	if melee_retreat_remaining > 0.0:
		return
	velocity = Vector2.ZERO
	melee_retreat_source = null
	melee_retreat_counterattack_pending = false
	target = null
	if state != State.ATTACK_RECOVERY or state_timer <= 0.0:
		state = State.ACQUIRE_TARGET


func _update_frenzy(delta: float) -> void:
	if state == State.ATTACK_WINDUP:
		_update_attack_windup(delta)
		return
	if state == State.ATTACK_RECOVERY:
		state_timer -= delta
		if state_timer > 0.0:
			velocity = Vector2.ZERO
			return
		state = State.ACQUIRE_TARGET

	var attack_target: Combatant = session.find_frenzy_attack_target(self)
	if is_instance_valid(attack_target):
		target = attack_target
		if not is_basic_attack_side_position(target, position):
			if is_rooted():
				_stop_navigation()
				return
			_ensure_approach_goal(basic_attack_reach(target))
			_move_to_navigation_point(approach_goal, delta, target)
			return
		velocity = Vector2.ZERO
		_start_attack()
		return
	if is_rooted():
		velocity = Vector2.ZERO
		return

	frenzy_direction_timer -= delta
	if frenzy_direction_timer <= 0.0 or position.distance_to(frenzy_destination) <= body_radius:
		frenzy_destination = session.random_arena_point(self)
		frenzy_direction_timer = FRENZY_DIRECTION_INTERVAL
	var direction := (frenzy_destination - position).normalized()
	velocity = direction * get_effective_stat(&"movement_speed")
	_slide(delta)
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)


func _focused_damage_bonus(attack_target: Combatant) -> float:
	if focused_damage_per_stack <= 0.0 or not is_instance_valid(attack_target) or attack_target.snapshot.team == snapshot.team:
		return 0.0
	return focused_damage_per_stack * (focused_damage_stacks.get(attack_target.snapshot.runtime_id, []) as Array).size()


func _add_focused_damage_stack(attack_target: Combatant) -> void:
	if focused_damage_per_stack <= 0.0 or focused_stack_duration <= 0.0 or not is_instance_valid(attack_target) or attack_target.snapshot.team == snapshot.team:
		return
	var runtime_id := attack_target.snapshot.runtime_id
	var stacks: Array = focused_damage_stacks.get(runtime_id, [])
	stacks.append(focused_stack_duration)
	focused_damage_stacks[runtime_id] = stacks


func _update_focused_damage_stacks(delta: float) -> void:
	for runtime_id in focused_damage_stacks.keys():
		var stacks: Array = focused_damage_stacks[runtime_id]
		for index in range(stacks.size() - 1, -1, -1):
			stacks[index] = float(stacks[index]) - delta
			if float(stacks[index]) <= 0.0:
				stacks.remove_at(index)
		if stacks.is_empty():
			focused_damage_stacks.erase(runtime_id)
		else:
			focused_damage_stacks[runtime_id] = stacks


func _try_threshold_guard() -> void:
	if threshold_guard_health_ratio <= 0.0 or threshold_guard_cooldown_remaining > 0.0:
		return
	if current_hp / maxf(get_effective_stat(&"max_hp"), 1.0) > threshold_guard_health_ratio:
		return
	add_shield(get_effective_stat(&"max_hp") * threshold_guard_shield_multiplier, threshold_guard_duration, self, threshold_guard_ability_id, threshold_guard_effect_id)
	var armor_modifier := StatModifier.new()
	armor_modifier.stat = "armor"
	armor_modifier.operation = StatModifier.Operation.MULTIPLY
	armor_modifier.value = threshold_guard_armor_multiplier
	add_temporary_modifier(armor_modifier, threshold_guard_duration, self, threshold_guard_ability_id, threshold_guard_effect_id)
	threshold_guard_cooldown_remaining = threshold_guard_cooldown
	if unit_sprite_skill_overrides_attack:
		queued_reactive_skill = true


func _try_melee_teleport(attacker: Combatant) -> void:
	if melee_teleport_distance <= 0.0 or melee_teleport_cooldown_remaining > 0.0:
		return
	var direction := (position - attacker.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.LEFT if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	var destination := position + direction * melee_teleport_distance
	var previous_feet := feet_position()
	position = _clamp_navigation_point(destination)
	session.spawn_blink_vfx(self, previous_feet, melee_teleport_ability_id)
	melee_teleport_cooldown_remaining = melee_teleport_cooldown
	pending_ability = null
	target = null
	state = State.ACQUIRE_TARGET


func _refresh_body_radius() -> void:
	var multiplier := 1.0
	for empowerment in basic_attack_empowerments:
		multiplier *= float(empowerment.size_multiplier)
	body_radius = base_body_radius * multiplier
	visual_radius = base_visual_radius * multiplier
	var collision_shape := $CollisionShape2D.shape as CircleShape2D
	if collision_shape != null:
		collision_shape.radius = body_radius
	position = _clamp_navigation_point(position)
	queue_redraw()


func _apply_modifier(base_value: float, modifier: StatModifier, stack_count: int) -> float:
	if modifier == null:
		return base_value
	return modifier.apply_to(base_value, stack_count)


## Step-driven movement with terrain collision. Never use renderer/physics frame
## time here: Balance Lab advances the same movement manually at a fixed delta.
func _slide(delta: float) -> void:
	var before := position
	position = ARENA_GEOMETRY.move_point(position, position + velocity * delta, arena_bounds, body_radius)
	if delta > 0.0:
		velocity = (position - before) / delta


func _update_stuck_state(delta: float) -> void:
	if position.distance_squared_to(last_movement_position) < 0.25:
		stuck_time += delta
	else:
		stuck_time = 0.0
		last_movement_position = position

	if stuck_time < STUCK_TIMEOUT:
		return

	stuck_time = 0.0
	approach_target = null
	approach_committed = false
	target = null
	state = State.ACQUIRE_TARGET


func _update_boss_phase() -> void:
	if not snapshot.is_boss or boss_phase >= snapshot.boss_phase_count:
		return
	var health_ratio := current_hp / maxf(snapshot.stats.max_hp, 1.0)
	while boss_phase < snapshot.boss_phase_count:
		var threshold_index := boss_phase - 1
		if threshold_index >= snapshot.boss_phase_health_thresholds.size() or health_ratio > snapshot.boss_phase_health_thresholds[threshold_index]:
			break
		boss_phase += 1
		phase_banner_timer = 1.5
		ability_cooldowns.clear()
		session.record_event(
			CombatEvent.BOSS_PHASE_CHANGED,
			snapshot.runtime_id,
			"",
			&"",
			&"boss.phase",
			float(boss_phase)
		)
	queue_redraw()


func _draw() -> void:
	var color := snapshot.placeholder_color
	if stealth_remaining > 0.0:
		color.a = 0.35
	if state == State.DEAD:
		color = color.darkened(0.65)
	if flash_remaining > 0.0:
		color = flash_color

	if not unit_sprite.visible and placeholder_medallion == null:
		if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
			draw_circle(Vector2.ZERO, visual_radius, color)
			draw_arc(Vector2.ZERO, visual_radius, 0.0, TAU, 32, Color.WHITE, 2.0)
		else:
			draw_rect(Rect2(Vector2(-visual_radius, -visual_radius), Vector2.ONE * visual_radius * 2.0), color)
	if snapshot.is_boss and ground_marker == null:
		draw_arc(Vector2.ZERO, visual_radius + 5.0, 0.0, TAU, 40, snapshot.boss_telegraph_color, 3.0)
		for phase_ring in range(1, boss_phase):
			draw_arc(Vector2.ZERO, visual_radius + 5.0 + phase_ring * 4.0, 0.0, TAU, 40, snapshot.boss_telegraph_color.lightened(0.2), 2.0)
	if selected and ground_marker == null:
		draw_arc(Vector2.ZERO, visual_radius + 7.0, 0.0, TAU, 32, Color(1.0, 0.86, 0.35), 3.0)

	if state == State.DEAD:
		if not unit_sprite.visible or not unit_sprite.sprite_frames.has_animation(&"death"):
			draw_line(Vector2(-10, -10), Vector2(10, 10), Color.WHITE, 3.0)
			draw_line(Vector2(10, -10), Vector2(-10, 10), Color.WHITE, 3.0)
		return
	if snapshot.is_boss and state == State.ATTACK_WINDUP and ground_marker == null:
		var progress := 1.0 - state_timer / maxf(windup_duration, 0.01)
		draw_arc(Vector2.ZERO, visual_radius + 13.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, snapshot.boss_telegraph_color, 5.0)


func _update_health_trail(delta: float) -> void:
	var ratio := clampf(current_hp / maxf(get_effective_stat(&"max_hp"), 1.0), 0.0, 1.0)
	if last_visual_health_ratio < 0.0 or ratio > last_visual_health_ratio:
		health_trail_ratio = ratio
		health_trail_delay = 0.0
	elif ratio < last_visual_health_ratio:
		health_trail_delay = 0.3
	else:
		health_trail_delay = maxf(0.0, health_trail_delay - delta)
	if health_trail_delay <= 0.0:
		health_trail_ratio = move_toward(health_trail_ratio, ratio, delta * 0.8)
	last_visual_health_ratio = ratio


func overhead_bar_rect() -> Rect2:
	var width := 72.0 if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else 56.0
	if snapshot.is_boss:
		width = 96.0
	elif snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON:
		width = 36.0
	var y := -health_bar_offset if health_bar_offset > 0.0 else -visual_radius - 11.0
	return Rect2(Vector2(-width * 0.5, y), Vector2(width, 6.0))


func overhead_health_color() -> Color:
	return Color(0.28, 0.86, 0.38) if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Color(0.9, 0.31, 0.25)


func draw_overhead(canvas: Node2D) -> void:
	if state == State.DEAD:
		return
	if snapshot.is_boss and state == State.ATTACK_WINDUP:
		var warning := pending_ability.presentation_text if pending_ability != null and not pending_ability.presentation_text.is_empty() else "INCOMING ATTACK"
		canvas.draw_string(ThemeDB.get_project_theme().default_font, Vector2(-visual_radius * 2.0, -visual_radius - 28.0), warning, HORIZONTAL_ALIGNMENT_CENTER, visual_radius * 4.0, 12, snapshot.boss_telegraph_color)
	if snapshot.is_boss and phase_banner_timer > 0.0:
		canvas.draw_string(ThemeDB.get_project_theme().default_font, Vector2(-visual_radius * 3.0, visual_radius + 30.0), snapshot.boss_phase_telegraph_text, HORIZONTAL_ALIGNMENT_CENTER, visual_radius * 6.0, 13, snapshot.boss_telegraph_color)

	var max_hp := maxf(get_effective_stat(&"max_hp"), 1.0)
	var health_ratio := clampf(current_hp / max_hp, 0.0, 1.0)
	var bar_rect := overhead_bar_rect()
	var rim := Color(0.72, 0.57, 0.31, 0.9) if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO or snapshot.is_boss else Color(0.03, 0.025, 0.02, 0.95)
	canvas.draw_rect(bar_rect.grow(2.0), Color(0.015, 0.012, 0.01, 0.8))
	canvas.draw_rect(bar_rect.grow(1.0), rim, false, 1.0)
	canvas.draw_rect(bar_rect, Color(0.07, 0.045, 0.035, 0.95))
	if health_trail_ratio > health_ratio:
		canvas.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_trail_ratio, bar_rect.size.y)), Color(0.85, 0.63, 0.3, 0.75))
	var fill := Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_ratio, bar_rect.size.y))
	canvas.draw_rect(fill, overhead_health_color())
	if fill.size.x > 0.0:
		canvas.draw_line(fill.position, fill.position + Vector2(fill.size.x, 0), Color(1.0, 1.0, 1.0, 0.3), 1.0)
	var shield_total := 0.0
	for shield in shields:
		shield_total += maxf(0.0, float(shield.amount))
	if shield_total > 0.0:
		var shield_rect := Rect2(bar_rect.position + Vector2(0, -5), Vector2(bar_rect.size.x, 3))
		canvas.draw_rect(shield_rect.grow(1.0), Color(0.015, 0.025, 0.04, 0.95))
		canvas.draw_rect(Rect2(shield_rect.position, Vector2(shield_rect.size.x * minf(1.0, shield_total / max_hp), 3)), Color(0.45, 0.8, 1.0))
	var control_text := "STUN" if is_stunned() else ("FEAR" if is_feared() else ("ROOT" if is_rooted() else ""))
	if not control_text.is_empty():
		var font := ThemeDB.get_project_theme().default_font
		var label_width := font.get_string_size(control_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
		var label_rect := Rect2(Vector2(-label_width * 0.5, bar_rect.position.y - 23.0), Vector2(label_width, 15.0))
		canvas.draw_rect(label_rect, Color(0.035, 0.025, 0.055, 0.92))
		canvas.draw_string(font, label_rect.position + Vector2(5, 11), control_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.88, 0.77, 1.0))
	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SOLDIER and snapshot.veterancy_level >= 0:
		# Rank chevrons just left of the health bar, readable without selecting the unit.
		var pulse := 0.0
		if veterancy_banner_timer > 0.0:
			pulse = sin(clampf(1.0 - veterancy_banner_timer / VETERANCY_BANNER_TIME, 0.0, 1.0) * PI)
		VeterancyInsignia.draw_insignia(canvas, Vector2(bar_rect.position.x - 9.0, bar_rect.get_center().y), snapshot.veterancy_level, 13.0 + 9.0 * pulse)
	if veterancy_banner_timer > 0.0:
		_draw_veterancy_banner(canvas, bar_rect)


## "RANK UP" rising above the health bar, fading in and out.
func _draw_veterancy_banner(canvas: Node2D, bar_rect: Rect2) -> void:
	var t := 1.0 - veterancy_banner_timer / VETERANCY_BANNER_TIME
	var alpha := clampf(t / 0.12, 0.0, 1.0) * clampf((1.0 - t) / 0.3, 0.0, 1.0)
	var font := ThemeDB.get_project_theme().default_font
	var text := "RANK UP"
	var size := 15
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(-width * 0.5, bar_rect.position.y - 14.0 - 26.0 * t)
	canvas.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.12, 0.06, 0.0, 0.85 * alpha))
	canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.86, 0.42, alpha))
