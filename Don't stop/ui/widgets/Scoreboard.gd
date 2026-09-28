extends Control

@onready var time = $Panel/TextureRect2/Label
@onready var kill = $Panel/TextureRect3/Label
@onready var gold = $Panel/TextureRect4/Label

var callback:Callable

var data

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.push_pause(self)

func _exit_tree() -> void:
	Demo.pop_pause(self)

func _ready() -> void:
	preload("res://ui/GildedTheme.gd").legacy_tree(self)
	preload("res://ui/GildedTheme.gd").modal_backdrop(self)
	preload("res://ui/GildedTheme.gd").primary($Panel/Button)
	preload("res://ui/GildedTheme.gd").entrance($Panel)
	time.text = "%02d:%02d" % [int(data["time"])/60,int(data["time"])%60]
	kill.text = str(data["kill"])
	gold.text = str(data["gold"])
	if data.has("stage"):
		$Panel/Route.text = ("试玩" if data.get("trial",false) else "正常进度")+" · "+DemoConfig.ENCOUNTERS[data.stage].name+("\n核心完成，可回营重玩" if data.stage == 30 else "")

func setData(data):
	self.data = data

func setCallBack(callback:Callable):
	self.callback = callback

func _on_button_pressed() -> void:
	if callback:
		callback.call()
	queue_free()
