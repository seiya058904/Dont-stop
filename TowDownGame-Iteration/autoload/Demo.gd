extends Node

signal changed
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
	Utils.onGameStart.connect(_start)

func _start():
	TranslationServer.set_locale("zh_CN")
	var hud = Label.new()
	hud.set_script(load("res://ui/DemoHUD.gd"))
	Utils.canvasLayer.add_child(hud)
	for bus in ["Master","Music","SFX","UI"]:
		var volume = ConfigUtils.getConfig("demo_audio",bus)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus),linear_to_db(maxf(float(volume)/100.0,0.0001)) if volume != null else linear_to_db(0.8))
	Utils.shake = ConfigUtils.getConfig("demo","shake") if ConfigUtils.getConfig("demo","shake") != null else 0.35
	Combat.reduced_flash = ConfigUtils.getConfig("demo","reduced_flash") == true
	if not test_mode: load_camp()
	refresh()

func play_ui():
	ui_audio.play()

func rank(id: String) -> int:
	return int(talents.get(id,0))

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
			result.reason = "已购买「%s」· %d金币 · 未装备\n在配件背包选择后点击安装" % [tr(obtained.am_name),price]
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
	save_camp()
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
	return {"schema_version":1,"build_profile":DemoConfig.PROFILE,"gold":PlayerData.gold,"points":PlayerData.reward_point,"ammo":PlayerData.player_ammo,"level":PlayerData.player_level,"exp":PlayerData.player_exp,"hp":PlayerData.player_hp,"hp_max":PlayerData.player_hp_max,"weapons":weapons,"attachments":attachments,"talents":talents,"legacy":purchases,"next_instance":next_instance,"next_stage":next_stage,"selected_stage":selected_stage,"equipped":str(Utils.player.gun.weapon_id) if is_instance_valid(Utils.player) and Utils.player.gun else ""}

func save_camp():
	if loading or test_mode or save_blocked or LevelServer.state != "CAMP": return
	var file = FileAccess.open(save_path+".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(snapshot(),"\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error == OK: DirAccess.rename_absolute(save_path+".tmp",save_path)

func load_camp():
	if not FileAccess.file_exists(save_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not valid_save(data):
		save_blocked = true
		DirAccess.copy_absolute(save_path,save_path+".invalid-"+str(Time.get_unix_time_from_system()))
		Utils.showToast("存档无法读取，原文件已保留；本次为临时试玩，未覆盖存档",6)
		return
	loading = true
	talents = data.talents
	PlayerData.player_level = int(data.level)
	PlayerData.player_exp = data.exp
	for w in data.weapons:
		if Utils.weapon_list.has(w.id) and not PlayerData.player_weapon_list.has(int(w.id)):
			var gun = Utils.weapon_list[w.id].instantiate()
			PlayerData.add_weapon(gun)
			gun.bullets_count = int(w.ammo)
	for a in data.attachments:
		if Utils.am_dict.has(a.definition):
			var am = Utils.am_dict[a.definition].instantiate()
			am.id = int(a.instance)
			PlayerData.add_attachment(am)
			if PlayerData.player_weapon_list.has(int(a.gun)) and a.gun != "": PlayerData.player_weapon_list[int(a.gun)].addAttachMent(am)
	purchases = data.get("legacy",[])
	for id in purchases:
		if RewardServer.reward_list.has(id): RewardServer.addReward(RewardServer.reward_list[id].instantiate())
	PlayerData.player_hp_max = data.hp_max
	PlayerData.player_hp = data.hp
	PlayerData.gold = int(data.gold)
	PlayerData.reward_point = int(data.points)
	PlayerData.player_ammo = int(data.ammo)
	next_instance = int(data.next_instance)
	next_stage = int(data.next_stage)
	selected_stage = int(data.selected_stage)
	if data.equipped != "": Utils.player.changeWeapon(int(data.equipped))
	loading = false

func valid_save(data) -> bool:
	if not data is Dictionary: return false
	for key in ["schema_version","gold","points","ammo","level","exp","hp","hp_max","weapons","attachments","talents","next_instance","next_stage","selected_stage","equipped"]:
		if not data.has(key): return false
	if data.schema_version != 1 or not data.weapons is Array or not data.attachments is Array or not data.talents is Dictionary: return false
	for key in ["gold","points","ammo","level","exp","hp","hp_max","next_instance","next_stage","selected_stage"]:
		if not (data[key] is float or data[key] is int) or not is_finite(float(data[key])) or data[key] < 0: return false
	if data.level < 1 or data.hp_max <= 0 or data.hp <= 0 or not DemoConfig.ENCOUNTERS.has(int(data.next_stage)) or not DemoConfig.ENCOUNTERS.has(int(data.selected_stage)): return false
	var instances = []
	var weapon_ids = []
	for w in data.weapons:
		if not w is Dictionary or not w.has_all(["id","ammo"]) or not w.id is String or w.id in weapon_ids: return false
		if not (w.ammo is float or w.ammo is int) or not is_finite(float(w.ammo)) or w.ammo < 0: return false
		weapon_ids.append(w.id)
	for a in data.attachments:
		if not a is Dictionary or not a.has_all(["definition","instance","gun"]): return false
		if not a.definition is String or not a.gun is String or not (a.instance is int or a.instance is float): return false
		if a.instance in instances or a.instance < 1 or a.instance >= data.next_instance: return false
		instances.append(a.instance)
	for id in data.talents:
		if not DemoConfig.TALENTS.has(id): return false
		var value = data.talents[id]
		if not (value is int or value is float) or not is_finite(float(value)) or value != int(value) or value < 0 or value > DemoConfig.TALENTS[id].max: return false
	if not data.equipped is String or (data.equipped != "" and data.equipped not in weapon_ids): return false

	return true

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
	save_camp()
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for node in get_tree().root.find_children("*",type,true,false): node.stop()
	await get_tree().create_timer(0.1,true).timeout
	get_tree().quit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST: quit_game()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Utils.is_game_start and LevelServer.state == "COMBAT" and pause_stack.is_empty():
		open_panel()
