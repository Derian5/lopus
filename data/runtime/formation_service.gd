class_name FormationService
extends RefCounted


## Starting positions of the player's army.
##
## Custom positions are stored in RunState.formation_positions as normalized
## coordinates (0..1) of the combat arena bounds, keyed by Hero/Soldier unique_id,
## so they survive different arena sizes and Save/Load. Units without a custom
## position use the automatic formation (the original deterministic layout).

## Player deployment zone in normalized arena coordinates.
const DEPLOY_ZONE := Rect2(0.02, 0.05, 0.40, 0.90)
## Reference arena size used to normalize the automatic layout in previews.
const REFERENCE_ARENA := Vector2(1748.0, 798.0)
const GRID_STEP := Vector2(1.0 / 48.0, 1.0 / 22.0)
const MIN_SPACING := 0.028
const AUTOMATIC_SPACING := 96.0


## Automatic layout in arena pixels, front to back: melee units (Soldiers, summons,
## enemies), then melee Heroes, then every ranged unit. Up to six per column.
static func automatic_positions(snapshots: Array[CombatUnitSnapshot], bounds: Rect2, player_team: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var row_spacing := minf(AUTOMATIC_SPACING, bounds.size.y / 7.0)
	var rows := 6
	var group_counts := [0, 0, 0]
	for snapshot in snapshots:
		group_counts[formation_group(snapshot)] += 1
	var group_first_column := [0, 0, 0]
	var total_columns := 0
	for group in 3:
		group_first_column[group] = total_columns
		total_columns += ceili(float(group_counts[group]) / rows)
	total_columns = maxi(total_columns, 1)
	var back_inset := minf(125.0, bounds.size.x * 0.1)
	var available_depth := maxf(0.0, bounds.size.x * DEPLOY_ZONE.end.x - back_inset)
	var column_spacing := minf(AUTOMATIC_SPACING, available_depth / maxi(total_columns - 1, 1))
	var front_x := bounds.position.x + back_inset + (total_columns - 1) * column_spacing
	if not player_team:
		front_x = bounds.end.x - back_inset - (total_columns - 1) * column_spacing
	var group_index := [0, 0, 0]
	for snapshot in snapshots:
		var group := formation_group(snapshot)
		var formation_index: int = group_index[group]
		var formation_column: int = group_first_column[group] + formation_index / rows
		var x := front_x - formation_column * column_spacing if player_team else front_x + formation_column * column_spacing
		var row := formation_index % rows
		var used_rows := mini(rows, group_counts[group] - (formation_index / rows) * rows)
		var y_offset := (row - (used_rows - 1) * 0.5) * row_spacing
		result.append(Vector2(x, bounds.get_center().y + y_offset))
		group_index[group] += 1
	return result


## 0 = melee non-Hero (front line), 1 = melee Hero, 2 = ranged (back line).
static func formation_group(snapshot: CombatUnitSnapshot) -> int:
	if snapshot.attack_type == &"ranged":
		return 2
	return 1 if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else 0


## Spawn positions in arena pixels (aligned with snapshots): custom where set, automatic otherwise.
static func spawn_positions(snapshots: Array[CombatUnitSnapshot], bounds: Rect2, player_team: bool) -> Array[Vector2]:
	var result := automatic_positions(snapshots, bounds, player_team)
	if not player_team:
		return result
	for index in snapshots.size():
		if has_custom(snapshots[index].formation_position):
			result[index] = bounds.position + clamp_to_zone(snapshots[index].formation_position) * bounds.size
	return result


## Normalized positions for every unit, using the reference arena for automatic ones.
static func normalized_positions(snapshots: Array[CombatUnitSnapshot], player_team := true) -> Dictionary:
	var bounds := Rect2(Vector2.ZERO, REFERENCE_ARENA)
	var pixels := spawn_positions(snapshots, bounds, player_team)
	var result := {}
	for index in snapshots.size():
		result[snapshots[index].runtime_id] = pixels[index] / REFERENCE_ARENA
	return result


static func has_custom(position: Vector2) -> bool:
	return position.x >= 0.0 and position.y >= 0.0


static func clamp_to_zone(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, DEPLOY_ZONE.position.x, DEPLOY_ZONE.end.x),
		clampf(position.y, DEPLOY_ZONE.position.y, DEPLOY_ZONE.end.y)
	)


static func snap(position: Vector2) -> Vector2:
	return clamp_to_zone(Vector2(
		roundf(position.x / GRID_STEP.x) * GRID_STEP.x,
		roundf(position.y / GRID_STEP.y) * GRID_STEP.y
	))


## Stores a full formation (every current unit) so later moves never shuffle the rest.
static func store_formation(run_state: RunState, positions: Dictionary) -> void:
	run_state.formation_positions.clear()
	for unit_id in positions:
		run_state.formation_positions[String(unit_id)] = clamp_to_zone(Vector2(positions[unit_id]))


static func reset(run_state: RunState) -> void:
	run_state.formation_positions.clear()


## Drops positions of units that no longer exist (dead soldiers, executed heroes).
static func prune(run_state: RunState) -> void:
	var alive_ids := {}
	for hero in run_state.heroes:
		if hero.life_state == HeroState.ALIVE:
			alive_ids[hero.unique_id] = true
	for soldier in run_state.soldiers:
		alive_ids[soldier.unique_id] = true
	for unit_id in run_state.formation_positions.keys():
		if not alive_ids.has(String(unit_id)):
			run_state.formation_positions.erase(unit_id)


static func position_for(run_state: RunState, unit_id: String) -> Vector2:
	if run_state == null or not run_state.formation_positions.has(unit_id):
		return Vector2(-1.0, -1.0)
	return Vector2(run_state.formation_positions[unit_id])


static func to_serializable(positions: Dictionary) -> Dictionary:
	var data := {}
	for unit_id in positions:
		var position := Vector2(positions[unit_id])
		data[String(unit_id)] = [position.x, position.y]
	return data


static func from_serializable(data: Variant) -> Dictionary:
	var result := {}
	if not data is Dictionary:
		return result
	for unit_id in data:
		var value = data[unit_id]
		if value is Array and value.size() == 2:
			result[String(unit_id)] = clamp_to_zone(Vector2(float(value[0]), float(value[1])))
	return result
