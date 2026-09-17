extends "res://tests/M8Runtime.gd"

## B10 SpecialThreatAudit: does a special enemy's attack actually demand a decision?
##
## WHY THIS EXISTS
## ---------------
## The real-playtest finding was not "there are too few special enemies" - it was "a special
## enemy does not change what I do". A clear rate cannot see that, and neither can a damage
## table: an attack the player never has to react to is invisible to both. So this scene measures
## the thing the complaint is actually about, per enemy, in three scenarios:
##
##   STANDING        the player does not move at all. An attack worth fearing must land.
##   NAIVE STRAFE    the player holds ONE direction at full speed for the whole trial - the
##                   "just keep circling and it misses" behaviour. A threat that is real must not
##                   be free against every special.
##   REACTIVE DODGE  the player runs the real B9 movement core (M8Runtime.choose_safe_movement),
##                   i.e. it reads the live telegraphs and steps out of them. Most attacks SHOULD
##                   be avoidable here - that is the "dangerous but fair" column, and a special
##                   that cannot be dodged even by a reactive player is a defect, not a threat.
##
## WHAT IS MEASURED
## ----------------
## Hits are counted on Hero.damage_taken, attributed to the enemy under test by instance id, so a
## hit from anything else is reported as "foreign" rather than credited. Every trial is a real
## attack from a real actor: nothing injects damage and nothing forces an attack. The only fixture
## liberties are placement (the player is put back at the round's own spawn point so trials are
## comparable), survivability (the pool is widened so a trial can finish) and the enemy's HP, so
## it is still alive at the end of the window.
##
## The real driver is NOT used: it also shoots, which would kill the actor under test and end the
## trial early. The dodge scenario calls the same choose_safe_movement() core the driver calls.
##
## Usage:
##   res://tests/B10Threat.tscn --
##   res://tests/B10Threat.tscn -- only=E10,E14 trials=6 tag=baseline stage=24

## Every enemy whose threat is a special attack rather than plain contact pressure.
const SPECIALS := ["E04","E05","E06","E10","E11","E12","E13","E14"]
## One trial's ceiling. Long enough for the slowest role's wind-up + fire (E14: a 0.65 s warn then
## a 2.2 s recover), and the loop leaves early once the actor has actually attacked.
const TRIAL_SECONDS := 4.2
const SPAWN_DISTANCE := 150.0
const PLAYER_POOL := 4000.0
const TRIALS_DEFAULT := 5
const DODGE_DECISIONS_HZ := 10.0

var audit_stage := 24
var trials := TRIALS_DEFAULT
var home := Vector2.ZERO

var hits_by_enemy := {}
var fired_by_enemy := {}
var foreign_hits := 0
var current_id := ""
var current_hits := 0
var current_foreign := 0

var dodge_clock := 0.0
var dodging := false
var strafe_direction := Vector2.RIGHT

func _on_damage(_raw: float, _applied: float, _tag: String, attacker) -> void:
	if is_instance_valid(attacker) and str(attacker.get_meta("content_id","")) == current_id:
		current_hits += 1
	else:
		current_foreign += 1
		foreign_hits += 1

func _bucket(table: Dictionary, id: String) -> Dictionary:
	if not table.has(id):
		table[id] = {"standing":0,"strafe":0,"dodge":0,
			"fired_standing":0,"fired_strafe":0,"fired_dodge":0}
	return table[id]

func _ready():
	audit_stage = user_int("stage=",24)
	trials = user_int("trials=",TRIALS_DEFAULT)
	var tag := user_arg("tag=","final")
	var only := user_arg("only=","")
	var ids := SPECIALS
	if only != "":
		ids = []
		for piece in only.split(",",false): ids.append(piece.strip_edges())
	await boot()
	# The player's physics must STAY ON: this scene measures whether moving helps, so a disabled
	# Hero would make all three scenarios identical (a first version did exactly that, and every
	# enemy scored the same in all three columns).
	PlayerData.gold = 100000; PlayerData.reward_point = 9999
	Demo.try_purchase("weapon","117")
	check(LevelServer.town.depart(audit_stage,true),
		"a real arena departs for the threat audit (stage %d)" % audit_stage)
	await wait(1.0)
	check(LevelServer.state == "COMBAT","the audit runs inside a real round")
	# THE AUDIT OWNS THE ARENA. The round's own timer is what spawns the horde AND counts the
	# round down, so stopping it leaves the arena standing and the state at COMBAT - which is what
	# every enemy's AI and ArenaVisibility.fog_active() read - while nothing else spawns into the
	# measurement. Without this the stage's own monsters hit the player between trials (a first
	# version scored 16 such hits as "foreign") and inflated the transient count the attack
	# detector compares against, so most enemies looked as if they never attacked at all.
	LevelServer.timerStop()
	await clear_arena()
	# The round's own spawn point, so every trial starts from a place the game proved is legal
	# and has clearance.
	home = Utils.player.global_position
	Utils.player.damage_taken.connect(_on_damage)
	# The dodge scenario reuses the driver's decision core, but not the driver: see the header.
	set_process(true)
	# Every bucket is created BEFORE the first row is reported: the evidence file is rewritten
	# after each enemy with the rows for ALL of them, and reading a bucket that does not exist yet
	# is a hard error in GDScript, not a zero.
	for id in ids:
		_bucket(hits_by_enemy,id); _bucket(fired_by_enemy,id)
	print("B10 THREAT tag=%s stage=%d trials=%d enemies=%s" % [tag,audit_stage,trials,",".join(ids)])
	for id in ids:
		for scenario in ["standing","strafe","dodge"]:
			for trial in trials:
				var result = await run_trial(id,scenario)
				hits_by_enemy[id][scenario] += int(result.hits)
				if result.fired: fired_by_enemy[id]["fired_"+scenario] += 1
		print("B10 THREAT ROW ",JSON.stringify(_row(id)))
		write_json("res://docs/iteration/evidence/b10/threat-%s.json" % tag,
			{"tag":tag,"stage":audit_stage,"trials":trials,"enemies":ids,
				"rows":_rows(ids),"foreign_hits":foreign_hits})
	release_all(); driving = false
	print("B10 THREAT CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

func _row(id: String) -> Dictionary:
	var t := maxf(1.0,float(trials))
	return {"id":id,"name":M5Content.ENEMIES.get(id,{}).get("name",""),
		"role":M5Content.ENEMIES.get(id,{}).get("role",""),"trials":trials,
		"standing_hits":hits_by_enemy[id].standing,
		"strafe_hits":hits_by_enemy[id].strafe,
		"dodge_hits":hits_by_enemy[id].dodge,
		"standing_rate":float(hits_by_enemy[id].standing)/t,
		"strafe_rate":float(hits_by_enemy[id].strafe)/t,
		"dodge_rate":float(hits_by_enemy[id].dodge)/t,
		"fired_standing":fired_by_enemy[id].fired_standing,
		"fired_strafe":fired_by_enemy[id].fired_strafe,
		"fired_dodge":fired_by_enemy[id].fired_dodge}

func _rows(ids: Array) -> Array:
	var out := []
	for id in ids: out.append(_row(id))
	return out

## One trial: clear the arena, place the player, spawn exactly one actor, run one scenario.
func run_trial(id: String, scenario: String) -> Dictionary:
	await clear_arena()
	Utils.player.global_position = home
	PlayerData.player_hp_max = PLAYER_POOL; PlayerData.player_hp = PLAYER_POOL
	Utils.player.is_dead = false
	Utils.player.velocity = Vector2.ZERO
	current_id = id; current_hits = 0; current_foreign = 0
	var actor = M5Content.spawn(id,LevelServer.town.monster_root,home+Vector2(SPAWN_DISTANCE,0))
	if not is_instance_valid(actor):
		check(false,"the audit can spawn %s" % id)
		return {"hits":0,"fired":false}
	actor.set_meta("content_id",id)
	# The actor has to survive the window: this scene measures the ATTACK, not how fast a build
	# kills. Nothing about its behaviour is changed. `max_hp` is set through set() because the
	# DemoEnemy roster (E04/E05) does not declare it and a direct assignment is a hard error.
	actor.set("max_hp",100000.0)
	actor.HP = 100000.0
	var before_attacks := get_tree().get_nodes_in_group("combat_transient").size()
	begin_scenario(scenario)
	var spent := 0.0
	var fired := false
	while spent < TRIAL_SECONDS and is_instance_valid(actor) and not actor.is_die:
		await wait(0.1)
		spent += 0.1
		if get_tree().get_nodes_in_group("combat_transient").size() > before_attacks:
			fired = true
			break
	if fired:
		# LET THE ATTACK FINISH BEFORE SCORING. Every attack this scene measures throws something
		# that has to travel: a telegraph that has to elapse, a lane that has to burn, a volley
		# that has to fly. Scoring a fixed 0.9 s after the attack was COMMITTED cut the slow ones
		# off mid-flight and reported them as harmless - E05's 85 px/s pellet needs ~1.8 s to
		# cross the 150 px trial gap, so it was still in the air when the trial ended and the actor
		# was freed out from under it. Waiting for the arena to go quiet again is the honest
		# definition of "the attack has resolved".
		var quiet := 0.0
		while quiet < 4.0:
			await wait(0.1)
			spent += 0.1
			if get_tree().get_nodes_in_group("combat_transient").size() <= before_attacks: break
			quiet += 0.1
		await wait(0.25)
	stop_scenario()
	if is_instance_valid(actor): actor.queue_free()
	await wait(0.15)
	return {"hits":current_hits,"fired":fired,"foreign":current_foreign,"seconds":spent}

## Clears the arena and WAITS for the frees to land. The attack detector compares the transient
## count against a baseline taken just before the actor is spawned, so a stale node still queued
## for deletion would make the baseline too high and every trial would run its full window
## instead of ending when the attack lands.
func clear_arena() -> void:
	for node in get_tree().get_nodes_in_group("monsters"):
		if is_instance_valid(node): node.queue_free()
	for node in get_tree().get_nodes_in_group("combat_transient"):
		if is_instance_valid(node): node.queue_free()
	# Ground hazards are their own group and their own director, and they damage the player just
	# as much as an enemy does - so they have to go too, or a trial would be scored against a
	# hazard the enemy under test never fired.
	for node in get_tree().get_nodes_in_group(StageHazard.GROUP):
		if is_instance_valid(node): node.queue_free()
	if is_instance_valid(LevelServer.town.arena):
		for child in LevelServer.town.arena.get_children():
			if child.get_script() and str(child.get_script().resource_path).ends_with("ArenaHazardDirector.gd"):
				child.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await wait(0.1)

## Drives the player for one scenario using REAL input only.
func begin_scenario(scenario: String) -> void:
	release_all()
	dodging = scenario == "dodge"
	if scenario == "strafe":
		# One fixed direction, held for the whole trial. The direction with the most clearance is
		# used so the trial measures the attack and not a wall.
		var best := Vector2.RIGHT
		var best_room := -1.0
		for i in 16:
			var dir := Vector2.RIGHT.rotated(i*TAU/16)
			var room := 0.0
			while room < 300.0 and not Utils.player.test_move(Utils.player.global_transform,
					dir*(room+16.0)):
				room += 16.0
			if room > best_room: best_room = room; best = dir
		strafe_direction = best
		press(strafe_direction)

func stop_scenario() -> void:
	dodging = false
	release_all()

func press(dir: Vector2) -> void:
	if dir.x < -0.2: Input.action_press("left")
	if dir.x > 0.2: Input.action_press("right")
	if dir.y < -0.2: Input.action_press("up")
	if dir.y > 0.2: Input.action_press("down")

func release_all() -> void:
	for action in ["shoot","left","right","up","down","dash"]: Input.action_release(action)

## The reactive-dodge scenario: the same 16-direction danger scan the boss driver and the
## ordinary-stage driver both use, asked for a keep-away wish. Deliberately NOT M8Runtime._process:
## that would also shoot the actor under test to death and end its own trial.
func _process(delta: float) -> void:
	if not dodging: return
	if not is_instance_valid(Utils.player) or Utils.player.is_dead: return
	dodge_clock += delta
	if dodge_clock < 1.0/DODGE_DECISIONS_HZ: return
	dodge_clock = 0.0
	var actors = get_tree().get_nodes_in_group("monsters").filter(
		func(a): return not a.is_die and not a.is_queued_for_deletion())
	if actors.is_empty(): return
	var target = actors[0]
	var away = Utils.player.global_position-target.global_position
	var wanted = away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var direction = choose_safe_movement(wanted,target,actors)
	for pair in [["left",direction.x < -0.2],["right",direction.x > 0.2],
			["up",direction.y < -0.2],["down",direction.y > 0.2]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])

static func user_arg(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.substr(prefix.length())
	return fallback

static func user_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return int(arg.substr(prefix.length()))
	return fallback

func write_json(path: String, data) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: push_error("B10 cannot write "+path); return
	file.store_string(JSON.stringify(data,"\t")); file.close()
