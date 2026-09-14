extends "res://tests/M8Runtime.gd"

var observing = false
var samples = []
var previous_projectiles = {}
var target_point = Vector2.ZERO
var visual_contact = false
var observed_max = 0.0
var muzzle = Vector2.ZERO

func capsule_contact(a: Vector2,b: Vector2,padding: float) -> bool:
	# Monster2 is a vertical capsule (radius 7, total height 20), not a circle.
	var top = target_point-Vector2(0,3)
	var bottom = target_point+Vector2(0,3)
	if Geometry2D.segment_intersects_segment(a,b,top,bottom) != null: return true
	var distance = minf(Geometry2D.get_closest_point_to_segment(top,a,b).distance_to(top),Geometry2D.get_closest_point_to_segment(bottom,a,b).distance_to(bottom))
	distance = minf(distance,minf(Geometry2D.get_closest_point_to_segment(a,top,bottom).distance_to(a),Geometry2D.get_closest_point_to_segment(b,top,bottom).distance_to(b)))
	return distance <= 7.1+padding

func sample_projectile(node):
	if not observing or not is_instance_valid(node): return
	var previous = previous_projectiles.get(node.get_instance_id(),node.global_position)
	var point = node.global_position
	var radius = 8.0 if node.get("spec") != null and node.spec.get("mode","")=="disc" else 4.0
	if capsule_contact(previous,point,radius): visual_contact = true
	previous_projectiles[node.get_instance_id()] = point
	observed_max = maxf(observed_max,muzzle.distance_to(point)+radius)

func _process(delta):
	if not observing: return
	for node in get_tree().get_nodes_in_group("combat_transient"):
		if node is Bullet:
			if not previous_projectiles.has(node.get_instance_id()): node.tree_exiting.connect(sample_projectile.bind(node),CONNECT_ONE_SHOT)
			sample_projectile(node)
		elif node.get_script() == load("res://game/effects/CombatEffect.gd"):
			for point in node.points: observed_max = maxf(observed_max,muzzle.distance_to(point))
			if node.radius>0:
				if not node.footprint.is_empty():
					for point in node.footprint: observed_max = maxf(observed_max,muzzle.distance_to(node.to_global(point)))
					if Geometry2D.is_point_in_polygon(target_point+Vector2(-1,9)-node.global_position,node.footprint): visual_contact = true
				else:
					observed_max = maxf(observed_max,muzzle.distance_to(node.global_position)+node.radius)
					if target_point.distance_to(node.global_position)<=node.radius: visual_contact = true
			elif node.points.size()>2 and node.points[0].is_equal_approx(node.points[-1]):
				if Geometry2D.is_point_in_polygon(target_point,PackedVector2Array(node.points)): visual_contact = true
			else:
				for i in range(1,node.points.size()):
					var a = node.points[i-1]
					var b = node.points[i]
					if capsule_contact(a,b,node.width/2): visual_contact = true
					observed_max = maxf(observed_max,muzzle.distance_to(b))
	var gun = Utils.player.gun
	if gun.weapon_id == 6 and gun.is_cast:
		var a = gun.line_2d.to_global(gun.line_2d.points[0])
		var b = gun.line_2d.to_global(gun.line_2d.points[1])
		if capsule_contact(a,b,0): visual_contact = true
		observed_max = maxf(observed_max,a.distance_to(b))

func _ready():
	await boot()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(20,0)
	var rows = []
	for key in Utils.weapon_list:
		var id = int(key)
		configure(id,false)
		var gun = Utils.player.gun
		var reach = gun.effective.get("projectile_path_limit",gun.effective.range)
		if id == 121: reach = gun.bullet_speed*2*0.45+gun.effective.radius
		if id == 122: reach = gun.bullet_speed*2*0.55
		for scenario in ["near","middle","limit","outside","before_wall","behind_wall"]:
			gun.cancel_actions()
			gun.bullets_count = gun.bullets_max_count
			gun.global_rotation = 0
			gun.gun_tip.global_position = origin
			gun.direction = Vector2.RIGHT
			LevelServer.state = "COMBAT"
			muzzle = gun.cast.global_position if id == 6 else gun.gun_tip.global_position
			var distance = {"near":minf(40,reach*0.25),"middle":reach*0.5,"limit":reach-12,"outside":reach+40,"before_wall":reach*0.25,"behind_wall":reach*0.75}[scenario]
			target_point = muzzle+Vector2(distance,0)
			var target = enemy(target_point+Vector2(-1,9),100000)
			target.knockback_def = 100000
			var barrier = wall(muzzle+Vector2(reach*0.5,0),Vector2(4,500)) if scenario in ["before_wall","behind_wall"] else null
			await wait(0.08)
			var motion = InputEventMouseMotion.new(); motion.position = play_view.get_canvas_transform()*(muzzle+Vector2(2000,0)); play_view.push_input(motion,true)
			gun.direction = Vector2.RIGHT
			if id == 113: gun.charge_time = gun.effective.warmup
			previous_projectiles.clear(); visual_contact = false; observed_max = 0; observing = true
			gun._shoot()
			var start = Time.get_ticks_msec()
			while Time.get_ticks_msec()-start < 2400:
				if id == 6: gun._physics_process(1.0/60)
				await get_tree().physics_frame
			observing = false
			var actual = target.HP<100000
			var row = {"id":id,"case":scenario,"distance":distance,"declared_path_limit":reach,"observed_visible_max":observed_max,"visible_hit_expected":visual_contact,"actual_hit":actual,"consistent":visual_contact==actual,"screenshot":"PENDING","method":"runtime visual primitives and projectile sweep including tree_exiting collision endpoint; actual capsule radius 7px plus 0.1px tolerance; screenshot review pending"}
			row["name"] = tr(gun.weapon_name)
			row["mechanism"] = WeaponCatalog.definition(id).get("mode","beam" if id==6 else ("arc" if id==112 else "projectile"))
			rows.append(row); print("M9_PRESENTATION ",JSON.stringify(row))
			gun.cancel_actions()
			if barrier: barrier.queue_free()
			await clean()
			DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/m9")
			var file = FileAccess.open("res://docs/iteration/evidence/m9/presentation.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(rows,"\t")); file.close()
	await Demo.quit_game()
