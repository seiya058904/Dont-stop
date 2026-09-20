extends Node2D

## Inert loading-stage draws for the lit primitive/attribute variants seen in
## Web traces. This node never enters a gameplay group or advances simulation.
func _draw() -> void:
	draw_line(Vector2(12,12),Vector2(28,20),Color.WHITE,2.0)
	draw_circle(Vector2(36,20),5.0,Color.WHITE)
	draw_colored_polygon(PackedVector2Array([Vector2(12,28),Vector2(28,28),Vector2(20,40)]),Color.WHITE)
