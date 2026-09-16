extends Node2D
class_name FogPierceCanvas

## Canvas for FogPierce. Lives on its own CanvasLayer, which is a separate canvas from
## the one holding Main.tscn's CanvasModulate, so what it draws is NOT multiplied by the
## Hell darkness. Producers write world-space geometry every physics tick; this node
## drains the queue once per drawn frame.

const MAX_ENTRIES := 128

var entries: Array = []

func _process(_delta: float) -> void:
	if not entries.is_empty(): queue_redraw()

func _draw() -> void:
	for entry in entries:
		match entry.kind:
			"circle": draw_arc(entry.a,entry.radius,0,TAU,32,entry.color,entry.width,true)
			"dot": draw_circle(entry.a,entry.width,entry.color)
			_: draw_line(entry.a,entry.b,entry.color,entry.width,true)
	entries.clear()
