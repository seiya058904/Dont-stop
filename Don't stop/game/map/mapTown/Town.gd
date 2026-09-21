extends Node2D

@onready var pos_start = $TileMap2/Level_1/pos_start
@onready var pos_end = $TileMap2/Level_1/pos_end
@onready var pos_level_1 = $TileMap2/Level_1
@onready var pos_level_5 = $TileMap2/Level_5/pos_start
@onready var pos_level_11 = $TileMap2/Level_11
@onready var pos_level_16 = $TileMap2/Level_16
@onready var pos_level_21 = $TileMap2/Level_21
@onready var pos_level_26 = $TileMap2/Level_26
@onready var monster_root = $TileMap2/MonsterRoot
@onready var shopBtn = $CanvasLayer/openShop
@onready var kill_playr = $Kill
@onready var portal_start = $TileMap2/PortalRoot/Portal
@onready var portal_lv1 = $TileMap2/PortalRoot/Portal2
@onready var portal_lv5 = $TileMap2/PortalRoot/Portal3
@onready var portal_lv11 = $TileMap2/PortalRoot/Portal4
@onready var portal_lv16 = $TileMap2/PortalRoot/Portal5
@onready var portal_lv21 = $TileMap2/PortalRoot/Portal6
@onready var portal_lv26 = $TileMap2/PortalRoot/Portal7

const gold = preload("res://game/items/Gold.tscn")
const weapon_choose = preload("res://ui/widgets/WeaponChoose.tscn")
const monster_pre = preload("res://game/monster/Monster 2/Monster2.tscn")
const death_borad = preload("res://ui/widgets/DeathBoard.tscn")

var camp_prompt: Label

func _ready():
	LevelServer.town = self
	# A fresh Main.tscn instance already carries the authored bright ambient and light, so
	# only the runtime stage needs dropping - never a second write to the scene defaults.
	ArenaVisibility.reset()
	camp_prompt = Label.new()
	camp_prompt.text = "按 E 打开营地"
	camp_prompt.position = Vector2(165,188)
	camp_prompt.add_theme_font_size_override("font_size",8)
	camp_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(camp_prompt)
	call_deferred("build_navigation")
	LevelServer.monsterCreate.connect(self.monsterCreate)
	LevelServer.roundVictory.connect(self.roundVictory)
	LevelServer.onTimeTick.connect(self.onTimeTick)
	LevelServer.onRoundStart.connect(self.onRoundStart)
	LevelServer.onRoundEnd.connect(self.onRoundEnd)
	LevelServer.onNextLevel.connect(self.onNextLevel)
	Utils.onGameStart.connect(self.onGameStart)
	PlayerData.onPlayerDeath.connect(self.onPlayerDeath)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("e") and Utils.is_game_start and LevelServer.state == "CAMP" and Demo.pause_stack.is_empty():
		if $RewardNpc.get_node("Button").visible:
			$RewardNpc.open_reward()
		else:
			Demo.open_panel()
		get_viewport().set_input_as_handled()

func onGameStart():
	$CanvasLayer/level.visible = true
	$CanvasLayer/timeout.visible = true

func onPlayerDeath():
	if LevelServer.state != "COMBAT": return
	LevelServer.state = "DEAD"
	LevelServer.timerStop()
	Demo.stop_attacks()
	var ins = death_borad.instantiate()
	ins.process_mode = Node.PROCESS_MODE_ALWAYS
	ins.setOnClick(func(success):
		Demo.pop_pause(ins)
		if success:
			PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
			LevelServer.state = "COMBAT"
			LevelServer.timerStart()
		else:
			PlayerData.resurrectPlayer(1,20)
			LevelServer.return_to_camp())
	$CanvasLayer.add_child(ins)
	Demo.push_pause(ins)

func _on_portal_2_move_out() -> void:
	# Arrival is cosmetic; the shared departure request already started the round.
	pass

func onTimeTick(timeout) -> void:
	if Utils.player.is_dead == false:
		$CanvasLayer/timeout.text = ("Boss 战斗用时 " if DemoConfig.ENCOUNTERS[LevelServer.level].has("boss") else tr("REMAINING TIME")) + str(timeout)

#回合开始
func onRoundStart():
	camp_prompt.hide()
	Utils.showToast("START_TIP",2)
	$CanvasLayer/timeout.visible = true
	$CanvasLayer/level.visible = true
	$CanvasLayer/level.text = DemoConfig.ENCOUNTERS[LevelServer.level].name

#回合结束
func onRoundEnd():
	camp_prompt.show()
	if is_instance_valid(arena): arena.queue_free(); arena = null
	Utils.player.global_position = $PositionHome.global_position
	$CanvasLayer/timeout.text = "营地整备 · E 商店 / Tab 配置"
	for item in $TileMap2/PortalRoot.get_children(): item.reset()
	# Belt and braces with LevelServer.return_to_camp(): the camp is bright in every path
	# out of a round, including death, a manual return and a scene teardown.
	ArenaVisibility.restore(true)
	FogPierce.discard()

#回合胜利
func roundVictory():
	Utils.showToast("VICTORY IN THE ROUND",1)
	$CanvasLayer.add_child(LevelServer.getScoreboard())

#获取坐标点
func getPoint():
	var random_point
	if [1,2,3,4,5].has(LevelServer.level):
		var node = pos_level_1.get_child(randi()%pos_level_1.get_child_count())
		random_point = node.global_position
	elif [6,7,8,9,10].has(LevelServer.level):
		random_point = pos_level_5.global_position
	elif [11,12,13,14,15].has(LevelServer.level):
		var node = pos_level_11.get_child(randi()%pos_level_11.get_child_count())
		random_point = node.global_position
	elif [16,17,18,19,20].has(LevelServer.level):
		var node = pos_level_16.get_child(randi()%pos_level_16.get_child_count())
		random_point = node.global_position
	elif [21,22,23,24,25].has(LevelServer.level):
		var node = pos_level_21.get_child(randi()%pos_level_21.get_child_count())
		random_point = node.global_position
	elif [26,27,28,29,30].has(LevelServer.level):
		var node = pos_level_26.get_child(randi()%pos_level_26.get_child_count())
		random_point = node.global_position
	# R7/R8 (31-40) fight in a generated arena rather than the camp tilemap, and any future
	# stage must not fall through to `null` and crash a caller.
	return random_point if random_point != null else $PositionHome.global_position

func _on_shop_body_entered(body: Node2D) -> void:
	if body is Player:
		shopBtn.visible = true

func _on_shop_body_exited(body: Node2D) -> void:
	if body is Player:
		shopBtn.visible = false

#进入地图
func _on_portal_move_in(_next_area):
	if not depart(Demo.next_stage,false):
		Utils.showToast("无法出发：需要存活、装备武器并处于营地")
		portal_start.call_deferred("reset")

#下一关通知
func onNextLevel(level):
	if [1,2,3,4,5].has(LevelServer.level):
		portal_start.next_area = portal_lv1
	elif [6,7,8,9,10].has(LevelServer.level):
		portal_start.next_area = portal_lv5
	elif [11,12,13,14,15].has(LevelServer.level):
		portal_start.next_area = portal_lv11
	elif [16,17,18,19,20].has(LevelServer.level):
		portal_start.next_area = portal_lv16
	elif [21,22,23,24,25].has(LevelServer.level):
		portal_start.next_area = portal_lv21
	elif [26,27,28,29,30].has(LevelServer.level):
		portal_start.next_area = portal_lv26

#怪物生成
func monsterCreate():
	if LevelServer.state != "COMBAT": return
	var config = DemoConfig.ENCOUNTERS[LevelServer.level]
	var active = 0
	for enemy in get_tree().get_nodes_in_group("monsters"):
		if not enemy.is_die and not enemy.training: active += 1
	if active >= config.cap or config.roles.is_empty(): return
	var role = LevelServer.horde_role if LevelServer.horde_active else ("E02" if LevelServer.rush_active else config.roles[LevelServer.spawn_index % config.roles.size()])
	# The clearance must match the actor that is about to be created: a fixed 7 px
	# radius is the collider's radius only, and the capsule bodies are larger and
	# offset from their origin, which let a wave enemy be created inside a wall.
	var point = spawn_point(M5Content.radius_for(role))
	if point == Vector2.INF:
		M5Content.audit_deferred += 1
		return
	# Rhythm controls arrival timing, never replaces a mixed roster with one role for 7-15 seconds.
	LevelServer.spawn_index += 1
	var ins = M5Content.spawn(role,monster_root,point)
	if ins == null: return
	_promote_if_elite(ins,ins.get_meta("content_id",role))

## Elites are a rate now, not a single mid-round flag. The plan gives a start time, an
## interval and a simultaneous ceiling; every promoted actor also receives one named extra
## mechanic, so an elite is a different problem rather than a bigger health bar.
func _promote_if_elite(ins,role: String) -> void:
	var plan = M5Content.elite_plan(LevelServer.level)
	if plan.is_empty() or ins.get("is_elite") == true: return
	if LevelServer.level_info.time < float(plan.get("start",1e9)) or LevelServer.elite_clock > 0.0: return
	if not M5Content.can_promote(ins): return
	var alive = 0
	for enemy in get_tree().get_nodes_in_group("monsters"):
		if not enemy.is_die and enemy.get("is_elite") == true: alive += 1
	if alive >= int(plan.get("cap",1)): return
	LevelServer.elite_clock = float(plan.get("interval",12.0))
	LevelServer.elites_created += 1
	M5Content.promote_elite(ins,M5Content.elite_modifier_for(role))

#怪物死亡
func onMonsterDeath(monster_ins):
	LevelServer.level_info.kill += 1
	if randi() % 3 <= 1:
		var ins = gold.instantiate()
		ins.global_position = monster_ins.global_position
		ins.setGiveCallBack(func onGive():
			LevelServer.level_info.gold += 1)
		monster_root.add_child(ins)
	if not kill_playr.playing: kill_playr.play()

var navigation = AStarGrid2D.new()
var nav_ready = false
var walkable: Array[Vector2i] = []
func build_navigation():
	await get_tree().physics_frame
	navigation.region = Rect2i(-10,18,58,34)
	navigation.cell_size = Vector2(16,16)
	navigation.offset = Vector2(8,8)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	# One reusable shape and one reusable query for the whole pass. This runs once per scene load,
	# but it is 1972 cells: allocating a CircleShape2D and a PhysicsShapeQueryParameters2D per cell
	# was 1972 allocations for a result that never changes.
	var shape = CircleShape2D.new()
	shape.radius = 7
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 2147483649
	query.exclude = [Utils.player.get_rid()]
	var space = get_world_2d().direct_space_state
	var ground_count = 0
	var collision_count = 0
	for x in range(-10,48):
		for y in range(18,52):
			var cell = Vector2i(x,y)
			var point = navigation.get_point_position(cell)
			var ground = $TileMap3.get_cell_source_id(0,$TileMap3.local_to_map(point)) != -1
			# A cell with no ground is already solid; asking the physics world about it cannot change
			# that answer, so the query is skipped. Cells with ground are asked exactly as before.
			var blocked = false
			if ground:
				query.transform = Transform2D(0,point)
				blocked = not space.intersect_shape(query,1).is_empty()
			if ground: ground_count += 1
			if blocked: collision_count += 1
			var solid = not ground or blocked
			navigation.set_point_solid(cell,solid)
			if not solid: walkable.append(cell)
	nav_ready = true

func nav_cell(point: Vector2) -> Vector2i:
	return Vector2i(floor(point.x/16),floor(point.y/16))

func path_step(from: Vector2, to: Vector2) -> Vector2:
	if is_instance_valid(arena): return arena.path_step(from,to)
	if not nav_ready or Combat.clear_line(from,to): return to
	var a = nav_cell(from)
	var b = nav_cell(to)
	if not navigation.is_in_boundsv(a) or not navigation.is_in_boundsv(b): return from
	if navigation.is_point_solid(a) or navigation.is_point_solid(b): return to
	var path = navigation.get_point_path(a,b)
	return path[1] if path.size() > 1 else from

## Arrival ring. The MINIMUM is the near-player pressure dial: late and Hell stages close it
## from 145 px to ~108 px so reinforcement actually forms pressure around the player instead
## of queueing at the rim. The maximum stays at the arena's usable radius - lowering the
## minimum is the lever, not raising the ceiling.
func ring() -> Vector2:
	var pressure = M5Content.encounter_pressure(LevelServer.level)
	return Vector2(float(pressure.get("ring_min",145.0)),float(pressure.get("ring_max",280.0)))

func spawn_point(radius := -1.0) -> Vector2:
	if radius <= 0.0: radius = M5Content.default_radius()
	var limits = ring()
	if is_instance_valid(arena):
		if LevelServer.flank_active:
			# Hell multi-direction arrival. Same validators as the ring, arbitrary arc, so a
			# flank wave cannot place an enemy somewhere the ring would have refused.
			var flank_point = arena.spawn_flank(Utils.player.global_position,limits.x,limits.y,radius)
			if flank_point != Vector2.INF: return flank_point
		var sides = M5Content.REGIONS[arena.region_id].sides
		var side=LevelServer.horde_side if LevelServer.horde_active else (LevelServer.rush_side if LevelServer.rush_active else LevelServer.spawn_index%sides.size())
		return arena.spawn_near(Utils.player.global_position,limits.x,limits.y,sides[side],radius)
	if not nav_ready or walkable.is_empty():
		M5Content.audit_deferred += 1
		return Vector2.INF
	var player_cell = nav_cell(Utils.player.global_position)
	if not navigation.is_in_boundsv(player_cell) or navigation.is_point_solid(player_cell):
		M5Content.audit_deferred += 1
		return Vector2.INF
	var offset = randi()%walkable.size()
	for attempt in walkable.size():
		var cell = walkable[(offset+attempt)%walkable.size()]
		var point = navigation.get_point_position(cell)
		M5Content.audit_candidates += 1
		var distance = point.distance_to(Utils.player.global_position)
		if distance < limits.x or distance > limits.y:
			M5Content.audit_rejected += 1; continue
		if navigation.get_id_path(cell,player_cell).size() <= 1:
			M5Content.audit_rejected += 1; continue
		# The navigation grid is built once with a 7 px circle, so a larger actor
		# needs its own clearance check: otherwise the grid would certify a cell that
		# only fits the smallest enemy.
		if not _nav_point_clear(point,radius):
			M5Content.audit_rejected += 1; continue
		return point
	M5Content.audit_deferred += 1
	return Vector2.INF

## Same shape query the arena uses, for the town's navigation branch.
## Cached per radius, exactly like the arena's own copy: `spawn_point()` asks this once per candidate
## cell, so an uncached version allocated two physics objects per candidate.
var _town_queries: Dictionary = {}
func _nav_query(radius: float) -> PhysicsShapeQueryParameters2D:
	var key := snappedf(radius,0.01)
	if _town_queries.has(key): return _town_queries[key]
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 2147483649
	_town_queries[key] = query
	return query

func _nav_point_clear(point: Vector2, radius: float) -> bool:
	var query := _nav_query(radius)
	query.transform = Transform2D(0,point)
	query.exclude = [Utils.player.get_rid()] if is_instance_valid(Utils.player) else []
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func depart(stage: int, is_trial: bool) -> bool:
	var target_stage = stage if is_trial else Demo.next_stage
	if not LevelServer.can_start(target_stage): return false
	var previous_stage = Demo.selected_stage
	var previous_trial = Demo.trial
	Demo.selected_stage = target_stage
	Demo.trial = is_trial
	if not LevelServer.roundStart():
		Demo.selected_stage = previous_stage
		Demo.trial = previous_trial
		return false
	prepare_region(DemoConfig.ENCOUNTERS[target_stage].region)
	# Fog is applied AFTER the region exists, so the tween targets the live CanvasModulate and
	# the retained camera light of this scene rather than a stale node. Stage 1-30 targets the
	# authored bright ambient, so this call is a no-op for the normal campaign.
	ArenaVisibility.apply_stage(target_stage)
	StageHazard.audit_spawned = 0
	StageHazard.audit_rejected = 0
	StageHazard.audit_skipped_anchor = 0
	StageHazard.audit_peak_live = 0
	StageHazard.audit_peak_coverage = 0.0
	StageHazard.audit_poison_ticks = 0
	StageHazard.audit_poison_capped = 0
	if is_instance_valid(arena):
		var hazard_director = load("res://game/map/ArenaHazardDirector.gd").new()
		hazard_director.arena = arena
		arena.add_child(hazard_director)
	if DemoConfig.ENCOUNTERS[target_stage].has("boss"):
		var point = boss_spawn_point(DemoConfig.ENCOUNTERS[target_stage].boss)
		if point == Vector2.INF:
			# spawn_near() returns this sentinel when no validated point exists.
			# Spawning anyway used to place the boss at an infinite coordinate,
			# which the player sees as a monster stuck outside the map wall.
			# Defer instead: the encounter keeps running and retries next tick.
			_boss_pending = DemoConfig.ENCOUNTERS[target_stage].boss
			M5Content.audit_boss_deferred += 1
			push_warning("[spawn] no legal boss spawn point for stage %d; deferring" % target_stage)
			return true
		var boss = M5Content.spawn(DemoConfig.ENCOUNTERS[target_stage].boss,monster_root,point)
		LevelServer.set_boss(boss)
	return true

## Bosses are the largest actors, so their clearance is measured from the boss scene instead
## of being a fixed constant that only fits a small enemy. The ring is widened in stages: the
## authored 160-220 band is tried first, and only if the arena's own layout blocks it (R8's
## fractured core leaves a narrow annulus around the player) are the wider bands used. This
## replaces a single-ring failure that showed up as "the stage-40 boss did not appear".
const BOSS_RINGS := [Vector2(160,220),Vector2(220,320),Vector2(120,380)]

func boss_spawn_point(boss_id: String) -> Vector2:
	var radius = M5Content.radius_for(boss_id)
	for ring in BOSS_RINGS:
		var point = spawn_near(Utils.player.global_position,ring.x,ring.y,radius)
		if point != Vector2.INF: return point
	return Vector2.INF

## A deferred boss (see depart()) is retried here once a validated point exists,
## instead of being created at an unvalidated coordinate.
var _boss_pending := ""

func _process(_delta: float) -> void:
	if _boss_pending == "" or LevelServer.state != "COMBAT": return
	if not is_instance_valid(Utils.player): return
	M5Content.audit_boss_retry += 1
	var point = boss_spawn_point(_boss_pending)
	if point == Vector2.INF: return
	var boss = M5Content.spawn(_boss_pending,monster_root,point)
	if boss == null: return
	LevelServer.set_boss(boss)
	_boss_pending = ""

func clear_practice():
	if LevelServer.state != "CAMP": return
	Demo.stop_attacks()
	for enemy in get_tree().get_nodes_in_group("monsters"):
		if enemy.training: enemy.queue_free()
	for effect in get_tree().get_nodes_in_group("combat_transient"): effect.queue_free()

func practice(count = 3):
	if LevelServer.state != "CAMP": return
	clear_practice()
	for offset in [Vector2(70,0),Vector2(85,18),Vector2(90,-18)].slice(0,clampi(count,1,3)):
		var dummy = monster_pre.instantiate()
		dummy.training = true
		dummy.global_position = $PositionHome.global_position+offset
		dummy.HP = 1000
		monster_root.add_child(dummy)
		var label = Label.new()
		label.text = "练枪靶"
		label.add_theme_font_size_override("font_size",6)
		label.position = Vector2(-12,-25)
		dummy.add_child(label)

func spawn_near(center: Vector2, minimum: float, maximum: float, radius := -1.0) -> Vector2:
	if radius <= 0.0: radius = M5Content.default_radius()
	if is_instance_valid(arena): return arena.spawn_near(center,minimum,maximum,-1,radius)
	if not nav_ready:
		M5Content.audit_deferred += 1
		return Vector2.INF
	var offset = randi()%walkable.size()
	for attempt in walkable.size():
		var cell = walkable[(offset+attempt)%walkable.size()]
		var point = navigation.get_point_position(cell)
		M5Content.audit_candidates += 1
		if point.distance_to(center) < minimum or point.distance_to(center) > maximum:
			M5Content.audit_rejected += 1; continue
		if point.distance_to(Utils.player.global_position) < 50:
			M5Content.audit_rejected += 1; continue
		var dest = nav_cell(Utils.player.global_position)
		if navigation.is_in_boundsv(dest) and not navigation.is_point_solid(dest) and navigation.get_id_path(cell,dest).size() > 1: return point
		M5Content.audit_rejected += 1
	M5Content.audit_deferred += 1
	return Vector2.INF

var arena
func prepare_region(id: String):
	if is_instance_valid(arena): arena.queue_free(); arena = null
	if id == "R1": Utils.player.global_position = portal_lv1.global_position+Vector2(0,35); return
	arena = load("res://game/map/CombatArena.gd").new(); arena.region_id = id; arena.position = Vector2(10000+int(id.substr(1))*1000,-6000); add_child(arena)
	Utils.player.global_position = arena.global_position
