extends RefCounted
class_name DemoConfig

const NORMAL_INCOMING = 0.875
const BOSS_INCOMING = 1.1155
## Hell Mode's damage axis (1.08x -> 1.90x) is applied in full to telegraphed attacks and
## at this weight to raw body contact. Contact is the one source the player cannot dodge,
## so scaling it fully would turn a fogged Hell wave into unavoidable chip damage and would
## make difficulty come from HP totals rather than from the fight.
const CONTACT_DAMAGE_WEIGHT = 0.5
## Hell uses a smaller share of the same axis. Contact is the one attack that carries no footprint
## to read, so at Hell's top end the full axis made a single touch worth more than two fifths of a
## starting health bar. B11 pairs this with the player-side contact window in game/hero/Hero.gd:
## the window bounds how OFTEN contact can land, this bounds how much each landing is worth.
const CONTACT_DAMAGE_WEIGHT_HELL = 0.35
const PROFILE = "experience_demo"
const INITIAL_GOLD = 9999
const INITIAL_TALENT_POINTS = 9999
## Kept ONLY for the legacy reward shop (原型奖励). Talent prices are data-driven per
## quality and rank since B13: TALENT_GOLD_PRICE is no longer a talent price source.
const TALENT_GOLD_PRICE = 100
const SWITCH_SECONDS = 0.12 # Input debounce only; HUD keeps its .3 + .5 + .3 animation.
const MAX_DERIVATION = 2
const AMBIENT = Color(0.64, 0.69, 0.76, 1)
const MIN_RELOAD_SECONDS = 0.15
## B13: talents share the upgrade system's three player-visible qualities. Quality is the
## value grade of the talent itself (not a route, not a rank): 普通=渐进成长, 稀有=明显/组合,
## 传说=机制解锁. Rank (1..max) is how many times a talent was bought and stays independent.
## Core B13 rule: overall, talent value must exceed upgrade value; legends change how fights play.
const TALENT_QUALITY = {
	"T01":1,"T03":1,"T04":1,"T05":1,"T07":1,"T08":1,"T09":3,"T18":1,"T20":1,
	"T02":2,"T06":2,"T10":2,"T11":2,"T12":2,"T15":2,"T17":2,"T21":2,"T22":2,"T24":2,
	"T13":3,"T14":3,"T16":3,"T19":3,"T23":3
}
## Data-driven prices per rank (index = next rank - 1), calibrated against the 9999 demo
## wallet: all commons ≈ 6750 gold, each rare ≈ 1650, each legend 2400 - a full account
## (~35k) is deliberately out of reach of the starting wallet. B13.1: the legendary talent
## price sits ABOVE the legendary upgrade price band's upper edge (AttachmentCatalog tops
## out at 2000), because a legend talent is max=1, has no later rank cost, and the talent
## system is the premium one - a legend must never be the cheaper legendary purchase.
const TALENT_GOLD_PRICES = {1:[150,250,350],2:[400,550,700],3:[2400]}
const TALENT_POINT_PRICES = {1:[1,1,2],2:[2,3,4],3:[5]}
const TALENTS = {
	"T02": {"name":"快速循环","max":3,"step":0.1,"info":"每级射速+10%；热流转为每tick伤害，转管超过24发/秒的部分转单发伤害；原激光提升脉冲频率，轨道炮只缩短发射后冷却。","unit":"射速/DPS"},
	"T05": {"name":"弹道延展","max":3,"step":0.1,"info":"每级有效射程/实体弹寿命+10%；墙仍阻断。","unit":"射程"},
	"T06": {"name":"弱点识别","max":3,"step":0.06,"info":"每级暴击率+6个百分点；每次命中只采样一次，暴击×1.5。","unit":"暴击率百分点"},
	"T07": {"name":"生存余量","max":3,"step":1.0,"info":"每级最大生命+1（初始基础5的20%），购买补该增量；旧头盔生命增量作为历史来源保留。","unit":"生命"},
	"T08": {"name":"轻装移动","max":3,"step":0.03,"info":"每级基础移速+3%；不改变冲刺。旧蓝靴来源保留，详情另列。","unit":"基础移速"},
	"T09": {"name":"强磁回收","max":3,"values":[120.0,180.0,240.0],"info":"金币在120/180/240范围内加速飞来，到达才入账；墙阻挡，暂停停止。医疗包独立判定，满血不消耗。","unit":"金币吸引半径","gold_prices":[700,1000,1400],"point_prices":[3,4,5]},
	"T11": {"name":"弹药回流","max":3,"step":1.0,"kills":5,"info":"每5次有效武器击杀补1×等级备用弹匣；假人、派生击杀不计，不填弹匣。","unit":"每5杀弹匣"},
	"T12": {"name":"首发重击","max":3,"values":[0.25,0.4,0.55],"info":"完成实际补弹后的第一发伤害+25/40/55%；同次同时发射的弹丸共享，不含后续连发。取消装填不触发。","unit":"首发伤害"},
	"T13": {"name":"贯穿专精","max":1,"step":2.0,"info":"明确兼容的直射攻击+2贯穿；总目标最多8，实墙阻断，不影响爆炸/跟踪/锯盘。轨道炮按蓄力比例兑现；已达上限时不继续增加。","unit":"额外贯穿"},
	"T14": {"name":"静电跃迁","max":1,"step":0.25,"cooldown":0.5,"damage":0.5,"radius":80.0,"info":"直接命中25%概率电弧到附近一个不同目标，50%命中伤害；冷却0.5秒，墙阻挡；派生不触发。","unit":"触发概率"},
	"T15": {"name":"灼热弹道","max":3,"step":0.3,"seconds":1.5,"tick":0.25,"info":"直接命中施加1.5秒灼烧，每0.25秒至少伤害0.3×等级，随发射时单发伤害的2%×等级成长，上限0.6×等级；同来源刷新，一条计时记录。","unit":"每次灼烧tick"},
	"T17": {"name":"低温冲击","max":3,"step":0.08,"seconds":1.5,"info":"直接命中减速8%×等级，1.5秒；最高24%，Boss仅四分之一，不叠无限层。","unit":"减速"},
	"T18": {"name":"冲击放大","max":3,"step":0.15,"info":"普通敌人冲量每级+15%；Boss免推移。","unit":"冲量"},
	"T19": {"name":"应急护盾","max":1,"cooldown":6.0,"step":1.0,"info":"战斗抵消一次正伤害，基础恢复6秒；有效原生击杀缩短0.35秒，破盾后至少2秒才可恢复；只有一层。","unit":"抵消次数"},
	"T20": {"name":"战后修复","max":3,"step":0.1,"info":"有效遭遇胜利回复最大生命10%×等级；手动回营、选关和重复结算不触发。","unit":"胜利回复生命比例"},
	"T21": {"name":"精英猎手","max":3,"values":[0.15,0.25,0.35],"info":"对精英目标伤害+15/25/35%；Boss不适用。精英按关卡计划与存活预算出现，并非所有特殊怪都是精英。","unit":"对精英伤害"},
	"T22": {"name":"密集火网","max":3,"step":0.08,"radius":100.0,"count":3,"interval":0.2,"info":"100范围内至少3名存活敌人时伤害+8%×等级；每0.2秒更新，发射快照保留该次状态。","unit":"条件伤害"},
	"T23": {"name":"暴击回响","max":1,"step":0.4,"radius":85.0,"cooldown":0.15,"info":"直接暴击向附近一个不同目标回响40%该次伤害，冷却0.15秒；墙阻挡，回响不暴击、不递归。","unit":"回响伤害比例"},

	"T01": {"name":"火力强化", "max":3, "step":0.15},
	"T03": {"name":"熟练装填", "max":3, "step":0.08},
	"T04": {"name":"扩充弹匣", "max":3, "step":0.18},
	"T10": {"name":"连杀加速", "max":3, "step":0.04, "stacks":5, "seconds":4.0},
	"T16": {"name":"连锁爆破", "max":1, "radius":40.0, "damage":2.6, "cooldown":0.4},
	"T24": {"name":"吸能修复", "max":3, "step":0.2, "cooldown":0.5}
}

static func talent_quality(id: String) -> int:
	return int(TALENT_QUALITY.get(id,1))

static func talent_quality_name(id: String) -> String:
	return AttachmentCatalog.QUALITY_NAMES[clampi(talent_quality(id),1,3)-1]

## Price of buying `rank` (the rank being purchased, 1-based) of a talent in the given
## currency. Recorded per payment, so reset/refund keeps replaying actual payments.
static func talent_gold_price(id: String, rank: int) -> int:
	var ladder: Array = TALENTS[id].get("gold_prices",TALENT_GOLD_PRICES[talent_quality(id)])
	return int(ladder[clampi(rank-1,0,ladder.size()-1)])

static func talent_point_price(id: String, rank: int) -> int:
	var ladder: Array = TALENTS[id].get("point_prices",TALENT_POINT_PRICES[talent_quality(id)])
	return int(ladder[clampi(rank-1,0,ladder.size()-1)])

static func talent_value(id: String, rank: int) -> float:
	var d = TALENTS[id]
	if rank <= 0: return 0.0
	if d.has("values"): return d.values[mini(rank,d.max)-1]
	return d.get("step",0.0)*rank

static func talent_effect(id: String, rank: int) -> String:
	var value = talent_value(id,rank)
	if id == "T09": return "金币吸引半径：%.0f" % value
	if TALENTS[id].has("unit"):
		var unit = TALENTS[id].unit
		if unit in ["生命","每5杀弹匣","每次灼烧tick","额外贯穿","抵消次数"]: return "累计 %s：%.2f" % [unit,value]
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
		"T10": return "有效击杀：每层射速 +%d%% × 等级，最多%d层；%.1f秒刷新，超时归零。热流及封顶转管转换为单次伤害。" % [roundi(d.step*100),d.stacks,d.seconds]
		"T16": return "原生武器击杀：半径%.0f爆炸，伤害取%.2f与该攻击25%%的较大值（上限12），冷却%.1f秒；派生不再爆破" % [d.radius,d.damage,d.cooldown]
		"T24": return "武器原生击杀回复 %.2f × 等级 生命，冷却%.1f秒；假人不触发" % [d.step,d.cooldown]
	return ""

static var ENCOUNTERS = M5Content.encounters()

static func weapon_tags(id: int) -> Array:
	if WeaponCatalog.DEFINITIONS.has(id): return WeaponCatalog.DEFINITIONS[id].tags
	if id == 6: return ["beam","energy"]
	if id == 112: return ["chain","energy"]
	if id == 114: return ["projectile","explosive","energy"]
	if id == 123: return ["projectile","spread","burst","straight"]
	return ["projectile","spread","straight"] if id in [1,5,8] else ["projectile","straight"]

const WEAPON_INFO = {
	112:"一次最多3根放电、10个不同目标；连接140，后跳×90%且至少保留60%；每目标一次，墙阻挡。",
	114:"慢速可见大弹，接触后半径48爆炸；每目标一次伤害。",
	123:"每组3发，组内0.08秒，组间独立间隔；剩弹不足只射剩余。",
	6:"原型激光：射线阻墙，0.1秒持续tick，保留0.4秒脉冲。"
}
static func weapon_info(id: int) -> String:
	if id == 112: return "一次最多%d根放电、%d个不同目标；连接距离%.0f，后跳×90%%且至少保留60%%；每目标一次，墙阻挡。" % [WeaponCatalog.ARC.roots,WeaponCatalog.ARC.targets,WeaponCatalog.ARC.link_range]
	if id == 114: return "慢速可见大弹，接触后半径%.0f爆炸；每目标一次伤害。" % WeaponCatalog.PLASMA_RADIUS
	if WeaponCatalog.DEFINITIONS.has(id): return WeaponCatalog.DEFINITIONS[id].info
	return WEAPON_INFO.get(id,"保留原型弹道、开火节奏、枪体动作与音色。")
