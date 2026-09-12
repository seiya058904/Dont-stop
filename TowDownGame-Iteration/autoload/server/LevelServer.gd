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

func _ready() -> void:
	timer.wait_time = 0.1
	timer.timeout.connect(_timeout)
	add_child(timer)

func can_start(stage: int) -> bool:
	return state == "CAMP" and is_instance_valid(Utils.player) and not Utils.player.is_dead and PlayerData.player_hp > 0 and Utils.player.gun != null and PlayerData.player_weapon_list.values().has(Utils.player.gun) and DemoConfig.ENCOUNTERS.has(stage)

func roundStart() -> bool:
	if not can_start(Demo.selected_stage): return false
	if is_instance_valid(town): town.clear_practice()
	state = "PREPARING"
	Demo.stop_attacks()
	epoch += 1
	level = Demo.selected_stage
	resetLevelInfo()
	spawn_index = 0
	wait_time_temp = 0
	level_time = DemoConfig.ENCOUNTERS[level].seconds
	state = "COMBAT"
	timerStart()
	onRoundStart.emit()
	return true

func resetLevelInfo():
	level_info = {"time":0.0,"kill":0,"gold":0}

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
	level_time = maxf(0,level_time-0.1)
	level_info.time += 0.1
	if level_time <= 0: victory()
	else:
		onMonsterCreate()
		onTimeTick.emit(int(ceil(level_time)))

func onMonsterCreate():
	wait_time_temp += 0.1
	var config = DemoConfig.ENCOUNTERS[level]
	var phase = level_info.time / config.seconds
	# Arrival, build, peak, brief recovery. No hidden health scaling.
	var multiplier = 1.3 if phase < 0.2 else (0.7 if phase < 0.8 else 1.5)
	if wait_time_temp >= config.interval * multiplier:
		wait_time_temp = 0
		monsterCreate.emit()

func victory() -> bool:
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
	roundVictory.emit()
	return_to_camp()
	return true

func return_to_camp():
	if state == "CAMP": return
	state = "RESOLVING"
	timerStop()
	Demo.stop_attacks()
	epoch += 1
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	for node in get_tree().get_nodes_in_group("monsters"):
		node.queue_free()
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
