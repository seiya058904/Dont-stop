extends Bullet
var exploded = false
func _ready():
	super._ready()
	scale = Vector2(2,2)
func _draw():
	draw_circle(Vector2.ZERO,4,Color(0.2,1,0.65))
	draw_arc(Vector2.ZERO,6,0,TAU,16,Color(0.65,1,0.85),1)
func _physics_process(delta):
	if exploded: return
	var collision = move_and_collide(velocity*delta)
	if collision:
		exploded = true
		Combat.explosion_context(global_position,context.get("radius",32.0),context)
		queue_free()
