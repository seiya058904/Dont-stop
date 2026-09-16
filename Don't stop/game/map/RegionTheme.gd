extends RefCounted
class_name RegionTheme

## Region art. One flat `_draw` per arena, executed once when the arena enters the tree and
## then replayed from the canvas item's command buffer - no per-frame redraw, because Web is
## Godot nothreads and every one of these regions has to keep 100+ monsters affordable.
##
## What each region must do, per the B批 brief: be identifiable at a glance, and give the
## fight a different FLOOR (lanes, channels, pools, ring) rather than a different palette.
## Motion (vents erupting, embers, spore drift, pulse travel) belongs to StageHazard and the
## attack telegraphs, which are the nodes that are allowed to move.
const FLOOR = {
	"R2":Color("343c40"),"R3":Color("2c454e"),"R4":Color("2c272c"),"R5":Color("2a3e31"),
	"R6":Color("323144"),"R7":Color("2b3a36"),"R8":Color("241f38")
}
const WALL = {
	"R2":Color("58636b"),"R3":Color("799fa9"),"R4":Color("66504c"),"R5":Color("57674b"),
	"R6":Color("77717e"),"R7":Color("4f6b60"),"R8":Color("5b4f7e")
}
## Accent per region, used for the identification pass (lane paint, ring markers, edge glow).
const ACCENT = {
	"R2":Color("c5a65e"),"R3":Color("9ed8e4"),"R4":Color("e07a34"),"R5":Color("6fbf72"),
	"R6":Color("8f9ddc"),"R7":Color("5fe0a8"),"R8":Color("a06fe8")
}

static func draw_arena(canvas: Node2D, region: String, bounds: Rect2, obstacles: Array):
	var rng = RandomNumberGenerator.new(); rng.seed = 900+int(region.substr(1))
	canvas.draw_rect(bounds,FLOOR[region])
	_ground(canvas,region,rng)
	_identity(canvas,region,bounds,obstacles,rng)
	for rect in obstacles: _wall(canvas,region,rect)
	_identification_frame(canvas,region,bounds)

## Broad ground formations. These exist so the biome is readable before any fine decal, and
## they are deliberately large and low-contrast so they never compete with a telegraph.
static func _ground(canvas: Node2D, region: String, rng: RandomNumberGenerator):
	for i in 18:
		var center = Vector2(rng.randf_range(-360,360),rng.randf_range(-268,268))
		var patch = PackedVector2Array()
		for j in 7:
			patch.append(center+Vector2(cos(j*TAU/7)*rng.randf_range(38,84),sin(j*TAU/7)*rng.randf_range(20,44)))
		match region:
			"R2": canvas.draw_colored_polygon(patch,Color("2e3639"))
			"R3":
				canvas.draw_colored_polygon(patch,Color("3f6270"))
				var edge = patch.duplicate(); edge.append(edge[0]); canvas.draw_polyline(edge,Color("5a7f8c"),1)
			"R4": canvas.draw_colored_polygon(patch,Color("211f26"))
			"R5": canvas.draw_colored_polygon(patch,Color("35502f"))
			"R6":
				canvas.draw_colored_polygon(patch,Color("3b3850"))
				canvas.draw_polyline(patch,Color("4d4a68"),1)
			"R7":
				canvas.draw_colored_polygon(patch,Color("33473f"))
				canvas.draw_polyline(patch,Color("416052"),1)
			"R8": canvas.draw_colored_polygon(patch,Color("2c264a"))
	# Fine ground marks stay flat, muted and visibly traversable. Solid silhouettes below use
	# precisely the existing physics rectangles, without invented terrain walls.
	for i in 90:
		var p = Vector2(rng.randf_range(-424,424),rng.randf_range(-314,314))
		match region:
			"R2":
				canvas.draw_rect(Rect2(p,Vector2(15,5)),Color("2d3438"))
				if i%7==0: canvas.draw_line(p,p+Vector2(11,-3),Color("3d474b"),1)
			"R3":
				var crack = PackedVector2Array([p,p+Vector2(9,-6),p+Vector2(18,1),p+Vector2(27,-8)])
				canvas.draw_polyline(crack,Color("50707a"),1)
				canvas.draw_line(p+Vector2(18,1),p+Vector2(15,9),Color("50707a"),1)
			"R4":
				canvas.draw_polyline(PackedVector2Array([p,p+Vector2(5,7),p+Vector2(14,3)]),Color("744d40"),1)
				if i%5==0: canvas.draw_circle(p,1.6,Color("c2601f"))
			"R5":
				canvas.draw_colored_polygon(PackedVector2Array([p,p+Vector2(9,-4),p+Vector2(18,3),p+Vector2(12,10),p+Vector2(-5,8)]),Color("344b36"))
				for j in 3: canvas.draw_line(p+Vector2(j*4,0),p+Vector2(j*4-2,-4),Color("536748"),1)
			"R6":
				canvas.draw_polyline(PackedVector2Array([p,p+Vector2(12,4),p+Vector2(18,-3)]),Color("474458"),1)
			"R7":
				# Pitted corrosion: short irregular bites, denser near the quarantine blocks.
				canvas.draw_arc(p,5+rng.randf_range(0,4),0,TAU,7,Color("24322c"),1.4,true)
				if i%4==0: canvas.draw_circle(p+Vector2(4,-2),1.5,Color("4fd0a0",0.55))
			"R8":
				canvas.draw_line(p,p+Vector2(13,-5),Color("3b3460"),1)
				if i%6==0: canvas.draw_arc(p,4,0,TAU,8,Color("7a5ec0",0.4),1,true)

## The region's own gameplay-floor language: the shapes that make this map play differently.
static func _identity(canvas: Node2D, region: String, bounds: Rect2, obstacles: Array, rng: RandomNumberGenerator):
	match region:
		"R2":
			# Freight yard: painted lanes running east-west, hazard stripes at the loading
			# aprons and industrial indicator lamps on the container corners.
			for y in [-276,-92,92,276]:
				for x in range(-420,420,64):
					canvas.draw_rect(Rect2(x,y-2,34,4),Color("6d7466"))
			for x in [-196,196]:
				canvas.draw_line(Vector2(x,-314),Vector2(x,314),Color("7d865f"),3)
				for y in range(-306,306,46): canvas.draw_rect(Rect2(x-4,y,8,24),Color("b39a56"))
			for rect in obstacles:
				# Hazard stripe along the whole container footprint plus a lit corner.
				canvas.draw_rect(Rect2(rect.position+Vector2(0,-9),Vector2(rect.size.x,5)),Color("1b1f22"))
				for x in range(int(rect.position.x),int(rect.end.x)-12,14):
					canvas.draw_colored_polygon(PackedVector2Array([Vector2(x,rect.position.y-8),Vector2(x+7,rect.position.y-8),Vector2(x+13,rect.position.y-5),Vector2(x+6,rect.position.y-5)]),Color("c9a24e"))
				canvas.draw_circle(rect.position+Vector2(10,10),3,Color("ffca6a"))
				canvas.draw_arc(rect.position+Vector2(10,10),5,0,TAU,10,Color("ffca6a",0.4),1)
				# Loading-area corner marks.
				for corner in [rect.position,Vector2(rect.end.x,rect.position.y),Vector2(rect.position.x,rect.end.y),rect.end]:
					canvas.draw_line(corner,corner+Vector2(0,-6),Color("8b9aa2"),1)
			canvas.draw_rect(Rect2(-70,-40,140,80),Color("4a5459"),false,2)
			canvas.draw_rect(Rect2(-58,-28,116,56),Color("404a4f"),false,1)
		"R3":
			# Coolant station: pipes running between the frost walls, plus rimed frost banks.
			for y in [-314,314]:
				for x in range(-430,430,25): canvas.draw_colored_polygon(PackedVector2Array([Vector2(x,y),Vector2(x+22,y),Vector2(x+14,y-signf(y)*9)]),Color("708d94"))
			for rect in obstacles:
				var row = rect.position.y-6 if rect.size.x>rect.size.y else rect.position.x-6
				if rect.size.x>rect.size.y:
					canvas.draw_line(Vector2(rect.position.x,row),Vector2(rect.end.x,row),Color("4d8b9c"),4)
					for x in range(int(rect.position.x)+8,int(rect.end.x)-6,26):
						canvas.draw_circle(Vector2(x,row),3.5,Color("3d7183"),false,1.5,true)
				else:
					canvas.draw_line(Vector2(row,rect.position.y),Vector2(row,rect.end.y),Color("4d8b9c"),4)
			# Frozen steam: soft overlapping discs that read as vapour sitting on the ground.
			for i in 10:
				var p = Vector2(rng.randf_range(-380,380),rng.randf_range(-280,280))
				for j in 3: canvas.draw_circle(p+Vector2(j*13,j%2*7),16-j*3,Color("a9d9e6",0.05))
			# Ice sheets: flat, brighter panels with sharp crack edges.
			for i in 7:
				var p = Vector2(rng.randf_range(-360,360),rng.randf_range(-260,260))
				var panel = PackedVector2Array([p,p+Vector2(72,-14),p+Vector2(96,42),p+Vector2(24,58)])
				canvas.draw_colored_polygon(panel,Color("5c848f",0.5))
				var edge = panel.duplicate(); edge.append(edge[0]); canvas.draw_polyline(edge,Color("9ecdd6",0.65),1.5)
				canvas.draw_line(p,p+Vector2(96,42),Color("9ecdd6",0.35),1)
		"R4":
			# Lava processing: a glowing channel across each processing wall, heat pipes, vents.
			for rect in obstacles:
				canvas.draw_rect(rect.grow(2),Color("925c40"),false,2)
			for y in [-262,258]:
				canvas.draw_polyline(PackedVector2Array([Vector2(-420,y),Vector2(-200,y-13),Vector2(30,y+6),Vector2(240,y-9),Vector2(420,y)]),Color("594138"),3)
				canvas.draw_polyline(PackedVector2Array([Vector2(-420,y),Vector2(-200,y-13),Vector2(30,y+6),Vector2(240,y-9),Vector2(420,y)]),Color("d2611f",0.75),1)
			# Heat pipes: parallel runs with joint rings, laid across the open floor.
			for x in [-132,132]:
				canvas.draw_line(Vector2(x,-300),Vector2(x,300),Color("4a3a34"),7)
				canvas.draw_line(Vector2(x,-300),Vector2(x,300),Color("7a5344"),3)
				for y in range(-290,300,52): canvas.draw_circle(Vector2(x,y),5,Color("a85930"),false,2)
			# Vents: a bright throat with a scorched apron, so a real vent hazard reads as the
			# same object that is painted on the floor.
			for p in [Vector2(-70,-268),Vector2(70,268),Vector2(-300,0),Vector2(300,0),Vector2(0,-150),Vector2(0,150)]:
				canvas.draw_circle(p,26,Color("1b1418"))
				canvas.draw_arc(p,26,0,TAU,20,Color("7c4526"),2,true)
				canvas.draw_circle(p,13,Color("c2581f",0.85))
				for k in 6: canvas.draw_line(p,p+Vector2.RIGHT.rotated(k*TAU/6)*34,Color("6b3a22",0.6),1)
		"R5":
			# Overgrown corridor: two drainage canals, vegetation blocks, spore clusters.
			for x in [-84,84]:
				canvas.draw_polyline(PackedVector2Array([Vector2(x,-300),Vector2(x+13,-120),Vector2(x-8,65),Vector2(x,300)]),Color("436d6b"),16)
				canvas.draw_polyline(PackedVector2Array([Vector2(x,-300),Vector2(x+13,-120),Vector2(x-8,65),Vector2(x,300)]),Color("5c9c94",1.5))
				for y in range(-250,270,45): canvas.draw_line(Vector2(x-3,y),Vector2(x+4,y+4),Color("51706b"),1)
			# Toxic pools: the visual anchor for the poison mechanic this region introduces.
			for p in [Vector2(-300,-220),Vector2(280,240),Vector2(0,-285),Vector2(0,285),Vector2(-310,250)]:
				var pool = PackedVector2Array()
				for k in 22:
					var a = TAU*k/22
					pool.append(p+Vector2(cos(a)*(30+9*sin(a*3)),sin(a)*(19+6*cos(a*2))))
				canvas.draw_colored_polygon(pool,Color("2f6b46",0.9))
				var edge = pool.duplicate(); edge.append(edge[0]); canvas.draw_polyline(edge,Color("63c98a",0.8),2)
				for k in 5: canvas.draw_circle(p+Vector2.RIGHT.rotated(k*1.7)*11,2.4,Color("8ff0b0",0.6))
			# Vegetation blocks and vines.
			for i in 22:
				var p = Vector2(rng.randf_range(-400,400),rng.randf_range(-290,290))
				canvas.draw_colored_polygon(PackedVector2Array([p,p+Vector2(26,-10),p+Vector2(40,12),p+Vector2(12,26),p+Vector2(-12,14)]),Color("3a5b34"))
				for k in 4: canvas.draw_line(p+Vector2(k*7,0),p+Vector2(k*7-4,-9),Color("5f7f4d"),1)
			for rect in obstacles:
				for y in range(int(rect.position.y)+6,int(rect.end.y)-4,11): canvas.draw_circle(Vector2(rect.position.x+7,y),5,Color("465c38"))
		"R6":
			# Core platform: a ring, radial spokes, energy pillars at the wall corners and
			# fissure tracks crossing the open centre.
			canvas.draw_arc(Vector2.ZERO,232,0,TAU,72,Color("4a4a63"),8)
			canvas.draw_arc(Vector2.ZERO,215,0,TAU,72,Color("636277"),3)
			canvas.draw_arc(Vector2.ZERO,196,0,TAU,72,Color("46465c"),1)
			for i in 8:
				var v = Vector2.RIGHT.rotated(i*TAU/8)
				canvas.draw_line(v*152,v*206,Color("576378"),2)
				if i%2==0: canvas.draw_circle(v*206,4,Color("8f9ddc",0.8))
			for rect in obstacles:
				canvas.draw_circle(rect.get_center(),10,Color("2a2a3d"),false,0)
				canvas.draw_arc(rect.get_center(),10,0,TAU,16,Color("8f9ddc",0.8),2,true)
				for k in 4:
					var v = Vector2.RIGHT.rotated(k*PI/2+PI/4)
					canvas.draw_line(rect.get_center()+v*10,rect.get_center()+v*20,Color("6d6aa8",0.7),2)
			for i in 6:
				var a = i*TAU/6+0.3
				var start = Vector2.RIGHT.rotated(a)*120
				canvas.draw_polyline(PackedVector2Array([start,start+Vector2.RIGHT.rotated(a+0.25)*90,start+Vector2.RIGHT.rotated(a-0.2)*190]),Color("5f5c85",2))
				canvas.draw_polyline(PackedVector2Array([start,start+Vector2.RIGHT.rotated(a+0.25)*90,start+Vector2.RIGHT.rotated(a-0.2)*190]),Color("9aa2e0",0.5),1)
		"R7":
			# Quarantine ring: bioluminescent spore beds, corroded floor plates between the
			# sealed cells, and marker chevrons pointing along the two ring corridors.
			for x in [-120,120]:
				for y in range(-300,300,40):
					canvas.draw_line(Vector2(x,y-9),Vector2(x,y+9),Color("5fe0a8",0.25),3)
			for i in 14:
				var p = Vector2(rng.randf_range(-400,400),rng.randf_range(-290,290))
				for k in 5:
					var off = Vector2.RIGHT.rotated(k*1.3+i)*rng.randf_range(6,20)
					canvas.draw_circle(p+off,2.4,Color("5fe0a8",0.5))
					canvas.draw_arc(p+off,5,0,TAU,8,Color("5fe0a8",0.22),1)
			for rect in obstacles:
				# Seal band plus a corrosion bite, so a sealed cell reads as sealed.
				canvas.draw_rect(rect.grow(-5),Color("1d2622"),false,3)
				canvas.draw_line(rect.position+Vector2(6,-8),Vector2(rect.end.x-6,rect.position.y-8),Color("5fe0a8",0.7),3)
				canvas.draw_line(rect.position+Vector2(6,rect.size.y+8),Vector2(rect.end.x-6,rect.position.y+rect.size.y+8),Color("2f4a3f",0.9),3)
				for x in range(int(rect.position.x)+10,int(rect.end.x)-8,22):
					canvas.draw_line(Vector2(x,rect.end.y-3),Vector2(x+8,rect.position.y+3),Color("0f1512",0.55),2)
		"R8":
			# Abyss core: a fractured central core, an outer pylon ring, and a laser grid laid
			# on the floor so the region's own mechanic is visible before it fires.
			for i in 4:
				var a = i*PI/2+PI/4
				var v = Vector2.RIGHT.rotated(a)
				canvas.draw_line(v*70,v*300,Color("5b4f8a",0.35),1)
				canvas.draw_line(v*70,v*300,Color("a06fe8",0.5),1)
			for g in [-220,0,220]:
				canvas.draw_line(Vector2(g,-314),Vector2(g,314),Color("3d3564",0.5),1)
				canvas.draw_line(Vector2(-440,g),Vector2(440,g),Color("3d3564",0.5),1)
			for i in 8:
				var v = Vector2.RIGHT.rotated(i*TAU/8)
				canvas.draw_line(v*268,v*300,Color("6b5aa8"),2)
				canvas.draw_circle(v*300,5,Color("a06fe8",0.85))
				canvas.draw_arc(v*300,9,0,TAU,12,Color("a06fe8",0.35),1)
			# Fissures radiating from the core, with a hot inner line.
			for i in 6:
				var a = i*TAU/6+0.2
				var pts = PackedVector2Array([Vector2.RIGHT.rotated(a)*54])
				for k in range(1,4): pts.append(Vector2.RIGHT.rotated(a+k*0.13)*(54+k*62))
				canvas.draw_polyline(pts,Color("312851"),6)
				canvas.draw_polyline(pts,Color("b98bff",0.7),1.5)
			for rect in obstacles:
				canvas.draw_rect(rect.grow(3),Color("a06fe8",0.25),false,2)

## Walls. Same rectangles the physics uses; the drawing only adds a lit top face, a cast
## shadow and a region-specific material band, so "wall vs floor" is never ambiguous.
static func _wall(canvas: Node2D, region: String, rect: Rect2):
	canvas.draw_rect(Rect2(rect.position+Vector2(5,7),rect.size),Color(0,0,0,0.30))
	canvas.draw_rect(rect,Color("151b20"))
	canvas.draw_rect(rect.grow(-2),WALL[region])
	canvas.draw_rect(rect.grow(-2).grow(-2),WALL[region].darkened(0.16),false,1)
	canvas.draw_line(rect.position+Vector2(2,2),Vector2(rect.end.x-2,rect.position.y+2),WALL[region].lightened(0.22),2)
	match region:
		"R2":
			for x in range(int(rect.position.x)+9,int(rect.end.x)-4,12):
				canvas.draw_line(Vector2(x,rect.position.y+7),Vector2(x,rect.end.y-7),Color("3d4b53"),2)
			canvas.draw_rect(Rect2(rect.position+Vector2(3,3),Vector2(minf(24,rect.size.x-6),4)),ACCENT[region])
			canvas.draw_rect(Rect2(rect.get_center()-Vector2(7,4),Vector2(14,8)),Color("212a2f"))
		"R3":
			canvas.draw_line(rect.position+Vector2(3,3),Vector2(rect.end.x-3,rect.position.y+3),Color("b1cdd0"),3)
			for x in range(int(rect.position.x)+6,int(rect.end.x)-10,20):
				canvas.draw_colored_polygon(PackedVector2Array([Vector2(x,rect.position.y+4),Vector2(x+13,rect.position.y+4),Vector2(x+7,rect.end.y-4)]),Color("9ec4cc"))
			for x in range(int(rect.position.x)+4,int(rect.end.x)-6,34):
				canvas.draw_circle(Vector2(x,rect.end.y-5),4,Color("cfe9f0",0.7))
		"R4":
			var inset = rect.grow(-6)
			canvas.draw_rect(inset,Color("a85930"))
			canvas.draw_rect(inset.grow(-3),Color(1.4,0.72,0.2))
			for x in range(int(inset.position.x)+2,int(inset.end.x)-1,15):
				canvas.draw_line(Vector2(x,inset.position.y+1),Vector2(x+3,inset.end.y-1),Color("653f32"),2)
		"R5":
			for y in range(int(rect.position.y)+8,int(rect.end.y)-4,12):
				canvas.draw_circle(Vector2(rect.position.x+8,y),5,Color("465c38"))
			for x in range(int(rect.position.x)+4,int(rect.end.x)-6,17):
				canvas.draw_line(Vector2(x,rect.position.y+4),Vector2(x+6,rect.position.y+13),Color("6f8c56"),1)
		"R6":
			canvas.draw_colored_polygon(PackedVector2Array([rect.position+Vector2(4,4),Vector2(rect.end.x-4,rect.position.y+7),rect.get_center(),Vector2(rect.position.x+6,rect.end.y-4)]),Color("96929d"))
			canvas.draw_polyline(PackedVector2Array([rect.position+rect.size*0.2,rect.get_center(),rect.position+rect.size*0.8]),Color("98a3b0"),2)
			canvas.draw_arc(rect.get_center(),minf(rect.size.x,rect.size.y)*0.3,0,TAU,16,ACCENT[region],2,true)
		"R7":
			canvas.draw_rect(rect.grow(-4),Color("1e2a25"),false,4)
			for x in range(int(rect.position.x)+6,int(rect.end.x)-6,15):
				canvas.draw_line(Vector2(x,rect.position.y+4),Vector2(x+5,rect.end.y-4),Color("33473f"),2)
			canvas.draw_line(rect.position+Vector2(4,rect.size.y*0.5),Vector2(rect.end.x-4,rect.position.y+rect.size.y*0.5),ACCENT[region],2)
		"R8":
			canvas.draw_rect(rect.grow(-4),Color("1b1630"),false,2)
			canvas.draw_line(rect.position+Vector2(4,4),rect.end-Vector2(4,4),ACCENT[region],2)
			canvas.draw_line(Vector2(rect.end.x-4,rect.position.y+4),Vector2(rect.position.x+4,rect.end.y-4),ACCENT[region],2)

## The arena rim. A two-tone frame with region accent ticks: at a glance, each region's
## outer boundary looks like its own place rather than the same box in another colour.
static func _identification_frame(canvas: Node2D, region: String, bounds: Rect2):
	canvas.draw_rect(bounds.grow(2),Color(0,0,0,0.5),false,6)
	canvas.draw_rect(bounds,ACCENT[region].darkened(0.55),false,3)
	canvas.draw_rect(bounds.grow(-4),Color("819398",0.35),false,1)
	for x in range(int(bounds.position.x)+20,int(bounds.end.x)-10,80):
		canvas.draw_line(Vector2(x,bounds.position.y+3),Vector2(x+26,bounds.position.y+3),ACCENT[region],2)
		canvas.draw_line(Vector2(x,bounds.end.y-3),Vector2(x+26,bounds.end.y-3),ACCENT[region],2)
	for y in range(int(bounds.position.y)+20,int(bounds.end.y)-10,80):
		canvas.draw_line(Vector2(bounds.position.x+3,y),Vector2(bounds.position.x+3,y+26),ACCENT[region],2)
		canvas.draw_line(Vector2(bounds.end.x-3,y),Vector2(bounds.end.x-3,y+26),ACCENT[region],2)
