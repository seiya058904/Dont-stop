extends Node
const PROGRESSION = preload("res://game/config/LevelProgression.gd")
signal level_rewards_applied(rewards)

signal playerWeaponListChange() #武器列表改变
signal onWeaponChanged() #切换武器
signal onWeaponChangeAnim(id, tag) #切换武器动作
signal onPlayerFireRateChange(player_fire_rate) #玩家复活信号
signal onWeaponBulletsChange(bullet,max_bullet) #武器子弹数量变化
signal onAmmoChange(ammo) #备用子弹数量变化
signal onPlayerDeath() #玩家死亡信号
signal onPlayerResurrect() #玩家复活信号

signal onRewardChange(reward)#血量变化
signal onHpChange(hp,max_hp)#血量变化
signal onGoldChange(gold)#血量变化
signal onPlayerLevelChange(level) #玩家等级信号
signal onPlayerExpChange(exp,max_exp) #玩家经验信号

var player_fire_rate = 1: #全局武器间隔
	set(value):
		player_fire_rate = value
		emit_signal("onPlayerFireRateChange",player_fire_rate)
var reserve_magazines = 10: # Shared whole reloads, independent of gun capacity
	set(value):
		reserve_magazines = maxi(0,int(value))
		emit_signal("onAmmoChange",reserve_magazines)
var player_am_list = {} #配件列表
var player_weapon_list = {} #武器列表
var weapon_slots: Array = [-1,-1,-1,-1,-1,-1,-1]
var switch_reason := ""

func load_slots(data: Dictionary) -> void:
	weapon_slots = [-1,-1,-1,-1,-1,-1,-1]
	if data.has("weapon_slots"):
		var incoming = data.weapon_slots
		if incoming is Array:
			for i in mini(7,incoming.size()):
				var value = incoming[i]
				if not (value is int or value is float) or not is_finite(float(value)) or value != floor(value): continue
				var id = int(value)
				if player_weapon_list.has(id) and not weapon_slots.has(id): weapon_slots[i] = id
	else:
		# Legacy ownership order migrates once; an equipped eighth gun must stay reachable.
		var ids = player_weapon_list.keys()
		for i in mini(7,ids.size()): weapon_slots[i] = int(ids[i])
		if data.get("equipped","") != "":
			var current = int(data.equipped)
			if player_weapon_list.has(current) and not weapon_slots.has(current): weapon_slots[6] = current

func _loadout_result(text: String) -> Dictionary:
	playerWeaponListChange.emit()
	onWeaponChanged.emit()
	Demo.changed.emit()
	var saved = Demo.save_camp()
	return {"success":true,"saved":saved.success,"reason":text+("；已保存" if saved.success else "；尚未保存，请重试保存")}

func _disarm() -> void:
	if is_instance_valid(Utils.player) and is_instance_valid(Utils.player.gun):
		Utils.player.gun.set_use(false)
		Utils.player.gun = null
	Demo.explicitly_unequipped = true
	onWeaponChanged.emit()

func remove_slot(slot: int) -> Dictionary:
	if LevelServer.state != "CAMP": return {"success":false,"reason":"仅营地可调整携带栏"}
	if slot < 0 or slot >= 7: return {"success":false,"reason":"无效槽位"}
	var id = weapon_slots[slot]
	if is_instance_valid(Utils.player) and Utils.player.gun and Utils.player.gun.weapon_id == id: _disarm()
	weapon_slots[slot] = -1
	return _loadout_result("已移出槽位%d；保留所有已购武器" % (slot+1))

func clear_loadout() -> Dictionary:
	if LevelServer.state != "CAMP": return {"success":false,"reason":"仅营地可调整携带栏"}
	_disarm()
	weapon_slots = [-1,-1,-1,-1,-1,-1,-1]
	return _loadout_result("已卸下全部；保留所有已购武器")

func equip_owned(id: int, slot: int = -1) -> Dictionary:
	if LevelServer.state != "CAMP": return {"success":false,"reason":"仅营地可调整携带栏"}
	if not is_instance_valid(Utils.player) or Utils.player.is_dead or not player_weapon_list.has(id): return {"success":false,"reason":"武器未拥有或当前不能装备"}
	if Time.get_ticks_msec() < switch_deadline and Utils.player.gun != player_weapon_list[id]: return {"success":false,"reason":"切换冷却中，请稍后重试"}
	var existing = weapon_slots.find(id)
	if existing >= 0: slot = existing
	elif slot == -1: slot = weapon_slots.find(-1)
	if slot < 0 or slot >= 7: return {"success":false,"reason":"携带栏已满，请选择要替换的槽位", "needs_slot":true}
	var previous = weapon_slots[slot]
	if previous != id and Utils.player.gun and Utils.player.gun.weapon_id == previous: _disarm()
	weapon_slots[slot] = id
	if not changeWeapon(id,true,false): return {"success":false,"reason":switch_reason}
	return _loadout_result("已装备至槽位%d" % (slot+1))
var player_reward = {} #奖励列表
var player_hp_max = 5: #最大血量
	set(value):
		player_hp_max = value
		emit_signal("onHpChange",player_hp,player_hp_max)
var player_hp = 5: #当前血量
	set(value):
		var previous = player_hp
		player_hp = clampf(value, 0, player_hp_max)
		emit_signal("onHpChange",player_hp,player_hp_max)
		if player_hp <= 0 and previous > 0:
			emit_signal("onPlayerDeath")
var gold = DemoConfig.INITIAL_GOLD:
	set(value):
		gold = value
		emit_signal("onGoldChange",gold)

var player_speed = 1.0 #玩家额外移速加成
var player_damage = 0.3 #玩家基础伤害
var base_bullet_damage = 0 #子弹伤害增幅
var base_bullet_speed = 0 #射速增幅
var base_reload_speed = 0 #换弹增幅
var base_aim_enh = 0 #子弹暴击增幅
var base_magazine_count = 0 #子弹数量加成
var reward_point = DemoConfig.INITIAL_TALENT_POINTS:
	set(value):
		reward_point = value
		emit_signal("onRewardChange",reward_point)

var player_level = 1:
	set(value):
		player_level = maxi(1,int(value))
		player_damage = PROGRESSION.damage(player_level)
		onPlayerLevelChange.emit(player_level)

var player_exp = 0.0:
	set(value):
		if value < 0: return
		player_exp = value
		var before = player_level
		while player_exp >= getMaxExp():
			player_exp -= getMaxExp()
			player_level += 1
			var growth = PROGRESSION.rewards(player_level-1,player_level)
			player_hp_max += growth.max_hp
			player_hp += growth.heal
			reward_point += growth.points
		if player_level>before: level_rewards_applied.emit(PROGRESSION.rewards(before,player_level))
		onPlayerExpChange.emit(player_exp,getMaxExp())

#设置血量
func resurrectPlayer(hp, ammo_percentage):
	if hp >= player_hp_max:
		player_hp = player_hp_max
	else:
		player_hp = hp
	if Utils.player.gun != null:
		reserve_magazines = maxi(reserve_magazines,ceili(ammo_percentage/100.0))
	emit_signal("onPlayerResurrect")

#回复血量
func addPlayerHp(hp):
	if hp + player_hp >= player_hp_max:
		player_hp = player_hp_max
	else:
		player_hp += hp
	#emit_signal("onPlayerResurrect")

var is_change_weapon = false
#添加一把武器
func add_weapon(weapon:BaseGun):
	if !player_weapon_list.has(weapon.weapon_id):
		player_weapon_list[weapon.weapon_id] = weapon
		if not Demo.loading and not Demo.explicitly_unequipped and weapon_slots.has(-1) and not weapon_slots.has(weapon.weapon_id):
			weapon_slots[weapon_slots.find(-1)] = weapon.weapon_id
		emit_signal("playerWeaponListChange")
		return true
	return false

#添加一堆武器
func add_weapons(weapons :Array):
	var is_change = false
	for item in weapons:
		add_weapon(item)
	emit_signal("playerWeaponListChange")

func add_attachment(am:BaseAttachment):
	# Legacy scene entry point cannot create inventory in the M8 product model.
	am.free()

var switch_deadline = 0
var switch_remaining = 0.0
func changeWeapon(weapon_id: int, from_panel = false, persist = true) -> bool:
	switch_reason = ""
	if not is_instance_valid(Utils.player) or not player_weapon_list.has(weapon_id) or Utils.player.is_dead:
		switch_reason = "当前不能切换武器"; return false
	if from_panel and LevelServer.state != "CAMP":
		switch_reason = "仅营地可从面板装备"; return false
	if get_tree().paused and not from_panel:
		switch_reason = "暂停中不能切换武器"; return false
	if not weapon_slots.has(weapon_id):
		if from_panel:
			var result = equip_owned(weapon_id)
			switch_reason = result.reason
			return result.success
		switch_reason = "武器未在携带栏，请在营地加入"; return false
	if Utils.player.gun == player_weapon_list[weapon_id]: return true
	if Time.get_ticks_msec() < switch_deadline:
		switch_reason = "切换冷却中，请稍后重试"; return false
	switch_deadline = Time.get_ticks_msec() + int(DemoConfig.SWITCH_SECONDS*1000)
	is_change_weapon = true
	switch_remaining = DemoConfig.SWITCH_SECONDS
	Utils.player.changeWeapon(weapon_id)
	# Any successful equip - panel or hotkey - is an explicit player choice: it ends the
	# "player chose to stay unarmed" state, so a later purchase may resume default equipping.
	Demo.explicitly_unequipped = false
	Demo.changed.emit()
	if persist: Demo.save_camp()
	return true

func _physics_process(_delta: float) -> void:
	switch_remaining = maxf(0,(switch_deadline-Time.get_ticks_msec())/1000.0)
	is_change_weapon = switch_remaining > 0

func getMaxExp():
	return PROGRESSION.threshold(player_level)
