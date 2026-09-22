extends Node2D

## Inert loading-stage draws for the lit primitive/attribute variants seen in
## Web traces. This node never enters a gameplay group or advances simulation.
var draw_kind := -1

func _draw() -> void:
	if draw_kind in [-1,0]:
		draw_line(Vector2(12,12),Vector2(28,20),Color.WHITE,2.0)
	if draw_kind in [-1,1]:
		draw_circle(Vector2(36,20),5.0,Color.WHITE)
	if draw_kind in [-1,2]:
		draw_colored_polygon(PackedVector2Array([Vector2(12,28),Vector2(28,28),Vector2(20,40)]),Color.WHITE)
