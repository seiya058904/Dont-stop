extends Node

## Observes the REAL product launch: Boot.tscn -> main menu -> the real "继续" camp
## door -> a real round, with no test flag of any kind. Every sample reports both
## PlayerData and the live HP bar so "real HP" and "what the player sees" can never
## be confused again. Observation only: it presses the product's own buttons and
## reads state; it writes no HP, spawns nothing and grants nothing.

const FIXTURE_SAVE := "user://p0-flow-camp.json"
const OBSERVE_SECONDS := 50.0

var ui_button_presses := 0
var log_rows: Array = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("P0_FLOW headless is fine for this observation")
	# A first-time player: no save file at all, exactly the state the RC ships in.
	if FileAccess.file_exists(FIXTURE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_SAVE))
	Demo.save_path = FIXTURE_SAVE
	Demo.test_mode = false
	_run.call_deferred()

func _run() -> void:
	# 1. The real main menu.
	if not await _wait_for(func(): return Utils.canvasLayer != null and Utils.canvasLayer.get_node_or_null("MainUI") != null, 90.0):
		_finish("no main menu")
		return
	print("P0_FLOW step=menu")
	# 2. The product's own start button, pressed the way a player presses it.
	var start: Button = Utils.canvasLayer.get_node_or_null("MainUI/VBoxContainer/start")
	if start == null:
		print("P0_FLOW no start button; entries=%s" % _buttons(Utils.canvasLayer.get_node("MainUI")))
		_finish("no start button")
		return
	start.emit_signal("pressed")
	ui_button_presses += 1
	print("P0_FLOW step=start-pressed")

	# 3. The camp, and the product's own "继续：<stage>" door.
	if not await _wait_for(func(): return Demo.ui != null and LevelServer.state == "CAMP", 60.0):
		_finish("no camp")
		return
	print("P0_FLOW step=camp hp=%.3f hp_max=%.3f" % [PlayerData.player_hp,PlayerData.player_hp_max])
	# The camp opens on the weapon tab; the product's own "出发" tab exposes the door.
	var stage_tab := _find_button(Demo.ui, "出发")
	if stage_tab == null:
		print("P0_FLOW no 出发 tab; entries=%s" % _buttons(Demo.ui))
		_finish("no stage tab")
		return
	stage_tab.emit_signal("pressed")
	ui_button_presses += 1
	await wait_frames(4)
	var door := _find_button(Demo.ui, "继续")
	if door == null:
		print("P0_FLOW no 继续 door; entries=%s" % _buttons(Demo.ui))
		_finish("no camp door")
		return
	door.emit_signal("pressed")
	ui_button_presses += 1

	# 4. The round.
	if not await _wait_for(func(): return LevelServer.state == "COMBAT", 60.0):
		_finish("no combat")
		return
	print("P0_FLOW step=combat stage=%d trial=%s paused=%s" % [LevelServer.level,str(Demo.trial),str(get_tree().paused)])

	# 5. Nothing is pressed from here. Real monsters have to reach a player who does
	#    not move, exactly like the manual report.
	var ui = Utils.canvasLayer.get_node_or_null("GameUI")
	var bar: ProgressBar = ui.get_node_or_null("hpUI/ProgressBar") if ui != null else null
	print("P0_FLOW hud bar=%s" % ("missing" if bar == null else str(bar.get_path())))
	var clock := 0.0
	var next_sample := 0.0
	var attack_frames := 0
	var attacks_prev := 0
	while clock < OBSERVE_SECONDS and LevelServer.state == "COMBAT" and not Utils.player.is_dead:
		await get_tree().process_frame
		clock += get_process_delta_time()
		if clock < next_sample:
			continue
		next_sample = clock+1.0
		var monsters := get_tree().get_nodes_in_group("monsters")
		var live := monsters.filter(func(m): return not m.is_die and not m.training)
		var hurting := monsters.filter(func(m): return not m.is_die and not m.training and bool(m.is_atk))
		if not hurting.is_empty(): attack_frames += 1
		var hp: float = PlayerData.player_hp
		var bar_value: float = bar.value if bar != null else -1.0
		var pct: int = int(round(bar_value/bar.max_value*100.0)) if bar != null and bar.max_value > 0.0 else -1
		var row := {"t":"%.1f" % clock,"state":LevelServer.state,"hp":"%.3f" % hp,
			"hp_max":"%.1f" % PlayerData.player_hp_max,"bar":"%.3f" % bar_value,"pct":pct,
			"live":live.size(),"attacking":hurting.size(),"blocked":Utils.player.contact_blocked,
			"paused":get_tree().paused,"dead":Utils.player.is_dead}
		log_rows.append(row)
		print("P0_FLOW_TICK ",JSON.stringify(row))
	# 6. Keep watching past death so the final transition is visible too.
	var death_clock := 0.0
	while death_clock < 3.0:
		await get_tree().process_frame
		death_clock += get_process_delta_time()
	var summary := {"rows":log_rows.size(),"button_presses":ui_button_presses,
		"hp_min":_min_hp(),"hp_end":PlayerData.player_hp,"hp_max":PlayerData.player_hp_max,
		"dead":Utils.player.is_dead,"state":LevelServer.state,
		"observed_s":clock,"seconds_with_attacking_monsters":attack_frames}
	print("P0_FLOW ",JSON.stringify(summary))
	_finish("")

func _min_hp() -> float:
	var low := 1e9
	for row in log_rows: low = minf(low,float(row.hp))
	return low

func _finish(reason: String) -> void:
	if reason != "": print("P0_FLOW aborted: ",reason)
	await get_tree().process_frame
	get_tree().quit.call_deferred(0 if reason == "" and _min_hp() < 5.0 else 1)

func _wait_for(predicate: Callable, seconds: float) -> bool:
	var clock := 0.0
	while clock < seconds:
		await get_tree().process_frame
		clock += get_process_delta_time()
		if predicate.call(): return true
	return false

func wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _find_button(root: Node, prefix: String) -> Button:
	if root == null: return null
	for child in root.find_children("*","Button",true,false):
		if (child as Button).text.begins_with(prefix) and (child as Button).is_visible_in_tree():
			return child
	return null

func _buttons(root: Node) -> String:
	if root == null: return "none"
	var names: Array = []
	for child in root.find_children("*","Button",true,false):
		names.append((child as Button).text)
	return str(names)
