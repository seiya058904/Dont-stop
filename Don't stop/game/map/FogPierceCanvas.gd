extends Node2D
class_name FogPierceCanvas

## Canvas for FogPierce. Lives on its own CanvasLayer, which is a separate canvas from
## the one holding Main.tscn's CanvasModulate, so what it draws is NOT multiplied by the
## Hell darkness. Producers write world-space geometry every physics tick; this node
## drains the queue once per drawn frame.

const MAX_ENTRIES := 128

var entries: Array = []
var decorations: Array = []
var seen: Dictionary = {}
var physics_frame := -1

func begin_frame() -> void:
	var frame = Engine.get_physics_frames()
	if physics_frame == frame: return
	physics_frame = frame
	entries.clear(); decorations.clear(); seen.clear()

func offer(entry: Dictionary) -> bool:
	begin_frame()
	var decorative = entry.get("decorative",false)
	var key = str(entry)
	if seen.has(key): return true
	# Necessary geometry scales with admitted threats (180 shots + bounded zones).
	# Only cosmetic cores share the fixed budget; they can never evict a boundary.
	if decorative and decorations.size() >= MAX_ENTRIES: return false
	seen[key] = true
	if decorative: decorations.append(entry)
	else: entries.append(entry)
	return true

func _process(_delta: float) -> void:
	begin_frame()
	# Also repaint the empty frame, removing the last producer's cached commands.
	queue_redraw()

func _draw() -> void:
	# B11.2 measurement only: the Fog layer was the one remaining producer whose cost was inferred
	# rather than read. `fog_draws` is the flicker proxy (see B11Probe) and `fog_entries_drawn`
	# is the entry volume that has to be held against the BEFORE build before the HostileZone
	# repaint gate is accepted.
	var started := Time.get_ticks_usec() if B11Probe.enabled else 0
	for entry in entries + decorations:
		match entry.kind:
			"circle": draw_arc(entry.a,entry.radius,0,TAU,32,entry.color,entry.width,true)
			"dot": draw_circle(entry.a,entry.width,entry.color)
			_: draw_line(entry.a,entry.b,entry.color,entry.width,true)
	if B11Probe.enabled:
		B11Probe.fog_draws += 1
		B11Probe.fog_entries_drawn += entries.size()
		B11Probe.fog_draw_usec += Time.get_ticks_usec()-started
