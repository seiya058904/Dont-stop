extends "res://tests/M8Runtime.gd"

## Shared rig for the B批 visual and measurement audits.
##
## Harness note (read this before trusting any brightness number): in the native rig
## Utils.get_aim_world_position() resolves against the ROOT viewport, so the aim lands near
## the world origin while the arena sits at (10000+N*1000,-6000). Camera2D._process() then
## chases a runaway lead, and because the retained fog light is a CHILD of that camera it is
## dragged thousands of pixels away from the player. That is purely an artefact of the test
## window; in a real session the light is locked to the screen centre. This rig freezes the
## chase and renders through a camera placed on the player, which reproduces the production
## relationship (player -> light) instead of the artefact.

var world: Node
var game_camera: Camera2D
var render_camera: Camera2D
var anchor: Node2D

func visual_ready(size := Vector2i(960,720)) -> void:
	world = play_view.get_child(0)
	play_view.size = size
	game_camera = world.get_node_or_null("Town/TileMap2/PlayerRoot/Anchor/Camera2D")
	anchor = world.get_node_or_null("Town/TileMap2/PlayerRoot/Anchor")
	if game_camera != null:
		game_camera.set_process(false)
		game_camera.position = Vector2.ZERO
	await settle_anchor()
	if is_instance_valid(render_camera):
		recenter()
		return
	render_camera = Camera2D.new()
	play_view.add_child(render_camera)
	render_camera.global_position = Utils.player.global_position
	render_camera.make_current()

func settle_anchor() -> void:
	for i in 600:
		await get_tree().physics_frame
		if is_instance_valid(anchor) and anchor.global_position.distance_to(Utils.player.global_position) < 10.0: return

func recenter() -> void:
	if is_instance_valid(render_camera) and is_instance_valid(Utils.player):
		render_camera.global_position = Utils.player.global_position

## Stops the round clock and clears actors so a screenshot shows terrain, telegraphs and
## lighting without a moving crowd. Never used to make an assertion pass.
func freeze_room() -> void:
	LevelServer.timerStop()
	Demo.stop_attacks()
	Utils.player.set_physics_process(false)
	for node in get_tree().get_nodes_in_group("monsters"): node.queue_free()
	for node in get_tree().get_nodes_in_group("combat_transient"):
		if node.get_script() == load("res://game/monster/EnemyShot.gd"): node.queue_free()
	await wait(0.3)

const EVIDENCE := "res://docs/iteration/evidence/b"

## True when the run can actually read pixels. A SubViewport under `--headless` has its
## render target disabled, so profile()/snap() return nothing. Scenes that produce visual
## evidence therefore skip the pixel half in a headless gate run and still assert every
## programmatic contract, and the render run (gl_compatibility, the renderer Web uses) is
## where the screenshots and the luminance numbers come from.
func rendering() -> bool:
	return DisplayServer.get_name() != "headless"

## Reads back a frame that really contains the state the caller just changed. A SubViewport's
## texture is one or more frames behind a state mutation, so a screenshot taken immediately
## after writing `elapsed` silently repeats the PREVIOUS state - which is exactly what made
## three different telegraph states hash identically before this existed.
func settle_render(frames := 3) -> void:
	if not rendering(): return
	for i in frames:
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame

func snap(label: String) -> void:
	if not rendering(): return
	RenderingServer.force_draw(false)
	var texture = play_view.get_texture()
	if texture == null: return
	var image = texture.get_image()
	if image == null: return
	if play_view.size.x == 960: image.resize(1366,768,Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
	image.save_png(EVIDENCE+"/"+label+".png")

## Radial luminance profile: band i is the mean luminance of band i*48 px from the screen
## centre outwards. This is the measurement behind every "Fog is on / the radius is N px"
## statement in the report - it is read off the actual rendered frame.
func profile() -> Array:
	var empty = []
	for i in 12: empty.append(0.0)
	if not rendering(): return empty
	RenderingServer.force_draw(false)
	var texture = play_view.get_texture()
	if texture == null: return empty
	var image = texture.get_image()
	if image == null: return empty
	var size = image.get_size()
	var center = Vector2(size)*0.5
	var sums = []
	var counts = []
	for i in 12: sums.append(0.0); counts.append(0)
	for x in range(0,size.x,4):
		for y in range(0,size.y,4):
			var c = image.get_pixel(x,y)
			var l = 0.2126*c.r+0.7152*c.g+0.0722*c.b
			var band = mini(11,int(Vector2(x,y).distance_to(center)/48.0))
			sums[band] += l; counts[band] += 1
	var out = []
	for i in 12: out.append(sums[i]/maxi(1,counts[i]))
	return out

## World-pixel radius the light makes READABLE, as the last band whose luminance is at least
## twice the outermost band's. An absolute floor is not usable here: the arena rim and the
## region accent frame sit just outside the playfield and read brighter than the fogged floor,
## so a fixed threshold would report the whole screen as "visible" in both modes.
func readable_radius(bands: Array) -> int:
	if bands.is_empty(): return 0
	var floor = maxf(bands[bands.size()-1]*2.0,0.03)
	var edge = 0
	for i in bands.size():
		if bands[i] > floor: edge = (i+1)*48
	return edge

func band_text(bands: Array) -> String:
	var parts = []
	for value in bands: parts.append("%.3f" % value)
	return " ".join(parts)
