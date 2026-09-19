extends "res://tests/B8Runtime.gd"

# Render-only debug ink is never loaded by production. Cyan is the actual player
# collider; magenta is the attack's player-center acceptance boundary.
class BoundaryInk extends Node2D:
	var kind := "line"
	var player_point := Vector2.ZERO
	var player_radius := 7.0
	func _draw():
		draw_arc(player_point,player_radius,0,TAU,32,Color.CYAN,1,true)
		if kind in ["line","shot"]:
			var half_length = 70.0 if kind == "line" else 30.0
			var margin = 14.0 if kind == "line" else 12.0
			draw_line(Vector2(-half_length,-margin),Vector2(half_length,-margin),Color.MAGENTA,1,true)
			draw_line(Vector2(-half_length,margin),Vector2(half_length,margin),Color.MAGENTA,1,true)
			draw_arc(Vector2(-half_length,0),margin,PI/2,PI*1.5,32,Color.MAGENTA,1,true)
			draw_arc(Vector2(half_length,0),margin,-PI/2,PI/2,32,Color.MAGENTA,1,true)
		elif kind == "cone":
			draw_arc(Vector2.ZERO,38,-0.7,0.7,32,Color.MAGENTA,1,true)
			for side in [-1,1]: draw_line(Vector2.ZERO,Vector2.RIGHT.rotated(side*0.7)*38,Color.MAGENTA,1,true)
		else:
			draw_arc(Vector2.ZERO,38,0,TAU,64,Color.MAGENTA,1,true)

var output: String
var rows: Array = []
func record(name: String, ink: Node2D, result: Dictionary):
	await wait(0.35) # Let actual hit feedback settle before inspecting the debug edge.
	await settle_render()
	play_view.get_texture().get_image().save_png(output+"/"+name+".png")
	result["name"] = name
	rows.append(result)
	ink.queue_free()

func _ready():
	await boot()
	dismiss()
	output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty() or not rendering(): get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	configure(124,false)
	PlayerData.player_hp_max = 100000
	PlayerData.player_hp = 100000
	check(LevelServer.town.depart(6,true),"boundary fixture departs into actual arena")
	await visual_ready(Vector2i(410,230))
	await freeze_room()
	var center: Vector2 = Utils.player.global_position
	render_camera.global_position = center
	var collider = Utils.player.get_node("CollisionShape2D")
	var actual_radius: float = collider.shape.radius
	for kind in ["line","circle","cone"]:
		for inside in [true,false]:
			var zone = load("res://game/monster/HostileZone.gd").new()
			zone.mode = kind; zone.style = "beam" if kind == "line" else "poison"
			zone.world_point = center-Vector2(70,0) if kind == "line" else center
			zone.length = 140; zone.width = 8; zone.radius = 38
			zone.warning = 0.01; zone.duration = 10; zone.damage = 1
			add_child(zone) # Same shared World2D and parent layer as production zones.
			zone.set_physics_process(false); zone.fair_gate = false
			var offset = Vector2(0,13.8 if inside else 14.2) if kind == "line" else Vector2(37.8 if inside else 38.2,0)
			Utils.player.global_position = center+offset
			zone.step(0.02)
			check((zone.hit_count>0)==inside,kind+" actual boundary hit="+str(inside))
			var ink = BoundaryInk.new()
			ink.kind = kind; ink.player_point = offset; ink.player_radius = actual_radius
			add_child(ink); ink.global_position = center; ink.z_index = 100
			await record(kind+("-inside" if inside else "-outside"),ink,{"hit_count":zone.hit_count,"player_radius":actual_radius,"offset":str(offset)})
			zone.queue_free()
			await wait(0.15)
	for inside in [true,false]:
		var shot = load("res://game/monster/EnemyShot.gd").new()
		add_child(shot)
		shot.set_physics_process(false)
		shot.global_position = center-Vector2(30,0); shot.velocity = Vector2(60,0)
		var offset = Vector2(0,11.8 if inside else 12.2)
		Utils.player.global_position = center+offset
		var ink = BoundaryInk.new()
		ink.kind = "shot"; ink.player_point = offset; ink.player_radius = actual_radius
		add_child(ink); ink.global_position = center; ink.z_index = 100
		# Capture the body and full swept acceptance corridor before the real step frees it.
		await record("shot"+("-inside" if inside else "-outside"),ink,{"player_radius":actual_radius,"offset":str(offset)})
		var hp: float = PlayerData.player_hp
		shot._physics_process(1.0)
		var hit: bool = PlayerData.player_hp < hp
		rows[-1]["actual_hit"] = hit
		check(hit==inside,"actual swept projectile boundary hit="+str(inside))
		if is_instance_valid(shot): shot.queue_free()
		await wait(0.15)
	var file = FileAccess.open(output+"/events.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("PRESENTATION_BOUNDARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
