extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(0)
	var rows = []
	for id in RewardServer.reward_list:
		var scene = RewardServer.reward_list[id]
		var reward = scene.instantiate()
		rows.append({"kind":"reward","id":id,"name":tr(reward.reward_name),"info":tr(reward.reward_info),"purchase_cap":reward.max_count,"source":scene.resource_path,"status":"PARTIAL: direct-event matrix plus selected lifecycle/resource contracts; see event logs"})
		reward.free()
	for id in AttachmentCatalog.DEFINITIONS:
		rows.append({"kind":"upgrade","id":str(id),"definition":AttachmentCatalog.DEFINITIONS[id],"purchase_cap":1,"source":"res://game/config/AttachmentCatalog.gd","consumer":"EffectiveStats.calculate / BaseGun.shot_context / Combat","status":"passive matrix and 24-gun three-source firing; event-specific contracts separate"})
	for id in DemoConfig.TALENTS:
		rows.append({"kind":"talent","id":id,"definition":DemoConfig.TALENTS[id],"purchase_cap":DemoConfig.TALENTS[id].max,"source":"res://game/config/DemoConfig.gd","consumer":"EffectiveStats / Demo / Combat / Hero","status":"passive matrix and selected event contracts; not exhaustive combinations"})
	check(rows.size()==72,"72 actual registered sources")
	var gun=Utils.player.gun
	Demo.talents={"T01":1}
	Demo.owned_global_upgrades=["114"]
	Demo.refresh()
	# Independent reference: the base scene's damage/level/quality, +15% upgrade,
	# +15% T01, then charged battery's +50% at the hit layer, rounded to cents.
	var battery=RewardServer.reward_list["9"].instantiate()
	RewardServer.addReward(battery)
	battery.is_time_out=true
	var raw=(gun.base_stats.damage+PlayerData.player_damage)*WeaponCatalog.power(0)
	var expected=snappedf(raw*1.30*1.5,0.01)
	var target=enemy(origin+Vector2(80,0),1000)
	LevelServer.state="COMBAT"
	var before=target.HP
	var context=gun.shot_context(); context.crit=0
	Combat.hit(target,context)
	var actual=before-target.HP
	check(is_equal_approx(actual,expected),"independent three-source actual HP expected="+str(expected)+" actual="+str(actual))
	var frozen=context.damage
	Demo.talents={"T01":3}; Demo.refresh()
	check(context.damage==frozen,"issued context does not read later growth")
	var ordered=gun.effective.duplicate()
	Demo.owned_global_upgrades=["114","110"]; Demo.refresh()
	ordered=gun.effective.duplicate()
	Demo.owned_global_upgrades.reverse(); Demo.refresh()
	check(gun.effective==ordered,"purchase order leaves same effective stats")
	LevelServer.state="CAMP"
	battery.count=3
	var gold=PlayerData.gold
	var purchase=Demo.try_purchase("legacy","9","gold")
	check(not purchase.success and PlayerData.gold==gold and battery.count==3,"capped battery transaction does not charge or add layer")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/visual-upgrade-20260919"))
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b17-sources.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"independent_hp":{"expected":expected,"actual":actual},"rows":rows},"\t")); file.close()
	await clean()
	print("B17 SOURCES checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
