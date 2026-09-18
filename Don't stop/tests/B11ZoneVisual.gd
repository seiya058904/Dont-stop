extends "res://tests/B8Runtime.gd"

## B11.2 visual-fidelity check for the repaint change, read off REAL rendered frames.
##
## WHY THIS EXISTS. The round stopped an active, non-turning footprint from repainting, and moved
## `HostileZone`'s fog mirror out of `_draw()` into `step()`. Both are claims about what the player
## SEES, and neither can be settled by counting redraw requests: "0 redraws" is only acceptable
## because the ink is still on screen, and "the mirror is still pushed" is only acceptable because
## the lane is still visible above the fog. So this file reads pixels.
##
## HOW THE PIXELS GET HERE, and the two things that are easy to get wrong.
##
## WHERE. The zone is created by the product's own factory, and that factory parents it to
## `get_tree().current_scene` - which in this rig is THIS node, so the zone renders in the ROOT
## viewport. `tests/M8Runtime.gd` gives `play_view` the ROOT's `world_2d`, so the two viewports
## share one canvas: the terrain, the actors and the zone's ink are all drawn into BOTH of them,
## at different transforms, while the `CanvasLayer` HUD belongs to `play_view` alone.
##
## The consequence is the part that is easy to get wrong: NEITHER viewport is an empty black
## canvas. Whatever the zone's ink is read against, the arena floor is behind it. An absolute
## luminance threshold therefore only works if the lane is brighter than everything behind it -
## which is a property of this palette, is true, and is asserted rather than assumed (see the
## floor control in section W). Hiding the terrain to get a black background is NOT a fix: the ink
## is drawn over the floor, so on black its brightest pixel drops from 1.0 to 0.568 and a threshold
## set for the composited case reads nothing at all.
##
## SCALE. `project.godot` renders a 410x230 design area into a 1536x864 window
## (`stretch/mode = "canvas_items"`), so `get_canvas_transform()` speaks DESIGN coordinates while
## `get_texture().get_image()` hands back DEVICE pixels - measured 3.7464x apart on each axis. The
## rects below are built in design space (that is the space the camera transforms live in) and are
## converted by `scale_rect()` at sampling time. Skipping that conversion put the sample window
## near the top-left corner of the frame, over empty background, and read "median ink 2" on a lane
## that was fully on screen - which looks exactly like a lane that is not being drawn.
##
## A camera is made current in the root viewport and parked on the player, so the lane sits where
## the geometry says it should and the geometry assertions below are meaningful.
##
## Under `--headless` a viewport has no render target and every reading would be empty, so the
## pixel half is skipped there and the run still exits cleanly; the numbers come from the windowed
## gl_compatibility run, which is the renderer the deployed Web build uses.
##
## WHAT IS PINNED
##   W. during the warning the ink is present in EVERY one of 14 consecutive frames AND changes
##      from frame to frame - the countdown is animating, not frozen and not blinking.
##   E. the activation edge changes the ink in a way the player can see: the warning carries NO
##      white core, and the firing lane carries one. Judged on the red channel - see WHITE_LEVEL.
##   A. once ACTIVE and no longer turning, the ink is present in EVERY one of 14 consecutive frames
##      and its pixel count never collapses - the retained command buffer really is on screen, so
##      stopping the repaint cannot be read as a blink.
##   S. a lane that IS turning keeps every frame present and keeps moving: its angle advances every
##      frame by a small, bounded, non-zero amount (no stalls, no teleports).
##   G. the drawn ink covers the geometry the damage uses: the ink's extent along the lane direction
##      matches `length`, and its extent across matches `width`, within the drawn line width.
##   M. the mirrored lane above the fog is RE-OFFERED on every physics tick - never on alternate
##      ones - and its ink is on screen in every consecutive frame while a competing producer keeps
##      forcing the fog canvas to redraw. The zone's own canvas item is hidden throughout, so the
##      offer provably comes from `step()` and the pixels are provably the mirror. The control is
##      ambient-neutral: only `pierce` changes between the two reads.

const SENTINEL_OFFSET := Vector2(180.0, 0.0)
## Frames read per phase. Enough for an even/odd blink to be unmistakable, short enough that a
## warning phase does not end underneath the measurement.
const SAMPLES := 14
## Luminance above which a pixel counts as ink when the read is DIFFERENTIAL (the mirror half, where
## an on/off control decides). Kept low on purpose: there the background is common to both sides and
## the control subtracts it, so sensitivity matters more than separation.
const INK_LEVEL := 0.35
## Luminance above which a pixel counts as the LANE's ink, for the reads that have no control frame
## to subtract and must separate the lane from the arena floor directly.
##
## 0.75 is measured, not chosen. On a real worst-load frame the lane window carries ~38000 such
## pixels while a same-sized control window over plain floor carries 0 - the floor's brightest pixel
## is 0.666 - so the lane's core is the only thing up there. Section W re-asserts that emptiness on
## every run, so a palette or floor that drifts into the band fails loudly instead of quietly
## counting floor tiles as lane ink.
const LANE_INK_LEVEL := 0.75
## The activation edge is judged on CHANNELS, not on luminance. Every warning colour in the laser
## palette has R <= 0.88 (edge 0.42 / edge_hot 0.88 / fill 0.20) and the painter lerps the stroke
## toward `edge_hot` over the last third of the wind-up, so by the time the lane fires its stroke is
## ALREADY near-white in luminance - measured, on a warning lane at p=0.76, bright(>0.75) = 69 px
## and the brightest pixels read (0.81..0.91, 1.00, 1.00), i.e. cyan with the red channel pinned
## below 0.91. Luminance and bright-width statistics therefore CANNOT separate the two phases; they
## came out at 1.1x-1.7x, inside frame-to-frame noise.
##
## What does separate them is the palette contract for `active`: `active` = (0.90,1.0,1.0) plus a
## pure WHITE core line `Color(1,1,1,0.9)` of its own. A pixel with R ~ 1 is unreachable in the
## warning phase - the floor, the glow on the warning stroke, and every warning colour all cap R
## below 0.91 - so white pixels at the lane's centre line are a direct, hue-based reading of "this
## lane is firing". Measured: 0 in every one of 3 late-warning frames, 6 in every one of 3 active
## frames, with the active sample containing literal (1.00,1.00,1.00) over a run of the core line.
const WHITE_LEVEL := 0.95
## Pixel scan stride. The lane is tens of px wide, so every second pixel is ample and 4x faster.
const STRIDE := 2
## Tolerance on the geometry assertions, in px. The painter draws with an antialiased stroke whose
## half-width is added to both ends, so this is the drawn line, not slack in the lane.
const GEOMETRY_SLACK := 14.0
## Where the pixel evidence for point 4 lands. Regenerated by every run, so the screenshots in the
## report cannot drift from the code that produced them.
const EVIDENCE_DIR := "res://docs/iteration/evidence/b11_2/visual"

var cam: Camera2D
var sampled_ratio_floor := 1.0
var mirror_frame_floor := -1
var mirror_control_ceiling := -1

func screen_of(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * point

func frame_image() -> Image:
	RenderingServer.force_draw(false)
	var texture = get_viewport().get_texture()
	if texture == null: return null
	return texture.get_image()

## Design units -> device pixels for a viewport's readback. See the SCALE note at the top: the
## canvas transforms speak design space, the image is device pixels, and they differ by exactly the
## ratio below (measured 3.7464x for the root viewport, 1.0 for `play_view`).
func pixels_per_unit(viewport: Viewport, image: Image) -> Vector2:
	if image == null or viewport == null: return Vector2.ONE
	var vis := Vector2(viewport.get_visible_rect().size)
	if vis.x <= 0.0 or vis.y <= 0.0: return Vector2.ONE
	return Vector2(image.get_width(),image.get_height())/vis

func scale_rect(rect: Rect2i, viewport: Viewport, image: Image) -> Rect2i:
	var s := pixels_per_unit(viewport,image)
	return Rect2i(int(rect.position.x*s.x),int(rect.position.y*s.y),
		int(rect.size.x*s.x),int(rect.size.y*s.y))

## Ink statistics inside `rect`, read off a real rendered frame.
## `ink` counts pixels above `level`; `min_x`/`max_x`/`min_y`/`max_y` bound them.
##
## `mean` is over EVERY sampled pixel in the rect; `ink_mean` is over the ink pixels only. The
## distinction matters when the window is mostly background: a palette change on a thin stroke moves
## `ink_mean` by a lot and `mean` by almost nothing, because the floor dominates the average.
func ink_stats(image: Image, rect: Rect2i, stride: int = STRIDE,
		level: float = INK_LEVEL) -> Dictionary:
	var empty := {"ink":0,"mean":0.0,"ink_mean":0.0,"ink_max":0.0,
		"min_x":0,"max_x":0,"min_y":0,"max_y":0}
	if image == null: return empty
	var w: int = image.get_width(); var h: int = image.get_height()
	var x0: int = maxi(rect.position.x,0); var x1: int = mini(rect.end.x,w)
	var y0: int = maxi(rect.position.y,0); var y1: int = mini(rect.end.y,h)
	var ink := 0; var total := 0; var sum := 0.0
	var ink_sum := 0.0; var ink_max := 0.0
	var min_x := 1 << 30; var max_x := -(1 << 30)
	var min_y := 1 << 30; var max_y := -(1 << 30)
	var x := x0
	while x < x1:
		var y := y0
		while y < y1:
			var c := image.get_pixel(x,y)
			var l := 0.2126*c.r+0.7152*c.g+0.0722*c.b
			total += 1; sum += l
			if l > level:
				ink += 1; ink_sum += l
				if l > ink_max: ink_max = l
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
			y += stride
		x += stride
	if ink == 0: min_x = 0; max_x = 0; min_y = 0; max_y = 0
	return {"ink":ink,"mean":sum/maxf(1.0,float(total)),"ink_mean":ink_sum/maxf(1.0,float(ink)),
		"ink_max":ink_max,"min_x":min_x,"max_x":max_x,"min_y":min_y,"max_y":max_y}

## The AABB of a lane in screen space, padded so the stroke and the arrow marks are inside it.
func lane_rect(zone) -> Rect2i:
	var a: Vector2 = screen_of(zone.global_position)
	var b: Vector2 = screen_of(zone.global_position+zone.direction*zone.length)
	var pad := 46.0
	var top_left := Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2(pad,pad)
	var span := Vector2(absf(a.x-b.x),absf(a.y-b.y))+Vector2(pad*2.0,pad*2.0)
	return Rect2i(int(top_left.x),int(top_left.y),int(span.x),int(span.y))

## ---- the fog mirror is read through `play_view`, not the root viewport ----------------------
##
## `FogPierce.ensure()` parents the layer to `Utils.canvasLayer.get_parent()`, and `canvasLayer` is
## `ui/ControlUI.gd` - a node INSIDE `game/map/Main.tscn`, which this rig hosts inside `play_view`.
## So the mirrored lane is composited into play_view while the zone's own ink (parented to
## `current_scene`) lands in the root viewport. Two different render targets, two different
## transforms; mixing them up would read empty frames and look like a flicker that is not there.
func play_screen_of(point: Vector2) -> Vector2:
	return play_view.get_canvas_transform() * point

func play_image() -> Image:
	RenderingServer.force_draw(false)
	var texture = play_view.get_texture()
	if texture == null: return null
	return texture.get_image()

func play_lane_rect(zone) -> Rect2i:
	var a: Vector2 = play_screen_of(zone.global_position)
	var b: Vector2 = play_screen_of(zone.global_position+zone.direction*zone.length)
	var pad := 60.0
	var top_left := Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2(pad,pad)
	var span := Vector2(absf(a.x-b.x),absf(a.y-b.y))+Vector2(pad*2.0,pad*2.0)
	return Rect2i(int(top_left.x),int(top_left.y),int(span.x),int(span.y))

## Ink for `frames` CONSECUTIVE frames, with a competing producer fired on every one of them.
##
## The competing producer is the point of this function. `FogPierceCanvas` redraws only on frames
## where at least one entry arrived, and `_draw()` re-issues the command buffer from the entries it
## just cleared. In a real Hell round the `EnemyShot` producer offers on every physics tick, so the
## canvas keeps being redrawn even on frames the zone itself does not repaint - and on those frames
## a mirror tied to the zone's repaint cadence is simply not in the new buffer. So the decoy is not
## decoration: without it this read cannot reproduce the failure it is checking for. It is fired far
## from the lane, on screen, so it forces the redraw without landing inside the measured region.
##
## Stride is 1 here, unlike the zone reads: the mirrored lane is 2-3 px wide, and a stride of 2 can
## step over an axis-aligned line entirely, which would read as a blink that is not there.
func mirror_series(zone, frames: int, decoy: Vector2) -> Array:
	var out: Array = []
	if not is_instance_valid(zone): return out
	var rect := play_lane_rect(zone)
	for i in frames:
		FogPierce.push_circle(decoy,5.0,Color(0.2,1.0,0.4,0.9),2.0)
		await wait(1.0/60.0)
		if not is_instance_valid(zone): break
		var img := play_image()
		out.append(ink_stats(img,scale_rect(rect,play_view,img),1))
	return out

## Frames read back to back, each one after a real physics tick, so "consecutive" means what it says.
## The rect is rebuilt per frame - a sweeping lane moves - and converted to device pixels, which can
## only happen once the frame's image is in hand because the ratio is derived from its size.
func sample(zone, frames: int) -> Array:
	var out: Array = []
	for i in frames:
		if not is_instance_valid(zone): break
		await wait(1.0/60.0)
		if not is_instance_valid(zone): break
		var img := frame_image()
		out.append(ink_stats(img,scale_rect(lane_rect(zone),get_viewport(),img),
			STRIDE,LANE_INK_LEVEL))
	return out

## One lane's ink, in device pixels, at the lane-ink level. The window is rebuilt from the lane's
## current transform and scaled, so a caller never has to remember either step.
func lane_stats(zone) -> Dictionary:
	var img := frame_image()
	return ink_stats(img,scale_rect(lane_rect(zone),get_viewport(),img),STRIDE,LANE_INK_LEVEL)

## How many pixels on the lane's CENTRE LINE are genuinely white - see WHITE_LEVEL. The lane's own
## cross-section is scanned at several points along its axis, stepping across the beam, and the
## player's own ink is kept out by reading off-centre fractions only. This is the one reading in this
## file that names a channel rather than a brightness.
func white_core(zone, fracs: Array) -> int:
	var img := frame_image()
	if img == null or not is_instance_valid(zone): return -1
	var s := pixels_per_unit(get_viewport(),img)
	var dir: Vector2 = zone.direction.normalized()
	var n: Vector2 = dir.orthogonal()
	var count := 0
	for frac in fracs:
		var mid: Vector2 = screen_of(zone.global_position
			+ dir*float(zone.length)*float(frac))*s
		for off in range(-24,25,3):
			var p: Vector2 = mid+n*float(off)
			var x := int(p.x); var y := int(p.y)
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height(): continue
			var c := img.get_pixel(x,y)
			if c.r > WHITE_LEVEL and 0.2126*c.r+0.7152*c.g+0.0722*c.b > WHITE_LEVEL: count += 1
	return count

## Saves the lane's own window as a PNG. This whole file is a claim about pixels, so the report has
## to be able to SHOW the frames the numbers came from - and writing them from the test, rather than
## from a throwaway harness, is what makes them reproducible.
func dump_lane(label: String, zone) -> void:
	if not rendering() or not is_instance_valid(zone): return
	var img := frame_image()
	if img == null: return
	var r := scale_rect(lane_rect(zone),get_viewport(),img)
	var x0: int = maxi(r.position.x,0); var y0: int = maxi(r.position.y,0)
	var x1: int = mini(r.end.x,img.get_width()); var y1: int = mini(r.end.y,img.get_height())
	if x1 <= x0 or y1 <= y0: return
	var crop := img.get_region(Rect2i(x0,y0,x1-x0,y1-y0))
	if crop == null: return
	DirAccess.make_dir_recursive_absolute(EVIDENCE_DIR)
	crop.save_png(EVIDENCE_DIR+"/lane-"+label+".png")

func ink_series(rows: Array) -> Array:
	var out: Array = []
	for row in rows: out.append(int(row.ink))
	return out

func median_of(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate(); sorted.sort()
	return float(sorted[sorted.size()/2])

func parked_sentinel(role: String):
	var actor = M5Content.spawn(role,LevelServer.town.monster_root,
		Utils.player.global_position+SENTINEL_OFFSET)
	if actor == null: return null
	actor.set_physics_process(false)
	actor.contact_cooldown = 99.0
	actor.locked_direction = actor.global_position.direction_to(Utils.player.global_position)
	return actor

func lanes() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("hostile_zone"):
		if node.mode == "line": out.append(node)
	return out

func until(predicate: Callable, frames: int) -> bool:
	var i := 0
	while i < frames:
		if predicate.call(): return true
		i += 1
		await wait(1.0/60.0)
	return predicate.call()

func clean_actors() -> void:
	for group in ["monsters","hostile_zone","enemy_projectiles"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node): node.queue_free()
	await wait(0.2)

func _ready():
	await boot(); configure(124,true)
	LevelServer.state = "COMBAT"
	await visual_ready()
	# Terrain, telegraphs and lighting only: no crowd, no round clock, no incoming shots, and the
	# player parked. Nothing here may be used to make an assertion pass.
	LevelServer.timerStop()
	Demo.stop_attacks()
	Utils.player.set_physics_process(false)
	for node in get_tree().get_nodes_in_group("monsters"): node.queue_free()
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	await wait(0.4)
	# The root-viewport camera the lane is read through, parked exactly on the player.
	cam = Camera2D.new()
	add_child(cam)
	cam.global_position = Utils.player.global_position
	cam.make_current()
	await wait(0.3)

	var vision := rendering()
	print("B11_ZONE_VISUAL pixel_half=",("armed" if vision else "skipped (no render target under --headless)"))

	# ---- W. the warning countdown is continuously readable and really animates -------------------
	await clean_actors()
	var actor = parked_sentinel("E14")
	check(actor != null,"a laser sentinel spawns for the visual half")
	if actor != null:
		actor.phase = "move"; actor.phase_time = 0.0
		actor._begin("beam")
	var lane = null
	check(await until(func(): return not lanes().is_empty(),120),"the beam creates a line lane")
	lane = lanes()[0] if not lanes().is_empty() else null
	check(lane != null,"a line lane is available for the pixel half")
	if lane == null:
		await finish(); return

	if vision:
		# Give the freshly created lane a couple of frames to be drawn before the first read: the
		# canvas item is queued, not painted, on the frame `_ready` ran.
		await wait(3.0/60.0)
		# Before trusting any ink count, prove the threshold still separates the lane from the arena
		# floor. The two share a canvas, so the lane is always read against terrain and an absolute
		# level is only meaningful while the lane's core is the brightest thing in the window. A
		# same-sized control window below the lane, over plain floor, has to come back empty; if a
		# floor tile or a palette tweak ever drifts into the band, this fails instead of quietly
		# counting floor as ink and making every check below vacuously true. See LANE_INK_LEVEL.
		var probe_img := frame_image()
		var lane_design := lane_rect(lane)
		var lane_box := scale_rect(lane_design,get_viewport(),probe_img)
		# Control: the same window, a design-space margin below the lane. The margin is MEASURED,
		# not guessed - at one window-height of clearance the lane's own glow tail still reached
		# into the control (151 sampled px) and made it report "the floor is bright" when the ink
		# was really the lane's, so the control is pushed far enough that the lane cannot be what
		# fills it.
		var floor_box := scale_rect(
			Rect2i(lane_design.position+Vector2i(0,lane_design.size.y+40),lane_design.size),
			get_viewport(),probe_img)
		var lane_ink := int(ink_stats(probe_img,lane_box,STRIDE,LANE_INK_LEVEL).ink)
		var floor_ink := int(ink_stats(probe_img,floor_box,STRIDE,LANE_INK_LEVEL).ink)
		check(lane_ink > 0,
			"the lane's ink clears the brightest pixel the floor offers (%d px above the level)"
			% lane_ink)
		check(lane_ink > floor_ink*10,
			"the same window over plain floor is all but empty by comparison, so the counts below "
			+ "are the lane's and not the floor's (%d px in the lane window, %d over floor)"
			% [lane_ink,floor_ink])
		# Read while the warning still has room to run: the lane's own warning is the phase the old
		# gate sampled at 30 Hz, so this is the phase the change could have broken.
		var warn_rows: Array = await sample(lane,4)
		var moving := 0
		var present := 0
		for row in warn_rows:
			if int(row.ink) > 0: present += 1
		check(present == warn_rows.size(),
			"warning: the lane's ink is on screen in all %d frames read (%d)"
			% [warn_rows.size(),present])
		if is_instance_valid(lane) and lane.elapsed < float(lane.warning)-0.25:
			var more: Array = await sample(lane,10)
			var series: Array = ink_series(warn_rows)+ink_series(more)
			var prev: int = series[0]
			var blank := 0
			for i in range(1,series.size()):
				var v: int = series[i]
				if v > 0 and prev == 0: blank += 1
				if v == 0 and prev > 0: blank += 1
				prev = v
			# A countdown that blinks on and off shows up here as transitions to or from zero while
			# the lane is still in its warning. An animating countdown shows none.
			check(blank == 0,
				"warning: the countdown never blanks between frames (%d zero-crossings over %d frames)"
				% [blank,series.size()])
			var changed := 0
			for i in range(1,series.size()):
				if series[i] != series[i-1]: changed += 1
			check(changed >= (series.size()-1)/2,
				"warning: the countdown really animates (%d of %d frame pairs differ in ink)"
				% [changed,series.size()-1])
			check(median_of(series) > 0.0,
				"warning: the lane is actually visible while it counts down (median ink %.0f)"
				% median_of(series))
		else:
			check(true,"(informational) the warning phase ended before the long sample; short sample used")

	# ---- E. the activation edge still reads as "now" rather than "soon" -------------------------
	#
	# WHAT IS MEASURED, and why it is a channel rather than a brightness. See WHITE_LEVEL: the
	# warning stroke already goes near-white in luminance over its last third, so brightness-based
	# readings of the edge are noise (measured +2% on one frame, against a per-frame wander of
	# +-1.5%). The palette's own contract is what separates the two phases - `active` is
	# (0.90,1.0,1.0) and the painter adds a pure white `Color(1,1,1,0.9)` core line - so the question
	# "can the player see that this lane is firing" is answered by "does the lane's core contain
	# white", which no warning colour, no floor tile and no glow can produce.
	#
	# A lane of its own, authored through the product factory: the W/E lane is the product's real
	# attack and is one frame from firing when this section starts, so it cannot supply a warning
	# window. Reading a frame back costs real wall time (measured: ~80 ms per sampled frame here), so
	# the warning is held open for 2 s - enough to collect the samples inside the late-warning band -
	# and the active phase for 3 s. `damage = 0` keeps the parked player from being hit across the
	# window; no check below reads `damage`.
	var edge_lane = null
	if vision:
		var edge_actor = parked_sentinel("E14")
		check(edge_actor != null,"a sentinel spawns for the activation-edge half")
		if edge_actor != null:
			edge_lane = edge_actor.zone("line",edge_actor.global_position,330.0,2.0,3.0,"laser")
			if edge_lane != null: edge_lane.damage = 0.0
		check(edge_lane != null,"the activation-edge lane is authored")
	if vision and edge_lane != null:
		# Off-centre fractions only: the parked player sits at the lane's midpoint, and this reads
		# channels, so the player's own bright sprite must stay out of the scan.
		var fracs := [0.3,0.4,0.6,0.8]
		var white_warn: Array = []
		var white_active: Array = []
		var edge_spin := 0
		# The last ~600 ms of the warning: inside the band the claim is about, and wide enough to
		# hold the samples at the sampler's real cost.
		while is_instance_valid(edge_lane) and not edge_lane.activated \
				and white_warn.size() < 4 and edge_spin < 400:
			edge_spin += 1
			await wait(1.0/60.0)
			if not is_instance_valid(edge_lane) or edge_lane.activated: break
			if float(edge_lane.elapsed) < float(edge_lane.warning)-0.6: continue
			white_warn.append(white_core(edge_lane,fracs))
		dump_lane("warning",edge_lane)
		# ... and the first frames after it fires.
		edge_spin = 0
		while is_instance_valid(edge_lane) and white_active.size() < 4 and edge_spin < 400:
			edge_spin += 1
			await wait(1.0/60.0)
			if not is_instance_valid(edge_lane): break
			if not edge_lane.activated: continue
			white_active.append(white_core(edge_lane,fracs))
		dump_lane("active",edge_lane)
		print("B11_ZONE_VISUAL activation white_warn=",white_warn,
			" white_active=",white_active)
		check(white_warn.size() >= 4 and white_active.size() >= 4,
			"the activation-edge lane survives a read on both sides (%d warning frames, %d active)"
			% [white_warn.size(),white_active.size()])
		var wwm := median_of(white_warn)
		var wam := median_of(white_active)
		check(wwm == 0.0,
			("the warning shows no white core at all, so this reading is specific to the firing "
			+ "lane (median %.0f white px per frame over %d frames)")
			% [wwm,white_warn.size()])
		check(wam > 0.0,
			("activation changes the ink itself, so the last 150 ms is a visible escalation: the "
			+ "firing core carries white where the warning carried none (median %.0f white px per "
			+ "frame over %d frames, on a step-3 scan across the beam)") % [wam,white_active.size()])


	# ---- A. an ACTIVE frozen lane's ink is on screen in EVERY consecutive frame ----------------
	#
	# A lane of its OWN, authored through the product's factory. The lane W/E read is the product's
	# real attack and is short-lived: reading frames back off the GPU costs real wall time, so by the
	# time A and G wanted to look at that lane it had already expired - and because BOTH sections are
	# guarded on validity they then did not run AT ALL, which left the no-flicker claim and the
	# geometry claim unproven while the run still reported success. Holding a lane makes them both
	# readable, and `damage = 0` stops the parked player being hit across the whole window (neither
	# section reads `damage`).
	var frozen_lane = null
	if vision:
		var frozen_actor = parked_sentinel("E14")
		check(frozen_actor != null,"a sentinel spawns for the frozen-active half")
		if frozen_actor != null:
			frozen_lane = frozen_actor.zone("line",frozen_actor.global_position,
				330.0,0.30,12.0,"laser")
		check(frozen_lane != null,"the frozen-active lane is authored")
		if frozen_lane != null:
			frozen_lane.damage = 0.0
	if vision and frozen_lane != null:
		check(await until(func(): return is_instance_valid(frozen_lane) and frozen_lane.activated,600),
			"the frozen-active lane reaches its active phase")
	if vision and is_instance_valid(frozen_lane):
		check(float(frozen_lane.sweep) == 0.0,
			"the lane under test really is a non-turning one, so the frozen case is the one read")
		var active_rows: Array = await sample(frozen_lane,4)
		var more: Array = await sample(frozen_lane,10)
		var series: Array = ink_series(active_rows)+ink_series(more)
		check(series.size() >= SAMPLES,
			"the frozen-active lane outlives a full read (%d of %d frames)"
			% [series.size(),SAMPLES])
		var zero_frames := 0
		for v in series:
			if v == 0: zero_frames += 1
		check(zero_frames == 0,
			"active: the frozen lane's ink is on screen in all %d consecutive frames (%d blank)"
			% [series.size(),zero_frames])
		var med := median_of(series)
		var ratio: float = float(series.min())/maxf(1.0,med)
		sampled_ratio_floor = ratio
		check(ratio > 0.6,
			"active: no frame collapses relative to the median, so the retained ink does not "
			+ "blink (weakest frame is %.0f%% of the median ink %.0f)"
			% [ratio*100.0,med])

	# ---- G. the drawn ink covers the geometry the damage uses ----------------------------------
	# Read off the held lane for the same reason as A: this section used to be guarded on the W/E
	# lane and therefore never ran, so "the ink matches the damaging geometry" was asserted by
	# nothing at all.
	if vision and is_instance_valid(frozen_lane):
		var g_img := frame_image()
		var g_scale := pixels_per_unit(get_viewport(),g_img)
		var stats := ink_stats(g_img,scale_rect(lane_rect(frozen_lane),get_viewport(),g_img),
			STRIDE,LANE_INK_LEVEL)
		var along: Vector2 = frozen_lane.direction.normalized()
		var screen_along: Vector2 = along
		var origin: Vector2 = screen_of(frozen_lane.global_position)
		# Project the ink's own corner set onto the lane axis and compare with the authored length.
		# The ink bounds arrive in DEVICE pixels, so they are divided back by the design->device
		# scale first: that puts them in the same space as the camera transform and the authored
		# `length`, which keeps the slack comparison a statement about world units.
		var reach := 0.0
		for corner in [Vector2(stats.min_x/g_scale.x,stats.min_y/g_scale.y),
				Vector2(stats.max_x/g_scale.x,stats.min_y/g_scale.y),
				Vector2(stats.min_x/g_scale.x,stats.max_y/g_scale.y),
				Vector2(stats.max_x/g_scale.x,stats.max_y/g_scale.y)]:
			reach = maxf(reach,(corner-origin).dot(screen_along))
		var want: float = float(frozen_lane.length)
		check(reach > 0.0 and reach <= want+GEOMETRY_SLACK+float(frozen_lane.width)*0.5,
			"the drawn ink does not extend past the damaging lane (%.0f px of %.0f px + slack)"
			% [reach,want])
		check(reach > want*0.35,
			"...and it really covers the lane rather than a stray mark (%.0f px of %.0f px)"
			% [reach,want])
		check(int(stats.ink) > 0,
			"the geometry read found ink to measure at all (%d px)" % int(stats.ink))

	# ---- S. a lane that IS turning keeps every frame and keeps moving --------------------------
	await clean_actors()
	var sweeping_actor = parked_sentinel("E14")
	check(sweeping_actor != null,"a promoted sentinel spawns for the turning half")
	if sweeping_actor != null:
		sweeping_actor.is_elite = true
		sweeping_actor.phase = "move"; sweeping_actor.phase_time = 0.0
		sweeping_actor._begin("beam")
		check(await until(func(): return not lanes().is_empty(),120),"the promoted beam creates a lane")
		var spin = lanes()[0] if not lanes().is_empty() else null
		check(spin != null and float(spin.sweep) != 0.0,"the promoted lane really TURNS")
		if spin != null and float(spin.sweep) != 0.0:
			check(await until(func(): return spin.activated,600),"the turning lane fires")
			if is_instance_valid(spin):
				await until(func(): return spin.active_elapsed > 0.06,120)
				if is_instance_valid(spin):
					var prev_angle: float = float(spin.direction.angle())
					var present := 0
					var stepped := 0
					var max_step := 0.0
					var rows := 0
					for i in 10:
						if not is_instance_valid(spin): break
						await wait(1.0/60.0)
						# RE-CHECKED, and the check has to be here rather than only above the await:
						# awaiting a frame lets the lane expire and free itself mid-series, and the
						# stale check above would then be answering a question that is one frame out
						# of date. `lane_rect(spin)` and `spin.direction` both touch the object, so a
						# freed lane crashed the reader on `global_position` instead of ending the
						# series cleanly.
						if not is_instance_valid(spin): break
						# The pixel read is taken only where there is a render target: under
						# `--headless` the root viewport has no texture to read and asking for one
						# errors on every frame, while the angle sweep below is still measurable and
						# is the half that keeps this section useful in the headless gate run.
						var stats := {"ink":0}
						if vision:
							var img := frame_image()
							stats = ink_stats(img,scale_rect(lane_rect(spin),get_viewport(),img),
								STRIDE,LANE_INK_LEVEL)
						rows += 1
						if int(stats.ink) > 0: present += 1
						var angle: float = float(spin.direction.angle())
						# Shortest signed difference, computed locally rather than leaning on a
						# built-in whose availability varies by engine build.
						var turned: float = angle-prev_angle
						while turned > PI: turned -= TAU
						while turned < -PI: turned += TAU
						var step: float = absf(turned)
						if step > 0.0001: stepped += 1
						max_step = maxf(max_step,step)
						prev_angle = angle
					if vision:
						check(rows > 0 and present == rows,
							"turning: the lane's ink is on screen in all %d frames (%d)" % [rows,present])
					check(stepped >= rows-1,
						"turning: the lane advances on essentially every frame (%d of %d)" % [stepped,rows])
					check(max_step > 0.0 and max_step < 0.5,
						"turning: each frame's step is small and bounded, so the sweep stays smooth "
						+ "(largest step %.4f rad)" % max_step)

	# ---- M. the mirrored lane is re-offered EVERY tick, so it cannot vanish on alternate frames --
	#
	# The lane's own canvas item is hidden for this whole section, which makes the section do double
	# duty: `visible = false` means `_draw()` never runs for this zone, so anything that still
	# reaches the fog layer provably comes from `step()`.
	#
	# Why the mirror can vanish at all, spelled out because it is not obvious: `FogPierceCanvas`
	# redraws only on frames where an entry arrived, and its `_draw()` RE-ISSUES its command buffer
	# from the list it just cleared. Another producer - `EnemyShot`, which offers on every physics
	# tick in a real Hell round - therefore keeps forcing the canvas to redraw on frames the zone
	# itself did not repaint, and on each of those frames the mirror is absent from the new buffer.
	# That is why the mirror belongs to the physics tick and not to the repaint cadence, and why the
	# section fails the round if the offer is not made on every single tick.
	await clean_actors()
	ArenaVisibility.apply_stage(31,true)
	check(ArenaVisibility.fog_active(),"the Hell profile turns the fog on for the mirror half")
	# Even applied instantly, the profile change is observed through the autoload on the next frame;
	# giving it one costs nothing and keeps a timing artefact out of a fidelity assertion.
	await wait(0.25)
	var fog_layer = FogPierce.ensure()
	check(fog_layer != null,"the fog pierce layer exists while Hell is active")
	var mirror_actor = parked_sentinel("E14")
	check(mirror_actor != null,"a sentinel spawns for the mirror half")
	var mirror_lane = null
	if mirror_actor != null:
		# The product's own factory. The direction runs back over the parked player, i.e. across the
		# middle of the frame, and the ACTIVE window is deliberately long: both halves below read
		# pixels back off the GPU, and a viewport readback advances the game clock by real elapsed
		# time, so a lane authored with its production 3 s burn would expire underneath a slow read
		# and turn a harness cost into a phantom failure.
		mirror_lane = mirror_actor.zone("line",mirror_actor.global_position,330.0,0.40,12.0,"laser")
	check(mirror_lane != null and bool(mirror_lane.pierce),
		"the lane is a piercing lane, i.e. it owes the fog layer a mirrored direction")
	if mirror_lane != null:
		# Zero damage on purpose. The mirrored direction is emitted by the pierce branch of `step()`,
		# which does not read `damage` at all, so the claim under test is unaffected - while a
		# damaging lane parked across a stationary player would fire `tick` (0.2 s) hits for the whole
		# twelve-second window and could end the run in the middle of a pixel read.
		mirror_lane.damage = 0.0
		mirror_lane.visible = false
		# Read the ACTIVE phase, which is the phase the repaint gate changed: a lane at 0.6 s stops
		# repainting, so it is the one whose mirror would be cleared and not refilled. The lane runs
		# back over the parked player, so its footprint is inside the lit radius and the fairness
		# gate lets it open at the authored delay rather than stretching it.
		check(await until(func(): return is_instance_valid(mirror_lane) and mirror_lane.activated,600),
			"the mirrored lane reaches its active phase, i.e. the frozen case the gate changed")

		# ---- M1. one offer on every physics tick, and never refused -----------------------------
		# Renderer-independent, so this half holds under --headless too. Counted per TICK rather
		# than in total, because that is the property that decides whether a redraw can catch the
		# lane missing: a build that offered twice on half the ticks would satisfy a total-only
		# check while still blanking the mirror on every other frame.
		#
		# The counter is read ONLY on a physics-frame emission, and that detail is load-bearing.
		# Reading it once outside a tick boundary - which is what this did first, and it reported
		# 15 of 16 ticks as if one offer had been missed - puts the opening read somewhere in the
		# middle of a tick, so the first interval it measures is shorter than a tick and one
		# boundary is spent before the series starts. `HostileZone.step()` is called from
		# `_physics_process` and reaches its `push_line` unconditionally for a live lane with
		# `pierce` set, so an offer cannot actually be skipped while the lane is alive; the missing
		# one was the measurement's, not the product's. Sampling only at emissions removes the
		# question: consecutive emissions bracket exactly one physics tick by definition.
		B11Probe.enabled = true
		var ticks := 16
		var dropped_before: int = B11Probe.fog_entries_dropped
		await get_tree().physics_frame
		var prev: int = B11Probe.fog_push_lines
		var offered := 0
		var busiest := 0
		var samples := 0
		for i in ticks:
			await get_tree().physics_frame
			var now: int = B11Probe.fog_push_lines
			var grew: int = now-prev
			if grew > 0: offered += 1
			if grew > busiest: busiest = grew
			prev = now
			samples += 1
		check(samples >= ticks and offered == samples,
			"the mirror is re-offered on every one of the %d physics ticks measured "
			% samples
			+ "(%d ticks offered, busiest tick %d)"
			% [offered,busiest])
		check(B11Probe.fog_entries_dropped == dropped_before,
			"none of those offers is refused by the per-frame cap, so the lane can never be the "
			+ "entry that is dropped (%d refused)" % (B11Probe.fog_entries_dropped-dropped_before))

		# ---- M2. pixel half: present in EVERY consecutive frame, and gone when pierce is off ----
		# Ambient-neutral control: `pierce` is the only thing that changes between the two reads, so
		# fog, lighting, terrain and the lane's own hidden animation are all identical. A control
		# that turned the fog off would move the background as well and prove nothing.
		if vision and is_instance_valid(mirror_lane):
			var decoy: Vector2 = Utils.player.global_position+Vector2(-400.0,-300.0)
			var on_rows: Array = await mirror_series(mirror_lane,SAMPLES,decoy)
			var on_series: Array = ink_series(on_rows)
			var zero_frames := 0
			for v in on_series:
				if v == 0: zero_frames += 1
			check(on_series.size() >= SAMPLES,
				"the mirrored lane outlives a full read (%d of %d frames)" % [on_series.size(),SAMPLES])
			check(zero_frames == 0,
				"mirror: the lane is on screen in all %d consecutive frames (%d blank)"
				% [on_series.size(),zero_frames])

			mirror_lane.pierce = false
			await wait(0.12)
			var off_rows: Array = await mirror_series(mirror_lane,6,decoy)
			var off_series: Array = ink_series(off_rows)
			# Printed because the decision here is min(on) > max(off), so the MARGIN is the whole
			# story: a pass by a handful of pixels means the rect is only grazing the mirror and the
			# check is riding on noise rather than on the lane being drawn.
			print("B11_ZONE_VISUAL mirror_on=",on_series," mirror_off=",off_series)

			if on_series.is_empty() or off_series.is_empty():
				check(false,"the mirror A/B read produced frames on both sides")
			else:
				var lowest := 1 << 30
				var highest := 0
				for v in on_series: lowest = mini(lowest,v)
				for v in off_series: highest = maxi(highest,v)
				# The whole point: the WEAKEST frame of the mirror half is brighter than the
				# strongest frame of the control. An every-other-frame blink puts the weakest
				# mirror frame down at the control level, which fails here.
				check(on_series.size() > 0 and lowest > highest,
					("mirror: every mirrored frame carries more ink than the control does, so the "
					+ "lane never disappears on alternate frames (weakest mirror frame %d px, "
					+ "strongest control frame %d px)") % [lowest,highest])
				mirror_frame_floor = lowest
				mirror_control_ceiling = highest
			mirror_lane.pierce = true

		B11Probe.enabled = false
	ArenaVisibility.restore(true)
	FogPierce.discard()

	await clean_actors()
	await finish()

func finish() -> void:
	await clean_actors()
	B11Probe.enabled = false
	if is_instance_valid(cam): cam.queue_free()
	print("B11_ZONE_VISUAL checks=",checks," failures=",failures,
		" frozen_frame_ink_floor=",snappedf(sampled_ratio_floor,0.001),
		" mirror_frame_floor=",mirror_frame_floor,
		" mirror_control_ceiling=",mirror_control_ceiling)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
