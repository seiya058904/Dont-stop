extends RefCounted
const DAMAGE_PER_LEVEL = 0.3
const HP_PER_LEVEL = 0.5
const POINTS_PER_LEVEL = 1
static func damage(level: int) -> float: return DAMAGE_PER_LEVEL*level
static func threshold(level: int) -> float: return pow(level,2.2)+15
static func rewards(before: int, after: int) -> Dictionary:
	return {"before":before,"after":after,"damage":DAMAGE_PER_LEVEL*(after-before),"max_hp":HP_PER_LEVEL*(after-before),"heal":HP_PER_LEVEL*(after-before),"points":POINTS_PER_LEVEL*(after-before)}
static func help_text() -> String:
	return "等级有什么作用？\n有效击杀获得1经验，训练靶不计。经验需求 = 等级^2.2 + 15，超出经验保留。\n每级基础伤害 +%.1f，最大生命 +%.1f，同时只回复新增的 %.1f 生命；不会回满。奖励点 +%d，可用于奖励 NPC 或计划天赋。\n等级、经验与成长随营地存档保存。" % [DAMAGE_PER_LEVEL,HP_PER_LEVEL,HP_PER_LEVEL,POINTS_PER_LEVEL]
static func notice(row: Dictionary) -> String:
	return "等级提升 Lv.%d → Lv.%d\n最大生命 +%.1f · 回复 +%.1f\n基础伤害 +%.1f · 奖励点 +%d" % [row.before,row.after,row.max_hp,row.heal,row.damage,row.points]
