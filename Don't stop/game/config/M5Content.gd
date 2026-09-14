extends RefCounted
class_name M5Content

# Additional timed arrivals overlap living cohorts; HP and the roster remain frozen.
const HORDES = {
	21:{"batch":4,"window":4.0,"step":0.3,"floor":6,"windows":2},
	22:{"batch":4,"window":3.8,"step":0.3,"floor":6,"windows":2},
	23:{"batch":4,"window":3.7,"step":0.3,"floor":7,"windows":2},
	24:{"batch":5,"window":3.4,"step":0.25,"floor":9,"windows":2},
	25:{"batch":5,"window":3.1,"step":0.25,"floor":9,"windows":2},
	26:{"batch":6,"window":3.0,"step":0.25,"floor":10,"windows":2},
	27:{"batch":12,"window":2.2,"step":0.18,"floor":14,"windows":3},
	28:{"batch":14,"window":2.0,"step":0.18,"floor":16,"windows":3},
	29:{"batch":16,"window":1.8,"step":0.18,"floor":18,"windows":3}
}

const ENEMIES = {
	"E01":{"name":"追击者","hp":2.0,"speed":90.0,"role":"近战追击"},
	"E02":{"name":"轻型蜂群","hp":1.2,"speed":105.0,"role":"成群接触"},
	"E03":{"name":"重甲破坏者","hp":12.0,"speed":82.0,"role":"持续迫近、可破甲重冲锋、失败后续追","armor":9.0},
	"E04":{"name":"预警冲锋者","hp":5.0,"speed":65.0,"role":"固定方向冲刺"},
	"E05":{"name":"远程喷射者","hp":3.0,"speed":50.0,"role":"停步实体弹"},
	"E06":{"name":"自爆逼近者","hp":3.0,"speed":125.0,"role":"高速追近、近身锁定预警自爆；提前击杀取消"},
	"E07":{"name":"分裂母体","hp":8.0,"speed":72.0,"role":"前移繁殖、有限蜂群追击、死亡分裂；子体不生产"},
	"E08":{"name":"支援治疗者","hp":4.0,"speed":96.0,"role":"跟随前排、受压绕位；每目标最多恢复3生命"},
	"E09":{"name":"正面盾卫","hp":8.0,"speed":78.0,"role":"正面推进夹击、侧后弱点、可破盾","armor":7.0},
	"E10":{"name":"标记炮击者","hp":4.0,"speed":78.0,"role":"移动炮击循环、近身撤步、蓄力射线"},
	"E11":{"name":"侧绕猎手","hp":4.0,"speed":122.0,"role":"沿侧面切入、短扑、落空后持续追近"},
	"E12":{"name":"易爆载能体","hp":2.0,"speed":95.0,"role":"推进扇面放电；死亡对敌有限爆破"}
}
const BOSSES = {
	"B01":{"name":"破城机甲","hp":4400.0,"speed":84.0,"role":"冲锋、重扇斩、震地；半血推进加速与护卫","armor":120.0},
	"B02":{"name":"蜂巢聚合体","hp":6000.0,"speed":76.0,"role":"追击召唤、连续封区、扇面脉冲；半血追近与自爆蜂群"},
	"B03":{"name":"棱镜核心","hp":6200.0,"speed":115.0,"role":"切侧突进、方向扫束、快速扇射；半血反向压迫"}
}
static func definition(id: String) -> Dictionary:
	return ENEMIES.get(id,BOSSES.get(id,{}))
static func spawn(id: String, parent: Node, point: Vector2, summoned = false):
	if definition(id).is_empty(): return null
	var actor = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	if id in ["E02","E04","E05"]:
		actor.set_script(load("res://game/monster/DemoEnemy.gd")); actor.role = id
	elif id != "E01":
		actor.set_script(load("res://game/monster/TacticalEnemy.gd")); actor.role = id; actor.summoned = summoned
	var d = definition(id)
	actor.setData({"speed":d.speed,"hp":d.hp,"hurt":1})
	actor.set_meta("content_id",id)
	actor.set_meta("summoned",summoned)
	actor.set_meta("spawn_epoch",LevelServer.epoch)
	actor.set_meta("born_ms",Time.get_ticks_msec())
	actor.position = parent.to_local(point)
	if is_instance_valid(LevelServer.town): actor.setDeathCallBack(LevelServer.town.onMonsterDeath)
	parent.add_child(actor)
	if LevelServer.level in [27,28,29] and id in ["E01","E02"]: actor.SPEED*=1.2
	return actor

const REGIONS = {
	"R1":{"name":"营地外街区","info":"原街口改良；路口墙角、四向渐进入场","sides":[0,1,2,3]},
	"R2":{"name":"货运场","info":"宽车道、四组货物绕行；东西方向压迫","sides":[0,2]},
	"R3":{"name":"冰原冷却站","info":"冰裂地表与霜墙；交错短墙、两侧开阔","sides":[1,3,0]},
	"R4":{"name":"熔岩处理区","info":"暗岩热裂、墙内熔流；四个互通小场与宽绕行口","sides":[0,1,2,3]},
	"R5":{"name":"过生长走廊","info":"草块、浅水沟与蔓生废墙；三条互通宽通路","sides":[1,3]},
	"R6":{"name":"山地核心平台","info":"岩柱与能量裂隙；多出口开阔中心","sides":[0,2,1,3]}
}
const WALLS = {
	"R2":[Rect2(-260,-185,105,70),Rect2(150,-185,105,70),Rect2(-260,105,105,70),Rect2(150,105,105,70)],
	"R3":[Rect2(-255,-130,190,24),Rect2(55,-15,210,24),Rect2(-225,110,170,24)],
	"R4":[Rect2(-245,-120,150,24),Rect2(95,-120,150,24),Rect2(-245,95,150,24),Rect2(95,95,150,24),Rect2(-245,-40,24,70),Rect2(221,-40,24,70)],
	"R5":[Rect2(-135,-225,26,155),Rect2(-135,60,26,155),Rect2(109,-225,26,155),Rect2(109,60,26,155)],
	"R6":[Rect2(-175,-135,55,55),Rect2(120,-135,55,55),Rect2(-175,80,55,55),Rect2(120,80,55,55)]
}
static func encounters() -> Dictionary:
	return {
		1:{"name":"R1 · 01 街口接敌","region":"R1","info":"生存45秒；渐进；敌群 E01 E01 E02","seconds":45,"roles":["E01", "E01", "E02"],"cap":35,"interval":0.8,"rhythm":"渐进"},
		2:{"name":"R1 · 02 蜂群分流","region":"R1","info":"生存45秒；轮换；敌群 E02 E02 E01","seconds":45,"roles":["E02", "E02", "E01"],"cap":38,"interval":0.65,"rhythm":"轮换"},
		3:{"name":"R1 · 03 远程交错","region":"R1","info":"生存45秒；渐进；敌群 E01 E02 E01 E05","seconds":45,"roles":["E01", "E02", "E01", "E05"],"cap":40,"interval":0.7,"rhythm":"渐进"},
		4:{"name":"R1 · 04 蜂群冲锋","region":"R1","info":"生存45秒；脉冲；敌群 E02 E02 E02 E04","seconds":45,"roles":["E02", "E02", "E02", "E04"],"cap":55,"interval":0.55,"rhythm":"脉冲"},
		5:{"name":"R1 · 05 街区精英","region":"R1","info":"生存45秒；精英；敌群 E01 E02 E05 E04","seconds":45,"roles":["E01", "E02", "E05", "E04"],"cap":40,"interval":0.65,"rhythm":"精英"},
		6:{"name":"R2 · 06 装甲车道","region":"R2","info":"生存45秒；渐进；敌群 E01 E03","seconds":45,"roles":["E01", "E03"],"cap":47,"interval":0.57,"rhythm":"渐进"},
		7:{"name":"R2 · 07 爆点清场","region":"R2","info":"生存45秒；轮换；敌群 E02 E02 E06","seconds":45,"roles":["E02", "E02", "E06"],"cap":49,"interval":0.55,"rhythm":"轮换"},
		8:{"name":"R2 · 08 甲后射界","region":"R2","info":"生存45秒；协同；敌群 E03 E05 E01","seconds":45,"roles":["E03", "E05", "E01"],"cap":45,"interval":0.68,"rhythm":"协同"},
		9:{"name":"R2 · 09 货场突围","region":"R2","info":"生存45秒；脉冲；敌群 E02 E04 E03 E02","seconds":45,"roles":["E02", "E04", "E03", "E02"],"cap":59,"interval":0.43,"rhythm":"脉冲"},
		10:{"name":"R2 · 10 破城机甲","region":"R2","info":"击败Boss；无倒计时自动胜利；Boss；敌群 ","seconds":0,"roles":[],"cap":15,"interval":1.5,"rhythm":"Boss","boss":"B01"},
		11:{"name":"R3 · 11 侧翼接近","region":"R3","info":"生存45秒；轮换；敌群 E01 E11","seconds":45,"roles":["E01", "E11"],"cap":45,"interval":0.55,"rhythm":"轮换"},
		12:{"name":"R3 · 12 盾后蜂群","region":"R3","info":"生存45秒；协同；敌群 E09 E02 E02","seconds":45,"roles":["E09", "E02", "E02"],"cap":49,"interval":0.51,"rhythm":"协同"},
		13:{"name":"R3 · 13 标记交叉火力","region":"R3","info":"生存45秒；交替；混合追击 / 侧翼 / 支援；敌群 E01 E11 E10 E02","seconds":45,"roles":["E01","E11","E10","E02"],"cap":38,"interval":0.55,"rhythm":"交替"},
		14:{"name":"R3 · 14 短墙折射","region":"R3","info":"生存45秒；轮换；敌群 E04 E11 E02","seconds":45,"roles":["E04", "E11", "E02"],"cap":56,"interval":0.47,"rhythm":"轮换"},
		15:{"name":"R3 · 15 冷却精英","region":"R3","info":"生存45秒；精英；混合追击 / 侧翼 / 支援；敌群 E09 E11 E02 E05 E06","seconds":45,"roles":["E09","E11","E02","E05","E06"],"cap":56,"interval":0.51,"rhythm":"精英"},
		16:{"name":"R4 · 16 母体增殖","region":"R4","info":"生存45秒；高速追击群为主，保留特殊协同；中段同方向有限突袭","seconds":45,"roles":["E01","E02","E07","E02","E07","E01","E02","E07","E02","E07"],"cap":52,"interval":0.53,"rhythm":"渐进"},
		17:{"name":"R4 · 17 后排修复","region":"R4","info":"生存45秒；高速追击群为主，保留特殊协同；中段同方向有限突袭","seconds":45,"roles":["E01","E02","E08","E02","E09","E01","E02","E06","E02","E08"],"cap":47,"interval":0.53,"rhythm":"协同"},
		18:{"name":"R4 · 18 载能连爆","region":"R4","info":"生存45秒；高速追击群为主，保留特殊协同；中段同方向有限突袭","seconds":45,"roles":["E01","E02","E12","E02","E11","E01","E02","E12","E02","E11"],"cap":70,"interval":0.39,"rhythm":"脉冲"},
		19:{"name":"R4 · 19 再生压迫","region":"R4","info":"生存45秒；高速追击群为主，保留特殊协同；中段同方向有限突袭","seconds":45,"roles":["E01","E02","E07","E02","E08","E01","E02","E06","E02","E07"],"cap":52,"interval":0.49,"rhythm":"协同"},
		20:{"name":"R4 · 20 蜂巢聚合体","region":"R4","info":"击败Boss；无倒计时自动胜利；Boss；敌群 ","seconds":0,"roles":[],"cap":20,"interval":1.6,"rhythm":"Boss","boss":"B02"},
		21:{"name":"R5 · 21 双重防线","region":"R5","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E03","E02","E09","E01","E02","E06","E02","E03"],"cap":65,"interval":0.42,"rhythm":"协同"},
		22:{"name":"R5 · 22 走廊射界","region":"R5","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E09","E02","E10","E01","E02","E11","E02","E09"],"cap":55,"interval":0.4,"rhythm":"交替"},
		23:{"name":"R5 · 23 纵向追猎","region":"R5","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E04","E02","E11","E01","E02","E06","E02","E04"],"cap":72,"interval":0.37,"rhythm":"轮换"},
		24:{"name":"R5 · 24 分裂连锁","region":"R5","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E12","E02","E07","E01","E02","E11","E02","E12"],"cap":72,"interval":0.39,"rhythm":"脉冲"},
		25:{"name":"R5 · 25 能源精英","region":"R5","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E03","E02","E05","E01","E02","E08","E02","E06"],"cap":68,"interval":0.39,"rhythm":"精英"},
		26:{"name":"R6 · 26 四面清场","region":"R6","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E12","E02","E11","E01","E02","E06","E02","E12"],"cap":93,"interval":0.29,"rhythm":"轮换"},
		27:{"name":"R6 · 27 核心护卫","region":"R6","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E09","E02","E08","E01","E02","E11","E02","E06"],"cap":110,"interval":0.37,"rhythm":"协同"},
		28:{"name":"R6 · 28 交替封路","region":"R6","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E04","E02","E10","E01","E02","E09","E02","E11"],"cap":125,"interval":0.37,"rhythm":"交替"},
		29:{"name":"R6 · 29 平台高潮","region":"R6","info":"生存45秒；高速追击群为主，保留特殊协同；多方向分批进入，增援可重叠","seconds":45,"roles":["E01","E02","E07","E02","E05","E01","E02","E11","E02","E06"],"cap":145,"interval":0.27,"rhythm":"三段"},
		30:{"name":"R6 · 30 棱镜核心","region":"R6","info":"击败Boss；无倒计时自动胜利；Boss；敌群 ","seconds":0,"roles":[],"cap":20,"interval":1.6,"rhythm":"Boss","boss":"B03"},
	}
