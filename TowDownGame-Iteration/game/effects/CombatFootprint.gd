extends RefCounted
class_name CombatFootprint

# A shared, wall-clipped footprint for radial visuals and point damage tests.
static func polygon(center: Vector2, radius: float, direction = Vector2.RIGHT, half_angle = PI) -> PackedVector2Array:
	var result = PackedVector2Array()
	if half_angle < PI: result.append(center)
	var segments = maxi(16,ceili(64*half_angle/PI))
	for i in range(segments+1 if half_angle < PI else segments):
		var endpoint = center+direction.rotated(lerpf(-half_angle,half_angle,float(i)/segments))*radius
		var query = PhysicsRayQueryParameters2D.create(center,endpoint,2147483649)
		if Combat.exclusions_dirty: Combat._refresh_exclusions()
		query.exclude = Combat.actor_exclusions
		var hit = Utils.player.get_world_2d().direct_space_state.intersect_ray(query)
		result.append(hit.get("position",endpoint))
	return result
