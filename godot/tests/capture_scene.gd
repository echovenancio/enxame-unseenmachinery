extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var options = {}
	for arg in OS.get_cmdline_user_args():
		var pair = arg.trim_prefix("--").split("=",true,1)
		if pair.size()==2: options[pair[0]] = pair[1]
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	await process_frame
	scene.fields.ants.value = int(options.get("ants","12000"))
	scene.fields.scenario.selected = int(options.get("scenario","2"))
	scene.prepare_round()
	scene.speed = float(options.get("speed","1"))
	scene.arena.camera_mode = int(options.get("camera","0"))
	scene.toolbar.get_child(3).selected = scene.arena.camera_mode
	if options.get("controls","0")=="1": scene._toggle_controls()
	if options.get("running","0")=="1": scene.start_round()
	for frame in range(int(options.get("frames","48"))): await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(options.get("output","user://enxame-preview.png"))
	print("CAPTURE_METRICS ",JSON.stringify({"population":scene.sim.population,"agents":scene.sim.agent_count,"details":scene.arena.detail_ant_count,"density":scene.arena.density_population,"fps":Engine.get_frames_per_second(),"viewport":str(root.size),"toolbar":str(scene.toolbar.get_rect())}))
	quit()
