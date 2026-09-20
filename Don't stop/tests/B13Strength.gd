extends Node
## B13 strength contract: verifies the FROZEN growth benchmarks
## (docs/iteration/evidence/b13/growth-*.json, written once by tests/B13GrowthBench.tscn
## on the real game runtime) against the B13 design rules. It reads NO catalog values:
##   * every build beats the baseline by >10% sustained DPS in single and boss
##   * quality is real strength as a THREE-SCENARIO growth score:
##       GrowthScore = geomean(single_ratio, boss_ratio, crowd_speed_ratio)
##     with single_ratio/boss_ratio = build DPS / baseline DPS and crowd_speed_ratio =
##     baseline crowd clear seconds / build crowd clear seconds. The score is
##     deliberately AGGREGATE: legendary talents (pierce/arc/kill-blast/shield/crit
##     echo) spend much of their value on crowd and utility, not on single-target dummy
##     DPS - talents_full's single/boss DPS is measurably NOT above talents_rare's, so
##     no per-scenario strict-monotonic ladder is claimed for the legendary step. What
##     bounds that trade-off is the anti-masking guard below, not an invented claim.
##   * the B13 core rule: the talent build outgains the upgrade build at common, rare
##     and full investment (GrowthScore), and Talent Full / Upgrade Full >= 1.15
##   * anti-masking guards for the legendary talent step (talents_full vs talents_rare):
##     single and boss DPS may not fall below 90% of the rare build, the crowd clear
##     must clearly improve (>10% faster), and the legendary mechanisms still cut the
##     crowd clear by >30% in the frozen data
##   * no runaway: every crowd clear stays finite and bounded, and the strongest
##     account stays inside the budget envelope (boss DPS <= 12x baseline)
##   * the benchmark's MEASUREMENT INPUTS must match the LF-normalised sha256 manifest
##     recorded next to the evidence: the harness chain, the catalogs that decide the
##     build composition, the stat/combat/projectile path, the benchmark weapon (id 0)
##     and the damage dummy's accounting. Missing files, a manifest that no longer
##     covers the required set, or ANY hash mismatch FAILS - after editing one of these
##     files the old JSON cannot announce a pass until the bench is re-run and the
##     manifest regenerated (tools/b13_manifest.py).
##
## Deliberately NOT in the manifest: LevelServer (the bench only flips its state flag),
## Hero (the player is frozen and takes no hits during measurement), the save/store and
## UI layers (never on the measurement path). Anything on the path that can move these
## numbers or the build composition is listed.

var checks := 0
var failures := 0
var data := {}

## The minimal-but-complete set of source files that can change what the 8 growth
## benchmarks measure: every entry is on the boot/fixture/firing/measurement path or
## decides the build composition. tools/b13_manifest.py parses this list as the single
## source of truth, so the generator and this verifier cannot drift apart.
const REQUIRED_MEASUREMENT_INPUTS := [
	# harness chain: boot, fixture, firing loop, damage accounting
	"tests/B13GrowthBench.gd",
	"tests/B13GrowthBench.tscn",
	"tests/M9Power.gd",
	"tests/M8Runtime.gd",
	"tests/M3Weapons.gd",
	# build composition and stat calculation
	"game/config/DemoConfig.gd",
	"game/config/AttachmentCatalog.gd",
	"game/config/EffectiveStats.gd",
	"game/config/WeaponCatalog.gd",
	# runtime combat path
	"autoload/Demo.gd",
	"autoload/Combat.gd",
	"autoload/PlayerData.gd",
	# PlayerData preloads this as PROGRESSION; every scenario resets player_level, whose
	# setter calls PROGRESSION.damage(level) into the level-damage term of
	# EffectiveStats.calculate - so DAMAGE_PER_LEVEL moves the measured DPS.
	"game/config/LevelProgression.gd",
	"autoload/Utils.gd",
	"autoload/server/RewardServer.gd",
	# the benchmark weapon (id 0) and its projectile/hit path
	"game/guns/BaseGun.gd",
	"game/guns/GunSprite.gd",
	"game/guns/GunSprite.tscn",
	"game/bullets/Bullet.gd",
	"game/bullets/SmpBullet.gd",
	"game/bullets/SmpBullet.tscn",
	# the damage dummy's HP accounting
	"game/monster/BaseMonster.gd",
	"game/monster/Monster 2/Monster2.gd",
	"game/monster/Monster 2/Monster2.tscn",
]

func check(cond: bool, label: String):
	checks += 1
	if not cond: failures += 1
	print(("PASS " if cond else "FAIL ")+label)

func load_rows(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return {}
	var result := {}
	for row in parser.data: result[str(row.scenario)] = row
	return result

func load_manifest() -> Array:
	if not FileAccess.file_exists("res://docs/iteration/evidence/b13/manifest.json"): return []
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://docs/iteration/evidence/b13/manifest.json")) != OK: return []
	return parser.data

func sha256_lf(path: String) -> String:
	if not FileAccess.file_exists(path): return "MISSING"
	var bytes = FileAccess.get_file_as_string(path).to_utf8_buffer()
	var flat := PackedByteArray()
	for b in bytes:
		if b == 13: continue
		flat.append(b)
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(flat)
	return hasher.finish().hex_encode()

const BUILDS := ["baseline","upgrades_common","upgrades_rare","upgrades_full","talents_common","talents_rare","talents_full","both_full"]

func dps_of(build: String, scenario: String) -> float:
	return float(data.get(build,{}).get(scenario,{}).get("dps",0.0))

func clear_of(build: String) -> float:
	return maxf(0.01,float(data.get(build,{}).get("crowd",{}).get("clear_seconds",999.0)))

## The three-scenario growth score against the baseline build (see header).
func growth_score(build: String) -> float:
	var single := dps_of(build,"single")/dps_of("baseline","single")
	var boss := dps_of(build,"boss")/dps_of("baseline","boss")
	var crowd := clear_of("baseline")/clear_of(build)
	return pow(single*boss*crowd,1.0/3.0)

func _ready():
	if "--b17" in OS.get_cmdline_user_args():
		var current=load("res://tests/B17Evidence.gd").new()
		current.scope="growth"; add_child(current); return
	if "--b14" in OS.get_cmdline_user_args():
		var current=load("res://tests/B14Evidence.gd").new()
		current.scope="growth";add_child(current)
		return
	for build in BUILDS:
		data[build] = load_rows("res://docs/iteration/evidence/b13/growth-%s.json" % build)
		check(not data[build].is_empty(),"evidence present for "+build)
	if failures:
		print("B13_STRENGTH_CHECKS ",checks," FAILURES ",failures)
		get_tree().quit(1); return
	# --- growth above baseline ------------------------------------------------------------
	for build in ["upgrades_common","upgrades_rare","upgrades_full","talents_common","talents_rare","talents_full","both_full"]:
		for scenario in ["single","boss"]:
			check(dps_of(build,scenario) > dps_of("baseline",scenario)*1.1,"%s beats baseline by >10%% in %s"%[build,scenario])
	# --- the three-scenario growth score ---------------------------------------------------
	var scores := {}
	for build in BUILDS:
		scores[build] = growth_score(build)
		print("B13_GROWTH_SCORE %s %.3f" % [build,scores[build]])
	# Quality is real strength inside each system: the score rises through every quality step.
	check(scores["upgrades_common"] < scores["upgrades_rare"],"upgrade GrowthScore rises 普通 → 稀有")
	check(scores["upgrades_rare"] < scores["upgrades_full"],"upgrade GrowthScore rises 稀有 → 全档")
	check(scores["talents_common"] < scores["talents_rare"],"talent GrowthScore rises 普通 → 稀有")
	check(scores["talents_rare"] < scores["talents_full"],"talent GrowthScore rises 稀有 → 全档")
	# --- the B13 core rule: talents outgain upgrades at every investment level -------------
	# Compared ONLY as the three-scenario aggregate: per-scenario the two systems trade
	# blows (legendary talents buy mechanisms, not dummy DPS), and this contract claims
	# exactly what the data measures.
	check(scores["talents_common"] > scores["upgrades_common"],"talent commons outgain upgrade commons across the three scenarios (%.2f vs %.2f)"%[scores["talents_common"],scores["upgrades_common"]])
	check(scores["talents_rare"] > scores["upgrades_rare"],"talent rares outgain upgrade rares across the three scenarios (%.2f vs %.2f)"%[scores["talents_rare"],scores["upgrades_rare"]])
	check(scores["talents_full"] > scores["upgrades_full"],"the full talent build outgains the full upgrade build across the three scenarios (%.2f vs %.2f)"%[scores["talents_full"],scores["upgrades_full"]])
	var full_ratio: float = scores["talents_full"]/scores["upgrades_full"]
	check(full_ratio > 1.15,"Talent Full / Upgrade Full GrowthScore >= 1.15 (measured %.2f)"%full_ratio)
	# --- the full account compounds beyond either system alone ------------------------------
	check(dps_of("both_full","single") > dps_of("upgrades_full","single")*1.4,"the full account compounds beyond either system alone (single)")
	check(dps_of("both_full","boss") > dps_of("upgrades_full","boss")*1.4,"the full account compounds beyond either system alone (boss)")
	# --- anti-masking guards: the legendary talent step cannot be a disguised regression ----
	check(dps_of("talents_full","single") >= dps_of("talents_rare","single")*0.9,"legendary talents keep >=90%% of the rare build's single DPS (%.2fx)"%[dps_of("talents_full","single")/dps_of("talents_rare","single")])
	check(dps_of("talents_full","boss") >= dps_of("talents_rare","boss")*0.9,"legendary talents keep >=90%% of the rare build's boss DPS (%.2fx)"%[dps_of("talents_full","boss")/dps_of("talents_rare","boss")])
	check(clear_of("talents_full") < clear_of("talents_rare")*0.9,"legendary talents clearly improve the crowd clear (>10%% faster)")
	check(clear_of("talents_rare")/clear_of("talents_full") > 1.3,"the legendary mechanisms cut the crowd clear by >30%% vs the rare build")
	# --- no runaway ----------------------------------------------------------------------------
	for build in BUILDS:
		var clear = float(data[build].get("crowd",{}).get("clear_seconds",-1.0))
		check(clear > 0.0 and clear < 60.0,"%s crowd clear is finite and bounded (%.2fs)"%[build,clear])
	check(dps_of("both_full","boss") < dps_of("baseline","boss")*12.0,"the strongest account stays inside a 12x envelope (no exponential growth)")
	# --- measurement-input integrity (stale-evidence guard) -------------------------------------
	verify_manifest()
	print("B13_STRENGTH_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: get_tree().quit(0)

## The manifest must name exactly the required measurement set, every listed file must
## still exist, and every LF-normalised sha256 must match the file at this head. Any
## drift between the frozen evidence and the code that produced it fails here.
func verify_manifest():
	var manifest := load_manifest()
	check(not manifest.is_empty(),"the B13 measurement-input manifest exists and is not empty")
	if manifest.is_empty(): return
	var stored := {}
	for entry in manifest:
		var rel := str(entry.get("path",""))
		check(rel != "" and not stored.has(rel),"manifest entry carries a unique path: "+rel)
		stored[rel] = str(entry.get("sha256",""))
	for required in REQUIRED_MEASUREMENT_INPUTS:
		check(stored.has(required),"manifest covers the required measurement input "+required)
	for rel in stored:
		var digest := sha256_lf("res://"+rel)
		check(digest != "MISSING","measured input still exists on disk: "+rel)
		check(digest == stored[rel],"manifest sha256 matches the current file: "+rel+
			((" (now "+digest.substr(0,12)+"…)") if digest != "MISSING" else " (file missing)"))
	var covered: Array = stored.keys()
	covered.sort()
	var expected: Array = REQUIRED_MEASUREMENT_INPUTS.duplicate()
	expected.sort()
	var missing: Array = expected.filter(func(p): return not covered.has(p))
	var extra: Array = covered.filter(func(p): return not expected.has(p))
	check(missing.is_empty() and extra.is_empty(),"manifest covers exactly the required measurement set (no extras, no gaps)"+
		(("; missing: "+str(missing)) if not missing.is_empty() else (("; extra: "+str(extra)) if not extra.is_empty() else "")))
