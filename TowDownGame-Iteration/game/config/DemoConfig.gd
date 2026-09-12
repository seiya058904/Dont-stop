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
	"T02": {"name":"快速循环","max":3,"step":0.06,"info":"每级射速+6%；热流保持0.1秒tick并提升每tick伤害，原激光仅提升脉冲频率。","unit":"射速/DPS"},
	"T05": {"name":"弹道延展","max":3,"step":0.1,"info":"每级有效射程/实体弹寿命+10%；墙仍阻断。","unit":"射程"},
	"T06": {"name":"弱点识别","max":3,"step":0.05,"info":"每级暴击率+5个百分点；每次命中只采样一次，暴击×1.5。","unit":"暴击率百分点"},
	"T07": {"name":"生存余量","max":3,"step":1.0,"info":"每级最大生命+1（初始基础5的20%），购买补该增量；旧头盔生命增量作为历史来源保留。","unit":"生命"},
	"T08": {"name":"轻装移动","max":3,"step":0.03,"info":"每级基础移速+3%；不改变冲刺。旧蓝靴来源保留，详情另列。","unit":"基础移速"},
	"T09": {"name":"拾取磁场","max":3,"step":0.2,"info":"金币/回血拾取半径每级+20%；隔墙不可吸附，不执行寻路。","unit":"拾取范围"},
	"T11": {"name":"弹药回流","max":3,"step":2.0,"kills":5,"info":"每5次有效直接击杀补2×等级备弹；假人、派生击杀不计，不填弹匣。","unit":"每5杀备弹"},
	"T12": {"name":"首发重击","max":3,"values":[0.15,0.2,0.25],"info":"完成实际补弹后的第一发伤害+15/20/25%；同次同时发射的弹丸共享，不含后续连发。取消装填不触发。","unit":"首发伤害"},
	"T13": {"name":"贯穿专精","max":1,"step":1.0,"info":"明确兼容的直射攻击+1贯穿；总目标最多8，实墙阻断，不影响爆炸/跟踪/锯盘。","unit":"额外贯穿"},
	"T14": {"name":"静电跃迁","max":1,"step":0.2,"cooldown":0.6,"damage":0.4,"radius":80.0,"info":"直接命中20%概率电弧到附近一个不同目标，40%命中伤害；冷却0.6秒，墙阻挡；派生不触发。","unit":"触发概率"},
	"T15": {"name":"灼热弹道","max":3,"step":0.2,"seconds":1.5,"tick":0.25,"info":"直接命中施加1.5秒灼烧，每0.25秒伤害0.2×等级；同来源刷新，一条计时记录。","unit":"每次灼烧tick"},
	"T17": {"name":"低温冲击","max":3,"step":0.08,"seconds":1.5,"info":"直接命中减速8%×等级，1.5秒；最高24%，Boss仅四分之一，不叠无限层。","unit":"减速"},
	"T18": {"name":"冲击放大","max":3,"step":0.15,"info":"普通敌人冲量每级+15%；Boss免推移。","unit":"冲量"},
	"T19": {"name":"应急护盾","max":1,"cooldown":8.0,"step":1.0,"info":"战斗抵消一次正伤害，冷却8秒；先占用冷却再反馈，同帧下一击仍受伤。","unit":"抵消次数"},
	"T20": {"name":"战后修复","max":3,"step":0.1,"info":"有效遭遇胜利回复最大生命10%×等级；手动回营、选关和重复结算不触发。","unit":"胜利回复生命比例"},
	"T21": {"name":"精英猎手","max":3,"values":[0.1,0.15,0.2],"info":"对显式is_elite目标伤害+10/15/20%；Boss不适用。当前R1未增加精英内容。","unit":"对精英伤害"},
	"T22": {"name":"密集火网","max":3,"step":0.05,"radius":100.0,"count":3,"interval":0.2,"info":"100范围内至少3名存活敌人时伤害+5%×等级；每0.2秒更新，发射快照保留该次状态。","unit":"条件伤害"},
	"T23": {"name":"暴击回响","max":1,"step":0.3,"radius":70.0,"cooldown":0.15,"info":"直接暴击向附近一个不同目标回响30%该次伤害，冷却0.15秒；墙阻挡，回响不暴击、不递归。","unit":"回响伤害比例"},

	"T01": {"name":"火力强化", "max":3, "step":0.08},
	"T03": {"name":"熟练装填", "max":3, "step":0.05},
	"T04": {"name":"扩充携弹", "max":3, "step":0.1},
	"T10": {"name":"连杀加速", "max":3, "step":0.03, "stacks":5, "seconds":4.0},
	"T16": {"name":"连锁爆破", "max":1, "radius":32.0, "damage":2.0, "cooldown":0.4},
	"T24": {"name":"吸能修复", "max":3, "step":0.15, "cooldown":0.5}
}

static func talent_value(id: String, rank: int) -> float:
	var d = TALENTS[id]
	if rank <= 0: return 0.0
	if d.has("values"): return d.values[mini(rank,d.max)-1]
	return d.get("step",0.0)*rank

static func talent_effect(id: String, rank: int) -> String:
	var value = talent_value(id,rank)
	if TALENTS[id].has("unit"):
		var unit = TALENTS[id].unit
		if unit in ["生命","每5杀备弹","每次灼烧tick","额外贯穿","抵消次数"]: return "累计 %s：%.2f" % [unit,value]
		return "累计 %s：%.0f%%" % [unit,value*100]
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
	if d.has("info"): return d.info
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
	if id == 123: return ["projectile","spread","burst","straight"]
	return ["projectile","spread","straight"] if id in [1,5,8] else ["projectile","straight"]

const WEAPON_INFO = {
	112:"首次射线主目标命中，最多3次后跳；后跳伤害逐次×75%，墙阻挡电弧。",
	114:"慢速可见大弹，接触后半径32爆炸；每目标一次伤害。",
	123:"每组3发，组内0.08秒，组间独立间隔；剩弹不足只射剩余。",
	6:"原型激光：射线阻墙，0.1秒持续tick，保留0.4秒脉冲。"
}
static func weapon_info(id: int) -> String:
	if WeaponCatalog.DEFINITIONS.has(id): return WeaponCatalog.DEFINITIONS[id].info
	return WEAPON_INFO.get(id,"保留原型弹道、开火节奏、枪体动作与音色。")
