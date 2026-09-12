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
	time.text = "%s: %s" %[tr("SURVIVAL TIME"),int(data["time"])]
	kill.text = "%s: %s" %[tr("DEFEAT ENEMIES"),data["kill"]]
	gold.text = "%s: %s" %[tr("OBTAIN GOLD"),data["gold"]]
	if data.has("stage"):
		var route = Label.new(); route.text = ("试玩" if data.get("trial",false) else "正常进度")+" · "+DemoConfig.ENCOUNTERS[data.stage].name+(" · 核心完成，可回营重玩" if data.stage == 30 else ""); route.position = Vector2(18,18); route.add_theme_font_size_override("font_size",10); add_child(route)

func setData(data):
	self.data = data

func setCallBack(callback:Callable):
	self.callback = callback

func _on_button_pressed() -> void:
	if callback:
		callback.call()
	queue_free()
