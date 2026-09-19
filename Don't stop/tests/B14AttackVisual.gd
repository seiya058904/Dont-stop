extends "res://tests/B8Runtime.gd"

var output=""
var viewed={}
var current_label=""

# Observation only: the normal movement driver dodges, but does not shoot its subject.
func fire_at(point: Vector2, _delta: float):
	Utils.aim_override=get_viewport().get_canvas_transform()*point

func _ready():
	await boot();configure(115)
	var tag="before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):tag=arg.substr(6)
	output="res://evidence/visual-upgrade-20260919/b14-attack-"+tag
	DirAccess.make_dir_recursive_absolute(output)
	if not rendering():push_error("B14 attack visual requires real rendering");get_tree().quit(2);return
	var log_rows=[]
	for role in ["B04-1","B04-2","B04-3","E14","E13","E04","E06","E07","E15"]:
		stop();dismiss();LevelServer.return_to_camp();await clean()
		LevelServer.state="CAMP"
		check(LevelServer.town.depart(40,true),"visual fixture enters real Stage40")
		LevelServer.timer.stop()
		var subject=instance_from_id(LevelServer.boss_instance)
		if role.begins_with("B04"):
			var phase_number=int(role.right(1))
			subject.HP=subject.max_hp*([1.0,0.65,0.30][phase_number-1])
		else:
			subject.queue_free();await wait(0.1)
			subject=M5Content.spawn(role,LevelServer.town.monster_root,LevelServer.town.spawn_near(Utils.player.global_position,100,140,M5Content.radius_for(role)))
			check(subject!=null,"real enemy spawned "+role)
			if subject==null:continue
		await visual_ready(Vector2i(410,230));recenter()
		PlayerData.player_hp_max=100000;PlayerData.player_hp=100000
		moving=true;target_boss=role.begins_with("B04");driving=true
		var start=Time.get_ticks_msec();var next_sample=0
		while Time.get_ticks_msec()-start<(12000 if role.begins_with("B04") else 8000) and is_instance_valid(subject) and not subject.is_die:
			await wait(0.05);recenter()
			PlayerData.player_hp=100000
			if Time.get_ticks_msec()<next_sample:continue
			next_sample=Time.get_ticks_msec()+100
			var kind=str(subject.get("attack_kind")) if subject.get("attack_kind")!=null else role
			var key=role+"-"+subject.phase+"-"+kind+("-locked" if subject.lock_frozen else "-tracking")
			for ultimate in get_tree().get_nodes_in_group("boss_ultimate"):
				key=role+"-ultimate-"+("active" if ultimate.activated else ("late-warning" if ultimate.elapsed>ultimate.warning*0.65 else "early-warning"))
			if viewed.has(key):continue
			viewed[key]=true
			await settle_render()
			play_view.get_texture().get_image().save_png(output+"/"+key+".png")
			log_rows.append({"key":key,"seconds":(Time.get_ticks_msec()-start)/1000.0,"role":role,"observer":"scripted phase HP setup, invulnerable moving observer, real AI/timing/render; not clear or performance proof"})
		stop()
	var file=FileAccess.open(output+"/index.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(log_rows,"\t"));file.close()
	print("B14_ATTACK_VISUAL images=",log_rows.size()," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
