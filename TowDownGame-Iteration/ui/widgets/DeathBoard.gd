extends Control

var handled = false
var click:Callable

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func setOnClick(callback:Callable):
	click = callback

func _on_button_pressed() -> void:
	if handled: return
	handled = true
	if PlayerData.gold >= 50:
		PlayerData.gold -= 50
		click.call(true)
	else:
		click.call(false)
		Utils.showToast("BUY_ERROR")
	queue_free()


func _on_button_2_pressed() -> void:
	if handled: return
	handled = true
	click.call(false)
	queue_free()
