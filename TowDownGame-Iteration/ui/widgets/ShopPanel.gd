extends NinePatchRect

const wi_pre = preload("res://ui/widgets/ShopWeaponItem.tscn")
@onready var shop_weapon_list = $ScrollContainer/GridContainer
@onready var shop_am_list = $ScrollContainer2/GridContainer
@onready var dialog = $Control
@onready var dilaog_label = $Control/TextureRect/Label
@onready var tip = $Tooltip
@onready var player = $AudioStreamPlayer

var choose_id = null
var choose_am : BaseAttachment= null

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.push_pause(self)

func _exit_tree() -> void:
	Demo.pop_pause(self)

func _ready() -> void:
	for id in Utils.weapon_list:
		var ins = wi_pre.instantiate()
		shop_weapon_list.add_child(ins)
		ins.setData(id)
		ins.onWeaponClick.connect(self.onWeaponClick)
	loadAmList()

func loadAmList():
	for item in shop_am_list.get_children():
		item.queue_free()
	for item in Utils.getTempAmList():
		var ins = wi_pre.instantiate()
		shop_am_list.add_child(ins)
		ins.setAmData(item)
		ins.mouseEvent.connect(self.mouseEvent)
		ins.onAmClick.connect(self.onAmClick)

func onWeaponClick(id,gun:BaseGun):
	choose_am = null
	choose_id = id
	dialog.visible = true
	dilaog_label.text = tr("BUY_WEAPON_TIP") + tr(gun.weapon_name)

func onAmClick(id,am:BaseAttachment):
	choose_id = id
	choose_am = am
	dialog.visible = true
	dilaog_label.text = tr("BUY_AM_TIP") + tr(am.am_name)

func _on_button_pressed() -> void:
	dialog.visible = false
	var result = Demo.try_purchase("attachment" if choose_am != null else "weapon",str(choose_id))
	choose_id = null
	choose_am = null
	Utils.showToast(result.reason,3)

func _on_button_2_pressed() -> void:
	dialog.visible = false
	choose_id = null
	choose_am = null

func mouseEvent(show,am):
	tip.visible = show
	tip.setData(am)

#关闭
func _on_button_3_pressed() -> void:
	queue_free()

#刷新
func _on_reload_pressed() -> void:
	Utils.reloadTempAmList()
	loadAmList()


func _on_add_ammo_pressed() -> void:
	if PlayerData.gold > 0:
		PlayerData.gold -= 1
		PlayerData.reserve_magazines += 1
		player.play()

func _on_health_pressed() -> void:
	if PlayerData.gold >= 10:
		PlayerData.gold -= 10
		PlayerData.player_hp = PlayerData.player_hp_max
		player.play()

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
