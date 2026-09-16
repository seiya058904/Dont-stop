extends RefCounted
class_name M5Content

## Additional timed arrivals overlap living cohorts; HP and the roster remain frozen.
## B批: the windows overlap more and the simple-chaser share drops with stage, because the
## measured problem was never the cap (Stage 29 caps at 145 and peaked at 41 alive).
const HORDES = {
	21:{"batch":5,"window":3.8,"step":0.3,"floor":6,"windows":2},
	22:{"batch":5,"window":3.5,"step":0.28,"floor":6,"windows":2},
	23:{"batch":5,"window":3.4,"step":0.28,"floor":7,"windows":3},
	24:{"batch":6,"window":3.1,"step":0.24,"floor":9,"windows":3},
	25:{"batch":6,"window":2.9,"step":0.24,"floor":9,"windows":3},
	26:{"batch":7,"window":2.7,"step":0.22,"floor":10,"windows":4},
	27:{"batch":13,"window":2.0,"step":0.16,"floor":14,"windows":4},
	28:{"batch":15,"window":1.8,"step":0.16,"floor":16,"windows":5},
	29:{"batch":17,"window":1.6,"step":0.15,"floor":18,"windows":5},
	# Hell: the same mechanism carries the difficulty instead of a bigger cap.
	31:{"batch":6,"window":2.8,"step":0.24,"floor":8,"windows":3},
	32:{"batch":7,"window":2.6,"step":0.22,"floor":9,"windows":3},
	33:{"batch":8,"window":2.4,"step":0.22,"floor":10,"windows":4},
	34:{"batch":9,"window":2.2,"step":0.2,"floor":11,"windows":4},
	35:{"batch":11,"window":2.0,"step":0.18,"floor":13,"windows":5},
	36:{"batch":12,"window":1.9,"step":0.18,"floor":14,"windows":5},
	37:{"batch":14,"window":1.7,"step":0.16,"floor":16,"windows":5},
	38:{"batch":16,"window":1.6,"step":0.16,"floor":18,"windows":6},
	39:{"batch":18,"window":1.5,"step":0.14,"floor":20,"windows":6}
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
	"E12":{"name":"易爆载能体","hp":2.0,"speed":95.0,"role":"推进扇面放电；死亡对敌有限爆破"},
	# Hell-only roster. Two new mechanics and one new area denial, not two more stat blocks.
	"E13":{"name":"震颤射手","hp":3.0,"speed":56.0,"role":"远距离停步射击紫色震颤弹；命中施加束缚，直接伤害极低；控制免疫严格生效"},
	"E14":{"name":"激光哨兵","hp":6.0,"speed":44.0,"armor":4.0,"role":"长距离持续射线；细线预警后增亮发射，墙体裁剪，与追击怪组合"},
	"E15":{"name":"毒囊携带者","hp":5.0,"speed":84.0,"role":"推进毒囊；近身或死亡释放短时毒区，受全局毒区上限约束"}
}
const BOSSES = {
	"B01":{"name":"破城机甲","hp":5600.0,"speed":84.0,"role":"三阶段：冲锋、重扇斩、震地；中段护卫与环状冲击；末段连招加速","armor":120.0},
	"B02":{"name":"蜂巢聚合体","hp":9000.0,"speed":76.0,"role":"三阶段：追击召唤、连续封区、扇面脉冲；中段自爆蜂群；末段毒区与束缚弹"},
	"B03":{"name":"棱镜核心","hp":10600.0,"speed":115.0,"role":"三阶段：切侧突进、方向扫束、快速扇射；中段反向压迫；末段十字激光、旋转扫束、侧翼突进"},
	"B04":{"name":"深渊核心体","hp":16000.0,"speed":96.0,"role":"地狱终局：三阶段；战争迷雾内移动安全区、激光网、移动危险带与百分比终极"}
}
static func definition(id: String) -> Dictionary:
	return ENEMIES.get(id,BOSSES.get(id,{}))
## Instrumentation for tests/R3SpawnAudit.gd. Counters only - no behaviour change.
## They live here because M5Content has a class_name; Town.gd and CombatArena.gd do
## not, so a test cannot reach static state on those two scripts by name.
## "Candidates rejected" and "deferred" are decisions, not outcomes: they cannot be
## read off final positions, only counted where the decision is made.
static var audit_candidates := 0     # candidate points examined by both validators
static var audit_rejected := 0       # candidate points a validation rule refused
static var audit_deferred := 0       # wave spawn attempts deferred (no legal point)
static var audit_boss_deferred := 0  # boss spawns deferred (no legal point)
static var audit_boss_retry := 0     # retries of a deferred boss
static var audit_arena_failed := 0   # arena spawn_near() gave up entirely
static var audit_refused := 0        # spawn() refusals by the shared guard
static var audit_elites := 0         # elite arrivals promoted by the elite plan

## Bounding radius of an enemy, in world units, measured from the scene that is
## actually spawned and cached per id.
##
## Why this exists: the spawn-point clearance used to be a fixed 7 px circle, which
## is the collider's *radius*. The actors use a CapsuleShape2D (radius 7, height 20)
## that is also offset from the actor's origin by (1,-9), so a candidate could pass
## the check and still be created with part of the body inside a wall - exactly what
## the player saw as enemies stuck in walls. Measuring the real collider removes the
## drift between "this point is legal" and "this body fits", and it is measured from
## the scene rather than typed into a table, so it cannot rot when a collider is
## resized.
static var _radius_cache := {}
## Clearance used when a caller does not name an actor: the plain monster body, which
## every enemy id instantiates.
static func default_radius() -> float:
	return radius_for("E01")

static func radius_for(id: String) -> float:
	if _radius_cache.has(id): return _radius_cache[id]
	var radius := 7.0
	if not definition(id).is_empty():
		var actor = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
		var collider := actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collider != null and collider.shape != null:
			# The candidate check is a circle centred on the actor's ORIGIN, while the
			# collider may sit away from it, so both parts count.
			radius = collider.position.length() + _shape_extent(collider.shape)
		actor.free()
	_radius_cache[id] = radius
	return radius

static func _shape_extent(shape: Shape2D) -> float:
	if shape is CapsuleShape2D:
		# A capsule is every point within `radius` of a segment of length
		# height - 2*radius, so its furthest point is exactly height/2 away.
		return maxf(shape.radius, shape.height * 0.5)
	if shape is CircleShape2D:
		return shape.radius
	if shape is RectangleShape2D:
		return shape.size.length() * 0.5
	if shape is ConvexPolygonShape2D:
		var extent := 0.0
		for point in shape.points: extent = maxf(extent, point.length())
		return extent
	return 7.0

static func spawn(id: String, parent: Node, point: Vector2, summoned = false):
	if definition(id).is_empty(): return null
	# Shared guard for every spawn path. Callers are supposed to validate their
	# candidate first, but a missed check used to create the actor at whatever
	# sentinel came back (Vector2.INF), which the player sees as an enemy stuck
	# outside the map. Refusing here turns that into a logged skip instead of a
	# monster in an unreachable place.
	if not point.is_finite():
		audit_refused += 1
		push_warning("[spawn] %s refused: non-finite point %s" % [id, str(point)])
		return null
	var actor = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	if id in ["E02","E04","E05"]:
		actor.set_script(load("res://game/monster/DemoEnemy.gd")); actor.role = id
	elif id != "E01":
		actor.set_script(load("res://game/monster/TacticalEnemy.gd")); actor.role = id; actor.summoned = summoned
	var d = definition(id)
	# Hell Mode pressure is applied here, once, per actor: bounded HP/speed axes and a
	# damage axis the actor reads when it deals damage. Bosses are excluded - B04 is
	# authored at its own value and 31-39 field no boss.
	var hell := HellMode.is_hell(LevelServer.level) and not id.begins_with("B")
	# `hurt` is the raw body-contact damage Monster2's attack frame uses for E01. It gets the
	# damped axis, while telegraphed attacks read `damage_scale` at full weight.
	var contact := 1.0
	if hell:
		actor.HP *= HellMode.hp_scale(LevelServer.level)
		actor.SPEED *= HellMode.speed_scale(LevelServer.level)
		actor.damage_scale = HellMode.damage_scale(LevelServer.level)
		contact = 1.0+(HellMode.damage_scale(LevelServer.level)-1.0)*DemoConfig.CONTACT_DAMAGE_WEIGHT
		actor.set_meta("hell",LevelServer.level)
	actor.setData({"speed":d.speed,"hp":d.hp,"hurt":contact})
	actor.set_meta("content_id",id)
	actor.set_meta("summoned",summoned)
	actor.set_meta("spawn_epoch",LevelServer.epoch)
	actor.set_meta("born_ms",Time.get_ticks_msec())
	actor.position = parent.to_local(point)
	# Per-stage chase pressure, table driven instead of the old hardcoded [27,28,29].
	var pressure = encounter_pressure(LevelServer.level)
	if float(pressure.get("chase_speed",1.0)) != 1.0 and id in ["E01","E02"]:
		actor.SPEED *= float(pressure.chase_speed)
	if is_instance_valid(LevelServer.town): actor.setDeathCallBack(LevelServer.town.onMonsterDeath)
	parent.add_child(actor)
	return actor

## Elite promotion. The mechanism is the point: every elite gets exactly one named extra
## behaviour (TacticalEnemy.ELITE_MODIFIERS), a coloured aura so it can be identified before
## it is engaged, and a single bounded 1.5x HP - never "HP x 1.5 and nothing else".
static func promote_elite(actor, modifier := ""):
	if actor == null or not is_instance_valid(actor): return
	if actor.get("is_elite") == true: return
	actor.is_elite = true
	actor.HP *= 1.5
	actor.set_meta("elite_modifier",modifier)
	var aura = load("res://game/effects/EliteAura.gd").new()
	aura.modifier = modifier
	actor.add_child(aura)
	audit_elites += 1

## Modifier for an id, with a fallback so a new enemy can never be promoted without a
## mechanism attached.
static func elite_modifier_for(id: String) -> String:
	return load("res://game/monster/TacticalEnemy.gd").ELITE_MODIFIERS.get(id,"ram_shockwave")

## Authored pressure dials for one stage. Everything the round needs to feel harder than
## the last one lives here, so no difficulty value is buried in the spawn loop.
## Read through DemoConfig.ENCOUNTERS on purpose: that is the single live table the whole
## game validates against, so a static copy here could silently drift out of step.
static func encounter_pressure(stage: int) -> Dictionary:
	return DemoConfig.ENCOUNTERS.get(stage,{}).get("pressure",{})

## The elite plan for a stage. `start` is seconds into the round, `interval` the seconds
## between arrivals and `cap` the simultaneous elite ceiling. Replaces the old
## single-shot "elite_spawned" boolean that only the four 精英-rhythm stages used.
static func elite_plan(stage: int) -> Dictionary:
	return DemoConfig.ENCOUNTERS.get(stage,{}).get("elite",{})

const REGIONS = {
	"R1":{"name":"营地外街区","info":"原街口改良；路口墙角、四向渐进入场","sides":[0,1,2,3]},
	"R2":{"name":"货运场","info":"宽车道与四组货柜；装卸标线、危险条纹、工业指示灯；东西方向压迫","sides":[0,2]},
	"R3":{"name":"冰原冷却站","info":"冰裂地表、霜墙与冷却管线；交错短墙、两侧开阔；霜爆危险区","sides":[1,3,0]},
	"R4":{"name":"熔岩处理区","info":"暗岩热裂、墙内熔流与热泉喷口；四个互通小场与宽绕行口","sides":[0,1,2,3]},
	"R5":{"name":"过生长走廊","info":"藤蔓、植被块、浅水沟与孢子毒池；三条互通宽通路","sides":[1,3]},
	"R6":{"name":"山地核心平台","info":"岩柱、能量裂隙与核心环；多出口开阔中心；能量危险带","sides":[0,2,1,3]},
	"R7":{"name":"雾蚀隔离区","info":"废弃检疫区：生物荧光孢子、腐蚀地面与破封隔间；宽环廊加中央通道","sides":[0,1,2,3]},
	"R8":{"name":"深渊核心","info":"碎裂核心、能量柱与激光网格；外环开放、内环裂隙","sides":[0,1,2,3]}
}
const WALLS = {
	"R2":[Rect2(-300,-212,120,80),Rect2(172,-212,120,80),Rect2(-300,120,120,80),Rect2(172,120,120,80)],
	"R3":[Rect2(-292,-148,218,26),Rect2(63,-17,240,26),Rect2(-258,126,195,26)],
	"R4":[Rect2(-280,-137,172,26),Rect2(109,-137,172,26),Rect2(-280,109,172,26),Rect2(109,109,172,26),Rect2(-280,-46,26,80),Rect2(253,-46,26,80)],
	"R5":[Rect2(-155,-258,28,178),Rect2(-155,69,28,178),Rect2(125,-258,28,178),Rect2(125,69,28,178)],
	"R6":[Rect2(-200,-155,62,62),Rect2(138,-155,62,62),Rect2(-200,92,62,62),Rect2(138,92,62,62)],
	# Broken quarantine cells: a wide ring corridor plus a central channel, so a fogged
	# player always has a long sight line to move along and never a dead end.
	"R7":[Rect2(-330,-190,150,66),Rect2(-330,124,150,66),Rect2(180,-190,150,66),Rect2(180,124,150,66),Rect2(-40,-258,80,52),Rect2(-40,206,80,52)],
	# Fractured core: four core fragments with gaps lasers sweep through, and four outer
	# pylons that break the outer ring into readable quadrants.
	"R8":[Rect2(-70,-70,140,26),Rect2(-70,44,140,26),Rect2(-70,-44,26,88),Rect2(44,-44,26,88),Rect2(-330,-230,70,70),Rect2(260,-230,70,70),Rect2(-330,160,70,70),Rect2(260,160,70,70)]
}

## ---- Encounter table ---------------------------------------------------------------
##
## Every stage carries the fields the spawn loop reads, plus three explicit pressure dials:
##   pressure.horde_simple  share of a horde window that is the simple chaser
##   pressure.ring_min      closest a wave member may be placed to the player
##   pressure.chase_speed   E01/E02 speed multiplier for this stage
##   elite                  {start, interval, cap}
##   flank                  true = Hell-style multi-direction arrivals
##
## The roster is authored as the exact cycle the spawn loop walks, so the intended mix is
## readable instead of emergent.
static func encounters() -> Dictionary:
	return {
		1:{"name":"R1 · 01 街口接敌","region":"R1","info":"生存45秒；渐进；敌群 E01 E01 E02","seconds":45,"roles":["E01", "E01", "E02"],"cap":35,"interval":0.70,"rhythm":"渐进","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		2:{"name":"R1 · 02 蜂群分流","region":"R1","info":"生存45秒；轮换；敌群 E02 E02 E01","seconds":45,"roles":["E02", "E02", "E01"],"cap":38,"interval":0.57,"rhythm":"轮换","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		3:{"name":"R1 · 03 远程交错","region":"R1","info":"生存45秒；渐进；敌群 E01 E02 E01 E05","seconds":45,"roles":["E01", "E02", "E01", "E05"],"cap":40,"interval":0.61,"rhythm":"渐进","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		4:{"name":"R1 · 04 蜂群冲锋","region":"R1","info":"生存45秒；脉冲；敌群 E02 E02 E02 E04","seconds":45,"roles":["E02", "E02", "E02", "E04"],"cap":55,"interval":0.48,"rhythm":"脉冲","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		5:{"name":"R1 · 05 街区精英","region":"R1","info":"生存45秒；精英；敌群 E01 E02 E05 E04","seconds":45,"roles":["E01", "E02", "E05", "E04"],"cap":40,"interval":0.57,"rhythm":"精英","elite":{"start":26.0,"interval":18.0,"cap":1},"pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		6:{"name":"R2 · 06 装甲车道","region":"R2","info":"生存45秒；渐进；敌群 E01 E03","seconds":45,"roles":["E01", "E03"],"cap":47,"interval":0.50,"rhythm":"渐进","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		7:{"name":"R2 · 07 爆点清场","region":"R2","info":"生存45秒；轮换；敌群 E02 E02 E06","seconds":45,"roles":["E02", "E02", "E06"],"cap":49,"interval":0.48,"rhythm":"轮换","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		8:{"name":"R2 · 08 甲后射界","region":"R2","info":"生存45秒；协同；敌群 E03 E05 E01","seconds":45,"roles":["E03", "E05", "E01"],"cap":45,"interval":0.60,"rhythm":"协同","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		9:{"name":"R2 · 09 货场突围","region":"R2","info":"生存45秒；脉冲；敌群 E02 E04 E03 E02","seconds":45,"roles":["E02", "E04", "E03", "E02"],"cap":59,"interval":0.38,"rhythm":"脉冲","pressure":{"horde_simple":0.70,"ring_min":145.0,"chase_speed":1.0}},
		10:{"name":"R2 · 10 破城机甲","region":"R2","info":"击败Boss；无倒计时自动胜利；Boss；敌群 ","seconds":0,"roles":[],"cap":15,"interval":1.5,"rhythm":"Boss","boss":"B01"},
		11:{"name":"R3 · 11 侧翼接近","region":"R3","info":"生存45秒；轮换；侧绕正式登场；敌群 E01 E11","seconds":45,"roles":["E01", "E11"],"cap":45,"interval":0.45,"rhythm":"轮换","pressure":{"horde_simple":0.66,"ring_min":135.0,"chase_speed":1.02}},
		12:{"name":"R3 · 12 盾后蜂群","region":"R3","info":"生存45秒；协同；盾卫正式登场；敌群 E09 E02 E02","seconds":45,"roles":["E09", "E02", "E02"],"cap":49,"interval":0.42,"rhythm":"协同","pressure":{"horde_simple":0.66,"ring_min":135.0,"chase_speed":1.02}},
		13:{"name":"R3 · 13 标记交叉火力","region":"R3","info":"生存45秒；交替；混合追击 / 侧翼 / 炮击 / 支援；敌群 E01 E11 E10 E02","seconds":45,"roles":["E01","E11","E10","E02"],"cap":38,"interval":0.45,"rhythm":"交替","pressure":{"horde_simple":0.64,"ring_min":135.0,"chase_speed":1.02}},
		14:{"name":"R3 · 14 短墙折射","region":"R3","info":"生存45秒；轮换；冲锋与侧翼借短墙折角；敌群 E04 E11 E02","seconds":45,"roles":["E04", "E11", "E02"],"cap":56,"interval":0.39,"rhythm":"轮换","pressure":{"horde_simple":0.66,"ring_min":135.0,"chase_speed":1.02}},
		15:{"name":"R3 · 15 冷却精英","region":"R3","info":"生存45秒；精英；混合追击 / 侧翼 / 支援 / 远程 / 自爆；敌群 E09 E11 E02 E05 E06","seconds":45,"roles":["E09","E11","E02","E05","E06"],"cap":56,"interval":0.42,"rhythm":"精英","elite":{"start":24.0,"interval":17.0,"cap":1},"pressure":{"horde_simple":0.64,"ring_min":135.0,"chase_speed":1.02}},
		16:{"name":"R4 · 16 母体增殖","region":"R4","info":"生存45秒；召唤正式组合；中段同方向有限突袭；敌群 E01 E02 E07 E02 E07 E01 E02 E07 E02 E07","seconds":45,"roles":["E01","E02","E07","E02","E07","E01","E02","E07","E02","E07"],"cap":52,"interval":0.43,"rhythm":"渐进","pressure":{"horde_simple":0.62,"ring_min":130.0,"chase_speed":1.04}},
		17:{"name":"R4 · 17 后排修复","region":"R4","info":"生存45秒；治疗与盾卫协同，必须换位切后排；敌群 E01 E02 E08 E02 E09 E01 E02 E06 E02 E08","seconds":45,"roles":["E01","E02","E08","E02","E09","E01","E02","E06","E02","E08"],"cap":47,"interval":0.43,"rhythm":"协同","pressure":{"horde_simple":0.62,"ring_min":130.0,"chase_speed":1.04}},
		18:{"name":"R4 · 18 载能连爆","region":"R4","info":"生存45秒；载能体与侧绕连爆，逼迫拉扯；敌群 E01 E02 E12 E02 E11 E01 E02 E12 E02 E11","seconds":45,"roles":["E01","E02","E12","E02","E11","E01","E02","E12","E02","E11"],"cap":70,"interval":0.34,"rhythm":"脉冲","pressure":{"horde_simple":0.62,"ring_min":130.0,"chase_speed":1.04}},
		19:{"name":"R4 · 19 再生压迫","region":"R4","info":"生存45秒；再生与自爆叠加，必须持续清除；敌群 E01 E02 E07 E02 E08 E01 E02 E06 E02 E07","seconds":45,"roles":["E01","E02","E07","E02","E08","E01","E02","E06","E02","E07"],"cap":52,"interval":0.40,"rhythm":"协同","pressure":{"horde_simple":0.60,"ring_min":130.0,"chase_speed":1.04}},
		20:{"name":"R4 · 20 蜂巢聚合体","region":"R4","info":"击败Boss；第一次明显难度跨阶；Boss；敌群 ","seconds":0,"roles":[],"cap":20,"interval":1.5,"rhythm":"Boss","boss":"B02"},
		21:{"name":"R5 · 21 双重防线","region":"R5","info":"生存45秒；毒区机制首次登场；多方向分批进入，增援可重叠；敌群 E01 E02 E03 E02 E09 E01 E02 E06 E02 E03","seconds":45,"roles":["E01","E02","E03","E02","E09","E01","E02","E06","E02","E03"],"cap":65,"interval":0.38,"rhythm":"协同","pressure":{"horde_simple":0.60,"ring_min":122.0,"chase_speed":1.06}},
		22:{"name":"R5 · 22 走廊射界","region":"R5","info":"生存45秒；炮击与盾卫封锁走廊；敌群 E01 E02 E09 E02 E10 E01 E02 E11 E02 E09","seconds":45,"roles":["E01","E02","E09","E02","E10","E01","E02","E11","E02","E09"],"cap":55,"interval":0.36,"rhythm":"交替","pressure":{"horde_simple":0.58,"ring_min":122.0,"chase_speed":1.06}},
		23:{"name":"R5 · 23 纵向追猎","region":"R5","info":"生存45秒；冲锋与侧绕沿纵向夹击；敌群 E01 E02 E04 E02 E11 E01 E02 E06 E02 E04","seconds":45,"roles":["E01","E02","E04","E02","E11","E01","E02","E06","E02","E04"],"cap":72,"interval":0.33,"rhythm":"轮换","pressure":{"horde_simple":0.58,"ring_min":122.0,"chase_speed":1.06}},
		24:{"name":"R5 · 24 分裂连锁","region":"R5","info":"生存45秒；母体分裂与载能连爆叠压；敌群 E01 E02 E12 E02 E07 E01 E02 E11 E02 E12","seconds":45,"roles":["E01","E02","E12","E02","E07","E01","E02","E11","E02","E12"],"cap":72,"interval":0.35,"rhythm":"脉冲","pressure":{"horde_simple":0.58,"ring_min":122.0,"chase_speed":1.06}},
		25:{"name":"R5 · 25 能源精英","region":"R5","info":"生存45秒；精英；混合远程 / 治疗 / 自爆 / 重甲；敌群 E01 E02 E03 E02 E05 E01 E02 E08 E02 E06","seconds":45,"roles":["E01","E02","E03","E02","E05","E01","E02","E08","E02","E06"],"cap":68,"interval":0.35,"rhythm":"精英","elite":{"start":22.0,"interval":15.0,"cap":2},"pressure":{"horde_simple":0.56,"ring_min":122.0,"chase_speed":1.06}},
		26:{"name":"R6 · 26 四面清场","region":"R6","info":"生存45秒；能量危险带登场；多方向增援重叠；敌群 E01 E02 E12 E02 E11 E01 E02 E06 E02 E12","seconds":45,"roles":["E01","E02","E12","E02","E11","E01","E02","E06","E02","E12"],"cap":93,"interval":0.26,"rhythm":"轮换","elite":{"start":20.0,"interval":14.0,"cap":2},"pressure":{"horde_simple":0.54,"ring_min":118.0,"chase_speed":1.08}},
		27:{"name":"R6 · 27 核心护卫","region":"R6","info":"生存45秒；高密度追击配精英护卫；敌群 E01 E02 E09 E02 E08 E01 E02 E11 E02 E06","seconds":45,"roles":["E01","E02","E09","E02","E08","E01","E02","E11","E02","E06"],"cap":110,"interval":0.30,"rhythm":"协同","elite":{"start":18.0,"interval":13.0,"cap":2},"pressure":{"horde_simple":0.52,"ring_min":116.0,"chase_speed":1.10}},
		28:{"name":"R6 · 28 交替封路","region":"R6","info":"生存45秒；炮击与盾卫交替封路，能量危险带叠加；敌群 E01 E02 E04 E02 E10 E01 E02 E09 E02 E11","seconds":45,"roles":["E01","E02","E04","E02","E10","E01","E02","E09","E02","E11"],"cap":125,"interval":0.30,"rhythm":"交替","elite":{"start":16.0,"interval":12.0,"cap":3},"pressure":{"horde_simple":0.50,"ring_min":114.0,"chase_speed":1.12}},
		29:{"name":"R6 · 29 平台高潮","region":"R6","info":"生存45秒；三段节奏叠加增援重叠与精英；敌群 E01 E02 E07 E02 E05 E01 E02 E11 E02 E06","seconds":45,"roles":["E01","E02","E07","E02","E05","E01","E02","E11","E02","E06"],"cap":145,"interval":0.23,"rhythm":"三段","elite":{"start":14.0,"interval":11.0,"cap":3},"pressure":{"horde_simple":0.48,"ring_min":112.0,"chase_speed":1.14}},
		30:{"name":"R6 · 30 棱镜核心","region":"R6","info":"Normal Campaign Final Boss；击败后完成普通战役并解锁第31关；敌群 ","seconds":0,"roles":[],"cap":20,"interval":1.5,"rhythm":"Boss","boss":"B03"},
		# ---- HELL MODE (31-40) ---------------------------------------------------------
		31:{"name":"R7 · 31 雾蚀初现","region":"R7","info":"HELL；生存45秒；战争迷雾开启；低强度毒区；震颤射手与激光哨兵登场；敌群 E01 E02 E14 E02 E13 E01 E02 E15 E02 E13","seconds":45,"roles":["E01","E02","E14","E02","E13","E01","E02","E15","E02","E13"],"cap":72,"interval":0.30,"rhythm":"渐进","hell":true,"flank":true,"elite":{"start":22.0,"interval":15.0,"cap":1},"pressure":{"horde_simple":0.52,"ring_min":120.0,"chase_speed":1.10}},
		32:{"name":"R7 · 32 侧翼包夹","region":"R7","info":"HELL；生存45秒；迷雾下多方向侧翼同时进入；敌群 E01 E02 E13 E02 E11 E01 E02 E14 E02 E15","seconds":45,"roles":["E01","E02","E13","E02","E11","E01","E02","E14","E02","E15"],"cap":80,"interval":0.29,"rhythm":"协同","hell":true,"flank":true,"elite":{"start":20.0,"interval":14.0,"cap":2},"pressure":{"horde_simple":0.50,"ring_min":118.0,"chase_speed":1.11}},
		33:{"name":"R7 · 33 孢子污染","region":"R7","info":"HELL；生存45秒；毒囊与毒区叠加，必须持续移动；敌群 E01 E02 E15 E02 E15 E01 E02 E14 E02 E13","seconds":45,"roles":["E01","E02","E15","E02","E15","E01","E02","E14","E02","E13"],"cap":88,"interval":0.28,"rhythm":"交替","hell":true,"flank":true,"elite":{"start":18.0,"interval":13.0,"cap":2},"pressure":{"horde_simple":0.50,"ring_min":116.0,"chase_speed":1.12}},
		34:{"name":"R7 · 34 精英射线","region":"R7","info":"HELL；生存45秒；精英激光哨兵封锁可见范围；敌群 E01 E02 E14 E02 E14 E01 E02 E13 E02 E15","seconds":45,"roles":["E01","E02","E14","E02","E14","E01","E02","E13","E02","E15"],"cap":96,"interval":0.27,"rhythm":"精英","hell":true,"flank":true,"elite":{"start":16.0,"interval":12.0,"cap":2},"pressure":{"horde_simple":0.48,"ring_min":115.0,"chase_speed":1.13}},
		35:{"name":"R7 · 35 隔离区高压","region":"R7","info":"HELL；生存45秒；R7综合高压：迷雾、毒区、喷发与三方增援；敌群 E01 E02 E14 E02 E13 E01 E02 E15 E02 E11","seconds":45,"roles":["E01","E02","E14","E02","E13","E01","E02","E15","E02","E11"],"cap":105,"interval":0.26,"rhythm":"三段","hell":true,"flank":true,"elite":{"start":14.0,"interval":11.0,"cap":3},"pressure":{"horde_simple":0.46,"ring_min":113.0,"chase_speed":1.14}},
		36:{"name":"R8 · 36 深渊入口","region":"R8","info":"HELL；生存45秒；进入深渊核心，视野进一步收紧；敌群 E01 E02 E14 E02 E12 E01 E02 E13 E02 E15","seconds":45,"roles":["E01","E02","E14","E02","E12","E01","E02","E13","E02","E15"],"cap":114,"interval":0.25,"rhythm":"协同","hell":true,"flank":true,"elite":{"start":14.0,"interval":11.0,"cap":3},"pressure":{"horde_simple":0.46,"ring_min":112.0,"chase_speed":1.15}},
		37:{"name":"R8 · 37 激光网格","region":"R8","info":"HELL；生存45秒；激光网格与哨兵交叉，安全走位变短；敌群 E01 E02 E14 E02 E14 E01 E02 E10 E02 E14","seconds":45,"roles":["E01","E02","E14","E02","E14","E01","E02","E10","E02","E14"],"cap":124,"interval":0.24,"rhythm":"交替","hell":true,"flank":true,"elite":{"start":13.0,"interval":10.0,"cap":3},"pressure":{"horde_simple":0.44,"ring_min":111.0,"chase_speed":1.16}},
		38:{"name":"R8 · 38 裂隙重叠","region":"R8","info":"HELL；生存45秒；危险带与毒区重叠，安全区不断移动；敌群 E01 E02 E15 E02 E13 E01 E02 E14 E02 E12","seconds":45,"roles":["E01","E02","E15","E02","E13","E01","E02","E14","E02","E12"],"cap":134,"interval":0.24,"rhythm":"脉冲","hell":true,"flank":true,"elite":{"start":12.0,"interval":10.0,"cap":4},"pressure":{"horde_simple":0.44,"ring_min":110.0,"chase_speed":1.17}},
		39:{"name":"R8 · 39 核心暴走","region":"R8","info":"HELL；生存45秒；高密度精英配合危险带，必须靠视野判断；敌群 E01 E02 E14 E02 E13 E01 E02 E15 E02 E10","seconds":45,"roles":["E01","E02","E14","E02","E13","E01","E02","E15","E02","E10"],"cap":146,"interval":0.23,"rhythm":"三段","hell":true,"flank":true,"elite":{"start":10.0,"interval":9.0,"cap":4},"pressure":{"horde_simple":0.42,"ring_min":108.0,"chase_speed":1.18}},
		40:{"name":"R8 · 40 深渊核心体","region":"R8","info":"HELL FINAL BOSS；三阶段；迷雾中移动安全区；击败后 HELL COMPLETE；敌群 ","seconds":0,"roles":[],"cap":24,"interval":1.4,"rhythm":"Boss","boss":"B04","hell":true,"flank":true}
	}
