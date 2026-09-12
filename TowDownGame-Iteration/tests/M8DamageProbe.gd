extends "res://game/monster/TacticalEnemy.gd"
# Test-only tracing, preserving the complete production damage chain.
var damage_trace = []
var volley = 0
func receive_damage(amount: float, critical: bool, context: Dictionary):
	var before = HP
	var armor_before = armor
	super.receive_damage(amount,critical,context)
	damage_trace.append({"ms":Time.get_ticks_msec(),"volley":volley,"input":context.get("damage",0),"resolved":amount,"applied":before-HP,"hp_before":before,"hp_after":HP,"armor_before":armor_before,"armor_after":armor,"crit":critical,"depth":context.get("depth",0),"shards":context.get("shards",0),"burn":context.get("burn_talent",0),"impulse":context.get("impulse",0),"phase_two":phase_two})
