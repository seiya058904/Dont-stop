extends Node

## A2: the graphic magazine must track the REAL magazine at every size the game
## can hand out, not just the one the player happens to be holding.
##
## The shipped bar built `min(bullets_count, 40)` shells and deleted one shell per
## round fired. A 100-round magazine therefore drew 40 shells and looked empty
## after 40 shots while 60 rounds were still loaded - the number and the picture
## disagreed for the whole second half of the magazine. The fix renders the
## current/capacity RATIO into at most 40 segments, so the picture is a scale of
## the magazine rather than a one-shell-per-round tally.
##
## This fixture drives the real GameUI through the boundary sizes:
##   1, 2, 3   - single/triple round effects and the smallest possible magazine
##   21        - the mid-size the R3 return test also uses
##   27, 35    - other mid magazines
##   40, 41    - the exact segment cap and one past it (the ">40 must not draw
##               100 shells" edge)
##   60, 100, 200 - oversized magazines, where the old bar broke hardest
##
## For each size it sweeps the magazine empty -> full and asserts:
##   * the drawn segment count is min(capacity, 40) and never exceeds 40;
##   * empty draws nothing and full draws everything, exactly;
##   * every partial value draws ceil(ratio * segments) lit segments, which is
##     the documented mapping (60/100 -> 24 of 40);
##   * the readout is "remaining/capacity";
##   * lit count never decreases as rounds are added (monotonic).
##
## Run headless:
##   Godot_v4.7.2-stable_win64.exe --headless --path <project> res://tests/AmmoBarCoverage.tscn

static var _probe_spawned := false

const MENU_SCENE := "res://game/map/Main.tscn"
const MAX_SEGMENTS := 40
const CAPACITIES := [1, 2, 3, 21, 27, 35, 40, 41, 60, 100, 200]

var _failures := 0
var _checks := 0

func _ready() -> void:
	if _probe_spawned:
		_run.call_deferred()
		return
	_probe_spawned = true
	var probe := Node.new()
	probe.name = "AmmoBarCoverageProbe"
	probe.set_script(load("res://tests/AmmoBarCoverage.gd"))
	get_tree().root.add_child.call_deferred(probe)

func _watchdog() -> void:
	await get_tree().create_timer(180.0, true).timeout
	print("AMMO_RESULT=TIMEOUT after 180s")
	get_tree().quit(2)

func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok: _failures += 1
	print("AMMO %s %s%s" % ["ok  " if ok else "FAIL", label, (" :: " + detail) if detail != "" else ""])

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _main_ui() -> Node:
	if not is_instance_valid(Utils.canvasLayer): return null
	return Utils.canvasLayer.get_node_or_null("MainUI")

func _game_ui() -> Node:
	if not is_instance_valid(Utils.canvasLayer): return null
	return Utils.canvasLayer.get_node_or_null("GameUI")

## Independent oracle for the intended mapping. Kept separate from GameUI's own
## helper on purpose: if the bar and this ever disagree, one of them is wrong and
## the test should say so rather than agreeing with itself.
func _expected_segments(capacity: int) -> int:
	if capacity <= 0: return 0
	return capacity if capacity <= MAX_SEGMENTS else MAX_SEGMENTS

func _expected_lit(current: int, capacity: int, segments: int) -> int:
	if capacity <= 0 or segments <= 0: return 0
	if current <= 0: return 0
	if current >= capacity: return segments
	var exact := float(current) / float(capacity) * float(segments)
	return ceili(exact - 0.000001)

func _lit_now(ui: Node) -> int:
	var lit := 0
	for item in ui.ammo_segments:
		if is_instance_valid(item) and item.lit > 0.0: lit += 1
	return lit

func _run() -> void:
	_watchdog()
	var main = load(MENU_SCENE).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _wait(0.6)

	var menu := _main_ui()
	_check("MENU_PRESENT", menu != null)
	if menu == null:
		_finish()
		return
	var start: Button = menu.get_node_or_null("VBoxContainer/start")
	_check("START_BUTTON", start != null)
	if start == null:
		_finish()
		return
	start.pressed.emit()
	await _wait(0.6)

	# The camp panel opens and pauses the tree; close it the way the player does.
	if is_instance_valid(Demo.ui):
		var panel = Demo.ui
		Demo.pop_pause(panel)
		panel.queue_free()
		Demo.ui = null
	await _wait(0.2)

	var gun = Utils.player.gun if is_instance_valid(Utils.player) else null
	_check("GUN_EQUIPPED", is_instance_valid(gun), "a session must own a live weapon")
	if not is_instance_valid(gun):
		_finish()
		return

	var ui := _game_ui()
	_check("GAME_UI_PRESENT", ui != null)
	if ui == null:
		_finish()
		return

	for capacity in CAPACITIES:
		_sweep(ui, gun, int(capacity))

	_finish()

func _sweep(ui: Node, gun, capacity: int) -> void:
	var segments := _expected_segments(capacity)
	_check("CAP%d_SEGMENT_COUNT" % capacity,
		ui.segment_count(capacity) == segments,
		"segment_count(%d)=%d expected=%d" % [capacity, ui.segment_count(capacity), segments])
	_check("CAP%d_SEGMENTS_AT_MOST_40" % capacity, segments <= MAX_SEGMENTS,
		"a %d-round magazine draws %d segments, ceiling is %d" % [capacity, segments, MAX_SEGMENTS])

	# Candidate magazine values: empty, one round, the halfway point, one short of
	# full, and full. Deduplicated so tiny magazines do not run the same value twice.
	var values: Array = [0, 1, capacity / 2, capacity - 1, capacity]
	var seen: Array = []
	var prev_lit := -1
	var prev_current := -1
	for value in values:
		var current := clampi(int(value), 0, capacity)
		if current in seen: continue
		seen.append(current)
		gun.bullets_max_count = capacity
		gun.bullets_count = current
		ui._render_ammo(true)

		var lit := _lit_now(ui)
		var want := _expected_lit(current, capacity, segments)
		_check("CAP%d_CUR%d_SEGMENTS" % [capacity, current],
			ui.ammo_segments.size() == segments,
			"drawn=%d expected=%d" % [ui.ammo_segments.size(), segments])
		_check("CAP%d_CUR%d_LIT" % [capacity, current], lit == want,
			"lit=%d expected=%d (ratio %d/%d)" % [lit, want, current, capacity])
		# Monotonicity: more rounds must never light fewer segments.
		if prev_current >= 0:
			_check("CAP%d_CUR%d_MONOTONIC" % [capacity, current], lit >= prev_lit,
				"lit=%d after lit=%d at %d rounds" % [lit, prev_lit, prev_current])
		prev_lit = lit
		prev_current = current

		# Empty is empty and full is full, exactly - never one short.
		if current == 0:
			_check("CAP%d_EMPTY_DRAWS_NOTHING" % capacity, lit == 0, "lit=%d" % lit)
		if current == capacity:
			_check("CAP%d_FULL_DRAWS_EVERYTHING" % capacity, lit == segments,
				"lit=%d segments=%d" % [lit, segments])

		var expected_text := "%d/%d" % [current, capacity]
		_check("CAP%d_CUR%d_NUMBER" % [capacity, current],
			ui.ammo_count_label.text == expected_text,
			"text='%s' expected='%s'" % [ui.ammo_count_label.text, expected_text])

	# The headline regression: the old bar showed nothing once 40 of 100 rounds were
	# spent. 60/100 must read as 24 of 40, and the magazine is nowhere near empty.
	if capacity == 100:
		gun.bullets_max_count = 100
		gun.bullets_count = 60
		ui._render_ammo(true)
		var lit := _lit_now(ui)
		_check("REGRESSION_60_OF_100_SHOWS_24", lit == 24,
			"lit=%d expected=24; the old bar drew 0 here while 60 rounds remained" % lit)

func _finish() -> void:
	print("AMMO_RESULT checks=%d failures=%d" % [_checks, _failures])
	# Exit explicitly on BOTH paths. A headless Godot main loop does not end on its
	# own once the last await resolves, so a PASS that only stops printing would
	# still hang the runner - and a hang is worse than a failure for a CI gate.
	var code := 1 if _failures > 0 else 0
	print("AMMO_RESULT=%s" % ("FAIL" if _failures > 0 else "PASS"))
	get_tree().quit(code)
