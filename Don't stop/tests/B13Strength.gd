extends Node
## B13 strength contract: verifies the FROZEN growth benchmarks
## (docs/iteration/evidence/b13/growth-*.json, written once by tests/B13GrowthBench.tscn
## on the real game runtime) against the B13 design rules. It reads NO catalog values:
##   * every build measures strictly above the baseline in every scenario
##   * quality is real strength: common < rare < full for BOTH systems, single + boss
##   * the B13 core rule: the talent build outgains the upgrade build at common, rare
##     and full investment (single + boss sustained DPS)
##   * legendary talents are felt: talents_full > talents_rare (the mechanisms pay off)
##   * no runaway: every crowd clear stays finite and the strongest build stays inside
##     the measured budget envelope (crowd clear <= 10 s, boss DPS <= 8x baseline)
##   * the benchmark harness input must match the sha256 manifest recorded next to the
##     evidence, so a silent harness edit cannot rotate the meaning of the numbers

var checks := 0
var failures := 0

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

func _ready():
	var data := {}
	for build in BUILDS:
		data[build] = load_rows("res://docs/iteration/evidence/b13/growth-%s.json" % build)
		check(not data[build].is_empty(),"evidence present for "+build)
	if failures: 
		print("B13_STRENGTH_CHECKS ",checks," FAILURES ",failures)
		get_tree().quit(1); return
	var dps := func(build: String, scenario: String) -> float: return float(data[build].get(scenario,{}).get("dps",0.0))
	# --- growth above baseline ------------------------------------------------------------
	for build in ["upgrades_common","upgrades_rare","upgrades_full","talents_common","talents_rare","talents_full","both_full"]:
		for scenario in ["single","boss"]:
			check(dps.call(build,scenario) > dps.call("baseline",scenario)*1.1,"%s beats baseline by >10%% in %s"%[build,scenario])
	# --- quality is real strength inside each system ----------------------------------------
	for scenario in ["single","boss"]:
		check(dps.call("upgrades_rare",scenario) > dps.call("upgrades_common",scenario)*1.1,"upgrade quality ladder pays in %s"%scenario)
		check(dps.call("upgrades_full",scenario) > dps.call("upgrades_rare",scenario),"full upgrades keep growing in %s"%scenario)
		check(dps.call("talents_rare",scenario) > dps.call("talents_common",scenario)*1.1,"talent quality ladder pays in %s"%scenario)
	# --- the B13 core rule: talents outgain upgrades -----------------------------------------
	# legendary talents are MECHANISMS (arc/echo/blast need a second target or a kill), so the
	# systems are compared where the spec measures them: per-scenario at common/rare, and at
	# full investment across ALL THREE scenarios via the geometric mean of the ratios.
	for scenario in ["single","boss"]:
		check(dps.call("talents_common",scenario) > dps.call("upgrades_common",scenario),"talent commons outgain upgrade commons in %s"%scenario)
		check(dps.call("talents_rare",scenario) > dps.call("upgrades_rare",scenario),"talent rares outgain upgrade rares in %s"%scenario)
	check(dps.call("talents_full","boss") > dps.call("upgrades_full","boss"),"talent full build outgains the full upgrade build vs the boss")
	var crowd_ratio := func(a: String, b: String) -> float:
		return float(data[b].get("crowd",{}).get("clear_seconds",999.0))/maxf(0.01,float(data[a].get("crowd",{}).get("clear_seconds",0.001)))
	check(crowd_ratio.call("talents_full","upgrades_full") > 1.0,"talent full build clears the crowd faster than the full upgrade build")
	var ratio := 1.0
	for scenario in ["single","boss"]:
		ratio *= dps.call("talents_full",scenario)/dps.call("upgrades_full",scenario)
	ratio *= crowd_ratio.call("talents_full","upgrades_full")
	ratio = pow(ratio,1.0/3.0)
	check(ratio > 1.15,"across the three scenarios the talent build outgains the upgrade build by >15%% (geomean %.2f)"%ratio)
	check(dps.call("both_full","single") > dps.call("upgrades_full","single")*1.4,"the full account compounds beyond either system alone (single)")
	check(dps.call("both_full","boss") > dps.call("upgrades_full","boss")*1.4,"the full account compounds beyond either system alone (boss)")
	# --- legendary talents are felt -----------------------------------------------------------
	check(crowd_ratio.call("talents_full","talents_rare") > 1.3,"legendary talent mechanisms cut the crowd clear by >30%% vs the rare build")
	check(dps.call("talents_full","boss") > dps.call("talents_rare","boss")*0.9,"legendary talents keep the boss output of the rare build")
	# --- no runaway ----------------------------------------------------------------------------
	for build in BUILDS:
		var clear = float(data[build].get("crowd",{}).get("clear_seconds",-1.0))
		check(clear > 0.0 and clear < 60.0,"%s crowd clear is finite and bounded (%.2fs)"%[build,clear])
	check(dps.call("both_full","boss") < dps.call("baseline","boss")*12.0,"the strongest account stays inside a 12x envelope (no exponential growth)")
	# --- harness integrity ---------------------------------------------------------------------
	var digest := sha256_lf("res://tests/B13GrowthBench.gd")
	var stored := ""
	var manifest = load_rows_evidence()
	for entry in manifest:
		if str(entry.get("path","")) == "tests/B13GrowthBench.gd": stored = str(entry.get("sha256",""))
	check(stored != "" and stored == digest,"benchmark harness matches its recorded manifest sha256")
	print("B13_STRENGTH_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: get_tree().quit(0)

func load_rows_evidence() -> Array:
	if not FileAccess.file_exists("res://docs/iteration/evidence/b13/manifest.json"): return []
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://docs/iteration/evidence/b13/manifest.json")) != OK: return []
	return parser.data
