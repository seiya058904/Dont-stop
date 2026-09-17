extends "res://tests/M8Runtime.gd"

## B11 Stage 39 / Stage 40 sustained-load measurement.
##
## WHY IT EXISTS. A human playing Stage 39 late in the round reported the frame rate collapsing to
## the point where the game could not be operated. That is a claim about a REAL session, so this rig
## runs a real one: the real stage, the real spawn director, the real hazard director, the real
## player movement and the real weapon, for 60-90 s, and it reports the engine's own numbers.
##
## It is deliberately NOT a synthetic spawn-a-hundred-monsters fixture. Synthetic fixtures measure
## the fixture; the reported defect was about what the stage itself builds up over time.
##
## Usage:
##   res://tests/B11Perf.tscn -- stage=39 seconds=75
##   res://tests/B11Perf.tscn -- stage=40 seconds=75
##
## Reports, per second: average and minimum FPS, average and peak frame time, and the live counts of
## enemies, projectiles, telegraphs, hazards, VFX, particles, total nodes, plus nodes created and
## freed per second. It also reports the FPS of the LAST third of the run separately, because a
## build-up defect shows up there and an average over the whole run can hide it.
##
## The player is held alive on purpose. A dead player ends the round and stops the build-up, which is
## exactly the measurement this test exists to take.
const GROUP_VFX := "hostile_vfx"

var stage := 39
var seconds := 75.0

func arg_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return int(arg.substr(prefix.length()))
	return fallback

func arg_float(prefix: String, fallback: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return float(arg.substr(prefix.length()))
	return fallback

## Nodes the engine really added / removed, counted at the tree level rather than inferred from
## group sizes. This is the only way to see churn that nets to zero.
var created := 0
var removed := 0
var counting := false

func _on_node_added(_node: Node) -> void:
	if counting: created += 1

func _on_node_removed(_node: Node) -> void:
	if counting: removed += 1

func count_group(name: String) -> int:
	return get_tree().get_nodes_in_group(name).size()

func particle_nodes() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		if is_instance_valid(node) and node.has_node("body/AnimatedSprite2D"):
			total += 1
	return total

## One sample of everything the report needs. Kept as a function so the "is it still growing?"
## comparison later uses exactly the same fields as the live line.
func sample() -> Dictionary:
	return {
		"enemies": get_tree().get_nodes_in_group("monsters").filter(
			func(node): return not node.is_die and not node.training).size(),
		"projectiles": count_group("enemy_projectiles"),
		"telegraphs": count_group("hostile_zone"),
		"hazards": count_group(StageHazard.GROUP),
		"vfx": count_group(GROUP_VFX) + count_group("combat_transient"),
		"nodes": get_tree().get_node_count(),
		"created": created,
		"removed": removed,
	}

func _ready():
	await boot()
	stage = arg_int("stage=",39)
	seconds = arg_float("seconds=",75.0)
	configure(124,true)
	Demo.test_mode = true
	# A survivable player, so the round cannot end and stop the build-up being measured. This is the
	# one number the rig sets, and it is set to the same value before and after any change.
	PlayerData.player_hp_max = 100000.0
	PlayerData.player_hp = 100000.0
	PlayerData.resurrectPlayer(100000.0,100)
	LevelServer.state = "CAMP"
	check(LevelServer.town.depart(stage,true),"stage %d departs for the sustained run" % stage)
	await wait(0.8)
	check(LevelServer.state == "COMBAT","the sustained run is really in combat")

	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	counting = true
	driving = true
	moving = true
	target_boss = DemoConfig.ENCOUNTERS[stage].has("boss")

	var frame_ms: Array = []
	var rows: Array = []
	var previous := Time.get_ticks_usec()
	var clock := 0.0
	var start := Time.get_ticks_msec()
	var samples: Array = []
	while Time.get_ticks_msec()-start < int(seconds*1000.0):
		# The player has to keep playing: contact damage is live, telegraphs are live, and a player
		# who stands in a corner measures a round that is not the one that was reported.
		PlayerData.player_hp = PlayerData.player_hp_max
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var delta_ms := (now-previous)/1000.0
		previous = now
		frame_ms.append(delta_ms)
		clock += delta_ms
		if clock < 1000.0: continue
		clock = 0.0
		var row := sample()
		row["fps"] = Engine.get_frames_per_second()
		row["t"] = roundf((Time.get_ticks_msec()-start)/1000.0)
		rows.append(row)
		samples.append(row.duplicate())
		print("B11 PERF TICK %s" % JSON.stringify(row))
	driving = false
	stop()
	counting = false

	frame_ms.sort()
	var total := 0.0
	for value in frame_ms: total += value
	var third := int(rows.size()/3.0)
	var late: Array = []
	for index in range(rows.size()-1,maxi(-1,rows.size()-1-third),-1):
		late.append(float(rows[index].fps))
	var worst_nodes := 0
	var worst_projectiles := 0
	var worst_telegraphs := 0
	for row in samples:
		worst_nodes = maxi(worst_nodes,int(row.nodes))
		worst_projectiles = maxi(worst_projectiles,int(row.projectiles))
		worst_telegraphs = maxi(worst_telegraphs,int(row.telegraphs))
	var gate := {
		"stage":stage,"seconds":seconds,"samples":rows.size(),"physics_fps":Engine.physics_ticks_per_second,
		"renderer":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),
		"frames":frame_ms.size(),
		"frame_ms_avg":total/maxf(1.0,frame_ms.size()),
		"frame_ms_p50":frame_ms[int(frame_ms.size()*0.50)],
		"frame_ms_p95":frame_ms[int(frame_ms.size()*0.95)],
		"frame_ms_p99":frame_ms[int(frame_ms.size()*0.99)],
		"frame_ms_max":frame_ms.back() if not frame_ms.is_empty() else 0.0,
		"fps_avg":1000.0/maxf(0.001,total/maxf(1.0,frame_ms.size())),
		"fps_min":1000.0/maxf(0.001,frame_ms.back()),
		"fps_late_third_avg":(func():
			var sum := 0.0
			for value in late: sum += value
			return sum/maxf(1.0,late.size())).call(),
		"peak_enemies":samples.map(func(r): return int(r.enemies)).max() if not samples.is_empty() else 0,
		"peak_projectiles":worst_projectiles,"peak_telegraphs":worst_telegraphs,
		"peak_nodes":worst_nodes,
		"created":created,"removed":removed,
		"created_per_second":created/maxf(1.0,seconds),"removed_per_second":removed/maxf(1.0,seconds),
	}
	print("B11 PERF %s" % JSON.stringify(gate))

	# Bounded-growth gate. The claim under test is NOT "the node count never rises": a boss round adds
	# the boss and its first wave immediately and then oscillates as waves and barrages spawn and die,
	# so a rising edge is normal. The claim is that the count does not grow WITHOUT BOUND, and the way
	# to see that is a BAND rather than two single samples - comparing two endpoints inside an
	# oscillation measures which phase they landed in, which is how an earlier version of this gate
	# failed a Stage-40 run whose own trajectory was flat (peak 980, band 489-980, no trend).
	# So: the second half of the run must stay inside the ceiling the first half established, with a
	# tolerance for a wave plan that legitimately peaks later. A leak lifts the second half's floor and
	# its ceiling together and fails.
	if samples.size() >= 12:
		var half := int(samples.size()/2.0)
		var first := samples.slice(0,half)
		var second := samples.slice(half)
		var first_peak := 0.0
		for row in first: first_peak = maxf(first_peak,float(row.nodes))
		var second_peak := 0.0
		var second_floor := INF
		for row in second:
			second_peak = maxf(second_peak,float(row.nodes))
			second_floor = minf(second_floor,float(row.nodes))
		var ceiling := first_peak*1.25+100.0
		check(second_peak <= ceiling,
			"the node count stays inside the ceiling the first half established (first peak %.0f, second peak %.0f, ceiling %.0f over %ds)"
				% [first_peak,second_peak,ceiling,int(seconds)])
		# A leak also lifts the FLOOR: a build that never frees what it creates cannot return to a low
		# count even between waves. This is the half of the claim two endpoints could never see.
		check(second_floor <= first_peak,
			"and it still returns towards its own baseline between waves (second-half floor %.0f, first-half peak %.0f)"
				% [second_floor,first_peak])
		var quarter := int(samples.size()/4.0)
		var last_projectiles := 0
		for row in samples.slice(samples.size()-quarter):
			last_projectiles = maxi(last_projectiles,int(row.projectiles))
		check(last_projectiles <= 180,"projectiles stay inside their own ceiling (%d)" % last_projectiles)
		var last_telegraphs := 0
		for row in samples.slice(samples.size()-quarter):
			last_telegraphs = maxi(last_telegraphs,int(row.telegraphs))
		check(last_telegraphs <= 48,
			"live telegraphs stay bounded in the last quarter (%d)" % last_telegraphs)

	LevelServer.return_to_camp()
	await wait(0.5)
	print("B11_PERF checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
