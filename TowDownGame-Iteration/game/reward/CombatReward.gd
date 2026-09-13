extends BaseReward
# Direct-event reward layer. Derived damage never enters these hooks.
var direct_hits = 0
var direct_kills = 0
var cooldown = 0.0
var armed = false
var move_time = 0.0
var moving_buff = false

func onRewardStart():
	connect_kill = id in [18,21]

func _physics_process(delta):
	cooldown = maxf(0,cooldown-delta)
	if id != 22: return
	var moving = LevelServer.state == "COMBAT" and is_instance_valid(Utils.player) and Utils.player.velocity.length() > 5 and not Utils.player.is_dead
	move_time = minf(2.0,move_time+delta) if moving else 0.0
	var active = move_time >= 2.0
	if active != moving_buff:
		moving_buff = active
		Demo.refresh()

func modify_direct(target, amount: float) -> float:
	if id == 14 and (target.is_elite or target.is_boss): return amount*0.05*count
	if id == 15:
		direct_hits += 1
		if direct_hits >= 8-count:
			direct_hits = 0
			return amount*0.35
	return 0.0

func after_direct(target, amount: float, critical: bool, context: Dictionary):
	if id == 16 and critical and randf() < 0.10+0.05*count:
		var child = context.duplicate(true)
		child.damage = amount; child.shards = 2; child.shard_ratio = 0.125
		child.range_mul = 0.3
		var angle = Utils.player.global_position.direction_to(target.global_position).angle()
		Combat.fragments(target.global_position,angle,child,target,180.0)
	if target.is_die: return
	if id == 12 and randf() < 0.07+0.03*count:
		target.apply_burn("R12",maxf(0.05,amount*0.125),1.0,context)
	if id == 13 and randf() < 0.06+0.04*count:
		target.apply_slow("R13",0.20,1.0)

func incoming(amount: float, percentage: bool) -> float:
	if id == 17 and armed and not percentage:
		armed = false
		return -amount*0.20
	return 0.0

func received():
	if id == 17 and cooldown <= 0:
		armed = true; cooldown = 7.0-count
	if id == 19 and cooldown <= 0 and PlayerData.player_hp > 0 and PlayerData.player_hp < PlayerData.player_hp_max*0.3:
		cooldown = 20.0
		PlayerData.addPlayerHp(0.5+0.5*count)

func onKill(_monster: BaseMonster):
	direct_kills += 1
	var limit = [12,10,8][count-1] if id == 18 else [15,12,10][count-1]
	if direct_kills >= limit:
		direct_kills = 0
		if id == 18: PlayerData.addPlayerHp(0.5)
		elif id == 21: PlayerData.reserve_magazines += 1

func saved_state() -> Dictionary:
	return {"hits":direct_hits,"kills":direct_kills,"cooldown":cooldown,"armed":armed,"move_time":move_time,"moving_buff":moving_buff}

func restore_state(state: Dictionary):
	direct_hits = int(state.get("hits",0)); direct_kills = int(state.get("kills",0))
	cooldown = float(state.get("cooldown",0)); armed = state.get("armed",false)
	move_time = float(state.get("move_time",0)); moving_buff = state.get("moving_buff",false)
