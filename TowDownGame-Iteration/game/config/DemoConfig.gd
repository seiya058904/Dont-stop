extends RefCounted
class_name DemoConfig

const PROFILE = "experience_demo"
const INITIAL_GOLD = 9999
const INITIAL_TALENT_POINTS = 9999
const TALENT_GOLD_PRICE = 100
const SWITCH_SECONDS = 0.12 # Input debounce only; HUD keeps its .3 + .5 + .3 animation.
const MAX_DERIVATION = 2
const AMBIENT = Color(0.64, 0.69, 0.76, 1)
const MIN_RELOAD_SECONDS = 0.15
const TALENTS = {
	"T01": {"name":"火力强化", "max":3, "step":0.08},
	"T03": {"name":"熟练装填", "max":3, "step":0.05},
	"T04": {"name":"扩充携弹", "max":3, "step":0.1},
	"T10": {"name":"连杀加速", "max":3, "step":0.03, "stacks":5, "seconds":4.0},
	"T16": {"name":"连锁爆破", "max":1, "radius":32.0, "damage":2.0, "cooldown":0.4},
	"T24": {"name":"吸能修复", "max":3, "step":0.15, "cooldown":0.5}
}

static func talent_value(id: String, rank: int) -> float:
	return TALENTS[id].get("step",0.0)*rank

static func talent_effect(id: String, rank: int) -> String:
	var value = talent_value(id,rank)
	match id:
		"T01": return "累计伤害 +%d%%" % roundi(value*100)
		"T03": return "累计装填 -%d%%" % roundi(value*100)
		"T04": return "累计弹匣 +%d%%" % roundi(value*100)
		"T10": return "每层射速 +%d%%；满层 +%d%%" % [roundi(value*100),roundi(value*TALENTS[id].stacks*100)]
		"T16": return "已解锁" if rank else "未解锁"
		"T24": return "每次回复 %.2f 生命" % value
	return ""

static func talent_info(id: String) -> String:
	var d = TALENTS[id]
	match id:
		"T01": return "常驻：每级武器伤害 +%d%%（含基础伤害）" % roundi(d.step*100)
		"T03": return "常驻：每级装填时间 -%d%%，最低 %.2f 秒" % [roundi(d.step*100),MIN_RELOAD_SECONDS]
		"T04": return "常驻：每级弹匣 +%d%%；不会凭空补弹" % roundi(d.step*100)
		"T10": return "有效击杀：每层射速 +%d%% × 等级，最多%d层；%.1f秒刷新，超时归零" % [roundi(d.step*100),d.stacks,d.seconds]
		"T16": return "直接击杀：半径%.0f的小爆炸（伤害%.0f），冷却%.1f秒；派生击杀不再爆破" % [d.radius,d.damage,d.cooldown]
		"T24": return "直接击杀回复 %.2f × 等级 生命，冷却%.1f秒；假人不触发" % [d.step,d.cooldown]
	return ""

const ENCOUNTERS = {
	1:{"name":"R1 · 街口接敌", "info":"追击者为主，少量蜂群；生存45秒", "seconds":45, "roles":["E01","E01","E02"], "cap":35, "interval":0.8},
	3:{"name":"R1 · 远程交错", "info":"近战推进，喷射者间歇压制；生存45秒", "seconds":45, "roles":["E01","E02","E01","E05"], "cap":40, "interval":0.7},
	4:{"name":"R1 · 蜂群冲锋", "info":"分方向蜂群，少量预警冲锋者；生存45秒", "seconds":45, "roles":["E02","E02","E02","E04"], "cap":55, "interval":0.55}
}

static func weapon_tags(id: int) -> Array:
	if WeaponCatalog.DEFINITIONS.has(id): return WeaponCatalog.DEFINITIONS[id].tags
	if id == 6: return ["beam","energy"]
	if id == 112: return ["chain","energy"]
	if id == 114: return ["projectile","explosive","energy"]
	if id == 123: return ["projectile","spread","burst"]
	return ["projectile","spread"] if id in [1,5,8] else ["projectile"]

const WEAPON_INFO = {
	112:"首次射线主目标命中，最多3次后跳；后跳伤害逐次×75%，墙阻挡电弧。",
	114:"慢速可见大弹，接触后半径32爆炸；每目标一次伤害。",
	123:"每组3发，组内0.08秒，组间独立间隔；剩弹不足只射剩余。",
	6:"原型激光：射线阻墙，0.1秒持续tick，保留0.4秒脉冲。"
}
static func weapon_info(id: int) -> String:
	if WeaponCatalog.DEFINITIONS.has(id): return WeaponCatalog.DEFINITIONS[id].info
	return WEAPON_INFO.get(id,"保留原型弹道、开火节奏、枪体动作与音色。")
