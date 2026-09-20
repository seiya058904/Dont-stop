extends "res://tests/M8Runtime.gd"
const LAYER = preload("res://game/monster/B19EnchantmentLayer.gd")
const SHOTS = preload("res://game/monster/EnemyShot.gd")
const VARIANTS = preload("res://game/config/B18Variants.gd")

func _ready():
	await boot(); configure(116,true)
	for cycle in 2:
		LevelServer.return_to_camp(); dismiss(); await wait(0.1)
		LevelServer.town.depart(39,true); LevelServer.timerStop()
		for actor in get_tree().get_nodes_in_group("monsters"): actor.queue_free()
		await wait(0.05)
		# Enough ordinary bodies to admit a real E14 through the production special budget.
		VARIANTS.generation = -1
		var targets: Array = []
		for i in 12:
			var point = LevelServer.town.spawn_point(M5Content.radius_for("E01"))
			if point.is_finite(): targets.append(M5Content.spawn("E01",LevelServer.town.monster_root,point))
		if cycle == 0:
			var before_usec := 0
			var after_usec := 0
			var same := true
			for i in 80:
				var center = Utils.player.global_position+Vector2((i%8)*7-28,(i/8)*5-25)
				var started = Time.get_ticks_usec()
				var old = reference_polygon(center,100.0)
				before_usec += Time.get_ticks_usec()-started
				started = Time.get_ticks_usec()
				var current = CombatFootprint.polygon(center,100.0)
				after_usec += Time.get_ticks_usec()-started
				same = same and old == current
			check(same,"all wall-clipped footprint vertices identical across 80 probes")
			print("B191_FOOTPRINT ",JSON.stringify({"rays":80*64,"before_usec":before_usec,"after_usec":after_usec}))
		var target = targets[0]
		var tier = int(target.get_meta("enchantment",0))
		check(is_equal_approx(target.HP,8.0*[1,2,4][tier]),"factory applies independent stage39 final HP once")
		var hp = target.HP
		VARIANTS.apply(target,tier)
		check(target.HP==hp,"second enchantment application is idempotent")
		check(float(target.anim.material.get_shader_parameter("enchantment_tier"))==tier,"enchantment is bound to existing body material")
		var peer = targets[1]
		peer.set_enchantment_visual(tier,target.enchantment_phase)
		check(peer.anim.material == target.anim.material,"identical body states share immutable material")
		target.flash_time = 0.08; target._process(0.01)
		check(target.anim.material != peer.anim.material,"one actor hit does not flash its peer")
		check(float(peer.anim.material.get_shader_parameter("flash"))==0.0,"shared normal material stays unchanged")
		target.flash_time = 0; target._process(0.01)
		check(peer.anim.material == target.anim.material,"flash completion reuses original material")
		var labels_before = preload("res://ui/widgets/HitLabel.gd").live_count
		var label_node = Utils.hitlabel.instantiate(); target.add_child(label_node)
		check(preload("res://ui/widgets/HitLabel.gd").live_count==labels_before+1,"label registration increments once")
		target.remove_child(label_node); label_node.free()
		check(preload("res://ui/widgets/HitLabel.gd").live_count==labels_before,"label removal releases capacity synchronously")
		var layer = LevelServer.town.monster_root.get_node_or_null("B19EnchantmentLayer")
		layer._process(0.016)
		check(layer.last_combat and layer.epoch==LevelServer.epoch,"new epoch visible on first display update")
		var animation = layer.animation_frame
		target.global_position += Vector2(4,7); target.HP -= 1
		layer._process(0.001)
		check(layer.animation_frame==animation,"position and HP update do not advance quantized animation")
		var snapshot = Combat._monsters_for_frame()
		check(snapshot.is_read_only(),"monster snapshot cannot be sorted by a caller")
		var reward = BaseReward.new(); reward.id = 999999
		Utils.player.reward_root.add_child(reward)
		check(Combat._rewards_for_frame().has(reward),"same tick reward addition invalidates cache")
		Utils.player.reward_root.remove_child(reward)
		check(not Combat._rewards_for_frame().has(reward),"same tick reward removal invalidates cache")
		reward.free()
		var point = LevelServer.town.spawn_point(M5Content.radius_for("E14"))
		var elite = M5Content.spawn("E14",LevelServer.town.monster_root,point)
		check(elite.get_meta("content_id")=="E14","production factory admits requested E14")
		M5Content.promote_elite(elite,"cross_beam")
		var stream = elite.get_node_or_null("ContinuousBarrage")
		check(is_instance_valid(stream),"production elite promotion attaches continuous source")
		if is_instance_valid(stream):
			elite.set_physics_process(false); elite.set_process(false); stream.set_physics_process(false)
			elite.phase = "move"
			elite.global_position += Vector2(20,10)
			stream._physics_process(stream.telegraph+0.01)
			check(elite.actions.get("continuous_barrage_emitted",0)==4,"real stream emits complete four-shot wave")
			var shots = get_tree().get_nodes_in_group("enemy_projectiles")
			check(shots.size()>=4 and SHOTS.live_count==shots.size(),"group and live projectile count agree")
			var elapsed = stream.elapsed
			elite.phase = "pause"; stream._physics_process(10.0)
			check(stream.elapsed==elapsed,"phase safety window freezes source clock")
			elite.phase = "move"; stream._physics_process(0.01)
			check(elite.actions.get("continuous_barrage_emitted",0)==4,"resume never catches up accumulated waves")
			elite.is_die = true; stream._physics_process(0.01)
			check(stream.is_queued_for_deletion(),"dead owner retires source")
		var contact = targets[2]
		contact.set_physics_process(false)
		contact.global_position = Utils.player.global_position+Vector2(-1,8)
		await wait(0.08)
		var sensed = contact.get_node("Area2D").get_overlapping_bodies()
		check(sensed.has(Utils.player),"narrow contact mask still senses the real player")
		check(sensed.all(func(body): return body is Player),"contact sensor excludes unrelated crowd and walls")
		check(contact.is_atk,"real player entry starts authored melee attack")
		var removed_actor = targets[-1]
		removed_actor.tree_exiting.connect(func(): Combat._monsters_for_frame())
		removed_actor.get_parent().remove_child(removed_actor)
		check(not Combat._monsters_for_frame().has(removed_actor),"post-exit invalidation survives reentrant exiting callback")
		removed_actor.free()
		LevelServer.return_to_camp(); dismiss(); await wait(0.15)
		check(SHOTS.live_count==0,"cycle %d projectile registry drains"%cycle)
		check(get_tree().get_nodes_in_group("monsters").is_empty(),"cycle %d actor registry drains"%cycle)
		print("B191_LIFECYCLE ",JSON.stringify({"cycle":cycle,"shots":SHOTS.live_count,"monsters":get_tree().get_nodes_in_group("monsters").size(),"nodes":get_tree().get_node_count(),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}))
	print("B191_RUNTIME checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

func reference_polygon(center: Vector2, radius: float, direction = Vector2.RIGHT, half_angle = PI) -> PackedVector2Array:
	var result = PackedVector2Array()
	if half_angle < PI: result.append(center)
	var segments = maxi(16,ceili(64*half_angle/PI))
	for i in range(segments+1 if half_angle < PI else segments):
		var endpoint = center+direction.rotated(lerpf(-half_angle,half_angle,float(i)/segments))*radius
		var query = PhysicsRayQueryParameters2D.create(center,endpoint,2147483649)
		if Combat.exclusions_dirty: Combat._refresh_exclusions()
		query.exclude = Combat.actor_exclusions
		var hit = Utils.player.get_world_2d().direct_space_state.intersect_ray(query)
		result.append(hit.get("position",endpoint))
	return result
