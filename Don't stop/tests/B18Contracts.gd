extends "res://tests/M8Runtime.gd"

const SHOT = preload("res://game/monster/EnemyShot.gd")
const VARIANTS = preload("res://game/config/B18Variants.gd")

func pellet(point, speed, rebounds = 0):
	var p = SHOT.new(); p.position = point; p.velocity = speed; p.bounces_left = rebounds
	p.damage = 0.5
	play_view.add_child(p); p.set_physics_process(false)
	return p

func _ready():
	await boot(); configure(0)
	for pair in [[31,2.0],[35,3.6],[39,8.0]]:
		LevelServer.return_to_camp(); dismiss(); await wait(0.1)
		LevelServer.town.depart(pair[0],true); LevelServer.timerStop()
		# Isolate the manual variant fixture from the real arrival allocator.
		VARIANTS.generation = LevelServer.epoch
		VARIANTS.arrivals = 0
		VARIANTS.enchanted_arrivals = 999999
		VARIANTS.tier_two_arrivals = 0
		for n in get_tree().get_nodes_in_group("monsters"): n.queue_free()
		await wait(0.1)
		for kind in [0,1,2,3]:
			var point = LevelServer.town.spawn_point(M5Content.radius_for("E01")*2.2)
			check(point.is_finite(),"large legal spawn "+str(pair[0]))
			if not point.is_finite(): continue
			var actor = M5Content.spawn("E01",LevelServer.town.monster_root,point)
			check(actor != null,"real factory instance")
			if actor == null: continue
			VARIANTS.apply(actor,kind)
			var expected = M5Content.giant_final_hp(pair[0]) if kind == 3 else pair[1]*[1,2,4][kind]
			check(is_equal_approx(actor.HP,expected),"independent final HP stage %d variant %d actual=%.2f expected=%.2f"%[pair[0],kind,actor.HP,expected])
			VARIANTS.apply(actor,kind)
			check(is_equal_approx(actor.HP,expected),"apply twice does not multiply twice")
			check(not actor.is_elite,"numerical variant does not enable elite AI")
			if kind > 0: check(not M5Content.can_promote(actor),"variant excluded from elite promotion")
			if kind == 3:
				check(actor.get_node("CollisionShape2D").scale==Vector2.ONE*2.2 and actor.scale==Vector2.ONE,"giant scales real collider without root scale")
			else:
				PlayerData.player_hp = PlayerData.player_hp_max
				var hp_before = PlayerData.player_hp
				Utils.player.contact_immunity = 0
				Utils.player.onHit(1.0,actor,0,"shot:test")
				check(is_equal_approx(hp_before-PlayerData.player_hp,[1,2,4][kind]*DemoConfig.NORMAL_INCOMING),"actual variant damage once")
			actor.queue_free(); await wait(0.02)
	# Dedicated real wall, in an isolated region of the same physics world.
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	await wait(0.05)
	var wall = StaticBody2D.new(); wall.collision_layer = 2147483648; wall.collision_mask = 0
	var shape = CollisionShape2D.new(); shape.shape = RectangleShape2D.new(); shape.shape.size = Vector2(10,200)
	wall.add_child(shape); wall.position = Vector2(10100,10000); play_view.add_child(wall)
	Utils.player.set_physics_process(false); Utils.player.set_process(false)
	await get_tree().physics_frame; await get_tree().physics_frame
	Utils.player.global_position = Vector2(10050,10000); PlayerData.player_hp = 100
	var before = PlayerData.player_hp
	var p = pellet(Vector2(10000,10000),Vector2(1000,0))
	p._physics_process(0.2)
	check(p.is_queued_for_deletion() and PlayerData.player_hp < before,"high delta hits player before later wall")
	await wait(0.03)
	Utils.player.global_position = Vector2(10150,10000); before = PlayerData.player_hp
	p = pellet(Vector2(10000,10000),Vector2(1000,0))
	p._physics_process(0.2)
	check(p.is_queued_for_deletion() and PlayerData.player_hp==before,"wall blocks player behind it")
	await wait(0.03)
	Utils.player.global_position = Vector2(10000,10200)
	p = pellet(Vector2(10000,10000),Vector2(1000,0),1)
	p._physics_process(0.15)
	check(not p.is_queued_for_deletion() and p.velocity.x < 0 and p.bounces_done==1,"real wall normal reflects")
	check(p.position.x < 10080,"reflection consumes remaining displacement")
	p.queue_free(); await wait(0.03)
	Utils.player.global_position = Vector2(10070,10000)
	p = pellet(Vector2(10000,10000),Vector2(300,0),1)
	p.set_process(false)
	B11Probe.enabled = true
	var mirrors_before = B11Probe.shot_fog_mirrors
	p._physics_process(0.01); p._physics_process(0.01)
	check(is_equal_approx(p.life,0.02) and p.position.x > 10005,"all physics substeps advance lifetime and displacement")
	check(p._ink_dirty and B11Probe.shot_fog_mirrors == mirrors_before,"physics substeps defer only drawing submissions")
	check(p._fog_position.x > 10002 and p._fog_position.x < p.position.x,"latest original pre-sweep fog position retained")
	p._process(0.0)
	check(not p._ink_dirty and B11Probe.shot_fog_mirrors == mirrors_before+1,"one display update submits latest necessary warning")
	p._process(0.0)
	check(B11Probe.shot_fog_mirrors == mirrors_before+1,"no duplicate warning without a new physics step")
	B11Probe.enabled = false
	LevelServer.epoch += 1; p._physics_process(0.01)
	check(p.is_queued_for_deletion(),"epoch clears reflected shot")
	wall.queue_free(); await wait(0.05)
	check(SHOT.live_count==0,"all collision probes drained")
	print("B18_CONTRACTS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
