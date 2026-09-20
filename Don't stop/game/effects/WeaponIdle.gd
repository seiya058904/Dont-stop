extends Node2D
var gun: BaseGun
var clock := 0.0
func _process(delta):
	visible = is_instance_valid(gun) and gun.is_use and not gun.player.is_dead
	if not visible: return
	clock += delta
	queue_redraw()
func _draw():
	if not visible: return
	var a = (0.58+0.16*sin(clock*4))*(0.65 if Combat.reduced_flash else 1.0)
	var tip = gun.gun_tip.position
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
