extends "res://tests/M8Runtime.gd"

const VARIANTS = preload("res://game/config/B18Variants.gd")
const BARRAGE = preload("res://game/monster/ContinuousBarrage.gd")

func _ready():
	await boot(); configure(0)
	var total = [0.10,0.15,0.22,0.32,0.45,0.58,0.70,0.82,0.90]
	var tier_two = [0.00,0.00,0.03,0.05,0.08,0.12,0.18,0.25,0.30]
	for i in total.size():
		check(is_equal_approx(VARIANTS.enchantment_total_ratio(31+i),total[i]),"total enchantment ratio stage %d"%(31+i))
		check(is_equal_approx(VARIANTS.enchantment_tier_two_ratio(31+i),tier_two[i]),"tier-2 absolute ratio stage %d"%(31+i))
	check(is_equal_approx(VARIANTS.enchantment_total_ratio(40),0.0),"stage 40 reserves ordinary variants for the final boss")
	check(float(M5Content.BOSSES["B04"].final_hp)==20000.0,"B04 explicit final HP is 20000")
	check(is_equal_approx(M5Content.giant_final_hp(33),6000.0),"stage 33 giant uses 30% of B04 reference")
	check(is_equal_approx(M5Content.giant_final_hp(39),11000.0),"stage 39 giant uses 55% of B04 reference")
	check(BARRAGE.BOSS_SPECS.has("B04") and BARRAGE.ELITE_SPECS.has("E14"),"continuous barrage covers B04 and the bounded elite set")
	check(BARRAGE.BOSS_SPECS["B04"].count < preload("res://game/monster/EnemyShot.gd").capacity_limit,"continuous barrage stays below the projectile capacity per tick")
	print("B19 CONTRACTS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
