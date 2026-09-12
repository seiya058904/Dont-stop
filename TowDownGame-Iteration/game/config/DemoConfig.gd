extends RefCounted
class_name DemoConfig

const PROFILE = "experience_demo"
const INITIAL_GOLD = 9999
const INITIAL_TALENT_POINTS = 9999
const TALENT_GOLD_PRICE = 100
const SWITCH_SECONDS = 0.12 # Input debounce only; HUD keeps its .3 + .5 + .3 animation.
const MAX_DERIVATION = 2
const AMBIENT = Color(0.64, 0.69, 0.76, 1)
const TALENTS = {
	"T01": {"name":"火力强化", "max":3, "info":"常驻：每级武器伤害 +8%（含基础伤害）"},
	"T03": {"name":"熟练装填", "max":3, "info":"常驻：每级装填时间 -5%，最低 0.15 秒"},
	"T04": {"name":"扩充携弹", "max":3, "info":"常驻：每级弹匣 +10%；不会凭空补弹"},
	"T10": {"name":"连杀加速", "max":3, "info":"有效击杀：每层射速 +3% × 等级，最多5层；4秒刷新，超时归零"},
	"T16": {"name":"连锁爆破", "max":1, "info":"直接击杀：半径32的小爆炸（伤害2），冷却0.4秒；派生击杀不再爆破"},
	"T24": {"name":"吸能修复", "max":3, "info":"直接击杀回复 0.15 × 等级 生命，冷却0.5秒；假人不触发"}
}
const ENCOUNTERS = {
	1:{"name":"R1 · 街口接敌", "info":"追击者为主，少量蜂群；生存45秒", "seconds":45, "roles":["E01","E01","E02"], "cap":35, "interval":0.8},
	3:{"name":"R1 · 远程交错", "info":"近战推进，喷射者间歇压制；生存45秒", "seconds":45, "roles":["E01","E02","E01","E05"], "cap":40, "interval":0.7},
	4:{"name":"R1 · 蜂群冲锋", "info":"分方向蜂群，少量预警冲锋者；生存45秒", "seconds":45, "roles":["E02","E02","E02","E04"], "cap":55, "interval":0.55}
}

static func weapon_tags(id: int) -> Array:
	if id == 6: return ["beam","energy"]
	if id == 112: return ["chain","energy"]
	if id == 114: return ["projectile","explosive","energy"]
	if id == 123: return ["projectile","spread","burst"]
	return ["projectile","spread"] if id in [1,5,8] else ["projectile"]
