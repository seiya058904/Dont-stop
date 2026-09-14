extends Control

const pre = preload("res://ui/widgets/RewardShopItem.tscn")

@onready var list = $NinePatchRect/HBoxContainer
@onready var info_label = $NinePatchRect/Label3

func _ready() -> void:
	PlayerData.onRewardChange.connect(self.onRewardChange)
	loadList(false)
	onRewardChange(PlayerData.reward_point)

func onRewardChange(reward):
	$NinePatchRect/Label.text = tr("REMAINING REWARD POINTS") + str(reward)

func loadList(reload):
	for item in list.get_children():
		item.queue_free()
	for item in RewardServer.getShopList(reload):
		var ins = pre.instantiate()
		list.add_child(ins)
		ins.setData(item)
		ins.onClick.connect(self.onClick)
		ins.onMouseIn.connect(self.onMouseIn)

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

func onClick(id):
	var result = Demo.try_purchase("legacy",str(id),"points")
	if result.success:
		loadList(true)
		$AudioStreamPlayer2.play()
	Utils.showToast(result.reason,3)

func onMouseIn(info):
	info_label.text = tr(info)


func _on_button_2_pressed() -> void:
	if PlayerData.gold >= 10:
		$AudioStreamPlayer.play()
		PlayerData.gold -= 10
		loadList(true)


func _on_button_pressed() -> void:
	queue_free()

func _enter_tree():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.push_pause(self)
func _exit_tree():
	Demo.pop_pause(self)
