extends "res://tests/M8Runtime.gd"

## B11.2 `FogPierce` canvas-cache lifetime.
##
## WHY THIS EXISTS. `FogPierce` is the information layer that keeps a long beam or a sweeping laser
## readable from inside Hell darkness. B11.2 removed a measured redundancy from it: `push_line`
## offers TWO entries per logical line (the lane, then its decorative core) and each offer used to
## re-resolve the canvas by scanning every child of the world root, so one line cost two scans -
## 85,664 scans for 43,245 lines in a 45 s run. The resolved layer is now held in a `static var`.
##
## A static reference to a Node outlives every scene in the game, and this layer sits on the
## fairness path, so "does the cache ever hand back the wrong canvas" is not a micro-optimisation
## question. This test answers it against the real lifecycle events, not against a mock:
##
##   1. no fog           -> no canvas exists and `instance()` says so;
##   2. Hell combat      -> a canvas appears, and it is REUSED: repeated pushes add zero scans;
##   3. `queue_free()`   -> the condemned canvas is never handed back inside the same frame, which
##                          is the window `is_instance_valid()` alone leaves open (`queue_free`
##                          defers) and `is_queued_for_deletion()` closes;
##   4. after the frame  -> the freed canvas is gone and `instance()` is null, not dangling;
##   5. a NEW round      -> gets a NEW canvas, by instance id;
##   6. camp return      -> the canvas self-retires, the cache is cleared by `_exit_tree`, and no
##                          reference survives;
##   7. back to Hell     -> a fresh canvas is found again, so nothing was remembered;
##   8. immediate free() -> the `is_instance_valid` arm of the guard is exercised on its own;
##   9. arithmetic       -> the canvas drains exactly the entries it was offered, so the push
##                          volume the AFTER report is judged on is the volume that was drawn.
##
## The fog state is driven through the product's own `ArenaVisibility`, so `fog_active()` and the
## producers' own gates are the real ones.

var checks_before_drain := 0

func finish_cleanup() -> void:
	LevelServer.state = "CAMP"
	FogPierce.discard()
	await wait(0.2)

func _ready():
	B11Probe.enabled = true
	await boot(); configure(124,true)
	var town = LevelServer.town

	# ---- 1. no fog -> no canvas ---------------------------------------------------------------
	check(not ArenaVisibility.fog_active(),"camp has no fog")
	check(FogPierce._cached == null,"the cache starts empty")
	check(FogPierce.instance() == null,"with no fog there is no canvas to hand out")

	# ---- 2. enter Hell combat and reuse the canvas --------------------------------------------
	LevelServer.state = "COMBAT"
	ArenaVisibility.apply_stage(31)
	await wait(0.8)
	check(ArenaVisibility.fog_active(),"a Hell stage with a live COMBAT state turns fog on")
	var canvas = FogPierce.ensure()
	check(canvas != null,"ensure() creates the canvas")
	if canvas == null:
		await finish_cleanup(); await finish(); return
	var first_id: int = canvas.get_instance_id()
	check(canvas.is_inside_tree(),"...and it is in the live tree")
	check(FogPierce._cached == canvas,
		"`_ready` publishes the canvas, so the very first push needs no scan at all")

	var scans_before: int = B11Probe.fog_scans
	for i in 6: FogPierce.instance()
	check(B11Probe.fog_scans == scans_before,
		"repeated resolutions add ZERO child scans (%d -> %d)" % [scans_before,B11Probe.fog_scans])

	var hits_before: int = B11Probe.fog_canvas_hits
	# Snapshotted BEFORE the pushes, so the drain arithmetic below really covers them. Taking it
	# after was the first version's bug: `_offer` increments the accepted counter synchronously, so
	# the delta read as zero while the drawn counter still moved on the next idle frame.
	var ap_before: int = B11Probe.fog_entries_appended
	var dr_before: int = B11Probe.fog_entries_dropped
	var dw_before: int = B11Probe.fog_entries_drawn
	var a := Vector2(0,0); var b := Vector2(120,0)
	for i in 5: FogPierce.push_line(a+Vector2(i*4,0),b+Vector2(i*4,0),Color(1,0.66,0.22,0.6),2.0)
	check(B11Probe.fog_scans == scans_before,
		"the producers' own push path adds no scan either (%d scans)" % B11Probe.fog_scans)
	check(B11Probe.fog_canvas_hits >= hits_before+5,
		"...and every one of the 5 lines was served from the cache (+%d)"
		% [B11Probe.fog_canvas_hits-hits_before])

	# ---- 9. the canvas drains exactly what it was offered -------------------------------------
	await wait(0.25)
	var appended: int = B11Probe.fog_entries_appended-ap_before
	var dropped: int = B11Probe.fog_entries_dropped-dr_before
	var drawn: int = B11Probe.fog_entries_drawn-dw_before
	check(appended == 10,"each of the 5 pushed lines offered exactly two entries (%d)" % appended)
	check(drawn == appended-dropped,
		"the canvas drew every entry it accepted and no more (%d drawn = %d accepted - %d dropped)"
		% [drawn,appended,dropped])

	# ---- 3. a condemned canvas is never handed back -------------------------------------------
	canvas.queue_free()
	check(is_instance_valid(canvas),
		"`queue_free()` defers, so the condemned canvas is still a VALID object this frame")
	check(FogPierce.instance() == null,
		"...and it is still NOT handed back inside that frame (the window `is_instance_valid` "
		+ "alone leaves open)")
	check(FogPierce.instance() == null,
		"...and nothing else is invented to replace it")

	# ---- 4. after the frame, it is really gone ------------------------------------------------
	await wait(0.25)
	check(not is_instance_valid(canvas),"the freed canvas is reclaimed")
	check(FogPierce.instance() == null,"and the cache did not keep a dangling reference to it")

	# ---- 5. a new round gets a new canvas -----------------------------------------------------
	var canvas2 = FogPierce.ensure()
	check(canvas2 != null,"a later round creates its own canvas")
	check(canvas2 != null and canvas2.get_instance_id() != first_id,
		"...which is a genuinely NEW node, not the one that died")
	var second_id: int = canvas2.get_instance_id() if canvas2 != null else 0

	# ---- 6. camp return retires it and clears the cache ---------------------------------------
	LevelServer.state = "CAMP"
	await wait(0.4)
	check(not is_instance_valid(canvas2),
		"the canvas retires itself when fog goes away (its own `_process`)")
	check(FogPierce._cached == null,
		"`_exit_tree` cleared the cache, so nothing outlives the round")
	check(FogPierce.instance() == null,
		"a camp return leaves no stale canvas behind")
	check(not ArenaVisibility.fog_active(),"...and fog really is off")

	# ---- 7. back to Hell finds a fresh canvas --------------------------------------------------
	LevelServer.state = "COMBAT"
	ArenaVisibility.apply_stage(38)
	await wait(0.3)
	var canvas3 = FogPierce.ensure()
	check(canvas3 != null,"returning to Hell resolves a canvas again")
	check(canvas3 != null and canvas3.get_instance_id() != second_id,
		"...and it is not the previous round's node (%d vs %d)"
		% [canvas3.get_instance_id() if canvas3 != null else 0,second_id])

	# ---- 8. the is_instance_valid arm, on an immediate free -----------------------------------
	# Compared by instance id, not by `!=`: a freed Object compares equal to null in GDScript, so a
	# direct `instance() != canvas` can read as satisfied for the wrong reason.
	if canvas3 != null:
		var dead_id: int = canvas3.get_instance_id()
		canvas3.free()
		check(not is_instance_valid(canvas3),"the immediately freed canvas really is invalid")
		var replacement = FogPierce.instance()
		check(replacement == null or replacement.get_instance_id() != dead_id,
			"an immediately freed canvas is discarded by the validity check alone")
		var canvas4 = FogPierce.ensure()
		check(canvas4 != null and is_instance_valid(canvas4) and canvas4.get_instance_id() != dead_id,
			"and the next push resolves a replacement rather than the dead one")

	# ---- discard() is the explicit teardown the fix relies on -------------------------------
	FogPierce.discard()
	await wait(0.2)
	check(FogPierce._cached == null,"discard() clears the cache")
	check(FogPierce.instance() == null,"...and nothing survives it")

	await finish_cleanup()
	await finish()

func finish() -> void:
	B11Probe.enabled = false
	print("B11_FOG_CACHE checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
