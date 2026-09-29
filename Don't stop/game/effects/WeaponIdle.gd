extends Node2D
var gun: BaseGun
var clock := 0.0
var aura_enabled := true
# Pure visual mode shares the held weapon renderer, without constructing a gun.
var preview_id := -1
var preview_tip := Vector2.ZERO
const PALETTES = {112:Color("66cfff"),121:Color("c68cff"),116:Color("ff863d"),113:Color("90bfff"),120:Color("ffbf69"),124:Color("ffd47a"),6:Color("70ffac"),111:Color("b7a0ff"),114:Color("ff78ce"),115:Color("77eeff"),122:Color("c8e5e9")}
# Keep the aura just outside each weapon's silhouette.  The small per-weapon offsets
# preserve the distinct idle shapes while keeping the bright pixels from covering their
# readable bodies in the camp preview and during combat.
const AURA_OFFSETS = {112:Vector2(-7,0),121:Vector2(-6,0),116:Vector2(-8,0),113:Vector2(-5,0),120:Vector2(-6,0),124:Vector2(-7,0),6:Vector2(-7,0),111:Vector2(-8,0),114:Vector2(-8,0),115:Vector2(-4,0),122:Vector2(-6,0)}
func _process(delta):
	visible = preview_id >= 0 or (is_instance_valid(gun) and gun.is_use and is_instance_valid(gun.player) and not gun.player.is_dead)
	if not visible: return
	if not is_visible_in_tree(): return
	clock += delta
	queue_redraw()
func _draw():
	if not visible: return
	if preview_id < 0 and not is_instance_valid(gun): return
	var id = preview_id if preview_id >= 0 else gun.weapon_id
	var tip = preview_tip if preview_id >= 0 else gun.gun_tip.position
	if aura_enabled and PALETTES.has(id): draw_aura(id,tip)
	if preview_id >= 0: return
	var a = (0.58+0.16*sin(clock*4))*(0.65 if Combat.reduced_flash else 1.0)
	if gun.weapon_id == 124:
		for i in 3:
			var y = sin(clock*(2.0+18.0*gun.spin)+i*TAU/3)*2
			draw_line(tip+Vector2(-7,y),tip+Vector2(-1,y),Color(0.7,0.8,0.85,a),1)

func draw_aura(id: int, tip: Vector2):
	var color: Color = PALETTES[id]
	var center: Vector2 = tip + AURA_OFFSETS.get(id,Vector2(-10,0))
	var intensity = 0.65 if Combat.reduced_flash else 0.82+0.08*sin(clock*2.4)
	var steel := Color("71838a")
	var recess := Color("111e26")
	# Energy belongs to the mechanism. Keep the receiver readable, with restrained
	# reflected light and distinctive rails, chambers, fins or a containment field.
	var glow = preload("res://game/effects/PresentationLight.gd").texture()
	draw_texture_rect(glow,Rect2(center-Vector2(16,8),Vector2(32,16)),false,Color(color,0.10*intensity))
	match id:
		113:
			var charge = gun.charge_time if is_instance_valid(gun) else 0.0
			for side in [-1,1]:
				var rail := center+Vector2(-14,side*4.5)
				draw_line(rail,rail+Vector2(25,0),recess,3)
				draw_line(rail,rail+Vector2(25,0),steel,1)
				for cell in 4:
					var hot := clampf(charge/0.8*4-cell,0.0,1.0)
					draw_line(rail+Vector2(2+cell*6,0),rail+Vector2(5+cell*6,0),Color(color,0.25+hot*0.75),1.5)
		121:
			for side in [-1,1]:
				var orbit := PackedVector2Array()
				for k in 17:
					var angle = k*TAU/16
					orbit.append(center+Vector2(cos(angle)*12,sin(angle)*5).rotated(side*0.55))
				draw_polyline(orbit,Color(color,0.36*intensity),0.7,true)
				var angle = clock*side*1.1
				var lock = center+Vector2(cos(angle)*12,sin(angle)*5).rotated(side*0.55)
				draw_rect(Rect2(lock.round()-Vector2.ONE,Vector2(2,2)),Color("e3c4ff"))
		112:
			for side in [-1,1]:
				var rail = center+Vector2(-9,side*5)
				draw_line(rail,rail+Vector2(17,0),recess,3)
				for cell in 3:
					var at = rail+Vector2(cell*7,0)
					draw_rect(Rect2(at-Vector2(1,1),Vector2(3,2)),steel)
				var phase = sin(clock*7+side)*0.9
				draw_polyline(PackedVector2Array([rail,rail+Vector2(4,phase),rail+Vector2(10,-phase),rail+Vector2(16,0)]),Color(color,intensity),0.8,true)
		116:
			for side in [-1,1]:
				for fin in 4:
					var at = center+Vector2(-10+fin*4,side*4)
					draw_rect(Rect2(at,Vector2(2,2)),Color("a77b56"))
					draw_line(at+Vector2(0,side),at+Vector2(1,side),Color(color,intensity*(0.35+fin*0.12)),1)
		120:
			for side in [-1,1]:
				for chamber in 3:
					var at = center+Vector2(-11+chamber*7,side*4)
					draw_rect(Rect2(at,Vector2(5,3)),recess)
					draw_line(at,at+Vector2(4,0),steel,1)
					draw_rect(Rect2(at+Vector2(3,1),Vector2.ONE),Color(color,intensity if int(clock*2)%3==chamber else 0.28))
		124:
			# Feed belt and barrel collar. Actual spin remains driven by gun.spin below.
			draw_line(center+Vector2(-11,4),center+Vector2(-1,4),recess,3)
			for tooth in 4:
				draw_rect(Rect2(center+Vector2(-11+tooth*3,4),Vector2(2,2)),Color("b79962"))
			for side in [-1,1]: draw_line(tip+Vector2(-5,side*3),tip+Vector2(-2,side*3),steel,1.5)
		6:
			for side in [-1,1]:
				var rear := tip+Vector2(-12,side*4)
				var joint := tip+Vector2(-3,side*4)
				var nose := tip+Vector2(0,side*2)
				# The bevel and inset exercise both lit primitive/attribute paths while
				# equipped, as the beam and muzzle do. Keep both: Web compiles them lazily.
				draw_line(rear,joint,recess,3)
				draw_line(joint,nose,recess,3)
				draw_polyline(PackedVector2Array([rear,joint,nose]),steel,1)
				for cell in 3: draw_rect(Rect2(center+Vector2(-8+cell*4,side*4),Vector2(2,1)),Color(color,intensity*(0.5+0.2*sin(clock*3-cell))))
		111:
			for prism in 3:
				var at = center+Vector2(-7+prism*6,-4)
				draw_colored_polygon(PackedVector2Array([at,at+Vector2(2,-2),at+Vector2(4,0),at+Vector2(2,1)]),Color(color,0.7*intensity))
		114:
			for side in [-1,1]:
				draw_arc(center,5,side*PI+0.3,side*PI+2.2,9,steel,1.6,true)
				draw_arc(center,4,side*PI+0.5,side*PI+1.8,8,Color(color,intensity),0.8,true)
		115:
			for side in [-1,1]:
				draw_line(tip+Vector2(-5,side*4),tip+Vector2(0,side*6),steel,2)
				draw_line(tip+Vector2(-4,side*4),tip+Vector2(-1,side*5),Color(color,intensity),1)
		122:
			var hub := tip+Vector2(-4,0)
			for tooth in 6:
				var axis := Vector2.RIGHT.rotated(tooth*TAU/6+clock*0.8)
				draw_line(hub+axis*4,hub+axis*6,steel,1.5,true)
			draw_arc(hub,4,0,TAU,17,Color(color,0.5*intensity),0.8,true)
