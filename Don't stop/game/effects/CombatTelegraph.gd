extends RefCounted
# Shared world-space language. Fill = footprint, advancing light = time, chevrons = direction.
static func segments(radius: float, radians = TAU):
	# At the native pixel viewport this bounds chord error below half a pixel.
	return clampi(int(ceil(absf(radians)*sqrt(maxf(radius,1.0))))+1,12,64)
static func geometry(kind: String, direction: Vector2, radius: float, length: float, width: float, angle: float, sweep: float, cache: Dictionary):
	var key = [kind,direction,radius,length,width,angle,sweep]
	if cache.get("key") == key: return cache
	cache.clear(); cache.key = key
	var normal = direction.orthogonal()*width
	cache.box = PackedVector2Array([-normal,direction*length-normal,direction*length+normal,normal])
	cache.sides = PackedVector2Array([-normal,direction*length-normal,normal,direction*length+normal])
	var cone = PackedVector2Array([Vector2.ZERO])
	var count = segments(radius,angle*2)
	for i in count: cone.append(direction.rotated(lerpf(-angle,angle,i/float(count-1)))*radius)
	cache.cone = cone
	cone.append(Vector2.ZERO); cache.cone_edge = cone
	var sector = PackedVector2Array([Vector2.ZERO])
	count = segments(length,sweep)
	for i in count: sector.append(direction.rotated(sweep*i/float(count-1))*length)
	cache.sector = sector
	var ring = PackedVector2Array()
	count = segments(radius)
	for i in count: ring.append(Vector2.RIGHT.rotated(TAU*i/float(count-1))*radius)
	cache.ring = ring
	var marks = PackedVector2Array()
	for i in 4:
		var dir = Vector2.RIGHT.rotated(i*PI/2)
		marks.append(dir*4); marks.append(dir*9)
	cache.marks = marks
	return cache
static func paint(canvas: Node2D, kind: String, direction: Vector2, radius: float, length: float, width: float, angle: float, progress: float, active: bool, sweep = 0.0, cache: Dictionary = {}, detail = true):
	var shape = geometry(kind,direction,radius,length,width,angle,sweep,cache)
	var p = clampf(progress,0,1)
	var pulse = 0.5+0.5*sin(p*PI*16) if p>0.72 else p
	var edge = Color(1,0.55+0.22*p,0.19,0.72+0.26*pulse)
	var fill = Color(0.95,0.23,0.08,0.09+0.13*p)
	if active: edge = Color(1,0.86,0.52,0.95); fill = Color(1,0.3,0.06,0.3)
	if kind in ["line","charge"]:
		var normal = direction.orthogonal()*width
		canvas.draw_colored_polygon(shape.box,fill)
		canvas.draw_multiline(shape.sides,Color(0.13,0.04,0.02,0.65),3,true)
		canvas.draw_multiline(shape.sides,edge,1.1+0.6*pulse,true)
		if kind == "charge":
			var arrows = PackedVector2Array()
			for i in int(length/26.0):
				var point = direction*fposmod(i*26.0+p*52.0,length)
				arrows.append_array(PackedVector2Array([point-direction*5-normal*0.42,point,point,point-direction*5+normal*0.42]))
			if not arrows.is_empty(): canvas.draw_multiline(arrows,Color(1,0.65,0.3,0.28+0.45*p),1.3,true)
		else:
			canvas.draw_line(Vector2.ZERO,direction*length,edge,width*1.5 if active else 0.8,true)
			if active: canvas.draw_line(Vector2.ZERO,direction*length,Color(1,0.95,0.77,0.9),width*0.45,true)
		if sweep != 0 and not active:
			canvas.draw_colored_polygon(shape.sector,Color(1,0.25,0.05,0.06))
			canvas.draw_line(Vector2.ZERO,direction.rotated(sweep)*length,edge*Color(1,1,1,0.6),1,true)
			var turn = direction.rotated(sweep*p)*length*0.65
			var tangent = turn.normalized().orthogonal()*signf(sweep)
			canvas.draw_polyline(PackedVector2Array([turn-tangent*7-turn.normalized()*4,turn,turn-tangent*7+turn.normalized()*4]),edge,1.8,true)
	elif kind == "cone":
		canvas.draw_colored_polygon(shape.cone,fill)
		canvas.draw_polyline(shape.cone_edge,Color(0.12,0.04,0.02,0.8),4,true)
		canvas.draw_polyline(shape.cone_edge,edge,1.6,true)
		canvas.draw_arc(Vector2.ZERO,radius*p,direction.angle()-angle,direction.angle()+angle,segments(radius*p,angle*2),edge*Color(1,1,1,0.55),2,true)
		canvas.draw_line(direction*radius*0.3,direction*radius*0.55,edge,1.2,true)
	else:
		canvas.draw_circle(Vector2.ZERO,radius,fill)
		canvas.draw_polyline(shape.ring,Color(0.12,0.04,0.02,0.8),4,true)
		canvas.draw_polyline(shape.ring,edge,1.6+0.5*pulse,true)
		canvas.draw_arc(Vector2.ZERO,radius*(1.0-p),0,TAU,segments(radius*(1.0-p)),edge*Color(1,1,1,0.7),1.5,true)
		canvas.draw_arc(Vector2.ZERO,radius+3,-PI/2,-PI/2+TAU*p,segments(radius+3,TAU*p),edge,2,true)
		if kind == "summon":
			# Three emerging buds distinguish summoning from an impact footprint.
			for i in 3:
				var center = Vector2.RIGHT.rotated(-PI/2+i*TAU/3)*radius*0.48
				canvas.draw_arc(center,4+3*p,0,TAU,12,edge,2,true)
		else: canvas.draw_multiline(shape.marks,edge,1.4,true)
	# Common origin charge halo, never an opaque screen flash.
	if detail or kind == "summon": canvas.draw_arc(Vector2.ZERO,5+4*p,0,TAU,segments(5+4*p),edge,1.4,true)
