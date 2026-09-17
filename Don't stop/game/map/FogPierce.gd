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

static func instance() -> FogPierce:
	if not is_instance_valid(Utils.canvasLayer): return null
	var root = Utils.canvasLayer.get_parent()
	if root == null: return null
	for child in root.get_children():
		if child is FogPierce: return child
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
	return layer

static func discard() -> void:
	if not is_instance_valid(Utils.canvasLayer): return
	var root = Utils.canvasLayer.get_parent()
	if root == null: return
	for child in root.get_children():
		if child is FogPierce: child.queue_free()

## Push order is a PRIORITY, not an accident. Each frame's list is capped, so when a crowded Hell
## stage fills it the last pushes are the ones that are dropped. The two-kilometre beam lane that
## tells the player where a laser is about to fire therefore goes FIRST, and the decorative bright
## core that doubles it goes last, so the cap can only ever cost ink and never information.
static func _push(entry: Dictionary) -> void:
	if not ArenaVisibility.fog_active(): return
	var layer = ensure()
	if layer == null: return
	if layer.canvas.entries.size() >= FogPierceCanvas.MAX_ENTRIES: return
	layer.canvas.entries.append(entry)

## World-space segment.
static func push_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	_push({"kind":"line","a":a,"b":b,"color":color,"width":width})
	# A doubled thin core reads as emissive against a near-black far field. Both keys are
	# quoted on purpose: a bare `width:` here created a differently typed key, which made the
	# renderer read a missing property and draw nothing.
	_push({"kind":"line","a":a,"b":b,"color":Color(color.r,color.g,color.b,color.a*0.55),"width":width*0.4})

## World-space circle outline.
static func push_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	_push({"kind":"circle","a":center,"radius":radius,"color":color,"width":width})

func _ready() -> void:
	add_to_group(GROUP)
	# combat_transient so LevelServer.return_to_camp() clears it with everything else.
	add_to_group("combat_transient")
	canvas = load("res://game/map/FogPierceCanvas.gd").new()
	canvas.z_index = 40
	add_child(canvas)

func _process(_delta: float) -> void:
	if not ArenaVisibility.fog_active(): queue_free()
