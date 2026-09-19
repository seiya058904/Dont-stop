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
func changeWeapon(weapon_id: int, from_panel = false) -> bool:
	if not is_instance_valid(Utils.player) or not player_weapon_list.has(weapon_id) or Utils.player.is_dead: return false
	if get_tree().paused and not from_panel: return false
	if Utils.player.gun == player_weapon_list[weapon_id]: return true
	if Time.get_ticks_msec() < switch_deadline: return false
	switch_deadline = Time.get_ticks_msec() + int(DemoConfig.SWITCH_SECONDS*1000)
	is_change_weapon = true
	switch_remaining = DemoConfig.SWITCH_SECONDS
	Utils.player.changeWeapon(weapon_id)
	# Any successful equip - panel or hotkey - is an explicit player choice: it ends the
	# "player chose to stay unarmed" state, so a later purchase may resume default equipping.
	Demo.explicitly_unequipped = false
	Demo.changed.emit()
	Demo.save_camp()
	return true

func _physics_process(_delta: float) -> void:
	switch_remaining = maxf(0,(switch_deadline-Time.get_ticks_msec())/1000.0)
	is_change_weapon = switch_remaining > 0

func getMaxExp():
	return PROGRESSION.threshold(player_level)
