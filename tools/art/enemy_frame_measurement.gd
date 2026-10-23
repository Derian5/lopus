extends RefCounted

## Measure the legs relative to standing height, not the current whole-frame
## bounds: raised weapons/spell trails must not pull the body anchor sideways.
static func body_anchor(image: Image, standing_height: float) -> Vector2:
	var bounds := image.get_used_rect()
	var bottom := bounds.end.y - 1
	for y in range(bounds.end.y - 1, bounds.position.y - 1, -1):
		var solid := 0
		for x in range(bounds.position.x, bounds.end.x, 2):
			if image.get_pixel(x, y).a >= 0.5:
				solid += 1
		if solid >= 3:
			bottom = y
			break
	var xs: Array[int] = []
	var band_top := maxi(bounds.position.y, bottom - roundi(standing_height * 0.35))
	var band_bottom := maxi(band_top, bottom - roundi(standing_height * 0.12))
	for y in range(band_top, band_bottom + 1, 2):
		for x in range(bounds.position.x, bounds.end.x, 2):
			if image.get_pixel(x, y).a >= 0.5:
				xs.append(x)
	xs.sort()
	# A median jumps from one leg to the other when their pixel counts cross.
	# A trimmed centroid follows both legs smoothly and ignores thin outliers.
	var center_x := float(bounds.get_center().x)
	if not xs.is_empty():
		var trim := xs.size() / 10
		var sum_x := 0.0
		for index in range(trim, xs.size() - trim):
			sum_x += xs[index]
		center_x = sum_x / float(xs.size() - trim * 2)
	return Vector2(center_x, bottom)
