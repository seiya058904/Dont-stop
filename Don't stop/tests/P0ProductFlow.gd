extends Node

## Entry point that hands the session to the REAL product boot scene while keeping
## the observer alive across the scene change.
func _ready() -> void:
	var observer := Node.new()
	observer.name = "P0ProductFlowObserver"
	observer.set_script(load("res://tests/P0ProductFlowObserver.gd"))
	get_tree().root.add_child.call_deferred(observer)
	get_tree().change_scene_to_file.call_deferred("res://boot/Boot.tscn")
