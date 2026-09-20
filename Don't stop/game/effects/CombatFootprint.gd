extends RefCounted
class_name CombatFootprint

# A shared, wall-clipped footprint for radial visuals and point damage tests.
static func polygon(center: Vector2, radius: float, direction = Vector2.RIGHT, half_angle = PI) -> PackedVector2Array:
	var measured := Time.get_ticks_usec() if B11Probe.enabled else 0
	var result = PackedVector2Array()
	if half_angle < PI: result.append(center)
	var segments = maxi(16,ceili(64*half_angle/PI))
	# No callbacks or tree mutations occur inside this loop: the exclusion snapshot
	# and world are identical for all rays. Copy once, keep every authored ray.
	if Combat.exclusions_dirty: Combat._refresh_exclusions()
	var query = PhysicsRayQueryParameters2D.create(center,center,2147483649)
	query.exclude = Combat.actor_exclusions
	var space = Utils.player.get_world_2d().direct_space_state
	for i in range(segments+1 if half_angle < PI else segments):
		var endpoint = center+direction.rotated(lerpf(-half_angle,half_angle,float(i)/segments))*radius
		query.to = endpoint
		var hit = space.intersect_ray(query)
		result.append(hit.get("position",endpoint))
	if B11Probe.enabled: B11Probe.cost("footprint",measured)
	return result
