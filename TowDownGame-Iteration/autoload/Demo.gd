extends Node

signal changed
signal restored
var talents: Dictionary = {}
var purchases: Array = []
var owned_global_upgrades: Array = []
var grenade_cooldown = 0.0
var next_instance = 1
var campaign_complete = false
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
var talent_payments: Array = []
var reset_revision = 0
var applied_talent_hp = 0.0
var talent_cooldowns: Dictionary = {}
var ammo_kills = 0
var crowd_clock = 0.0
var crowd_active = false
var quitting_game = false

func reset_preview() -> Dictionary:
	var result = {"gold":0,"points":0,"unknown":0,"revision":reset_revision}
	var known = {}
	for payment in talent_payments:
		result[payment.currency] += payment.amount
		known[payment.id] = known.get(payment.id,0)+1
	for id in talents: result.unknown += maxi(0,rank(id)-known.get(id,0))
	return result

func reset_talents(revision: int) -> Dictionary:
	if LevelServer.state != "CAMP" or revision != reset_revision: return {"success":false,"reason":"配置已变化或不在营地，请重新查看退款预览"}
	var refund = reset_preview()
	if talents.is_empty(): return {"success":false,"reason":"当前无计划天赋可重置"}
	stop_attacks()
	reset_revision += 1
	talents.clear()
	talent_payments.clear()
	kill_stacks = 0; stack_time = 0
	ammo_kills = 0; crowd_active = false
	talent_cooldowns.clear()
	for target in get_tree().get_nodes_in_group("monsters"):
		target.burns.erase("T15")
		target.slows.erase("T17")
		target.refresh_slow()
	PlayerData.gold += refund.gold
	PlayerData.reward_point += refund.points
	refresh()
	var saved = save_camp()
	return {"success":true,"refund":refund,"saved":saved.success,"reason":"计划天赋已重置；返还%d金币/%d点。历史无凭据%d级未退款，原型历史来源保留。" % [refund.gold,refund.points,refund.unknown]}

func cooldown(id: String) -> float:
	return talent_cooldowns.get(id,0.0)

func ready_trigger(id: String) -> bool:
	if cooldown(id) > 0: return false
	talent_cooldowns[id] = DemoConfig.TALENTS[id].get("cooldown",0.0)
	return true

func shield_hit(amount: float) -> bool:
	return amount > 0 and rank("T19") > 0 and ready_trigger("T19")

func talent_status(id: String) -> String:
	if rank(id) == 0: return "当前未解锁"
	if id == "T16": return "冷却剩余 %.1f秒" % blast_cooldown
	if id == "T24": return "冷却剩余 %.1f秒" % heal_cooldown
	if id == "T22": return "当前生效" if crowd_active else "当前未满足：近距至少3敌"
	if id == "T13": return "当前枪生效" if Utils.player.gun and "straight" in Utils.player.gun.tags else "当前枪不兼容"
	if id == "T21": return "仅对精英生效；Boss不适用"
	if id == "T11": return "进度 %d / %d 次直接击杀" % [ammo_kills,DemoConfig.TALENTS.T11.kills]
	if id == "T12": return "首发已就绪" if Utils.player.gun and Utils.player.gun.first_round else "等待真实装填完成"
	if DemoConfig.TALENTS[id].has("cooldown"): return "冷却剩余 %.1f秒" % cooldown(id)
	return "已启用；按所列条件触发"

func _ready():
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(quit_game)
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
	var boss_hud = load("res://ui/BossHUD.gd").new()
	Utils.canvasLayer.add_child(boss_hud)
	apply_audio_settings()
	Utils.shake = ConfigUtils.getConfig("demo","shake") if ConfigUtils.getConfig("demo","shake") != null else 0.35
	Combat.reduced_flash = ConfigUtils.getConfig("demo","reduced_flash") == true
	if not test_mode:
		load_camp()
		# This build is a playtest: refill once at startup, not on each save/load.
		PlayerData.gold = maxi(PlayerData.gold,DemoConfig.INITIAL_GOLD)
		PlayerData.reward_point = maxi(PlayerData.reward_point,DemoConfig.INITIAL_TALENT_POINTS)
	refresh()
	if not test_mode and not save_blocked: save_camp()

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
	if not loading and is_instance_valid(Utils.player):
		var hp_bonus = DemoConfig.talent_value("T07",rank("T07"))
		var delta_hp = hp_bonus-applied_talent_hp
		applied_talent_hp = hp_bonus
		if delta_hp != 0:
			PlayerData.player_hp_max += delta_hp
			PlayerData.player_hp = minf(PlayerData.player_hp_max,PlayerData.player_hp+maxf(0,delta_hp))
		Utils.player.SPEED = EffectiveStats.player_values().speed
	for gun in PlayerData.player_weapon_list.values():
		if gun.is_node_ready(): gun.updateGun()
	changed.emit()

func _process(delta):
	if not Input.is_action_pressed("shoot"): fire_released = true
	if get_tree().paused: return
	grenade_cooldown = maxf(0,grenade_cooldown-delta)
	for id in talent_cooldowns: talent_cooldowns[id] = maxf(0,talent_cooldowns[id]-delta)
	crowd_clock -= delta
	if crowd_clock <= 0:
		crowd_clock = DemoConfig.TALENTS.T22.interval
		var nearby = 0
		if rank("T22") > 0 and is_instance_valid(Utils.player):
			for target in get_tree().get_nodes_in_group("monsters"):
				if not target.is_die and Utils.player.global_position.distance_to(target.global_position) <= DemoConfig.TALENTS.T22.radius: nearby += 1
		crowd_active = nearby >= DemoConfig.TALENTS.T22.count
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
		Utils.set_gameplay_mouse_mode()

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
		if id in owned_global_upgrades: return {"success":false,"reason":"强化已激活；未扣款"}
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
	elif kind == "supply" and id in ["ammo","mag5","mag10","mag25","health"] and currency == "gold":
		price = {"ammo":10,"mag5":10,"mag10":18,"mag25":40,"health":10}[id]
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
			result.reason = "已购买「%s」· %d金币\n%s" % [tr(obtained.weapon_name), price, "已装备" if obtained.is_use else "已拥有；在武器页选择装备"]
		"attachment":
			owned_global_upgrades.append(id)
			owned_global_upgrades.sort()
			result.reason = "「%s」已激活 · %d金币\n所有当前和未来武器自动生效" % [tr(obtained.am_name),price]
			obtained.free()
		"talent":
			talents[id] = rank(id)+1
			talent_payments.append({"id":id,"level":rank(id),"currency":currency,"amount":price})
			reset_revision += 1
			result.reason = "%s：%d → %d / %d\n%s" % [DemoConfig.TALENTS[id].name, rank(id)-1,rank(id), DemoConfig.TALENTS[id].max,DemoConfig.talent_info(id)]
		"legacy":
			if not RewardServer.addReward(obtained): return result
			purchases.append(id)
			result.reason = "已获得原型奖励；详见当前配置"
		"supply":
			if id != "health": PlayerData.reserve_magazines += {"ammo":5,"mag5":5,"mag10":10,"mag25":25}[id]
			else: PlayerData.addPlayerHp(PlayerData.player_hp_max)
			result.reason = "补给完成 · %d金币 · 备用%d弹匣" % [price,PlayerData.reserve_magazines]
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
	PlayerData.gold = maxi(PlayerData.gold,9999)
	PlayerData.reward_point = maxi(PlayerData.reward_point,9999)
	changed.emit()
	save_camp()

func on_kill(monster, context: Dictionary):
	if monster.training: return
	if rank("T10") > 0:
		kill_stacks = mini(DemoConfig.TALENTS.T10.stacks,kill_stacks+1)
		stack_time = DemoConfig.TALENTS.T10.seconds
		refresh()
	if context.get("depth",0) != 0: return
	if rank("T11") > 0:
		ammo_kills += 1
		if ammo_kills >= DemoConfig.TALENTS.T11.kills:
			ammo_kills = 0
			PlayerData.reserve_magazines += int(DemoConfig.talent_value("T11",rank("T11")))
	var gun = context.get("gun")
	if is_instance_valid(gun) and context.get("refill",0) > 0 and cooldown("A24") <= 0:
		talent_cooldowns.A24 = AttachmentCatalog.DEFINITIONS[124].cooldown
		gun.bullets_count = mini(gun.bullets_max_count,gun.bullets_count+1)
	if rank("T24") > 0 and heal_cooldown <= 0:
		heal_cooldown = DemoConfig.TALENTS.T24.cooldown
		PlayerData.addPlayerHp(DemoConfig.talent_value("T24",rank("T24")))
	if rank("T16") > 0 and blast_cooldown <= 0:
		blast_cooldown = DemoConfig.TALENTS.T16.cooldown
		Combat.explosion(monster.global_position,DemoConfig.TALENTS.T16.radius,DemoConfig.TALENTS.T16.damage,context.get("gun"),1)

func snapshot() -> Dictionary:
	var weapons = []
	for gun in PlayerData.player_weapon_list.values(): weapons.append({"id":str(gun.weapon_id),"ammo":gun.bullets_count})
	return {"schema_version":6,"campaign_complete":campaign_complete,"build_profile":DemoConfig.PROFILE,"gold":PlayerData.gold,"points":PlayerData.reward_point,"reserve_magazines":PlayerData.reserve_magazines,"level":PlayerData.player_level,"exp":PlayerData.player_exp,"hp":PlayerData.player_hp,"hp_max":PlayerData.player_hp_max,"weapons":weapons,"owned_global_upgrades":owned_global_upgrades.duplicate(),"talents":talents,"talent_payments":talent_payments,"legacy":purchases,"legacy_state":legacy_state(),"next_stage":next_stage,"selected_stage":selected_stage,"equipped":str(Utils.player.gun.weapon_id) if is_instance_valid(Utils.player) and Utils.player.gun else ""}

func legacy_state() -> Dictionary:
	var result = {}
	if is_instance_valid(Utils.player):
		for reward in Utils.player.reward_root.get_children():
			if reward.id == 10: result["10"] = reward.kill_count
			if reward.has_method("saved_state"): result[str(reward.id)] = reward.saved_state()
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
	owned_global_upgrades = data.owned_global_upgrades.duplicate()
	grenade_cooldown = 0
	talent_payments = data.talent_payments.duplicate(true)
	applied_talent_hp = DemoConfig.talent_value("T07",rank("T07"))
	reset_revision += 1
	talent_cooldowns.clear()
	ammo_kills = 0
	crowd_active = false
	PlayerData.player_level = int(data.level)
	PlayerData.player_exp = data.exp
	for w in data.weapons:
		PlayerData.add_weapon(Utils.weapon_list[w.id].instantiate())
	purchases = data.legacy.duplicate()
	for id in purchases:
		var reward = RewardServer.reward_list[id].instantiate()
		if reward.only_start: reward.free()
		else: RewardServer.addReward(reward)
	for reward in Utils.player.reward_root.get_children():
		if reward.id == 10: reward.kill_count = int(data.legacy_state.get("10",0))
		if reward.has_method("restore_state"): reward.restore_state(data.legacy_state.get(str(reward.id),{}))
	campaign_complete = data.get("campaign_complete",false)
	next_stage = int(data.next_stage)
	selected_stage = int(data.selected_stage)
	trial = false
	kill_stacks = 0; stack_time = 0
	for gun in PlayerData.player_weapon_list.values(): gun.bullets_count = 0
	loading = false
	# One complete configuration calculation; intermediate ammo is never restored.
	refresh()
	for w in data.weapons: PlayerData.player_weapon_list[int(w.id)].bullets_count = int(w.ammo)
	PlayerData.reserve_magazines = int(data.reserve_magazines)
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
	if parsed.schema_version < 6 and not test_mode: save_camp()
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
	var fresh = {"schema_version":6,"campaign_complete":false,"gold":DemoConfig.INITIAL_GOLD,"points":DemoConfig.INITIAL_TALENT_POINTS,"reserve_magazines":10,"level":1,"exp":0,"hp":5,"hp_max":5,"weapons":[],"owned_global_upgrades":[],"talents":{},"talent_payments":[],"legacy":[],"legacy_state":{},"next_stage":1,"selected_stage":1,"equipped":""}
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

func open_stats():
	var panel=load("res://ui/StatPanel.gd").new()
	Utils.canvasLayer.add_child(panel)

var lesson_state = ""
var lesson_overlay: Control
func root_lesson():
	if lesson_state!="": return
	lesson_state="explanation"
	lesson_message("束缚攻击训练", "学习如何识别并应对 Boss 的紫色束缚攻击\n\n某些 Boss 会发射特殊的紫色束缚弹。\n命中后约0.5秒无法移动、无法Dash；\n仍可瞄准、射击和换弹。正式战斗中应优先躲避。\n\n本次训练目标：故意让紫色束缚弹命中你一次。", "开始训练", start_root_lesson)

func lesson_message(title: String, text: String, action_text: String, action: Callable):
	var overlay=Control.new(); overlay.set_script(load("res://ui/RootLessonPanel.gd"))
	overlay.heading=title; overlay.explanation=text; overlay.action_text=action_text; overlay.action=action
	lesson_overlay=overlay; Utils.canvasLayer.add_child(overlay)

func start_root_lesson():
	if lesson_state!="explanation": return
	lesson_state="starting"
	for menu in pause_stack.duplicate(): menu.queue_free(); pop_pause(menu)
	LevelServer.return_to_camp()
	await get_tree().create_timer(0.3).timeout
	for menu in pause_stack.duplicate(): menu.queue_free(); pop_pause(menu)
	if not LevelServer.town.depart(20,true): lesson_state=""; return
	LevelServer.timerStop()
	PlayerData.player_hp=PlayerData.player_hp_max
	var boss=instance_from_id(LevelServer.boss_instance)
	var center=LevelServer.town.arena.global_position
	Utils.player.global_position=center+Vector2(-40,0)
	boss.global_position=center+Vector2(40,0)
	boss.set_physics_process(false); boss.phase_two=true; boss.HP=boss.max_hp*0.49; boss.ultimate_cooldown=0
	var lesson_epoch=LevelServer.epoch
	lesson_state="objective"
	var objective=Label.new(); objective.text="训练目标：让紫色束缚弹命中你"
	objective.position=Vector2(70,38); objective.add_theme_font_size_override("font_size",9)
	objective.add_theme_font_override("font",load("res://fonts/fusion-pixel.otf")); Utils.canvasLayer.add_child(objective)
	while LevelServer.epoch==lesson_epoch and LevelServer.state=="COMBAT" and is_instance_valid(boss) and not boss.is_die:
		if get_tree().get_nodes_in_group("boss_ultimate").is_empty():
			boss.ultimate_cooldown=0; boss.choose_attack()
		var deadline=Time.get_ticks_msec()+5000
		while Utils.player.root_remaining<=0 and Time.get_ticks_msec()<deadline and LevelServer.epoch==lesson_epoch:
			await get_tree().create_timer(0.02,false).timeout
		if Utils.player.root_remaining>0:
			lesson_state="hit"; objective.text="束缚！约0.5s · 仍可瞄准 / 射击 / 换弹"
			while Utils.player.root_remaining>0: await get_tree().create_timer(0.02,false).timeout
			objective.text="束缚结束"
			await get_tree().create_timer(0.35,false).timeout
			break
	objective.queue_free()
	if LevelServer.epoch!=lesson_epoch or LevelServer.state!="COMBAT": lesson_state=""; return
	if lesson_state!="hit": LevelServer.return_to_camp(); lesson_state=""; return
	lesson_state="complete"
	lesson_message("训练完成", "你已经体验过束缚攻击。\n\n看到紫色束缚弹时，优先移动躲避。\n如果被击中，会短暂无法移动，\n但仍可继续攻击。", "返回营地", finish_root_lesson)

func finish_root_lesson():
	lesson_state=""
	for menu in pause_stack.duplicate(): menu.queue_free(); pop_pause(menu)
	LevelServer.return_to_camp()

func quit_game():
	if quitting_game: return
	stop_attacks()
	if Utils.is_game_start and not save_camp().success:
		show_save_dialog(save_blocked,true)
		return
	finish_quit()

func finish_quit():
	if quitting_game: return
	quitting_game = true
	# Release the custom cursor texture before the renderer shuts down.
	Input.set_custom_mouse_cursor(null)
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for node in get_tree().root.find_children("*",type,true,false): node.stop()
	await get_tree().create_timer(0.1,true).timeout
	get_tree().quit()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Utils.is_game_start and LevelServer.state == "COMBAT" and pause_stack.is_empty():
		open_panel()

func fire_global_grenade(point: Vector2) -> bool:
	if not "9" in owned_global_upgrades or grenade_cooldown > 0 or get_tree().paused or not is_instance_valid(Utils.player) or Utils.player.is_dead or not Utils.player.gun: return false
	if LevelServer.state != "COMBAT": return false
	grenade_cooldown = 2.0
	var grenade = load("res://game/other/Grenade.tscn").instantiate()
	grenade.hurt = Utils.player.gun.effective.damage*0.35
	grenade.global_position = Utils.player.gun.global_position
	get_tree().current_scene.add_child(grenade)
	grenade.launch(point)
	return true

func _unhandled_input(event):
	if event.is_action_pressed("mouse_right") and pause_stack.is_empty() and is_instance_valid(Utils.player):
		if fire_global_grenade(Utils.player.Utils.get_aim_world_position()): get_viewport().set_input_as_handled()
