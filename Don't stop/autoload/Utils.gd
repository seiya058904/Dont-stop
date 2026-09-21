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

var temp_am_list = []

signal onGameStart()

# --- Web boot handshake -----------------------------------------------------
# The browser shell (web/loader.html) must not reveal the game until the title
# menu is really up AND the pre-warm pass has finished. Both are reported here
# as explicit stages so the shell never treats the engine's startGame() promise
# as proof that the game is ready.
var _web_boot_menu := false
var _web_boot_warmup := false
var _web_boot_reported := false
var _web_boot_menu_ms := 0
var _web_boot_warmup_ms := 0

# One-shot startup timeline. It is active only until ten seconds after the
# first real menu frame, so normal gameplay pays no per-frame instrumentation.
var _startup_trace_active := true
var _startup_origin_ms := 0
var _startup_last_frame_ms := -1
var _startup_menu_visible_ms := -1
var _startup_menu_deadline_ms := -1
var _startup_stages: Dictionary = {}
var _startup_all_gaps: Array = []
var _startup_menu_gaps: Array = []
var _startup_long_gaps: Array = []

func _ready() -> void:
	TranslationServer.set_locale("zh_CN")
	_startup_origin_ms = Time.get_ticks_msec()
	_startup_last_frame_ms = _startup_origin_ms
	startup_mark("utils-ready")
	print("[boot-probe] utils_ready t=%d" % Time.get_ticks_msec())

func _process(_delta: float) -> void:
	if not _startup_trace_active:
		return
	var now := Time.get_ticks_msec()
	if _startup_last_frame_ms >= 0:
		var gap := now - _startup_last_frame_ms
		_startup_all_gaps.append(gap)
		if gap > 50:
			_startup_long_gaps.append({"t_ms":now - _startup_origin_ms,"gap_ms":gap})
		if _startup_menu_visible_ms >= 0 and now <= _startup_menu_deadline_ms:
			_startup_menu_gaps.append(gap)
	_startup_last_frame_ms = now
	if (_startup_menu_deadline_ms >= 0 and now >= _startup_menu_deadline_ms) or now - _startup_origin_ms >= 120000:
		_finish_startup_trace()

func startup_mark(stage: String) -> void:
	if not _startup_trace_active or _startup_stages.has(stage):
		return
	var now := Time.get_ticks_msec()
	_startup_stages[stage] = {"t_ms":now,"since_utils_ms":now - _startup_origin_ms,
		"process_frame":Engine.get_process_frames()}
	if stage == "menu-first-visible" and _startup_menu_visible_ms < 0:
		_startup_menu_visible_ms = now
		_startup_menu_deadline_ms = now + 10000
	print("[startup] stage=%s t=%d since_utils=%d frame=%d" % [stage,now,now - _startup_origin_ms,Engine.get_process_frames()])

func startup_mark_once(stage: String) -> void:
	startup_mark(stage)

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * fraction) - 1,0,sorted.size() - 1)
	return float(sorted[index])

func _finish_startup_trace() -> void:
	if not _startup_trace_active:
		return
	_startup_trace_active = false
	print("[startup-summary] %s" % JSON.stringify({
		"stages":_startup_stages,
		"all_frame_gaps":{"count":_startup_all_gaps.size(),"max_ms":(_startup_all_gaps.max() if not _startup_all_gaps.is_empty() else -1),"over50":_startup_all_gaps.filter(func(v): return v > 50).size()},
		"menu_10s":{"samples":_startup_menu_gaps.size(),"p95_ms":_percentile(_startup_menu_gaps,0.95),"p99_ms":_percentile(_startup_menu_gaps,0.99),"max_ms":(_startup_menu_gaps.max() if not _startup_menu_gaps.is_empty() else -1),"over50":_startup_menu_gaps.filter(func(v): return v > 50).size(),"over100":_startup_menu_gaps.filter(func(v): return v > 100).size(),"over250":_startup_menu_gaps.filter(func(v): return v > 250).size(),"over1000":_startup_menu_gaps.filter(func(v): return v > 1000).size()},
		"long_gaps":_startup_long_gaps
	}))

func _notification(what: int) -> void:
	if not OS.has_feature("web"): return
	# Browser/tab lost focus: release held combat input so nothing stays stuck,
	# and pause so the player does not come back to a firing gun.
	# Deliberately NOT suppressed for the E2E driver flag: the focus-loss
	# contract has to be exercised exactly as it ships.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.action_release("shoot")
		for action in ["up", "down", "left", "right", "dash", "reload"]:
			Input.action_release(action)
		if is_game_start and is_gameplay_mouse_mode() and Demo.pause_stack.is_empty():
			Demo.open_panel()

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("web"): return
	# Esc opens the pause panel. The browser no longer drops a pointer lock for
	# us (there is no pointer lock), so the pause key has to be handled here.
	# When a panel is already on top it consumes ui_cancel itself and this branch
	# is skipped by the pause_stack guard.
	if is_game_start and Demo.pause_stack.is_empty() and event.is_action_pressed("ui_cancel"):
		Demo.open_panel()
		get_viewport().set_input_as_handled()

func set_gameplay_mouse_mode() -> void:
	# Web gameplay uses an ordinary, un-captured pointer: the aim is the real
	# absolute cursor position, so the player never has to press Esc (or click a
	# second "start" button) to be able to aim. The OS arrow is hidden in favour
	# of the product crosshair, which is the same contract Windows uses with
	# MOUSE_MODE_CONFINED_HIDDEN. Windows input is untouched.
	if OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func is_gameplay_mouse_mode() -> bool:
	if OS.has_feature("web"):
		return Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
	return Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN

## Unified gameplay aim provider.
## Both platforms use the engine's absolute viewport mouse position: the viewport
## transform already folds in the canvas CSS size, window stretch/aspect (black
## bars), page offset, device pixel ratio and the canvas_items scale, so the
## conversion to world space happens exactly once, in get_aim_world_position().
## aim_override is a TEST-ONLY hook: a headless fixture cannot move the OS cursor,
## and the root viewport mouse ignores synthetic input events entirely (measured),
## so a benchmark whose weapon re-derives its direction from the mouse in _shoot()
## cannot be aimed without it. It is gated behind Demo.test_mode, so even a stray
## assignment can never move the aim in a production launch; null (the shipped
## state) keeps the behaviour below in every mode.
var aim_override: Variant = null
func get_aim_viewport_position() -> Vector2:
	if Demo.test_mode and aim_override != null: return aim_override
	return get_viewport().get_mouse_position()

func get_aim_world_position() -> Vector2:
	var vport := get_viewport()
	return vport.get_canvas_transform().affine_inverse() * get_aim_viewport_position()

## The shell handshake. web/loader.html exposes exactly these two functions on
## window.__dontStop, and this file is the only caller, so the names live here
## once and are asserted by tools/web-aim-e2e.js: a mismatch used to mean the
## shell only revealed itself through its 20 s fallback, which looked like a
## successful start until the E2E started checking *how* it was revealed.
const WEB_SHELL_HOOKS := {
	"ready": "ready",
	"failed": "failed",
	# Stage progress. The shell used to remove its cover on a fixed 20 s timer when
	# no notice arrived; on the deployed site the notice was measured at 20923 ms,
	# so the timer - not the game - decided what the player saw. The shell now uses
	# these marks to tell "slow" from "stalled" and never reveals on a timer.
	"stage": "stage",
}

## Reports one launch stage to the browser shell. No-op outside Web builds.
func notify_web_boot_stage(stage: String) -> void:
	if not OS.has_feature("web"): return
	print("[boot] stage %s t=%d" % [stage, Time.get_ticks_msec()])
	_web_call_shell_arg(WEB_SHELL_HOOKS.stage, stage)

## Called by ui/MainUI.gd once the title menu is really on screen.
func notify_web_boot_menu_ready() -> void:
	_web_boot_menu = true
	_web_boot_menu_ms = Time.get_ticks_msec()
	print("[boot] title menu drawn t=%d" % _web_boot_menu_ms)
	notify_web_boot_stage("menu")
	_web_report_boot_ready()

## Called by autoload/Warmup.gd when the pre-warm pass has completed (or was skipped).
func notify_web_boot_warmup_done() -> void:
	_web_boot_warmup = true
	_web_boot_warmup_ms = Time.get_ticks_msec()
	notify_web_boot_stage("warmup-done")
	_web_report_boot_ready()

func _web_report_boot_ready() -> void:
	if not OS.has_feature("web") or _web_boot_reported: return
	# The menu can be built while the autoload is still paying first-use costs on the
	# browser's single thread. The shell must stay in its real loading state until
	# both sides of that hand-off have completed; otherwise it reveals a menu and
	# immediately freezes again while the warm-up pass finishes behind it.
	if not _web_boot_menu or not _web_boot_warmup: return
	_web_boot_reported = true
	# Two drawn frames: the shell must only drop its overlay once the menu has
	# actually been presented, not merely built.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	startup_mark("menu-first-visible")
	_web_call_shell(WEB_SHELL_HOOKS.ready)
	print("[boot] completion notice sent t=%d (menu=%d warmup=%s)" % [
		Time.get_ticks_msec(), _web_boot_menu_ms,
		str(_web_boot_warmup_ms) if _web_boot_warmup else "not-yet"])

## Fire-and-forget call into web/loader.html's __dontStop hook.
## The bridge is looked up by name because the JavaScriptBridge singleton only
## exists in web builds; naming it directly would not even parse on desktop.
## The eval is wrapped so a shell without the hook (or a blocked eval) can never
## take the game down - but it also cannot silently look like success: the shell
## only counts a reveal as "game-reported-ready" when this call arrives.
func _web_call_shell(hook: String) -> void:
	if not OS.has_feature("web"): return
	var bridge = Engine.get_singleton("JavaScriptBridge")
	if bridge == null: return
	bridge.call("eval",
		"try{if(window.__dontStop&&typeof window.__dontStop.%s==='function'){window.__dontStop.%s();}}catch(e){}"
		% [hook, hook], true)

## Same call, with one string argument (stage names). The argument is reduced to
## word characters before it reaches the eval, so a caller cannot inject script
## through a stage name even if one is ever built from data.
func _web_call_shell_arg(hook: String, arg: String) -> void:
	if not OS.has_feature("web"): return
	var bridge = Engine.get_singleton("JavaScriptBridge")
	if bridge == null: return
	var safe := ""
	for index in arg.length():
		var c := arg[index]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" or c == "_":
			safe += c
	bridge.call("eval",
		"try{if(window.__dontStop&&typeof window.__dontStop.%s==='function'){window.__dontStop.%s(\"%s\");}}catch(e){}"
		% [hook, hook, safe], true)

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
	# B11.2 visual isolation (test-only): damage numbers are pure feedback - no damage, no state and
	# no gameplay timing flows through here, so switching them off isolates their cost exactly.
	if B11Probe.iso_labels: return
	if preload("res://ui/widgets/HitLabel.gd").live_count >= 90: return
	var ins = hitlabel.instantiate()
	ins.setNumber(num)
	traget.add_child(ins)

#伤害数字 加强版
func showHitLabelMore(num,traget:Node2D,position = Vector2.ZERO,color = Color.WHITE):
	# B11.2 visual isolation (test-only). See showHitLabel.
	if B11Probe.iso_labels: return
	if preload("res://ui/widgets/HitLabel.gd").live_count >= 90: return
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
