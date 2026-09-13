extends Node2D

const reward_shop_pre = preload("res://ui/widgets/RewardChoose.tscn")

var is_add = false
var is_in_area = false

func _ready():
	$Button.pressed.connect(open_reward)

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is Player:
		$Button.visible = true

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body is Player:
		$Button.visible = false
		get_tree().call_group("reward_choose","queue_free")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("e") && $Button.visible && !is_add:
		open_reward()
		get_viewport().set_input_as_handled()

func open_reward():
	if $Button.visible && !is_add && Demo.pause_stack.is_empty():
		var ins = reward_shop_pre.instantiate()
		ins.tree_exited.connect(func tree_exited():
			Utils.set_gameplay_mouse_mode()
			Utils.crosshairChange(true)
			is_add = false)
		ins.tree_entered.connect(func tree_entered():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Utils.crosshairChange(false)
			is_add = true)
		Utils.canvasLayer.add_child(ins)
