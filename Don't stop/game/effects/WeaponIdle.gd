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
	match gun.weapon_id:
		112:
			for i in 4:
				draw_rect(Rect2(tip+Vector2(-16+i*3,-2),Vector2(2,3)),Color(0.25,0.7,1,a*0.45))
			for side in [-1,1]:
				draw_polyline(PackedVector2Array([tip+Vector2(-5,side*3),tip+Vector2(-3,side*4),tip+Vector2(-2,side*2)]),Color(0.5,0.85,1,a),1)
		116:
			for i in 4:
				draw_line(tip+Vector2(-15+i*3,-3),tip+Vector2(-15+i*3,2),Color(1,0.3+0.1*i,0.05,a*0.7),1)
			draw_rect(Rect2(tip-Vector2(5,2),Vector2(4,4)),Color(1,0.3,0.03,a*0.5))
			for i in 3: draw_rect(Rect2(tip+Vector2(-5+i,-3-fmod(clock*3+i,3)),Vector2.ONE),Color(1,0.6,0.15,a*0.4))
		113:
			for i in 5:
				var light = 0.9 if int(clock*5)%5==i else 0.3
				draw_rect(Rect2(tip+Vector2(-20+i*3,-2),Vector2(2,4)),Color(0.35,0.7,1,a*light))
			for side in [-1,1]: draw_line(tip+Vector2(-12,side*3),tip+Vector2(-4,side*3),Color(0.5,0.8,1,a*0.7),1)
		120:
			for i in 3:
				draw_line(tip+Vector2(-14+i*3,3),tip+Vector2(-12+i*3,3),Color(1,0.6,0.2,a),1)
			for i in 3: draw_rect(Rect2(tip+Vector2(-8+i*2,-3),Vector2.ONE),Color(1,0.55,0.12,a if int(clock*2)%3==i else a*0.25))
		6:
			for i in 4:
				draw_line(tip+Vector2(-16+i*3,-2),tip+Vector2(-14+i*3,1),Color(0.4,1,0.55,a*0.7),2)
			draw_line(tip+Vector2(-7,-2),tip+Vector2(-2,-2),Color(0.65,1,0.7,a),1)
		124:
			for i in 3:
				var y = sin(clock*(2.0+18.0*gun.spin)+i*TAU/3)*2
				draw_line(tip+Vector2(-7,y),tip+Vector2(-1,y),Color(0.7,0.8,0.85,a),1)

func draw_aura(id: int, tip: Vector2):
	var color: Color = PALETTES[id]
	var center: Vector2 = tip + AURA_OFFSETS.get(id,Vector2(-10,0))
	var legendary = WeaponCatalog.tier(id) == 5
	var intensity = 0.78 if Combat.reduced_flash else 0.9+0.1*sin(clock*2.4)
	# Stepped translucent pixels form a local energy sheath, not a player halo.
	for side in [-1,1]:
		for x in range(-13,11,2):
			var edge = 4.0+2.0*sin(float(x+13)/24.0*PI)
			for layer in 3:
				draw_rect(Rect2(center+Vector2(x,side*(edge+layer*2)),Vector2(2,2)),Color(color, intensity*(0.22-layer*0.06)))
	var count = 18 if legendary else 9
	for i in count:
		var phase = clock*(1.1 if legendary else 0.7)+i*TAU/count
		var pos = center+Vector2(cos(phase)*15,sin(phase)*9)
		match id:
			116: pos = center+Vector2((i*7%25)-12,-4-fmod(clock*8+i*1.7,11))
			113: pos = center+Vector2(13-fmod(clock*12+i*2.3,27),(-1 if i%2 else 1)*7)
			120: pos = center+Vector2((i%3)*9-9,(-1 if i%2 else 1)*(6+sin(phase)*2))
			124: pos = center+Vector2(8+fmod(clock*10+i*1.7,9),sin(phase)*7)
			111: pos = center+Vector2(cos(phase)*12,sin(phase*2)*8)
			114: pos = center+Vector2(cos(phase)*(10+sin(clock*2)),sin(phase)*8)
			115: pos = tip+Vector2(cos(phase*0.5)*7-3,sin(phase*0.5)*9)
			122: pos = center+Vector2(cos(phase)*10,sin(phase)*10)
		pos = pos.round()
		draw_rect(Rect2(pos-Vector2.ONE,Vector2(3,3)),Color(color,0.22*intensity))
		draw_rect(Rect2(pos,Vector2.ONE),Color(color.lightened(0.45),0.85*intensity))
		if id == 112 and i%3 == 0:
			var end = center+Vector2(cos(phase+0.28)*13,sin(phase+0.28)*7)
			draw_polyline(PackedVector2Array([pos,(pos+end)/2+Vector2(1,-2),end]),Color(color.lightened(0.35),0.8*intensity),1)
		elif id == 121 and i%3 == 0:
			draw_rect(Rect2(pos,Vector2(2,2)),Color("e3c4ff"))
		elif id in [111,122] and i%2 == 0:
			draw_line(pos-Vector2(1,2),pos+Vector2(1,1),Color(color.lightened(0.5),intensity),1)
		elif id in [6,114,115,120] and i%3 == 0:
			draw_arc(center,8+i%3,phase,phase+0.55,5,Color(color,0.65*intensity),1)
	if id == 113:
		var charge = gun.charge_time if is_instance_valid(gun) else 0.0
		for side in [-1,1]:
			draw_line(center+Vector2(-12,side*6),center+Vector2(12,side*6),Color(color,0.5+minf(0.4,charge)),1)
