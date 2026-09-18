extends CanvasLayer
class_name FogPierce

## Draws the small set of warnings that must stay readable even when they start outside
## the player's lit radius.
##
## Why this exists: Hell restores the upstream darkness, so a long beam or a sweeping
## laser that originates beyond the light would otherwise be invisible right up to the
## moment it touches the player. The fog fairness gate (see HostileZone / StageHazard)
## already forbids damage before the footprint has been visible for long enough; this
## layer makes the threat DIRECTION readable, which is the user's stated requirement
## ("Laser：危险线必须先进入可见范围", "关键危险 telegraph 可以在 Fog 层上方绘制").
##
## Deliberately minimal: one canvas, straight segments and circles only, a hard per-frame
## cap, and it only exists while fog is active. It is an information layer, never a
## damage layer.
const GROUP := "fog_pierce"

var canvas: Node2D

## B11.2. `push_line` offers TWO entries per logical line (the lane, then its decorative core) and
## each offer used to re-resolve the canvas by scanning the parent's children, so one line cost two
## scans of every child of the world root. Measured on the worst-load profile: 85,664 scans for
## 43,245 lines in 45 s. The resolved layer is cached instead, and dropped the instant the node
## leaves the tree, so `queue_free()` (fog off, camp return) can never leave a stale reference.
##
## Lifetime, spelled out because a static reference to a Node outlives every scene:
##   * `_ready()`   publishes `self`, so the FIRST push of a round resolves nothing at all.
##   * `_exit_tree()` clears it, and is the only place that can - it runs for `queue_free()`,
##     for `remove_child()`, and for a whole-tree teardown (camp return, next stage, quit).
##   * every use re-validates. Three checks, because each one alone leaves a hole:
##       `is_instance_valid` - a freed object still reads as non-null through a static var;
##       `is_inside_tree`    - a node that left the tree but is not reclaimed yet;
##       `is_queued_for_deletion` - `queue_free()` defers, so for the rest of that frame the
##                             node is valid AND in the tree AND already condemned. FogPierce
##                             condemns itself (`_process`, fog off) exactly when a camp return
##                             deletes it, so this window is on the real camp-return path.
##     Any of the three failing means "not this one", never "return a dead canvas".
##   * the scan skips condemned nodes too, so a round that starts while the previous canvas is
##     still waiting to die gets a NEW canvas instead of the one being torn down.
##   * nothing is remembered across a scene change: the new round's canvas is found by scanning
##     the live tree, and `_cached` can only ever point at a node that passes all three checks.
static var _cached: FogPierce = null

## A canvas the producers can still draw into: alive, still parented, not condemned this frame.
static func _usable(layer) -> bool:
	return is_instance_valid(layer) and layer.is_inside_tree() and not layer.is_queued_for_deletion()

static func instance() -> FogPierce:
	# B11.2 test-only counter: the child scan is the unit of cost this cache removes.
	if B11Probe.enabled: B11Probe.fog_ensure_scans += 1
	if _usable(_cached):
		if B11Probe.enabled: B11Probe.fog_canvas_hits += 1
		return _cached
	_cached = null
	if not is_instance_valid(Utils.canvasLayer): return null
	var root = Utils.canvasLayer.get_parent()
	if root == null: return null
	if B11Probe.enabled: B11Probe.fog_scans += 1
	for child in root.get_children():
		if child is FogPierce and _usable(child):
			_cached = child
			if B11Probe.enabled: B11Probe.fog_canvas_hits += 1
			return child
	return null

static func ensure() -> FogPierce:
	var existing = instance()
	if existing != null: return existing
	if not is_instance_valid(Utils.canvasLayer): return null
	var root = Utils.canvasLayer.get_parent()
	if root == null: return null
	var layer = load("res://game/map/FogPierce.gd").new()
	# Above the default canvas that carries the CanvasModulate, and following the camera
	# so producers can keep writing plain world coordinates.
	layer.layer = 1
	layer.follow_viewport_enabled = true
	root.add_child(layer)
	_cached = layer
	return layer

static func discard() -> void:
	_cached = null
	if not is_instance_valid(Utils.canvasLayer): return
	var root = Utils.canvasLayer.get_parent()
	if root == null: return
	for child in root.get_children():
		if child is FogPierce: child.queue_free()

## One entry offered to an already-resolved canvas. The per-entry cap check is deliberately kept
## here rather than hoisted: the whole point of the push ORDER is that a full list may cost the
## decorative core and never the lane, so the cap has to be evaluated between the two.
static func _offer(layer: FogPierce, entry: Dictionary) -> void:
	if B11Probe.enabled: B11Probe.fog_pushes += 1
	if layer.canvas.entries.size() >= FogPierceCanvas.MAX_ENTRIES:
		if B11Probe.enabled: B11Probe.fog_entries_dropped += 1
		return
	if B11Probe.enabled: B11Probe.fog_entries_appended += 1
	layer.canvas.entries.append(entry)

## Single-entry producers (circles) go through here; the canvas is resolved once for the one entry.
static func _push(entry: Dictionary) -> void:
	if not ArenaVisibility.fog_active(): return
	var layer = ensure()
	if layer == null: return
	_offer(layer, entry)

## World-space segment. Push order is a PRIORITY, not an accident: the lane that tells the player
## where a laser is about to fire goes FIRST and the decorative bright core that doubles it goes
## last, so a full list can only ever cost ink and never information. B11.2 keeps that order and
## that guarantee, and resolves the canvas once for the pair instead of once per entry.
static func push_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	if B11Probe.enabled: B11Probe.fog_push_lines += 1
	if not ArenaVisibility.fog_active(): return
	var layer = ensure()
	if layer == null: return
	_offer(layer, {"kind":"line","a":a,"b":b,"color":color,"width":width})
	if B11Probe.iso_fog_core: return
	# A doubled thin core reads as emissive against a near-black far field. Both keys are
	# quoted on purpose: a bare `width:` here created a differently typed key, which made the
	# renderer read a missing property and draw nothing.
	_offer(layer, {"kind":"line","a":a,"b":b,"color":Color(color.r,color.g,color.b,color.a*0.55),"width":width*0.4})

## World-space circle outline.
static func push_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	if B11Probe.enabled: B11Probe.fog_push_lines += 1
	_push({"kind":"circle","a":center,"radius":radius,"color":color,"width":width})

func _ready() -> void:
	_cached = self
	add_to_group(GROUP)
	# combat_transient so LevelServer.return_to_camp() clears it with everything else.
	add_to_group("combat_transient")
	canvas = load("res://game/map/FogPierceCanvas.gd").new()
	canvas.z_index = 40
	add_child(canvas)

func _exit_tree() -> void:
	if _cached == self: _cached = null

func _process(_delta: float) -> void:
	if not ArenaVisibility.fog_active(): queue_free()
