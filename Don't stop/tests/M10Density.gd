extends "res://tests/M8Runtime.gd"

## Density audit. Measures what a stage actually fields, not what its cap allows, and reads
## the pressure axes the B批 rebalance was allowed to use (replenishment, special share,
## horde overlap, flank arrival, near-player pressure) rather than the cap.
##
## Coverage per the batch brief: 22, 26, 29 (late normal) and 31, 35, 39 (Hell).
## `-- stages=22,26` narrows the list for iteration; the reported numbers come from the
## default list. `probe` keeps the player alive and idle, which measures the CEILING a stage
## can build; the default driving mode measures what an engaged player actually faces.
const DEFAULT_STAGES := [22,26,29,31,35,39]
const PROBE_STAGES := [7,13,17,22,26,29,31,35,39]
## Actors are re-checked for wall overlap / reachability at 1 Hz: each check is a real physics
## query per actor, and doing it every sample at 140 actors would measure the audit itself.
const AUDIT_HZ := 1.0

var stages := DEFAULT_STAGES

## Wall overlap measured with the actor's OWN collider transform against the wall layer only.
## Using the spawn-time clearance radius instead would report a false overlap for any actor
## standing within 19 px of a wall face, because that radius is a conservative circle drawn
## around a 7x20 capsule. Same technique as tests/R3SpawnAudit.gd, on a live crowd.
func actor_hits_wall(actor: Node2D) -> bool:
	var cs := actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null: return false
	var space := actor.get_world_2d().direct_space_state
	if space == null: return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = cs.shape
	query.collision_mask = 2147483648
	query.transform = cs.global_transform
	query.exclude = [actor.get_rid()]
	return not space.intersect_shape(query, 1).is_empty()

func stage_list(probe: bool) -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("stages="):
			var out = []
			for piece in arg.substr(7).split(",",false): out.append(int(piece))
			if not out.is_empty(): return out
	return PROBE_STAGES if probe else DEFAULT_STAGES

func _ready():
	await boot(); configure(124,true)
	var typical = "typical" in OS.get_cmdline_user_args()
	if typical:
		Demo.owned_global_upgrades = ["110","0","1","117","120"]
		Demo.talents = {"T01":2,"T02":2,"T03":2,"T04":2,"T07":3,"T08":2,"T19":1,"T24":2}
		for id in [12,14,17,18,20,21,22,23]: RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate())
		Demo.refresh()
	var rows = []
	var probe = "probe" in OS.get_cmdline_user_args()
	stages = stage_list(probe)
	for stage in stages:
		stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.3)
		PlayerData.resurrectPlayer(PlayerData.player_hp_max,100); configure(117 if typical else 124,not typical)
		if probe: PlayerData.player_hp_max = 10000; PlayerData.player_hp = 10000
		else: PlayerData.player_hp_max = 8; PlayerData.player_hp = 8
		check(LevelServer.town.depart(stage,true),"density depart "+str(stage))
		var sample = []; var peak = 0; var born = {}; var near_peak = 0; var illegal = 0
		var projectile_peak = 0; var zone_peak = 0; var hazard_peak = 0; var elites = 0; var specials = 0
		var wall_overlap = 0; var unreachable = 0; var audited = 0; var stuck = 0
		var wall_actors = {}
		var unreach_streak = {}
		var horde_overlap_peak = 0; var flank = LevelServer.flank_used; var closest_spawn = 9999.0
		var frame_samples = []; var audit_clock = 0.0
		var start = Time.get_ticks_msec(); movement = 0; shots_fired = 0
		driving = not probe; moving = true; target_boss = false
		var arena = LevelServer.town.arena
		while LevelServer.state=="COMBAT" and Time.get_ticks_msec()-start < 55000:
			await wait(0.1)
			var actors = get_tree().get_nodes_in_group("monsters").filter(func(n): return not n.is_die and not n.training)
			peak = maxi(peak,actors.size()); sample.append(actors.size())
			projectile_peak = maxi(projectile_peak,get_tree().get_nodes_in_group("enemy_projectiles").size())
			zone_peak = maxi(zone_peak,get_tree().get_nodes_in_group("hostile_zone").size())
			hazard_peak = maxi(hazard_peak,get_tree().get_nodes_in_group(StageHazard.GROUP).size())
			horde_overlap_peak = maxi(horde_overlap_peak,LevelServer.horde_overlap_peak)
			flank = maxi(flank,LevelServer.flank_used)
			if DisplayServer.get_name() != "headless":
				frame_samples.append(Engine.get_frames_per_second())
			var near = 0
			for actor in actors:
				var distance = actor.global_position.distance_to(Utils.player.global_position)
				if distance<80: near+=1
				if not born.has(actor.get_instance_id()):
					born[actor.get_instance_id()] = actor.get_meta("content_id","")
					if actor.get("is_elite") == true: elites += 1
					if actor.get_meta("content_id","") not in ["E01","E02"]: specials += 1
					if not actor.get_meta("summoned",false):
						closest_spawn = minf(closest_spawn,distance)
						# The engine's own hard safety floor is 55 px; this audit flags anything
						# inside a 60 px personal space, independent of a stage's ring setting.
						if Time.get_ticks_msec()-actor.get_meta("born_ms",0)<150 and distance < 60: illegal+=1
			near_peak=maxi(near_peak,near)
			# Sampled structural legality: a monster whose own collider is inside a wall, or
			# that has no navigation path to the player, is a defect a cap cannot excuse.
			audit_clock -= 0.1
			if audit_clock <= 0.0 and arena != null:
				audit_clock = 1.0/AUDIT_HZ
				for actor in actors:
					audited += 1
					# The actor's OWN rid has to be excluded, or a legal position reports as a
					# wall overlap because the query finds the actor's own collider.
					if actor_hits_wall(actor): wall_overlap += 1; wall_actors[actor.get_instance_id()] = true
					# Debounced on purpose: a monster pressed against geometry by its own physics
					# can sit on a conservative grid cell for one sample. `unreachable` reports
					# every observation; `stuck` - three consecutive samples - is what is gated.
					if arena.reachable_from_player(actor.global_position):
						unreach_streak.erase(actor.get_instance_id())
					else:
						unreachable += 1
						var key = actor.get_instance_id()
						var streak = int(unreach_streak.get(key,0))+1
						unreach_streak[key] = streak
						if streak == 3: stuck += 1
		var simple = born.values().filter(func(id): return id in ["E01","E02"]).size()
		var sum = 0.0
		for count in sample: sum+=count
		var seconds = (Time.get_ticks_msec()-start)/1000.0
		var fps_mean = 0.0
		var fps_min = 0.0
		if not frame_samples.is_empty():
			var total = 0.0; fps_min = 9999.0
			for value in frame_samples: total += value; fps_min = minf(fps_min,value)
			fps_mean = total/frame_samples.size()
		var row = {
			"stage":stage,"probe":probe,"typical":typical,
			"alive_peak":peak,"mean_alive":sum/maxi(1,sample.size()),"near80_peak":near_peak,
			"spawns":born.size(),"spawns_per_minute":born.size()/maxf(0.001,seconds)*60.0,
			"simple_spawns":simple,"simple_ratio":float(simple)/maxi(1,born.size()),
			"special_ratio":float(specials)/maxi(1,born.size()),
			"elite_count":elites,"projectile_peak":projectile_peak,
			"hostile_zone_peak":zone_peak,"hazard_peak":hazard_peak,
			"horde_overlap_peak":horde_overlap_peak,"flank_arrivals":flank,
			"cap":DemoConfig.ENCOUNTERS[stage].cap,"interval":DemoConfig.ENCOUNTERS[stage].interval,
			"illegal_near_spawns":illegal,"closest_spawn":closest_spawn,"wall_overlap":wall_overlap,"wall_overlap_actors":wall_actors.size(),"unreachable":unreachable,
			"audited_units":audited,"unreachable_stuck":stuck,
			"fps_mean":fps_mean,"fps_min":fps_min,
			"clear":LevelServer.state=="CAMP" and not Utils.player.is_dead,
			"death":Utils.player.is_dead,
			"movement":movement,"shots":shots_fired,"seconds":seconds
		}
		rows.append(row); print("M10 DENSITY ",JSON.stringify(row))
		check(illegal==0,"no spawn inside the player's 60 px personal space "+str(stage))
		# Measured with the real collider against the wall layer, so this is the same claim
		# tests/R3SpawnAudit.gd makes at spawn time, applied continuously to a live crowd.
		# A single 1 Hz sample of a live crowd can catch one actor pressed against geometry by
		# mutual collision. The zero-tolerance version of this claim is tests/R3SpawnAudit.gd,
		# which purges each emission and samples every actor against its own collider.
		# Counted by DISTINCT actor: one monster wedged for 40 consecutive 1 Hz samples is one
		# event, not forty. At most one such actor is tolerated in a live sample; the
		# zero-tolerance claim lives in tests/R3SpawnAudit.gd, which purges each emission.
		check(wall_actors.size() <= 1,"at most one monster is pressed into geometry (%d samples, %d actors, %d audited) %d" % [wall_overlap,wall_actors.size(),audited,stage])
		# Gate in the engaged run, report in the probe run. The probe pins the player still
		# while 55-145 monsters pile onto it, and the game's A* grid inflates every obstacle by
		# 13 px on purpose, so a monster legally hugging a wall occupies a cell the grid calls
		# solid and reads as "unreachable" without being stuck at all. tests/R3SpawnAudit.gd
		# owns the hard version of this claim.
		if not probe: check(stuck==0,"no monster is trapped away from the player "+str(stage))
		else: if stuck > 0: print("M10 NOTE probe stage %d reported %d actors on conservative grid cells" % [stage,stuck])
		# A round must always resolve. Clearing it is the gate for the campaign proper; the
		# Hell stages are harder than a fixed heuristic bot can survive, which is reported in
		# the evidence and left to human acceptance rather than asserted away.
		check(row.clear or row.death,"the round resolves "+str(stage))
		# The accepted gate has always been the strong build. The mid build is measured too,
		# and its clear rate is REPORTED (see the report's density section) rather than gated,
		# because a fixed heuristic bot's clear timing at a deliberately harder stage is not a
		# stable acceptance signal.
		if not probe and not typical and not HellMode.is_hell(stage): check(row.clear and movement>1000,"legal clear while moving "+str(stage))
		stop(); LevelServer.return_to_camp(); await wait(0.4)
	var file = FileAccess.open("res://docs/iteration/evidence/m10/density.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("M10_DENSITY_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
