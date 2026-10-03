extends Node2D
var gun: BaseGun
var clock := 0.0
var aura_enabled := true
var resting_sprite_offset := Vector2.ZERO
# Pure visual mode shares the held weapon renderer, without constructing a gun.
var preview_id := -1
var preview_tip := Vector2.ZERO
const PALETTES = {112:Color("66cfff"),121:Color("c68cff"),116:Color("ff863d"),113:Color("90bfff"),120:Color("ffbf69"),124:Color("ffd47a"),6:Color("70ffac"),111:Color("b7a0ff"),114:Color("ff78ce"),115:Color("77eeff"),122:Color("c8e5e9")}
func _ready() -> void:
	if not is_instance_valid(gun): return
	# Sprite parenting carries reload rotation/translation and recoil scale.
	# Texture offset is not a node transform, so running bob needs this signal.
	resting_sprite_offset = gun.gun_image.offset
	gun.gun_image.item_rect_changed.connect(_sync_sprite_offset)

func _sync_sprite_offset() -> void:
	position = gun.gun_image.offset-resting_sprite_offset

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

func draw_aura(id: int, tip: Vector2):
	var color: Color = PALETTES[id]
	var intensity = 0.65 if Combat.reduced_flash else 0.82+0.08*sin(clock*2.4)
	# Coordinates match the authored 32x16 artwork: muzzle pixel (21,8).
	# Fixed metal is in the texture; only inlaid energy and working parts animate.
	var origin := tip-Vector2(21,8)
	match id:
		113:
			var charge := 0.0
			if is_instance_valid(gun): charge = clampf(gun.charge_time/maxf(0.01,gun.effective.warmup),0,1)
			for cell in 4:
				var hot := clampf(charge*4-cell,0,1)
				draw_rect(Rect2(origin+Vector2(8+cell*3,5),Vector2(2,1)),Color(color,(0.22+hot*0.78)*intensity))
			for cell in 3:
				var hot := clampf(charge*3-cell,0,1)
				draw_rect(Rect2(origin+Vector2(12+cell*3,11),Vector2(2,1)),Color(color,(0.22+hot*0.78)*intensity))
			if charge > 0:
				chamber_glow(origin+Vector2(16,8),Vector2(14,8),color,0.14*charge*intensity)
		121:
			var center := origin+Vector2(13.5,8)
			chamber_glow(center,Vector2(11,11),color,0.24*intensity)
			draw_arc(center,2.4,clock*0.8,clock*0.8+PI*1.5,12,Color(color,0.65*intensity),0.8,true)
			var lock := center+Vector2.RIGHT.rotated(clock*0.8)*2.4
			draw_rect(Rect2(lock.round(),Vector2.ONE),Color("d8c5e9"))
		112:
			chamber_glow(origin+Vector2(18,8),Vector2(9,9),color,0.16*intensity)
			for y in [6,9]:
				draw_rect(Rect2(origin+Vector2(18,y),Vector2(3,1)),Color(color,0.65*intensity))
			var phase := sin(clock*5)*0.4
			draw_polyline(PackedVector2Array([origin+Vector2(19.5,7),origin+Vector2(19+phase,8),origin+Vector2(20,9)]),Color(color,0.55*intensity),0.7,true)
		116:
			for vent in 2:
				draw_rect(Rect2(origin+Vector2(13+vent*3,7),Vector2(2,2)),Color(color,(0.35+vent*0.13)*intensity))
			chamber_glow(origin+Vector2(16,8),Vector2(12,7),color,0.16*intensity)
		120:
			for chamber in 3:
				draw_rect(Rect2(origin+Vector2(8+chamber*3,6),Vector2.ONE),Color(color,(0.65 if int(clock*1.5)%3 == chamber else 0.25)*intensity))
		124:
			var spin: float = gun.spin if is_instance_valid(gun) else 0.0
			# A stationary preview; barrel reflections only turn when the motor does.
			for barrel in 3:
				var lit := maxf(0,sin(clock*18+barrel*TAU/3))*spin
				draw_rect(Rect2(origin+Vector2(18,5+barrel*2),Vector2(3,1)),Color("dce6d9",lit*0.7*intensity))
			draw_rect(Rect2(origin+Vector2(8,8),Vector2(2,1)),Color(color,(0.18+spin*0.65)*intensity))
		6:
			for y in [6,9]:
				var rear := origin+Vector2(14,y)
				var nose := origin+Vector2(20,y)
				# Both primitive paths also warm the beam's lazy Web draw variants.
				draw_line(rear,nose,Color(color,0.25*intensity),1)
				draw_polyline(PackedVector2Array([rear,rear+Vector2(2,0),nose]),Color(color,0.38*intensity),1)
			chamber_glow(origin+Vector2(17,8),Vector2(12,9),color,0.14*intensity)
		111:
			chamber_glow(origin+Vector2(14,7),Vector2(10,12),color,0.16*intensity)
			draw_colored_polygon(PackedVector2Array([origin+Vector2(14,4),origin+Vector2(15,6),origin+Vector2(14,9)]),Color("e4dffe",0.4*intensity))
		114:
			var center := origin+Vector2(14,8)
			chamber_glow(center,Vector2(10,10),color,0.3*intensity)
			draw_rect(Rect2(center-Vector2.ONE,Vector2(2,2)),Color(color,0.7*intensity))
			draw_rect(Rect2(center-Vector2.ONE,Vector2.ONE),Color("f0c9dd",0.8*intensity))
		115:
			draw_rect(Rect2(origin+Vector2(18,5),Vector2(1,6)),Color(color,0.55*intensity))
			chamber_glow(origin+Vector2(19,8),Vector2(8,10),color,0.2*intensity)
		122:
			var hub := origin+Vector2(16.5,8)
			for spoke in 3:
				var axis := Vector2.RIGHT.rotated(spoke*TAU/3+clock*0.7)
				draw_line(hub+axis,hub+axis*2.5,Color(color,0.52*intensity),0.8,true)

func chamber_glow(center: Vector2, size: Vector2, color: Color, alpha: float):
	var glow = preload("res://game/effects/PresentationLight.gd").texture()
	draw_texture_rect(glow,Rect2(center-size/2,size),false,Color(color,alpha))
