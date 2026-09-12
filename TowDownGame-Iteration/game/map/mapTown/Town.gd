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

func _ready():
	LevelServer.town = self
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
	if LevelServer.state == "CAMP" and Utils.player.gun != null: LevelServer.roundStart()

func onTimeTick(timeout) -> void:
	if Utils.player.is_dead == false:
		$CanvasLayer/timeout.text =tr("REMAINING TIME") + str(timeout)

#回合开始
func onRoundStart():
	Utils.showToast("START_TIP",2)
	$CanvasLayer/timeout.visible = true
	$CanvasLayer/level.visible = true
	$CanvasLayer/level.text = tr("DIFFICULTY LEVEL") + " " + str(LevelServer.level)

#回合结束
func onRoundEnd():
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
func _on_portal_move_in(next_area):
	if Utils.player.gun == null:
		Utils.showToast("PLEASE PURCHASE A WEAPON FIRST")
	else:
		Utils.player.global_position = next_area.global_position

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
	if active >= config.cap: return
	var point = spawn_point()
	if point == Vector2.INF: return
	var role = config.roles[LevelServer.spawn_index % config.roles.size()]
	LevelServer.spawn_index += 1
	var ins = monster_pre.instantiate()
	if role != "E01":
		ins.set_script(load("res://game/monster/DemoEnemy.gd"))
		ins.role = role
	ins.global_position = point
	ins.setData({"speed":90,"hp":2,"hurt":1})
	ins.setDeathCallBack(onMonsterDeath)
	monster_root.add_child(ins)

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
	if not nav_ready or Combat.clear_line(from,to): return to
	var a = nav_cell(from)
	var b = nav_cell(to)
	if not navigation.is_in_boundsv(a) or not navigation.is_in_boundsv(b): return from
	if navigation.is_point_solid(a) or navigation.is_point_solid(b): return to
	var path = navigation.get_point_path(a,b)
	return path[1] if path.size() > 1 else from

func spawn_point() -> Vector2:
	if not nav_ready or walkable.is_empty(): return Vector2.INF
	var player_cell = nav_cell(Utils.player.global_position)
	if not navigation.is_in_boundsv(player_cell) or navigation.is_point_solid(player_cell): return Vector2.INF
	for attempt in 32:
		var cell = walkable.pick_random()
		var point = navigation.get_point_position(cell)
		var distance = point.distance_to(Utils.player.global_position)
		if distance < 145 or distance > 280: continue
		if navigation.get_id_path(cell,player_cell).size() > 1: return point
	return Vector2.INF

func depart(stage: int, is_trial: bool) -> bool:
	if LevelServer.state != "CAMP" or Utils.player.gun == null: return false
	Demo.selected_stage = stage
	Demo.trial = is_trial
	Demo.save_camp()
	Utils.player.global_position = portal_lv1.global_position + Vector2(0,35)
	return LevelServer.roundStart()

func practice():
	if LevelServer.state != "CAMP": return
	for enemy in get_tree().get_nodes_in_group("monsters"):
		if enemy.training: return
	for offset in [Vector2(70,0),Vector2(85,18),Vector2(90,-18)]:
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
