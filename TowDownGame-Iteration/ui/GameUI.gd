extends Control

const weapon_item_pre = preload("res://ui/widgets/WeaponListItem.tscn")
const weapon_bullet_pre = preload("res://ui/widgets/BulletCountItem.tscn")
const weapon_inventory = preload("res://ui/Inventory.tscn")
const rw_top = preload("res://ui/widgets/RewardTopItem.tscn")

@onready var change_audio = $AudioStreamPlayer2D

@onready var box_top = $hpUI
@onready var bottom_bls = $Container
@onready var gold_label = $hpUI/Label
@onready var reward_label = $hpUI/Label2
@onready var weapon_lsit_node = $HBoxContainer
@onready var weapon_change_image = $WeaponChangeUI/WeaponImage
@onready var weapon_bullet_list = $Container/BulletHbox
@onready var ammo_count_label = $Container/Label
@onready var weapon_change_name = $WeaponChangeUI/WeaponImage/Label
@onready var hp_bar = $hpUI/ProgressBar
@onready var ammo_label = $Container/all_ammo
@onready var rw_grid = $RwGridContainer
@onready var level_label = $hpUI/Label3
@onready var level_bar = $hpUI/ProgressBar2
@onready var level_panel = $LevelUpPanel

var weapon_feedback_tween: Tween
var inv_ui

func _ready() -> void:
	change_audio.bus = "UI"
	Demo.restored.connect(on_restore)
	Utils.onGameStart.connect(self.onGameStart)
	RewardServer.onRewardAdd.connect(self.onRewardAdd)
	PlayerData.onRewardChange.connect(self.onRewardChange)
	PlayerData.onGoldChange.connect(self.onGoldChange)
	PlayerData.onAmmoChange.connect(self.onAmmoChange)
	PlayerData.onPlayerLevelChange.connect(self.onPlayerLevelChange)
	PlayerData.onPlayerExpChange.connect(self.onPlayerExpChange)
	PlayerData.playerWeaponListChange.connect(self.playerWeaponListChange) #武器列表化监听
	PlayerData.onWeaponChangeAnim.connect(self.onWeaponChangeAnim) #武器化监听
	PlayerData.onWeaponBulletsChange.connect(self.onWeaponBulletsChange) #武器化监听
	PlayerData.onHpChange.connect(func hpChange(hp,max_hp): #血量变化监听
		hp_bar.max_value = max_hp;hp_bar.value = hp)

func onGameStart():
	level_label.text = tr("LEVEL") + str(PlayerData.player_level)
	onPlayerExpChange(PlayerData.player_exp,PlayerData.getMaxExp())
	onGoldChange(PlayerData.gold)
	onRewardChange(PlayerData.reward_point)
	onAmmoChange(PlayerData.reserve_magazines)
	var tween = get_tree().create_tween().set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	tween.tween_property(box_top,"position:y",box_top.position.y,0.3).from(box_top.position.y-box_top.size.y)
	tween.tween_property(bottom_bls,"position:y",bottom_bls.position.y,0.3).from(bottom_bls.position.y+bottom_bls.size.y)
	tween.tween_property(weapon_lsit_node,"position:y",weapon_lsit_node.position.y,0.3).from(weapon_lsit_node.position.y+weapon_lsit_node.size.y)
	show()

func on_restore():
	for box in [weapon_lsit_node,rw_grid,weapon_bullet_list]:
		for child in box.get_children(): child.free()
	playerWeaponListChange()
	for reward in Utils.player.reward_root.get_children(): onRewardAdd(reward)
	if Utils.player.gun: loadWeaponBullets(Utils.player.gun.weapon_id)
	else:
		ammo_count_label.text = "0"
		weapon_change_image.texture = null
		weapon_change_name.text = ""

func playerWeaponListChange():
	for item in PlayerData.player_weapon_list:
		if weapon_lsit_node.get_child_count() < 7 and !weapon_lsit_node.has_node(str(item)):
			var ins = weapon_item_pre.instantiate()
			ins.name = str(item)
			ins.local_id = item
			weapon_lsit_node.add_child(ins)

func onWeaponChangeAnim(weapon_id,tag = Utils.GUN_CHANGE_TYPE.CHANGE):
	if tag == Utils.GUN_CHANGE_TYPE.CHANGE:
		change_audio.play()
		var weapon:BaseGun = PlayerData.player_weapon_list[weapon_id]
		weapon_change_name.text = weapon.weapon_name
		ammo_count_label.text = "%s" %[weapon.bullets_count]
		weapon_change_image.texture = weapon.image
		if weapon_feedback_tween and weapon_feedback_tween.is_valid(): weapon_feedback_tween.kill()
		weapon_feedback_tween = get_tree().create_tween().set_ease(Tween.EASE_IN_OUT)
		weapon_feedback_tween.tween_property(weapon_change_image,"modulate:a",1.0,0.3).from(0.0)
		weapon_feedback_tween.tween_property(weapon_change_image,"modulate:a",0.0,0.3).from(1.0).set_delay(0.5)
	call_deferred("loadWeaponBullets",weapon_id)

func loadWeaponBullets(weapon_id):
	if not PlayerData.player_weapon_list.has(weapon_id): return
	for item in weapon_bullet_list.get_children():
		item.free()
	weapon_bullet_list.get_children().clear()
	var weapon:BaseGun = PlayerData.player_weapon_list[weapon_id]
	var local_count =  weapon.bullets_max_count - weapon.bullets_count
	var index = 1
	for item in mini(weapon.bullets_count,40):
		var ins = weapon_bullet_pre.instantiate()
		ins.name = str(local_count + index)
		weapon_bullet_list.add_child(ins)
		index += 1

func onWeaponBulletsChange(bullet,bullet_max):
	ammo_count_label.text = "%s" %[bullet]
	var local_count =  bullet_max - bullet
	if weapon_bullet_list.has_node(str(local_count)):
		weapon_bullet_list.get_node(str(local_count)).destory()

func onGoldChange(gold):
	gold_label.text = tr("GOLD_HAS") + str(gold)

func onAmmoChange(ammo):
	ammo_label.text = "%d MAGS" % ammo

func onRewardChange(reward):
	reward_label.text = tr("REWARD_POINT") + str(reward)

func onRewardAdd(rw:BaseReward):
	if rw.only_start:
		return
	if rw_grid.has_node(str(rw.id)):
		rw_grid.get_node(str(rw.id)).setData(rw)
	else:
		var ins = rw_top.instantiate()
		ins.name = str(rw.id)
		rw_grid.add_child(ins)
		ins.setData(rw)

func onPlayerLevelChange(level):
	level_label.text = tr("LEVEL") + str(level)
	if !level_panel.visible :
		level_panel.visible = true
		var tween = create_tween()
		tween.tween_property(level_panel,"position:x",8,0.5)
		tween.tween_property(level_panel,"position:x",-level_panel.size.x - 5,0.5).set_delay(1)
		tween.tween_callback(func callback():
			level_panel.visible = false)

func onPlayerExpChange(exp,max_exp):
	level_bar.max_value = max_exp
	level_bar.value = exp

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inv") and Utils.is_game_start and Demo.pause_stack.is_empty():
		Demo.open_panel()
		get_viewport().set_input_as_handled()
