extends RefCounted
class_name RegionTheme

const FLOOR = {"R2":Color("343c40"),"R3":Color("304952"),"R4":Color("302b30"),"R5":Color("2c4033"),"R6":Color("343344")}
const WALL = {"R2":Color("58636b"),"R3":Color("799fa9"),"R4":Color("66504c"),"R5":Color("57674b"),"R6":Color("77717e")}

static func draw_arena(canvas: Node2D, region: String, bounds: Rect2, obstacles: Array):
	canvas.draw_rect(bounds,FLOOR[region])
	var rng = RandomNumberGenerator.new(); rng.seed = 900+int(region.substr(1))
	# Large flat ground formations make the biome readable before fine decals.
	for i in 18:
		var center = Vector2(rng.randf_range(-315,315),rng.randf_range(-235,235))
		var patch = PackedVector2Array()
		for j in 7:
			patch.append(center+Vector2(cos(j*TAU/7)*rng.randf_range(35,75),sin(j*TAU/7)*rng.randf_range(18,38)))
		if region=="R3":
			canvas.draw_colored_polygon(patch,Color("466773"))
			var edge = patch.duplicate(); edge.append(edge[0]); canvas.draw_polyline(edge,Color("63858f"),1)
		elif region=="R4": canvas.draw_colored_polygon(patch,Color("25232a"))
		elif region=="R5": canvas.draw_colored_polygon(patch,Color("3d5937"))
		elif region=="R6":
			canvas.draw_colored_polygon(patch,Color("3e3b4c"))
			canvas.draw_polyline(patch,Color("545062"),1)
	# Ground marks stay flat, muted and visibly traversable. Solid silhouettes below
	# use precisely the existing physics rectangles, without invented terrain walls.
	for i in 65:
		var p = Vector2(rng.randf_range(-370,370),rng.randf_range(-274,274))
		match region:
			"R2":
				canvas.draw_rect(Rect2(p,Vector2(15,5)),Color("2d3438"))
			"R3":
				var crack = PackedVector2Array([p,p+Vector2(9,-6),p+Vector2(18,1),p+Vector2(27,-8)])
				canvas.draw_polyline(crack,Color("50707a"),1)
				canvas.draw_line(p+Vector2(18,1),p+Vector2(15,9),Color("50707a"),1)
			"R4":
				canvas.draw_polyline(PackedVector2Array([p,p+Vector2(5,7),p+Vector2(14,3)]),Color("744d40"),1)
			"R5":
				canvas.draw_colored_polygon(PackedVector2Array([p,p+Vector2(9,-4),p+Vector2(18,3),p+Vector2(12,10),p+Vector2(-5,8)]),Color("344b36"))
				for j in 3: canvas.draw_line(p+Vector2(j*4,0),p+Vector2(j*4-2,-4),Color("536748"),1)
			"R6":
				canvas.draw_polyline(PackedVector2Array([p,p+Vector2(12,4),p+Vector2(18,-3)]),Color("474458"),1)
	match region:
		"R2":
			for x in [-90,90]:
				canvas.draw_line(Vector2(x,-270),Vector2(x,270),Color("77816c"),2)
				for y in range(-260,260,48): canvas.draw_rect(Rect2(x-3,y,6,22),Color("b39a56"))
			for y in [-245,245]: canvas.draw_line(Vector2(-365,y),Vector2(365,y),Color("59686e"),5)
		"R3":
			for y in [-277,275]:
				for x in range(-380,380,25): canvas.draw_colored_polygon(PackedVector2Array([Vector2(x,y),Vector2(x+22,y),Vector2(x+14,y-signf(y)*9)]),Color("708d94"))
		"R4":
			# Glowing channels are inset into the existing solid processing walls.
			for rect in obstacles:
				canvas.draw_rect(rect.grow(2),Color("925c40"),false,2)
			for y in [-255,250]:
				canvas.draw_polyline(PackedVector2Array([Vector2(-350,y),Vector2(-170,y-11),Vector2(25,y+5),Vector2(210,y-8),Vector2(355,y)]),Color("594138"),2)
		"R5":
			# Shallow narrow drainage lies on the floor; no raised bank or cliff edge.
			for x in [-72,72]:
				canvas.draw_polyline(PackedVector2Array([Vector2(x,-280),Vector2(x+13,-120),Vector2(x-8,65),Vector2(x,280)]),Color("436d6b"),14)
				for y in range(-240,260,45): canvas.draw_line(Vector2(x-2,y),Vector2(x+3,y+3),Color("51706b"),1)
		"R6":
			canvas.draw_arc(Vector2.ZERO,205,0,TAU,64,Color("636277"),3)
			canvas.draw_arc(Vector2.ZERO,192,0,TAU,64,Color("46465c"),1)
			for i in 8:
				var v = Vector2.RIGHT.rotated(i*TAU/8)
				canvas.draw_line(v*150,v*185,Color("576378"),2)
	for rect in obstacles:
		canvas.draw_rect(rect,Color("192127"))
		canvas.draw_rect(rect.grow(-2),WALL[region])
		canvas.draw_rect(rect.grow(-4),WALL[region].darkened(0.18),false,1)
		match region:
			"R2":
				for x in range(int(rect.position.x)+9,int(rect.end.x)-4,12): canvas.draw_line(Vector2(x,rect.position.y+5),Vector2(x,rect.end.y-5),Color("3d4b53"),2)
				canvas.draw_rect(Rect2(rect.position+Vector2(3,3),Vector2(minf(24,rect.size.x-6),4)),Color("c5a65e"))
			"R3":
				canvas.draw_line(rect.position+Vector2(3,3),Vector2(rect.end.x-3,rect.position.y+3),Color("b1cdd0"),3)
				for x in range(int(rect.position.x)+6,int(rect.end.x)-10,20):
					canvas.draw_colored_polygon(PackedVector2Array([Vector2(x,rect.position.y+4),Vector2(x+13,rect.position.y+4),Vector2(x+7,rect.end.y-4)]),Color("9ec4cc"))
			"R4":
				var inset = rect.grow(-6)
				canvas.draw_rect(inset,Color("a85930"))
				canvas.draw_rect(inset.grow(-3),Color(1.4,0.72,0.2))
				for x in range(int(inset.position.x)+2,int(inset.end.x)-1,15): canvas.draw_line(Vector2(x,inset.position.y+1),Vector2(x+3,inset.end.y-1),Color("653f32"),2)
			"R5":
				for y in range(int(rect.position.y)+8,int(rect.end.y)-4,12): canvas.draw_circle(Vector2(rect.position.x+8,y),5,Color("465c38"))
			"R6":
				canvas.draw_colored_polygon(PackedVector2Array([rect.position+Vector2(4,4),Vector2(rect.end.x-4,rect.position.y+7),rect.get_center(),Vector2(rect.position.x+6,rect.end.y-4)]),Color("96929d"))
				canvas.draw_polyline(PackedVector2Array([rect.position+rect.size*0.2,rect.get_center(),rect.position+rect.size*0.8]),Color("98a3b0"),2)
	canvas.draw_rect(bounds,Color("819398"),false,3)
