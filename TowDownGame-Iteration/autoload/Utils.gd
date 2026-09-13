extends Node

var shop_pre = load("res://ui/CampPanel.tscn")

enum STATE_TYPE {
	STUN #眩晕
}

enum GUN_TYPE { #枪械类型
	ASSAULT_RIFLES = 1 << 0, #突击步枪
	SUBMACHINE_GUNSRELOAD = 1 << 1, #冲锋枪
	MACHINE_GUNS = 1 << 2, #机枪
	SNIPER_RIFLES = 1 << 3, #狙击步枪
	SHOTGUNS = 1 << 4, #霰弹枪
	LASER_WEAPONS = 1 << 5, #激光武器
}

enum GUN_CHANGE_TYPE { #切枪类型
	CHANGE, #切换枪械
	RELOAD #切换子弹
}

enum ATTACHMENTS_TYPE { #配件类型
	WEAPON_OPTICS, #瞄准镜
	WEAPON_MUZZLE, #枪口
	WEAPON_BARREL, #枪口
	WEAPON_UNDERBARREL, #枪口
	WEAPON_AMMUNITION, #枪口
	WEAPON_STOCK, #枪口
	WEAPON_TACTICAL, #枪口
	WEAPON_PERKS, #枪口
}

var weapon_list = {
	"121" = load("res://game/guns/W21.tscn"),
	"122" = load("res://game/guns/W22.tscn"),
	"124" = load("res://game/guns/W24.tscn"),

	"111" = load("res://game/guns/W11.tscn"),
	"113" = load("res://game/guns/W13.tscn"),
	"115" = load("res://game/guns/W15.tscn"),
	"116" = load("res://game/guns/W16.tscn"),

	"117" = load("res://game/guns/W17.tscn"),
	"118" = load("res://game/guns/W18.tscn"),
	"119" = load("res://game/guns/W19.tscn"),
	"120" = load("res://game/guns/W20.tscn"),

	"112" =  preload("res://game/guns/ArcCaster.tscn"),
	"114" =  preload("res://game/guns/PlasmaOrb.tscn"),
	"123" =  preload("res://game/guns/BurstCarbine.tscn"),
	"0" = preload("res://game/guns/GunSprite.tscn"),
	"1" = preload("res://game/guns/ShotgunBlaster.tscn"),
	"2" = preload("res://game/guns/Sniper.tscn"),
	"3" = preload("res://game/guns/BabyZapZap.tscn"),
	"4" = preload("res://game/guns/AlienRifle.tscn"),
	"5" = preload("res://game/guns/EmpireShotgun.tscn"),
	"6" = preload("res://game/guns/BoomBoi.tscn"),
	"7" = preload("res://game/guns/AlienMachine.tscn"),
	"8" = preload("res://game/guns/RebalShotgun.tscn"),
	"9" = preload("res://game/guns/Uzi.tscn")
}

var am_dict = {
	"111" = load("res://game/attachments/A111.tscn"),
	"113" = load("res://game/attachments/A113.tscn"),
	"115" = load("res://game/attachments/A115.tscn"),
	"116" = load("res://game/attachments/A116.tscn"),
	"118" = load("res://game/attachments/A118.tscn"),
	"119" = load("res://game/attachments/A119.tscn"),
	"120" = load("res://game/attachments/A120.tscn"),
	"123" = load("res://game/attachments/A123.tscn"),
	"124" = load("res://game/attachments/A124.tscn"),

	"110" =  preload("res://game/attachments/A110.tscn"),
	"112" =  preload("res://game/attachments/A112.tscn"),
	"114" =  preload("res://game/attachments/A114.tscn"),
	"117" =  preload("res://game/attachments/A117.tscn"),
	"121" =  preload("res://game/attachments/A121.tscn"),
	"122" =  preload("res://game/attachments/A122.tscn"),

	"0" = preload("res://game/attachments/QuickdrawMagazine.tscn"),
	"1" = preload("res://game/attachments/UniversalExtendedMagazines.tscn"),
	"2" = preload("res://game/attachments/ExtendedRifleMagazine.tscn"),
	"3" = preload("res://game/attachments/QuickExpansionMagazine.tscn"),
	"5" = preload("res://game/attachments/ShotgunShellPouch.tscn"),
	"6" = preload("res://game/attachments/MachineGunMagazine.tscn"),
	"7" = preload("res://game/attachments/SubmachineGunMagazine.tscn"),
	"8" = preload("res://game/attachments/SuperUniversalMagazine.tscn"),
	"9" = preload("res://game/attachments/GrenadeLauncher.tscn")
}

const weapon_money_list = WeaponCatalog.PRICES

const hitlabel = preload("res://ui/widgets/HitLabel.tscn")

var canvasLayer:CanvasLayer
var player:Player
var freeze_frame = false
var shake = 1.0 #振动幅度
var pause_state = false #暂停状态
var is_game_start = false #游戏是否开始

var is_inv_show = false #是否展示背包

var crosshair_position = Vector2.ZERO

# Web Pointer Lock aim state. The OS cursor is captured, so absolute mouse
# positions are frozen at the lock point; the real cursor movement only arrives
# as InputEventMouseMotion.relative. Gameplay aiming must go through
# get_aim_world_position() / get_aim_viewport_position(), never through
# get_global_mouse_position().
var web_aim_viewport_position: Vector2
var web_aim_sensitivity := 1.0
var _web_had_capture := false
var _web_capture_request_ms := -10000
# E2E harness flag (set via Utils.set() to avoid autoload parse cycles):
# driver-driven runs ignore OS focus-loss auto-pause, they manage pause
# explicitly through real ESC input.
var web_e2e_driver := false

var temp_am_list = []

signal onGameStart()

func _ready() -> void:
	TranslationServer.set_locale("zh_CN")
	if OS.has_feature("web"):
		web_aim_viewport_position = get_viewport().get_visible_rect().size / 2

func _input(event: InputEvent) -> void:
	if not OS.has_feature("web"): return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventMouseMotion:
		# Pointer Lock: only relative deltas describe real cursor movement.
		var vport := get_viewport()
		web_aim_viewport_position += (event as InputEventMouseMotion).relative * web_aim_sensitivity
		web_aim_viewport_position = web_aim_viewport_position.clamp(
			Vector2.ZERO, vport.get_visible_rect().size)

func _notification(what: int) -> void:
	if not OS.has_feature("web"): return
	# Browser/tab lost focus: release held combat input so nothing stays stuck,
	# and pause (Pointer Lock is dropped by the browser anyway).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if web_e2e_driver: return
		Input.action_release("shoot")
		for action in ["up", "down", "left", "right", "dash", "reload"]:
			Input.action_release(action)
		if is_game_start and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Demo.open_panel()

func _process(_delta: float) -> void:
	if not OS.has_feature("web"): return
	var gameplay = is_gameplay_mouse_mode()
	# Pointer Lock was lost (Esc / browser focus change): open the pause panel,
	# matching desktop behaviour where Esc opens the menu.
	# Grace window: right after a capture request (e.g. closing the pause panel)
	# the browser may take a moment (or reject during its post-ESC cooldown);
	# do not interpret that brief loss as "player pressed ESC" and re-pause.
	if is_game_start and _web_had_capture and not gameplay and Demo.pause_stack.is_empty() 			and Time.get_ticks_msec() - _web_capture_request_ms > 4000:
		_web_had_capture = false
		Demo.open_panel()
	if gameplay:
		_web_had_capture = true

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("web"): return
	if is_game_start and Demo.pause_stack.is_empty() and not is_gameplay_mouse_mode() \
			and event is InputEventMouseButton and event.pressed:
		# Re-request Pointer Lock after it was lost; the click provides the gesture.
		set_gameplay_mouse_mode()

func set_gameplay_mouse_mode() -> void:
	# Web browsers only support real capture (Pointer Lock), not confined mode.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if OS.has_feature("web") else Input.MOUSE_MODE_CONFINED_HIDDEN
	if OS.has_feature("web"):
		_web_capture_request_ms = Time.get_ticks_msec()

func is_gameplay_mouse_mode() -> bool:
	if OS.has_feature("web"):
		return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN

## Unified gameplay aim provider.
## Windows: native absolute mouse (unchanged behaviour).
## Web (Pointer Lock): virtual viewport cursor driven by relative mouse motion.
func get_aim_viewport_position() -> Vector2:
	var vport := get_viewport()
	if OS.has_feature("web") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return web_aim_viewport_position
	return vport.get_mouse_position()

func get_aim_world_position() -> Vector2:
	var vport := get_viewport()
	return vport.get_canvas_transform().affine_inverse() * get_aim_viewport_position()

func reloadTempAmList():
	temp_am_list.clear()
	var temp = am_dict.keys().duplicate()
	temp.shuffle()
	for i in 5:
		temp_am_list.append(temp[i])

func getTempAmList():
	if temp_am_list.is_empty():
		var temp = am_dict.keys().duplicate()
		temp.shuffle()
		for i in 5:
			temp_am_list.append(temp[i])
	return temp_am_list

func gameStart():
	is_game_start = true
	emit_signal("onGameStart")

#伤害数字
func showHitLabel(num,traget:Node2D):
	if get_tree().get_nodes_in_group("damage_labels").size() >= 90: return
	var ins = hitlabel.instantiate()
	ins.setNumber(num)
	traget.add_child(ins)

#伤害数字 加强版
func showHitLabelMore(num,traget:Node2D,position = Vector2.ZERO,color = Color.WHITE):
	if get_tree().get_nodes_in_group("damage_labels").size() >= 90: return
	var ins = hitlabel.instantiate()
	ins.setNumber(num)
	ins.position = position
	ins.setColor(color)
	traget.add_child(ins)

#获取配件类型名称
func getAttachmentsName(type:ATTACHMENTS_TYPE):
	match type:
		ATTACHMENTS_TYPE.WEAPON_OPTICS :return "WEAPON_OPTICS"
		ATTACHMENTS_TYPE.WEAPON_MUZZLE :return "WEAPON_MUZZLE"
		ATTACHMENTS_TYPE.WEAPON_BARREL :return "WEAPON_BARREL"
		ATTACHMENTS_TYPE.WEAPON_UNDERBARREL :return "WEAPON_UNDERBARREL"
		ATTACHMENTS_TYPE.WEAPON_AMMUNITION :return "WEAPON_AMMUNITION"
		ATTACHMENTS_TYPE.WEAPON_STOCK :return "WEAPON_STOCK"
		ATTACHMENTS_TYPE.WEAPON_TACTICAL :return "WEAPON_TACTICAL"
		ATTACHMENTS_TYPE.WEAPON_PERKS :return "WEAPON_PERKS"

#获取武器类型名称
func getWeaponName(type:GUN_TYPE):
	match type:
		GUN_TYPE.ASSAULT_RIFLES :return "ASSAULT_RIFLES"
		GUN_TYPE.SUBMACHINE_GUNSRELOAD :return "SUBMACHINE_GUNSRELOAD"
		GUN_TYPE.MACHINE_GUNS :return "MACHINE_GUNS"
		GUN_TYPE.SNIPER_RIFLES :return "SNIPER_RIFLES"
		GUN_TYPE.SHOTGUNS :return "SHOTGUNS"
		GUN_TYPE.LASER_WEAPONS :return "LASER_WEAPONS"

func freezeFrame(scale):
	#OS.delay_msec(50)
	#return
	if !freeze_frame && scale > 0:
		# 冻结帧
		pass
		#freeze_frame = true
		# 将时间比例设置为0.1
		#Engine.time_scale = scale

func showToast(msg,time = 1):
	if is_instance_valid(canvasLayer): canvasLayer.showToast(msg,time)

func crosshairChange(is_change):
	canvasLayer.crosshairChange(is_change)

func getShader(quality):
	match quality:
		0:""

#func _physics_process(delta):
#	if freeze_frame && Engine.get_physics_frames() % 2 == 0:
		# 暂停一帧
#		freeze_frame = false
		# 将时间比例设置为1
#		Engine.time_scale = 1
#		return
