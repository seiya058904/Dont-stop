extends Node

signal changed
signal restored
var talents: Dictionary = {}
var purchases: Array = []
var next_instance = 1
var next_stage = 1
var selected_stage = 1
var trial = false
var kill_stacks = 0
var stack_time = 0.0
var blast_cooldown = 0.0
var heal_cooldown = 0.0
var pause_stack: Array = []
var loading = false
var save_blocked = false
var test_mode = false
var fire_released = true
var save_store = CampSaveStore.new()
var dirty = false
var save_result = {"success":true,"reason":""}
var save_dialog
var save_path = "user://camp-v1.json"
var ui
var ui_audio = AudioStreamPlayer.new()

func _ready():
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music","SFX","UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
	ui_audio.bus = "UI"
	ui_audio.stream = load("res://audio/bullet/GUNMech_Insert Clip_01.wav")
	add_child(ui_audio)
	apply_audio_settings()
	Utils.onGameStart.connect(_start)
	PlayerData.onPlayerLevelChange.connect(_level_changed)

func _start():
	TranslationServer.set_locale("zh_CN")
	var hud = Label.new()
	hud.set_script(load("res://ui/DemoHUD.gd"))
	Utils.canvasLayer.add_child(hud)
	apply_audio_settings()
	Utils.shake = ConfigUtils.getConfig("demo","shake") if ConfigUtils.getConfig("demo","shake") != null else 0.35
	Combat.reduced_flash = ConfigUtils.getConfig("demo","reduced_flash") == true
	if not test_mode: load_camp()
	refresh()

func set_volume(bus: String, value: float):
	var index = AudioServer.get_bus_index(bus)
	if index < 0: return
	AudioServer.set_bus_mute(index,value <= 0)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(value/100.0,0.0001)))

func apply_audio_settings():
	for bus in ["Master","Music","SFX","UI"]:
		var value = ConfigUtils.getConfig("demo_audio",bus)
		set_volume(bus,float(value) if value != null else 80.0)

func play_ui():
	ui_audio.play()

func rank(id: String) -> int:
	return int(talents.get(id,0))

func _level_changed(_level):
	if not loading: refresh()

func refresh():
	for gun in PlayerData.player_weapon_list.values():
		if gun.is_node_ready(): gun.updateGun()
	changed.emit()

func _process(delta):
	if not Input.is_action_pressed("shoot"): fire_released = true
	if get_tree().paused: return
	blast_cooldown = maxf(0,blast_cooldown-delta)
	heal_cooldown = maxf(0,heal_cooldown-delta)
	if stack_time > 0:
		stack_time -= delta
		if stack_time <= 0:
			kill_stacks = 0
			refresh()

func stop_attacks():
	fire_released = false
	for gun in PlayerData.player_weapon_list.values(): gun.cancel_actions()
	if is_instance_valid(Combat):
		for voice in Combat.audio_pool: voice.stop()
	for effect in get_tree().get_nodes_in_group("combat_transient"):
		for voice in effect.find_children("*","AudioStreamPlayer2D",true,false): voice.stop()

func push_pause(owner_node):
	if owner_node in pause_stack: return
	pause_stack.append(owner_node)
	stop_attacks()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func pop_pause(owner_node):
	pause_stack.erase(owner_node)
	get_tree().paused = not pause_stack.is_empty()
	if pause_stack.is_empty() and Utils.is_game_start:
		fire_released = false
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func top_pause(owner_node) -> bool:
	return not pause_stack.is_empty() and pause_stack.back() == owner_node

func try_purchase(kind: String, id: String, currency = "gold") -> Dictionary:
	var result = {"success":false,"reason":"无效商品或支付方式"}
	if LevelServer.state != "CAMP":
		result.reason = "战斗中仅查看配置；请返回营地购买，未扣款"
		return result
	if currency not in ["gold","points"]: return result
	var price = 0
	var obtained = null
	if kind == "weapon" and Utils.weapon_list.has(id) and currency == "gold":
		if PlayerData.player_weapon_list.has(int(id)):
			result.reason = "已拥有这把枪；未扣款"
			return result
		price = Utils.weapon_money_list[id]
		obtained = Utils.weapon_list[id].instantiate()
	elif kind == "attachment" and Utils.am_dict.has(id) and currency == "gold":
		obtained = Utils.am_dict[id].instantiate()
		price = obtained.money
	elif kind == "talent" and DemoConfig.TALENTS.has(id):
		if rank(id) >= DemoConfig.TALENTS[id].max:
			result.reason = "已满级；未扣款"
			return result
		price = DemoConfig.TALENT_GOLD_PRICE if currency == "gold" else 1
	elif kind == "legacy" and RewardServer.reward_list.has(id):
		obtained = RewardServer.reward_list[id].instantiate()
		if not RewardServer.can_add(obtained):
			obtained.free()
			result.reason = "已满级；未扣款"
			return result
		price = DemoConfig.TALENT_GOLD_PRICE if currency == "gold" else 1
	elif kind == "supply" and id in ["ammo","health"] and currency == "gold":
		price = 10
		if id == "health" and PlayerData.player_hp >= PlayerData.player_hp_max:
			result.reason = "生命已满；未扣款"
			return result
	else: return result
	if (PlayerData.gold if currency == "gold" else PlayerData.reward_point) < price:
		if obtained != null: obtained.free()
		result.reason = "余额不足；未扣款"
		return result
	match kind:
		"weapon":
			PlayerData.add_weapon(obtained)
			result.reason = "已购买「%s」· %d金币\n%s" % [tr(obtained.weapon_name), price, "已装备" if obtained.is_use else "已拥有但未装备；在配置页选枪"]
		"attachment":
			obtained.id = next_instance
			next_instance += 1
			PlayerData.add_attachment(obtained)
			result.instance_id = obtained.id
			result.reason = "已购买「%s」· %d金币 · 未装备\n已定位到新实例；确认属性后点击安装" % [tr(obtained.am_name),price]
		"talent":
			talents[id] = rank(id)+1
			result.reason = "%s：%d → %d / %d\n%s" % [DemoConfig.TALENTS[id].name, rank(id)-1,rank(id), DemoConfig.TALENTS[id].max,DemoConfig.TALENTS[id].info]
		"legacy":
			if not RewardServer.addReward(obtained): return result
			purchases.append(id)
			result.reason = "已获得原型奖励；详见当前配置"
		"supply":
			if id == "ammo": PlayerData.player_ammo += 300
			else: PlayerData.addPlayerHp(PlayerData.player_hp_max)
			result.reason = "补给完成 · 10金币"
	if currency == "gold": PlayerData.gold -= price
	else: PlayerData.reward_point -= price
	result.success = true
	result.charged_currency = currency
	result.charged_amount = price
	refresh()
	result.saved = save_camp().success
	if not result.saved: result.reason += "\n已购买但尚未保存；请重试保存（不会再次扣款）"
	return result

func replenish():
	if LevelServer.state != "CAMP": return
	PlayerData.gold = maxi(PlayerData.gold,DemoConfig.INITIAL_GOLD)
	PlayerData.reward_point = maxi(PlayerData.reward_point,DemoConfig.INITIAL_TALENT_POINTS)
	changed.emit()
	save_camp()

func on_kill(monster, context: Dictionary):
	if monster.training: return
	if rank("T10") > 0:
		kill_stacks = mini(5,kill_stacks+1)
		stack_time = 4.0
		refresh()
	if context.get("depth",0) != 0: return
	if rank("T24") > 0 and heal_cooldown <= 0:
		heal_cooldown = 0.5
		PlayerData.addPlayerHp(0.15 * rank("T24"))
	if rank("T16") > 0 and blast_cooldown <= 0:
		blast_cooldown = 0.4
		Combat.explosion(monster.global_position,32.0,2.0,context.get("gun"),1)

func snapshot() -> Dictionary:
	var weapons = []
	for gun in PlayerData.player_weapon_list.values(): weapons.append({"id":str(gun.weapon_id),"ammo":gun.bullets_count})
	var attachments = []
	for am in PlayerData.player_am_list.values(): attachments.append({"definition":str(am.am_id),"instance":am.id,"gun":str(am.gun.weapon_id) if is_instance_valid(am.gun) else ""})
	return {"schema_version":2,"build_profile":DemoConfig.PROFILE,"gold":PlayerData.gold,"points":PlayerData.reward_point,"ammo":PlayerData.player_ammo,"level":PlayerData.player_level,"exp":PlayerData.player_exp,"hp":PlayerData.player_hp,"hp_max":PlayerData.player_hp_max,"weapons":weapons,"attachments":attachments,"talents":talents,"legacy":purchases,"legacy_state":legacy_state(),"next_instance":next_instance,"next_stage":next_stage,"selected_stage":selected_stage,"equipped":str(Utils.player.gun.weapon_id) if is_instance_valid(Utils.player) and Utils.player.gun else ""}

func legacy_state() -> Dictionary:
	var result = {}
	if is_instance_valid(Utils.player):
		for reward in Utils.player.reward_root.get_children():
			if reward.id == 10: result["10"] = reward.kill_count
	return result

func save_camp() -> Dictionary:
	if loading or test_mode: return {"success":true,"skipped":true,"reason":"测试或恢复中，不写磁盘"}
	dirty = true
	if save_blocked:
		save_result = {"success":false,"reason":"原存档待处理；临时试玩不会覆盖"}
	elif LevelServer.state != "CAMP":
		save_result = {"success":false,"reason":"战斗尚未结算，回营后保存"}
	else:
		var data = snapshot()
		save_result = save_store.save(save_path,data) if valid_save(data) else {"success":false,"reason":"当前配置未通过完整校验"}
	if save_result.success: dirty = false
	changed.emit()
	return save_result

func load_camp() -> bool:
	if not FileAccess.file_exists(save_path): return false
	var parser = JSON.new()
	var parse_error = parser.parse(FileAccess.get_file_as_string(save_path))
	var parsed = parser.data if parse_error == OK else null
	if not valid_save(parsed):
		save_blocked = true
		save_result = {"success":false,"reason":"存档损坏，原文保持；当前为临时试玩"}
		if not test_mode: show_save_dialog.call_deferred(true)
		return false
	var data = CampSnapshot.normalize(parsed)
	# Validation has completed. From here, restore the entire graph before any recalc.
	loading = true
	stop_attacks()
	Utils.player.gun = null
	for am in PlayerData.player_am_list.values(): am.free()
	PlayerData.player_am_list.clear()
	for gun in PlayerData.player_weapon_list.values(): gun.free()
	PlayerData.player_weapon_list.clear()
	for reward in Utils.player.reward_root.get_children(): reward.free()
	Utils.player.SPEED = 100 * PlayerData.player_speed
	talents = data.talents.duplicate()
	PlayerData.player_level = int(data.level)
	PlayerData.player_exp = data.exp
	for w in data.weapons:
		PlayerData.add_weapon(Utils.weapon_list[w.id].instantiate())
	for a in data.attachments:
		var am = Utils.am_dict[a.definition].instantiate()
		am.id = int(a.instance)
		PlayerData.add_attachment(am)
		if a.gun != "":
			var gun = PlayerData.player_weapon_list[int(a.gun)]
			gun.attachments_dict[am.am_type] = am
			am.reparent(gun.attachments_node)
			am.gun = gun
	purchases = data.legacy.duplicate()
	for id in purchases:
		var reward = RewardServer.reward_list[id].instantiate()
		if reward.only_start: reward.free()
		else: RewardServer.addReward(reward)
	for reward in Utils.player.reward_root.get_children():
		if reward.id == 10: reward.kill_count = int(data.legacy_state.get("10",0))
	next_instance = int(data.next_instance)
	next_stage = int(data.next_stage)
	selected_stage = int(data.selected_stage)
	trial = false
	kill_stacks = 0; stack_time = 0
	for gun in PlayerData.player_weapon_list.values(): gun.bullets_count = 0
	loading = false
	# One complete configuration calculation; intermediate ammo is never restored.
	refresh()
	for w in data.weapons: PlayerData.player_weapon_list[int(w.id)].bullets_count = int(w.ammo)
	PlayerData.player_ammo = int(data.ammo)
	PlayerData.player_hp_max = data.hp_max
	PlayerData.player_hp = data.hp
	Utils.player.is_dead = data.hp <= 0
	PlayerData.gold = int(data.gold)
	PlayerData.reward_point = int(data.points)
	loading = true
	if data.equipped != "": Utils.player.changeWeapon(int(data.equipped))
	loading = false
	save_blocked = false; dirty = false
	save_result = {"success":true,"reason":"已恢复"}
	restored.emit()
	changed.emit()
	return true

func valid_save(data) -> bool:
	return CampSnapshot.validate(data)

func show_save_dialog(recovery = false, quitting = false):
	if is_instance_valid(save_dialog):
		if not quitting or save_dialog.quitting: return
		# A close request must also offer cancel/discard while recovery is open.
		save_dialog.queue_free()
		save_dialog = null
	save_dialog = load("res://ui/SaveDialog.gd").new()
	save_dialog.recovery = recovery
	save_dialog.quitting = quitting
	Utils.canvasLayer.add_child(save_dialog)

func export_bad_save() -> String:
	var destination = save_path+".invalid-"+str(Time.get_ticks_usec())+".json"
	return ProjectSettings.globalize_path(destination) if DirAccess.copy_absolute(save_path,destination) == OK else "导出失败；原文件未改动"

func create_new_save() -> bool:
	var exported = export_bad_save()
	if exported.begins_with("导出失败"): return false
	var fresh = {"schema_version":2,"gold":DemoConfig.INITIAL_GOLD,"points":DemoConfig.INITIAL_TALENT_POINTS,"ammo":100,"level":1,"exp":0,"hp":5,"hp_max":5,"weapons":[],"attachments":[],"talents":{},"legacy":[],"legacy_state":{},"next_instance":1,"next_stage":1,"selected_stage":1,"equipped":""}
	var result = save_store.save(save_path,fresh)
	if not result.success: return false
	return load_camp()

func open_panel():
	if is_instance_valid(ui): return
	ui = Control.new()
	ui.set_script(load("res://ui/CampPanel.gd"))
	Utils.canvasLayer.add_child(ui)

func open_settings():
	var settings = Control.new()
	settings.set_script(load("res://ui/DemoSettings.gd"))
	Utils.canvasLayer.add_child(settings)
	Demo.push_pause(settings)

func quit_game():
	stop_attacks()
	if Utils.is_game_start and not save_camp().success:
		show_save_dialog(save_blocked,true)
		return
	finish_quit()

func finish_quit():
	# Release the custom cursor texture before the renderer shuts down.
	Input.set_custom_mouse_cursor(null)
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for node in get_tree().root.find_children("*",type,true,false): node.stop()
	await get_tree().create_timer(0.1,true).timeout
	get_tree().quit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST: quit_game()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Utils.is_game_start and LevelServer.state == "COMBAT" and pause_stack.is_empty():
		open_panel()
