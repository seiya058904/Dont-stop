extends "res://tests/M3Weapons.gd"
var play_view: SubViewport
var driving = false
var moving = true
var target_boss = false
var shots_fired = 0
var movement = 0.0
var bot_clock = 0.0
var last_position = Vector2.ZERO
var dash_cooldown = 0.0

# ---- B9 dodge telemetry ---------------------------------------------------------------
# Observation only. Every counter below is written inside choose_safe_movement() and read
# back by the measurement row; none of them feeds a decision, and removing them would not
# change one pixel of movement.
const DODGE_DIRECTIONS := 16
const DODGE_WALL_STEP := 24.0
const DODGE_LOOKAHEAD := 38.0
const DODGE_SHOT_LOOKAHEAD := 0.3
var dodge_decisions := 0
var dodge_blocked := 0
var dodge_scored := 0
var dodge_danger_marks := 0
var dodge_all_danger := 0
var dodge_risky_choices := 0
var dodge_unchanged := 0
var dodge_all_blocked := 0
var dodge_last: Dictionary = {}

func reset_dodge_telemetry() -> void:
	dodge_decisions = 0; dodge_blocked = 0; dodge_scored = 0; dodge_danger_marks = 0
	dodge_all_danger = 0; dodge_risky_choices = 0; dodge_unchanged = 0
	dodge_all_blocked = 0; dodge_last = {}

func dodge_report() -> Dictionary:
	return {"dodge_decisions":dodge_decisions,"dodge_blocked_candidates":dodge_blocked,
		"dodge_scored_candidates":dodge_scored,"dodge_danger_marks":dodge_danger_marks,
		"dodge_all_danger":dodge_all_danger,"dodge_risky_choices":dodge_risky_choices,
		"dodge_unchanged":dodge_unchanged,"dodge_all_blocked":dodge_all_blocked,
		"dodge_last":dodge_last}

func _enter_tree():
	if DisplayServer.get_name()!="headless":
		get_window().unfocusable = true
		get_window().mouse_passthrough = true
func boot():
	Demo.test_mode = true; seed(808)
	play_view = SubViewport.new(); play_view.size = Vector2i(410,230); play_view.world_2d = get_viewport().world_2d
	play_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if DisplayServer.get_name() != "headless" else SubViewport.UPDATE_DISABLED
	add_child(play_view); play_view.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000; PlayerData.reward_point = 9999
func dismiss():
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
func stop():
	driving = false
	for action in ["shoot","left","right","up","down","dash"]: Input.action_release(action)
	Demo.stop_attacks()
func configure(gun_id: int, full = false):
	LevelServer.state = "CAMP"
	if not PlayerData.player_weapon_list.has(gun_id): Demo.try_purchase("weapon",str(gun_id))
	if full:
		for id in Utils.am_dict: Demo.try_purchase("attachment",id)
		for id in DemoConfig.TALENTS:
			while Demo.rank(id) < DemoConfig.TALENTS[id].max: Demo.try_purchase("talent",id,"points")
	Utils.player.changeWeapon(gun_id)
	var gun = Utils.player.gun
	# M7 comparison retains its legal one-per-slot installation; M8 needs none.
	if Demo.get("owned_global_upgrades") == null:
		for am in PlayerData.player_am_list.values(): gun.addAttachMent(am)
	gun.set_process(false); gun.set_physics_process(false)
	gun.bullets_count = gun.bullets_max_count; PlayerData.reserve_magazines = 100
	PlayerData.player_hp = PlayerData.player_hp_max
	last_position = Utils.player.global_position
func fire_at(point: Vector2, delta: float):
	var gun = Utils.player.gun
	gun.set_process(false); gun.set_physics_process(false)
	var motion = InputEventMouseMotion.new(); motion.position = play_view.get_canvas_transform()*point; play_view.push_input(motion,true)
	gun.look_at(point); gun.direction = gun.gun_tip.global_position.direction_to(point)
	var before = gun.bullets_count
	if gun.weapon_id == 113:
		gun.handle_charge(not (gun.charging and gun.charge_time >= gun.effective.warmup),delta)
	elif gun.weapon_id == 116: gun.handle_thermal(true,delta)
	else:
		if gun.weapon_id == 124: gun.drive_spin(not gun.is_reloading,delta)
		if gun.can_shoot and not gun.is_reloading:
			if gun.bullets_count == 0: gun.reload_ammo()
			else: gun._shoot(); gun.can_shoot = false; gun.timer.start()
	if gun.bullets_count < before: shots_fired += 1
func _process(delta):
	# A truly minimized non-focusable window suppresses automatic drawing.
	# Keep the native game viewport rendered without presenting or taking focus.
	if DisplayServer.get_name()!="headless": RenderingServer.force_draw(false)
	if not driving or get_tree().paused or not is_instance_valid(Utils.player) or Utils.player.is_dead or LevelServer.state != "COMBAT": return
	dash_cooldown = maxf(0,dash_cooldown-delta)
	var actors = get_tree().get_nodes_in_group("monsters").filter(func(a): return not a.is_die and not a.is_queued_for_deletion())
	if actors.is_empty(): return
	actors.sort_custom(func(a,b): return a.global_position.distance_squared_to(Utils.player.global_position)<b.global_position.distance_squared_to(Utils.player.global_position))
	var target = actors[0]
	if target_boss:
		var boss = instance_from_id(LevelServer.boss_instance)
		if is_instance_valid(boss) and not boss.is_die: target = boss
	var aim_target = target
	if target_boss and actors[0]!=target and actors[0].global_position.distance_to(Utils.player.global_position)<95:
		aim_target = actors[0]
	var aim_point = aim_target.global_position-Vector2(0,8)
	if target_boss and Utils.player.gun.weapon_id == 117:
		var flight = Utils.player.global_position.distance_to(aim_target.global_position)/Utils.player.gun.effective.projectile_speed
		aim_point += aim_target.velocity*minf(flight,0.5)
	fire_at(aim_point,delta)
	movement += last_position.distance_to(Utils.player.global_position); last_position = Utils.player.global_position
	bot_clock += delta
	if bot_clock < 0.1: return
	bot_clock = 0
	var direction = Vector2.ZERO
	var offset = target.global_position-Utils.player.global_position
	if moving:
		if offset.length()>110 or not Combat.clear_line(Utils.player.global_position,target.global_position):
			var step = LevelServer.town.path_step(Utils.player.global_position,target.global_position)
			direction = Utils.player.global_position.direction_to(step)
		elif offset.length()<65: direction = -offset.normalized().rotated(0.5)
		else: direction = offset.normalized().orthogonal()*0.7
		# Both an ordinary late-game encounter and a boss steer through the SAME core. This
		# evaluation used to sit behind `target_boss and target.is_boss`, so the Boss driver
		# dodged and the Stage 21-29 driver walked straight into the telegraphs - which made
		# every Normal clear rate measured with it an underestimate of what the build can do.
		# Only the Boss TARGET PRIORITY, the Boss lead aim and the Boss close-range dash below
		# stay boss-specific.
		direction = choose_safe_movement(direction,target,actors)
	for pair in [["left",direction.x < -0.2],["right",direction.x > 0.2],["up",direction.y < -0.2],["down",direction.y > 0.2]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])
	if target_boss and target.is_boss and dash_cooldown<=0 and actors[0].global_position.distance_to(Utils.player.global_position)<65:
		dash_cooldown = 0.85
		Input.action_press("dash")
		var event = InputEventAction.new(); event.action = "dash"; event.pressed = true
		Utils.player._input(event)
		Input.action_release("dash")

## The ONE dangerous-direction evaluator, shared by ordinary encounters and bosses.
##
## `wanted_direction` is what the chase logic above wants to do; the return value is the
## direction the driver will actually press. It reads only real state - the player's own
## collider through test_move, the live monster list, the live hostile zones, the live enemy
## shots, the real line-of-sight ray - and it moves the player only through the WASD presses
## the caller issues. There is no teleport, no invulnerability, no HP edit, no deleted
## projectile, no deleted zone and no forced kill anywhere in this function, and there must
## never be one.
##
## The 16-direction scoring itself is the boss driver's own scan, moved here verbatim: same
## wall step, same 38 px lookahead, same firing-lane, arena-bounds, body-spacing, telegraph
## and projectile-lookahead terms, same graded exit depth. What changed is WHO calls it.
##
## Reaction budget: the caller invokes this once per movement decision (10 Hz), not per
## physics frame. The bot therefore reacts about as fast as a person, not 60 times a second.
func choose_safe_movement(wanted_direction: Vector2, target, actors: Array) -> Vector2:
	var wanted := wanted_direction
	var choice := wanted
	var best := -INF
	var best_risky := false
	var scored := 0
	var blocked := 0
	var marks := 0
	var risky_candidates := 0
	var penalties := 0
	var zones = get_tree().get_nodes_in_group("hostile_zone")
	var shots: Array = []
	for shot in get_tree().get_nodes_in_group("combat_transient"):
		if shot.get_script() and shot.get_script().resource_path == "res://game/monster/EnemyShot.gd":
			shots.append(shot)
	var arena = LevelServer.town.arena if is_instance_valid(LevelServer.town) else null
	var origin: Vector2 = Utils.player.global_position
	for i in DODGE_DIRECTIONS:
		var candidate = Vector2.RIGHT.rotated(i*TAU/DODGE_DIRECTIONS)
		if Utils.player.test_move(Utils.player.global_transform,candidate*DODGE_WALL_STEP):
			blocked += 1
			continue
		scored += 1
		var next = origin+candidate*DODGE_LOOKAHEAD
		var score = candidate.dot(wanted)*1.5
		var risky := false
		# Keep a firing lane instead of circling indefinitely behind an arena column.
		if not Combat.clear_line(next,target.global_position): score -= 3; penalties += 1
		if arena != null:
			var local = arena.to_local(next)
			if absf(local.x)>320 or absf(local.y)>230: score -= 1.5; penalties += 1
		for actor in actors:
			var distance = next.distance_to(actor.global_position)
			if distance<62: score -= (62-distance)*0.2; penalties += 1
		for zone in zones:
			if zone.damage<=0 and zone.mode not in ["charge","circle"]: continue
			var relative = next-zone.global_position
			var danger = relative.length()<zone.radius+16
			if zone.mode in ["line","charge"]:
				danger = Geometry2D.get_closest_point_to_segment(next,zone.global_position,zone.global_position+zone.direction*zone.length).distance_to(next)<zone.width+18
			elif zone.mode=="cone": danger = relative.length()<zone.radius+16 and absf(zone.direction.angle_to(relative))<zone.angle+0.15
			if danger:
				# A graded exit distance still chooses an escape when every nearby sample is inside.
				var depth = maxf(0,zone.radius+16-relative.length())
				if zone.mode == "cone": depth = minf(depth,relative.length()*maxf(0,zone.angle+0.15-absf(zone.direction.angle_to(relative))))
				elif zone.mode in ["line","charge"]: depth = zone.width+18-Geometry2D.get_closest_point_to_segment(next,zone.global_position,zone.global_position+zone.direction*zone.length).distance_to(next)
				score -= 8+depth*0.6
				penalties += 1; marks += 1; risky = true
		for shot in shots:
			if Geometry2D.get_closest_point_to_segment(next,shot.global_position,shot.global_position+shot.velocity*DODGE_SHOT_LOOKAHEAD).distance_to(next)<18:
				score -= 4; penalties += 1; marks += 1; risky = true
		if risky: risky_candidates += 1
		if score>best: best=score; choice=candidate; best_risky=risky
	dodge_decisions += 1
	dodge_blocked += blocked
	dodge_scored += scored
	dodge_danger_marks += marks
	if scored > 0 and risky_candidates == scored: dodge_all_danger += 1
	if scored == 0: dodge_all_blocked += 1
	# Two ways the wish survives untouched, and both are deliberate:
	#  * nothing in the field argued against it - no wall, no live footprint, no incoming shot,
	#    no crowding body, no lost firing lane - so snapping it to the nearest of 16 samples
	#    would be a change with no cause;
	#  * nothing is reachable at all (every sample is pressed into geometry), so there is no
	#    better answer to give and a NaN would be a bug. The wish is kept and reported.
	var constrained := penalties > 0 or blocked > 0
	if scored == 0 or (not constrained and wanted.length_squared() > 0.0001):
		choice = wanted
		best_risky = false
		dodge_unchanged += 1
	if best_risky: dodge_risky_choices += 1
	dodge_last = {"wanted":wanted,"chosen":choice,"scored":scored,"blocked":blocked,
		"marks":marks,"penalties":penalties,"risky":best_risky,
		"all_danger":(scored > 0 and risky_candidates == scored)}
	return choice
