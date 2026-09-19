extends "res://tests/M8Runtime.gd"

# Explicit UI-driver observation, not a physical-input latency measurement.
# The same scene runs against the unchanged baseline and current presentation.
var samples: Array = []
var cycles: Array = []
var peak_nodes := 0
var peak_objects := 0
func sample_call(action: Callable, label: String):
	var start = Time.get_ticks_usec()
	action.call()
	var elapsed = Time.get_ticks_usec()-start
	samples.append({"action":label,"call_ms":elapsed/1000.0})
	peak_nodes = maxi(peak_nodes,get_tree().get_node_count())
	peak_objects = maxi(peak_objects,int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	await get_tree().process_frame
	await get_tree().process_frame

func _ready():
	await boot()
	configure(124,false)
	var output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty(): get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var ids = Utils.weapon_list.keys()
	ids.sort()
	for cycle in 10:
		Demo.open_panel()
		await wait(0.1)
		var panel = Demo.ui
		for id in ids:
			panel.search_text = str(id)
			panel.selection = str(id)
			await sample_call(panel.render,"search-"+str(id))
			check(panel.detail_actions.has(str(id)),"search retains weapon "+str(id)+" cycle "+str(cycle))
		panel.search_text = ""
		for tab in ["weapon","attachment","supply","talent","stage"]:
			await sample_call(func(): panel.switch_tab(tab),"tab-"+tab)
		dismiss()
		await wait(0.15)
		cycles.append({"cycle":cycle,"closed_nodes":get_tree().get_node_count(),
			"closed_objects":Performance.get_monitor(Performance.OBJECT_COUNT),
			"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)})
	check(cycles[-1].closed_nodes <= cycles[1].closed_nodes+2,"Camp nodes converge after warmup")
	check(cycles[-1].orphans <= cycles[1].orphans,"closed Camp has no growing orphan count")
	var file = FileAccess.open(output+"/metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"Godot UI-driver synchronous call cost; excludes physical input and GPU frame completion", "samples":samples,"cycles":cycles,"peak_nodes":peak_nodes,"peak_objects":peak_objects},"\t")); file.close()
	# The observer itself retained 290 dictionaries above. Release those before
	# reporting retained memory, so its growing sample array is not called a UI leak.
	samples.clear(); cycles.clear()
	await wait(0.2)
	var cleanup = {"closed_nodes":get_tree().get_node_count(),"closed_objects":Performance.get_monitor(Performance.OBJECT_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"observer_samples_released":true}
	file = FileAccess.open(output+"/cleanup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(cleanup,"\t")); file.close()
	print("PRESENTATION_CAMP_PRESSURE checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
