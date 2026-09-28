extends Control

@onready var image = $TextureRect
@onready var rw_name = $Label
var id
var ins:BaseReward

signal onMouseIn(info)
signal onClick(id)

func _ready() -> void:
	preload("res://ui/GildedTheme.gd").legacy_tree(self)
	# One visible focus/hover surface behind the real icon; the whole card is clickable.
	move_child($Button,0)
	$Button.flat = false
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Button.focus_entered.connect(_on_button_mouse_entered)
	preload("res://ui/GildedTheme.gd").entrance(self)

func setData(id):
	self.id = id
	ins = RewardServer.reward_list[id].instantiate()
	image.texture = ins.reward_image
	rw_name.text = ins.reward_name.get_slice(" ",0) if ins.id>=12 else ins.reward_name

func _exit_tree() -> void:
	if ins:
		ins.queue_free()

func _on_button_pressed() -> void:
	emit_signal("onClick",id)

func _on_button_mouse_entered() -> void:
	if ins:
		emit_signal("onMouseIn",ins.reward_info)
