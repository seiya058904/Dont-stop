extends RefCounted
# Fixed earned-budget profiles; every item is bought through the production shop.
const PROFILES = {
	"A":{"level":8,"gun":117,"gold":6500,"points":20,"upgrades":[0,1,110,117],"talents":{"T01":2,"T02":1,"T03":1,"T07":2,"T08":2,"T11":1,"T19":1,"T24":1},"rewards":{12:1,17:1,18:1,22:1}},
	"B":{"level":16,"gun":124,"gold":15500,"points":48,"upgrades":[0,1,3,9,110,114,117,118,120,124],"talents":{"T01":3,"T02":3,"T03":2,"T04":2,"T05":2,"T06":2,"T07":3,"T08":3,"T09":1,"T10":2,"T11":2,"T15":2,"T17":2,"T19":1,"T24":2},"rewards":{2:2,4:2,5:2,12:2,14:2,17:2,18:2,21:2,22:2}},
	"C":{"level":23,"gun":124,"gold":23500,"points":90,"upgrades":[0,1,2,3,5,6,9,110,111,113,114,115,117,118,120,121,123,124],"talents":{"T01":3,"T02":3,"T03":3,"T04":3,"T05":3,"T06":3,"T07":3,"T08":3,"T09":2,"T10":3,"T11":3,"T12":3,"T13":1,"T14":1,"T15":3,"T16":1,"T17":3,"T18":3,"T19":1,"T20":2,"T21":2,"T22":3,"T23":1,"T24":3},"rewards":{2:3,4:4,5:4,6:2,8:2,9:2,11:2,12:3,13:2,14:3,15:2,16:2,17:3,18:3,19:2,20:2,21:3,22:3,23:2}}
}
static func install(id: String) -> Dictionary:
	var p = PROFILES[id]
	PlayerData.player_level = p.level
	PlayerData.player_exp = 0
	PlayerData.player_hp_max = 5+0.5*(p.level-1)
	PlayerData.player_hp = PlayerData.player_hp_max
	PlayerData.gold = p.gold; PlayerData.reward_point = p.points
	var failures = []
	var result = Demo.try_purchase("weapon",str(p.gun))
	if not result.success: failures.append(result.reason)
	for key in p.upgrades:
		result = Demo.try_purchase("attachment",str(key))
		if not result.success: failures.append(result.reason)
	for key in p.talents:
		for i in p.talents[key]:
			result = Demo.try_purchase("talent",key,"points" if PlayerData.reward_point>0 else "gold")
			if not result.success: failures.append(result.reason)
	for key in p.rewards:
		for i in p.rewards[key]:
			result = Demo.try_purchase("legacy",str(key),"points" if PlayerData.reward_point>0 else "gold")
			if not result.success: failures.append(result.reason)
	Utils.player.changeWeapon(p.gun)
	PlayerData.reserve_magazines = 100
	return {"id":id,"spec":p,"gold_spent":p.gold-PlayerData.gold,"points_spent":p.points-PlayerData.reward_point,"failures":failures,"save":Demo.snapshot()}
