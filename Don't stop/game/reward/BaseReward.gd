extends Node
class_name BaseReward

@export var id = Time.get_ticks_usec() + randi()%1000 #唯一ID
@export_range(0,3,1) var reward_quality = 0 #品质
@export var reward_name = "" #奖励名称
@export var reward_image :Texture #奖励图片
const EFFECT_INFO = {
	2:"获得及叠层时最大生命+3；最多前4层提供效果，旧存档计数和历史生命保留。",
	3:"15%/层概率抵消少量伤害；概率最高60%，减伤量按最多4层计算。",
	4:"直接命中每层10%概率伤害翻倍，概率最高100%；保留蓝斧特色。",
	5:"基础移动速度每层+5，效果最多6层；与天赋及动量环相加。",
	6:"同目标每3次直接命中造成5×层数附加伤害，效果最多6层；附伤不递归。",
	7:"直接击杀20%掉落回血包，回复量最多3HP；不触发派生击杀。",
	8:"1秒内直接击杀3敌，射速+20个百分点，持续层数+1秒（最多6秒），不重复叠加；保存剩余时间。",
	9:"每3秒充能，下一次直接命中伤害+50%×层数，效果最多3层；保存充能状态。",
	10:"前100次直接击杀每次最大生命+0.1；旧存档击杀计数及历史生命保留。",
	11:"直接命中20%概率额外造成25%×层数伤害，效果最多4层；派生不再触发。"
}
@export_multiline var reward_info = "":
	get: return EFFECT_INFO.get(id,reward_info)
@export var only_start = false #是否只触发start方法
@export var max_count = 99 #叠加最大数量
@export var count = 1: #叠加数量
	set(value):
		count = value
		onCountChange()

@export_group("Signal")
@export var connect_beforeAtk = false#怪物收到伤害前触发
@export var connect_afterAtk = false#怪物收到伤害后触发
@export var connect_beforePlayerHit = false#玩家收到伤害前触发
@export var connect_afterPlayerHit = false#玩家收到伤害后触发
@export var connect_kill = false#击杀怪物后触发

func _ready():
	add_to_group("reward")
	Combat.invalidate_group_cache()
	tree_exited.connect(Combat.invalidate_group_cache,CONNECT_ONE_SHOT)
	onRewardStart()
	if only_start:
		RewardServer.removeReward(self)

func onRewardStart():
	pass

func onRewardRemove():
	pass

func afterAtk(monster:BaseMonster,hit_num):#怪物收到伤害后触发
	pass

func beforeAtk(monster:BaseMonster,hit_num):#怪物收到伤害前触发
	return 0

func beforePlayerHit(hit_num):#玩家收到伤害前触发
	return 0

func afterPlayerHit(hit_num): #玩家收到伤害后触发
	return 0

func onKill(monster:BaseMonster): #击杀后触发
	pass

func onCountChange():
	pass

func _exit_tree():
	onRewardRemove()

func target_removed(_target):
	pass
