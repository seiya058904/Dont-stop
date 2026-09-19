extends Node2D
static var alive = 0
var age = 0.0
var lifetime = 0.28
var radius = 18.0
var direction = Vector2.RIGHT
var style = "generic"
var tint = Color(1,0.56,0.2)
## Per-family impact ink, so "what just went off" is legible without a label. Kept in step
## with CombatTelegraph.STYLES: same families, same hues.
const INK = {
	"generic":Color(1,0.56,0.2),
	"charge":Color(1,0.62,0.18),
	"detonate":Color(1,0.32,0.28),
	"projectile":Color(1,0.72,0.24),
	"laser":Color(0.45,0.95,1.0),
	"sweep":Color(1.0,0.5,0.94),
	"artillery":Color(1,0.78,0.3),
	"root":Color(0.8,0.5,1.0),
	"poison":Color(0.44,1.0,0.62),
	"ice":Color(0.66,0.96,1.0),
	"shock":Color(0.68,0.54,1.0),
	"summon":Color(0.64,0.84,1.0),
	"heal":Color(0.3,1,0.6),
	"shield":Color(0.35,0.8,1),
	"refill":Color(0.95,0.8,0.3)
}
static func emit_at(parent: Node, point: Vector2, reach = 18.0, dir = Vector2.RIGHT, family := "generic"):
	if alive >= 32: return
	# B11.1 test-only counter (game/diag/B11Probe.gd): transient VFX creation rate.
	if B11Probe.enabled: B11Probe.vfx_created += 1
	var fx = load("res://game/effects/HostileVFX.gd").new()
	fx.position = point; fx.radius = minf(75,reach); fx.direction = dir
	fx.style = family; fx.tint = INK.get(family,INK.generic)
	parent.add_child(fx)
func _ready():
	alive += 1; add_to_group("combat_transient"); add_to_group("hostile_vfx"); z_index = 6
func _exit_tree(): alive -= 1
func _process(delta):
	age += delta
	if age >= lifetime: queue_free(); return
	queue_redraw()
func _draw():
	# B11.2 test-only counter + visual isolation. `emit_at` and the node's lifetime are untouched:
	# this switches the INK off, not the effect, so an A/B run charges a cost to the drawing alone.
	if B11Probe.enabled: B11Probe.vfx_draws += 1
	if B11Probe.iso_vfx: return
	var p = age/lifetime
	var color = Color(tint.r,minf(1.0,tint.g+0.28*(1-p)),tint.b,(1-p)*0.7)
	if style in ["shield","refill","heal"]:
		if style=="shield":
			for i in 6:
				var a=i*TAU/6
				draw_arc(Vector2.ZERO,radius*(1+0.3*p),a+0.1,a+0.8,4,color,2,true)
		else:
			var at=Vector2(0,-radius*p)
			draw_line(at-Vector2(4,0),at+Vector2(4,0),color,2)
			if style=="heal":draw_line(at-Vector2(0,4),at+Vector2(0,4),color,2)
			else:draw_line(at+Vector2(-4,3),at+Vector2(4,3),color,2)
		return
	draw_arc(Vector2.ZERO,radius*(0.25+0.75*p),0,TAU,28,color,1.8*(1-p)+0.5,true)
	var sparks = PackedVector2Array()
	for i in 8:
		var dir = direction.rotated(i*TAU/8)
		sparks.append(dir*radius*p*0.6)
		sparks.append(dir*radius*(p*0.8+0.18))
	draw_multiline(sparks,color,1.4,true)
	# A muzzle flash is a directional cone, not a symmetric ring: projectile sources read
	# as "fired from there" rather than "exploded here".
	if style in ["projectile","laser","sweep"] and p < 0.6:
		var spread = 0.45 if style == "projectile" else 0.12
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO,direction.rotated(-spread)*radius*1.5,direction*radius*1.9,direction.rotated(spread)*radius*1.5]),Color(tint.r,tint.g,tint.b,(1.0-p/0.6)*0.45))
