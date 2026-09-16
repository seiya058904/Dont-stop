extends RefCounted
# Shared world-space language. Fill = footprint, advancing light = time, chevrons = direction.
#
# B批 adds a STYLE dimension: every attack family now has its own palette so the player can
# tell "what is about to happen" from colour alone, before reading the shape. Collision,
# timing and geometry are untouched - only the ink changes. `generic` is exactly the
# palette this file shipped with, so any caller that passes no style renders as before.
#
# Palette contract, asserted by tests/B1Telegraphs.gd:
#   charge      orange    dash lane with flowing arrows
#   detonate    red       shrinking ring + countdown
#   projectile  amber     muzzle/trail family
#   laser       cyan      thin warning line that brightens in the last 0.2-0.3 s
#   sweep       magenta   rotating line with the turning chevron
#   artillery   amber     ground target + timing ring
#   root        purple    control attack
#   poison      green     area denial
#   ice         cyan      frost burst
#   shock       violet    energy band
#   summon      pale blue emerging buds
const STYLES = {
	"generic":   {"edge":Color(1,0.55,0.19),"edge_hot":Color(1,0.86,0.52),"fill":Color(0.95,0.23,0.08),"active":Color(1,0.86,0.52),"active_fill":Color(1,0.3,0.06)},
	"charge":    {"edge":Color(1,0.58,0.16),"edge_hot":Color(1,0.90,0.45),"fill":Color(0.95,0.32,0.05),"active":Color(1,0.92,0.55),"active_fill":Color(1,0.36,0.06)},
	"detonate":  {"edge":Color(1,0.30,0.28),"edge_hot":Color(1,0.72,0.62),"fill":Color(0.92,0.12,0.12),"active":Color(1,0.68,0.55),"active_fill":Color(1,0.20,0.12)},
	"projectile":{"edge":Color(1,0.70,0.22),"edge_hot":Color(1,0.94,0.62),"fill":Color(0.98,0.55,0.10),"active":Color(1,0.95,0.65),"active_fill":Color(1,0.62,0.14)},
	"laser":     {"edge":Color(0.42,0.94,1.0),"edge_hot":Color(0.88,1.0,1.0),"fill":Color(0.20,0.80,0.95),"active":Color(0.90,1.0,1.0),"active_fill":Color(0.30,0.88,1.0)},
	"sweep":     {"edge":Color(1.0,0.45,0.92),"edge_hot":Color(1.0,0.82,0.98),"fill":Color(0.90,0.22,0.78),"active":Color(1.0,0.86,0.98),"active_fill":Color(1.0,0.34,0.86)},
	"artillery": {"edge":Color(1,0.76,0.26),"edge_hot":Color(1,0.96,0.66),"fill":Color(0.95,0.58,0.10),"active":Color(1,0.96,0.70),"active_fill":Color(1,0.66,0.16)},
	"root":      {"edge":Color(0.78,0.48,1.0),"edge_hot":Color(0.94,0.80,1.0),"fill":Color(0.58,0.26,0.92),"active":Color(0.94,0.82,1.0),"active_fill":Color(0.66,0.34,1.0)},
	"poison":    {"edge":Color(0.42,1.0,0.60),"edge_hot":Color(0.80,1.0,0.86),"fill":Color(0.14,0.62,0.32),"active":Color(0.84,1.0,0.88),"active_fill":Color(0.22,0.72,0.38)},
	"ice":       {"edge":Color(0.64,0.96,1.0),"edge_hot":Color(0.90,1.0,1.0),"fill":Color(0.28,0.66,0.86),"active":Color(0.92,1.0,1.0),"active_fill":Color(0.36,0.76,0.96)},
	"shock":     {"edge":Color(0.66,0.52,1.0),"edge_hot":Color(0.90,0.84,1.0),"fill":Color(0.44,0.28,0.94),"active":Color(0.92,0.86,1.0),"active_fill":Color(0.52,0.34,1.0)},
	"summon":    {"edge":Color(0.62,0.82,1.0),"edge_hot":Color(0.88,0.96,1.0),"fill":Color(0.30,0.50,0.86),"active":Color(0.90,0.96,1.0),"active_fill":Color(0.36,0.58,0.94)}
}

static func palette(style: String) -> Dictionary:
	return STYLES.get(style,STYLES.generic)

## Kind -> default style, so an existing caller that only names the mode still gets the
## family colour instead of the fallback orange.
static func style_for(kind: String, explicit := "") -> String:
	if explicit != "": return explicit
	match kind:
		"charge","dash": return "charge"
		"circle": return "artillery"
		"cone": return "detonate"
		"line": return "laser"
		"summon": return "summon"
	return "generic"

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
static func paint(canvas: Node2D, kind: String, direction: Vector2, radius: float, length: float, width: float, angle: float, progress: float, active: bool, sweep = 0.0, cache: Dictionary = {}, detail = true, style := "generic"):
	var shape = geometry(kind,direction,radius,length,width,angle,sweep,cache)
	var ink = palette(style_for(kind,style))
	var p = clampf(progress,0,1)
	var pulse = 0.5+0.5*sin(p*PI*16) if p>0.72 else p
	var edge = Color(ink.edge.r,ink.edge.g,ink.edge.b,0.72+0.26*pulse)
	var fill = Color(ink.fill.r,ink.fill.g,ink.fill.b,0.09+0.13*p)
	# The warning is not static: as the timer runs out the ink shifts toward `edge_hot`, so
	# "nearly now" is legible without reading a number.
	if p > 0.62:
		edge = edge.lerp(ink.edge_hot,(p-0.62)/0.38*0.75)
	if active: edge = Color(ink.active.r,ink.active.g,ink.active.b,0.95); fill = Color(ink.active_fill.r,ink.active_fill.g,ink.active_fill.b,0.3)
	if kind in ["line","charge"]:
		var normal = direction.orthogonal()*width
		canvas.draw_colored_polygon(shape.box,fill)
		canvas.draw_multiline(shape.sides,Color(0.06,0.05,0.09,0.65),3,true)
		canvas.draw_multiline(shape.sides,edge,1.1+0.6*pulse,true)
		if kind == "charge":
			var arrows = PackedVector2Array()
			for i in int(length/26.0):
				var point = direction*fposmod(i*26.0+p*52.0,length)
				arrows.append_array(PackedVector2Array([point-direction*5-normal*0.42,point,point,point-direction*5+normal*0.42]))
			if not arrows.is_empty(): canvas.draw_multiline(arrows,Color(ink.edge_hot.r,ink.edge_hot.g,ink.edge_hot.b,0.28+0.45*p),1.3,true)
		else:
			# Beam language: a thin line while warning, and a hard brightness step in the
			# last quarter of the wind-up so the shot reads as "now" rather than "soon".
			var near = p > 0.75
			canvas.draw_line(Vector2.ZERO,direction*length,edge,width*1.5 if active else (2.6 if near else 0.8),true)
			if near and not active: canvas.draw_line(Vector2.ZERO,direction*length,Color(ink.edge_hot.r,ink.edge_hot.g,ink.edge_hot.b,0.55),1.2,true)
			if active: canvas.draw_line(Vector2.ZERO,direction*length,Color(1,1,1,0.9),width*0.45,true)
		if sweep != 0 and not active:
			canvas.draw_colored_polygon(shape.sector,Color(ink.fill.r,ink.fill.g,ink.fill.b,0.06))
			canvas.draw_line(Vector2.ZERO,direction.rotated(sweep)*length,edge*Color(1,1,1,0.6),1,true)
			var turn = direction.rotated(sweep*p)*length*0.65
			var tangent = turn.normalized().orthogonal()*signf(sweep)
			canvas.draw_polyline(PackedVector2Array([turn-tangent*7-turn.normalized()*4,turn,turn-tangent*7+turn.normalized()*4]),edge,1.8,true)
	elif kind == "cone":
		canvas.draw_colored_polygon(shape.cone,fill)
		canvas.draw_polyline(shape.cone_edge,Color(0.07,0.04,0.08,0.8),4,true)
		canvas.draw_polyline(shape.cone_edge,edge,1.6,true)
		canvas.draw_arc(Vector2.ZERO,radius*p,direction.angle()-angle,direction.angle()+angle,segments(radius*p,angle*2),edge*Color(1,1,1,0.55),2,true)
		canvas.draw_line(direction*radius*0.3,direction*radius*0.55,edge,1.2,true)
		if style == "root":
			# Control attacks get a waveform so they never look like plain damage.
			var wave = PackedVector2Array()
			for i in 16:
				var t = float(i)/15.0
				var along = direction.rotated(lerpf(-angle,angle,t))*radius*0.82
				var cross = along.normalized().orthogonal()*sin(t*PI*4+progress*10)*7
				wave.append(along+cross)
			canvas.draw_polyline(wave,Color(ink.edge_hot.r,ink.edge_hot.g,ink.edge_hot.b,0.7),1.6,true)
	else:
		canvas.draw_circle(Vector2.ZERO,radius,fill)
		canvas.draw_polyline(shape.ring,Color(0.07,0.04,0.08,0.8),4,true)
		canvas.draw_polyline(shape.ring,edge,1.6+0.5*pulse,true)
		canvas.draw_arc(Vector2.ZERO,radius*(1.0-p),0,TAU,segments(radius*(1.0-p)),edge*Color(1,1,1,0.7),1.5,true)
		canvas.draw_arc(Vector2.ZERO,radius+3,-PI/2,-PI/2+TAU*p,segments(radius+3,TAU*p),edge,2,true)
		if kind == "summon":
			# Three emerging buds distinguish summoning from an impact footprint.
			for i in 3:
				var center = Vector2.RIGHT.rotated(-PI/2+i*TAU/3)*radius*0.48
				canvas.draw_arc(center,4+3*p,0,TAU,12,edge,2,true)
		elif style == "poison":
			# Area denial: an unstable edge plus spore bubbles, not a bare timing circle.
			var wobble = PackedVector2Array()
			for i in 40:
				var a = TAU*i/40.0
				wobble.append(Vector2.RIGHT.rotated(a)*radius*(1.0+0.06*sin(a*5.0+progress*8.0)))
			canvas.draw_polyline(wobble,edge,1.6,true)
			for i in 7:
				var a = i*TAU/7.0+progress*3.0
				canvas.draw_circle(Vector2.RIGHT.rotated(a)*radius*0.55,2.0+2.0*p,Color(ink.edge_hot.r,ink.edge_hot.g,ink.edge_hot.b,0.45))
		elif style == "detonate":
			# Self-destruct: a fast inner blink that accelerates as the fuse burns down.
			canvas.draw_circle(Vector2.ZERO,4.0+3.0*sin(progress*40.0),Color(1,0.4,0.3,0.85))
		else: canvas.draw_multiline(shape.marks,edge,1.4,true)
	# Common origin charge halo, never an opaque screen flash.
	if detail or kind == "summon": canvas.draw_arc(Vector2.ZERO,5+4*p,0,TAU,segments(5+4*p),edge,1.4,true)
