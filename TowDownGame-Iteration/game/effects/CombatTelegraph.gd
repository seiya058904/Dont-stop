extends RefCounted
# Shared world-space language. Fill = footprint, advancing light = time, chevrons = direction.
static func paint(canvas: Node2D, kind: String, direction: Vector2, radius: float, length: float, width: float, angle: float, progress: float, active: bool, sweep = 0.0):
	var p = clampf(progress,0,1)
	var pulse = 0.5+0.5*sin(p*PI*16) if p>0.72 else p
	var edge = Color(1,0.55+0.22*p,0.19,0.72+0.26*pulse)
	var fill = Color(0.95,0.23,0.08,0.09+0.13*p)
	if active: edge = Color(1,0.86,0.52,0.95); fill = Color(1,0.3,0.06,0.3)
	if kind in ["line","charge"]:
		var normal = direction.orthogonal()*width
		var points = PackedVector2Array([-normal,direction*length-normal,direction*length+normal,normal])
		canvas.draw_colored_polygon(points,fill)
		for side in [-1,1]:
			var start = normal*side; var end = direction*length+normal*side
			canvas.draw_line(start,end,Color(0.13,0.04,0.02,0.65),3,true)
			canvas.draw_line(start,end,edge,1.1+0.6*pulse,true)
		if kind == "charge":
			for i in int(length/26.0):
				var point = direction*fposmod(i*26.0+p*52.0,length)
				canvas.draw_polyline(PackedVector2Array([point-direction*5-normal*0.42,point,point-direction*5+normal*0.42]),Color(1,0.65,0.3,0.28+0.45*p),1.3,true)
		else:
			canvas.draw_line(Vector2.ZERO,direction*length,edge,width*1.5 if active else 0.8,true)
			if active: canvas.draw_line(Vector2.ZERO,direction*length,Color(1,0.95,0.77,0.9),width*0.45,true)
		if sweep != 0 and not active:
			var sector = PackedVector2Array([Vector2.ZERO])
			for i in 25: sector.append(direction.rotated(sweep*i/24.0)*length)
			canvas.draw_colored_polygon(sector,Color(1,0.25,0.05,0.06))
			canvas.draw_line(Vector2.ZERO,direction.rotated(sweep)*length,edge*Color(1,1,1,0.6),1,true)
			var turn = direction.rotated(sweep*p)*length*0.65
			var tangent = turn.normalized().orthogonal()*signf(sweep)
			canvas.draw_polyline(PackedVector2Array([turn-tangent*7-turn.normalized()*4,turn,turn-tangent*7+turn.normalized()*4]),edge,1.8,true)
	elif kind == "cone":
		var points = PackedVector2Array([Vector2.ZERO])
		for i in 33: points.append(direction.rotated(lerpf(-angle,angle,i/32.0))*radius)
		canvas.draw_colored_polygon(points,fill)
		points.append(Vector2.ZERO)
		canvas.draw_polyline(points,edge,1.6,true)
		canvas.draw_arc(Vector2.ZERO,radius*p,direction.angle()-angle,direction.angle()+angle,24,edge*Color(1,1,1,0.55),2,true)
		canvas.draw_line(direction*radius*0.3,direction*radius*0.55,edge,1.2,true)
	else:
		canvas.draw_circle(Vector2.ZERO,radius,fill)
		canvas.draw_arc(Vector2.ZERO,radius,0,TAU,64,Color(0.12,0.04,0.02,0.8),4,true)
		canvas.draw_arc(Vector2.ZERO,radius,0,TAU,64,edge,1.6+0.5*pulse,true)
		canvas.draw_arc(Vector2.ZERO,radius*(1.0-p),0,TAU,48,edge*Color(1,1,1,0.7),1.5,true)
		canvas.draw_arc(Vector2.ZERO,radius+3,-PI/2,-PI/2+TAU*p,48,edge,2,true)
		for i in 4:
			var dir = Vector2.RIGHT.rotated(i*PI/2)
			canvas.draw_line(dir*4,dir*9,edge,1.4,true)
	# Common origin charge halo, never an opaque screen flash.
	canvas.draw_arc(Vector2.ZERO,5+4*p,0,TAU,20,edge,1.4,true)
