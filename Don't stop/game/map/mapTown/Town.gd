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
	return random_point

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
	var point = spawn_point()
	if point == Vector2.INF: return
	var role = LevelServer.horde_role if LevelServer.horde_active else ("E02" if LevelServer.rush_active else config.roles[LevelServer.spawn_index % config.roles.size()])
	# Rhythm controls arrival timing, never replaces a mixed roster with one role for 7-15 seconds.
	LevelServer.spawn_index += 1
	var ins = M5Content.spawn(role,monster_root,point)
	if config.rhythm == "精英" and LevelServer.level_info.time >= 30 and not LevelServer.elite_spawned:
		LevelServer.elite_spawned = true; ins.is_elite = true; ins.HP *= 1.5
		var marker = Label.new(); marker.text = "精英"; marker.add_theme_font_size_override("font_size",7); marker.position = Vector2(-10,-32); ins.add_child(marker)

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
			query.transform = Transform2D(0,point)
			var ground = $TileMap3.get_cell_source_id(0,$TileMap3.local_to_map(point)) != -1
			var hits = space.intersect_shape(query,1)
			if ground: ground_count += 1
			if not hits.is_empty(): collision_count += 1
			var solid = not ground or not hits.is_empty()
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

func spawn_point() -> Vector2:
	if is_instance_valid(arena):
		var sides = M5Content.REGIONS[arena.region_id].sides
		var side=LevelServer.horde_side if LevelServer.horde_active else (LevelServer.rush_side if LevelServer.rush_active else LevelServer.spawn_index%sides.size())
		return arena.spawn_near(Utils.player.global_position,145,280,sides[side])
	if not nav_ready or walkable.is_empty(): return Vector2.INF
	var player_cell = nav_cell(Utils.player.global_position)
	if not navigation.is_in_boundsv(player_cell) or navigation.is_point_solid(player_cell): return Vector2.INF
	var offset = randi()%walkable.size()
	for attempt in walkable.size():
		var cell = walkable[(offset+attempt)%walkable.size()]
		var point = navigation.get_point_position(cell)
		var distance = point.distance_to(Utils.player.global_position)
		if distance < 145 or distance > 280: continue
		if navigation.get_id_path(cell,player_cell).size() > 1: return point
	return Vector2.INF

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
	if DemoConfig.ENCOUNTERS[target_stage].has("boss"):
		# Bosses are the largest actors, so they need a larger clearance than the
		# default the wave spawner uses.
		var point = spawn_near(Utils.player.global_position,160,220,12.0)
		if point == Vector2.INF:
			# spawn_near() returns this sentinel when no validated point exists.
			# Spawning anyway used to place the boss at an infinite coordinate,
			# which the player sees as a monster stuck outside the map wall.
			# Defer instead: the encounter keeps running and retries next tick.
			_boss_pending = DemoConfig.ENCOUNTERS[target_stage].boss
			push_warning("[spawn] no legal boss spawn point for stage %d; deferring" % target_stage)
			return true
		var boss = M5Content.spawn(DemoConfig.ENCOUNTERS[target_stage].boss,monster_root,point)
		LevelServer.boss_instance = boss.get_instance_id()
	return true

## A deferred boss (see depart()) is retried here once a validated point exists,
## instead of being created at an unvalidated coordinate.
var _boss_pending := ""

func _process(_delta: float) -> void:
	if _boss_pending == "" or LevelServer.state != "COMBAT": return
	if not is_instance_valid(Utils.player): return
	var point = spawn_near(Utils.player.global_position,160,220)
	if point == Vector2.INF: return
	var boss = M5Content.spawn(_boss_pending,monster_root,point)
	if boss == null: return
	LevelServer.boss_instance = boss.get_instance_id()
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

func spawn_near(center: Vector2, minimum: float, maximum: float, radius := 7.0) -> Vector2:
	if is_instance_valid(arena): return arena.spawn_near(center,minimum,maximum,-1,radius)
	if not nav_ready: return Vector2.INF
	var offset = randi()%walkable.size()
	for attempt in walkable.size():
		var cell = walkable[(offset+attempt)%walkable.size()]
		var point = navigation.get_point_position(cell)
		if point.distance_to(center) < minimum or point.distance_to(center) > maximum: continue
		if point.distance_to(Utils.player.global_position) < 50: continue
		var dest = nav_cell(Utils.player.global_position)
		if navigation.is_in_boundsv(dest) and not navigation.is_point_solid(dest) and navigation.get_id_path(cell,dest).size() > 1: return point
	return Vector2.INF

var arena
func prepare_region(id: String):
	if is_instance_valid(arena): arena.queue_free(); arena = null
	if id == "R1": Utils.player.global_position = portal_lv1.global_position+Vector2(0,35); return
	arena = load("res://game/map/CombatArena.gd").new(); arena.region_id = id; arena.position = Vector2(10000+int(id.substr(1))*1000,-6000); add_child(arena)
	Utils.player.global_position = arena.global_position
