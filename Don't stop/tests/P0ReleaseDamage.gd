extends "res://tests/M8Runtime.gd"

## Product-path damage contract. This deliberately does not use Smoke's scripted
## combat driver: it calls the live Hero damage entry point with the same state
## a normal round uses, then checks PlayerData.player_hp rather than a callback.
func _ready():
	await boot()
	dismiss()
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var explicit_e2e := "--e2e" in args
	check(Demo.is_e2e_mode() == explicit_e2e,"E2E immunity gate requires the exact --e2e argument")

	# test_mode, trial and a directly selected stage are not defence rules.
	Demo.test_mode = true
	Demo.trial = true
	Demo.selected_stage = 7
	Demo.talents = {}
	Demo.owned_global_upgrades = []
	Demo.talent_cooldowns = {}
	LevelServer.state = "COMBAT"
	get_tree().paused = false
	Utils.player.is_dead = false
	PlayerData.player_hp_max = 5
	PlayerData.player_hp = 5
	var hp_before: float = PlayerData.player_hp
	Utils.player.onHit(1.0,null,1.0,"p0-release-first")
	if explicit_e2e:
		check(PlayerData.player_hp == hp_before,"explicit E2E keeps the driver character alive")
		# Keep the E2E assertion meaningful after the first call: all effective
		# damage sources remain gated, while no gameplay state was edited.
		Utils.player.onHit(1.0,null,1.0,"p0-release-repeat")
		check(PlayerData.player_hp == hp_before,"E2E immunity is limited to the explicit driver flag")
	else:
		check(PlayerData.player_hp < hp_before,"test_mode/trial/direct-stage hit lowers real PlayerData HP")
		var after_first: float = PlayerData.player_hp
		Utils.player.onHit(1.0,null,1.0,"p0-release-second")
		check(PlayerData.player_hp < after_first,"repeated effective hits cannot keep HP permanently full")

		# A normal run with no defensive reward or talent must still take damage.
		Demo.test_mode = false
		Demo.trial = false
		Demo.talents = {}
		Demo.owned_global_upgrades = []
		Demo.talent_cooldowns = {}
		PlayerData.player_hp = PlayerData.player_hp_max
		hp_before = PlayerData.player_hp
		Utils.player.onHit(1.0,null,1.0,"p0-no-defence")
		check(PlayerData.player_hp < hp_before,"no defence reward/talent lowers the real HP value")

		# T19 consumes one hit, then real cooldown time must let a later hit through.
		Demo.talents = {"T19":1}
		Demo.talent_cooldowns = {}
		PlayerData.player_hp = PlayerData.player_hp_max
		hp_before = PlayerData.player_hp
		Utils.player.onHit(1.0,null,1.0,"p0-t19-first")
		check(PlayerData.player_hp == hp_before and Demo.cooldown("T19") > 0,"T19 blocks exactly the first effective hit")
		await wait(2.2)
		Utils.player.onHit(1.0,null,1.0,"p0-t19-cooldown")
		check(PlayerData.player_hp < hp_before,"T19 cooldown allows a later effective hit to lower HP")

	get_tree().paused = false
	print("P0_RELEASE_DAMAGE checks=",checks," failures=",failures," e2e=",explicit_e2e)
	get_tree().quit.call_deferred(1 if failures else 0)
