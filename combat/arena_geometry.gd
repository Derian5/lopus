extends RefCounted

## Static battlefield cutouts in normalized WALKABLE bounds (the sky is already
## excluded by CombatSession). Shared by combat, deployment and the Balance Lab.
## Side ruins above the central lane, then the two foreground corner piles.
const CUTOUTS := [
	[Vector2(0, 0), Vector2(0.32, 0), Vector2(0.31, 0.065), Vector2(0.24, 0.17), Vector2(0.08, 0.27), Vector2(0, 0.30)],
	[Vector2(0.75, 0), Vector2(1, 0), Vector2(1, 0.35), Vector2(0.81, 0.30), Vector2(0.75, 0.23)],
	[Vector2(0, 0.59), Vector2(0.09, 0.68), Vector2(0.17, 0.81), Vector2(0.23, 1), Vector2(0, 1)],
	[Vector2(1, 0.66), Vector2(1, 1), Vector2(0.82, 1), Vector2(0.84, 0.90), Vector2(0.88, 0.80)],
]
static var _regions: Dictionary = {}


static func blocked_polygons(bounds: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for cutout in CUTOUTS:
		var points := PackedVector2Array()
		for point in cutout:
			points.append(bounds.position + point * bounds.size)
		result.append(points)
	return result


static func _largest(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var result := PackedVector2Array()
	var largest_area := -1.0
	for points in polygons:
		var area := 0.0
		for index in points.size():
			area += points[index].cross(points[(index + 1) % points.size()])
		if absf(area) > largest_area:
			largest_area = absf(area)
			result = points
	return result


static func polygon(bounds: Rect2, radius := 0.0) -> PackedVector2Array:
	if not _regions.has(bounds):
		var base := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		for blocked in blocked_polygons(bounds):
			base = _largest(Geometry2D.clip_polygons(base, blocked))
		_regions[bounds] = {0.0: {"polygon": base}}
	var sizes: Dictionary = _regions[bounds]
	if not sizes.has(radius):
		var inset := _largest(Geometry2D.offset_polygon(sizes[0.0].polygon, -radius, Geometry2D.JOIN_MITER))
		if inset.is_empty():
			# Degenerate tiny test arenas / oversized units still have a safe centre.
			var center := bounds.get_center()
			inset = PackedVector2Array([center + Vector2(-0.01, -0.01), center + Vector2(0.01, -0.01), center + Vector2(0.01, 0.01), center + Vector2(-0.01, 0.01)])
		sizes[radius] = {"polygon": inset}
	return sizes[radius].polygon


## Open part of an entry line inset from one rectangular edge: right, bottom,
## left, top. Cutouts can shorten the line but cannot move entry to another side.
static func entry_segment(bounds: Rect2, side: int, inset: float, radius: float) -> PackedVector2Array:
	var from: Vector2
	var to: Vector2
	if side == 0 or side == 2:
		var x := bounds.end.x - inset if side == 0 else bounds.position.x + inset
		from = Vector2(x, bounds.position.y)
		to = Vector2(x, bounds.end.y)
	else:
		var y := bounds.end.y - inset if side == 1 else bounds.position.y + inset
		from = Vector2(bounds.position.x, y)
		to = Vector2(bounds.end.x, y)
	var points := polygon(bounds, radius)
	var hits: Array[Vector2] = []
	for index in points.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, points[index], points[(index + 1) % points.size()])
		if hit != null:
			hits.append(hit)
	if hits.size() < 2:
		var safe := clamp_point((from + to) * 0.5, bounds, radius)
		return PackedVector2Array([safe, safe])
	hits.sort_custom(func(a: Vector2, b: Vector2) -> bool: return from.distance_squared_to(a) < from.distance_squared_to(b))
	return PackedVector2Array([hits[0], hits[-1]])


static func contains(point: Vector2, bounds: Rect2, radius := 0.0) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon(bounds, radius))


static func clamp_point(point: Vector2, bounds: Rect2, radius := 0.0) -> Vector2:
	var points := polygon(bounds, radius)
	if Geometry2D.is_point_in_polygon(point, points):
		return point
	var best := bounds.get_center()
	var best_distance := INF
	for index in points.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
		var distance := point.distance_squared_to(candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


static func _segment_clear(from: Vector2, to: Vector2, points: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon((from + to) * 0.5, points):
		return false
	for index in points.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, points[index], points[(index + 1) % points.size()])
		if hit != null and Vector2(hit).distance_squared_to(from) > 0.0001 and Vector2(hit).distance_squared_to(to) > 0.0001:
			return false
	return true


static func segment_is_walkable(from: Vector2, to: Vector2, bounds: Rect2, radius := 0.0) -> bool:
	var points := polygon(bounds, radius)
	return Geometry2D.is_point_in_polygon(from, points) and Geometry2D.is_point_in_polygon(to, points) and _segment_clear(from, to, points)


## Small cached visibility graph. Only obstructed routes use Dijkstra; normal
## centre-field movement goes straight through the cheap line-of-sight check.
## Stable vertex order and comparisons; never touches a random stream.
static func next_waypoint(from: Vector2, goal: Vector2, bounds: Rect2, radius: float) -> Vector2:
	var points := polygon(bounds, radius)
	var start := clamp_point(from, bounds, radius)
	goal = clamp_point(goal, bounds, radius)
	if _segment_clear(start, goal, points):
		return goal
	var region: Dictionary = _regions[bounds][radius]
	var count := points.size()
	if not region.has("graph"):
		var graph: Array = []
		for index in count:
			var neighbours: Array[int] = []
			for other in count:
				if other != index and _segment_clear(points[index], points[other], points):
					neighbours.append(other)
			graph.append(neighbours)
		region.graph = graph
	var costs: Array[float] = []
	var first_hops: Array[int] = []
	var visited: Array[bool] = []
	var sees_goal: Array[bool] = []
	for index in count:
		costs.append(start.distance_to(points[index]) if _segment_clear(start, points[index], points) else INF)
		first_hops.append(index)
		visited.append(false)
		sees_goal.append(_segment_clear(points[index], goal, points))
	var best_cost := INF
	var best_hop := -1
	for iteration in count:
		var current := -1
		var smallest := INF
		for index in count:
			if not visited[index] and costs[index] < smallest:
				current = index
				smallest = costs[index]
		if current < 0 or smallest >= best_cost:
			break
		visited[current] = true
		if sees_goal[current]:
			var total := smallest + points[current].distance_to(goal)
			if total < best_cost:
				best_cost = total
				best_hop = first_hops[current]
		for neighbour in region.graph[current]:
			var cost := smallest + points[current].distance_to(points[neighbour])
			if cost < costs[neighbour]:
				costs[neighbour] = cost
				first_hops[neighbour] = first_hops[current]
	return points[best_hop] if best_hop >= 0 else start


## Collision for a whole simulation step, including fast knockback: stop at the
## first wall instead of tunnelling through a cutout, then slide along its edge.
static func move_point(from: Vector2, to: Vector2, bounds: Rect2, radius: float) -> Vector2:
	from = clamp_point(from, bounds, radius)
	var points := polygon(bounds, radius)
	if Geometry2D.is_point_in_polygon(to, points) and _segment_clear(from, to, points):
		return to
	var hit_point := from
	var edge := Vector2.ZERO
	var closest := INF
	var heading_inside := Geometry2D.is_point_in_polygon(from.move_toward(to, 0.05), points)
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, a, b)
		if hit == null:
			continue
		var distance := from.distance_squared_to(hit)
		if distance < 0.0001 and heading_inside:
			continue
		if distance < closest:
			closest = distance
			hit_point = hit
			edge = (b - a).normalized()
	if closest == INF:
		return clamp_point(to, bounds, radius)
	var stop := clamp_point(hit_point.move_toward(from, 0.01), bounds, radius)
	var slide := clamp_point(stop + (to - hit_point).project(edge), bounds, radius)
	return slide if _segment_clear(stop, slide, points) else stop
