extends Node
##======关卡等级全局管理=========

const score_board = preload("res://ui/widgets/Scoreboard.tscn")
#节点
var timer = Timer.new()

#属性
var level = 1 #当前关卡等级
var level_time = 0 #当前关卡持续时间
var wait_time = 1 #怪物生成间隔
var wait_time_temp = 0 #怪物生成间隔

var time_dict = {
	"1" = 45,
	"2" = 45,
	"3" = 45,
	"4" = 45,
	"5" = 45,
	"6" = 30,
	"7" = 30,
	"8" = 30,
	"9" = 30,
	"10" = 60,
	"11" = 60,
	"12" = 60,
	"13" = 60,
	"14" = 60,
	"15" = 60,
	"16" = 60,
	"17" = 60,
	"18" = 60,
	"19" = 60,
	"20" = 90,
	"21" = 90,
	"22" = 90,
	"23" = 90,
	"24" = 90,
	"25" = 150,
	"26" = 150,
	"27" = 150,
	"28" = 150,
	"29" = 150,
	"30" = 150
}

var monster_attr = {
	"1" = {'speed' = 90,'hp' = 2,'hurt' = 1},
	"2" = {'speed' = 90,'hp' = 3,'hurt' = 1},
	"3" = {'speed' = 90,'hp' = 4,'hurt' = 2},
	"4" = {'speed' = 90,'hp' = 5,'hurt' = 2},
	"5" = {'speed' = 90,'hp' = 6,'hurt' = 2},
	"6" = {'speed' = 70,'hp' = 7,'hurt' = 2},
	"7" = {'speed' = 70,'hp' = 8,'hurt' = 2},
	"8" = {'speed' = 70,'hp' = 9,'hurt' = 2},
	"9" = {'speed' = 70,'hp' = 10,'hurt' = 2},
	"10" = {'speed' = 65,'hp' = 11,'hurt' = 2},
	"11" = {'speed' = 65,'hp' = 12,'hurt' = 3},
	"12" = {'speed' = 65,'hp' = 13,'hurt' = 3},
	"13" = {'speed' = 65,'hp' = 14,'hurt' = 3},
	"14" = {'speed' = 65,'hp' = 15,'hurt' = 3},
	"15" = {'speed' = 65,'hp' = 16,'hurt' = 3},
	"16" = {'speed' = 80,'hp' = 17,'hurt' = 5},
	"17" = {'speed' = 80,'hp' = 18,'hurt' = 5},
	"18" = {'speed' = 80,'hp' = 19,'hurt' = 5},
	"19" = {'speed' = 80,'hp' = 20,'hurt' = 6},
	"20" = {'speed' = 80,'hp' = 21,'hurt' = 6},
	"21" = {'speed' = 150,'hp' = 22,'hurt' = 6},
	"22" = {'speed' = 150,'hp' = 23,'hurt' = 7},
	"23" = {'speed' = 150,'hp' = 24,'hurt' = 7},
	"24" = {'speed' = 150,'hp' = 25,'hurt' = 7},
	"25" = {'speed' = 150,'hp' = 26,'hurt' = 8},
	"26" = {'speed' = 100,'hp' = 27,'hurt' = 8},
	"27" = {'speed' = 100,'hp' = 28,'hurt' = 8},
	"28" = {'speed' = 100,'hp' = 29,'hurt' = 9},
	"29" = {'speed' = 100,'hp' = 30,'hurt' = 9},
	"30" = {'speed' = 100,'hp' = 16,'hurt' = 9}
}

var level_info = {
	time = 0,
	kill = 0,
	gold = 0
}

signal onTimeTick(seconds) #时间流逝
signal onRoundStart() #回合开始
signal onRoundEnd() #回合结束
signal roundVictory() #回合胜利
signal monsterCreate() #怪物生成
signal onNextLevel(level) #下一关

var state = "CAMP"
var epoch = 0
var town
var spawn_index = 0
var settled_epoch = -1
var boss_instance = 0
var boss_ref = null
var boss_victory_epoch = -1
var rush_remaining = 0
var rush_used = false
var rush_active = false
var rush_clock = 0.0
var rush_side = 0
var elite_spawned = false
var horde_jobs: Array = []
var horde_clock = 0.0
var horde_since = 0.0
var horde_last_kills = 0
var horde_index = 0
var horde_active = false
var horde_side = 0
var horde_role = "E02"
var horde_overlap_peak = 0
var horde_while_alive = 0
## B批: elites are a rate, not a one-shot boolean. `elite_clock` counts down inside the
## 10 Hz spawn tick; the plan's `start` / `interval` / `cap` come from the encounter table.
var elite_clock = 0.0
var elites_created = 0
var flank_used = 0
var flank_clock = 0.0
var flank_active = false

func set_boss(node) -> void:
	if is_instance_valid(node):
		boss_ref = weakref(node)
		boss_instance = node.get_instance_id()
	else:
		clear_boss()

func get_boss():
	if boss_ref == null: return null
	var node = boss_ref.get_ref()
	return node if is_instance_valid(node) and not node.is_queued_for_deletion() else null

func clear_boss() -> void:
	boss_ref = null
	boss_instance = 0

func _ready() -> void:
	timer.wait_time = 0.1
	timer.timeout.connect(_timeout)
	add_child(timer)

func can_start(stage: int) -> bool:
	# B13: an explicitly unarmed player is a legal combatant - movement/dash stay live and
	# firing is simply impossible without a weapon. If armed, the held gun must be owned.
	return state == "CAMP" and is_instance_valid(Utils.player) and not Utils.player.is_dead and PlayerData.player_hp > 0 \
		and (Utils.player.gun == null or PlayerData.player_weapon_list.values().has(Utils.player.gun)) \
		and DemoConfig.ENCOUNTERS.has(stage)

func roundStart() -> bool:
	if not can_start(Demo.selected_stage): return false
	if is_instance_valid(town): town.clear_practice()
	state = "PREPARING"
	Demo.stop_attacks()
	epoch += 1
	level = Demo.selected_stage
	resetLevelInfo()
	spawn_index = 0
	clear_boss()
	boss_victory_epoch = -1
	rush_remaining = 0; rush_used = false; rush_active = false; rush_clock = 0
	horde_jobs.clear(); horde_clock=1.0; horde_since=0; horde_last_kills=Combat.kill_events; horde_index=0; horde_active=false; horde_overlap_peak=0; horde_while_alive=0
	elite_spawned = false
	elite_clock = float(M5Content.elite_plan(level).get("start",0.0))
	elites_created = 0
	flank_used = 0
	flank_clock = 1.4
	wait_time_temp = 0
	level_time = DemoConfig.ENCOUNTERS[level].seconds
	state = "COMBAT"
	timerStart()
	onRoundStart.emit()
	return true

func resetLevelInfo():
	level_info = {"time":0.0,"kill":0,"gold":0,"stage":level,"trial":Demo.trial}

func getLevelMonsterData():
	return monster_attr[str(level)]

func timerStart():
	timer.paused = false
	timer.start()

func timerStop():
	timer.stop()

func isPause(value):
	timer.paused = value

func _timeout():
	if state != "COMBAT": return
	if Utils.player.is_dead:
		state = "DEAD"
		timerStop()
		return
	level_info.time += 0.1
	if DemoConfig.ENCOUNTERS[level].has("boss"):
		if boss_victory_epoch == epoch: victory(); return
		onTimeTick.emit(int(level_info.time))
		return
	level_time = maxf(0,level_time-0.1)
	if level_time <= 0: victory()
	else:
		onMonsterCreate()
		onTimeTick.emit(int(ceil(level_time)))

func onMonsterCreate():
	wait_time_temp += 0.1
	var config = DemoConfig.ENCOUNTERS[level]
	if config.has("boss"): return
	elite_clock = maxf(0,elite_clock-0.1)
	tick_horde(config)
	if level>=16 and not rush_used and level_info.time>=config.seconds*0.5:
		rush_used = true
		# Hell stages bring a longer, multi-direction rush instead of a longer spawn list.
		rush_remaining = 8 if level>=26 else (6 if level>=21 else 4)
		if config.get("flank",false): rush_remaining += 2
		rush_side = spawn_index % M5Content.REGIONS[config.region].sides.size()
	if rush_remaining>0:
		rush_clock -= 0.1
		if rush_clock<=0:
			rush_active = true; monsterCreate.emit(); rush_active = false
			rush_remaining -= 1; rush_clock = 0.3
	if config.get("flank",false) and level_info.time >= config.seconds*0.35:
		# Hell multi-direction arrival: the same cap, the same validation, a different arc.
		flank_clock -= 0.1
		if flank_clock <= 0:
			flank_clock = 2.6
			flank_used += 1
			flank_active = true
			monsterCreate.emit()
			flank_active = false
	var phase = level_info.time / config.seconds
	# Arrival, build, peak, brief recovery. No hidden health scaling.
	var multiplier = 1.3 if phase < 0.2 else (0.7 if phase < 0.8 else 1.5)
	if config.rhythm == "脉冲": multiplier = 0.5 if fmod(level_info.time,10)<4 else 1.8
	if config.rhythm == "三段": multiplier = [1.3,0.7,0.5][mini(2,int(level_info.time/15))]
	if wait_time_temp >= config.interval * multiplier:
		wait_time_temp = 0
		monsterCreate.emit()
		if level>=16 and spawn_index%4==0:
			# A second existing roster member arrives from the next side. Each emission obeys the encounter cap.
			monsterCreate.emit()

func tick_horde(config: Dictionary):
	if not M5Content.HORDES.has(level): return
	var h=config.get("horde",M5Content.HORDES[level])
	horde_clock-=0.1; horde_since+=0.1
	var alive=get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die and not m.training).size()
	var thinning=Combat.kill_events-horde_last_kills>=ceili(h.batch*0.6)
	if horde_jobs.size()<h.windows and alive<config.cap and (horde_clock<=0 or (horde_since>=h.window*0.55 and (thinning or alive<h.floor))):
		horde_jobs.append({"remaining":h.batch,"next":0.0,"side":horde_index%M5Content.REGIONS[config.region].sides.size()})
		horde_clock=h.window; horde_since=0; horde_last_kills=Combat.kill_events
		if alive>0: horde_while_alive+=1
	horde_overlap_peak=maxi(horde_overlap_peak,horde_jobs.size())
	var specials=config.roles.filter(func(id): return id not in ["E01","E02"])
	for job in horde_jobs:
		job.next-=0.1
		if job.next>0: continue
		horde_active=true; horde_side=(job.side+horde_index)%M5Content.REGIONS[config.region].sides.size()
		var ordinary_slots=clampi(roundi(float(config.get("pressure",{}).get("horde_simple",0.7))*10),0,10)
		horde_role=("E02" if horde_index%2==0 else "E01") if specials.is_empty() or horde_index%10<ordinary_slots else specials[horde_index%specials.size()]
		monsterCreate.emit(); horde_active=false
		horde_index+=1; job.remaining-=1; job.next=h.step
	horde_jobs=horde_jobs.filter(func(job): return job.remaining>0)

func victory() -> bool:
	if DemoConfig.ENCOUNTERS[level].has("boss"):
		# Boss death is reported deferred, after the node may already be queued for
		# deletion. Use the epoch written by boss_defeated() instead of resolving a
		# potentially stale ObjectID from that callback.
		if boss_victory_epoch != epoch: return false
	if state != "COMBAT" or settled_epoch == epoch or Utils.player.is_dead: return false
	state = "RESOLVING"
	settled_epoch = epoch
	if Demo.rank("T20") > 0: PlayerData.addPlayerHp(PlayerData.player_hp_max*DemoConfig.talent_value("T20",Demo.rank("T20")))
	timerStop()
	Demo.stop_attacks()
	PlayerData.reward_point += 1
	PlayerData.gold += 20
	level_info.gold += 20
	if not Demo.trial:
		var stages = DemoConfig.ENCOUNTERS.keys()
		Demo.next_stage = stages[mini(stages.find(level)+1,stages.size()-1)]
		# Stage 30 finishes the NORMAL campaign and unlocks Stage 31; Stage 40 is the last
		# stage that exists, so `next_stage` clamps to 40 and no Stage 41 is ever produced.
		if level == 30: Demo.campaign_complete = true
		if level == 40: Demo.hell_complete = true
	roundVictory.emit()
	return_to_camp()
	return true

func return_to_camp():
	horde_jobs.clear(); horde_active=false
	flank_active = false; flank_clock = 1.4; flank_used = 0
	elite_clock = 0.0
	if state == "CAMP": return
	state = "RESOLVING"
	timerStop()
	Demo.stop_attacks()
	epoch += 1
	# The boss node is queued for deletion below. Clear its ObjectID before any
	# HUD/diagnostic process callback can observe the new CAMP state.
	clear_boss()
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	for node in get_tree().get_nodes_in_group("monsters"):
		node.queue_free()
	# Fog is a property of Hell combat only: camp, death and menu are always bright, and the
	# stage target is dropped so no later gate can believe Hell is still applied.
	ArenaVisibility.restore(true)
	FogPierce.discard()
	Demo.kill_stacks = 0
	Demo.stack_time = 0
	state = "CAMP"
	onRoundEnd.emit()
	Demo.refresh()
	Demo.save_camp()

func _onNextLevel():
	onNextLevel.emit(level)

func getScoreboard():
	var board = score_board.instantiate()
	board.setData(level_info.duplicate())
	return board

func boss_defeated(generation: int):
	if generation == epoch and state in ["COMBAT","DEAD"] and DemoConfig.ENCOUNTERS[level].has("boss"):
		boss_victory_epoch = generation
		if state == "COMBAT": victory()
